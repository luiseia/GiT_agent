# ORCH_050 执行报告

- **状态**: COMPLETED (EARLY STOP @200 — 全背景坍塌)
- **执行者**: Admin Agent
- **时间**: 2026-03-16 02:45 — 03:19

## 代码修改

### Config (`plan_full_nuscenes_large_v1.py`)
- **BUG-76**: `marker_pos_punish` 1.0→2.0, `bg_balance_weight` 5.0→3.0
  - 新 FG/BG 比: (5×2.0)/(3.0×1.0) ≈ 3.3x (居于 049 的 1x 和 048 的 6x 之间)
- **BUG-75**: `marker_grid_pos_dropout=0.5` — 训练时 50% cells 置零 grid_pos_embed
- 保留: around_weight=0.0, prefix_drop_rate=0.5, RandomFlipBEV, grid_assign_mode='center'

### Code (`mmdet/models/detectors/git.py`)
- 新增 `marker_grid_pos_dropout` 参数
- 在 `forward_visual_modeling` 中实现 grid_pos_embed per-cell dropout:
  - 训练时 occ 任务, 以 50% 概率对每个 cell 的 grid_pos_embed 置零
  - 推理时不受影响

### 新脚本 (`scripts/auto_frozen_check_050.sh`)
- 更新早停规则为 OR 逻辑 + 全阴性检测 (saturation<0.05)

### GiT Commit
- `cc749d9` — fix: ORCH_050 BUG-76 FG/BG ratio + BUG-75 grid_pos_embed dropout

## 训练概况

- GPU: 2,3 (2×A6000), ~29 GB/GPU, ~3.7 sec/iter
- 训练到 iter_200 后被早停 kill

### Loss 行为
- **iter 10-30**: cls=3.6-2.4, reg=2.0-2.2 (从一开始就有 reg_loss，好于 049)
- **iter 40-130**: loss 降到 0.11, reg=0 (全背景期)
- **iter 140-160**: reg_loss 再次出现 (3.0, 2.9, 3.2), 振荡 spike
- **iter 170-200**: 回到全背景 (loss≈0.03, reg=0)
- **结论**: 与 049 相同的振荡模式，但最终稳定在全背景模式

## @200 Frozen Check 结果 (EARLY STOP)

```
Checkpoint: iter_200.pth
Samples checked: 5

  Avg positive slots: 0/1200 (0.0%)
  Positive IoU (cross-sample): 0.0000
  Marker same rate: 1.0000
  Coord diff (shared pos): 0.000000
  Saturation: 0.000

  VERDICT: 🔴 FROZEN PREDICTIONS DETECTED (marker_same)
  EARLY STOP: saturation=0.000 < 0.05 (all-negative)
```

所有 5 个样本: Pred=0, TP=0

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| marker_pos_punish=2.0 | config 可见 | ✅ | PASS |
| bg_balance_weight=3.0 | config 可见 | ✅ | PASS |
| marker_grid_pos_dropout=0.5 | config 可见 | ✅ | PASS |
| grid_pos_embed dropout 仅训练时 marker | 代码检查 | ✅ (训练时 occ 任务) | PASS |
| iter_200 frozen check | 已执行+数值 | ✅ | PASS |
| saturation 0.10~0.80 | 不陷入两极 | **0.000** (全背景) | **FAIL** |
| marker_same < 0.95 | 低于阈值 | 1.000 | **FAIL** |
| TP > 0 | 有检测 | 0 | **FAIL** |

**总体: FAIL** — 模型在 iter_200 时完全全背景坍塌，比 ORCH_049 @200 退步。

## 全系列对比

| ORCH | Iter | Pos slots | IoU | marker_same | saturation | TP | 状态 |
|------|------|-----------|-----|-------------|------------|-----|------|
| 047 | @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | 0 | FAIL (全正) |
| 048 | @500 | 482 (40%) | 0.946 | 0.977 | 0.426 | 27 | FAIL (marker固定) |
| 049 | @200 | 565 (47%) | 0.952 | 0.976 | 0.487 | 112 | FAIL (但TP最高) |
| 049 | @500 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景) |
| **050** | **@200** | **0 (0%)** | 0.000 | 1.000 | 0.000 | **0** | **FAIL (全背景, 早停)** |

## 关键诊断

1. **grid_pos_embed dropout 可能适得其反**: 在模型已经倾向全背景的情况下，去掉空间先验让模型更难找到正样本位置
2. **bg_balance_weight 从 5.0 降到 3.0 不够**: 模型仍然偏好全背景，FG/BG=3.3x 对于当前架构可能仍不足以推动正样本预测
3. **iter_200 vs iter_200 直接对比**:
   - 049@200: 47% positive, 112 TP → 050@200: 0% positive, 0 TP
   - 唯一区别: marker_pos_punish 1→2, bg_balance_weight 5→3, grid_pos_dropout 0→0.5
   - **grid_pos_dropout 是最可能的退步原因** — 去掉位置信息让 marker 无法定位有物体的 cell
4. **建议**:
   - 关闭 grid_pos_dropout (=0.0)
   - 保留 marker_pos_punish=2.0, bg_balance_weight=3.0
   - 或者恢复 049 的 marker_pos_punish=1.0 + bg_balance_weight=5.0 但保留 grid_pos_dropout

## 可视化
- iter_200: `/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/050_iter200_frozen_check/`

## Work Dir
`/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch050`
