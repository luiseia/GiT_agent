# Conductor 上下文快照
> 时间: 2026-03-16 03:33 CDT

---

## 当前状态

- **ORCH_051 训练中** (GPU 2,3) — 隔离变量实验: FG/BG=3.3x, dropout=0
- auto_frozen_check_051.sh 等待 iter_200.pth
- ORCH_050 FAILED @200 (cell-level dropout 破坏定位, BUG-77)

## ORCH_051 配置

- `marker_pos_punish=2.0`, `bg_balance_weight=3.0` (FG/BG=3.3x)
- `marker_grid_pos_dropout=0.0` (**关闭**)
- `around_weight=0.0`, `grid_assign_mode='center'`, `RandomFlipBEV only`, `prefix_drop_rate=0.5`
- PID: 2377630 (rank0)
- GiT Commit: ORCH_051 config change on top of cc749d9
- work_dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch051`

## 全系列 @200 frozen-check 对比

| ORCH | FG/BG | dropout | Pos slots | marker_same | TP |
|------|-------|---------|-----------|-------------|-----|
| 048 | 6x | 0 | 482 (40%) | 0.977 | 27 |
| **049** | **1x** | **0** | **565 (47%)** | **0.976** | **112** |
| 050 | 3.3x | 0.5 cell | 0 (0%) | 1.000 | 0 |
| **051** | **3.3x** | **0** | **?** | **?** | **?** |

## 判断线索

- 若 051 @200 ≈ 049 @200 → dropout 确是主因，继续到 @500
- 若 051 @200 全阴性 → FG/BG=3.3x 也有问题，需降到 ~2x
- iter_200 预计 ~03:58 CDT

## CEO 指令已处理

- Instance consistency loss 建议 — Conductor 回复: 方向正确但等 mode collapse 解决后再做
