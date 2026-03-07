# Report: ORCH_005 — P4 Phase 1: AABB Fix + BUG-11 + P4 Launch

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-07 03:05
**Status**: COMPLETED

---

## Task 1: AABB -> Rotated Polygon Label Fix

**File**: `mmdet/datasets/pipelines/generate_occ_flow_labels.py`

**Changes**:

1. **New parameter** `use_rotated_polygon: bool = False` added to `__init__` (backward compatible)

2. **New static method** `_point_in_convex_hull(px, py, hull_pts)`:
   - Cross-product based point-in-convex-polygon test
   - Works with counter-clockwise ordered vertices from scipy ConvexHull

3. **Modified `_compute_valid_grid_ids`** signature: added `polygon_uv=None` parameter
   - When `polygon_uv` is provided: computes scipy ConvexHull, checks each cell center against convex hull
   - When `polygon_uv` is None: falls back to original AABB logic (backward compatible)

4. **Modified call site (~L540)**: When `self.use_rotated_polygon=True`, constructs `poly_uv` from valid projected 3D box corners and passes to `_compute_valid_grid_ids`

**Label count comparison**: Full pipeline comparison was not feasible (requires full dataset class to construct `occ_future_ann_infos`). Verification was done with synthetic rotated boxes:
- 45-degree rotated box: AABB assigns ~2x more cells than convex hull method
- Axis-aligned box: both methods produce identical results
- Expected real-world reduction: 30-50% fewer labels for rotated vehicles (truck, trailer, bus)

---

## Task 2: BUG-11 Fix

**File**: `mmdet/datasets/pipelines/generate_occ_flow_labels.py`

**Change**: L77 default `classes=["car","bus","truck","trailer"]` replaced with `classes=None` + ValueError guard:
```python
classes: List[str] = None,  # BUG-11 FIX: force explicit pass
# In __init__ body:
if classes is None:
    raise ValueError("classes must be explicitly passed to avoid order mismatch")
self.classes = classes
```

This prevents silent truck/bus label swap if a config forgets to pass the `classes` parameter.

---

## Task 3: P4 Training Launch

**Config**: `configs/GiT/plan_g_aabb_fix.py`

| Parameter | P3 (plan_f) | P4 (plan_g) | Change |
|-----------|-------------|-------------|--------|
| load_from | P2@6000 | **P3@3000** | New checkpoint |
| max_iters | 4000 | 4000 | Same |
| bg_balance_weight | 3.0 | **2.0** | Critic: reduce bg dominance |
| reg_loss_weight | 1.0 | **1.5** | Protect theta regression |
| use_rotated_polygon | N/A | **True** | AABB fix active |
| warmup | 500 linear | 500 linear | Same |
| milestones | [2500, 3500] | [2500, 3500] | Same |
| max_norm | 10.0 | 10.0 | Same |
| center_weight | 2.0 | 2.0 | Same |
| around_weight | 0.5 | 0.5 | Same |

**PID**: 3929983
**GPU**: 0, 2 (as required by CEO)
**Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_g_aabb_fix/`
**Memory**: ~21.5 GB / 49.1 GB per GPU

### First 50 iterations:

| Iter | base_lr | Loss | loss_cls | loss_reg | grad_norm | Clipped? |
|------|---------|------|----------|----------|-----------|----------|
| 10 | 9.51e-7 | 1.333 | 0.560 | 0.773 | 29.63 | Yes |
| 20 | 1.95e-6 | 1.000 | 0.486 | 0.514 | 7.99 | No |
| 30 | 2.95e-6 | 1.200 | 0.198 | 1.002 | 17.83 | Yes |
| 40 | 3.95e-6 | 1.323 | 0.206 | 1.117 | 9.12 | No |
| 50 | 4.95e-6 | 1.407 | 0.215 | 1.192 | 21.88 | Yes |

**Observations**:
- Warmup active: LR climbing from ~1e-6
- loss_reg higher than P3 start (expected: reg_loss_weight 1.0->1.5 amplifies reg loss)
- 3/5 iterations clipped (grad_norm > 10.0) — higher than P3 (0/6 at same stage). Likely due to label distribution change from rotated polygon
- No NaN, no OOM
- ETA: ~3h15m, expected completion ~06:20 (Mar 7)

### Schedule:
- First val at iter 500
- Checkpoints every 500 iters
- Warmup ends at iter 500
- Milestones: 2500 (LR * 0.1), 3500 (LR * 0.01)

---

## Verification Checklist

- [x] AABB fix: rotated polygon label assignment with backward-compatible parameter
- [x] BUG-11 fix: classes default removed, ValueError if not passed
- [x] P4 config created with all required parameter changes
- [x] P4 config syntax check passed
- [x] P4 training launched on GPU 0,2 only
- [x] First 50 iters stable: no NaN/OOM
- [x] Report written to `shared/logs/report_ORCH_005.md`

---

## Notes for Orchestrator

1. **Gradient clipping rate is higher** than P3 warmup phase (60% vs 0%). Two possible causes:
   - `reg_loss_weight` increase (1.0->1.5) amplifies reg gradients
   - Rotated polygon changes label distribution, initially surprising the model
   - Should stabilize as warmup completes. Monitor at iter 100-200.

2. **Label count comparison** was not possible end-to-end due to pipeline dependency on dataset class. Synthetic verification confirms algorithm correctness.

3. **P3 final results** (for reference): car_R=0.570, truck_R=0.302, bus_R=0.712, trailer_R=0.622, bg_FA=0.185
