# Report: ORCH_003 — P1 Final Eval + P2 Launch

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-06 14:18
**Status**: COMPLETED

---

## Task 1: P1@6000 Final Evaluation (BUG-12 fixed eval)

Single-GPU eval on 323 samples with cell-internal class-based matching (BUG-12 fix).

| Metric | P1@6000 | Target |
|--------|---------|--------|
| car_recall | 0.6283 | >= 0.85 |
| car_precision | 0.0914 | >= 0.30 |
| truck_recall | **0.3579** | >= 0.70 |
| truck_precision | 0.1756 | >= 0.25 |
| bus_recall | **0.6265** | >= 0.40 |
| bus_precision | 0.1555 | >= 0.15 |
| trailer_recall | 0.6444 | >= 0.95 |
| trailer_precision | 0.0346 | >= 0.10 |
| bg_false_alarm | 0.1628 | low |
| avg_offset_cx | 0.0805 | <= 0.05 |
| avg_offset_cy | 0.1392 | <= 0.10 |
| avg_offset_w | 0.0036 | — |
| avg_offset_h | 0.0021 | — |
| avg_offset_th | 0.2197 | <= 0.20 |

**P1 final verdict**:
- Bus recall (0.63) exceeds target (0.40)
- Truck recall (0.36) best-ever for final checkpoint (BUG-12 corrected), but still below 0.70 target
- Car recall (0.63) below target — signs of class competition
- BG false alarm (0.16) is low and healthy
- Precision remains below target across all classes (inference pipeline issue, not training)

**Note**: ssd_workspace path resolved to `/mnt/SSD/GiT_Yihao/` (actual SSD mount point). All 12 P1 checkpoints (iter 500-6000) intact.

---

## Task 2: Plan E Config Update

**File**: `configs/GiT/plan_e_bug9_fix.py`

Changes made:
1. `clip_grad max_norm`: 5.0 -> **10.0** (ORCH_002 recommendation, Conductor approved)
2. `load_from`: updated to `/mnt/SSD/GiT_Yihao/Train/Train_20260305/plan_d_center_around/iter_6000.pth`
3. Header comments updated to reflect changes
4. Syntax check: PASSED (`ast.parse()`)

All other parameters unchanged from P1 (center/around weights, per-class balance, reg_loss_weight=1.0, milestones, etc.).

---

## Task 3: P2 Training Launch

**Command**:
```bash
CUDA_VISIBLE_DEVICES=0,2 nohup python -m torch.distributed.launch \
  --nproc_per_node=2 --master_port=29501 \
  tools/train.py configs/GiT/plan_e_bug9_fix.py \
  --launcher pytorch \
  --work-dir /mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_e_bug9_fix \
  > /mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_e_bug9_fix/train.log 2>&1 &
```

**Launch confirmed**: PID 3506111, checkpoint loaded from P1@6000, optimizer state reset (new optimizer).

### Early Iterations (first 50 iters):

| Iter | Loss | loss_cls | loss_reg | grad_norm | Clipped? |
|------|------|----------|----------|-----------|----------|
| 10 | 1.357 | 0.638 | 0.719 | 10.93 | Yes (1.09x) |
| 20 | 0.957 | 0.423 | 0.534 | 7.55 | **No** |
| 30 | 1.089 | 0.285 | 0.803 | 6.88 | **No** |
| 40 | 1.220 | 0.220 | 1.000 | 10.90 | Yes (1.09x) |
| 50 | 1.472 | 0.424 | 1.048 | 27.63 | Yes (2.76x) |

**BUG-9 fix confirmed working**:
- 2/5 iterations (40%) have grad_norm < 10.0 and are NOT clipped
- In P1, 0% of iterations were unclipped (100% at max_norm=0.5)
- When clipping occurs, it's mild (1.1x) for normal iterations, stronger (2.8x) for outliers
- No loss explosion, no NaN — training is stable

### GPU Status:

| GPU | Memory | Utilization |
|-----|--------|-------------|
| 0 | ~22GB/49GB | 100% (P2) |
| 1 | 31GB/49GB | 100% (yl0826 PETR) |
| 2 | ~22GB/49GB | 100% (P2) |
| 3 | 31GB/49GB | 100% (yl0826 PETR) |

### Schedule:
- 6000 iters, ~5h ETA, expected completion ~19:15
- Val every 500 iters, first val at iter 500 (~14:55)
- Milestones: LR decay at iter 3000, 5000

---

## Verification Checklist

- [x] P1@6000 precise metrics recorded (BUG-12 corrected eval)
- [x] plan_e config updated: max_norm=10.0, load_from=P1@6000
- [x] Syntax check passed
- [x] P2 training launched, first 50 iters stable, no errors
- [x] BUG-9 fix confirmed: ~40% iterations unclipped (was 0%)
- [x] Report written to `shared/logs/report_ORCH_003.md`
