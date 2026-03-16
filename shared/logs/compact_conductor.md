# Conductor 上下文快照
> 时间: 2026-03-16 02:16 CDT
> 原因: 为恢复自动 Conductor 前手动同步当前对话状态

---

## 当前状态

- **all_loops 已手动停止**
  - 原因: 自动循环与当前 `agent-conductor` 人工对话共用同一会话，会把当前对话打断
  - 后续恢复方向: 使用独立 `agent-conductor-auto` 会话承接自动 Phase 1/Phase 2
- **当前人工 Conductor 继续负责决策**
- **已创建** `agent-conductor-auto` tmux 会话，但尚未正式投入稳定自动循环

## 训练主线

### ORCH_049

- **状态**: RUNNING
- **work_dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch049`
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/nohup_orch049.out`
- **自动检查日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/auto_frozen_check_049.log`

### ORCH_049 已确认生效的 config 修改

- `marker_pos_punish=1.0`
- `bg_balance_weight=5.0`
- `around_weight=0.0`
- `grid_assign_mode='center'`
- `RandomFlipBEV only`
- `prefix_drop_rate=0.5`

### ORCH_049 @200 frozen-check

- Avg positive slots: **565/1200**
- Positive IoU: **0.9520**
- Marker same rate: **0.9755**
- Coord diff: **0.016052**
- Saturation: **0.487**
- TP total (5 samples): **112**
- 可视化: `shared/logs/VIS/049_iter200_frozen_check/`

### 当前判断

- `BUG-73` 已实际修复，但 **不是唯一主因**
- `marker_same` 几乎未降，说明 **BUG-75 (`grid_pos_embed` 空间模板 shortcut)** 仍是主阻断项
- 但 TP 明显上升，因此 **允许 ORCH_049 继续跑到 @500**
- **不在 @200 提前停训**
- 一旦 `@500` 失败，不再继续调 fg/bg 权重，直接转向 `ORCH_050`

## 下一步预案

### DRAFT_ORCH_050

- 文件: `shared/logs/DRAFT_ORCH_050.md`
- 状态: **DRAFT，不在 pending/，不会被 sync_loop 自动投递**
- 触发条件: **仅当 ORCH_049 @500 frozen-check 失败时转正**

### ORCH_050 核心方向

- **不要删除** `grid_pos_embed`
- **只在训练时、只对 marker step (`pos_id=0`) 做 `grid_pos_embed dropout`**
- 首版建议 dropout 概率: `0.3 ~ 0.5`
- 继续保留:
  - `RandomFlipBEV only`
  - `grid_assign_mode='center'`
  - `around_weight=0.0`
  - `prefix_drop_rate=0.5`

### 早停规则修正建议

- 现有 ORCH_049 @200 gate 太宽:
  - `marker_same > 0.95 AND saturation > 0.90`
- 下一版建议改严为单指标/OR 触发，例如:
  - `marker_same > 0.97` → STOP
  - 或 `Positive IoU > 0.95` → STOP
  - 或 `Saturation > 0.90` → STOP

## 审计与计划状态

- `VERDICT_ORCH049_MARKER_PATH` 已吸收并归档到 `shared/audit/processed/`
- `MASTER_PLAN.md` 已更新:
  - 记录 `ORCH_049 @200` 观察
  - 记录 `ORCH_050` 预备方向
- `ORCH_049` 已签发并处于 `DELIVERED`

## 恢复指令

如果后续要恢复自动 Conductor：

1. 先读本文件 `shared/logs/compact_conductor.md`
2. 再读 `MASTER_PLAN.md`
3. 再查:
   - `/mnt/SSD/GiT_Yihao/Train/Train_20260316/auto_frozen_check_049.log`
   - `shared/logs/DRAFT_ORCH_050.md`
4. 只有确认自动会话与人工会话分离后，再重新启动 `all_loops`
