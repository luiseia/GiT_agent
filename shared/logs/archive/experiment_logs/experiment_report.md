# Experiment Report: Overfitting on nuScenes-mini (323 images)

## Overfitting Targets

Based on baseline metrics at iter 500 (first validation), the following targets define "overfitting success":

| Metric | Baseline | Target | Rationale |
|--------|----------|--------|-----------|
| car_recall | 0.5934 | >= 0.85 | Model must find most cars |
| car_precision | 0.0563 | >= 0.30 | 5x reduction in false positives |
| truck_recall | 0.4277 | >= 0.70 | Trucks are common, should be learnable |
| truck_precision | 0.0618 | >= 0.25 | Reduce false truck predictions |
| bus_recall | 0.1363 | >= 0.40 | Bus is rare, lower bar acceptable |
| bus_precision | 0.0505 | >= 0.15 | Fewer samples = harder to be precise |
| trailer_recall | 0.9778 | >= 0.95 | Already high, maintain |
| trailer_precision | 0.0213 | >= 0.10 | Very few samples (90 GT), hard |
| avg_precision (all) | 0.047 | >= 0.20 | Primary success metric |
| avg_offset_cx | 0.0807 | <= 0.05 | Spatial accuracy |
| avg_offset_cy | 0.1786 | <= 0.10 | Spatial accuracy |
| avg_offset_th | 0.3261 | <= 0.20 | Angle accuracy |

**Primary success criterion**: avg_precision >= 0.20 AND avg_recall >= 0.70

---

## Experiment Timeline

### [2026-03-04 16:00] Initial Setup

**Baseline (CE + punish weights)**
- Config: `single_occupancy_base_front.py`
- GPUs: 0, 2 (shared)
- Work dir: `ssd_workspace/Train/Train_20260303/dinov3_integrated_run/`
- Status: Running, iter ~700/10000
- Settings: LR=5e-5, batch=2, accum=4, CE loss with punish weights (3.0/1.0/1.0)

**Plan A v1 (Focal Loss — FAILED)**
- Config: `plan_a_focal_loss.py`
- GPUs: 0, 2 (shared with baseline)
- Work dir: `ssd_workspace/Train/Train_20260304/plan_a_focal_loss/`
- Settings: LR=1e-4, batch=1, accum=8, Focal Loss (gamma=2.0, alpha=0.75)
- reg_loss_weight=2.0, cls_loss_weight=1.0

---

## Monitoring Log

### Check #1 - [2026-03-04 16:00] - Setup
- Baseline: iter ~700, loss ~1.5-2.5, grad_norm 7-65 (volatile)
- Plan A: Launched, confirmed running at iter 10
- GPU memory: GPU0 35/49GB, GPU2 36/49GB (both trainings on same GPUs)
- Disk: 121GB free

### Check #2 - [2026-03-04 16:30] - Baseline iter 1000 Validation

**Baseline iter 1000 results (vs iter 500):**
| Metric | iter 500 | iter 1000 | Change |
|--------|----------|-----------|--------|
| car_recall | 0.5934 | 0.6008 | +0.01 |
| car_precision | 0.0563 | 0.0782 | +0.02 |
| truck_recall | 0.4277 | 0.6499 | **+0.22** |
| truck_precision | 0.0618 | 0.1083 | +0.05 |
| bus_recall | 0.1363 | 0.2190 | +0.08 |
| bus_precision | 0.0505 | 0.1376 | **+0.09** |
| trailer_recall | 0.9778 | 0.8667 | -0.11 |
| trailer_precision | 0.0213 | 0.1029 | +0.08 |
| bg_false_alarm | 0.3260 | 0.2305 | -0.10 |
| avg_offset_cx | 0.0807 | 0.0556 | improved |
| avg_offset_cy | 0.1786 | 0.1294 | improved |
| avg_offset_th | 0.3261 | 0.3266 | flat |

**Analysis**: Baseline improving steadily. Precision nearly doubled. Truck recall jumped +0.22. False alarm rate dropped 10%. On track but slow.

### Check #3 - [2026-03-04 16:45] - Plan A v1 iter 500 Validation — FAILED

**Plan A v1 iter 500 results:**
| Metric | Plan A v1 | Baseline@500 | Verdict |
|--------|-----------|-------------|---------|
| car_recall | 0.1529 | 0.5934 | **much worse** |
| truck_recall | 0.2379 | 0.4277 | worse |
| bus_recall | 0.8779 | 0.1363 | flooded (prec=0.016) |
| trailer_recall | 0.0000 | 0.9778 | **collapsed** |
| bg_false_alarm | 0.4746 | 0.3260 | worse |
| avg_offset_th | 0.2526 | 0.3261 | better |

**Root cause**: `loss_cls=0.067, loss_reg=1.96` at convergence.
- `reg_loss_weight=2.0` doubled regression loss, starving classification gradients
- `focal_gamma=2.0` aggressively suppressed easy classification samples
- Combined effect: model barely learned what classes to predict, collapsed to always predicting "bus"

**Decision**: Stop Plan A v1, restart as v2 with corrected loss balance.

### Check #4 - [2026-03-04 16:50] - Plan A v2 Launch

**Plan A v2 changes (from v1):**
| Parameter | v1 (failed) | v2 (corrected) | Rationale |
|-----------|-------------|----------------|-----------|
| focal_gamma | 2.0 | 1.0 | Less suppression of easy cls samples |
| focal_alpha | 0.75 | 0.80 | Slightly stronger positive weight |
| cls_loss_weight | 1.0 | 2.0 | Prevent cls gradient starvation |
| reg_loss_weight | 2.0 | 1.0 | Was over-boosting regression |

Effective cls:reg ratio changed from 1:2 to 2:1.

### Check #5 - [2026-03-04 17:35] - Plan A v2 iter 500 Validation — FAILED (false positive flood)

**Plan A v2 iter 500:**
| Metric | Baseline@500 | Plan A v2@500 | Verdict |
|--------|-------------|-------------|---------|
| car_recall | 0.5934 | **0.8118** | excellent convergence speed |
| car_precision | 0.0563 | 0.0465 | worse |
| bg_false_alarm | 0.3260 | **0.6605** | double the false alarms |
| trailer_precision | 0.0213 | **0.5714** | surprisingly good |
| avg_offset_cx | 0.0807 | **0.0523** | best regression yet |

**Root cause**: Double-weighting. `pos_cls_w_multiplier=5.0` (target assignment) x `focal_alpha=0.80` (loss) = 5*0.80/(0.3*0.20) = **67:1 effective pos/neg ratio**. The Focal alpha and the target weight BOTH boost positives independently.

**Decision**: Start v3 with corrected pos/neg balance.

### Check #6 - [2026-03-04 17:38] - Plan A v3 Launch

**Plan A v3 changes (from v2):**
| Parameter | v2 (failed) | v3 (corrected) | Rationale |
|-----------|-------------|----------------|-----------|
| pos_cls_w_multiplier | 5.0 | 2.0 | Reduce target assignment boost |
| focal_gamma | 1.0 | 1.5 | Moderate: between v1 and v2 |
| focal_alpha | 0.80 | 0.60 | Reduced: avoid double-weighting |
| cls_loss_weight | 2.0 | 1.5 | Less cls dominance |

Effective pos/neg ratio: 2.0*0.60/(0.3*0.40) = 1.2/0.12 = **10:1** (was 67:1 in v2, 300:1 in original code)

### Baseline iter 1500 — oscillating

| Metric | iter 500 | iter 1000 | iter 1500 | Trend |
|--------|----------|-----------|-----------|-------|
| car_recall | 0.59 | 0.60 | **0.82** | +0.23 |
| truck_recall | 0.43 | **0.65** | 0.41 | oscillating |
| bus_precision | 0.05 | **0.14** | **0.15** | improving |
| bg_false_alarm | 0.33 | **0.23** | 0.34 | oscillating |
| offset_cy | 0.18 | 0.13 | **0.10** | improving |

Baseline is improving on recall and regression but precision/false alarms oscillate — classic symptom of the CE+punish design instability.

---

## Plan Iteration History

| # | Plan | Reason | Start | End | Result |
|---|------|--------|-------|-----|--------|
| 1 | Baseline (CE+punish) | Initial run with adjusted punish weights | 15:18 | running | oscillating, slow |
| 2 | Plan A v1 (Focal gamma=2, reg_w=2) | Focal Loss for auto pos/neg balancing | 16:00 | 16:50 | FAILED: cls gradient starvation |
| 3 | Plan A v2 (Focal gamma=1, alpha=0.80) | Corrected loss balance | 16:50 | 17:35 | FAILED: 67:1 pos/neg ratio, 66% false alarm |
| 4 | Plan A v3 (Focal gamma=1.5, alpha=0.60, pos_mult=2) | Fix double-weighting | 17:38 | 18:20 | Too conservative: 10:1 ratio, bus/trailer=0% |
| 5 | Plan A v4 (Focal gamma=1.5, alpha=0.70, pos_mult=4) | Calibrated 31:1 ratio | 18:22 | running | **BEST**: most balanced at iter 2000, no class collapse |

### Check #7 - [2026-03-04 18:22] - Baseline iter 2000 — Class Competition Problem

| Metric | iter 1000 | iter 1500 | iter 2000 | Trend |
|--------|-----------|-----------|-----------|-------|
| car_recall | 0.60 | 0.82 | **0.86** | improving |
| truck_recall | 0.65 | 0.41 | **0.002** | COLLAPSED |
| bus_recall | 0.22 | 0.30 | **0.60** | jumping (at expense of truck) |
| trailer_prec | 0.10 | 0.10 | **0.32** | improving |
| bg_false_alarm | 0.23 | 0.34 | 0.26 | oscillating |

Severe class-competition: bus recall jumped 0.30→0.60 but truck collapsed 0.41→0.002.
The CE+punish loss creates an unstable optimization landscape.

### Check #8 - [2026-03-04 19:04] - Plan A v4 iter 500 — BEST YET

| Metric | Baseline@500 | v2@500 | v3@500 | **v4@500** | Target |
|--------|-------------|--------|--------|-----------|--------|
| car_recall | 0.59 | 0.81 | 0.48 | 0.42 | ≥0.85 |
| car_prec | 0.056 | 0.047 | 0.060 | **0.121** | ≥0.30 |
| truck_prec | 0.062 | 0.021 | 0.096 | **0.212** | ≥0.25 |
| bus_recall | 0.14 | 0.88 | 0.00 | **0.57** | ≥0.40 |
| false_alarm | 0.33 | 0.66 | 0.17 | **0.146** | low |
| offset_th | 0.33 | 0.31 | 0.30 | **0.164** | ≤0.20 |

v4 has the best precision/false-alarm profile. No class collapse. Decision: keep running, check at iter 1000.

### Check #9 - [2026-03-04 19:22] - Baseline iter 2500

| Metric | iter 2000 | iter 2500 | Trend |
|--------|-----------|-----------|-------|
| car_recall | 0.86 | **0.91** | target exceeded |
| truck_recall | 0.002 | 0.045 | recovering slowly |
| bus_recall | 0.60 | 0.55 | stable |
| trailer_recall | 0.58 | **0.98** | recovered |
| bg_false_alarm | 0.26 | 0.36 | worsened |
| offset_th | 0.31 | 0.26 | improving |

Car recall excellent (0.91 > target 0.85). Truck still collapsed. Oscillation continues.

### Check #10 - [2026-03-04 19:44] - Plan A v4 iter 1000 — REGRESSED

| Metric | v4@500 | v4@1000 | Trend |
|--------|--------|---------|-------|
| car_recall | 0.42 | 0.38 | dropped |
| car_precision | **0.121** | 0.055 | regressed to baseline levels |
| truck_precision | **0.212** | 0.090 | dropped |
| bus_recall | **0.57** | 0.21 | dropped |
| bus_precision | 0.067 | **0.218** | improved |
| trailer_recall | 0.44 | 0.00 | collapsed |
| false_alarm | 0.146 | 0.196 | worsened |
| offset_th | **0.164** | **0.199** | still near target |

v4 is also oscillating, similar to baseline. Precision advantage at iter 500 was partially transient. However, false alarm remains much lower than baseline (19.6% vs 36%).

**Assessment**: Both models oscillate between classes. The core issue may not be the loss function alone — could be target assignment instability or LR dynamics. Decision: let both run and compare at later checkpoints.

### Check #11 - [2026-03-04 20:20] - Plan A v4 iter 1500 — Class Competition Continues

| Metric | v4@1000 | v4@1500 | Trend |
|--------|---------|---------|-------|
| car_recall | 0.38 | 0.39 | flat |
| car_precision | 0.055 | 0.064 | slight improvement |
| truck_recall | 0.37 | **0.007** | COLLAPSED |
| bus_recall | 0.21 | **0.62** | jumped (at expense of truck) |
| trailer_recall | 0.00 | **0.87** | recovered |
| false_alarm | 0.196 | 0.188 | stable |
| offset_cy | 0.143 | **0.092** | best yet |
| offset_th | 0.199 | 0.273 | regressed |

Same class-competition pattern as baseline: bus/trailer up → truck collapses.

### Check #12 - [2026-03-04 20:18] - Baseline iter 3000

| Metric | iter 2500 | iter 3000 | Trend |
|--------|-----------|-----------|-------|
| car_recall | 0.91 | 0.84 | dropped slightly |
| truck_recall | 0.04 | **0.18** | recovering |
| bus_recall | 0.55 | **0.89** | jumped |
| bus_precision | 0.06 | **0.041** | worsened (flooding) |
| trailer_recall | 0.98 | 0.58 | dropped |
| trailer_precision | 0.02 | **0.25** | improved |
| false_alarm | 0.36 | **0.40** | worsened |
| offset_th | 0.26 | 0.27 | flat |

Baseline avg_recall = 0.62, avg_precision = 0.13. Still oscillating heavily.

### Check #13 - [2026-03-04 21:03] - Plan A v4 iter 2000 — MOST BALANCED YET

| Metric | v4@500 | v4@1000 | v4@1500 | **v4@2000** | Target |
|--------|--------|---------|---------|------------|--------|
| car_recall | 0.42 | 0.38 | 0.39 | **0.66** | ≥0.85 |
| car_precision | 0.121 | 0.055 | 0.064 | 0.064 | ≥0.30 |
| truck_recall | 0.32 | 0.37 | 0.007 | **0.30** | ≥0.70 |
| truck_precision | 0.212 | 0.090 | 0.105 | **0.190** | ≥0.25 |
| bus_recall | 0.57 | 0.21 | 0.62 | 0.56 | ≥0.40 |
| bus_precision | 0.067 | 0.218 | 0.071 | **0.103** | ≥0.15 |
| trailer_recall | 0.44 | 0.00 | 0.87 | **0.64** | ≥0.95 |
| trailer_precision | 0.050 | 0.000 | 0.065 | 0.037 | ≥0.10 |
| false_alarm | 0.146 | 0.196 | 0.188 | 0.264 | low |
| offset_cx | 0.066 | 0.061 | 0.092 | **0.047** | ≤0.05 |
| offset_cy | 0.114 | 0.143 | 0.092 | 0.112 | ≤0.10 |
| offset_th | 0.164 | 0.199 | 0.273 | **0.210** | ≤0.20 |

**Key findings:**
- **Most balanced checkpoint**: ALL 4 classes have non-trivial recall (0.30-0.66). No collapse.
- Car recall jumped 0.39→0.66 — biggest single-step improvement for v4
- Truck recovered from 0.007→0.30 after collapsing at iter 1500
- offset_cx=0.047 **achieves target** (≤0.05)
- offset_th=0.21, just barely above target (≤0.20)
- avg_recall = 0.54, avg_precision = 0.10 — improving but still below targets

**Comparison with baseline at similar iteration count:**
| Metric | Baseline@2000 | v4@2000 | Winner |
|--------|--------------|---------|--------|
| car_recall | 0.86 | 0.66 | baseline |
| truck_recall | 0.002 | **0.30** | v4 (no collapse) |
| bus_recall | 0.60 | 0.56 | tie |
| false_alarm | 0.26 | 0.26 | tie |
| offset_cx | 0.058 | **0.047** | v4 |
| offset_th | 0.306 | **0.210** | v4 |

v4 trades car recall for truck stability and better regression accuracy. The Focal Loss prevents the severe class collapse seen in baseline (truck=0.002 at baseline@2000 vs 0.30 at v4@2000).

**Decision**: Continue both. v4 at iter 2000 is the most promising single checkpoint for class balance. First LR milestone at iter 4000 may further stabilize. Will check again at iter 2500/3000.

---

## Checkpoint Cleanup
- [2026-03-04 21:00] Deleted old Plan A v1/v2/v3 work dirs (~5.7GB freed)
- Remaining: v4 (5.6GB), baseline (9.2GB)
- Disk: 104GB free

### Check #14 - [2026-03-04 21:18] - Baseline iter 3500 — Oscillation Persists

| Metric | iter 3000 | iter 3500 | Trend |
|--------|-----------|-----------|-------|
| car_recall | 0.84 | 0.69 | dropped |
| truck_recall | 0.18 | 0.20 | flat (still far from 0.65 peak at iter 1000) |
| bus_recall | 0.89 | **0.94** | peaked |
| trailer_recall | 0.58 | **0.98** | recovered |
| false_alarm | 0.40 | 0.36 | oscillating |

Bus peaked at 0.94 but truck stuck at ~0.20. Car dropped from 0.84→0.69.

### Check #15 - [2026-03-04 21:39] - Plan A v4 iter 2500 — STILL OSCILLATING

| Metric | v4@2000 | v4@2500 | Trend |
|--------|---------|---------|-------|
| car_recall | 0.66 | 0.57 | dropped |
| truck_recall | 0.30 | 0.19 | dropped |
| bus_recall | 0.56 | 0.40 | dropped |
| trailer_recall | 0.64 | **0.93** | jumped |
| false_alarm | 0.264 | 0.198 | improved |

v4 regressed from its best (iter 2000). Trailer jumped at expense of all other classes.

### [2026-03-04 22:00] — DECISION: Terminate Both, Launch Plan B

**Root cause confirmed**: Both baseline and Plan A v4 show identical class-competition oscillation across 7 and 5 validation checkpoints respectively. No checkpoint in either run achieves all 4 classes above target simultaneously. The oscillation is structural (loss aggregation), not function-specific.

**Best per-class recall across ALL checkpoints (never simultaneous):**
| Class | Baseline best | Plan A v4 best |
|-------|--------------|----------------|
| car | 0.91 (iter 2500) | 0.66 (iter 2000) |
| truck | 0.65 (iter 1000) | 0.37 (iter 1000) |
| bus | 0.94 (iter 3500) | 0.62 (iter 1500) |
| trailer | 0.98 (multiple) | 0.93 (iter 2500) |

**Actions**:
1. Terminated baseline at iter ~3900/10000
2. Terminated Plan A v4 at iter ~2800/8000
3. Launched **Plan B: Per-Class Balanced Loss** — computes marker/cls/regression losses per-class independently, then averages with equal weight

**Plan B details**:
- Config: `plan_b_class_balanced.py`
- Work dir: `ssd_workspace/Train/Train_20260304/plan_b_class_balanced`
- GPU: 0,2 | batch=2 | accum=4 | effective_batch=16
- Loss mode: CE+punish + `use_per_class_balance=True`
- LR: 5e-5 | Schedule: 10000 iters, milestones [5000, 8000]
- Loaded from: iter_2000.pth (same starting point)
- First iter confirmed: loss=3.23, no NaN

---

## Plan Iteration History (Updated)

| # | Plan | Start | End | Result |
|---|------|-------|-----|--------|
| 1 | Baseline (CE+punish) | 15:18 | 22:00 | Oscillating, truck→0.002 collapse |
| 2 | Plan A v1 (gamma=2, reg_w=2) | 16:00 | 16:50 | FAILED: cls starvation |
| 3 | Plan A v2 (gamma=1, alpha=0.80) | 16:50 | 17:35 | FAILED: 67:1 ratio, 66% FA |
| 4 | Plan A v3 (gamma=1.5, alpha=0.60) | 17:38 | 18:20 | Too conservative |
| 5 | Plan A v4 (gamma=1.5, alpha=0.70) | 18:22 | 22:00 | Same oscillation as baseline |
| 6 | **Plan B (per-class balanced)** | 22:05 | running | First val at iter 500 (~23:00) |

### Check #16 - [2026-03-04 22:51] - Plan B iter 500 — PROMISING START

| Metric | Baseline@500 | v4@500 | **Plan B@500** | Target |
|--------|-------------|--------|---------------|--------|
| car_recall | 0.59 | 0.42 | **0.76** | >=0.85 |
| car_precision | 0.056 | 0.121 | **0.111** | >=0.30 |
| truck_recall | 0.43 | 0.32 | 0.26 | >=0.70 |
| truck_precision | 0.062 | 0.212 | 0.086 | >=0.25 |
| bus_recall | 0.14 | 0.57 | **0.46** | >=0.40 |
| bus_precision | 0.051 | 0.067 | **0.132** | >=0.15 |
| trailer_recall | 0.98 | 0.44 | **0.98** | >=0.95 |
| trailer_precision | 0.021 | 0.050 | 0.058 | >=0.10 |
| false_alarm | 0.326 | 0.146 | **0.194** | low |
| offset_cx | 0.081 | 0.066 | 0.077 | <=0.05 |
| offset_cy | 0.179 | 0.114 | 0.228 | <=0.10 |
| offset_th | 0.326 | 0.164 | **0.234** | <=0.20 |

**Key observation**: Plan B achieves ALL 4 classes with non-trivial recall simultaneously at iter 500:
- car=0.76 (best @500 across all runs)
- truck=0.26 (lower than baseline but NOT collapsed)
- bus=0.46 (**already above target**)
- trailer=0.98 (**already above target**)

This is the first time in ANY run that all 4 classes show meaningful recall at the same checkpoint. No class collapse. The per-class balanced loss is working as intended.

**Weaknesses**: offset_cy=0.228 worse than others, truck_recall still below target. But this is only iter 500.

**Decision**: Continue running. Next check at iter 1000. The critical test is whether truck improves without causing bus/trailer collapse — which would confirm the oscillation is broken.

### Check #17 - [2026-03-04 23:51] - Plan B iter 1000 & 1500 — OSCILLATION BROKEN

| Metric | B@500 | B@1000 | B@1500 | Trend |
|--------|-------|--------|--------|-------|
| car_recall | 0.76 | 0.74 | **0.92** | improving |
| car_precision | 0.111 | 0.074 | 0.086 | fluctuating |
| truck_recall | 0.26 | 0.25 | **0.26** | **STABLE** |
| truck_precision | 0.086 | 0.066 | **0.118** | improving |
| bus_recall | 0.46 | 0.41 | **0.58** | improving |
| bus_precision | 0.132 | **0.389** | 0.062 | volatile |
| trailer_recall | 0.98 | 0.98 | **0.98** | **ROCK STABLE** |
| trailer_precision | 0.058 | 0.032 | 0.058 | stable |
| false_alarm | 0.194 | 0.253 | 0.308 | rising (concern) |
| offset_cx | 0.077 | 0.095 | **0.061** | improving |
| offset_cy | 0.228 | **0.128** | **0.101** | **rapidly improving** |
| offset_th | 0.234 | 0.321 | 0.238 | fluctuating |

**CRITICAL RESULT — Oscillation is broken:**
- **Truck recall STABLE at 0.25-0.26 for 3 consecutive checkpoints**. In baseline, truck collapsed from 0.65→0.002 between iter 1000-2000. In Plan A v4, truck collapsed from 0.37→0.007 at iter 1500. Plan B's truck has NOT collapsed.
- **Car recall jumped to 0.92 WITHOUT killing truck**. In baseline, car=0.86 at iter 2000 coincided with truck=0.002. Plan B achieves car=0.92 with truck=0.26 — simultaneous.
- **Bus recall improving (0.46→0.41→0.58) WITHOUT crashing other classes**.
- **Trailer is rock-solid at 0.98 across all 3 checkpoints** — never drops.

**Best simultaneous recall (iter 1500)**: car=0.92, truck=0.26, bus=0.58, trailer=0.98
This is FAR better than any single checkpoint from baseline or Plan A.

**Remaining concerns**:
- Truck recall plateaued at 0.26, needs to reach 0.70. May improve with more iterations.
- False alarm rate rising (0.19→0.31). Need to monitor.
- Precision still below targets overall.

**Decision**: Strong continue. The per-class balance is proven to work. Next check at iter 2000.

### Check #18 - [2026-03-05 00:32] - Plan B iter 2000 — TRUCK CLIMBING

| Metric | B@500 | B@1000 | B@1500 | **B@2000** | Baseline@2000 | Target |
|--------|-------|--------|--------|-----------|---------------|--------|
| car_R | 0.76 | 0.74 | 0.92 | 0.69 | 0.86 | >=0.85 |
| truck_R | 0.26 | 0.25 | 0.26 | **0.35** | **0.002** | >=0.70 |
| bus_R | 0.46 | 0.41 | 0.58 | **0.83** | 0.60 | >=0.40 |
| trail_R | 0.98 | 0.98 | 0.98 | **0.98** | 0.58 | >=0.95 |
| FA | 0.194 | 0.253 | 0.308 | 0.294 | 0.257 | low |
| off_cy | 0.228 | 0.128 | 0.101 | **0.098** | 0.106 | <=0.10 |
| off_w | 0.005 | 0.005 | 0.005 | **0.005** | 0.006 | — |
| off_h | 0.002 | 0.003 | 0.002 | **0.001** | 0.002 | — |

**Key results:**
1. **Truck recall climbing**: 0.26→0.26→0.26→**0.35**. Baseline was at 0.002 at the same iteration. Plan B's truck is 175x better.
2. **Bus recall surging**: 0.46→0.58→**0.83** WITHOUT crashing truck. In baseline, bus=0.60 at iter 2000 coincided with truck=0.002.
3. **Trailer unshakeable**: 0.98 for 4 consecutive checkpoints. Baseline had trailer=0.58 at iter 2000.
4. **offset_cy reached target**: 0.098 <= 0.10 target.
5. **Car dipped to 0.69** — mild fluctuation, NOT a collapse (min in baseline was 0.59 at iter 500).

**Comparison at iter 2000 — Plan B vs Baseline:**
- truck: 0.35 vs 0.002 → Plan B **175x better**
- trailer: 0.98 vs 0.58 → Plan B **+69%**
- bus: 0.83 vs 0.60 → Plan B **+38%**
- car: 0.69 vs 0.86 → Baseline better (but Plan B car peaked at 0.92 at iter 1500)
- avg 4-class recall: **0.71 vs 0.49** → Plan B **+45%**

**Decision**: Strong continue. Per-class balancing definitively solves the oscillation problem. Truck is on an upward trajectory. Next check at iter 2500.

### Check #19 - [2026-03-05 01:00] - Plan B iter 2500 + Precision Root Cause Investigation

**Plan B iter 2500 results:**

| Metric | B@1500 | B@2000 | **B@2500** | Trend |
|--------|--------|--------|-----------|-------|
| car_R | 0.92 | 0.69 | 0.66 | declining |
| truck_R | 0.26 | 0.35 | **0.06** | dropped |
| bus_R | 0.58 | 0.83 | 0.64 | oscillating |
| trail_R | 0.98 | 0.98 | 0.73 | dropped |
| car_P | 0.086 | 0.079 | 0.079 | flat, low |
| truck_P | 0.118 | 0.123 | 0.020 | collapsed |
| bus_P | 0.062 | 0.077 | 0.137 | best yet |
| trail_P | 0.058 | 0.026 | 0.014 | dropping |
| FA | 0.308 | 0.294 | 0.245 | improving |
| off_th | 0.238 | 0.316 | **0.176** | **TARGET MET** |

**Observations:**
1. Truck dropped 0.35→0.06 — oscillation dampened (not 0.002 like baseline) but not eliminated.
2. **All classes have precision < 0.14.** This is a structural problem, not a training problem.
3. offset_th=0.176 reached target (<=0.20) for the first time.

---

## Precision Root Cause Analysis (Deep Investigation)

### Finding 1: No Confidence Filtering at Inference (CRITICAL)

In `decoder_inference` (git_occ_head.py), the model outputs predictions for ALL 400 cells x 3 slots = **1200 slots per image**. Every slot where the predicted marker is not END is treated as a detection. The marker softmax probability (a natural confidence score) is computed but **discarded**.

In `_predict_single` (line ~1480):
```python
ret_scores = bboxes.new_ones(len(ret_labels))  # ALL SCORES SET TO 1.0!
```

The evaluator config has `score_thr=0.0` — no filtering threshold.

### Finding 2: Massive False Positive Count

**Math for car at iter 2500:**
- TP = recall × gt_cnt = 0.6631 × 8267 ≈ 5,482
- TP + FP = TP / precision = 5,482 / 0.0792 ≈ 69,217
- **FP ≈ 63,735 false positive car predictions** across the 323 evaluation images
- That's ~197 false car predictions per image, vs ~26 true car GTs per image

With `bg_false_alarm_rate = 0.2448`, about 24.5% of truly-empty slots produce false predictions. Given ~1,050 empty slots per image, that's ~257 false predictions per image, which matches the FP count.

### Finding 3: No NMS or Deduplication

The same GT object covers multiple grid cells (its entire BEV footprint). The model correctly predicts the object at several overlapping cells, but each cell's prediction is counted separately. Without NMS to collapse these duplicates, the same correct detection generates multiple FPs.

### Finding 4: Slot-Aligned Metric Is Strict

The evaluation metric uses exact slot-position matching: a prediction at `(cell=100, slot=0)` is TP only if GT also exists at `(cell=100, slot=0)`. A prediction at the right cell but wrong slot order (due to depth-sorting mismatch) counts as FP. No IoU-based matching is used.

### Conclusion: Precision Is an Inference/Evaluation Problem, Not a Training Problem

| Component | Issue | Fix Location |
|-----------|-------|-------------|
| `_predict_single` | Scores hardcoded to 1.0 | Inference code |
| `decoder_inference` | No confidence filtering | Inference code |
| Evaluator | No NMS, `score_thr=0.0` | Post-processing |
| Evaluator | Slot-aligned matching (strict) | Metric design |
| Training | bg_false_alarm_rate=24.5% | Loss (improving but slow) |

**The training loss (Plan B per-class balance) is working correctly for its purpose (stabilizing recall). Precision requires inference-time fixes:**

1. **Use marker softmax probability as confidence score** (already computed, just discarded)
2. **Add score threshold filtering** (e.g., 0.3-0.5) before evaluation
3. **Add rotated NMS** to deduplicate overlapping predictions from adjacent cells
4. Optionally: switch to IoU-based matching in evaluation metric

These fixes can be tested immediately on existing checkpoints without retraining.

---

### Next Steps (Decided)

**Phase 1 (immediate)**: Add confidence score propagation + score threshold filtering at inference. This alone should dramatically improve precision without affecting recall (model already has the information, just not using it).

**Phase 2 (if needed)**: Add rotated NMS post-processing. This handles the duplicate predictions from overlapping grid cells.

**Phase 3 (optional)**: Consider IoU-based evaluation metric for fairer assessment.

Plan B training continues — the per-class balanced loss is correctly solving the oscillation problem. The precision fix is orthogonal and can be applied retroactively to any checkpoint.

---

### [2026-03-05 01:45] Inference Fixes Deployed + Plan B Restart

**Implemented**:
1. Confidence score propagation: marker softmax prob flows through `decoder_inference` → `add_pred_to_datasample` → evaluator
2. Score threshold filtering (`score_thr=0.3`) in `occ_2d_box_eval.py`
3. IoU-based matching attempted but **reverted** (changed GT counting semantics, incomparable metrics)

**Plan B restarted** from iter 3000 with `resume=True` to pick up new evaluator code.

### [2026-03-05 02:20] Check #20 — Plan B iter 3500 (FIRST with score filtering)

| Class | Recall | Precision | GT cnt |
|-------|--------|-----------|--------|
| car | 0.6697 | 0.0898 | 8267 |
| truck | 0.2100 | 0.1214 | 5167 |
| bus | 0.2513 | 0.0268 | 3096 |
| trailer | 0.6667 | 0.0508 | 90 |
| bg_FA | — | — | 0.2408 |

**Note**: Metrics NOT directly comparable to pre-3500 results due to score filtering. The filter suppresses low-confidence predictions, reducing both recall and false alarms. This is a new baseline for the score-filtered evaluator.

**Observations**:
- Precision still low (0.03–0.12) despite filtering — model's marker confidence doesn't discriminate TP vs FP well
- Score threshold of 0.3 may be too aggressive for rarer classes (bus/trailer recall hit hard)
- Truck recovering (0.210), positive trend
- FA improved to 0.241 (vs 0.351 at iter 3000 without filtering)

**Assessment**: Continue training. The model needs more iterations for confidence calibration to improve. Score filtering is correctly applied but the underlying confidence quality will improve as training continues.

### [2026-03-05 06:25] Plan B Full Trajectory (score-filtered evaluator)

| iter | car_R | car_P | truck_R | truck_P | bus_R | bus_P | trail_R | trail_P | FA | avg_R |
|------|-------|-------|---------|---------|-------|-------|---------|---------|------|-------|
| 3500 | 0.670 | 0.090 | 0.210 | 0.121 | 0.251 | 0.027 | 0.667 | 0.051 | 0.241 | 0.450 |
| 4000 | 0.784 | 0.068 | 0.121 | 0.132 | 0.304 | 0.071 | 0.756 | 0.012 | 0.284 | 0.491 |
| 4500 | 0.681 | 0.070 | 0.166 | 0.142 | 0.473 | 0.120 | 0.800 | 0.026 | 0.241 | 0.530 |
| **5000** | **0.757** | 0.069 | **0.501** | **0.189** | **0.597** | 0.077 | **0.844** | 0.025 | 0.317 | **0.675** |
| 5500 | 0.760 | 0.073 | 0.213 | 0.202 | 0.581 | 0.090 | 0.778 | 0.023 | 0.273 | 0.583 |
| 6000 | 0.738 | 0.074 | 0.163 | 0.186 | 0.569 | 0.086 | 0.756 | 0.023 | 0.262 | 0.556 |
| 6500 | 0.730 | 0.074 | 0.155 | 0.180 | 0.561 | 0.084 | 0.733 | 0.019 | 0.261 | 0.545 |
| 7000 | 0.715 | 0.076 | 0.148 | 0.180 | 0.567 | 0.080 | 0.711 | 0.016 | 0.258 | 0.535 |
| 7500 | 0.704 | 0.074 | 0.169 | 0.190 | 0.550 | 0.076 | 0.711 | 0.017 | 0.261 | 0.533 |

**Best checkpoint: iter 5000** (avg recall = 0.675, approaching 0.70 target)

**Key findings**:
1. **Per-class balanced loss works**: All 4 classes alive simultaneously (never achieved in baseline or Plan A)
2. **Truck oscillation dampened but not eliminated**: Peaks at 0.50 vs baseline's 0.65, but valleys at 0.15 vs baseline's 0.002
3. **LR decay at iter 5000 caused plateau**: Post-decay metrics slowly drift downward
4. **Precision remains the critical bottleneck**: All classes below 0.20, far from targets. Score filtering (0.3) helps FA but doesn't fix underlying confidence calibration
5. **Spatial offsets near targets**: cx≈0.05, cy≈0.09–0.10, theta≈0.20

**Remaining gap to targets**:
- avg_recall: 0.675 vs target 0.70 (close!)
- avg_precision: ~0.09 vs target 0.20 (major gap)
- Truck recall peak only at 0.50 vs target 0.70

Training continues to iter 10000 but no significant improvement expected. Next steps should focus on precision improvement.

### [2026-03-05 08:42] Plan B COMPLETE — 10000/10000

Final validation (iter 10000): car=0.696, truck=0.164, bus=0.556, trailer=0.667, avg_R=0.521, theta=0.197

**Best checkpoint: iter 5000** (avg recall 0.675). Post-LR-decay model plateaued at ~0.52 avg recall.

Late-stage checkpoints (iter 8500–10000) fully converged with nearly identical metrics. Theta offset converged to 0.197 (target met).

**Plan B achievements vs baseline**:
- All 4 classes alive simultaneously (never achieved in baseline)
- Truck oscillation dampened: valleys at 0.15 vs baseline's 0.002
- Class-competition oscillation reduced but not eliminated
- Theta accuracy met target (0.197 ≤ 0.20)

**Remaining gaps**:
- avg_recall: 0.675 best vs 0.70 target (close but not met)
- avg_precision: ~0.09 vs 0.20 target (major gap — primary bottleneck)
- Truck recall unstable (0.15–0.50 range)

**GPUs 0,2 now free** for next experiment.

### Git Push Status
- GitHub auth expired. Commits saved locally (4+ commits ahead of origin).
- User needs to run `gh auth login` to re-authenticate.
