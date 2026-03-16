# Admin Agent 上下文快照
- **时间**: 2026-03-16 03:25
- **当前任务**: ORCH_050 完成 (FAIL), 等待新指令

---

## 最近完成

### ORCH_050 (COMPLETED — FAIL, EARLY STOP @200)
- **改动**: marker_pos_punish=2.0, bg_balance_weight=3.0, marker_grid_pos_dropout=0.5
- **@200**: pos_slots=0 (0%), marker_same=1.000, saturation=0.000, TP=0 → 全背景坍塌
- **早停触发**: saturation=0.000 < 0.05 (all-negative detection)
- **GiT commit**: `cc749d9`
- **诊断**: grid_pos_dropout 可能适得其反，去掉位置信息让 marker 更难定位有物体的 cell

### ORCH_049 (COMPLETED — FAIL)
- **改动**: marker_pos_punish=1.0, bg_balance_weight=5.0, around_weight=0.0
- **@200**: pos_slots=565 (47%), TP=112 (全系列最高)
- **@500**: pos_slots=0 (0%), TP=0 (全背景坍塌)
- **GiT commit**: `6834922`

---

## Frozen Check 历史

| ORCH | Iter | Pos slots | IoU | marker_same | saturation | TP | 状态 |
|------|------|-----------|-----|-------------|------------|-----|------|
| 047 | @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | 0 | FAIL (全正) |
| 048 | @500 | 482 (40%) | 0.946 | 0.977 | 0.426 | 27 | FAIL (marker固定) |
| 049 | @200 | 565 (47%) | 0.952 | 0.976 | 0.487 | 112 | FAIL (TP最高) |
| 049 | @500 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景) |
| 050 | @200 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景早停) |

---

## GPU 共享状况
- **GPU 0,1**: xg0091 StreamPETR (~40/43 GB)
- **GPU 2,3**: 空闲 (050 训练已被 kill)

---

## 关键技术状态

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: [5,11,17,23] → 4096 → 2048 → GELU → 1024
- 2 层 PreLN Transformer adaptation (25.2M, lr=5e-05)
- bert-large embedding (pretrained)
- **当前最佳配置参考 (049@200)**: marker_pos_punish=1.0, bg_balance_weight=5.0, around_weight=0.0, prefix_drop_rate=0.5, marker_grid_pos_dropout=0.0

---

*Admin Agent 上下文快照 | 2026-03-16 03:25*
