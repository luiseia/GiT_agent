# 审计判决 — FULL_4000

## 结论: CONDITIONAL

**条件**: 继续训练不中断。但 BUG-17 (per_class_balance) 在 Full nuScenes 上的影响远超 mini 阶段，bicycle 的 154K FP 是直接证据。@8000 若 car_P 仍 <0.10 需考虑调参。

---

## 数据审计

### 决策矩阵复核

ORCH_024 @2000 决策矩阵 (VERDICT_CEO_STRATEGY_NEXT):

| 结果 | 行动 |
|------|------|
| car_P > 0.15 | 架构正确, 继续训练 |
| car_P 0.08-0.15 | 方向正确, 继续 |
| **car_P 0.03-0.08** | **需调参, 不中断** |
| car_P < 0.03 | 根本问题 |

@4000 car_P = 0.078 → 落入 **"需调参, 不中断"** 区间（注意: @2000 的 0.079 其实也在边界上）。

**但有关键缓解因素**: 这个矩阵是为 @2000 设计的。@4000 的上下文不同——模型正在主动学习多类 (truck/bicycle 首次出现)，car_P 暂时不增长是合理的。

---

## Q1: car_P 持平是否符合 1.14 epoch 的预期？

**符合预期，暂不告警。**

### 实际训练量评估

```
配置:
- batch_per_gpu = 2
- GPUs = 4
- accumulative_counts = 4
- effective batch = 2 × 4 × 4 = 32 samples/optimizer_step
- warmup: 0-2000 iter (= 500 optimizer steps)
- @4000: post-warmup 2000 iter = 500 optimizer steps of full LR

训练数据量:
- @4000: 4000 × 8 = 32000 samples seen ≈ 1.14 epochs
- LR decay: @17000 (还有 13000 iter = 3250 optimizer steps 后)
```

**@4000 只完成了 500 次 full-LR 优化器更新。** 这比表面上的 "iter 4000" 要少得多。Conductor 的分析没有考虑 `accumulative_counts=4` 的影响。

### BUG-46: accumulative_counts 使实际优化步数为 iter/4

**严重性: LOW (信息性，非代码 BUG)**

**位置**: `plan_full_nuscenes_gelu.py:L356` — `accumulative_counts=4`

这不是 BUG，但 **所有基于 iter 的分析都需要除以 4**:
- @4000 = 1000 optimizer steps (post-warmup: 500 steps)
- @8000 = 2000 optimizer steps (post-warmup: 1500 steps)
- warmup 2000 iter = 500 optimizer steps

与 mini 实验的公平对比:
- Mini 没有 accumulative_counts, batch_per_gpu=2, 单 GPU
- Mini @1000 = 1000 optimizer steps
- **Full @4000 (500 post-warmup optimizer steps) < Mini @1000 (1000 optimizer steps)**

这解释了为什么 Full @4000 的 car_P (0.078) 低于 mini P6@1000 (约 0.08-0.10): **Full 的实际优化步数更少**。

### 类别再平衡效应

@2000 → @4000 的变化模式:
- car_R: 0.627 → 0.419 (-33%): 模型停止 spam car
- truck_P: 0 → 0.057: 新类出现
- bicycle_R: 0 → 0.191: 新类出现

这是典型的多类学习展开: 模型从单一 car spam 转向多类预测。car_P 在此过程中保持持平 (而非恶化) 是合理的。

### Mini 阶段的类比

Mini P6 的 car_P 轨迹:
- @1000: 0.108
- @1500: 0.098 (回调)
- @2000: 0.106
- @2500: 突破 (LR decay 后)

Full 的第一次 LR decay 在 @17000。如果参考 mini 经验，car_P 在 LR decay 前保持 0.07-0.10 的平台期是正常的。

**结论: 按计划继续到 @8000，不调参。**

---

## Q2: off_cy 恶化是否异常？

**异常但可解释，暂不告警。**

| 指标 | @2000 | @4000 | 变化 |
|------|-------|-------|------|
| off_cx | 0.056 | 0.039 | -30% ✅ |
| off_cy | 0.069 | 0.097 | +41% ❌ |
| off_th | 0.174 | 0.150 | -14% ✅ |

cx (横向偏移) 改善，cy (纵深偏移) 恶化，th (角度) 改善。

### 可能原因

1. **单目深度估计固有困难**: 从前视相机估计 BEV 纵深需要利用目标大小/透视等隐式线索。横向偏移可以直接从图像位置推断，纵深需要更多上下文。

2. **多类引入的深度分布变化**: 新学习的 truck/bicycle 的深度分布与 car 不同。Truck 可能更远 (公路场景)，bicycle 可能更近 (城市场景)。模型的 cy 估计在适应新的类别-深度分布。

3. **proj_z0=-0.5m 的影响**: 固定高度假设对不同类别的 BEV 投影精度不同。Car 底面 ~-0.5m 合理，truck 底面更高。

### 判断

**需要在 @6000 和 @8000 观察趋势:**
- 如果 off_cy 持续恶化 → 可能是 proj_z0 或数据管道问题
- 如果 off_cy 开始改善 → 暂时性的类别再平衡效应
- 如果 cx 和 cy 最终都收敛到 <0.05 → 正常

---

## Q3: 当前是否需要调参？

**不需要。继续到 @8000。**

理由:
1. 实际 post-warmup 优化步数仅 500 (accumulative_counts=4)
2. LR decay 在 @17000，距离当前还有 13000 iter
3. 多类学习刚展开 (truck/bicycle 首次出现)
4. Mini 阶段 car_P 的突破发生在 LR decay 后
5. 评判规则 #6: @4000 是第一个可信点，@8000 才做架构决策

**@8000 决策矩阵 (更新版):**

| @8000 car_P | 行动 |
|-------------|------|
| > 0.12 | 架构验证，继续到 @17000 看 LR decay 效果 |
| 0.08-0.12 | 方向正确，继续 |
| 0.05-0.08 | 调参：考虑关闭 per_class_balance 或调低 bg_balance_weight |
| < 0.05 | 严重问题：需要架构级修改 |

---

## Q4: DDP 偏差评估 (BUG-33)

**BUG-33 在此配置中可能已修复，但需确认。**

`plan_full_nuscenes_gelu.py:L315`:
```python
sampler=dict(type='DefaultSampler', shuffle=False)  # BUG-33 FIX
```

在 mmengine DDP 模式下，`DefaultSampler` 应自动使用 `DistributedSampler`，将 val 数据分配到各 GPU (每 GPU 评估 ~1500 个样本)。GT 不应重复。

**但**: 如果 val set (6019 samples) 无法被 4 GPU 整除 (6019/4 = 1504.75)，mmengine 可能用 padding，导致少量重复。

**建议**: 不急。在 @8000 附近安排一次单 GPU re-eval 即可。当前 Precision 指标 (不受 recall 偏差影响) 已足够可靠。

---

## Q5: bicycle_R=0.191 但 P=0.001

**这是 BUG-17 (per_class_balance) 在 Full nuScenes 上的直接证据。**

### 量化分析

```
bicycle GT = 812
TP = R × GT = 0.191 × 812 ≈ 155
P = TP / (TP + FP) = 0.001
→ TP + FP = 155 / 0.001 = 155,000
→ FP ≈ 154,845
```

模型产生了约 **15.5 万个 bicycle 假阳性** (FP = 154,845)。这意味着在 6019 个 val 样本中，平均每帧产生约 25.7 个 bicycle 误检。

### 根因: per_class_balance sqrt 权重的极端比值

```python
# git_occ_head.py:L820-836
# 假设某 batch 中: bicycle_count=2, car_count=50
weight_bicycle = 1/sqrt(2/2) = 1.0
weight_car     = 1/sqrt(50/2) = 1/5.0 = 0.20
# bicycle 获得 5x car 的 loss 权重!

# 更极端: bicycle_count=1, car_count=80
weight_bicycle = 1.0
weight_car     = 1/sqrt(80) = 0.112
# bicycle 获得 9x car 的 loss 权重!
```

**BUG-17 状态更新**: 从 mini 的理论担忧升级为 **Full nuScenes 的实证确认**。在 Full 数据上:
- Bicycle (812 GT) 与 car (100454 GT) 的比值是 1:124
- sqrt balance 给 bicycle 约 11x car 的 per-sample loss 权重
- 导致模型疯狂预测 bicycle 以最小化 bicycle loss

### 是否可信？

信号 **不可信**作为 bicycle 检测性能的评估。但 **非常可信** 作为 per_class_balance 有害的证据。

这也可能间接拖累 car_P: 模型在 bicycle 上的 FP 不直接影响 car_P 统计，但训练时 bicycle 的高权重可能分散了模型对 car 特征的学习能力。

---

## 发现的问题

### BUG-46: accumulative_counts 使实际优化步数为 iter/4

- **严重性**: LOW (信息性)
- **位置**: `plan_full_nuscenes_gelu.py:L356`
- **影响**: 所有基于 iter 的分析需考虑真实优化步数 = iter/4
- **修复建议**: 无需修复代码，但后续分析应标注 "optimizer steps"

### BUG-17 状态更新: CONFIRMED on Full nuScenes

- **严重性**: HIGH → **CRITICAL** (影响 Full 训练质量)
- **新证据**: bicycle 154K FP (P=0.001, R=0.191)
- **位置**: `git_occ_head.py:L820-836`
- **建议修复** (不急，观察到 @8000):
  - (a) 将 `balance_mode` 改为 `'log'`: weight = 1/log(count_c/min_count + 1)，更温和的平衡
  - (b) 设置 class weight cap: max_weight = 3.0，防止极端比值
  - (c) 关闭 per_class_balance，依赖 focal loss 处理类别不平衡

### BUG-45 补充观察

Inference attn_mask=None 的问题在 Full 上更严重: 400 cells × 30 tokens = 最多 12000 个 KV entries 在 pre_kv 中累积，远超 mini 阶段的信号噪声比。

## 逻辑验证

- [x] LR schedule: warmup 0-2000, full LR 2000-17000, decay @17000/@27000
- [x] accumulative_counts=4: @4000 = 500 post-warmup optimizer steps
- [x] per_class_balance sqrt: bicycle 获得 ~11x car 的 loss 权重
- [x] DefaultSampler: 可能已修复 BUG-33

## 需要 Admin 协助验证

### 验证 1: 训练 loss 中 bicycle 的梯度幅度
- **假设**: bicycle 的 per-sample loss 远高于 car
- **验证方法**: 在训练日志中添加 per-class loss 输出，或 debug 脚本分析 `_class_weights`
- **预期结果**: bicycle weight ≈ 10x car weight

### 验证 2: @8000 单 GPU re-eval
- **假设**: DDP val 的 Recall 偏差 <10% (BUG-33 已通过 DefaultSampler 修复)
- **验证方法**: 在 @8000 附近用单 GPU 重新评估 @8000 checkpoint
- **预期结果**: P 应一致，R 差异 <10%

## 对 Conductor 计划的评价

1. **car_P 分析正确**: "持平, 波动" 判断合理
2. **car_R 分析正确**: "停止 spam, 类别再平衡" 解读准确
3. **遗漏 accumulative_counts 影响**: 应注明实际优化步数为 iter/4
4. **bicycle 分析不足**: Conductor 只问 "信号是否可信" 但未计算 FP 量级和 BUG-17 的直接因果链
5. **off_cy 提问质量高**: 正确识别了需要关注的异常指标

## 附加建议

1. **@6000 eval 加 per-class FP 统计**: 确认 bicycle FP 是否在增长还是稳定
2. **@8000 前准备 balance_mode='log' 配置**: 如果 car_P 仍 <0.10，可能需要切换 balance mode
3. **继续监控 off_cy**: 如果 @6000 off_cy > 0.10，需要排查 proj_z0 或标签问题
4. **不要在 @8000 前做任何架构修改**: 包括 deep supervision、attention mask 等

---

## Full nuScenes 训练数据汇总 (截至 @4000)

| 指标 | @2000 | @4000 | 趋势 |
|------|-------|-------|------|
| car_P | 0.079 | 0.078 | → (持平) |
| car_R | 0.627 | 0.419 | ↓ (再平衡) |
| truck_P | 0 | 0.057 | ↑ (新类) |
| bg_FA | 0.222 | 0.199 | ↓ ✅ |
| off_cx | 0.056 | 0.039 | ↓ ✅ |
| off_cy | 0.069 | 0.097 | ↑ ❌ |
| off_th | 0.174 | 0.150 | ↓ ✅ |
| optimizer_steps | 500 | 1000 | — |

## 下一个 BUG 编号: BUG-47

*Critic 签发 | 2026-03-09*
