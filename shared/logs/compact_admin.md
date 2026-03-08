# Admin Agent Context Snapshot
**Timestamp**: 2026-03-07 21:20
**Reason**: Context compaction requested

---

## 1. Current State

**P5 training RUNNING** on GPU 0,2 (PID 1572)
- Config: `configs/GiT/plan_h_dinov3_layer16.py`
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/`
- Progress: iter **4000/6000** (67%), ETA ~22:58
- LR milestone 4000 just hit (LR 5e-5 -> 5e-6)
- Next milestones: 5500 (LR->5e-7), 6000 (end)
- Checkpoints/val every 500 iters

No pending ORCH instructions.

---

## 2. ORCH History (This Session)

| ORCH | Status | Summary |
|------|--------|---------|
| ORCH_005 | COMPLETED | AABB->rotated polygon fix + BUG-11 + P4 launched |
| ORCH_006 | PARTIAL | DINOv3 extraction script written, Python 3.8 blocker documented |
| ORCH_007 | COMPLETED | DINOv3 features extracted (323 images, 24.15 GB, Layer 16+20) |
| ORCH_008 | COMPLETED | PreextractedFeatureEmbed + P5 launched with DINOv3 Layer 16 |

---

## 3. P5 Validation Trajectory (DDP 2-GPU)

| iter | car_R | car_P | truck_R | truck_P | bus_R | trail_R | bg_FA | offset_th |
|------|-------|-------|---------|---------|-------|---------|-------|-----------|
| 500  | 0.932 | 0.055 | 0.025 | 0.027 | 0.000 | 0.000 | 0.320 | 0.216 |
| 1000 | 0.952 | 0.052 | 0.000 | 0.000 | 0.000 | 0.056 | 0.354 | 0.225 |
| 1500 | 0.955 | 0.057 | 0.418 | 0.037 | 0.000 | 0.000 | 0.442 | 0.201 |
| 2000 | 0.945 | 0.073 | 0.216 | 0.019 | 0.000 | 0.056 | 0.383 | 0.222 |
| 2500 | 0.793 | 0.073 | 0.080 | 0.030 | 0.409 | 0.528 | 0.321 | 0.215 |
| 3000 | 0.728 | 0.091 | 0.230 | 0.048 | 0.118 | 0.556 | 0.260 | 0.232 |
| 3500 | 0.779 | 0.093 | 0.679 | 0.072 | 0.120 | 0.000 | 0.290 | 0.197 |

**Key observations**:
- car_P=0.093 and truck_P=0.072 surpass P4 best (0.085, 0.018)
- truck_R=0.679 far exceeds P4 best (0.463)
- offset_th=0.197 beats P4 best (0.200)
- bus_R and trailer_R oscillate heavily (class competition still unstable)
- bg_FA trending down (0.442->0.260->0.290) but still high vs P4 (~0.19)
- LR decay at iter 4000 should stabilize

---

## 4. P4 Final Results (Reference)

Best checkpoint varies by metric. Full trajectory:

| iter | car_R | truck_R | bus_R | trail_R | bg_FA | offset_th |
|------|-------|---------|-------|---------|-------|-----------|
| 500  | 0.594 | 0.270 | 0.694 | 0.667 | 0.176 | 0.206 |
| 1500 | 0.608 | 0.463 | 0.773 | 0.806 | 0.206 | 0.217 |
| 2000 | 0.667 | 0.458 | 0.679 | 0.667 | 0.239 | 0.235 |
| 3500 | 0.598 | 0.405 | 0.728 | 0.750 | 0.202 | 0.206 |
| 4000 | 0.592 | 0.410 | 0.752 | 0.750 | 0.194 | 0.207 |

---

## 5. Code Changes (Uncommitted in GiT Repo)

### New files this session:
| File | Description |
|------|-------------|
| `configs/GiT/plan_g_aabb_fix.py` | P4 config (AABB fix, bg_w=2.0, reg_w=1.5) |
| `configs/GiT/plan_h_dinov3_layer16.py` | P5 config (DINOv3 Layer 16, 6000 iter, warmup 1000) |
| `scripts/extract_dinov3_features.py` | DINOv3 feature extraction script |

### Modified files this session:
| File | Change |
|------|--------|
| `mmdet/models/backbones/vit_git.py` | +`PreextractedFeatureEmbed` class, +3 ViTGiT init params, modified `_freeze_stages` |
| `mmdet/models/detectors/git.py` | `forward_visual_modeling` passes `batch_data_samples` to patch_embed in preextracted mode |
| `mmdet/datasets/transforms/formatting.py` | `PackOccInputs` auto-propagates `sample_idx` to metainfo |
| `mmdet/datasets/pipelines/generate_occ_flow_labels.py` | AABB->rotated polygon fix + BUG-11 fix (from ORCH_005) |
| `mmdet/models/dense_heads/git_occ_head.py` | BUG-8 fix (bg cls loss) (from prior session) |
| `mmdet/evaluation/metrics/occ_2d_box_eval.py` | BUG-12 fix (from prior session) |

### Prior session files (still uncommitted):
- `configs/GiT/plan_a_focal_loss.py`, `plan_b_class_balanced.py`, `plan_c_bg_fix.py`
- `configs/GiT/plan_d_reg_rebalance.py`, `plan_d_reg_w1.py`
- `configs/GiT/plan_e_bug9_fix.py`, `plan_f_bug8_fix.py`

---

## 6. Key Paths

| Resource | Path |
|----------|------|
| SSD workspace | `/mnt/SSD/GiT_Yihao/` |
| P4 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_g_aabb_fix/` |
| P5 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/` |
| DINOv3 features | `/mnt/SSD/GiT_Yihao/dinov3_features/` (24.15 GB, 323 files, Layer 16+20) |
| DINOv3 weights | `/mnt/SSD/yz0370/dinov3_weights/dinov3_vit7b16_pretrain_lvd1689m.pth` (26 GB) |
| GiT repo | `/home/UNT/yz0370/projects/GiT/` |
| GiT_agent repo | `/home/UNT/yz0370/projects/GiT_agent/` |
| Conda extract env | `dinov3_extract` (Python 3.10, torch 2.7.1, for feature extraction only) |

---

## 7. GPU Status

| GPU | Usage |
|-----|-------|
| 0 | P5 training (~20.4 GB) |
| 1 | Free |
| 2 | P5 training (~20.9 GB) |
| 3 | Free |

---

## 8. Next Actions (for resuming agent)

1. **Wait for P5 to finish** (iter 6000, ETA ~22:58). Collect remaining val results (4000, 4500, 5000, 5500, 6000).
2. **Check for new ORCH instructions** (git pull cycle).
3. **P5 eval comparison**: DDP 2-GPU counts differ from single-GPU. If Conductor requests single-GPU eval, need to run separately.
4. **DINOv3 Layer 20 features** are also pre-extracted — could be used for future experiments.
5. **BUG-16 confirmed not blocking** — no image augmentations in pipeline.

---

## 9. Known Issues / Bugs Status

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-8 | FIXED (P3+) | cls loss missing bg class in per-class balance |
| BUG-9 | FIXED (P2+) | 100% grad clipping (max_norm 0.5->10.0) |
| BUG-10 | FIXED (P3+) | No warmup |
| BUG-11 | FIXED (P4+) | Default class order mismatch |
| BUG-12 | FIXED (P3+) | Eval slot ordering |
| BUG-16 | NOT BLOCKING | Preextracted features vs augmentation (no augmentation in pipeline) |
