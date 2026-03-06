# Report: ORCH_002 — BUG-9 Gradient Clipping 100% Diagnosis

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-06 03:00
**Status**: COMPLETED

---

## 1. Problem Statement

P1 training config (`plan_d_reg_w1.py`) uses `clip_grad=dict(max_norm=0.5, norm_type=2)`. All logged iterations show `grad_norm > 0.5`, meaning 100% of gradient updates are clipped. AdamW degrades to Sign-SGD: every update has constant magnitude `lr * 0.5 / ||params||`, and the LR schedule's effect is purely directional, not magnitude-based.

---

## 2. Phase 1: Diagnosis

### 2.1 Grad Norm Distribution (P1 training log, 600 logged iterations)

| Statistic | Value |
|-----------|-------|
| Min | 1.4856 |
| Max | 87.9144 |
| Mean | 14.5034 |
| Median | 8.8945 |
| Stdev | 14.2079 |
| P95 | 44.9754 |
| P99 | 75.0422 |

**Percentile analysis at candidate thresholds:**

| Threshold | % iters unclipped | Interpretation |
|-----------|-------------------|----------------|
| 0.5 (current) | 0.0% | All clipped — Sign-SGD |
| 1.0 | 0.0% | Still all clipped |
| 5.0 | 19.2% | Only small grads pass |
| 10.0 | 55.7% | Majority pass, outliers clipped |
| 20.0 | 78.7% | Most pass, heavy outliers clipped |
| 50.0 | 96.2% | Nearly all pass, only spikes clipped |

### 2.2 Config Confirmation

```python
# plan_d_reg_w1.py line 368
clip_grad=dict(max_norm=0.5, norm_type=2),
```

- `norm_type=2`: L2 norm computed over ALL model parameters (global norm)
- `max_norm=0.5`: If global L2 norm > 0.5, scale all gradients by `0.5 / norm`
- Optimizer: AdamW with `lr=5e-5, weight_decay=0.01`
- Layer-wise LR multipliers: backbone 0.05-0.80, new layers 1.0, head 1.0

### 2.3 Loss Component Analysis

**Loss architecture** (from `loss_by_feat_single`, lines 790-1015):

```
total_loss = loss_cls_combined + loss_reg
where:
  loss_cls_combined = (loss_marker + loss_cls) * cls_loss_weight   [weight=1.0]
  loss_reg          = (gx + gy + dx + dy + w + h + th_g*1.2 + th_f) * reg_loss_weight  [weight=1.0]
```

**Component breakdown:**

| Component | Sub-losses | Loss Type | Typical Scale |
|-----------|-----------|-----------|---------------|
| Marker | 1 (4-class CE: near/far/occluded/end) | CE + punish weights (3.0/1.0) | ~0.3-0.8 |
| Class | 1 (5-class CE: 4 classes + bg) | CE + punish weight (1.0 bg) | ~0.1-0.5 |
| Regression | 8 (gx, gy, dx, dy, w, h, th_group, th_fine) | Expectation L1 | ~0.05-0.15 each |

**Key observations:**

1. **Regression dominates gradient magnitude**: 8 sub-losses summed, each with its own softmax + L1 computation. The softmax over large bin ranges (e.g., wh_w has 101 bins) produces dense gradients across many parameters.

2. **Per-class balanced loss amplifies**: With `use_per_class_balance=True`, each class contributes equally regardless of frequency. Rare classes (trailer: 0.5% of GT) produce high per-sample gradients that are NOT averaged down by their low count.

3. **Center/Around weighting**: `center_weight=2.0` doubles loss for center cells. This doesn't change the mean gradient direction much but increases magnitude.

4. **Historical evidence**: From Plan A v1 (before per-class balance): `loss_cls=0.067, loss_reg=1.96` at convergence — reg was 30x larger than cls. With per-class balance the gap narrows, but reg still dominates because it has 8 summed sub-losses.

5. **From P1 hibernate state**: Total loss oscillated 0.49-0.94 at iter 4600. Given `loss_cls + loss_reg` and the historical 1:3-1:5 ratio, estimated split is approximately `loss_cls ~ 0.1-0.2, loss_reg ~ 0.3-0.7`.

**Gradient flow path:**

```
loss_reg (dominant)
  -> 8 regression sub-losses -> expectation L1 -> softmax over bins
  -> gradients flow into: decoder layers (12-17), head projection, vocabulary embed
  -> these layers have lr_mult=1.0, so full-magnitude gradients

loss_cls (secondary)
  -> marker CE + class CE -> per-class balanced
  -> same decoder/head parameters
  -> but CE on small label sets (4-5 classes) produces sparser gradients
```

The high grad_norm is primarily driven by **regression sub-losses flowing through shared decoder parameters at full learning rate**. The 8 regression terms produce dense gradients (softmax over 10-101 bins each) that accumulate additively in the shared layers.

---

## 3. Phase 2: Fix Options Evaluation

### Option A: Raise max_norm

| max_norm | % Unclipped | Pros | Cons |
|----------|-------------|------|------|
| 5.0 | 19.2% | Conservative, clips most | Still clips 80%, limited improvement |
| **10.0** | **55.7%** | **Median passes, outliers clipped** | **Moderate risk** |
| 20.0 | 78.7% | Most iterations natural | Large spikes (P95=45) unchecked |
| 50.0 | 96.2% | Nearly no clipping | Potential instability from P99=75 spikes |

**Assessment**: Simple, effective, low implementation risk. A value of **10.0** lets the majority of iterations use their natural gradient magnitude while still protecting against the heavy-tail spikes (P95=45, P99=75). This restores AdamW's adaptive behavior for normal iterations and makes the LR schedule meaningful again.

### Option B: Loss Scaling

Scale all losses down by a constant factor (e.g., `/ 30`) to bring mean grad_norm from 14.5 to ~0.5.

**Assessment**: **Not recommended.**
- Fragile: the correct scale factor depends on training stage, batch composition, and model state
- Equivalent to reducing LR by the same factor — but we already have lr=5e-5 which is low
- Doesn't address the root cause (0.5 is simply too low for this model size)
- If loss landscape changes (new config, different checkpoint), the factor needs recalibration

### Option C: Per-layer Clipping

Apply different clip thresholds to backbone vs decoder vs head parameters.

**Assessment**: **Not recommended as primary fix.**
- mmengine's `OptimWrapper.clip_grad` only supports global clipping; per-layer requires custom hook
- Implementation complexity is high for uncertain benefit
- The layer-wise LR multipliers already handle the backbone/head gradient balance
- Could be a secondary refinement if Option A proves insufficient

---

## 4. Recommendation

**Primary fix: Option A with max_norm=10.0**

Rationale:
1. Lets 55.7% of iterations use natural gradients (currently 0%)
2. Still clips the dangerous heavy-tail: P95=45 gets clipped to 10.0 (4.5x reduction)
3. Restores LR schedule effectiveness: when grad_norm < 10.0, the effective step size is `lr * grad_norm`, not `lr * 0.5`
4. Minimal code change: single number in config
5. Conservative choice: 10.0 is the median, so we're not removing all safety

**Secondary consideration**: If 10.0 proves too aggressive (training instability, loss spikes), fall back to 5.0. If too conservative (still too much clipping, slow convergence), try 20.0.

**Plan E config already prepared** (`configs/GiT/plan_e_bug9_fix.py`) with `max_norm=5.0`. Based on this analysis, **recommend changing to 10.0** instead of 5.0 for better coverage. With 5.0, 80.8% of iterations are still clipped.

---

## 5. Theoretical Impact

With max_norm=0.5 (current):
```
effective_step = lr * 0.5 = 5e-5 * 0.5 = 2.5e-5  (constant for ALL iterations)
After LR decay to 5e-6:  effective_step = 5e-6 * 0.5 = 2.5e-6  (still constant)
LR decay ratio: 10x (as intended)
```

With max_norm=10.0 (proposed):
```
When grad_norm=8.9 (median): effective_step = lr * 8.9 (NATURAL, adaptive)
When grad_norm=45 (P95):     effective_step = lr * 10.0 (clipped, safe)
After LR decay: both scale proportionally — schedule works correctly
```

The key insight: with the current 0.5 threshold, the LR schedule "works" in the sense that the constant multiplier decreases. But AdamW's per-parameter adaptive scaling is completely neutralized because every gradient is scaled by the same global factor `0.5/norm`. Raising to 10.0 lets AdamW's first and second moment estimates actually influence the update magnitude for the majority of iterations.

---

## 6. Verification Checklist

- [x] Grad norm distribution computed (600 iterations)
- [x] Config clip_grad setting confirmed (max_norm=0.5, norm_type=2)
- [x] Loss components analyzed (8 regression sub-losses dominate)
- [x] Three fix options evaluated with clear recommendation
- [x] Report written to `shared/logs/report_ORCH_002.md`
