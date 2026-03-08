# 审计判决 — P5_MID

## 结论: CONDITIONAL

**条件: (1) LR milestone 问题已确认——milestones 为相对值，第一次 decay 在 iter 5000 而非 4000，第二次 decay 永不触发。建议接受当前运行至 6000 iter 结束 (仅一次 decay)，不中断。(2) avg_P=0.040 暴跌的根因是类别轮换振荡——DINOv3 Layer 16 特征的类别语义过强，在 per_class_balance 下导致 truck/bus/trailer 零和竞争。(3) P5b 是必要的，应从 P5 最佳 checkpoint 出发，纠正 milestones 并降低 per_class_balance 的振荡效应。**

---

## 第 1 部分: LR Milestone 问题 (紧急)

### MMEngine MultiStepLR 行为确认

代码追踪 (`mmengine.optim.scheduler.param_scheduler._ParamScheduler.step`):

```python
# _ParamScheduler.step():
if self.begin <= self._global_step < self.end:
    self.last_step += 1       # last_step 从 0 开始，在 [begin, end) 范围内递增
    values = self._get_value()

# MultiStepParamScheduler._get_value():
if self.last_step not in self.milestones:
    return [group[self.param_name] for group in ...]
return [group[self.param_name] * self.gamma ** self.milestones[self.last_step] ...]
```

**last_step 从 `begin` 时刻起从 0 计数。** milestones 中的值是与 `last_step` 比较的，即相对于 `begin` 的偏移量。

### P5 Config 实际 LR Schedule

Config: `begin=1000, milestones=[4000, 5500], gamma=0.1, max_iters=6000`

| 阶段 | Global Iter | last_step | LR |
|------|------------|-----------|-----|
| Warmup | 0-999 | N/A | 5e-8 → 5e-5 |
| Full LR | 1000-4999 | 0-3999 | 5e-5 |
| **Decay 1** | **5000** | **4000** | **5e-6** |
| Post-decay | 5001-5999 | 4001-4999 | 5e-6 |
| Decay 2 | 6500 | 5500 | **永不触发** (max_iters=6000) |

**预期 vs 实际:**
- 预期: decay @4000, @5500 → 实际: decay @5000, @6500
- 第一次 decay 晚了 1000 iter
- 第二次 decay 超出 max_iters，永不触发

### 建议: 方案 (a) — 接受仅一次 decay，继续运行至 6000

**理由:**
1. **不中断**: 训练已进行到 @4500+，中断重启的成本高且不保证更好
2. **一次 decay 足够**: P3/P4 也只有一次有效 decay (LR 从 5e-5 降到 5e-6)。P4 中第二次 decay (5e-6→5e-7) 效果微弱 (P4@3500→@4000 几乎无改善)
3. **P5b 可以纠正**: 从 P5 最佳 checkpoint 出发，用修正后的绝对 milestones 重新训练

**如果要在 P5b 纠正:**
```python
# 修正方案: milestones 改为相对于 begin 的值
# 要在 global iter 4000 decay: milestone = 4000 - begin = 3000
# 要在 global iter 5500 decay: milestone = 5500 - begin = 4500
param_scheduler = [
    dict(type='LinearLR', start_factor=0.001, by_epoch=False, begin=0, end=1000),
    dict(type='MultiStepLR', by_epoch=False, begin=1000, end=max_iters,
         milestones=[3000, 4500], gamma=0.1)   # 修正: 相对值
]
```

---

## 第 2 部分: P5 全局评估

### P5 关键指标轨迹分析

从审计请求数据:

| 指标 | P4@4000 | P5@3500 | P5@4000 | P5@4500 | 趋势 |
|------|---------|---------|---------|---------|------|
| car_R | 0.592 | **0.779** | 0.569 | 0.529 | 剧烈波动 |
| car_P | 0.081 | 0.093 | 0.090 | **0.091** | 小幅提升 |
| truck_R | 0.410 | **0.679** | 0.421 | 0.317 | 剧烈波动 |
| truck_P | 0.175 | 0.072 | 0.130 | 0.095 | 大幅下降 |
| bus_R | 0.752 | 0.120 | 0.315 | 0.058 | **崩溃** |
| bus_P | 0.129 | 0.024 | 0.037 | 0.024 | **崩溃** |
| trailer_R | 0.750 | 0.000 | 0.472 | 0.361 | **崩溃** |
| trailer_P | 0.044 | 0.000 | 0.006 | 0.005 | **崩溃** |
| bg_FA | 0.194 | 0.290 | 0.213 | **0.167** | 下降 (好) |
| offset_th | 0.207 | 0.197 | **0.142** | 0.226 | 突破后回退 |

### DINOv3 Layer 16 投影效果评价

**正面效果:**
1. **car_P 小幅提升**: 0.081→0.091 (+12%)。DINOv3 中间层的语义特征确实提高了 car 的分类精度。
2. **offset_th 突破性改善**: P5@4000 达到 0.142 (P4 最佳 0.200)。语义特征包含物体方向信息，显著提升了角度预测。
3. **bg_FA 创新低**: 0.167 (P4 最佳 0.176)。更强的特征让模型更好地区分有车/无车。

**负面效果:**
1. **bus/trailer 崩溃**: bus_R 从 0.752→0.058，trailer_R 从 0.750→0.361。这不是渐进恶化而是灾难性遗忘。
2. **avg_P 暴跌**: 从 P4 的 0.107 降至 0.040。truck_P/bus_P/trailer_P 全部崩溃。
3. **剧烈波动**: car_R 在 @3500 达 0.779 但 @4500 降至 0.529，这种 250 iter 内 ±0.25 的波动说明模型在类别间剧烈振荡。

---

## 第 3 部分: 类别轮换振荡根因分析

### 现象

P5 训练中类别指标呈现明显的**零和竞争**模式:
- @3500: car_R=0.779, truck_R=0.679 极高，但 bus_R=0.120, trailer_R=0.000 崩溃
- @4000: car/truck 回落，bus/trailer 部分恢复
- @4500: 全面恶化

**某些类别的 recall 提升，总是伴随其他类别的 recall 下降。** 这是典型的类别间梯度竞争。

### 根因: DINOv3 Layer 16 特征 + per_class_balance 的冲突

1. **DINOv3 Layer 16 的类别语义过强**: Conv2d PatchEmbed 只有纹理信息，类别区分度低。Layer 16 包含清晰的物体类别表征。模型现在能区分 car/truck/bus/trailer，但区分能力**不均衡** — car (8269 GT) 和 truck (5165 GT) 有大量样本支撑，bus (3096 GT) 和 trailer (90 GT) 样本不足。

2. **per_class_balance 放大了不均衡**: `use_per_class_balance=True` 使每个类的 loss 权重相等 (1.0)。但 trailer 只有 90 个 GT，其 loss 的统计噪声极大。某个 batch 中 trailer 的 loss 可能比 car 大 10 倍，导致梯度被 trailer 主导一个 batch，然后下个 batch 被 car 主导。

3. **Linear(4096, 768) 是瓶颈**: 4096→768 的压缩比 5.3:1。DINOv3 Layer 16 的 4096 维特征中，不同类别的语义分布在不同子空间。单层 Linear 必须在 768 维中同时编码所有类别信息，导致类别间互相干扰。当模型调整权重以改善 truck 时，bus 的子空间被破坏。

### 为什么 P1-P4 没有这个问题

P1-P4 使用 Conv2d PatchEmbed，特征不含类别语义。模型的类别判断完全依赖 decoder head 的权重。Head 的参数空间足够大 (768×224 词表)，类别间干扰小。

P5 改用 Layer 16 特征后，类别语义"前置"到了 backbone 输入，backbone 的所有 18 层 Transformer 都参与了类别判断。backbone 参数是共享的，修改任何参数都影响所有类别。

### BUG-17: per_class_balance 在极不均衡数据下的振荡问题

- 严重性: **HIGH**
- 位置: `git_occ_head.py:L886-901` (per-class balance loop)
- 描述: 当类别样本量差异极大 (car 8269 vs trailer 90 = 92:1) 时，per_class_balance 让每个类的 loss 权重相等，但 trailer 的 loss 统计噪声极大 (少量样本 → 高方差)。在 DINOv3 语义特征下，噪声通过 backbone 传播，导致类别间零和振荡。
- 修复建议: 使用 **样本量加权的 per_class_balance**，而非等权。例如 `weight_c = 1.0 / sqrt(count_c)` 而非 `1.0`。这样 trailer (90) 的权重约为 car (8269) 的 `sqrt(8269/90) ≈ 9.6` 倍，而非 `8269/90 ≈ 92` 倍 (当前等权的隐含倍率)。

---

## 第 4 部分: Precision 瓶颈分析

### bg_FA=0.167 但 avg_P=0.040 — 脱钩原因

bg_FA 衡量的是"背景 cell 被错误预测为前景"的比例。avg_P 衡量的是"前景预测中正确的比例"。

两者脱钩说明:
1. **模型少预测前景了** (bg_FA 低 = 背景判断好)
2. **但预测的前景大多是错的** (avg_P 低 = 前景判断差)

具体原因: bus/trailer 的 Recall 和 Precision 同时崩溃，说明模型几乎放弃了预测这两个类。在 per_class_balance 下，car 和 truck 占据了 cls loss 的有效梯度空间，bus/trailer 的梯度噪声被挤出。模型学到了"只预测 car 和少量 truck"的策略。

### truck/bus/trailer Precision 极低的结构性原因

1. **truck_P=0.130→0.095**: truck 有 5165 GT 但 Linear(4096,768) 无法同时保持 car 和 truck 的精度。car 和 truck 在 DINOv3 特征空间中相似度高 (都是大型车辆)，768 维投影中容易混淆。

2. **bus_P=0.024**: bus 在 @4500 几乎不被预测 (bus_R=0.058)。少数预测中大多是误判。

3. **trailer_P=0.005**: trailer 90 个 GT 在 DINOv3 特征空间中没有足够的统计支持。Linear 投影无法为 trailer 分配独立的子空间。

---

## 第 5 部分: P5 后续策略

### P5 是否有价值

**有。** 尽管 avg_P 暴跌，P5 证明了两个关键假设:
1. DINOv3 Layer 16 特征**确实**提升了分类精度 (car_P 提升)
2. DINOv3 Layer 16 特征**确实**提升了回归精度 (offset_th 突破至 0.142)

问题不在特征本身，而在:
- 特征到 Transformer 的适配 (Linear 压缩太狠)
- 类别平衡策略不适合强语义特征
- LR schedule 被 milestone 错误拖延

### P5b 建议

**推荐从 P5@4000 出发:**

| Checkpoint | 理由 |
|-----------|------|
| P5@4000 | car_R/truck_R 较好，bus/trailer 有部分恢复，offset_th=0.142 是历史最佳 |
| P5@4500 | bg_FA=0.167 最低但其他指标太差 |
| P5@3500 | car/truck 极好但 bus/trailer=0，太偏 |

**P5b Config 修改:**

1. **Milestones 修正** (必须):
```python
milestones=[2000, 3500]  # 相对于 begin=500
# 实际 decay: @2500, @4000
```

2. **per_class_balance 改为样本量加权** (关键):
```python
# 在 git_occ_head.py 中修改 per-class balance 权重
# weight_c = 1.0 / sqrt(count_c / min_count)
# car: 1.0/sqrt(92) ≈ 0.10, truck: 1.0/sqrt(57) ≈ 0.13,
# bus: 1.0/sqrt(34) ≈ 0.17, trailer: 1.0
```

3. **考虑双层投影** (可选):
```python
# Linear(4096, 1024) + GELU + Linear(1024, 768)
# 缓解 5.3:1 压缩导致的类别子空间干扰
```

### P6 方向

**DINOv3 适配问题解决前，不应进入 BEV 坐标 PE。** 当前 P5 暴露的类别振荡问题是架构层面的，BEV PE 解决的是空间编码问题，两者不在同一维度。

优先级: P5b (修复振荡) > P6 (BEV PE)

---

## 第 6 部分: BUG 状态更新

| BUG | 状态 | 备注 |
|-----|------|------|
| BUG-17 | **NEW (HIGH)** | per_class_balance 在极不均衡数据下的零和振荡 |
| BUG-15 | OPEN | Precision 瓶颈 — P5 未解决 |
| BUG-11 | FIXED | classes 默认值已修 |

下一个 BUG 编号: BUG-18

---

## 逻辑验证

- [x] MMEngine MultiStepLR milestone 行为: 代码追踪确认 `last_step` 从 `begin` 起计数，milestones 为相对值
- [x] PreextractedFeatureEmbed 实现: `Linear(4096,768)` + kaiming_uniform 初始化 (vit_git.py:L103-105)，前向传播正确加载 .pt 文件
- [x] DINOv3 Conv2d 冻结不适用于 P5: config L232 `use_dinov3_patch_embed=False`，L235 `use_preextracted_features=True`，不再加载 DINOv3 7B 模型
- [x] 梯度流: `backbone.patch_embed.proj` (Linear 4096→768) 的 lr_mult=1.0 (config L386)，确保投影层全量训练

---

## 附加建议

1. **P5@4000 的 offset_th=0.142 是所有训练中的历史最佳**: 这证明 DINOv3 Layer 16 确实包含方向信息。P5b 应在此基础上保护 theta 回归。

2. **观察 P5 训练日志中 loss_cls vs loss_reg 的比值变化**: 如果 loss_cls 在某些 checkpoint 暴增，说明分类在某个类别上经历了灾难性遗忘。建议在 git_occ_head.py 中添加 per-class loss 的日志输出。

3. **warmup 1000 iter 可能过长**: P5 的 full LR 阶段为 1000-5000 (4000 iter)。warmup 占 25%。考虑 P5b 中将 warmup 缩短至 500 iter，给 full LR 更多时间。

4. **P5 证明了 VERDICT_P4_FINAL 的 P5 起点建议正确**: P4@500 (对旧分布适应最浅) 确实是合适的起点。但适配问题比预期更严重 — Linear 压缩和类别平衡是主要障碍。
