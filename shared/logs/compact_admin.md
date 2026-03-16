# Admin Agent 上下文快照
- **时间**: 2026-03-16 01:30
- **当前任务**: ORCH_049 训练运行中，等待双阶段 frozen check

---

## 当前训练状态

### ORCH_049 训练 (当前运行)
- **Config**: `plan_full_nuscenes_large_v1.py`
- **核心改动 (vs ORCH_048)**:
  - BUG-73 fix: `marker_pos_punish` 3.0→1.0, `bg_balance_weight` 2.5→5.0
  - `around_weight` 0.1→0.0 (完全关闭外围 supervision)
  - checkpoint interval=100, val_interval=99999 (禁用 auto-val)
- **保留**: RandomFlipBEV, grid_assign_mode='center', prefix_drop_rate=0.5, core/around framework
- **训练**: 从零, GPU 2,3 (2×A6000), ~29 GB/GPU, ~3.8 sec/iter
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch049`
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/nohup_orch049.out`
- **GiT commit**: `6834922`
- **启动时间**: 01:27 CDT
- **初始指标**: loss=13.2, grad_norm=215 @ iter 10
- **iter_200 预计**: ~01:40 CDT
- **iter_500 预计**: ~01:59 CDT

### 自动 Frozen Check 脚本
- PID: 2283884 (`scripts/auto_frozen_check_049.sh`)
- 日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/auto_frozen_check_049.log`
- 逻辑:
  1. 等 iter_200.pth → 运行 quick frozen check (GPU 2)
  2. **早停**: marker_same>0.95 AND saturation>0.90 → kill
  3. 等 iter_500.pth → kill 训练 → 运行 full frozen check (GPU 0)
  4. 输出到 `shared/logs/VIS/049_iter{200,500}_frozen_check/`

### GPU 共享状况 (已变化!)
- **GPU 0**: xg0091 StreamPETR VGGT (~21 GB) — 新用户，01:14 开始
- **GPU 1**: xg0091 StreamPETR VGGT (~16 GB) — 新用户
- **GPU 2,3**: 我们的 ORCH_049 训练 (~29 GB/GPU)
- 注意: GPU 0 不再空闲，ORCH_049 首次启动因 OOM 崩溃，已改用 GPU 2,3

---

## 本 Session 执行记录

### ORCH_046 (COMPLETED)
- BUG-69 fix (adapt_layers lr_mult=1.0) + BUG-62 fix (clip_grad=50)
- 训练被 CEO 终止，改用 bert-large
- GiT commits: `db4bd08`, `92c79ca`

### ORCH_047 (COMPLETED)
- RandomFlipBEV + GlobalRotScaleTransBEV 实现
- @500 frozen check: **FAIL** (IoU=1.0, 1200/1200 全正饱和)
- GiT commit: `3fc2e3e`

### ORCH_048 (COMPLETED)
- core/around weights + prefix dropout + rebalance pos/neg
- @500 frozen check: **部分 PASS** (IoU=0.946<0.95, 但 marker_same=0.977>0.90)
- 关键突破: 饱和 100%→42.6%, 首次出现 TP
- GiT commit: `33fbb4d`

### ORCH_049 (执行中)
- BUG-73: marker_pos_punish=1.0, bg_balance_weight=5.0, around_weight=0.0
- 训练运行中，等待 frozen check
- GiT commit: `6834922`

---

## ORCH_049 验收标准

### iter_200 早停门槛:
- marker_same > 0.95 AND saturation > 0.90 → 立即停训

### iter_500 验收:
1. marker_same 明显低于 0.9767 (ORCH_048 值)
2. Positive IoU 不高于 0.9459
3. 任一 frozen 条件 (IoU>0.95 或 marker_same>0.90 或 saturation>0.90) → 停训

---

## Frozen Check 历史

| ORCH | Pos slots | IoU | marker_same | saturation | 状态 |
|------|-----------|-----|-------------|------------|------|
| 047 @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | FAIL (全正) |
| 048 @500 | 482 (40%) | 0.946 | 0.977 | 0.426 | FAIL (marker固定) |
| **049 @200** | ??? | ??? | ??? | ??? | **等待** |
| **049 @500** | ??? | ??? | ??? | ??? | **等待** |

---

## 关键技术状态 (当前架构)

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: [5,11,17,23] → 4096 → 2048 → GELU → 1024
- 2 层 PreLN Transformer adaptation (25.2M, lr=5e-05)
- bert-large embedding (pretrained)
- **pos_cls_w=1.0, neg_cls_w=1.0, marker_pos_punish=1.0** (fully rebalanced)
- **bg_balance_weight=5.0** (强背景信号)
- **center_weight=1.0, around_weight=0.0** (只监督中心 cell)
- **prefix_drop_rate=0.5** (prefix dropout)
- RandomFlipBEV(0.5), grid_assign_mode='center', clip_grad=50

---

*Admin Agent 上下文快照 | 2026-03-16 01:30*
