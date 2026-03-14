# AUDIT REQUEST: GiT-Large v1 @4000 全面审计

- **签发时间**: 2026-03-14 10:42
- **签发人**: Conductor
- **优先级**: P0 — 硬决策点触发
- **触发条件**: @4000 决策树 → car_R=0 + offset 恶化 → 🚨🚨 全面审计

## 审计问题

### Q1: 分类器是否能在后续训练中激活？
- @4000 仍有 9/10 类 recall=0 (仅 pedestrian_R=0.0245)
- ORCH_024 (ViT-Base) @4000 已有 car_R=0.419
- GiT-Large v1 随机初始化参数更多 (bert_embed 1024-dim + layers 24-29)，是否合理需要更多 iter？

### Q2: bg_FA 上升是正面信号还是噪声？
- bg_FA: 0.002 (@2000) → 0.115 (@4000) — 模型开始预测前景
- 但几乎所有前景预测都是错误的 (precision ≈ 0)
- 这说明模型在学习"非背景"概念，还是随机预测？

### Q3: Offset 恶化如何解读？
- off_th: 0.078 → 0.212, off_cx: 0.106 → 0.193, off_cy: 0.029 → 0.141
- off_w 改善: 0.070 → 0.037
- @2000 时 bg_FA=0.002（几乎无前景预测），offset 基于极少样本
- @4000 前景预测数量大增，是否是样本量变化导致的统计偏差？

### Q4: BUG-61 升级是否影响训练质量？
- iter 3270: reg_loss=0 (孤立)
- iter 3520: reg_loss=0, grad_norm=177
- iter 3660-3670: reg_loss=0, grad_norm≈0 (连续 2 iter)
- iter 3870: reg_loss=0
- iter 3960: reg_loss=0, grad_norm=6.6
- **iter 3980-3990: ALL loss=0, grad_norm=0 (全零，前所未有)**
- iter 4030: reg_loss=0 (eval后立刻又出现)
- 频率和严重度均在增加

### Q5: 是否应该 STOP 训练？
决策树建议 STOP，但考虑：
- 模型确实在学习（bg_FA 上升、ped_R 激活、off_w 改善）
- 大模型冷启动慢可能是正常的
- STOP 后需要重新设计或等待更长时间验证

## 参考数据

### @4000 vs @2000 vs ORCH_024

| 指标 | @2000 | @4000 | ORCH_024 @4000 |
|------|-------|-------|----------------|
| car_R | 0.000 | 0.000 | 0.419 |
| ped_R | 0.000 | 0.025 | — |
| bus_R | 0.002 | 0.000 | — |
| bg_FA | 0.002 | 0.115 | — |
| off_cx | 0.106 | 0.193 | 0.039 |
| off_cy | 0.029 | 0.141 | — |
| off_w | 0.070 | 0.037 | — |
| off_th | 0.078 | 0.212 | 0.150 |

### 训练配置
- Config: `plan_full_nuscenes_large_v1.py`
- 架构: GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen
- 数据增强: PhotoMetricDistortion (P0 fix)
- Train/test 分离: ✅ (P0 fix)
- Checkpoint: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/iter_4000.pth`

## 期望判决
- PROCEED / CONDITIONAL PROCEED / STOP
- 如 PROCEED: 下一个检查点建议
- 如 STOP: 建议的修复方向
