# Conductor 上下文快照
> 时间: 2026-03-16 05:53 CDT

---

## 当前状态

- **ORCH_055 训练中** (2-GPU DDP, GPU 2,3) — 精确复现 ORCH_049 + 多点 frozen-check
- auto_frozen_check_055.sh 等待 iter_100.pth
- ORCH_053/054 因单 GPU 执行而无效 (BUG-78)

## ORCH_055 配置 (= ORCH_049 精确复现)

- `marker_pos_punish=1.0`, `bg_balance_weight=5.0` (FG/BG=1x)
- `marker_grid_pos_dropout=0.0`, `around_weight=0.0`
- `grid_assign_mode='center'`, `RandomFlipBEV only`, `prefix_drop_rate=0.5`
- **2-GPU DDP**: memory=28878, accumulative_counts=8, effective batch=16 ✅
- work_dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch055`

## 多点 frozen-check 计划

@100, @200, @300, @400, @500 — 仅 saturation>0.95 早停，全阴性允许继续
- 目标: 确认 @200 可复现 ORCH_049 的 TP=112，定位 @200→@500 崩塌轨迹

## FG/BG 扫描全表 (只看 2-GPU DDP 结果)

| ORCH | bg_balance_weight | FG/BG | @200 | 备注 |
|------|-------------------|-------|------|------|
| 048 | 2.5 | 6x | — | @500 all-positive |
| **049** | **5.0** | **1x** | **TP=112** | **唯一存活** → @500 all-neg |
| 050 | 3.0 + dropout | 3.3x | 0/1200 | dropout 致死 |
| 051 | 3.0 | 3.3x | 1200/1200 | all-positive |
| 052 | 3.0 | 1.67x | 0/1200 | all-negative |
| 053* | 4.0 | 1.25x | 0/1200 | *单GPU无效 |
| 054* | 5.0 | 1x | 0/1200 | *单GPU无效 |
| **055** | **5.0** | **1x** | **?** | 2-GPU DDP |

## BUG-78: 单 GPU vs DDP 训练差异

- ORCH_049 (DDP): effective batch=16 → TP=112
- ORCH_053/054 (单GPU): effective batch=1 → 全阴性
- 结论: batch size 对 mode collapse 有关键影响
