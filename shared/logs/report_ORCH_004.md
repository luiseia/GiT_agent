# Report: ORCH_004 — BUG-8 Fix + BUG-10 Fix + P3 Launch

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-06 21:28
**Status**: COMPLETED

---

## Task 1: BUG-8 Fix — cls loss 添加背景类

**File**: `mmdet/models/dense_heads/git_occ_head.py`

**Changes (2 locations):**

1. **Focal path (L886-900)**: Replaced `n_cls_active2` counter with `total_weight` accumulator. Added background class loss after foreground loop:
   ```python
   bg_cls_mask = (cls_target_rel == self.num_classes) & (cls_weight > 0)
   if bg_cls_mask.any():
       loss_cls += bg_balance_weight * focal[bg_cls_mask] / count
       total_weight += bg_balance_weight
   loss_cls /= total_weight
   ```

2. **CE path (L957-972)**: Same pattern applied to CE+punish mode.

Both paths now match the marker loss bg handling pattern (L853-867).

**Syntax check**: PASSED

---

## Task 2: BUG-10 Fix — P3 config with warmup

**File**: `configs/GiT/plan_f_bug8_fix.py` (new, copied from plan_e)

| Parameter | P2 (plan_e) | P3 (plan_f) |
|-----------|-------------|-------------|
| load_from | P1@6000 | **P2@6000** |
| max_iters | 6000 | **4000** |
| warmup | none | **LinearLR 500 iters (0.001x -> 1.0x)** |
| milestones | [3000, 5000] | **[2500, 3500]** |
| max_norm | 10.0 | 10.0 (unchanged) |
| bg_balance_weight | 3.0 | 3.0 (unchanged) |

**Syntax check**: PASSED

---

## Task 3: P3 Training Launch

**PID**: 3775971
**GPU**: 0, 2
**Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/`

### First 60 iterations:

| Iter | base_lr | Loss | loss_cls | loss_reg | grad_norm | Clipped? |
|------|---------|------|----------|----------|-----------|----------|
| 10 | 9.5e-7 | 0.876 | 0.332 | 0.544 | 8.02 | No |
| 20 | 1.95e-6 | 0.664 | 0.274 | 0.390 | 3.46 | No |
| 30 | 2.95e-6 | 0.833 | 0.149 | 0.683 | 3.76 | No |
| 40 | 3.95e-6 | 0.752 | 0.093 | 0.659 | 3.63 | No |
| 50 | 4.95e-6 | 0.886 | 0.148 | 0.737 | 6.45 | No |
| 60 | 5.96e-6 | 0.235 | 0.013 | 0.223 | 1.06 | No |

**Observations:**
- Warmup working correctly: base_lr climbing from ~1e-6 linearly
- **0/6 iterations clipped** (all grad_norm < 10.0) — warmup keeps gradients low during ramp-up
- No NaN, no OOM, memory 15849 MiB per GPU
- loss_cls includes background contribution (BUG-8 fix active)
- ETA ~3h15m, expected completion ~00:40 (Mar 7)

### Schedule:
- First val at iter 500 (~22:10)
- Checkpoints every 500 iters
- LR warmup ends at iter 500
- Milestones: 2500 (LR * 0.1), 3500 (LR * 0.01)

### P2 Final Status (for reference):
P2 completed 6000/6000. Last val (iter 6000, DDP 2-GPU):
- car_R=0.596, truck_R=0.290, bus_R=0.623, trailer_R=0.689
- bg_FA=0.198, offset_cy=0.095, offset_th=0.217

---

## Verification Checklist

- [x] BUG-8 fix: cls loss includes background in both Focal and CE paths
- [x] BUG-8 fix passes syntax check
- [x] P3 config created with warmup (500 iter linear) and milestones [2500, 3500]
- [x] P3 config passes syntax check
- [x] P3 training launched, first 60 iters stable, no NaN/OOM
- [x] Warmup confirmed: LR climbing from 9.5e-7, grad_norm all < 10.0
- [x] Report written to `shared/logs/report_ORCH_004.md`
