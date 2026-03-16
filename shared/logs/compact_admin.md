# Admin Agent 上下文快照
- **时间**: 2026-03-16 05:18
- **当前任务**: ORCH_053 已完成 (FAIL)，无训练运行中，等待新指令

---

## GPU 状况
- **GPU 0,1**: xg0091 StreamPETR (~40/39 GB)
- **GPU 2**: 空闲（053 训练已被 early stop killed）
- **GPU 3**: yl0826 PETR (~14 GB)
- **SSD**: 清理了 049-052 checkpoint，剩余 ~67 GB

---

## 本 Session 执行记录

### ORCH_049 (COMPLETED — FAIL)
- marker_pos_punish=1.0, bg_balance_weight=5.0, around_weight=0.0
- @200: pos=565 (47%), sat=0.487, TP=112 (全系列最高@200)
- @500: pos=0 (0%), sat=0.000, TP=0 (全背景坍塌)
- GiT commit: `6834922`

### ORCH_050 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=2.0, bg_balance_weight=3.0, marker_grid_pos_dropout=0.5
- @200: pos=0 (0%), sat=0.000, TP=0 (全背景)
- GiT commit: `cc749d9`

### ORCH_051 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=2.0, bg_balance_weight=3.0, marker_grid_pos_dropout=0.0
- @200: pos=1200 (100%), sat=1.000, TP=177 (全正饱和)
- GiT commit: `d3095f1`

### ORCH_052 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=1.0, bg_balance_weight=3.0, FG/BG=1.67x
- @200: pos=0 (0%), sat=0.000, TP=0 (全背景)
- GiT commit: `07659cb`

### ORCH_053 (COMPLETED — FAIL, EARLY STOP @200)
- marker_pos_punish=1.0, bg_balance_weight=4.0
- @200: pos=0 (0%), sat=0.000, marker_same=1.000, TP=0 (全背景)
- 执行异常: SSD 磁盘满，清理后重启
- GiT commit: `7961447`

---

## bg_balance_weight 二分搜索结论

| ORCH | marker_pos_punish | bg_balance_weight | @200 sat | @200 TP | 模式 |
|------|-------------------|-------------------|----------|---------|------|
| 052 | 1.0 | 3.0 | 0.000 | 0 | 全背景 |
| 053 | 1.0 | 4.0 | 0.000 | 0 | 全背景 |
| **049** | **1.0** | **5.0** | **0.487** | **112** | **中间态 ✓** (唯一) |

bg=3.0 和 4.0 都全背景，只有 bg=5.0 存活。下一步: 试 bg=4.5 或复现 bg=5.0。

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
| 053 | @200 | 0 (0%) | 0.000 | 1.000 | 0.000 | 0 | FAIL (全背景早停) |

---

*Admin Agent 上下文快照 | 2026-03-16 05:18*
