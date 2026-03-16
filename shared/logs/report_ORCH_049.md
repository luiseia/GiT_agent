# ORCH_049 执行报告

- **状态**: COMPLETED (frozen check 失败 — 全背景坍塌)
- **执行者**: Admin Agent
- **时间**: 2026-03-16 01:17 — 02:40

## 代码修改

### Config (`plan_full_nuscenes_large_v1.py`)
- **BUG-73 修复**: `marker_pos_punish` 3.0→1.0, `bg_balance_weight` 2.5→5.0
  - `marker_pos_punish` 是 CE loss 中正样本 marker token 的惩罚倍数，3.0 造成了 3× fg bias
  - `bg_balance_weight` 控制背景 cell 的 loss 权重，2.5 不足以对抗 fg bias
- **around_weight**: 0.1→0.0 (完全关闭外围 cell supervision)
- **checkpoint interval**: 100 (保存 iter_100, 200, 300, 400, 500)
- **val_interval**: 99999 (禁用 auto-val)

### 新脚本 (`scripts/auto_frozen_check_049.sh`)
- 双阶段 frozen check: iter_200 快速检查 + iter_500 完整检查
- iter_200 早停逻辑: marker_same>0.95 AND saturation>0.90 → kill

### GiT Commit
- `6834922` — fix: ORCH_049 BUG-73 marker_pos_punish, bg_balance_weight, around_weight=0

## 训练概况

- GPU: 2,3 (2×A6000), ~29 GB/GPU
- 速度: ~3.8 sec/iter
- 从零训练，500 iter

### Loss 行为 (关键发现)
- **iter 10-130**: loss 从 13.2 快速降到 0.24, reg_loss=0 (全背景预测)
- **iter 140**: reg_loss 首次出现 (2.11), 模型开始尝试正样本
- **iter 140-500**: 剧烈振荡 — 交替在全背景 (loss≈0.01) 和检测尝试 (loss 3-13) 之间
- **结论**: bg_balance_weight=5.0 让模型偏好全背景模式，偶尔产生的正样本预测被强背景信号推回

## Frozen Check 结果

### iter_200 (快速检查)
```
Checkpoint: iter_200.pth
Samples checked: 5

  Avg positive slots: 565/1200 (47.1%)
  Positive IoU (cross-sample): 0.9520
  Marker same rate: 0.9755
  Coord diff (shared pos): 0.016052
  Saturation: 0.487

  VERDICT: 🔴 FROZEN PREDICTIONS DETECTED (IoU + marker_same)
```

样本级:
| Sample | GT objects | Pred | TP | FP | FN |
|--------|-----------|------|----|----|-----|
| 0 | 5 | 573 | 1 | 190 | 6 |
| 1 | 10 | 561 | 46 | 141 | 25 |
| 2 | 5 | 546 | 23 | 159 | 4 |
| 3 | 17 | 585 | 20 | 175 | 14 |
| 4 | 25 | 562 | 22 | 166 | 16 |

**早停门槛**: marker_same=0.976>0.95 但 saturation=0.487<0.90 → **未触发早停**

### iter_500 (完整检查)
```
Checkpoint: iter_500.pth
Samples checked: 5

  Avg positive slots: 0/1200 (0.0%)
  Positive IoU (cross-sample): 0.0000
  Marker same rate: 1.0000
  Coord diff (shared pos): 0.000000
  Saturation: 0.000

  VERDICT: 🔴 FROZEN PREDICTIONS DETECTED (marker_same)
```

样本级: 所有样本 Pred=0, TP=0 — **完全全背景坍塌**

注: iter_500 auto-check 首次在 GPU 0 运行时 OOM (xg0091 占用)，手动在 GPU 2 重跑成功。

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| marker_pos_punish=1.0 | config 可见 | ✅ | PASS |
| bg_balance_weight=5.0 | config 可见 | ✅ | PASS |
| around_weight≤0.05 | config 可见 | 0.0 ✅ | PASS |
| iter_200 frozen check | 执行+报告数值 | ✅ | PASS |
| iter_500 frozen check | 完整执行+可视化 | ✅ | PASS |
| marker_same < 0.9767 | 低于 048 值 | @200: 0.9755 (微降), @500: 1.000 (恶化) | **FAIL** |
| Positive IoU ≤ 0.9459 | 不高于 048 值 | @200: 0.9520 (高于), @500: 0.000 (坍塌) | **FAIL** |

**总体: FAIL** — 模型从 iter_200 的部分检测能力退化到 iter_500 的完全全背景坍塌。

## 全系列对比

| ORCH | Iter | Pos slots | IoU | marker_same | saturation | TP | 状态 |
|------|------|-----------|-----|-------------|------------|-----|------|
| 047 | @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | 0 | FAIL (全正) |
| 048 | @500 | 482 (40%) | 0.946 | 0.977 | 0.426 | 27 | FAIL (marker固定) |
| **049** | **@200** | 565 (47%) | 0.952 | 0.976 | 0.487 | **112** | FAIL (但 TP 最高) |
| **049** | **@500** | **0 (0%)** | 0.000 | 1.000 | 0.000 | **0** | **FAIL (全背景)** |

## 关键诊断

1. **bg_balance_weight=5.0 过于激进**: 模型在 500 iter 内完全坍塌到全背景模式
2. **iter_200 其实是 049 的峰值**: TP=112 是所有实验中最高的，说明 BUG-73 fix (marker_pos_punish=1.0) 是正确方向
3. **Loss 振荡模式**: 全背景 (loss≈0.01) ↔ 检测尝试 (loss 3-13) 的交替表明 bg_balance_weight 和 fg supervision 之间的拉锯
4. **建议下一步**: bg_balance_weight 从 5.0 回调到 2.5-3.0，保留 marker_pos_punish=1.0

## 可视化
- iter_200: `/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/049_iter200_frozen_check/`
- iter_500: `/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/049_iter500_frozen_check/`

## Work Dir
`/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch049`
