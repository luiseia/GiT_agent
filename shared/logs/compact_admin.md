# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 06:45
**Reason**: P5b completed (6000/6000), final results collected

---

## 1. Current State

**P5b training COMPLETED** (6000/6000) on GPU 0,2
- Config: `configs/GiT/plan_i_p5b_3fixes.py`
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/`
- 12 checkpoints saved (iter 500-6000, every 500)
- 10-class model (num_vocal=230), DINOv3 backbone, 3 fixes (BUG-17, sqrt balance, dual proj)

**GPUs**: All 4 FREE after P5b completion.

**Awaiting CEO decision** on DINOv3 storage BLOCKER for P6 full nuScenes.

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| ORCH_005 | COMPLETED | AABB->rotated polygon fix + BUG-11 + P4 launched |
| ORCH_006 | PARTIAL | DINOv3 extraction script written, Python 3.8 blocker |
| ORCH_007 | COMPLETED | DINOv3 features extracted (323 images, 24.15 GB) |
| ORCH_008 | COMPLETED | PreextractedFeatureEmbed + P5 launched |
| ORCH_009 | COMPLETED | Rotated polygon visualization (10 images) |
| ORCH_010 | COMPLETED | P5b 3 fixes: LR milestones, sqrt balance, dual proj |
| ORCH_011 | COMPLETED | work_dirs migrated to SSD + symlinks |
| ORCH_012 | COMPLETED | BUG-19 fix (valid_mask + z center) |
| ORCH_013 | COMPLETED | 10-class expansion (num_vocal=230) |
| ORCH_014 | COMPLETED | P6 full nuScenes prep — DINOv3 2.1TB BLOCKER |

---

## 3. P5b Complete Validation Trajectory (10-class, DDP 2-GPU)

| iter | car_R | car_P | truck_R | truck_P | bus_R | bus_P | trail_R | trail_P | bg_FA | offset_th |
|------|-------|-------|---------|---------|-------|-------|---------|---------|-------|-----------|
| 500  | 0.856 | 0.080 | 0.153 | 0.039 | 0.014 | 0.030 | 0.000 | 0.000 | 0.235 | 0.210 |
| **1000** | 0.760 | 0.089 | **0.568** | **0.061** | **0.368** | **0.057** | 0.000 | 0.000 | 0.302 | **0.168** |
| 1500 | 0.924 | 0.091 | 0.390 | 0.030 | 0.000 | 0.000 | 0.000 | 0.000 | 0.333 | 0.203 |
| 2000 | 0.856 | 0.094 | 0.340 | 0.035 | 0.085 | 0.071 | 0.028 | 0.003 | 0.282 | 0.208 |
| **2500** | 0.831 | 0.094 | 0.287 | 0.045 | **0.470** | **0.067** | **0.444** | 0.010 | 0.283 | 0.212 |
| 3000 | 0.835 | **0.107** | 0.205 | 0.035 | 0.051 | 0.026 | 0.389 | **0.037** | 0.217 | 0.200 |
| **3500** | 0.819 | **0.108** | 0.234 | 0.040 | 0.053 | 0.024 | 0.417 | 0.036 | 0.214 | 0.206 |
| 4000 | 0.792 | 0.105 | 0.229 | 0.040 | 0.060 | 0.026 | 0.417 | 0.033 | 0.211 | 0.196 |
| 4500 | 0.788 | 0.105 | 0.238 | 0.042 | 0.059 | 0.026 | 0.417 | 0.032 | 0.210 | 0.202 |
| 5000 | 0.788 | 0.105 | 0.239 | 0.042 | 0.059 | 0.026 | 0.417 | 0.034 | 0.210 | 0.201 |
| 5500 | 0.777 | 0.104 | 0.243 | 0.043 | 0.058 | 0.026 | 0.417 | 0.028 | 0.209 | 0.202 |
| 6000 | 0.774 | 0.104 | 0.240 | 0.043 | 0.059 | 0.027 | 0.417 | 0.027 | 0.208 | 0.198 |

**Key findings**:
- **car_P best**: 0.108@3500 (P5 best was 0.093@3500, **+16% improvement**)
- **Multi-class golden checkpoint**: iter 1000 (truck_R=0.568, bus_R=0.368, offset_th=0.168)
- **Rare class peak**: iter 2500 (bus_R=0.470, trailer_R=0.444) — coincides with 1st LR decay
- **iter 3000+ plateau**: model frozen after 2nd LR decay, minimal change through iter 6000
- **P5b best checkpoint**: iter 3500 (car_P=0.108, bg_FA=0.214, balanced multi-class)

---

## 4. P5 Complete Validation Trajectory (4-class, DDP 2-GPU)

| iter | car_R | car_P | truck_R | truck_P | bus_R | trail_R | trail_P | bg_FA | offset_th |
|------|-------|-------|---------|---------|-------|---------|---------|-------|-----------|
| 500  | 0.932 | 0.055 | 0.025 | 0.027 | 0.000 | 0.000 | 0.000 | 0.320 | 0.216 |
| **4000** | 0.569 | 0.090 | 0.421 | **0.130** | 0.315 | 0.472 | 0.006 | 0.213 | **0.142** |
| 6000 | 0.682 | 0.089 | 0.228 | 0.065 | 0.011 | 0.500 | 0.043 | 0.190 | 0.192 |

**P5 best**: iter 4000 (truck_P=0.130, offset_th=0.142)

---

## 5. P5b vs P5 Comparison

| Metric | P5 best | P5b best | Change |
|--------|---------|----------|--------|
| car_P | 0.093@3500 | **0.108@3500** | +16% |
| truck_P | **0.130@4000** | 0.061@1000 | -53% (but 10-class harder) |
| offset_th | **0.142@4000** | 0.168@1000 | -18% |
| bg_FA | **0.160@5000** | 0.208@6000 | -30% |
| bus_R | 0.409@2500 | **0.470@2500** | +15% |
| trailer_P | 0.046@5500 | **0.037@3000** | ~similar |

**Conclusion**: P5b's 3 fixes improved car_P significantly. Truck/offset regression likely due to 10-class expansion diluting per-class attention. The sqrt balance mode may need further tuning.

---

## 6. P6 Readiness (ORCH_014)

| Item | Status |
|------|--------|
| Data (full nuScenes) | ✅ 28,130 train, 6,019 val |
| Config (plan_j) | ✅ Created, DINOv3 path TODO |
| Checkpoint compat | ✅ 4→10 class seamless |
| **DINOv3 features** | ❌ **BLOCKER**: need 2.1 TB, only 528 GB SSD free |

---

## 7. Code Status

All code changes committed to GiT repo. Key commits:
- `2b52544`: 10-class expansion (num_vocal=230)
- `b3cca77`: plan_j_full_nuscenes.py config
- Earlier: BUG-8/9/10/11/12/17/19 fixes, polygon, DINOv3, etc.

---

## 8. Key Paths

| Resource | Path |
|----------|------|
| P5b work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/` |
| P5b best ckpt | `iter_3500.pth` (car_P=0.108) or `iter_1000.pth` (multi-class) |
| P5 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/` |
| DINOv3 features | `/mnt/SSD/GiT_Yihao/dinov3_features/` (mini, 323 files) |
| GiT repo | `/home/UNT/yz0370/projects/GiT/` |
| GiT_agent repo | `/home/UNT/yz0370/projects/GiT_agent/` |

---

## 9. Next Actions

1. **Report P5b results to CEO** (via compact_admin.md push)
2. **Await CEO decision** on DINOv3 storage BLOCKER for P6
3. **Check for new ORCH instructions** periodically
4. All 4 GPUs now free — ready for next training

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
| BUG-19 | FIXED (P5b) | valid_mask + z center offset |
