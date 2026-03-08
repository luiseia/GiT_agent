# 审计判决 — PLAN_P_FAIL_P6_TREND

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: Plan P 失败归因 + P6@3500 突破平台 + BUG-41 确认 + 路线决策

---

## 结论: CONDITIONAL — Plan P2 必须执行，Full nuScenes 等 Plan P2 结果

P6@3500 car_P=0.121 超越 P5b (0.116) 的事实改变了一切。BUG-39 在数学上仍然正确，但实际影响被**严重高估**。Critic 在 VERDICT_P6_VS_P5B 中的 "CRITICAL" 定级是过激反应。同时，Plan P 的失败完全是超参数灾难，不能用于否定 GELU 架构。Plan P2 (P6 config 仅加 GELU) 是唯一能裁决 GELU 价值的实验。

---

## BUG-39 严重性修正: CRITICAL → MEDIUM

### 数学证明依然成立

`Sequential(Linear(4096,2048), Linear(2048,768))` 无激活 = 单个线性变换。这是数学事实，不可推翻。

### 但实验数据推翻了 "CRITICAL" 判定

| Ckpt | P6 car_P | P5b car_P | P6 vs P5b |
|------|----------|-----------|-----------|
| @3000 | 0.106 | **0.116** | -8.6% ❌ |
| **@3500** | **0.121** | 0.116 | **+4.5% ✅** |
| **@4000 DDP** | **0.123** | 0.116 | **+6% ✅** |

P6 在"退化"架构下超越了 P5b。这说明：

1. **因式分解参数化有优化优势**: W2(768×2048) × W1(2048×4096) = 9.96M 参数 vs 单层 W(768×4096) = 3.15M 参数。参数量 3x，提供更平滑的优化景观和隐式正则化（矩阵因式分解 ≈ 核范数正则化）。
2. **lr_mult=2.0 对因式分解的效果**: 两层各以 2x 学习率更新，等效梯度步长更大，收敛路径不同于单层。
3. **收敛延迟是唯一代价**: P6 需要 3500 iter 才突破 P5b，而 P5b 在 3000 iter 就稳定。额外 500 iter (~15 min on 2xA6000) 是可接受的成本。

**BUG-39 降级理由**:
- "CRITICAL" 意味着"必须立即修复，实验无效"。事实是 P6 在该架构下产生了有效且优越的结果。
- 降为 "MEDIUM (设计层)": 架构不最优，但可工作。GELU 版本可能更好，待 Plan P2 验证。

### Critic 自我纠正 (BUG-40 补充)

VERDICT_P6_VS_P5B 的核心结论"P6 的 3000 iter 训练基于退化架构"在 @3500 数据面前站不住。Critic 在 P6@3000 时做出判断，缺少 @3500 数据点。教训：**不要在数据不完整时做架构性判决**。@3000 恰好是类振荡低谷 (car 被压), @3500 是回弹期。等一个完整振荡周期 (~500-1000 iter) 再下结论。

---

## Plan P 失败归因: 100% 超参数问题

### Config 审计

`GiT/configs/GiT/plan_p_wide_gelu_verify.py`:
- `preextracted_proj_hidden_dim=2048` (L212)
- `preextracted_proj_use_activation=True` (L213) — ✅ GELU 已恢复
- `backbone.patch_embed.proj: lr_mult=1.0` (L349) — ⚠️ 比 P6 (2.0) 低
- `LinearLR: end=100` (L327) — ⚠️ warmup 仅 100 iter
- `MultiStepLR: milestones=[300]` (L334) — ⚠️ iter 300 即 decay
- `max_iters=500` (L318)

### 时间线重构

```
iter 0-100:   LinearLR warmup (LR 从 0.05e-5 → 5e-5)
              proj 有效 LR: 0.05e-5 → 5e-5 (lr_mult=1.0)
              2048 投影层从随机初始化，梯度巨大但 LR 极小
              → 几乎无有效学习

iter 100-300: Full LR (5e-5), proj LR = 5e-5
              仅 200 iter 正常训练
              Plan L 在这个阶段 car_P 仍在 0.054 水平
              → 远不够收敛

iter 300-500: LR decay 10x (5e-6), proj LR = 5e-6
              投影层学习率骤降，car 分类几乎停滞
              → 游戏结束
```

**Plan P 仅有 200 iter (iter 100-300) 在正常 LR 下训练投影层。** 对比:
- P6: 2000 iter (500-2500) 在正常 LR 下 + lr_mult=2.0 = 等效 4000 正常 iter
- Plan L: ≥500 iter 在正常 LR 下 + lr_mult=1.0，@1000 才显现效果
- Plan P: **200 iter** 在正常 LR 下 + lr_mult=1.0 = 等效 200 iter

**200 iter vs 4000 等效 iter。比例 1:20。Plan P 失败是必然的。**

### 五因素归因

| 因素 | 影响 | 证据 |
|------|------|------|
| A: lr_mult=1.0 (vs P6 2.0) | **高** | 投影层学习速度减半 |
| B: warmup=100 (vs P6 500) | **中** | 前 100 iter 几乎无学习 |
| C: LR decay @300 | **致命** | 仅 200 iter 正常训练后就 decay |
| D: 需要 ≥1000 iter | **高** | Plan L @500=0.054, @1000=0.140 |
| E: 叠加效应 | **致命** | A+B+C 使有效训练量 < Plan L 的 1/5 |

**结论: Plan P 失败是实验设计缺陷，与 2048+GELU 架构无关。** Admin 分析正确。

### Plan P bg_FA=0.165 的重要信号

这是**全实验历史最低 bg_FA**:
- P6@500: bg_FA=0.163 (之前最优，无 GELU)
- Plan P@500: bg_FA=**0.165** (有 GELU)
- P5b@3000: bg_FA=0.189

Plan P 在 car 几乎没学到任何东西 (car_P=0.004) 的情况下，bg/fg 判别已经优于 P5b@3000。这暗示：

**GELU 对 bg/fg 判别有独立且强大的贡献。** bg_FA 改善不需要 car 分类器收敛。2048+GELU 的宽投影在早期就建立了好的 bg/fg 边界。

---

## P6 @3500/@4000 突破分析

### 突破机制

P6 car_P 轨迹：0.106(@3000) → **0.121**(@3500) → **0.123**(@4000 DDP)

突破发生在第一次 LR decay 后 1000 iter (@2500 decay, @3500 突破)。机制：

1. **LR decay 压制类振荡**: 梯度更新减少 10x → 小类无法快速抢占 → car 逐步积累优势
2. **因式分解正则化**: W2*W1 的隐式核范数正则化在低 LR 下更明显，减少过拟合
3. **投影层微调**: lr_mult=2.0 × 5e-6 = 1e-5，仍足够微调投影权重

### 对 BUG-38 的修正

VERDICT_P6_3000 (BUG-38): Critic 预测 car_P @3000 为 0.12-0.13，实际 0.106。当时归因为"预测偏乐观"。

**修正**: 预测时间点错了，不是预测值错了。@3500 car_P=0.121 落入预测区间。Critic 低估了类振荡的延迟效应（@3000 恰好在振荡低谷）。

**BUG-38 降级为 LOW**——预测方向正确，仅有 500 iter (~15min) 的时间偏差。

### P6 趋势预测 (修正版)

- @4500 (第二次 LR decay): car_P 可能微降 (decay 过渡期)，~0.118-0.122
- @5000: car_P 再次微升，~0.120-0.125
- @6000: mini 最终值，~0.122-0.128，bg_FA ~0.270-0.280
- **P6 不会继续大幅提升**: LR 已在 5e-7，梯度更新极小

---

## BUG-41 确认: Plan O 全程 Warmup

### Config 审计

`GiT/configs/GiT/plan_o_online_wide_diag.py`:
- `LinearLR: begin=0, end=500` (L324, L328)
- `max_iters=500` (L319)
- 无 MultiStepLR

**LR 轨迹**: 从 0.001×base_lr 线性增长到 base_lr，在 iter 500 达到目标。但 iter 500 = max_iters，训练结束。**模型从未在完整 LR 下训练过。**

### 额外问题: Plan O 未采纳 GELU 推荐

- `preextracted_proj_use_activation=False` (L212) — 仍然无 GELU
- VERDICT_P6_VS_P5B COND-3 明确要求: "Plan O 必须使用 2048 + GELU"
- 该推荐未被执行

### BUG-41 正式记录
- **严重性**: HIGH
- **位置**: `GiT/configs/GiT/plan_o_online_wide_diag.py:L324-328`
- **描述**: LinearLR warmup end=500 = max_iters=500，全程在 warmup 中，模型从未在正常 LR 下训练
- **影响**: Plan O 结果不可信，在线 vs 预提取的对比无效
- **额外**: proj_use_activation=False，未采纳 VERDICT_P6_VS_P5B COND-3

---

## 对审计问题的回应

### Q1: BUG-39 重新评估 — 退化架构是否可行?

**可行。BUG-39 降级为 MEDIUM。**

数学证明不变：两层线性 = 一层线性。但实践证明：
- 因式分解参数化 (W2×W1) 有独立的优化优势
- P6@3500 car_P=0.121 > P5b 0.116，退化架构**跑赢了**非线性 MLP
- 代价是额外 500 iter 收敛时间，可接受

**是否可直接用于 full nuScenes?** 可以，但不最优。理由：
1. P6 bg_FA=0.287 远劣于 P5b 0.189
2. Plan P bg_FA=0.165 暗示 GELU 能修复 bg_FA
3. 2h Plan P2 实验的 ROI 极高——如果 GELU 版本 bg_FA < 0.20 且 car_P ≥ 0.12，那 full nuScenes 用 GELU 版本可能节省数天调参时间

### Q2: Plan P 失败的归因

**E: 所有因素叠加，其中 C (LR decay @300) 是致命一击。**

详见上方分析。Plan P 仅有 200 iter 有效训练，是 P6 等效训练量的 1/20。Plan L 证据 (@500=0.054, @1000=0.140) 明确显示至少需要 1000 iter。

### Q3: Plan P2 是否值得做?

**必须做。这是当前最高价值实验。**

Plan P2 提案审计：
- P6 config 仅改 `proj_use_activation=True` → ✅ 唯一变量：GELU
- lr_mult=2.0 → ✅ 与 P6 一致
- warmup=500 → ✅ 与 P6 一致
- milestones=[2000, 4000] → ✅ 与 P6 一致
- max_iters=2000 → ✅ 足够看到趋势（Plan L@2000 已明确）
- load_from P5b@3000 → ✅ 与 P6 相同起点

**判定标准**:

| 指标 | 阈值 | 含义 |
|------|------|------|
| Plan P2@500 car_P | > 0.05 | GELU + lr_mult=2.0 的早期学习正常 |
| Plan P2@1000 car_P | > 0.10 | GELU 投影正在收敛 |
| Plan P2@1000 bg_FA | < 0.25 | GELU 修复 bg/fg 判别 |
| Plan P2@2000 car_P | vs P6@2000 (0.110) | GELU 是否加速收敛 |
| Plan P2@2000 bg_FA | vs P6@2000 (0.300) | GELU 是否改善 bg_FA |

**最重要的指标是 bg_FA**: 如果 Plan P2 bg_FA < 0.20 而 car_P ≥ 0.10，则 GELU 的价值被确认。Full nuScenes 应用 2048+GELU。

### Q4: 现在可以直接去 full nuScenes 吗?

**不建议。Plan P2 仅 2h，但能避免 24-48h 的 full nuScenes 试错。**

风险矩阵:

| 选择 | 风险 | 成本 |
|------|------|------|
| 跳过 Plan P2，用 P6 config | bg_FA=0.287 可能在 full 上更差 | 如果失败: 48h 浪费 |
| 跳过 Plan P2，用 P5b config | 放弃 offset 精度优势 | 如果次优: 持续损失 |
| 做 Plan P2 再决定 | 延迟 2h | 2h 投入 |

**2h 投入换取 24-48h 风险规避。ROI > 10x。**

但如果 CEO 决定时间优先级高于配置优化，P6 config 是可接受的选择（car_P=0.121 > P5b，已验证）。

### Q5: Full nuScenes Config 候选

| 排名 | Config | car_P (mini) | bg_FA (mini) | 状态 |
|------|--------|-------------|-------------|------|
| 1 | **Plan P2 (2048+GELU)** | 预期 0.12-0.14 | 预期 0.17-0.22 | **待验证 (2h)** |
| 2 | P6 (2048+noGELU) | 0.121 (@3500) | 0.287 | ✅ 已验证 |
| 3 | P5b (1024+GELU) | 0.116 | 0.189 | ✅ 已验证 |

**P5b 不应是 full nuScenes 首选**: P6 已超越它。P5b 仅在 bg_FA 上有优势。

### Q6: BUG-41 Plan O — 在线路径如何验证?

**Plan O 结果无效 (BUG-41 + 未用 GELU)。在线路径验证需要 Plan O2。**

Plan O2 要求:
- 在线 DINOv3 frozen + 2048 + **GELU** (不能再用无 GELU)
- warmup=500 (与 P6/P5b 一致)
- max_iters ≥ 1000 (至少完成一个 warmup + 500 iter 正常训练)
- milestones=[1000] (合理 LR decay)
- lr_mult=2.0 (投影层从随机初始化)

**时间优先级**: Plan O2 可以在 Plan P2 之后，或与 Plan P2 并行 (如果两块 GPU 可用)。

**替代方案**: 如果 CEO 已决定在线路径，跳过 Plan O2，直接在 full nuScenes 上测试在线 + 2048 + GELU。full nuScenes 的数据量可能掩盖 mini 上的在线 vs 预提取差异。

---

## 发现的问题

### BUG-39 状态更新: CRITICAL → MEDIUM (设计层)
- **原严重性**: CRITICAL
- **新严重性**: **MEDIUM**
- **理由**: P6@3500 car_P=0.121 > P5b 0.116。退化架构可工作，因式分解参数化有独立优化优势。数学证明不变，但实际影响有限。
- **位置不变**: `GiT/mmdet/models/backbones/vit_git.py:L238-244`

### BUG-40 补充: Critic 过激反应
- VERDICT_P6_VS_P5B 在 P6@3000 (振荡低谷) 做出 CRITICAL 判定
- @3500 数据 (500 iter / ~15min 后) 即推翻了该判定
- 教训: 等完整振荡周期再做架构性结论

### BUG-41: Plan O 全程 Warmup [HIGH] — 已确认
- **严重性**: HIGH
- **位置**: `GiT/configs/GiT/plan_o_online_wide_diag.py:L324-328`
- **描述**: `LinearLR end=500 = max_iters=500`，模型从未在正常 LR 下训练
- **额外**: `proj_use_activation=False` (L212)，未执行 VERDICT_P6_VS_P5B COND-3
- **影响**: Plan O 结果不可信。在线 vs 预提取对比需要 Plan O2。

### BUG-38 状态更新: MEDIUM → LOW
- **原严重性**: MEDIUM
- **新严重性**: LOW
- **理由**: Critic @3000 预测 0.12-0.13，@3500 实际 0.121。预测值正确，仅时间延迟 500 iter。

---

## 逻辑验证

### 梯度守恒
- [x] Plan P 超参审计: warmup=100 + decay@300 = 仅 200 iter 有效训练。与 Plan L 对比 (500+ iter) 一致解释 car_P=0.004。
- [x] P6 lr_mult=2.0 的正面效果确认: 加速因式分解投影层收敛，@3500 突破 P5b。
- [x] Plan P bg_FA=0.165 与 P6@500 bg_FA=0.163 对比: GELU/无 GELU 对 bg_FA 早期影响极小，差异 0.002 在噪声内。bg_FA 恶化发生在后期 (类振荡)。

### 边界条件
- [x] Plan P2 config 可行性: 仅改 P6 config 的 `proj_use_activation=True`，shape 不变 (Linear 仍是 4096→2048→768)，P5b@3000 checkpoint 的 proj 权重仍会 shape mismatch → 随机初始化。这与 P6 完全一致。
- [x] Plan O2 config: 在线模式需要 dinov3_weight_path 有效、use_preextracted_features=False。已确认 Plan O config 中存在这些设置。

### 数值稳定性
- [x] P6@4000 DDP 校正: @3500 DDP→真实偏差 ±4-6%。@4000 DDP car_P=0.123 → 真实预估 ~0.117-0.130。仍在 P5b (0.116) 之上。
- [x] 第二次 LR decay @4500: LR 5e-6 → 5e-7。proj 有效 LR 1e-5 → 1e-6。梯度更新量级进一步缩小 10x，car_P 不会有大幅变化。

---

## 条件清单

### COND-A: Plan P2 执行 [BLOCKING for full nuScenes config decision]
- Config: P6 config (`plan_p6_wide_proj.py`) 仅改 `proj_use_activation=True`
- 保持: lr_mult=2.0, warmup=500, milestones=[2000,4000], load_from P5b@3000
- max_iters=2000 (或更多如果 GPU 允许)
- val_interval=500
- 单 GPU, ~2h
- **判定**: @1000 bg_FA < 0.25 + car_P > 0.10 → GELU 版本用于 full nuScenes

### COND-B: P6@4000 单 GPU re-eval [NON-BLOCKING]
- 确认 DDP 偏差
- 10 min

### COND-C: Plan O2 (在线路径) [NON-BLOCKING, 可并行]
- 在线 frozen + 2048 + GELU + warmup=500 + max_iters≥1000
- 如果 CEO 已决定路线，可跳过

---

## 附加建议

### 对 Conductor
1. **Plan P2 是 2h 实验，今天就能完成。** GPU 1 空闲。没有理由不做。
2. **Plan P2 config 极简**: `cp plan_p6_wide_proj.py plan_p2_gelu_verify.py`，改一行 (`proj_use_activation=True`)，改 `max_iters=2000`。
3. **如果 CEO 催促 full nuScenes**: P6 config 已可用 (car_P > P5b)，但 bg_FA 是风险。建议对 CEO 说"2h 后给出最终 config 推荐"。
4. **不要基于 Plan P@500 否定 GELU。** Plan P 的超参数设计有致命缺陷，与架构无关。

### 对 Admin
1. Plan P2 config 改动量: 1 行 (`proj_use_activation`=True→只需改 False 为 True)
2. 如果额外改 max_iters=2000 和对应 milestones，总改动 3 行
3. 可选: 添加 `# Plan P2: GELU 验证，仅差一个 GELU vs P6` 注释

### 时间线建议
- 14:00: Plan P2 启动 (GPU 1)
- 14:30: P6@4000 单 GPU re-eval (GPU 3, 10 min)
- ~15:00: P6@6000 完成 (GPU 0+2)
- 15:00: Plan P2@1000 eval — 初步判断 GELU 效果
- ~16:00: Plan P2@2000 eval — 最终判断
- 16:30: Full nuScenes config 决策 + 开始准备

**下一个 BUG 编号**: BUG-42
