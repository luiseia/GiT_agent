# Admin Agent 上下文快照
- **时间**: 2026-03-16 04:20
- **当前任务**: ORCH_052 训练运行中，等待双阶段 frozen check

---

## 当前训练状态

### ORCH_052 训练 (当前运行)
- **Config**: `plan_full_nuscenes_large_v1.py`
- **核心改动 (vs ORCH_051)**: marker_pos_punish 2.0→1.0, bg_balance_weight 保持 3.0
  - FG/BG = (5×1.0)/(3.0×1.0) = **1.67x** (介于 049 的 1x 和 051 的 3.3x 之间)
- **保留**: marker_grid_pos_dropout=0.0, around_weight=0.0, prefix_drop_rate=0.5, RandomFlipBEV, grid_assign_mode='center'
- **训练**: 从零, GPU 2,3 (2×A6000), ~29 GB/GPU, ~3.8 sec/iter
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch052`
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/nohup_orch052.out`
- **GiT commit**: `07659cb`
- **启动时间**: 04:04 CDT
- **当前进度**: iter 100, loss=0.32 (cls only, reg=0, 全背景期)
- **iter_200 预计**: ~04:27 CDT
- **iter_500 预计**: ~04:46 CDT

### 自动 Frozen Check 脚本
- 日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/auto_frozen_check_052.log`
- 早停规则 (OR 触发):
  - @200: marker_same>0.97 OR saturation>0.90 OR saturation<0.05
  - @500: IoU>0.95 OR marker_same>0.90 OR saturation>0.90 OR saturation<0.05
- 可视化: `shared/logs/VIS/052_iter{200,500}_frozen_check/`

### GPU 共享状况
- **GPU 0,1**: xg0091 StreamPETR (~40/43 GB)
- **GPU 2,3**: 我们的 ORCH_052 训练 (~29 GB/GPU)

---

## 本 Session 执行记录

### ORCH_049 (COMPLETED — FAIL)
- marker_pos_punish=1.0, bg_balance_weight=5.0, around_weight=0.0
- @200: pos=565 (47%), IoU=0.952, marker_same=0.976, sat=0.487, **TP=112** (全系列最高@200)
- @500: pos=0 (0%), sat=0.000, TP=0 (全背景坍塌)
- GiT commit: `6834922`

### ORCH_050 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=2.0, bg_balance_weight=3.0, **marker_grid_pos_dropout=0.5**
- @200: pos=0 (0%), sat=0.000, TP=0 (全背景, 早停)
- GiT commit: `cc749d9`

### ORCH_051 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=2.0, bg_balance_weight=3.0, marker_grid_pos_dropout=0.0
- @200: pos=1200 (100%), sat=1.000, TP=177 (全正饱和, 早停)
- GiT commit: `d3095f1`

### ORCH_052 (执行中)
- marker_pos_punish=1.0, bg_balance_weight=3.0, FG/BG=1.67x
- 训练运行中，等待 frozen check
- GiT commit: `07659cb`

---

## 变量隔离结论 (049-051 系列)

| ORCH | marker_pos_punish | bg_balance_weight | FG/BG | dropout | @200 sat | @200 TP | 模式 |
|------|-------------------|-------------------|-------|---------|----------|---------|------|
| 049 | 1.0 | 5.0 | 1x | 0 | 0.487 | 112 | 中间态 ✓ |
| 050 | 2.0 | 3.0 | 3.3x | 0.5 | 0.000 | 0 | 全背景 |
| 051 | 2.0 | 3.0 | 3.3x | 0 | 1.000 | 177 | 全正 |
| **052** | **1.0** | **3.0** | **1.67x** | **0** | **?** | **?** | **等待** |

- FG/BG=3.3x → 全正; dropout 矫枉过正 → 全背景; FG/BG=1x 是唯一中间态
- 052 测试 FG/BG=1.67x 是否能在 @200 保持中间态且 @500 不坍塌

---

## ORCH_052 验收标准

1. Config: marker_pos_punish=1.0, bg_balance_weight=3.0, marker_grid_pos_dropout=0.0
2. @200 frozen-check 执行
3. 期望 @200: TP>0, saturation 0.1-0.8 (类似 049@200)
4. **关键验证**: @500 是否避免全阴性崩塌
5. 失败即停

---

## Frozen Check 完整历史

| ORCH | Iter | Pos slots | IoU | marker_same | saturation | TP | 状态 |
|------|------|-----------|-----|-------------|------------|-----|------|
| 047 | @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | 0 | FAIL (全正) |
| 048 | @500 | 482 (40%) | 0.946 | 0.977 | 0.426 | 27 | FAIL (marker固定) |
| 049 | @200 | 565 (47%) | 0.952 | 0.976 | 0.487 | 112 | FAIL (TP最高@200) |
| 049 | @500 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景) |
| 050 | @200 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景早停) |
| 051 | @200 | 1200 (100%) | 1.000 | 0.997 | 1.000 | 177 | FAIL (全正早停) |
| **052@200** | — | — | — | — | — | — | **等待** |
| **052@500** | — | — | — | — | — | — | **等待** |

---

## 关键技术状态 (当前架构)

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: [5,11,17,23] → 4096 → 2048 → GELU → 1024
- 2 层 PreLN Transformer adaptation (25.2M, lr=5e-05)
- bert-large embedding (pretrained)
- pos_cls_w=1.0, neg_cls_w=1.0, marker_pos_punish=1.0
- bg_balance_weight=3.0, center_weight=1.0, around_weight=0.0
- prefix_drop_rate=0.5, marker_grid_pos_dropout=0.0
- RandomFlipBEV(0.5), grid_assign_mode='center', clip_grad=50

---

*Admin Agent 上下文快照 | 2026-03-16 04:20*
