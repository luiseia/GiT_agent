# Report: ORCH_001 — BUG-12 Fix (Slot Ordering Inconsistency)

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-06 01:30
**Status**: COMPLETED

---

## 1. Problem Description

The eval script (`occ_2d_box_eval.py`) used strict slot-position-aligned matching:
```python
tp_mask = c_gt_mask & c_pd_mask  # requires (cell_id, slot_idx) exact match
```

When a cell contains multiple objects, GT slots are depth-sorted (nearest first). If the model's predicted slot ordering differs from the GT ordering (e.g., car in slot 0 and truck in slot 1, but GT has truck in slot 0 and car in slot 1), BOTH correct detections are counted as FP. This artificially deflates precision and recall.

## 2. Fix Applied

**File**: `mmdet/evaluation/metrics/occ_2d_box_eval.py`, lines 141-182

**Change**: Replaced slot-aligned matching with cell-internal class-based matching. For each cell, GT and prediction slots of the same class are paired regardless of slot index. Uses `min(gt_count, pred_count)` per-cell-per-class as TP count.

**Backward compatibility**: BG stats, GT count, and pred count remain unchanged. Only TP/FP assignment within foreground classes is affected.

## 3. A/B Test Results (P1@4000, single GPU, 323 samples)

| Metric | OLD (slot-aligned) | NEW (cell class-match) | Delta |
|--------|-------------------|----------------------|-------|
| car_recall | 0.6173 | **0.6260** | +1.4% |
| car_precision | 0.0913 | **0.0926** | +1.4% |
| truck_recall | 0.2032 | **0.3500** | **+72.2%** |
| truck_precision | 0.1116 | **0.1922** | **+72.2%** |
| bus_recall | 0.4794 | **0.6151** | **+28.3%** |
| bus_precision | 0.1340 | **0.1719** | **+28.3%** |
| trailer_recall | 0.6444 | 0.6444 | 0% |
| trailer_precision | 0.0312 | 0.0312 | 0% |
| bg_false_alarm | 0.1568 | 0.1568 | 0% |
| avg_offset_cx | 0.0755 | 0.0804 | +6.5% |
| avg_offset_cy | 0.1261 | 0.1299 | +3.0% |
| avg_offset_th | 0.2061 | 0.2159 | +4.8% |

## 4. Analysis

- **Truck (+72%)**: Trucks frequently share cells with cars (similar BEV footprints). Old eval systematically misaligned their slots, causing massive TP undercounting.
- **Bus (+28%)**: Buses share cells with trucks/trailers in multi-lane scenarios. Same slot-ordering mismatch.
- **Car (+1.4%)**: Car is usually the only object in a cell, so slot-alignment rarely causes issues.
- **Trailer (0%)**: Very few trailer instances (45 GT), and trailers rarely share cells with other classes.
- **BG (0%)**: Background matching is slot-independent, unaffected by the fix.
- **Offsets slightly worse**: Expected — the new matching pairs GT slot 0 with pred slot 1 (etc.), so spatial offsets are slightly less precise since the objects may be at different depths within the same cell.

## 5. Impact on All-Time Records

With BUG-12 fix, several metrics that appeared below target were actually much closer:
- truck_R was reported as 0.20 but is actually **0.35** — much closer to 0.70 target
- bus_R was reported as 0.48 but is actually **0.62** — above the 0.40 target
- truck_P was reported as 0.11 but is actually **0.19** — much closer to 0.25 target

**Note**: All historical metrics in MASTER_PLAN were computed with the OLD (slot-aligned) eval. Direct comparison with BUG-12-fixed metrics is not valid.

## 6. Verification Checklist

- [x] GT and prediction slots use same matching criteria (cell-internal class match)
- [x] P1@4000 checkpoint evaluated with both old and new code
- [x] Results written to `shared/logs/report_ORCH_001.md`
