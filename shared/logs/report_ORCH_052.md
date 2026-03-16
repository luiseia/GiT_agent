# ORCH_052 执行报告

- **状态**: COMPLETED (EARLY STOP @200 — 全背景坍塌)
- **执行者**: Admin Agent
- **时间**: 2026-03-16 04:04 — 04:36

## 代码修改

### Config (`plan_full_nuscenes_large_v1.py`)
- **唯一改动**: `marker_pos_punish` 2.0→1.0（从 ORCH_051 回到 ORCH_049 值）
- 其余与 ORCH_051 完全一致: bg_balance_weight=3.0, marker_grid_pos_dropout=0.0, around_weight=0.0

### GiT Commit
- `07659cb` — config: ORCH_052 marker_pos_punish=1.0 for FG/BG=1.67x

## @200 Frozen Check 结果 (EARLY STOP)

```
Checkpoint: iter_200.pth
Samples checked: 5

  Avg positive slots: 0/1200 (0.0%)
  Positive IoU (cross-sample): 0.0000
  Marker same rate: 1.0000
  Coord diff (shared pos): 0.000000
  Saturation: 0.000

  VERDICT: 🔴 FROZEN PREDICTIONS DETECTED
  EARLY STOP: saturation=0.000<0.05 AND marker_same=1.000>0.97
```

| Sample | GT | Pred | TP | FP | FN |
|--------|-----|------|----|----|-----|
| 0 | 5 | 0 | 0 | 0 | 7 |
| 1 | 10 | 0 | 0 | 0 | 71 |
| 2 | 5 | 0 | 0 | 0 | 27 |
| 3 | 17 | 0 | 0 | 0 | 34 |
| 4 | 25 | 0 | 0 | 0 | 38 |

## 训练 Loss 模式

| Iter | loss_cls | loss_reg | 阶段 |
|------|----------|----------|------|
| 10 | 5.97 | 1.88 | 初始 |
| 40 | 0.81 | 0.00 | 全背景开始 |
| 130 | 0.16 | 0.00 | 全背景 |
| 140 | 0.73 | **2.96** | reg 短暂回升 |
| 150 | 1.65 | 3.11 | reg 持续 |
| 160 | 6.90 | 3.25 | 震荡 |
| 200 | — | — | @200 全背景 (TP=0) |

训练 iter 140-160 曾短暂出现 reg_loss，但到 iter 200 已回落为全背景。

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| marker_pos_punish=1.0 | config 可见 | ✅ | PASS |
| bg_balance_weight=3.0 | config 可见 | ✅ | PASS |
| marker_grid_pos_dropout=0.0 | config 可见 | ✅ | PASS |
| iter_200 frozen check | 已执行 | ✅ | PASS |
| saturation 0.10~0.80 | 中间态 | **0.000** (全背景) | **FAIL** |

**总体: FAIL** — 全背景坍塌, 与 ORCH_050 同类问题。

## 关键发现: FG/BG 比假设被推翻

| ORCH | marker_pos_punish | bg_balance_weight | FG/BG | @200 sat | @200 TP | 模式 |
|------|-------------------|-------------------|-------|----------|---------|------|
| 049 | 1.0 | **5.0** | 1x | 0.487 | 112 | **中间态 ✓** |
| 050 | 2.0 | 3.0 | 3.3x | 0.000 | 0 | 全背景 (+ dropout) |
| 051 | 2.0 | 3.0 | 3.3x | 1.000 | 177 | 全正 |
| **052** | **1.0** | **3.0** | **1.67x** | **0.000** | **0** | **全背景** |

**FG/BG 比不是唯一决定因素**:
- 052 (FG/BG=1.67x) 应该比 049 (FG/BG=1x) 更倾向正预测，却坍塌为全背景
- 049 vs 052 的真正差异: **bg_balance_weight 5.0 vs 3.0**
- 可能 bg_balance_weight 的绝对值（不仅仅是比例）对训练动态有独立影响
- 或者训练结果对随机种子/数据顺序非常敏感

## 可视化
- iter_200: `/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/052_iter200_frozen_check/`

## Work Dir
`/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch052`
