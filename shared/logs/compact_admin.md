# Admin Agent 上下文快照
- **时间**: 2026-03-16 04:37
- **当前任务**: ORCH_052 已完成 (FAIL)，无训练运行中，等待新指令

---

## GPU 状况
- **GPU 0,1**: xg0091 StreamPETR (~40/43 GB)
- **GPU 2,3**: 空闲（052 训练已被 early stop killed）

---

## 本 Session 执行记录

### ORCH_049 (COMPLETED — FAIL)
- marker_pos_punish=1.0, bg_balance_weight=5.0, around_weight=0.0
- @200: pos=565 (47%), IoU=0.952, marker_same=0.976, sat=0.487, **TP=112** (全系列最高@200)
- @500: pos=0 (0%), sat=0.000, TP=0 (全背景坍塌)
- GiT commit: `6834922`

### ORCH_050 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=2.0, bg_balance_weight=3.0, **marker_grid_pos_dropout=0.5**
- @200: pos=0 (0%), sat=0.000, TP=0 (全背景, 早停)
- GiT commit: `cc749d9`

### ORCH_051 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=2.0, bg_balance_weight=3.0, marker_grid_pos_dropout=0.0
- @200: pos=1200 (100%), sat=1.000, TP=177 (全正饱和, 早停)
- GiT commit: `d3095f1`

### ORCH_052 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=1.0, bg_balance_weight=3.0, FG/BG=1.67x
- @200: pos=0 (0%), sat=0.000, marker_same=1.000, TP=0 (全背景坍塌)
- **意外结果**: FG/BG=1.67x 应比 1x 更倾向正预测，却全背景
- GiT commit: `07659cb`

---

## 变量隔离结论 (049-052 系列, 已更新)

| ORCH | marker_pos_punish | bg_balance_weight | FG/BG | dropout | @200 sat | @200 TP | 模式 |
|------|-------------------|-------------------|-------|---------|----------|---------|------|
| 049 | 1.0 | **5.0** | 1x | 0 | 0.487 | 112 | **中间态 ✓** (唯一) |
| 050 | 2.0 | 3.0 | 3.3x | 0.5 | 0.000 | 0 | 全背景 |
| 051 | 2.0 | 3.0 | 3.3x | 0 | 1.000 | 177 | 全正 |
| 052 | 1.0 | 3.0 | 1.67x | 0 | 0.000 | 0 | 全背景 |

**关键发现**: FG/BG 比假设被推翻
- 052 vs 049: FG/BG 更高 (1.67x > 1x) 却全背景
- 049 的真正独特之处: **bg_balance_weight=5.0** (其余实验均为 3.0)
- 可能 bg_balance_weight 的绝对值对训练动态有独立影响
- 或者训练对随机种子/数据顺序高度敏感

---

## Frozen Check 完整历史

| ORCH | Iter | Pos slots | IoU | marker_same | saturation | TP | 状态 |
|------|------|-----------|-----|-------------|------------|-----|------|
| 047 | @500 | 1200 (100%) | 1.000 | 1.000 | 1.000 | 0 | FAIL (全正) |
| 048 | @500 | 482 (40%) | 0.946 | 0.977 | 0.426 | 27 | FAIL (marker固定) |
| 049 | @200 | 565 (47%) | 0.952 | 0.976 | 0.487 | 112 | FAIL (TP最高@200) |
| 049 | @500 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景) |
| 050 | @200 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景早停) |
| 051 | @200 | 1200 (100%) | 1.000 | 0.997 | 1.000 | 177 | FAIL (全正早停) |
| 052 | @200 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景早停) |

---

## 关键技术状态 (当前架构)

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: [5,11,17,23] → 4096 → 2048 → GELU → 1024
- 2 层 PreLN Transformer adaptation (25.2M, lr=5e-05)
- bert-large embedding (pretrained)
- pos_cls_w=1.0, neg_cls_w=1.0
- prefix_drop_rate=0.5, marker_grid_pos_dropout=0.0
- RandomFlipBEV(0.5), grid_assign_mode='center', clip_grad=50

---

*Admin Agent 上下文快照 | 2026-03-16 04:37*
