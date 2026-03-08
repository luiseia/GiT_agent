# AUDIT_REQUEST: Plan P 失败分析 + P6 突破平台 + BUG-41 + 路线决策
- 签发: Conductor | Cycle #81 Phase 1
- 时间: 2026-03-08 13:52
- 优先级: **HIGH — Full nuScenes 路线决策需要**

---

## 审计背景

三项关键新数据改变了决策格局:

1. **Plan P @500 car_P=0.004 — 失败**: 但 Admin 诊断为超参问题, 非架构缺陷
2. **P6@3500 car_P=0.121 首超 P5b (0.116)**: 尽管 BUG-39 退化架构
3. **BUG-41**: Plan O warmup=max_iters=500, 全程在 warmup 中, 结果不可信

---

## 数据

### 1. Plan P @500 (ORCH_022 — FAIL)

| 指标 | Plan P @500 | P6 @500 | Plan L @500 | P5b @500 (DDP) |
|------|------------|---------|-------------|----------------|
| car_P | **0.004** | 0.073 | 0.054 | 0.080 |
| car_R | 0.002 | 0.231 | — | 0.856 |
| truck_P | 0.040 | 0.019 | — | 0.039 |
| bus_P | 0.045 | 0.008 | — | — |
| bg_FA | **0.165** | 0.173 | 0.237 | 0.235 |

**Plan P config**:
- proj: 2048 + **GELU** + lr_mult=**1.0** (P6 用 2.0)
- warmup=100 (P6 用 500)
- LR decay @300 (iter 300 后 LR 降 10x)
- max_iters=500, 从 P5b@3000 加载

**Admin 分析 (Conductor 认同)**:
1. lr_mult=1.0: 随机初始化的 2048 proj 以半速训练, 500 iter 根本不够
2. warmup=100 太短: GELU + 随机权重 + 短 warmup = 早期梯度混乱
3. LR decay @300: 仅训练 200 iter (100-300 warmup后) 就 decay, proj 还没开始收敛
4. Plan L 证据: 同为 2048+GELU+lr_mult=1.0, @500 car_P=0.054, **@1000 飙到 0.140** → 需要 ≥1000 iter
5. bg_FA=0.165 **历史最低!**: 说明 2048+GELU 的 bg/fg 判别能力极强, 只是 car 没来得及学

**结论**: Plan P 失败不能用于否定 2048+GELU 架构。实验设计有缺陷。

### 2. P6 突破平台 (BUG-39 退化架构反而超越 P5b!)

| Ckpt | car_P (真实) | bg_FA (真实) | truck_P | vs P5b 0.116 |
|------|-------------|-------------|---------|--------------|
| @3000 | 0.106 | 0.297 | 0.054 | -8.6% ❌ |
| **@3500** | **0.121** | **0.287** | **0.069** | **+4.5% ✅** |
| **@4000 DDP** | **0.123** | **0.285** | **0.077** | **+6% ✅** |

**@4000 DDP 预估真实值** (基于 @3500 DDP→真实 校正 ±4-6%):
- car_P: ~0.125-0.130
- bg_FA: ~0.268-0.275
- off_th: ~0.193-0.198

**关键**: P6 在 BUG-39 退化架构下 @3500 突破了 @1500-3000 的平台 (0.106-0.111), 说明:
1. 退化架构 (≡Linear(4096,768)) 需要更多训练时间收敛
2. lr_mult=2.0 在 LR decay 后 (2.5e-07) 给了足够的微调空间
3. 因式分解参数化 W2*W1 可能有隐式正则化优势 (核范数)
4. 或者: BUG-39 的影响被高估了, 线性投影在 mini 上已经足够

### 3. BUG-41: Plan O 全程 Warmup

Plan O config: `LinearLR end=500, max_iters=500` → LR 从 0.001*base_lr 线性增长到 base_lr, 在 iter 500 才达到完整 LR。**模型从未在正常 LR 下训练过。**

这使 Plan O 结果 (待出) 不可信。在线 vs 预提取的对比需要重做。

---

## 审计问题

### Q1: BUG-39 重新评估 — P6 退化架构是否可行?

BUG-39 的数学证明是正确的: 两层 Linear 无 GELU = 单层 Linear。但实验数据显示:
- P6@3500 car_P=0.121 > P5b 0.116 (+4.5%)
- P6@4000 DDP car_P=0.123, 趋势继续上升
- P6 需要 3500 iter 才突破, P5b 在 3000 iter 就稳定在 0.116

**问题**: 退化架构是否 "足够好", 可直接用于 full nuScenes? 还是 GELU 版本在充分训练后会更好?

### Q2: Plan P 失败的归因

以下哪个因素是主要原因?
- A: lr_mult=1.0 (vs P6 的 2.0) — lr 不足
- B: warmup=100 (vs P6 的 500) — 训练不稳定
- C: LR decay @300 — 过早 decay
- D: 2048+GELU 本身需要 ≥1000 iter 收敛 (Plan L 证据)
- E: 所有因素叠加

Plan L (2048+GELU+lr_mult=1.0) @500 car_P=0.054, @1000 car_P=0.140。这说明至少 D 是真的。

### Q3: Plan P2 是否值得做?

**Plan P2 提案**: 从 P6 config 仅改一处 — `proj_use_activation=True` (加 GELU)
- lr_mult=2.0 (与 P6 一致)
- warmup=500 (与 P6 一致)
- milestones=[2000, 4000] (与 P6 一致)
- max_iters=2000 (比 Plan L 多, 足够收敛)
- load_from P5b@3000 (与 P6 相同起点)
- GPU 1, 单 GPU (~2h)

**这是唯一能干净分离 GELU 变量的实验**: P6 vs Plan P2 仅差一个 GELU。

- 如果 Plan P2@2000 car_P > P6@2000 (0.110): GELU 确实重要 → full 用 2048+GELU
- 如果 Plan P2@2000 ≈ P6@2000: GELU 不重要 → full 用 P6 config (simpler)
- 如果 Plan P2@2000 < P6@2000: 非线性反而有害? 不太可能

### Q4: 现在可以直接去 full nuScenes 吗?

**P6 在 mini 上的表现已经超越了 P5b**, 主要剩余问题:
- bg_FA=0.287 >> P5b 0.189 (+52%) — 但 Critic 之前说 mini bg_FA 意义有限
- car_P=0.121 > P5b 0.116 — 但是退化架构, GELU 版可能更好

**如果跳过 Plan P2 直接去 full**: 风险是选择了次优架构, 24-48h/实验的试错成本

**如果先做 Plan P2 再决定**: 额外 ~2h mini 实验, 但能确定最优 config

### Q5: Full nuScenes Config 候选

| Config | 投影层 | 优势 | 劣势 | 状态 |
|--------|-------|------|------|------|
| **P5b** | 1024+GELU | bg_FA=0.189 最低 | car_P 天花板 0.116 | 已验证 |
| **P6** | 2048+noGELU | car_P=0.121 最高, truck_P=0.069 | bg_FA=0.287, BUG-39 退化 | @4000+ |
| **Plan P2** | 2048+GELU | 理论最强 | 未验证 (Plan P 失败=超参) | 待做 |

### Q6: BUG-41 Plan O — 在线路径如何验证?

Plan O 全程 warmup, 结果不可信。在线路径验证被阻塞。建议:
- 等 Plan P2 完成后, 用 Plan P2 config (2048+GELU) 做在线版本 (Plan O2)
- 或: 接受 Plan M/N 的结论 (在线 car_P ~0.05 不达标), 在线路径不可行

---

## Conductor 分析

### 推荐: Plan P2 (2h) → Full nuScenes

1. **Plan P2 是最高价值实验**: 仅差一个 GELU, 用 P6 完全相同的超参, 2000 iter 够用, GPU 1 空闲
2. **P6 继续到 @6000**: 低成本, 提供退化架构的完整数据
3. **不要基于 Plan P @500 否定 GELU**: 实验设计有缺陷 (lr_mult+warmup+max_iters 全错)
4. **BUG-39 影响可能被高估**: P6@3500+ 表现说明线性投影在 mini 上可工作, 但 full 上是否一样未知
5. **bg_FA 仍是 P6 最大弱点**: GELU 可能修复 (Plan P bg_FA=0.165 暗示)

### 时间线

- 13:52: ORCH_023 P6@4000 re-eval (10 min, GPU 1)
- 14:05: Plan P2 启动 (2000 iter, ~2h, GPU 1)
- ~16:00: Plan P2@2000 完成
- ~15:00: P6@6000 完成
- 16:00+: Full nuScenes config 最终决策
