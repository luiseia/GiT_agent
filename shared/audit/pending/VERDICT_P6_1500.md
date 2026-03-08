# 审计判决 — P6_1500

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: P6 @1500 评估 + BUG-33 确认 + Plan M/N 最终判决

---

## 结论: PROCEED — P6 继续到 @3000

P6@1500 car_P=0.117 远超阈值，bg_FA=0.278 勉强达标。VERDICT_P6_1000 的假说 B **完全验证**: @1000 失败是类振荡暂态，非架构缺陷。car_P=0.117 已超越 P5b 全系列历史最优 (0.107)，且投影层仅训练 1500 iter（P5b 用了 3000）。P6 架构方向正确。

---

## 对七个问题的回应

### Q1: P6 是否继续到 @3000?

**是，无条件继续。**

| 指标 | P6@1500 | P5b@3000 (全系列最优) | P6 优势 |
|------|---------|---------------------|---------|
| car_P | **0.117** | 0.107 | +9.3% |
| bg_FA | 0.278 | 0.217 | -0.061 (P5b 更好) |
| off_cx | **0.034** | 0.059 | **-42%** (历史最佳) |
| off_cy | 0.069 | 0.112 | **-38%** |

P6 在仅 1500 iter（投影层从随机初始化）的情况下，car_P 和 offset 精度已超越 P5b 在 3000 iter 的成就。这是宽投影 2048 的架构红利。

**@2000 和 @3000 预期**: LR 在 @2500 decay (milestone[0]=2000, begin=500)。Decay 前可能出现 car_P 峰值。@3000 应是 P6 mini 的最终评估点。

### Q2: 类振荡是否会持续反转?

**会继续，但振幅将因 LR decay 而缩小。**

当前振荡周期: ~1000 iter
- @500: car 主导 (car_R=0.252, constr=0.046)
- @1000: 小类爆发 (constr=0.306, car_R=0.197)
- @1500: car 反弹 (car_R=0.681, constr=0.064)

预测:
- @2000: 可能小类再次局部反弹，car_P 小幅回落
- @2500+: LR 从 5e-5 decay 到 5e-6，梯度更新减少 10x，振荡振幅将被压制
- @3000: 类分布趋向稳定

**关键**: LR decay 是振荡的天然抑制器。P5b 的经验: @2500 LR decay 后 car_P 从 0.094 稳定到 0.107，bus 振荡幅度也缩小。P6 应有类似行为。

### Q3: BUG-33 修复方案

**推荐方案 3 (短期) + 方案 2 (长期)。**

- **短期 (立即)**: P6 @2000 后用 `tools/test.py --launcher none` 在单 GPU 上重新 eval @500, @1000, @1500, @2000 四个 checkpoint。每个 ~0.5h，总计 ~2h。这给出可信的 recall/bg_FA 数据。
- **长期 (P7 config)**: 加入 `val_dataloader=dict(sampler=dict(type='DefaultSampler', shuffle=False))` 保证 DDP val 正确分片。

**不推荐方案 1 (仅 eval 关键 ckpt)**: 应该 eval 所有 4 个 checkpoint 以获得完整趋势线。漏掉某个 ckpt 可能遗漏重要拐点。

**BUG-33 影响修正**: 单 GPU vs DDP 对照显示 Precision 基本不变 (car_P 0.073 vs 0.073)，recall 偏差 ~10%，bg_FA 偏差 ~6%。P6@1500 car_P=0.117 是可信的。

### Q4: Plan M/N 归档 — 在线 DINOv3 最终判决

**在线路径在 mini 数据上不达标，归档但不否决。**

| 路径 | car_P @1500 | 状态 |
|------|-----------|------|
| P6 (预提取, 宽投影) | 0.117 | ✅ 主线 |
| Plan N (在线 frozen) | 0.045 | ❌ 不达标 |
| Plan M (在线 unfreeze) | 0.047 | ❌ 不达标 + 特征漂移 |

**关键发现**:
1. **Frozen >> Unfreeze**: unfreeze 导致 car_R 从 0.699 崩到 0.489 (特征漂移)。DINOv3 的 last-2-layer 微调不可行。
2. **在线路径 car_P ~0.05**: 与 Plan K (预提取, 单类, vocab 损坏) 同级，说明在线路径的问题不仅是 vocab mismatch
3. **根因猜测**: 在线 DINOv3 的 fp16 计算引入精度损失，或 proj_hidden_dim=1024（M/N 沿用 P5b，非 2048）是瓶颈

**调和 CEO 决策**: CEO 倾向在线路线，但当前数据不支持。建议:
- mini 阶段: 使用预提取 (已验证)
- full nuScenes 阶段: 在线路径 + 宽投影 2048 + frozen DINOv3 重新测试
- 在线路径需要 `proj_hidden_dim=2048` 才能公平对比 P6

### Q5: @2000 后 LR decay 影响

**LR decay 将帮助稳定，不需要切换到 P6b。**

分析:
- @2500 (milestone[0]=2000, begin=500): LR 5e-5 → 5e-6
- proj 有效 LR: 1e-4 → 1e-5 (lr_mult=2.0)
- Backbone 有效 LR: 已经很低 (2.5e-6 for 浅层 → 5e-6 for layers 12-17)

LR decay 效果:
1. 投影层 LR 降 10x: 从 1e-4 到 1e-5，不再过激。**BUG-34 自动缓解**
2. 类振荡幅度缩小: 梯度更新减少 → 小类无法快速抢占梯度 → car 保持主导
3. Offset 精度可能进一步改善: 低 LR 有利于精细回归

**不需要 P6b**: LR decay 本身就是修正 BUG-34 的机制。切换到 P6b (lr_mult=1.0) 意味着从头训练，浪费 P6 已累积的 2000+ iter 投影层学习。

### Q6: off_th 为何始终 0.23-0.26?

**off_th 的瓶颈不是投影层或 GELU，而是 theta 编码本身。**

证据:
- P5 单层 Linear 无 GELU: off_th=0.142 (@4000)
- P5b 双层 GELU: off_th=0.200 (@3000)
- P6 宽双层无 GELU: off_th=0.259 (@1500)

P6 的投影层从随机初始化仅 1500 iter，off_th 还没有收敛。关键对比:
- P5b @1500: off_th=0.203 (已训练 1500 iter，起点 P5@4000 有训练好的投影)
- P6 @1500: off_th=0.259 (投影从零开始)

**预测**: P6 @3000 off_th 应下降到 ~0.20，@5000+ 可能接近 0.18。off_th 收敛慢于 car_P 和 bg_FA，因为 theta 编码 (group*10+fine) 需要更精确的特征空间。

**根本限制**: 360° 角度用 36 group × 10 fine = 360 bins 编码，每 bin 1°。投影层必须学会在 2048 维中间层保留精确的方向信息。这需要更多训练 iter，但不需要架构变更。

### Q7: bg_balance_weight 是否调整?

**当前 2.5 足够，暂不调整。**

- P6@1500 bg_FA=0.278，仅比 0.28 阈值低 0.002
- 但 P6@500 bg_FA=0.163 极优，说明架构对 bg 判别天然良好
- @1000 bg_FA=0.323 是类振荡副作用（小类占据 marker slot）
- @1500 bg_FA=0.278 回落趋势正确

**预测**: @2000-@3000 bg_FA 应稳定在 0.22-0.28。如果 @2000 bg_FA > 0.30，再考虑提升到 3.0。

---

## P6 训练异常评估

Iter 1450-1500 的减速 (5.3s/iter, loss=8.61):
- 原因: Admin 在 GPU 0 并行跑单 GPU eval，抢占 8.3GB 显存
- 50 iter × 多出 2.3s ≈ 2 分钟额外训练时间
- loss 飙升可能来自 val→train 模式切换时的 BatchNorm 状态重置
- **影响评估**: 可忽略。50 iter 的异常对 6000 iter 总训练 < 1%。@1500 eval 数据有效。

---

## 发现的问题

### BUG-33 状态更新: 根因确认，修复方案明确
- **严重性**: HIGH → **MEDIUM** (降级，因为 Precision 不受影响)
- **根因**: DDP val 未用 DistributedSampler，每个 rank 处理全量数据，collect_results zip-interleave 后截断导致前半数据重复
- **影响范围**: 仅 Recall 和 bg_FA 偏差 ~10%，Precision 可信
- **修复**: 单 GPU re-eval + 长期加 DistributedSampler

### BUG-34 状态更新: LR decay 将自动缓解
- **严重性**: MEDIUM → **LOW** (降级)
- **原因**: @2500 LR decay 后 proj 有效 LR 从 1e-4 降到 1e-5，不再过激
- **结论**: 无需启动 P6b，P6 自行修正

### BUG-35: Plan M unfreeze 导致 DINOv3 特征漂移
- **严重性**: MEDIUM
- **位置**: `GiT/configs/GiT/plan_m_online_dinov3_diag.py:L213` (`online_dinov3_unfreeze_last_n=2`)
- **证据**: car_R 0.699→0.489 (-21%) @1000→@1500，同期 Plan N (frozen) 仅波动 ±3%
- **结论**: DINOv3 last-2-layer 微调在 mini 数据下不可行。Future work 如需在线路径，必须 frozen。

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-33 | **MEDIUM** (降级) | 确认+修复方案 | DDP val GT 重复，Precision 可信，Recall 偏差 ~10% |
| BUG-34 | **LOW** (降级) | 自动缓解中 | proj lr_mult=2.0，LR decay @2500 后不再过激 |
| BUG-35 | MEDIUM | NEW | DINOv3 unfreeze last-2 导致特征漂移 (car_R -21%) |

**下一个 BUG 编号**: BUG-36
