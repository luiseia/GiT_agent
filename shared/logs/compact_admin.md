# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 00:00
**Reason**: Context save after ORCH_009/010/011

---

## 1. Current State

**P5b training RUNNING** on GPU 0,2 (PID 282655)
- Config: `configs/GiT/plan_i_p5b_3fixes.py`
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/`
- Progress: iter **60/6000** (~1%), ETA ~05:05
- Warmup phase (500 iter), LR ramping up
- Three fixes applied: BUG-17 LR milestones, sqrt balance, dual-layer proj
- Load from: P5@4000

**P5 training COMPLETED** (6000/6000)
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/`

ORCH_009 (polygon visualization) pending — MEDIUM priority, will execute after P5b stabilizes.

---

## 2. ORCH History (This Session)

| ORCH | Status | Summary |
|------|--------|---------|
| ORCH_005 | COMPLETED | AABB->rotated polygon fix + BUG-11 + P4 launched |
| ORCH_006 | PARTIAL | DINOv3 extraction script written, Python 3.8 blocker |
| ORCH_007 | COMPLETED | DINOv3 features extracted (323 images, 24.15 GB) |
| ORCH_008 | COMPLETED | PreextractedFeatureEmbed + P5 launched |
| ORCH_009 | PENDING | Rotated polygon visualization (MEDIUM) |
| ORCH_010 | COMPLETED | P5b 3 fixes: LR milestones, sqrt balance, dual proj |
| ORCH_011 | COMPLETED | work_dirs migrated to SSD + symlinks |

---

## 3. CRITICAL: git reset incident

All uncommitted tracked-file modifications were wiped by repeated `git reset --hard HEAD` (visible in reflog). Cause unknown (no git hooks found). All code changes were reconstructed from context memory:
- vit_git.py: PreextractedFeatureEmbed + proj_hidden_dim
- git.py: preextracted forward mode
- formatting.py: sample_idx propagation
- generate_occ_flow_labels.py: AABB fix + BUG-11
- git_occ_head.py: BUG-8 + per_class_balance + balance_mode + _per_class_reg_loss
- occ_2d_box_eval.py: BUG-12

**ACTION NEEDED**: Commit all changes ASAP to prevent future loss.

---

## 4. P5 Complete Validation Trajectory (DDP 2-GPU)

| iter | car_R | car_P | truck_R | truck_P | bus_R | trail_R | trail_P | bg_FA | offset_th |
|------|-------|-------|---------|---------|-------|---------|---------|-------|-----------|
| 500  | 0.932 | 0.055 | 0.025 | 0.027 | 0.000 | 0.000 | 0.000 | 0.320 | 0.216 |
| 1000 | 0.952 | 0.052 | 0.000 | 0.000 | 0.000 | 0.056 | 0.000 | 0.354 | 0.225 |
| 1500 | 0.955 | 0.057 | 0.418 | 0.037 | 0.000 | 0.000 | 0.000 | 0.442 | 0.201 |
| 2000 | 0.945 | 0.073 | 0.216 | 0.019 | 0.000 | 0.056 | 0.001 | 0.383 | 0.222 |
| 2500 | 0.793 | 0.073 | 0.080 | 0.030 | 0.409 | 0.528 | 0.004 | 0.321 | 0.215 |
| 3000 | 0.728 | 0.091 | 0.230 | 0.048 | 0.118 | 0.556 | 0.006 | 0.260 | 0.232 |
| 3500 | 0.779 | 0.093 | 0.679 | 0.072 | 0.120 | 0.000 | 0.000 | 0.290 | 0.197 |
| **4000** | 0.569 | 0.090 | 0.421 | **0.130** | 0.315 | 0.472 | 0.006 | 0.213 | **0.142** |
| 4500 | 0.529 | 0.091 | 0.317 | 0.095 | 0.058 | 0.361 | 0.005 | **0.167** | 0.226 |
| 5000 | 0.615 | 0.085 | 0.199 | 0.086 | 0.002 | 0.333 | 0.033 | 0.160 | 0.163 |
| 5500 | 0.721 | 0.092 | 0.203 | 0.065 | 0.014 | 0.417 | 0.046 | 0.186 | 0.182 |
| 6000 | 0.682 | 0.089 | 0.228 | 0.065 | 0.011 | 0.500 | 0.043 | 0.190 | 0.192 |

**P5 best checkpoint**: iter 4000 (truck_P=0.130, offset_th=0.142 — both all-time best)

---

## 5. P5b (Plan I) Config Diff vs P5

| Parameter | P5 (plan_h) | **P5b (plan_i)** | Fix |
|-----------|-------------|-------------------|-----|
| load_from | P4@500 | **P5@4000** | — |
| warmup | 1000 | **500** | BUG-17 |
| begin (MultiStepLR) | 1000 | **500** | BUG-17 |
| milestones | [4000, 5500] | **[2000, 3500]** | BUG-17 (actual decay @2500, @4000) |
| balance_mode | (none/equal) | **sqrt** | Fix 2 |
| proj_hidden_dim | None (Linear) | **1024** (Sequential) | Fix 3 |

---

## 6. Code Changes (Uncommitted in GiT Repo)

### Modified tracked files:
| File | Changes |
|------|---------|
| `mmdet/models/backbones/vit_git.py` | +`import math`, +`PreextractedFeatureEmbed` (with proj_hidden_dim), ViTGiT init params, `_freeze_stages` skip |
| `mmdet/models/detectors/git.py` | `forward_visual_modeling` preextracted branch |
| `mmdet/datasets/transforms/formatting.py` | `sample_idx` propagation in `PackOccInputs` |
| `mmdet/datasets/pipelines/generate_occ_flow_labels.py` | AABB→rotated polygon, `_point_in_convex_hull`, BUG-11 (classes=None) |
| `mmdet/models/dense_heads/git_occ_head.py` | BUG-8, per_class_balance, balance_mode='sqrt', `_per_class_reg_loss` |
| `mmdet/evaluation/metrics/occ_2d_box_eval.py` | BUG-12 (cell-internal class matching) |

### Untracked config files:
- `plan_a_focal_loss.py`, `plan_b_class_balanced.py`, `plan_c_bg_fix.py`
- `plan_d_reg_rebalance.py`, `plan_d_reg_w1.py`
- `plan_e_bug9_fix.py`, `plan_f_bug8_fix.py`
- `plan_g_aabb_fix.py`, `plan_h_dinov3_layer16.py`
- **`plan_i_p5b_3fixes.py`** (NEW)
- `scripts/extract_dinov3_features.py`

---

## 7. Key Paths

| Resource | Path |
|----------|------|
| SSD workspace | `/mnt/SSD/GiT_Yihao/` |
| P4 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_g_aabb_fix/` |
| P5 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/` |
| P5b work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/` |
| DINOv3 features | `/mnt/SSD/GiT_Yihao/dinov3_features/` (24.15 GB, 323 files) |
| GiT repo | `/home/UNT/yz0370/projects/GiT/` |
| GiT_agent repo | `/home/UNT/yz0370/projects/GiT_agent/` |
| work_dirs (symlink) | `/home/UNT/yz0370/projects/GiT/work_dirs` → SSD |

---

## 8. GPU Status

| GPU | Usage |
|-----|-------|
| 0 | P5b training (~15.9 GB) |
| 1 | Free |
| 2 | P5b training (~15.9 GB) |
| 3 | Free |

---

## 9. Next Actions

1. **Monitor P5b** (iter 60/6000, ETA ~05:05). Verify LR decay at iter 2500.
2. **Execute ORCH_009** (polygon visualization) — MEDIUM priority
3. **Check for new ORCH instructions** (git pull cycle)
4. **Commit all code changes** to prevent future git reset loss

---

## 10. Known Issues / Bugs Status

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-8 | FIXED (P3+) | cls loss missing bg class in per-class balance |
| BUG-9 | FIXED (P2+) | 100% grad clipping (max_norm 0.5->10.0) |
| BUG-10 | FIXED (P3+) | No warmup |
| BUG-11 | FIXED (P4+) | Default class order mismatch |
| BUG-12 | FIXED (P3+) | Eval cell-internal class matching |
| BUG-16 | NOT BLOCKING | Preextracted features vs augmentation |
| BUG-17 | FIXED (P5b) | LR milestones relative to begin, not absolute |
