# Conductor 上下文快照
> 时间: 2026-03-16 02:50 CDT
> 原因: ORCH_050 已启动，记录最新状态

---

## 当前状态

- **ORCH_050 训练中** (GPU 2,3)
- auto_frozen_check_050.sh 在等待 iter_200.pth
- all_loops 运行中

## 训练主线

### ORCH_050

- **状态**: RUNNING
- **work_dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch050`
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/nohup_orch050.out`
- **自动检查日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/auto_frozen_check_050.log`
- **PID**: 2364079 (rank0), 2364080 (rank1)
- **GiT Commit**: `cc749d9`

### ORCH_050 已确认生效的 config 修改

- `marker_pos_punish=2.0` (BUG-76 fix: FG/BG 从 1x 调至 ~3.3x)
- `bg_balance_weight=3.0`
- `marker_grid_pos_dropout=0.5` (BUG-75 fix: cell 级 grid_pos_embed dropout)
- `around_weight=0.0`
- `grid_assign_mode='center'`
- `RandomFlipBEV only`
- `prefix_drop_rate=0.5`

### 注意: grid_pos_embed dropout 实现偏差

- Spec 要求: 仅对 marker step (pos_id=0) dropout
- 实际实现: 整 cell 级 dropout (所有 token 共享，包括 box 回归 token)
- 原因: grid_pos_embed 在代码中是 cell 级属性，在 per-token 处理之前注入
- 风险: 可能影响 offset 回归质量
- 验证: frozen-check @200/@500 将显示影响

### ORCH_049 最终结论

- @200: positive=565/1200, marker_same=0.9755, TP=112 (所有实验最高)
- @500: positive=0/1200, marker_same=1.000, TP=0 — **全阴性崩塌**
- 根因: FG/BG=1x (marker_pos_punish=1.0, bg_balance_weight=5.0) 矫枉过正
- Admin 确认: iter_200 是 ORCH_049 峰值，BUG-73 fix 方向正确

### FG/BG 比历史

| ORCH | marker_pos_punish | bg_balance_weight | FG/BG | 结果 |
|------|-------------------|-------------------|-------|------|
| 048 | 3.0 | 2.5 | 6x | all-positive |
| 049 | 1.0 | 5.0 | 1x | all-negative |
| **050** | **2.0** | **3.0** | **3.3x** | **待验证** |

### 早停规则 (ORCH_050)

@200 (OR 触发):
- marker_same > 0.97 → STOP
- saturation > 0.90 → STOP (all-positive)
- saturation < 0.05 → STOP (all-negative, 新增)

@500 (OR 触发):
- Positive IoU > 0.95 → STOP
- Marker same > 0.90 → STOP
- Saturation > 0.90 / < 0.05 → STOP

## 审计状态

- VERDICT_ORCH048_PLAN 已归档
- 无活跃审计请求

## 恢复指令

1. 先读本文件
2. 再读 `MASTER_PLAN.md`
3. 再查: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/auto_frozen_check_050.log`
