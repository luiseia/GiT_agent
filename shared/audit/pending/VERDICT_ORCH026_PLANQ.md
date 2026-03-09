# 审计判决 — ORCH026_PLANQ

## 结论: PROCEED

**"类竞争不是 car_P 瓶颈" 的结论有效。** 混淆因素存在但不改变结论方向——反而加强了它。

---

## Q1: 结论有效性

**有效。混淆因素反而强化结论。**

### 混淆因素分析

Plan Q 使用 P5b checkpoint + 2048 proj 随机初始化。但 **P6 也有完全相同的混淆因素**:
- P6: P5b checkpoint (1024 proj) → 2048 proj 随机初始化
- Plan Q: P5b checkpoint (1024 proj) → 2048+GELU proj 随机初始化

两者都从随机初始化的 proj 开始。Plan Q 还有 GELU (已证明优于 noGELU)。

### 关键对比

| 实验 | 类别数 | GELU | Proj init | Iter | car_P |
|------|--------|------|-----------|------|-------|
| Plan Q @best | **1 (car)** | ✅ | random | 2500 | **0.083** |
| P6 @4000 | 10 | ❌ | random | 4000 | **0.126** |
| Plan P2 @1500 | 10 | ✅ | random | 1500 | **0.112** |

**Plan Q (单类+GELU) 的 best car_P=0.083 < P2 (10类+GELU) @1500 的 car_P=0.112。**

这意味着: 去掉 9 个竞争类别后，car_P 不升反降。10 类训练的 car_P 比单类训练高 35% (0.112 vs 0.083)。

### 为什么多类反而更好？

1. **特征多样性**: 共享 backbone 从 truck/bus/pedestrian 学到的空间特征对 car 有正迁移
2. **BEV 理解**: 模型通过识别其他类别更好地理解 BEV 空间结构
3. **背景判别**: 10 类训练提供更多 "这不是背景" 的信号

### Report 的 "3000 iter 足够学习线性映射" 论证

合理。off_cx@1500 恢复基线 = proj 层在 1500 iter 后已收敛。@2500 的 car_P=0.083 是 Plan Q 在 Mini 上的有效极限，不是训练不足的问题。

**结论: "类竞争无关" 有效且稳健。**

---

## Q2: 战略影响

### BUG-17 重新定位

Plan Q 证明: 类竞争（包括 BUG-17 的 sqrt balance 振荡）**不是 car_P 的瓶颈**。但 BUG-17 仍有实际危害:

| 影响 | 是否因 BUG-17 | 严重性 |
|------|-------------|--------|
| car_P 瓶颈 | **否** (Plan Q 证明) | — |
| bg_FA 膨胀 | **是** (bicycle/ped/bus FP) | MEDIUM |
| 训练不稳定 | **是** (类振荡) | MEDIUM |
| 评估指标可读性 | **是** (FP 噪声) | LOW |

### car_P 真正瓶颈的候选

排除类竞争后，car_P 瓶颈的主要候选:

1. **DINOv3→BEV 信息瓶颈** (BUG-15, HIGH)
   - 4096→2048→768 的 5.3:1 降维
   - 空间信息在降维中丢失
   - Deep supervision 可能缓解 (迫使中间层学习更好的表征)

2. **BEV 投影精度** (proj_z0=-0.5m 固定高度假设)
   - 不同高度的物体投影到错误的 BEV 位置
   - 影响: car 底面 ~-0.5m 合理，但 car 车顶不合理

3. **数据量** (Full vs Mini)
   - Full@6000 car_P=0.090 > Plan Q@best=0.083
   - Full 仍在上升，说明数据量有帮助
   - 但数据量不是根本瓶颈 (Mini P6@4000 car_P=0.126 > Full@6000)

4. **评估方法** (BUG-18: per-cell 不跨 cell 关联)
   - 一个大目标跨多个 cell → 多个 partial match → 降低 precision
   - 这是评估层面的系统性偏差

---

## Q3: 与 Full @6000 的联合解读

**三条结论全部正确。**

### 1. Full 数据量是关键

Full@6000 (1.71 epochs, 28130 train) car_P=0.090 > Plan Q@best (mini, 323 train) car_P=0.083。考虑到 Full 只跑了 1.71 epochs 而 Plan Q 跑了约 9 epochs (3000 iter / 323 × 2 ≈ 9.3)，Full 的数据效率远高于 Mini。

### 2. ORCH_024 方向正确

Full@6000 的 car_P=0.090 在仅 1500 optimizer steps 后已超过 Plan Q 在 Mini 上的极限。继续训练可期待更高 car_P。

### 3. Mini 实验已无参考价值

Plan Q 本身就是 Mini 实验的最终证明: Mini 数据集太小 (323 图)，无法充分训练模型。所有 Mini 实验的 car_P 上限约 0.12-0.13 (P6@4000)，而 Full 在 1.71 epochs 后已达到 0.090 且仍在上升。

**永久规则 #5 (不从 mini 做架构决策) 再次确认。**

---

## Q4: BUG-17 严重性重评

**从 CRITICAL 降为 HIGH。**

| 之前 | 之后 | 理由 |
|------|------|------|
| CRITICAL | **HIGH** | Plan Q 证明类竞争无关 car_P。BUG-17 的危害限于 bg_FA 膨胀和训练不稳定，不影响核心指标。|

BUG-17 仍需修复，但优先级低于 deep supervision 和方案 D:
- bg_FA=0.331 中有相当部分由 BUG-17 贡献
- bicycle/cone 的周期性振荡浪费训练资源
- 但这些不是 car_P 的障碍

**建议修复时机**: ORCH_024 结束后的第二轮实验 (与 deep supervision 或方案 D 同时)。

---

## Q5: 优先级调整

### 更新优先级排序

| 排名 | 提案 | 理由 |
|------|------|------|
| 1 | **Deep Supervision** | 零代码修改, 可能改善 BUG-15 (DINOv3→BEV 信息瓶颈) |
| 2 | **方案 D (历史 occ 2帧)** | 多帧信息是 BEV 投影精度的根本改善 |
| 3 | **方案 E (LoRA)** | 微调 DINOv3 可能改善特征质量 → 缓解 BUG-15 |
| 4 | **BUG-17 修复** (从 #3 降到 #4) | 类竞争无关 car_P, 优先级下降 |
| 5 | **Attention Mask** | 不变 |

**新增方向**: 调查 BUG-15 (Precision 瓶颈) 的根因。Plan Q 排除了类竞争，候选缩小到:
- DINOv3→BEV 投影层信息瓶颈
- BEV per-cell 评估方法的系统性偏差 (BUG-18)
- proj_z0 高度假设

---

## 发现的问题

无新 BUG。本次审计更新 BUG-17 严重性 (CRITICAL→HIGH) 并缩小 BUG-15 候选范围。

## 逻辑验证

- [x] Plan Q 与 P6 都有 proj 随机初始化 → 公平对比
- [x] Plan Q (单类+GELU) < P2 (10类+GELU): 0.083 < 0.112
- [x] Full@6000 > Plan Q@best: 0.090 > 0.083 (数据量优势)
- [x] Plan Q @2500 是 best → 非训练不足

## 对 Conductor 计划的评价

1. 实验设计正确: 单类 vs 多类是直接的消融实验
2. 判定标准合理: <0.12 = 类竞争无关
3. 分析质量高: 正确识别 proj random init 为混淆因素
4. 战略问题提出清晰: Q2-Q5 覆盖了所有必要的后续推理

## 附加建议

1. **不要再跑 Mini 实验**: Plan Q 是 Mini 阶段的收官实验。所有后续验证应在 Full nuScenes 上进行。
2. **BUG-15 需要专项调查**: 排除类竞争后，precision 瓶颈的根因需要系统性分析。建议 ORCH_024 @8000 后安排一次 BUG-15 专项审计。
3. **ORCH_024 继续训练**: Plan Q 结果不改变 ORCH_024 的训练策略。@8000 决策矩阵仍适用。

---

*Critic 签发 | 2026-03-09*
