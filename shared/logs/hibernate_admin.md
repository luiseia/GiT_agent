# Admin Agent Hibernate State
**Timestamp**: 2026-03-07 00:10
**Reason**: Emergency hibernate requested by user

---

## 1. ORCH Instructions Status

| ID | Status | Summary |
|----|--------|---------|
| ORCH_0306_0057_001 | **COMPLETED** | BUG-12 fix (slot ordering). Report: `shared/logs/report_ORCH_001.md` |
| ORCH_0306_0255_002 | **COMPLETED** | BUG-9 diagnosis (grad clip). Report: `shared/logs/report_ORCH_002.md` |
| ORCH_0306_1410_003 | **COMPLETED** | P1 final eval + P2 launch. Report: `shared/logs/report_ORCH_003.md` |
| ORCH_0306_2100_004 | **COMPLETED** | BUG-8 fix + BUG-10 warmup + P3 launch. Report: `shared/logs/report_ORCH_004.md` |

No pending ORCH instructions at time of hibernate.

---

## 2. Training Progress

### P1 (Center/Around) — COMPLETED
- **Config**: `configs/GiT/plan_d_reg_w1.py`
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260305/plan_d_center_around/`
- **Final**: 6000/6000
- **P1@6000 eval (BUG-12 fixed, single-GPU)**: car_R=0.628, truck_R=0.358, bus_R=0.627, trailer_R=0.644, bg_FA=0.163

### P2 (BUG-9 fix, max_norm=10.0) — COMPLETED
- **Config**: `configs/GiT/plan_e_bug9_fix.py`
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_e_bug9_fix/`
- **Final**: 6000/6000
- **P2@6000 val (DDP)**: car_R=0.596, truck_R=0.290, bus_R=0.623, trailer_R=0.689, bg_FA=0.198
- **All 12 checkpoints saved** (iter 500-6000)

### P3 (BUG-8 fix + warmup) — RUNNING
- **Config**: `configs/GiT/plan_f_bug8_fix.py`
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/`
- **Progress**: iter **2840/4000** (71%)
- **LR**: 2.5e-06 (post-milestone at 2500)
- **Loss**: ~0.14-1.75 (oscillating)
- **grad_norm**: 2.4-19.0 (majority unclipped at max_norm=10.0)
- **ETA**: ~58 min remaining, finishes ~01:08
- **GPU**: 0, 2 (22.4GB/23GB each)
- **Checkpoints saved**: iter 500, 1000, 1500, 2000, 2500
- **Remaining checkpoints**: 3000 (soon), 3500, 4000

### P3 Validation Results (5 checkpoints, DDP 2-GPU)

| iter | car_R | truck_R | bus_R | trail_R | bg_FA | offset_th |
|------|-------|---------|-------|---------|-------|-----------|
| 500  | 0.576 | 0.374   | 0.697 | 0.667   | 0.212 | 0.253 |
| 1000 | 0.578 | 0.390   | 0.576 | 0.511   | 0.206 | 0.232 |
| 1500 | 0.598 | 0.382   | 0.680 | 0.756   | 0.227 | 0.234 |
| 2000 | 0.608 | 0.152   | 0.737 | 0.689   | 0.216 | 0.191 |
| 2500 | 0.606 | 0.336   | 0.667 | 0.667   | 0.199 | 0.215 |

**Observations**: Truck still oscillates (0.15-0.39). Bus consistently above target (0.40). offset_th approaching target at iter 2000 (0.191).

---

## 3. Uncommitted Code Changes in GiT Repo

### Modified files (important):
| File | Change | Status |
|------|--------|--------|
| `MASTER_PLAN.md` | Updated with P1 trajectory, Plan E strategy | **UNCOMMITTED** |
| `mmdet/evaluation/metrics/occ_2d_box_eval.py` | **BUG-12 FIX**: cell-internal class-based matching | **UNCOMMITTED** |
| `mmdet/models/dense_heads/git_occ_head.py` | **BUG-8 FIX**: cls loss bg class + all prior changes | **UNCOMMITTED** |
| `configs/GiT/plan_e_bug9_fix.py` | P2 config (max_norm=10.0, load P1@6000) | **NEW, UNCOMMITTED** |
| `configs/GiT/plan_f_bug8_fix.py` | P3 config (BUG-8+BUG-10, warmup, 4000 iters) | **NEW, UNCOMMITTED** |

### Other modified (from prior sessions):
- `configs/GiT/plan_a_focal_loss.py` — focal loss config
- `configs/GiT/single_occupancy_base_front.py` — base config
- `mmdet/datasets/pipelines/generate_occ_flow_labels.py` — pipeline changes
- `experiment_logs/experiment_report.md` — experiment log
- `experiment_logs/session_history.md` — session history

### New untracked files:
- `RESEARCHER_ROLE.md`
- `configs/GiT/plan_b_class_balanced.py`
- `configs/GiT/plan_c_bg_fix.py`
- `configs/GiT/plan_d_reg_rebalance.py`
- `configs/GiT/plan_d_reg_w1.py` (P1 config)

---

## 4. Key Path Discovery

**ssd_workspace** does NOT exist as a symlink/directory. Actual path is:
```
/mnt/SSD/GiT_Yihao/
```
All training dirs are under `/mnt/SSD/GiT_Yihao/Train/`.

---

## 5. Next Actions (for resuming agent)

1. **Wait for P3 to finish** (~01:08). Collect final checkpoints 3000-4000.
2. **Evaluate P3 results** — check if BUG-8 fix improved avg_precision.
3. **All historical metrics** use DDP 2-GPU eval (GT counts ~2x single-GPU). Single-GPU eval needed for accurate comparison.
4. **BUG-12 fix is applied** in current eval code. All P3 val results use BUG-12 fixed eval.
5. **BUG-8 fix is applied** in current training code. P3 is the first run with BUG-8 fix active.

---

## 6. GPU Status at Hibernate

| GPU | User | Task | Memory |
|-----|------|------|--------|
| 0 | yz0370 | P3 training | 22434/49140 MiB |
| 1 | (light use) | — | 3056/49140 MiB |
| 2 | yz0370 | P3 training | 22966/49140 MiB |
| 3 | (light use) | — | 3250/49140 MiB |
