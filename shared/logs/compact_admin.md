# Admin Agent 上下文快照
- **时间**: 2026-03-16 00:06
- **当前任务**: ORCH_048 已完成，等待 CEO 新指令

---

## 最新结果: ORCH_048 @500 Frozen Check

```
Positive slots: 482/1200 (40.2%) — 不再 1200/1200 全正!
Positive IoU: 0.9459 (PASS < 0.95)
Marker same: 0.9767 (FAIL > 0.90)
Coord diff: 0.007 (FAIL < 0.01)
Saturation: 0.426
VERDICT: 🔴 FROZEN (marker_same + coord_diff)
```

**vs ORCH_047**: 饱和 100% → 42.6%, IoU 1.0 → 0.945, TP 从 0 到 27。方向正确。

### 样本级 TP (首次出现真阳性!)
- Sample 0: 4/5 TP, Sample 1: 8/10 TP, Sample 4: 9/25 TP

---

## ORCH_048 执行摘要
- 代码: core/around 权重 (center=1.0, around=0.1) + prefix dropout (0.5) + rebalance pos/neg (both=1.0) + grid_assign_mode='center'
- GiT commit: `33fbb4d`
- 训练在 @500 后 kill，未跑 full val (按 ORCH 指令)
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch048`

---

## 关键技术状态

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: [5,11,17,23] → 4096 → 2048 → GELU → 1024
- 2 层 adaptation (25.2M, lr=5e-05)
- bert-large embedding (pretrained)
- **pos_cls_w=1.0, neg_cls_w=1.0** (rebalanced)
- **center_weight=1.0, around_weight=0.1** (core/around active)
- **prefix_drop_rate=0.5** (替代 token_drop)
- RandomFlipBEV(0.5), grid_assign_mode='center'
- clip_grad=50

### GPU
- GPU 0,2: 空闲 (训练已停)
- GPU 1,3: yl0826 PETR (~31 GB)

---

## Frozen Check 历史

| ORCH | Pos slots | IoU | marker_same | saturation | 状态 |
|------|-----------|-----|-------------|------------|------|
| 047 @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | FAIL (全正) |
| **048 @500** | **482 (40%)** | **0.946** | 0.977 | **0.426** | FAIL (marker仍固定) |

---

*Admin Agent 上下文快照 | 2026-03-16 00:06*
