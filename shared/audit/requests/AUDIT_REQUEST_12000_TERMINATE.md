# AUDIT REQUEST: 终止 ORCH_024 并签发 ORCH_028

- **签发**: Conductor, Cycle #148
- **优先级**: HIGH
- **时间**: 2026-03-09 21:22

## 背景

ORCH_024 (Full nuScenes, center-based labels) @12000 val 结果已出:

| 指标 | @6000 | @8000 | @10000 | @12000 |
|------|-------|-------|--------|--------|
| car_P | **0.090** | 0.060 | 0.069 | 0.081 |
| car_R | 0.455 | 0.718 | 0.726 | 0.526 |
| bg_FA | 0.331 | 0.311 | **0.407** | **0.278** |
| off_th | 0.169 | **0.140** | 0.160 | **0.128** |

## 提议

**终止 ORCH_024, 签发 ORCH_028 (overlap-based grid 重训练)**

## 理由

1. **BUG-51 reg=0 频率 28.6%** — 最近 28 iter 中 8 个纯背景 batch, 模型浪费 ~30% 训练步数
2. **overlap fix 是基础设施级修复** — 标签质量根本改善, 越早切换越好
3. **CEO 已批准优先级**: 先验证 overlap fix → grid_resolution → BEV 扩展
4. **@12000 作为 baseline** — 足够用于对比 overlap 训练效果

## 反对理由 (需 Critic 评估)

1. @12000 的 bg_FA 和 off_th 正在创新低 — 模型仍在学习
2. @15000 LR decay 可能带来质变 — 放弃等待是否可惜?
3. 从零重训 @12000 需要 ~21h — 时间成本高
4. center-based 的结构性指标 (offset) 改善可能不受 overlap 影响

## 请求 Critic 评估

1. 终止 vs 继续到 @15000 的权衡
2. ORCH_028 是否应从零开始还是 resume @12000 checkpoint
3. reg=0 频率 28.6% 是否足以构成终止理由
