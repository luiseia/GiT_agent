# Admin Agent 上下文快照
- **时间**: 2026-03-16 02:40
- **当前任务**: ORCH_049 完成，等待新指令

---

## 最近完成

### ORCH_049 (COMPLETED — FAIL)
- **Config**: `plan_full_nuscenes_large_v1.py`
- **核心改动**: BUG-73 fix (marker_pos_punish=1.0, bg_balance_weight=5.0), around_weight=0.0
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch049`
- **GiT commit**: `6834922`
- **结果**:
  - @200: pos_slots=565 (47%), IoU=0.952, marker_same=0.976, saturation=0.487, **TP=112** (峰值)
  - @500: pos_slots=0 (0%), IoU=0.000, marker_same=1.000, saturation=0.000, TP=0 (**全背景坍塌**)
- **根因**: bg_balance_weight=5.0 过于激进，模型在 500 iter 完全坍塌到全背景
- **Auto-check iter_500 OOM**: GPU 0 被 xg0091 占用，手动在 GPU 2 重跑

---

## Frozen Check 历史

| ORCH | Iter | Pos slots | IoU | marker_same | saturation | TP | 状态 |
|------|------|-----------|-----|-------------|------------|-----|------|
| 047 | @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | 0 | FAIL (全正) |
| 048 | @500 | 482 (40%) | 0.946 | 0.977 | 0.426 | 27 | FAIL (marker固定) |
| 049 | @200 | 565 (47%) | 0.952 | 0.976 | 0.487 | 112 | FAIL (但TP最高) |
| 049 | @500 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景) |

---

## GPU 共享状况
- **GPU 0**: xg0091 StreamPETR VGGT (~40 GB)
- **GPU 1**: xg0091 StreamPETR VGGT (~43 GB)
- **GPU 2**: 空闲
- **GPU 3**: 部分占用 (~14 GB)

---

## 关键技术状态 (当前架构)

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: [5,11,17,23] → 4096 → 2048 → GELU → 1024
- 2 层 PreLN Transformer adaptation (25.2M, lr=5e-05)
- bert-large embedding (pretrained)
- pos_cls_w=1.0, neg_cls_w=1.0, marker_pos_punish=1.0
- bg_balance_weight=5.0 (过激，需回调)
- center_weight=1.0, around_weight=0.0
- prefix_drop_rate=0.5, RandomFlipBEV(0.5), grid_assign_mode='center', clip_grad=50

---

*Admin Agent 上下文快照 | 2026-03-16 02:40*
