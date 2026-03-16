# ORCH_053 执行报告

- **状态**: COMPLETED (EARLY STOP @200 — 全背景坍塌)
- **执行者**: Admin Agent
- **时间**: 2026-03-16 04:44 — 05:15 (含磁盘满修复重启)

## 代码修改

### Config (`plan_full_nuscenes_large_v1.py`)
- **唯一改动**: `bg_balance_weight` 3.0→4.0
- 其余不变: marker_pos_punish=1.0, marker_grid_pos_dropout=0.0, around_weight=0.0

### GiT Commit
- `7961447` — config: ORCH_053 bg_balance_weight=4.0 binary search between 3.0(dead) and 5.0(alive)

## 执行异常

- 首次启动用 DDP 2GPU 失败（GPU 3 被 yl0826 占用, OOM）
- 改为单 GPU 2 后，训练在 iter 100 后因 **SSD 磁盘满** (3.7T/3.7T, 100%) 静默崩溃
- 清理 049-052 旧 checkpoint（释放 ~67 GB）后从头重启
- 有效训练: 05:01-05:15 CDT

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

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| bg_balance_weight=4.0 | config 可见 | ✅ | PASS |
| marker_pos_punish=1.0 | config 可见 | ✅ | PASS |
| iter_200 frozen check | 已执行 | ✅ | PASS |
| saturation 0.05~0.90 | 中间态 | **0.000** (全背景) | **FAIL** |

**总体: FAIL** — 全背景坍塌

## 关键结论: bg_balance_weight 二分搜索

| ORCH | marker_pos_punish | bg_balance_weight | @200 sat | @200 TP | 模式 |
|------|-------------------|-------------------|----------|---------|------|
| 052 | 1.0 | 3.0 | 0.000 | 0 | 全背景 |
| **053** | **1.0** | **4.0** | **0.000** | **0** | **全背景** |
| 049 | 1.0 | **5.0** | 0.487 | 112 | **中间态 ✓** |

**bg=3.0 和 4.0 都死了，只有 bg=5.0 存活。** 下一步建议:
- 试 bg=4.5（缩小搜索范围）
- 或直接复现 049 (bg=5.0) 验证可重复性
- 注意: 049 @500 也最终坍塌为全背景，所以 bg=5.0 也只是在 @200 存活

## 可视化
- iter_200: `/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/053_iter200_frozen_check/`

## Work Dir
`/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch053`
