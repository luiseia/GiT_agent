# 审计判决 — P3_FINAL

## 结论: CONDITIONAL

**条件: P3 的 BUG-8/10 修复已正确实现且产生了可测量的正面效果，但 avg_P (0.122) 距红线 (0.20) 仍有巨大差距，且 car_R 持续下降。Loss 调优已接近天花板，P4 必须转向架构层面改动 (DINOv3 中间层特征提取) 或标签质量改进，否则继续在 loss/config 上调参将是无效劳动。**

---

## 第 1 部分: P3 最终判定

### BUG-8 修复核实: CONFIRMED

代码核实通过。Focal 和 CE 双路径均已添加背景 cls loss:

```python
# git_occ_head.py:L896-899 (Focal)
bg_cls_mask = (cls_target_rel == self.num_classes) & (cls_weight > 0)
if bg_cls_mask.any():
    loss_cls = loss_cls + self.bg_balance_weight * (c_focal[bg_cls_mask] * cls_weight[bg_cls_mask]).sum() / cls_weight[bg_cls_mask].sum().clamp_min(1.0)
    total_weight += self.bg_balance_weight

# git_occ_head.py:L968-971 (CE)
bg_cls_mask = (cls_target_rel == self.num_classes) & (cls_weight > 0)
if bg_cls_mask.any():
    loss_cls = loss_cls + self.bg_balance_weight * c_weighted[bg_cls_mask].sum() / cls_weight[bg_cls_mask].sum().clamp_min(1.0)
    total_weight += self.bg_balance_weight
```

模式与 marker loss 的 bg 处理 (L862-865) 完全一致。BUG-8 标记为 **FIXED**。

### BUG-10 修复核实: CONFIRMED

Warmup 已正确生效。训练日志证据:
- Iter 10: `base_lr=9.5e-7` (start_factor=0.001 * 5e-5 的前几步)
- Iter 100: `base_lr=9.96e-6`
- Iter 500: 预期达到 `base_lr=5e-5` (full LR)

Grad norm 在 warmup 期间保持健康 (1.0~8.0)，没有出现 P2 冷启动时的梯度爆炸。BUG-10 标记为 **FIXED (P3 config)**。

---

## 第 2 部分: P3 全 Checkpoint 追踪

| 指标 | @500 | @1000 | @1500 | @2000 | @2500 | @3000 | @3500 | @4000 | P2@6000 |
|------|------|-------|-------|-------|-------|-------|-------|-------|---------|
| car_R | 0.576 | 0.578 | 0.598 | **0.608** | 0.606 | 0.614 | 0.584 | 0.570 | 0.596 |
| car_P | 0.075 | **0.087** | 0.083 | 0.074 | 0.079 | 0.082 | 0.083 | 0.084 | 0.079 |
| truck_R | **0.374** | 0.390 | 0.382 | 0.152 | 0.336 | 0.326 | 0.311 | 0.302 | 0.290 |
| truck_P | 0.254 | 0.250 | 0.118 | 0.167 | 0.211 | **0.306** | 0.239 | 0.211 | 0.190 |
| bus_R | 0.697 | 0.576 | 0.680 | **0.737** | 0.667 | 0.636 | 0.682 | 0.712 | 0.623 |
| bus_P | 0.125 | 0.081 | 0.127 | 0.142 | **0.180** | 0.133 | 0.140 | 0.153 | 0.150 |
| trailer_R | 0.667 | 0.511 | **0.756** | 0.689 | 0.667 | 0.622 | 0.644 | 0.622 | 0.689 |
| trailer_P | 0.044 | 0.022 | 0.024 | 0.023 | 0.031 | **0.068** | 0.041 | 0.041 | 0.066 |
| bg_FA | 0.212 | 0.206 | 0.227 | 0.216 | 0.199 | 0.194 | 0.190 | **0.185** | 0.198 |
| off_cx | 0.085 | 0.055 | 0.066 | 0.071 | **0.052** | 0.059 | 0.054 | 0.052 | 0.068 |
| off_cy | 0.127 | 0.119 | 0.107 | 0.148 | 0.117 | 0.123 | 0.091 | **0.087** | 0.095 |
| off_th | 0.253 | 0.232 | 0.234 | **0.191** | 0.215 | 0.214 | 0.214 | 0.214 | 0.217 |

**加粗** 为该指标在 P3 训练中的最佳值。

---

## 第 3 部分: P3 vs P2 vs P1 综合对比

### BUG-8 修复的直接效果

1. **bg_FA 持续下降**: 0.212 (@500) → 0.185 (@4000)，对比 P2@6000 的 0.198，下降 6.6%。这是 BUG-8 修复的**最直接证据** — cls loss 现在正确惩罚背景预测错误，模型不再"疯狂预测有车"。

2. **bus_R 显著提升**: P3@4000=0.712 vs P2=0.623 (+14.3%)。BUG-8 修复前，背景 cls loss 完全缺失，背景样本的分类梯度为零，导致模型偏向把背景预测为前景。修复后，背景梯度恢复，模型对"确实有车"的判断更精准。

3. **truck_P 大幅提升**: P3@3000 达到 0.306 (vs P2=0.190, +61%)。这说明模型精度能力已大幅改善，但不稳定。

### BUG-10 修复的直接效果

1. **早期训练稳定性**: P3 首 500 步 grad_norm 范围 1.0~8.0，对比 P2 冷启动时 3.85~59.55 的剧烈波动，warmup 效果明显。

2. **offset_cx/cy 改善**: P3@4000 的 cx=0.052, cy=0.087 均优于 P2@6000 (cx=0.068, cy=0.095)。Warmup 避免了优化器初期的大幅震荡，使空间回归更精确。

### Config 调优效果 (非 BUG 修复)

LR schedule 变化 (milestones [2500, 3500]) 导致了明确的阶段性行为:
- @2500 后 LR 降至 5e-6: bg_FA 从 0.199 → 0.185 持续下降，说明低 LR 有助于精细调整
- 但 car_R 从 0.606 (@2500) → 0.570 (@4000) 持续恶化，说明低 LR 阶段出现了过拟合/遗忘

---

## 第 4 部分: P3 弱项分析

### 弱项 1: car_R 下降 (-4.4% vs P2)

**现象**: car_R 在 @2000 达到峰值 0.608 后持续下降至 0.570。

**根因**: car 是数据集中最大的类别 (8269 gt)。BUG-8 修复引入了 `bg_balance_weight=3.0` 的背景 cls loss，这对 car 的影响最大——因为 car 在训练样本中占比最高，大量 car 附近的 cell 从"无约束"变成了"有背景惩罚"。模型在背景判断上变好了 (bg_FA 下降)，但代价是部分正确的 car 预测被压制。

**本质**: car_R 下降和 bg_FA 下降是同一个机制的两面。bg_balance_weight=3.0 偏高，导致模型偏保守。

**建议**: 降低 bg_balance_weight 至 1.5~2.0 可能恢复 car_R，但会牺牲 bg_FA。更根本的解决方案是提升分类精度 (avg_P)，让模型不需要在 recall/precision 之间做权衡。

### 弱项 2: trailer_R/P 低迷

**现象**: trailer_R=0.622 (vs P2=0.689, -9.7%), trailer_P=0.041 (vs P2=0.066, -37.9%)。

**根因**: trailer 只有 90 个 GT (vs car 8269, truck 5165, bus 3096)。即使 `use_per_class_balance=True` 让每个类的 loss 权重相等，90 个样本的统计多样性极低。trailer 的几何特征 (长拖车) 与其他类差异最大，但样本量不足以学好。

**结构性问题**: 20x20 BEV grid 中 trailer 通常只占 1-2 个 cell，但其实际物理尺寸远大于 5m x 5m 的 cell，AABB 投影 (BUG-11 的前置问题) 导致大量 false positive cell 被标注为 trailer。

### 弱项 3: avg_P 远低于红线 (0.122 vs 0.20)

**这是最严重的问题**。详见第 6 部分。

---

## 第 5 部分: offset_th 未保持突破分析

**现象**: @2000 的 offset_th=0.191 (唯一达标 <=0.20 的时刻)，但 @2500 回升至 0.215 并稳定在 0.214。

**时间线分析**:
- @2000 处于 full LR (5e-5) 阶段
- @2500 是 milestone 切换点，LR 从 5e-5 骤降至 5e-6 (10x 下降)

**根因**: offset_th 的回归目标 (theta_group + theta_fine) 与分类目标 (marker + cls) 共享同一个 Transformer decoder。LR 骤降后:
1. 分类 loss (cls + marker) 的梯度绝对值远大于 theta 回归 loss
2. 在低 LR 下，模型优先收敛分类任务 (bg_FA 确实在持续下降)
3. theta 回归被挤出了有效梯度空间

**证据**: @2000 时 truck_R 暴跌至 0.152 (异常低)，说明模型在 @2000 附近经历了一次分类-回归的权衡翻转。theta 的突破是以分类能力暂时恶化为代价的。

**建议**: 如果要保持 theta 的突破，需要将 `reg_loss_weight` 从 1.0 提升至 1.5~2.0 以平衡分类和回归。但这可能重新恶化 avg_P。更合理的方式是采用分离的学习率或分离的 decoder head。

---

## 第 6 部分: avg_P 未达标根因分析

### avg_P 计算
```
avg_P = mean(car_P, truck_P, bus_P, trailer_P)
P3@4000: (0.084 + 0.211 + 0.153 + 0.041) / 4 = 0.122
P3@3000: (0.082 + 0.306 + 0.133 + 0.068) / 4 = 0.147  (P3 最佳)
红线: 0.20
```

### 结构性瓶颈分析

**瓶颈 1: car_P 和 trailer_P 拖累全局**

- car_P 从未超过 0.087 (全部 checkpoint)。car 占 GT 总量的 49.8% (8269/16620)，但 precision 极低。
- trailer_P 从未超过 0.068。样本量不足 (90 个 GT)。
- 要 avg_P >= 0.20，假设 truck_P=0.25, bus_P=0.15，则需要 car_P + trailer_P >= 0.40，即 car_P >= 0.35 (当前 0.084) 或同等水平。**这是当前架构完全不可能达到的**。

**瓶颈 2: 低 Precision 的根本原因 — 假阳性泛滥**

Precision = TP / (TP + FP)。car_P=0.084 意味着每 12 个 car 预测中只有 1 个是对的。

假阳性来源:
1. **AABB 标签污染**: generate_occ_flow_labels.py 使用轴对齐包围盒 (AABB) 分配 cell。旋转 45 度的车辆，AABB 面积约为实际面积的 2 倍，导致大量非车辆 cell 被标为车辆。模型学到了"在这些 cell 也应该预测车辆"，但评估时算 FP。
2. **3 slot per cell 的冗余**: 每个 cell 3 个 slot，大多数 cell 只有 0-1 个实际目标。空 slot 如果预测出车辆，直接计入 FP。
3. **score 阈值无效**: 评估时 `score_thr=0.0` (配置 L427)。模型 score 均值 0.97，没有区分度。模型无法表达"我不确定这个预测"，所有预测都以高置信度输出。

**瓶颈 3: 评估逻辑的 Precision 计算方式**

`occ_2d_box_eval.py` 中 Precision = TP / total_predictions。如果模型在 400 个 cell x 3 slot = 1200 个位置中，大量位置都输出非 bg 预测，分母会极大。**但这不是 BUG，而是模型确实在大量位置输出了假阳性。**

### 结论: avg_P 的瓶颈是系统性的

Loss 调参无法解决以下结构性问题:
1. AABB 标签污染 (需修 generate_occ_flow_labels.py)
2. Score 无区分度 (需架构改动: 添加 objectness head 或 sigmoid score)
3. DINOv3 只用 Conv2d 层 (语义不足以区分有车/无车)

**不修改架构或标签生成逻辑，avg_P 无法达到 0.20。**

---

## 第 7 部分: P4 方向建议

### 推荐优先级: 标签质量 > 架构改进 > Loss 调优

### 方案 1 (最高优先): 修复 AABB 标签污染

**目标**: 用旋转多边形替代 AABB 分配 cell，减少假阳性标签。

**改动**: `generate_occ_flow_labels.py:L507` 的 `_compute_valid_grid_ids`，从 `min_u, max_u, min_v, max_v` 改为使用 `shapely.geometry.Polygon` 判断 cell 中心是否在旋转框内。

**预估收益**: car_P 可能提升 50-100% (从 0.084 至 0.12-0.17)，因为旋转框的面积约为 AABB 的 50-70%。

**预估工作量**: 1-2 天。

**风险**: 低。标签生成是离线的，不影响模型结构。

### 方案 2 (高优先): DINOv3 中间层特征提取 (VERDICT_ARCH_REVIEW 方案 A)

**目标**: 使用 DINOv3 Layer 16 的特征替代 Conv2d PatchEmbed。

**预估收益**: 显著。中间层特征已包含物体类别信息，可大幅提升分类精度。

**预估工作量**: 2-3 天。

**风险**: 中。显存约增加 14GB (DINOv3 7B FP16)，4 卡 A6000 (48GB/卡) 可承受。

### 方案 3 (中优先): Score 区分度改进

**目标**: 让模型输出有意义的置信度分数，评估时可通过 score_thr 过滤低置信度预测。

**改动**: 在 OccHead 中添加独立的 objectness prediction (sigmoid)，替代当前的 softmax 概率作为 score。

**预估收益**: 中。如果 score 有区分度，score_thr=0.3 可过滤大量 FP，直接提升 Precision。

**预估工作量**: 2-3 天。

### BUG-11/13 是否需要修复

- **BUG-11 (类别顺序)**: **推荐修复**。风险极低 (改一行默认值)，但不修的话任何新 config 都是地雷。修复: `generate_occ_flow_labels.py:L77` 删除默认值，强制显式传入。
- **BUG-13 (slot_class bg clamp)**: **暂不修复**。影响仅在评估时，且 bg slot 被 marker=END 截断不参与计算。

### 推荐 P4 Config 参数 (基于 P3 数据)

如果继续 loss/config 调优 (不推荐作为主方向):
- `bg_balance_weight`: 降至 **2.0** (当前 3.0 偏高，压制 car_R)
- `reg_loss_weight`: 提升至 **1.5** (保护 theta 回归不被分类挤出)
- `use_focal_loss`: **True** (当前 False，Focal 可自动压制 easy negative)
- `focal_gamma`: **2.0** (标准值)
- `focal_alpha_cls`: **0.6** (降低前景权重，让背景也有更多贡献)
- 从 **P3@3000** 恢复 (avg_P=0.147，P3 最佳点)，而非 @4000
- `max_iters`: **3000** (P3 数据显示 2500-3000 是最佳区间)

---

## 第 8 部分: BUG 状态更新

| BUG | 审计前状态 | 审计后状态 | 备注 |
|-----|-----------|-----------|------|
| BUG-1 | FIXED | FIXED | — |
| BUG-2 | PARTIALLY_FIXED | **FIXED** | BUG-8 修复补全了 cls loss 的 bg 处理，BUG-2 现在完整修复 |
| BUG-3 | FIXED | FIXED | — |
| BUG-8 | UNPATCHED | **FIXED** | Focal + CE 双路径已添加 bg_cls_mask |
| BUG-9 | FIXED_P2_ONLY | FIXED_P2+P3 | plan_e/plan_f 已修，其他 config 仍为 0.5 |
| BUG-10 | UNPATCHED | **FIXED (P3 config)** | 500 步 linear warmup 已生效 |
| BUG-11 | UNPATCHED | UNPATCHED | 推荐 P4 修复 |
| BUG-12 | FIXED | FIXED | — |
| BUG-13 | LOW | LOW | 暂不修复 |

---

## 逻辑验证

- [x] BUG-8 修复梯度守恒: bg_cls_mask 使用 `cls_target_rel == self.num_classes`，与 logits 维度 `C_all = num_classes + 1` 对齐。bg 索引正确。
- [x] BUG-10 warmup 不干扰现有参数: `start_factor=0.001` 仅影响 LR，不改变 optimizer state。resume=False 确保从 P2@6000 权重冷加载但 LR 从低点爬升。
- [x] LR schedule 连续性: LinearLR(0→500) end=500 与 MultiStepLR begin=500 无缝衔接，无 LR 跳变。
- [x] 梯度范围健康: P3 训练全程 grad_norm 1.0~46.3 (偶发尖峰)，max_norm=10.0 有效裁剪极端值但不过度压制。

---

## 附加建议

1. **P3@3000 是更好的 P4 起点**: avg_P=0.147 (vs @4000 的 0.122)，truck_P=0.306 (vs 0.211)。@3000 之后的训练实际上是有害的。

2. **新增层全为 window attention 是瓶颈**: config L228 `new_more_layers=['win','win','win','win','win','win']`。建议至少将 Layer 14 和 17 改为 global attention，给 grid token 更多全局信息。

3. **数据增强缺失**: 当前 pipeline 无任何数据增强 (无 flip, rotation, color jitter)。323 张图训练 10000+ 步 (P2+P3)，过拟合是必然的。建议 P4 添加水平翻转 (需同步翻转 BEV 标签)。

4. **Effective batch=16 偏大**: 323 张图只有 ~20 iter/epoch，batch=16 意味着每 epoch 几乎遍历全部数据一次。对小数据集，减小 batch (如 8) 可能增加更新频率，改善泛化。
