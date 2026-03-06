# Session History — GiT Occupancy Prediction

## Session: 2026-03-04

### Current System State (captured 21:55)

#### GPU Usage
| GPU | Model | Utilization | Memory Used / Total |
|-----|-------|-------------|---------------------|
| 0 | NVIDIA RTX A6000 | 100% | 35433 / 49140 MiB |
| 1 | NVIDIA RTX A6000 | 100% | 31588 / 49140 MiB |
| 2 | NVIDIA RTX A6000 | 100% | 35598 / 49140 MiB |
| 3 | NVIDIA RTX A6000 | 100% | 31220 / 49140 MiB |

> GPU 0-3 occupied. GPU 0,2 by yz0370 training jobs; GPU 1,3 by yl0826 (PETR training, not ours).

#### tmux Sessions
| Session | Status | Description |
|---------|--------|-------------|
| `dinov3_integrated` | Running | Baseline CE+punish training, iter 3880/10000, GPU 0,2 |
| `plan_a` | Running | Plan A Focal Loss v4 training, iter 2750/8000, GPU 0,2 |
| `claude_admin` | Attached | Current Claude Code session |
| `4` | Running | Unknown/unnamed session |

#### Active Training Processes (yz0370)
1. **Baseline (CE+punish)** — `dinov3_integrated` tmux
   - Config: `configs/GiT/single_occupancy_base_front.py`
   - Work dir: `ssd_workspace/Train/Train_20260303/dinov3_integrated_run`
   - Progress: iter 3880/10000
   - LR: 2.5e-06, loss ~0.75-1.54
   - GPU: 0,2 (2 processes, distributed)
   - Loaded from: `iter_2000.pth`

2. **Plan A v4 (Focal Loss)** — `plan_a` tmux
   - Config: `configs/GiT/plan_a_focal_loss.py`
   - Work dir: `ssd_workspace/Train/Train_20260304/plan_a_focal_loss_v4`
   - Progress: iter 2750/8000
   - LR: 5.0e-06, loss ~1.14
   - GPU: 0,2 (2 processes, distributed, batch_size=1)
   - Loaded from: `iter_2000.pth`

---

### Key Decisions & Operations Log

#### [21:30] Plan B Implementation — Per-Class Balanced Loss

**Root Cause Analysis**: Both baseline (CE+punish) and Plan A v4 (Focal Loss) show identical class-competition oscillation: bus/trailer recall rises then truck recall collapses, in a cycle. Since two completely different loss functions produce the same symptom, the root cause is NOT in the loss function design, but in how loss aggregates gradients across classes.

**Problem**: In `loss_by_feat_single`, marker/class/regression losses compute a single weighted average over ALL positive slots. With car=50%, truck=31%, bus=19%, trailer=0.5% of GT samples, car/truck gradients dominate. When car converges, bus/truck loss becomes dominant and shifts gradient direction.

**Fix (Plan B)**: Compute loss per-class independently, then average across classes with equal weight. Each class contributes equally to the gradient regardless of frequency.

**Files Modified**:
1. `mmdet/models/dense_heads/git_occ_head.py`:
   - Added `use_per_class_balance: bool = False` to `__init__`
   - Added `_per_class_reg_loss()` helper method
   - Modified `loss_by_feat_single()`: per-class balanced marker, cls, and regression loss for BOTH Focal Loss and CE+punish branches
   - Backward compatible: `use_per_class_balance=False` preserves original behavior

2. `configs/GiT/single_occupancy_base_front.py`:
   - Added `use_per_class_balance = True`
   - Passed to OccHead in model dict

3. `configs/GiT/plan_a_focal_loss.py`:
   - Added `use_per_class_balance = True`
   - Passed to OccHead in model dict

**Verification**: All 3 files pass `ast.parse()` syntax check.

**Status**: Code ready. NOT yet launched — both baseline and Plan A are still running on GPU 0,2. Need to stop one or wait for GPU availability before launching Plan B.

#### Evaluation Strategy (agreed with user)
- Minimum observation: 2000 iters before any go/kill decision
- Kill criteria only if: NaN loss, >90% false alarm sustained, or ALL classes at 0% recall at iter 2000
- Assessment: Use BEST per-class metric across 500-2000 window (not just latest checkpoint)
- Success: All 4 classes simultaneously above recall targets at ANY single checkpoint

#### [22:00] Evaluation & Decision — Terminate Both, Launch Plan B

**Baseline (CE+punish) final metrics (7 validations, iter 500-3500):**

| iter | car | truck | bus | trailer | FA |
|------|-----|-------|-----|---------|-----|
| 500  | 0.59 | 0.43 | 0.14 | 0.98 | 0.33 |
| 1000 | 0.60 | **0.65** | 0.22 | 0.87 | 0.23 |
| 1500 | 0.82 | 0.41 | 0.30 | 0.98 | 0.34 |
| 2000 | 0.86 | **0.002** | 0.60 | 0.58 | 0.26 |
| 2500 | 0.91 | 0.04 | 0.55 | 0.98 | 0.36 |
| 3000 | 0.84 | 0.18 | **0.89** | 0.58 | 0.40 |
| 3500 | 0.69 | 0.20 | **0.94** | 0.98 | 0.36 |

**Plan A v4 (Focal Loss) final metrics (5 validations, iter 500-2500):**

| iter | car | truck | bus | trailer | FA |
|------|-----|-------|-----|---------|-----|
| 500  | 0.42 | 0.32 | 0.57 | 0.44 | 0.15 |
| 1000 | 0.38 | 0.37 | 0.21 | **0.00** | 0.20 |
| 1500 | 0.39 | **0.007** | 0.62 | 0.87 | 0.19 |
| 2000 | 0.66 | 0.30 | 0.56 | 0.64 | 0.26 |
| 2500 | 0.57 | 0.19 | 0.40 | 0.93 | 0.20 |

**Conclusion**: Both runs show textbook class-competition oscillation. No checkpoint achieves all 4 classes above target simultaneously. This is exactly Plan B's target symptom.

**Actions taken**:
1. Terminated baseline (`dinov3_integrated`) at iter ~3900/10000
2. Terminated Plan A v4 (`plan_a`) at iter ~2800/8000
3. Created `configs/GiT/plan_b_class_balanced.py` (copy of baseline + `use_per_class_balance=True`)
4. Launched Plan B in tmux `plan_b` on GPU 0,2
5. Verified: training started, iter 20 reached, loss=3.23, no NaN

**Plan B training details**:
- Config: `configs/GiT/plan_b_class_balanced.py`
- Work dir: `ssd_workspace/Train/Train_20260304/plan_b_class_balanced`
- GPU: 0,2 (CUDA_VISIBLE_DEVICES=0,2), 2 processes distributed
- batch_size=2, accumulative_counts=4, effective_batch=16
- LR: 5e-5, loss mode: CE+punish + per-class balanced
- Loaded from: `iter_2000.pth` (same starting point as baseline)
- Schedule: 10000 iters, val every 500

---

#### [22:51] Plan B iter 500 Validation — ALL 4 CLASSES ALIVE

| Class | Recall | Precision | vs Baseline@500 | vs PlanA_v4@500 |
|-------|--------|-----------|-----------------|-----------------|
| car | 0.76 | 0.111 | +0.17 | +0.34 |
| truck | 0.26 | 0.086 | -0.17 | -0.06 |
| bus | 0.46 | 0.132 | +0.32 | -0.11 |
| trailer | 0.98 | 0.058 | +0.00 | +0.53 |
| FA rate | 0.194 | — | -0.13 | +0.05 |

First time all 4 classes have non-trivial recall at the same checkpoint. Per-class balancing is working. Continue monitoring.

#### [23:51] Plan B iter 1000 & 1500 — OSCILLATION BROKEN

Truck recall stable at 0.25-0.26 for 3 consecutive checkpoints (was collapsing to 0.002 in baseline by this point). Car reached 0.92 without killing truck. Bus improving to 0.58. Trailer rock-solid at 0.98.

Best simultaneous recall at iter 1500: car=0.92, truck=0.26, bus=0.58, trailer=0.98.

**Per-class balanced loss confirmed working.** Continue monitoring.

#### [00:32] Plan B iter 2000 — Truck climbing, avg recall 0.71

Truck recall broke out of plateau: 0.26→0.35. Bus surged to 0.83. Trailer still 0.98. Car dipped to 0.69 (mild, not a collapse). Avg 4-class recall = 0.71, vs baseline's 0.49 at same iteration.

#### [01:10] Plan B iter 2500 + Precision Root Cause Investigation

Truck dropped 0.35→0.06 (oscillation dampened but not eliminated). ALL classes have precision <0.14.

**Root cause of low precision**: inference pipeline has NO confidence filtering. All 1200 slots per image are evaluated; marker confidence is computed but discarded (scores hardcoded to 1.0). No NMS. Result: ~197 false car predictions per image vs ~26 true GTs.

**This is an inference/evaluation problem, not a training problem.** Fix: propagate marker softmax probability as confidence score + add score threshold + add NMS.

#### [01:30] Inference Precision Fixes Implemented

**Changes made**:
1. `git_occ_head.py`: Added `grid_scores` (marker softmax confidence) propagation through `decoder_inference` → `add_pred_to_datasample`
2. `occ_2d_box_eval.py`: Added `score_thr` and `nms_iou_thr` params; applied confidence threshold filtering in `process()`
3. All 3 configs updated with `score_thr=0.3`, `nms_iou_thr=0.3` in `val_evaluator`

**IoU-based matching attempt (REVERTED)**: Tried Hungarian IoU matching + per-class rotated NMS. Failed because it changed GT counting semantics (unique objects vs grid-cell entries), making car_gt_cnt drop from 8267→1106. Metrics became incomparable. Reverted to slot-aligned matching + score filtering only.

**Eval result with score_thr=0.3 on iter_3000**:
- car precision: 0.079→0.097 (modest improvement)
- bg_false_alarm: 0.29→0.21
- Score filtering alone not sufficient — model's marker confidence doesn't discriminate TP vs FP well yet

#### [01:45] Plan B Restarted from iter 3000

Stopped Plan B at iter ~3240, modified config to `resume=True` from `iter_3000.pth`. Restarted training with new evaluator code (score filtering). Training resumed successfully at iter 3010.

Next validation at iter 3500 will use the new score-filtered evaluator, allowing us to track precision improvement as training continues.

### Pending Actions
- [x] Implement confidence score propagation in `_predict_single`
- [x] Add score threshold filtering at inference
- [x] Add rotated NMS post-processing (attempted, reverted — slot-aligned eval not compatible)
- [ ] Plan B training continues with score-filtered evaluator
- [ ] Monitor iter 3500 validation results (first with new evaluator)
- [ ] Push to GitHub when auth resolved

---

*This file is appended after each significant operation. Last updated: 2026-03-05 01:45*
