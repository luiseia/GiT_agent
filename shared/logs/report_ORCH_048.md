# ORCH_048 执行报告

- **状态**: COMPLETED (frozen check 部分通过，按指令停训)
- **执行者**: Admin Agent
- **时间**: 2026-03-15 23:24 — 2026-03-16 00:06

## 代码修改

### 1. Config (`plan_full_nuscenes_large_v1.py`)
- **移除** `GlobalRotScaleTransBEV`，仅保留 `RandomFlipBEV` ✅
- **显式设置** `grid_assign_mode='center'` ✅
- **权重重平衡**: `pos_cls_w_multiplier` 5.0→1.0, `neg_cls_w` 0.3→1.0
- **Core/around**: `center_weight=1.0`, `around_weight=0.1` (was 2.0/0.5)
- **Prefix dropout**: `token_drop_rate=0.0`, `prefix_drop_rate=0.5`

### 2. `generate_occ_flow_labels.py`
- 新增 `center_cell_id` 计算：投影中心所在 cell → `gt_projection_info['center_cell_id']`

### 3. `git_occ_head.py`
- `_get_targets_single_based_on_bev()`: 对每个 cell-GT 对，center cell 乘 `center_weight`，其他乘 `around_weight`
- 原 `center_weight/around_weight` 是死参数，现已激活

### 4. `git.py`
- 新增 `prefix_drop_rate` 参数
- Prefix dropout: 对每个 cell，以概率 p 随机选择 prefix 长度 k∈[1,30]，将前 k 个 teacher-forced token 替换为随机 token

### GiT Commit
- `33fbb4d` — fix: ORCH_048 anti-frozen — core/around weights, prefix dropout, rebalance pos/neg

## @500 Frozen Check 结果

```
Checkpoint: iter_500.pth
Samples checked: 5

  Avg positive slots: 482/1200 (40.2%)
  Positive IoU (cross-sample): 0.9459
  Marker same rate: 0.9767
  Coord diff (shared pos): 0.007028
  Saturation: 0.426

  VERDICT: 🔴 FROZEN PREDICTIONS DETECTED (marker_same + coord_diff)
```

### 样本级细节
| Sample | GT objects | Predictions | TP | FP | FN |
|--------|-----------|-------------|----|----|-----|
| 0 | 5 | 479 | 4 | 164 | 3 |
| 1 | 10 | 459 | 8 | 155 | 63 |
| 2 | 5 | 511 | 3 | 175 | 24 |
| 3 | 17 | 472 | 3 | 164 | 31 |
| 4 | 25 | 489 | 9 | 162 | 29 |

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| 移除 GlobalRotScaleTransBEV | 已移除 | ✅ | PASS |
| grid_assign_mode='center' | 显式可见 | ✅ | PASS |
| core/around 差异权重 | 非死参数 | ✅ (center=1.0, around=0.1) | PASS |
| Positive IoU | < 0.95 | 0.9459 | **PASS** |
| Marker same rate | < 0.90 | 0.9767 | **FAIL** |
| 不得 1200/1200 | < 1200 | 482 | **PASS** |

**总体**: 2/3 frozen 标准通过，但 marker_same 仍超阈值。按指令停训。

## 对比分析 (ORCH_047 vs 048)

| 指标 | ORCH_047 | ORCH_048 | 变化 |
|------|----------|----------|------|
| Positive slots | 1200 (100%) | 482 (40%) | **-60%** |
| Positive IoU | 1.0000 | 0.9459 | **-0.054** |
| Marker same | 1.0000 | 0.9767 | -0.023 |
| Saturation | 1.000 | 0.426 | **-0.574** |
| True Positives | 0 | 27 (across 5 samples) | **从 0 到检测到物体** |

**核心突破**: 模型不再全正饱和，开始产生有意义的检测（TP 出现）。
方向正确，但 marker_same 仍需进一步下降（0.977 → 需 <0.90）。

## 训练指标 (@500)
- Loss: 1.3-12.8 (波动大，变化中)
- Grad norm: 52-206
- 速度: ~3.8 sec/iter
- GPU: ~29 GB/GPU

## 可视化
`/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/048_iter500_frozen_check/`

## Work Dir
`/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch048`
