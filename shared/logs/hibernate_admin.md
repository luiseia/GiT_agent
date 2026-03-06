# Admin Agent Hibernate State
**Timestamp**: 2026-03-06 01:30
**Reason**: Emergency hibernate requested by user

---

## 1. ORCH Instructions Status

| ID | Status | Summary |
|----|--------|---------|
| ORCH_0306_0057_001 | **COMPLETED** | BUG-12 fix (slot ordering). Report: `shared/logs/report_ORCH_001.md` |

No other pending ORCH instructions at time of hibernate.

---

## 2. Training Progress

### P1 (Center/Around) — RUNNING
- **Config**: `configs/GiT/plan_d_reg_w1.py`
- **Work dir**: `ssd_workspace/Train/Train_20260305/plan_d_center_around/`
- **Progress**: iter **4600/6000** (76.7%)
- **LR**: 2.5e-07 (post-decay)
- **Loss**: ~0.49-0.94 (oscillating normally)
- **grad_norm**: 5.4-8.6 (BUG-9 still active, 100% clipped at 0.5)
- **ETA**: ~01:13 remaining, finishes ~02:43
- **GPU**: 0, 2 (22.4GB/23GB each)
- **Checkpoints saved**: iter 500-4000 (every 500)
- **Remaining checkpoints**: 4500 (imminent), 5000, 5500, 6000

### P1 Validation Results (8 checkpoints so far)

| iter | car_R | truck_R | bus_R | trail_R | bg_FA |
|------|-------|---------|-------|---------|-------|
| 500  | 0.640 | 0.401   | 0.285 | 0.978   | 0.203 |
| 1000 | 0.562 | 0.273   | 0.718 | 0.867   | 0.198 |
| 1500 | 0.451 | 0.160   | 0.780 | 0.956   | 0.253 |
| 2000 | 0.512 | 0.291   | 0.648 | 0.756   | 0.175 |
| 2500 | 0.478 | 0.150   | 0.364 | 0.689   | 0.125 |
| 3000 | 0.670 | 0.178   | 0.236 | 0.822   | 0.265 |
| 3500 | 0.604 | 0.226   | 0.457 | 0.689   | 0.209 |
| 4000 | 0.566 | 0.193   | 0.472 | 0.644   | 0.198 |

**Verdict**: Partial success. Truck never collapsed below 0.08 (first time in any plan). Oscillation dampened but not broken.

---

## 3. Uncommitted Code Changes in GiT Repo

### Modified files (important):
| File | Change | Status |
|------|--------|--------|
| `MASTER_PLAN.md` | Updated with P1 trajectory, Plan E strategy | **UNCOMMITTED** |
| `mmdet/evaluation/metrics/occ_2d_box_eval.py` | **BUG-12 FIX**: cell-internal class-based matching | **UNCOMMITTED** |
| `configs/GiT/plan_e_bug9_fix.py` | Plan E config (clip_grad 0.5->5.0, load P1@2000) | **NEW, UNCOMMITTED** |

### Other modified (from prior sessions):
- `configs/GiT/plan_a_focal_loss.py` — focal loss config
- `configs/GiT/single_occupancy_base_front.py` — base config
- `mmdet/datasets/pipelines/generate_occ_flow_labels.py` — pipeline changes
- `mmdet/models/dense_heads/git_occ_head.py` — head changes (center/around, per-class balance)
- `experiment_logs/experiment_report.md` — experiment log
- `experiment_logs/session_history.md` — session history

### New untracked files:
- `RESEARCHER_ROLE.md`
- `configs/GiT/plan_b_class_balanced.py`
- `configs/GiT/plan_c_bg_fix.py`
- `configs/GiT/plan_d_reg_rebalance.py`
- `configs/GiT/plan_d_reg_w1.py` (P1 config, actively used)
- `configs/GiT/plan_e_bug9_fix.py` (Plan E, ready to launch)

---

## 4. Next Actions (for resuming agent)

1. **Wait for P1 to finish** (~02:43). Collect final checkpoints 4500-6000.
2. **Launch Plan E** on GPU 0,2:
   ```bash
   CUDA_VISIBLE_DEVICES=0,2 python -m torch.distributed.launch \
     --nproc_per_node=2 --master_port=29700 \
     tools/train.py configs/GiT/plan_e_bug9_fix.py \
     --launcher pytorch \
     --work-dir ssd_workspace/Train/Train_20260306/plan_e_bug9_fix
   ```
3. **Update MASTER_PLAN** with P1 final results and Plan E launch.
4. **BUG-12 fix is applied** but NOT committed to GiT repo. The eval code in the running P1 training does NOT have this fix (it was running before the fix). Future evals will use the fixed code.
5. **All historical metrics in MASTER_PLAN** were computed with OLD slot-aligned eval. Post-BUG-12 metrics are ~28-72% higher for truck/bus. Direct comparison is NOT valid.

---

## 5. GPU Status at Hibernate

| GPU | User | Task | Memory |
|-----|------|------|--------|
| 0 | yz0370 | P1 training | 22434/49140 MiB |
| 1 | yl0826 | PETR | 31220/49140 MiB |
| 2 | yz0370 | P1 training | 22966/49140 MiB |
| 3 | yl0826 | PETR | 31220/49140 MiB |
