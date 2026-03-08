# 审计判决 — P6_3000

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: P6 @3000 Mini 最终评估 + Full nuScenes 决策

---

## 结论: CONDITIONAL — P6 mini 验证有条件通过，Full nuScenes 启动需满足前置条件

P6@3000 car_P=0.106 与 P5b@3000 (0.107) 持平，**未实现超越**。宽投影 2048 的架构在 1500 iter 内兑现了 car_P 快速攀升（@1500 即达 0.106），但随后 1500 iter car_P 在 0.106-0.111 **完全平台化**。这不是"验证成功"——这是 mini 数据的容量天花板。架构方向正确但证据不充分。

---

## 对七个问题的回应

### Q1: P6 @3000 PASS/FAIL？mini 验证结论？

**CONDITIONAL PASS — 架构验证通过，精度验证不充分。**

数据分析：

| 指标 | @1500 | @2000 | @2500 | @3000 | 趋势 |
|------|-------|-------|-------|-------|------|
| car_P | 0.106 | 0.110 | 0.111 | 0.106 | **平台化 ±0.005** |
| bg_FA | 0.250 | 0.300 | 0.336 | 0.309 | **振荡，@2500 见顶** |
| off_cx | 0.038 | 0.085 | 0.058 | 0.039 | **振荡，与 car 周期同步** |
| off_th | 0.246 | 0.234 | 0.201 | 0.205 | **单调下降后稳定** |

**car_P 平台化是核心问题**。从 @1500 到 @3000（整整 1500 iter，包含一次 LR decay @2500），car_P 纹丝不动。三种解释：

1. **mini 数据天花板** (最可能)：323 图 ~3500 框，car ~2000 框。模型已从这些数据中提取了全部可学习信息。
2. **sqrt balance 限制**：10 类 sqrt 平衡使 car 梯度被持续分流给小类，即便 car 有 57% 的标注量。
3. **投影层已收敛**：proj lr_mult=2.0 + 3000 iter = 等效单层 6000 iter。投影层参数空间已被充分探索。

**无论哪种解释，结论相同：mini 上 car_P ~0.11 是该架构的极限，继续训练不会突破。**

### Q2: 是否切 full nuScenes？何时？

**有条件启动。** 但需要先完成两个前置实验（见下方条件）。

**支持切换的论据**：
- mini 数据天花板已触达 (BUG-20, car_P 平台化)
- 类振荡是 mini 样本不足的产物，full nuScenes (~28000 图) 预期大幅缓解
- CEO 方向明确：mini 仅 debug
- GPU 1+3 空闲，可并行准备

**反对盲目切换的论据**：
- P6 vs P5b 对比缺乏可信基线（P5b 未 re-eval，见 Q3）
- 在线 DINOv3 + 宽 2048 从未测试过（Plan M/N 用的 1024）—— **BUG-36**
- 2.1TB 存储问题被过度渲染（BUG-26 已证实仅需 ~175GB fp16）

### Q3: P5b 是否需要 re-eval？

**必须。这不是建议，是审计要求。**

当前对比：P6@3000 car_P=0.106 (单GPU可信) vs P5b@3000 car_P=0.107 (DDP，不可信)

ORCH_019 数据显示 DDP vs 单GPU car_P 偏差：
- @500: 0%
- @1000: -7%
- @1500: +10%
- @2000: -2%
- @2500: +1%

**@3000 偏差未知**。P5b 是在旧 config 上跑的 DDP，连 DistributedSampler 都没有（BUG-33 fix 是 P6 才加的）。P5b 的 DDP 偏差可能比 P6 更大。

在没有 P5b 单GPU re-eval 之前，**"P6 与 P5b 持平"这个结论无法成立**。可能的真相：
- P5b 真实 car_P=0.096 → P6 超越 +10%
- P5b 真实 car_P=0.118 → P6 远不如

**耗时**: ~10 min (单 GPU eval 一个 checkpoint)。没有理由不做。

### Q4: @3000 后继续策略？

**P6 继续到 @6000 收集数据，但不要对 @4500+ 抱期望。**

- @4500: 第二次 LR decay (5e-6 → 5e-7)。proj 有效 LR: 1e-5 → 1e-6。
- @5000: 值得做单 GPU eval 以确认 LR decay 效果。
- @6000: 最终 mini eval。预测 car_P 与 @3000 基本持平 (~0.10-0.11)。

**不要在 P6 mini @6000 上投入决策权重。** Mini 的价值已在 @3000 耗尽。剩余 3000 iter 仅是保险确认。

### Q5: bg_FA=0.309 是否阻碍 full nuScenes？

**不阻碍。**

1. bg_FA=0.309 在 @3000 已较 @2500 (0.336) 改善，LR decay 效应开始显现
2. Mini 上 100 个 cell 中 ~85 个是空白，bg_FA 的统计波动大
3. Full nuScenes 的 BEV grid 密度远高于 mini，bg_FA 问题预期不同
4. CEO 明确"不以 mini 指标为最高目标"

但 bg_FA 趋势 (0.173→0.352→0.250→0.300→0.336→0.309) 揭示一个规律：**bg_FA 与 car_R 负相关**。car_R 高时 (多 slot 被 car 占据)，bg_FA 低；car_R 降时 slot 被小类抢占，bg_FA 升。这是类振荡的另一个表现。

### Q6: car_P @3000=0.106 回落解释？

**Precision-Recall 权衡 + 类振荡周期效应。**

@3000 是 car 回弹期 (car_R=0.692，可能虚高)：
- car_R 高 → 更多 slot 被预测为 car → 部分是 FP → Precision 下降
- 这与 @1500 完全相同的模式：car_R=0.499 时 car_P=0.106，car_R 更低但 P 相同

**@3500 预测**: car 回弹结束，小类开始回摆，car_R 可能降到 ~0.40，car_P 可能微升到 ~0.11。但不会超过 0.115。LR 已在 5e-6，梯度太小无法显著改变。

### Q7: Full nuScenes 路线选择？

**先做一个 500-iter mini 验证实验，再做路线选择。**

当前路线对比有致命缺陷：

| 路线 | mini car_P | proj_dim | 激活 | 公平性 |
|------|-----------|----------|------|--------|
| P6 (预提取) | 0.106 | **2048** | 无 | ✅ |
| Plan N (在线 frozen) | 0.045 | **1024** | GELU | ❌ 不公平 |
| Plan M (在线 unfreeze) | 0.047 | **1024** | GELU | ❌ 不公平 |

**BUG-36: Plan M/N 使用 proj_hidden_dim=1024，P6 使用 2048。CEO 基于此对比否决在线路径，但对比条件不一致。**

在线路径 car_P=0.05 可能有三个原因叠加：
1. 在线 vs 预提取的本质差异（计算精度、特征一致性）
2. proj_hidden_dim 1024 vs 2048 的差异
3. 有 GELU vs 无 GELU 的差异

**必须分离这三个变量。** 建议：

**Plan O (验证实验)**：在线 DINOv3 frozen + proj_hidden_dim=2048 + 无 GELU + 10 类 + num_vocal=230 + P5b@3000
- 在 GPU 1 或 3 上跑 500 iter mini
- 如果 car_P > 0.07 → 在线路径可行，全 nuScenes 用在线
- 如果 car_P < 0.05 → 在线路径确实不行，全 nuScenes 用预提取 (175GB fp16)
- 耗时预估: ~1h（含 DINOv3 在线前向 + 训练）

**存储估算修正**（BUG-26 重申）：
- 全 nuScenes 前摄 fp16 预提取: ~175GB (非 2.1TB)
- 在线 DINOv3 frozen: 0 额外存储，但每 iter 多 ~1.5s
- 175GB 在 SSD 上完全可接受

---

## 发现的问题

### BUG-36: Plan M/N vs P6 对比条件不一致 (proj_dim 1024 vs 2048)
- **严重性**: HIGH
- **位置**: `GiT/configs/GiT/plan_m_online_dinov3_diag.py` 和 `plan_n_online_frozen_diag.py` 均使用 `preextracted_proj_hidden_dim=1024`（继承自 P5b），而 P6 使用 2048
- **影响**: CEO 基于 Plan M/N car_P~0.05 否决在线路径，但 P6 从 P5b 的 1024 切到 2048 后 car_P 从 ~0.09 升到 ~0.11。在线路径 +2048 可能也有同比提升。
- **修复**: 必须跑 Plan O（在线 frozen + 2048 + 无 GELU）才能公平对比
- **代码引用**: `GiT/mmdet/models/backbones/vit_git.py:L238-250`（投影层构建逻辑）

### BUG-37: P5b 基线缺乏可信单 GPU 数据
- **严重性**: HIGH
- **位置**: P5b 全部 eval 数据来自 DDP（无 DistributedSampler），BUG-33 影响更大
- **影响**: P6 vs P5b 的所有对比结论均不可靠。Conductor 声称"P6 与 P5b 持平"缺乏证据支撑。
- **修复**: 对 P5b@3000 做单 GPU re-eval (`tools/test.py --launcher none`)

### BUG-38: car_P 平台化 — Critic 预测偏乐观
- **严重性**: MEDIUM (自我纠正)
- **描述**: VERDICT_P6_1500 预测 car_P @3000 为 0.12-0.13。实际 0.106。Critic 高估了 LR decay 对 car_P 的正面影响。
- **根因分析**: LR decay 稳定了类振荡（off_th 如期收敛到 0.205），但没有提升 car_P。这表明 car_P 瓶颈不在训练动态，而在数据/架构容量。
- **教训**: mini 上 car_P ~0.11 是硬天花板，未来审计不应对 mini 指标做进一步上升预测。

---

## 逻辑验证

### 梯度守恒
- [x] sqrt balance 权重计算正确：`w_c = 1/√(count_c/min_count)`，`GiT/mmdet/models/dense_heads/git_occ_head.py:L821-836`
- [x] bg_balance_weight=2.5 与 class weights 独立运作，`git_occ_head.py:L859-873`
- [x] clip_grad max_norm=10.0 维持不变，`plan_p6_wide_proj.py:L350`
- [x] accumulative_counts=4 (有效 batch=8)，梯度缩放正确

### 边界条件
- [x] proj 投影链: Linear(4096,2048) + Linear(2048,768)，无激活，无 LayerNorm，无 Dropout — `vit_git.py:L238-250`
- [x] num_vocal=230 保持与 P5b 一致，无 BUG-27 风险 — `plan_p6_wide_proj.py:L97`
- [x] BUG-33 修复已在 config 中: `sampler=dict(type='DefaultSampler', shuffle=False)` — `plan_p6_wide_proj.py:L309`
- [ ] **注意**: BUG-33 fix 仅在 P6 config 中。P5b config 没有此修复。P5b re-eval 将自动绕过此问题（单 GPU 不受 DDP 影响）。

### 数值稳定性
- [x] LR schedule 验证: @2500 decay 到 5e-6，@4500 decay 到 5e-7 — `plan_p6_wide_proj.py:L326-342`
- [x] proj lr_mult=2.0 在 @2500+ 等效 LR=1e-5，不再过激 — BUG-34 自动缓解确认
- [x] off_th=0.205 稳定，验证 theta 编码在低 LR 下收敛 — Critic 预测兑现

---

## 条件清单 (Full nuScenes 启动前必须满足)

### COND-1: P5b@3000 单 GPU re-eval [BLOCKING]
- 在 GPU 1 或 3 上: `tools/test.py --launcher none` 评估 P5b@3000
- 获取可信 car_P 基线
- 耗时: ~10 min
- **不满足则**: P6 vs P5b 对比无效，无法判断宽投影是否真正有效

### COND-2: Plan O 验证实验 [BLOCKING for route decision]
- Config: 在线 DINOv3 frozen + proj_hidden_dim=2048 + proj_use_activation=False + 10 类 + num_vocal=230 + load_from P5b@3000
- 在 GPU 1 或 3 上跑 500 iter mini
- 判定阈值: car_P@500 > 0.05 → 在线可行; < 0.05 → 在线不可行
- 耗时: ~1h
- **不满足则**: CEO 的在线路线决策基于不公平对比 (BUG-36)，可能导致 full nuScenes 浪费数天训练时间

### COND-3: P6 @5000 单 GPU eval [NON-BLOCKING]
- 在第二次 LR decay (@4500) 后做 @5000 eval 确认收敛
- 可与 full nuScenes 准备并行

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-36 | HIGH | NEW | Plan M/N vs P6 对比条件不一致 (proj_dim 1024 vs 2048) |
| BUG-37 | HIGH | NEW | P5b 基线缺乏可信单 GPU 数据 |
| BUG-38 | MEDIUM | 自我纠正 | Critic car_P 预测偏乐观 (0.12-0.13 vs 实际 0.106) |

**下一个 BUG 编号**: BUG-39

---

## P6 Mini 最终评价

### 成就
1. **off_cx=0.039 和 off_th=0.205** — 偏移量预测达到历史最佳，宽投影对空间精度有明确帮助
2. **car_P 快速收敛** — 从随机投影 @500 car_P=0.073 到 @1500 car_P=0.106 仅用 1000 iter
3. **架构验证** — Linear(4096,2048)+Linear(2048,768) 无激活函数的简洁设计被证实有效
4. **BUG-33 修复** — val_dataloader 加入 DefaultSampler，DDP eval 不再有 GT 重复

### 未解决
1. **car_P 天花板 ~0.11** — mini 数据量限制
2. **类振荡** — ~1000 iter 周期，LR decay 仅缩小振幅，不能消除
3. **bg_FA ~0.30** — 与类振荡耦合，无独立改善手段
4. **在线 vs 预提取** — 公平对比缺失 (BUG-36)

### Full nuScenes 预期
- car_P: 0.20-0.35 (full 数据量的非线性增长，但需实验验证)
- 类振荡: 预期大幅缓解（各类样本量提升 ~40x）
- bg_FA: 预期改善（BEV grid 更密集，空白 cell 比例降低）
- 训练时长: ~24-48h per 实验 (4xA6000)，试错成本高

---

## 附加建议

### 对 Conductor
1. **不要急于宣称 P6 "验证成功"**。持平 ≠ 超越。宽投影的价值体现在 offset 精度，不在 car_P。
2. **Plan O 是关键实验**。CEO 的在线路线和 Critic 的预提取路线争议，只有 Plan O 能裁决。
3. **Full nuScenes 的第一个 config** 应直接基于 P6 (宽 2048 + 无 GELU)，不要回退到 P5b 的 1024。

### 对 Admin
1. P5b re-eval 是 10 分钟的事。立即执行，不要等。
2. Plan O config 可以从 `plan_n_online_frozen_diag.py` 修改：仅改 `proj_hidden_dim=2048`、`proj_use_activation=False`、`classes=10类`、`num_vocal=230`。
3. Full nuScenes 预提取只需 175GB (前摄 fp16)。如果 Plan O 失败，这是 plan B。

### 对 Supervisor
1. 监控 P6 @5000 eval（预计 ~16:00）
2. 如果 Plan O 启动，监控其在 500 iter 后的 eval
