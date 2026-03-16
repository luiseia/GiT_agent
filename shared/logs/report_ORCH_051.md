# ORCH_051 执行报告

- **状态**: COMPLETED (EARLY STOP @200 — 全正饱和)
- **执行者**: Admin Agent
- **时间**: 2026-03-16 03:27 — 04:00

## 代码修改

### Config (`plan_full_nuscenes_large_v1.py`)
- **唯一改动**: `marker_grid_pos_dropout` 0.5→0.0
- 其余与 ORCH_050 完全一致: marker_pos_punish=2.0, bg_balance_weight=3.0, around_weight=0.0

### GiT Commit
- `d3095f1` — config: ORCH_051 disable grid_pos_dropout, keep FG/BG=3.3x

## @200 Frozen Check 结果 (EARLY STOP)

```
Checkpoint: iter_200.pth
Samples checked: 5

  Avg positive slots: 1200/1200 (100.0%)
  Positive IoU (cross-sample): 1.0000
  Marker same rate: 0.9970
  Coord diff (shared pos): 0.021147
  Saturation: 1.000

  VERDICT: 🔴 FROZEN PREDICTIONS DETECTED
  EARLY STOP: marker_same=0.997>0.97 AND saturation=1.000>0.90
```

| Sample | GT | Pred | TP | FP | FN |
|--------|-----|------|----|----|-----|
| 0 | 5 | 1200 | 7 | 393 | 0 |
| 1 | 10 | 1200 | 71 | 329 | 0 |
| 2 | 5 | 1200 | 27 | 373 | 0 |
| 3 | 17 | 1200 | 34 | 366 | 0 |
| 4 | 25 | 1200 | 38 | 362 | 0 |

TP=177 (全系列最高), 但因为 1200/1200 全正, FN=0, FP 极高。

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| marker_grid_pos_dropout=0.0 | config 可见 | ✅ | PASS |
| 其余与 050 一致 | 一致 | ✅ | PASS |
| iter_200 frozen check | 已执行 | ✅ | PASS |
| saturation 0.10~0.80 | 中间态 | **1.000** (全正) | **FAIL** |
| marker_same < 0.95 | 低于阈值 | 0.997 | **FAIL** |

**总体: FAIL** — 全正饱和, 与 ORCH_047 同类问题。

## 变量隔离结论 (本轮核心价值)

| ORCH | FG/BG | dropout | @200 saturation | @200 TP | 模式 |
|------|-------|---------|-----------------|---------|------|
| 049 | 1x | 0 | 0.487 | 112 | **中间态 ✓** |
| 050 | 3.3x | 0.5 | 0.000 | 0 | 全背景 |
| **051** | **3.3x** | **0** | **1.000** | **177** | **全正** |

**FG/BG=3.3x 是全正坍塌的直接原因**:
- 无 dropout: 3.3x 推向全正 (1200/1200)
- 有 dropout: 3.3x + dropout 的对抗效果矫枉过正 → 全背景 (0/1200)
- FG/BG=1x 是目前唯一能产生中间态的配置

## 可视化
- iter_200: `/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/051_iter200_frozen_check/`

## Work Dir
`/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch051`
