# 审计判决 — FULL_10000
> Critic | 2026-03-09 ~18:15
> 审计请求来源: Conductor Cycle #139

## 结论: CONDITIONAL

**条件**:
1. 继续 ORCH_024 到 @15000 LR decay, 不中断
2. 增加 @12000 中间 eval 作为健康检查
3. @17000 eval 后, 若 peak_car_P < 0.12 **或** bg_FA > 0.40, 立即启动 ORCH_025 (deep supervision)
4. ORCH_025 配置必须提前准备好, 不留时间在临时调配上

---

## Q1 判决: Deep Supervision 是否立即启用?

### 决策矩阵执行情况

矩阵命中: `peak 0.08-0.10 + 结构指标停滞 → 启用 deep supervision`

**但 Conductor 提出推迟到 LR decay 后, 我同意这个修正, 理由如下:**

### 反对立即启用的理由

**1. 从 @10000 checkpoint resume 有隐性风险**

Deep supervision 代码分析 (`git.py:L386-388` + `git_occ_head.py:L583-626`):
- `loss_out_indices` 从 `[17]` 改为 `[8, 10, 17]` → 新增 2 个辅助 loss 分支
- 辅助 loss 通过 `multi_apply` 调用相同的 `loss_by_feat_single` → 权重默认 1.0 (与主 loss 平权)
- 中间层 (layer 8, 10) **从未被监督过** → 初始辅助 loss 会很高
- **风险**: 2 个高量级辅助 loss + 1 个正常主 loss → 梯度被辅助 loss 主导 → 短期训练不稳定

**具体数值估算:**
- 主 loss (layer 17) @10000: ~2.5 (已收敛中)
- 辅助 loss (layer 8, 10) 初始: ~4.0-5.0 (未监督, 近似随机)
- 总 loss 突变: 2.5 → 2.5 + 4.5 + 4.0 = 11.0 (4.4× 跳变)
- 这个跳变在 AdamW 的 momentum 上会造成严重扰动

**缓解方案** (如果必须从 checkpoint resume):
```python
# 在 loss_by_feat 中对辅助 loss 降权
if num_dec_layers > 1:
    aux_weight = 0.4  # 辅助 loss 权重
    for i in range(num_dec_layers - 1):
        loss_dict[f'd{i}.loss_cls'] = losses_cls[i] * aux_weight
        loss_dict[f'd{i}.loss_reg'] = losses_reg[i] * aux_weight
```

**2. LR decay @15000 是 "免费" 干预**

- 自动触发, 无需任何代码修改
- LR 5e-5 → 5e-6 (×0.1), 直接减缓权重更新幅度
- 预期效果: 振荡幅度减小, P/R 在更优点稳定
- 距离 @15000 仅 5000 iter (~1250 opt steps, ~1.5 天)

**3. Deep supervision + 从头训练 的选项仍然存在**

如果 @17000 评估不及预期, 可以从头启动 ORCH_025:
- Deep supervision ON (`loss_out_indices = [8, 10, 17]`)
- 辅助 loss 权重 0.4
- 从 iter 0 开始, 辅助层和主层一起学习, 避免 resume 的不稳定

### 支持立即启用的理由 (反面论证)

- 决策矩阵存在的意义就是防止 "总是再等等" 的惯性
- @15000 后可能又会说 "等 @25000 第二次 decay"
- ORCH_024 已训练 25%, 如果方向错误, 剩下 75% 都在浪费 GPU

### 我的判决

**等到 @15000 LR decay, 但设置硬性 deadline:**

| 触发条件 | 行动 |
|---------|------|
| @12000 eval: peak_car_P < 0.090 且 bg_FA > 0.40 | 发出 early warning, 准备 ORCH_025 |
| @17000 eval: peak_car_P < 0.12 或 bg_FA > 0.40 | **立即启动 ORCH_025** (deep supervision + 辅助降权 0.4) |
| @17000 eval: peak_car_P > 0.12 且 bg_FA < 0.40 | 继续 ORCH_024 到 @25000 |

**不可再推迟**: @17000 是最后的决策点, 不接受 "再等 @20000" 的论调。

---

## Q2 判决: bg_FA 恶化是否需要紧急干预?

### 数据分析

| Eval | bg_FA | 活跃类数 | opt_steps |
|------|-------|---------|-----------|
| @2000 | 0.222 | ~1.5 | 500 |
| @4000 | **0.199** | ~3 | 1000 |
| @6000 | 0.331 | 5 | 1500 |
| @8000 | 0.311 | 2 | 2000 |
| @10000 | **0.407** | 6 | 2500 |

### 两个趋势叠加

**趋势 1: 与活跃类数正相关** (Conductor 假说正确)
- 更多类被预测 → 更多 cells 被标记为 occupied → bg_FA 上升
- @6000 (5类) 0.331 vs @8000 (2类) 0.311 — 活跃类数解释部分差异

**趋势 2: 世俗性上升** (Conductor 的"隐忧"也正确)
- 比较相似类数: @4000 (3类) 0.199 vs @8000 (2类) 0.311
- 类数更少但 bg_FA 更高 → 存在独立于类数的基线漂移
- **模型正在系统性地变得 "更激进"** — 倾向于预测更多 occupied cells

### 根因分析

**核心驱动力: sqrt balance + 高 rare class weights**

```
bicycle_weight ≈ 11× car_weight
cone_weight ≈ 8× car_weight
motorcycle_weight ≈ 6× car_weight
```

模型收到的训练信号: **漏检 1 个 bicycle 的惩罚 = 漏检 11 个 car 的惩罚**。理性响应是 "宁可多报不要漏报", 即提高 recall 牺牲 precision → bg_FA 上升。

**bg_weight=2.5 不足以对冲:**
- bg_weight=2.5 意味着 "1 个错报 bg 的惩罚 = 2.5 个正常 loss"
- 但 bicycle_weight=11, 如果模型多报 4 个 bg cells (惩罚 10) 来多检出 1 个 bicycle (奖励 11), 净收益为正
- **这是 loss 设计允许的套利行为, 不是 BUG, 是特征**

### 是否需要紧急干预?

**不需要紧急干预, 但需要监控和后续调整。**

理由:
1. LR decay 会减缓 bg_FA 恶化速度 (权重更新变小 → 套利行为被抑制)
2. bg_FA 在当前阶段不是首要矩盾 — car_P 才是
3. 如果 @17000 后 bg_FA > 0.50, 考虑提高 bg_weight (3.5 或 5.0)

**但注意**: bg_FA 恶化趋势如果持续到 @40000, 会使所有 precision 指标恶化。这是 BUG-17 (sqrt balance 振荡) 的延伸后果, 不是新 BUG。

---

## Q3 判决: 0.090 是否是 car_P 天花板?

### P/R 轨迹分析

| Eval | car_P | car_R | est_TP | est_FP | FP/TP |
|------|-------|-------|--------|--------|-------|
| @2000 | 0.079 | 0.627 | ~451 | ~5257 | 11.7 |
| @6000 | 0.090 | 0.455 | ~328 | ~3316 | 10.1 |
| @10000 | 0.069 | 0.726 | ~523 | ~7057 | 13.5 |

(假设 ~720 positive cells/frame)

**@10000 比 @6000 检出了 60% 更多的 car cells (523 vs 328), 但 FP 增长了 113% (7057 vs 3316)。** 模型在 P/R 曲线上向右下方移动 (高 recall, 低 precision)。

### 0.090 是天花板吗?

**不是硬天花板, 但是当前优化轨迹的局部极值。**

原因:
1. **P/R tradeoff 方向错误**: 模型在增加 recall 而非 precision. 这是 sqrt balance 驱动的行为
2. **LR decay 可能改变轨迹**: 降低 LR 后, 模型在 P/R 曲线上移动更慢, 有机会找到更高 precision 点
3. **但要突破 0.10, 可能需要结构性改变**: feature quality (layer 选择), deep supervision, 或投影层改进

### @40000 预估

| 情景 | 估计 peak_car_P | 假设 |
|------|----------------|------|
| 仅 LR decay, 无其他干预 | 0.10-0.12 | decay 减少振荡, precision 小幅回升 |
| LR decay + deep supervision | 0.12-0.16 | 中间层监督改善特征质量 |
| 上述 + layer 24 (BEV最优) | 0.15-0.22 | 更好的语义特征 + 更好的监督 |
| 上述 + unfreeze block (修BUG-48) | 0.18-0.25 | 特征适配 + 全栈优化 |

**0.090 不是最终天花板, 但在当前配置 (frozen DINOv3 layer 16 + 无 deep supervision + sqrt balance) 下, 很难超过 0.12。**

---

## Q4 判决: LR decay @15000 vs Deep Supervision @10000

### 直接结论

**LR decay 优先。Deep supervision 作为备选, @17000 后决定。**

### 对比分析

| | LR decay @15000 | Deep supervision from @10000 |
|--|----------------|------------------------------|
| 成本 | 0 (自动) | 需要改代码 + resume (有风险) |
| 预期效果 | 减缓振荡, 稳定 P/R 点 | 改善中间层特征, 可能提升 precision |
| 风险 | 无 | 辅助 loss 跳变, resume 不稳定 |
| 可逆性 | 不可逆 (但无害) | 不可逆 (checkpoint 已改变) |
| 信息量 | 高 (诊断 LR 是否是问题) | 低 (同时改两个变量, 归因困难) |

**两者不应同时从 @10000 启动。** 同时改 deep supervision + 等待 LR decay = 改了两个变量, 如果效果好不知道归功谁, 效果差不知道怪谁。

**正确顺序:**
1. @15000: LR decay 自动触发 (变量 1)
2. @17000: 评估 LR decay 效果 → 确定 LR 是否是瓶颈
3. 若不够: ORCH_025 从头训练, deep supervision ON (变量 2, 独立测试)
4. 若 ORCH_025 效果好: 后续合并两个改进

---

## 发现的问题

### 无新 BUG

@10000 数据揭示的所有问题都是已知 BUG 和训练动态的预期后果:
- bg_FA 恶化 → BUG-17 (sqrt balance) 的延伸
- car_P 未突破 → BUG-15 (precision 瓶颈, 投影层/layer 选择) 的持续表现
- 振荡继续 → BUG-47 已修正决策矩阵为 3-eval peak

无新 BUG。下一个编号仍为 BUG-51。

---

## 逻辑验证

- [x] **梯度守恒**: Deep supervision resume 时, 辅助 loss 分支的梯度会叠加到主损失上. 默认权重 1.0 会导致 loss 跳变 ~4×, 需要降权处理 (`git_occ_head.py:L621-624`)
- [x] **边界条件**: 如果 `loss_out_indices=[8,10,17]`, backbone 有 18 层 (arch=base 12+6=18), layer 8/10/17 均有效
- [x] **数值稳定性**: LR decay ×0.1 后 optimizer momentum 不会归零 (AdamW momentum 是历史梯度的 EMA), 不存在 "dead momentum" 问题

---

## 需要 Admin 协助验证

### 验证 1: @12000 中间 eval
- **假设**: 训练在 @10000→@12000 间可能出现新的 peak
- **验证方法**: 在 ORCH_024 config 中增加 @12000 eval 点 (或 `eval_interval=2000`)
- **预期结果**: 如果振荡周期 ~4000 iter, @12000 可能处于上升段, car_P 回升到 0.08+

### 验证 2: 准备 ORCH_025 配置
- **假设**: @17000 可能触发 deep supervision 启动
- **验证方法**: 提前准备 deep supervision config:
  ```python
  loss_out_indices = [8, 10, len(self.backbone.layers) - 1]
  # 在 git_occ_head.py loss_by_feat 中: aux_weight = 0.4
  ```
- **预期结果**: 配置就绪, @17000 后可立即启动, 不浪费时间

---

## 对 Conductor 计划的评价

### 正确的部分
1. **决策矩阵应用准确**: peak 0.08-0.10 + 结构停滞 → deep supervision, 矩阵命中正确
2. **bg_FA 趋势分析**: 与类数正相关 + 世俗性上升, 分析到位
3. **三种振荡模式分类**: 广泛/窄/车辆模式, 有助于理解训练动态
4. **推迟到 LR decay 的决策**: 合理, 我支持

### 需要修正的部分
1. **"等 @17000 再决定" 缺少硬性 deadline**: 我已添加。@17000 是最后决策点, 不可再推迟
2. **Deep supervision resume 风险未评估**: 辅助 loss 默认权重 1.0 会导致 ~4× loss 跳变, 必须降权
3. **@10000 预判偏差未深究**: 预判 car_P 回升 0.08-0.10, 实际 0.069. Conductor 没有解释为什么预判错误 — 原因是振荡周期可能从 ~4000 iter 扩展到 ~6000 iter, 或 @10000 仍处于 car_P 下行段

### 遗漏的风险
1. **Deep supervision 辅助 loss 权重**: 如果不降权, resume 训练可能发散. Conductor 没有提到这个
2. **bg_FA 恶化的长期后果**: 如果 @40000 bg_FA > 0.50, 所有 precision 指标将受严重拖累. 应在 @17000 后评估是否需要提高 bg_weight
3. **eval 频率不足**: 当前每 2000 iter 一次 eval, 但振荡周期可能 ~4000-6000 iter, 容易错过 peak. 考虑对 @12000-@20000 区间加密 eval (每 1000 iter)

---

## 附加建议

### 1. @12000-@20000 加密 eval
从 @12000 开始每 2000 iter eval 直到 @20000. 理由:
- 这是 LR decay 前后的关键区间
- 需要足够的数据点来评估 decay 效果
- 当前 5 个 eval 点不够建立可靠的振荡模型

### 2. 提前准备 ORCH_025 (deep supervision)
不要等到 @17000 才开始准备:
- 现在就写好 config
- 确认辅助 loss 降权代码 (`aux_weight=0.4`)
- 确认从 @10000 或 @15000 checkpoint resume 的流程
- @17000 eval 后如果触发, 当天就能启动

### 3. bg_FA 监控指标
建议为 bg_FA 也建立阈值:
| bg_FA | 状态 | 行动 |
|-------|------|------|
| < 0.30 | 健康 | 无需干预 |
| 0.30-0.45 | 关注 | 监控趋势 |
| 0.45-0.50 | 警告 | 考虑提高 bg_weight |
| > 0.50 | 危险 | 必须干预 (bg_weight 或 balance 策略) |

当前 bg_FA=0.407, 处于 "关注" 区间。

### 4. 振荡周期可能在变化
早期振荡周期 ~4000 iter (1000 opt steps). 但 @10000 的 car_P=0.069 低于预判, 可能说明:
- 振荡周期在拉长 (随着模型学到更多类, 类间竞争更复杂)
- 或振荡幅度在增大 (导致低点更低)
- 加密 eval 可以验证这个假设

---

## 训练数据更新 (5-eval 完整表)

| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | peak(5) |
|------|-------|-------|-------|-------|--------|---------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | **0.090** |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | **0.726** | — |
| truck_R | 0.000 | 0.059 | 0.138 | 0.000 | **0.239** | — |
| bus_R | 0.000 | 0.000 | 0.287 | 0.002 | 0.112 | — |
| CV_R | 0.000 | 0.000 | 0.000 | 0.000 | **0.287** | — |
| moto_R | 0.000 | 0.000 | 0.000 | 0.000 | **0.126** | — |
| ped_R | 0.067 | 0.026 | 0.145 | 0.276 | 0.000 | — |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | **0.407** | — |
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | 0.160 | — |
| opt_steps | 500 | 1000 | 1500 | 2000 | 2500 | — |
| 模式 | car spam | 收敛 | 广泛(5类) | 窄(2类) | 车辆(6类) | — |

**BUG 状态: 无新 BUG, 下一个编号 BUG-51**
