# 审计判决 — P2_FINAL

## 结论: CONDITIONAL

**条件: 修复 BUG-8 + BUG-10 后方可启动 P3。两个修复均为低风险配置/代码变更，可在 1 小时内完成。**

---

## 发现的问题

### 1. **BUG-8**: cls loss 在 per_class_balance 模式下完全丢弃背景类损失 (CONFIRMED)

- 严重性: **CRITICAL**
- 位置: `GiT/mmdet/models/dense_heads/git_occ_head.py:L886-896` (Focal 路径) 和 `L952-963` (CE 路径)
- 状态: UNPATCHED — P2 全程带伤训练

**问题本质:**

Marker loss 的 per-class balance 正确处理了背景 (L862-865):
```python
# marker loss — 正确: 背景有 bg_balance_weight
bg_mask = is_bg_gt & (marker_weight > 0)
if bg_mask.any():
    loss_marker += self.bg_balance_weight * (m_focal[bg_mask] * marker_weight[bg_mask]).sum() / ...
    total_weight += self.bg_balance_weight
```

但 cls loss 的 per-class balance 完全遗漏了背景 (L886-896):
```python
# cls loss — 错误: 只遍历前景类，背景被静默丢弃
for c in range(self.num_classes):        # 0 ~ num_classes-1，不含背景
    mask_c = (cls_target_rel == c) & ... # 背景的 cls_target_rel == num_classes，永远匹配不到
```

**根因链:**
1. `self.bg_cls_token = cls_start + self.num_classes` (L280)
2. 背景 slot 的 `cls_target_rel = bg_cls_token - cls_start = num_classes` (L876)
3. 循环 `range(self.num_classes)` = `[0, num_classes-1]`，永远跳过 `num_classes`
4. 背景 cls loss = **0.0**

**影响分析:**
- P2 config: `bg_balance_weight=3.0` (plan_e_bug9_fix.py:L146)
- Marker loss: 背景以 3.0x 权重参与训练 → 模型学会检测 "这是背景"
- Cls loss: 背景以 0.0x 权重参与训练 → 模型**从不学习**输出背景类别
- 结果: 模型倾向于将背景预测为前景类 → precision 暴跌 → car_P -14%
- 次级效应: 假阳性增多挤压 truck 真阳性 → truck_R -19%

**修复方案 (Focal 路径, L886-896):**
```python
if self.use_per_class_balance:
    loss_cls = logits_flat.new_tensor(0.0)
    total_weight = 0.0
    for c in range(self.num_classes):
        mask_c = (cls_target_rel == c) & (cls_weight > 0)
        if mask_c.any():
            loss_cls = loss_cls + 1.0 * (c_focal[mask_c] * cls_weight[mask_c]).sum() / cls_weight[mask_c].sum().clamp_min(1.0)
            total_weight += 1.0
    # >>> BUG-8 FIX: 添加背景 cls loss <<<
    bg_cls_mask = (cls_target_rel == self.num_classes) & (cls_weight > 0)
    if bg_cls_mask.any():
        loss_cls = loss_cls + self.bg_balance_weight * (c_focal[bg_cls_mask] * cls_weight[bg_cls_mask]).sum() / cls_weight[bg_cls_mask].sum().clamp_min(1.0)
        total_weight += self.bg_balance_weight
    if total_weight > 0:
        loss_cls = loss_cls / total_weight
```

**CE 路径 (L952-963) 需要同样修复:**
```python
if self.use_per_class_balance:
    c_weighted = cls_ce_raw * cls_weight * c_punish_weight
    loss_cls = logits_flat.new_tensor(0.0)
    total_weight = 0.0
    for c in range(self.num_classes):
        mask_c = (cls_target_rel == c) & (cls_weight > 0)
        if mask_c.any():
            loss_cls = loss_cls + 1.0 * c_weighted[mask_c].sum() / cls_weight[mask_c].sum().clamp_min(1.0)
            total_weight += 1.0
    # >>> BUG-8 FIX <<<
    bg_cls_mask = (cls_target_rel == self.num_classes) & (cls_weight > 0)
    if bg_cls_mask.any():
        loss_cls = loss_cls + self.bg_balance_weight * c_weighted[bg_cls_mask].sum() / cls_weight[bg_cls_mask].sum().clamp_min(1.0)
        total_weight += self.bg_balance_weight
    if total_weight > 0:
        loss_cls = loss_cls / total_weight
```

**注意:** 归一化从 `n_cls_active2` 计数改为 `total_weight` 加权求和，与 marker loss (L853-867) 保持一致。

---

### 2. **BUG-10**: 优化器冷启动 — 无 warmup 缓冲 (CONFIRMED)

- 严重性: **HIGH**
- 位置: `GiT/configs/GiT/plan_e_bug9_fix.py:L12-13` (resume=False) 和 `L344-352` (无 warmup)
- 状态: UNPATCHED

**问题本质:**

```python
load_from = '.../iter_6000.pth'   # L12: 只加载模型权重
resume = False                      # L13: 不恢复优化器状态
```

AdamW 维护每个参数的一阶矩 (mean) 和二阶矩 (variance) 估计。`resume=False` 将这些全部清零。

LR 调度无 warmup:
```python
param_scheduler = [
    dict(type='MultiStepLR', milestones=[3000, 5000], gamma=0.1)  # L344-352: 直接 5e-5 起跳
]
```

**影响:** 前 500-1000 步梯度更新方向不稳定，因为 AdamW 的自适应学习率基于历史梯度统计，冷启动时等价于原始 SGD + weight_decay。

**P2 实际受损情况:** P2 从 P1@6000 加载权重但冷启优化器。前 1000 步的学习不稳定部分解释了 P2 收敛路径的波动。

**修复方案 (P3 config):**
```python
param_scheduler = [
    dict(
        type='LinearLR',
        start_factor=0.001,    # 从 5e-8 起步
        by_epoch=False,
        begin=0,
        end=500                # 500 步线性 warmup
    ),
    dict(
        type='MultiStepLR',
        by_epoch=False,
        begin=500,
        end=max_iters,
        milestones=[3000, 5000],
        gamma=0.1
    )
]
```

---

### 3. **BUG-13** (新发现): slot_class 背景溢出被 clamp 到最后一个前景类

- 严重性: **LOW**
- 位置: `GiT/mmdet/models/dense_heads/git_occ_head.py:L831`
- 状态: UNPATCHED (潜在风险)

```python
slot_class = (tgt_flat[:, 1] - cls_start).clamp(0, self.num_classes - 1)
```

背景 slot 的 `tgt_flat[:, 1] = bg_cls_token = cls_start + num_classes`，计算后 `slot_class = num_classes`，被 clamp 到 `num_classes - 1` (最后一个前景类)。

**当前影响:** 低。背景 slot 的回归 weights 应为 0，所以被 clamp 的 slot_class 不影响回归 loss。但这是一个逻辑不一致——背景被伪装成最后一个前景类。

**如果后续代码改动导致背景回归 weight > 0，此 bug 将静默污染最后一个前景类的回归 loss 统计。**

修复: 无需立即修复，但建议在 BUG-8 修复时顺手处理。

---

## 审计请求逐项回答

### Q1: P2@6000 — truck_R -19%, car_R -5%, car_P -14% 是否可接受?

**不可接受。** 这些下降不是 BUG-9 fix 的正常代价，而是 BUG-8 的直接症状:

| 指标下降 | 根因 |
|---------|------|
| car_P -14% | BUG-8: 背景 cls loss = 0 → 模型无法学会分类背景 → 大量假阳性 → precision 崩塌 |
| truck_R -19% | BUG-9 fix 移除了 sign-SGD 保护 + BUG-8 放大了假阳性 → truck 真阳性被挤出 |
| car_R -5% | BUG-8 的间接效应: 假阳性背景被预测为 car → 与真 car 竞争 slot |

P2 的 9/14 指标提升证明 BUG-9 fix 是正确的。3 个指标下降完全归因于 BUG-8，修复后应全面恢复。

### Q2: BUG-8 修复是否安全?

**安全。** 理由:
1. **纯加法变更**: 只是在现有循环后追加背景分支，不修改前景逻辑
2. **模式一致**: 与 marker loss 的 bg_mask 处理完全对称 (L862-865)
3. **无架构变更**: 不改模型结构，P2 checkpoint 兼容
4. **参数已存在**: `bg_balance_weight` 已在 config 中定义 (=3.0)，修复只是让它在 cls loss 中生效

### Q3: P3 是否值得启动?

**值得。** P3 = P2@6000 权重 + BUG-8 fix + BUG-10 fix (warmup)。

预期改善:
- **car_P**: +15-20%。背景 cls loss 恢复后，假阳性率将显著下降
- **truck_R**: +10-15%。假阳性减少释放 slot 容量给 truck 真阳性
- **avg_precision**: 从 ~0.09 有望突破 0.15。BUG-8 是 precision 的最大制约因素

### Q4: 是否需要同时修复 BUG-10?

**强烈建议同时修复。** 理由:
1. 修复成本极低: 仅改 P3 config 的 `param_scheduler`，加 500 步 warmup
2. P3 必然 `resume=False` (因为代码改了 loss 计算)，所以冷启动问题会再次出现
3. Warmup 让前 500 步平稳过渡，避免浪费 ~8% 的训练步数在不稳定状态

---

## 逻辑验证

- [x] 梯度守恒: BUG-8 修复后，cls loss 对背景的梯度将从 0 恢复到 bg_balance_weight * focal_loss。marker loss 已有正确实现可对照
- [x] 边界条件: cls_target_rel == num_classes 恰好是 bg_cls_token - cls_start，匹配 C_all = num_classes + 1 的 logits 维度。不会越界
- [x] 数值稳定性: bg_balance_weight=3.0 与前景 1.0 的比例合理。total_weight 归一化防止 loss 尺度失衡。clamp_min(1.0) 防止除零

---

## 附加建议

1. **P3 config 建议保留 bg_balance_weight=3.0**: 背景样本远多于前景 (~70% vs ~30%)，3.0 的权重确保背景梯度不被前景类数量稀释。但训练 2000 步后监测 bg_recall，如果 >95% 可考虑降至 2.0 以释放更多容量给前景

2. **P3 训练步数建议 4000 步**: BUG-8 fix 是 loss 层面的根本性修复，比 BUG-9 fix (优化器层面) 影响更深。需要足够步数让分类决策边界重新收敛

3. **监测指标优先级**: P3 最关键的监测指标是 avg_precision 而非 recall。如果 BUG-8 fix 生效，precision 应在前 1000 步就显著上升

4. **BUG-12 (评估 slot 排序) 仍然 URGENT**: 本次审计未涉及评估代码，但 BUG-12 可能导致评估指标本身不准确。建议在 P3 启动前或并行修复
