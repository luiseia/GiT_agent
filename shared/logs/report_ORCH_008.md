# Report: ORCH_008 — P5: DINOv3 Layer 16 Feature Integration + Training

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-07 17:35
**Status**: COMPLETED

---

## Task 1: PreextractedFeatureEmbed Implementation

**File**: `mmdet/models/backbones/vit_git.py`

New class `PreextractedFeatureEmbed` (inserted after `DINOv3PatchEmbedWrapper`):
- Loads pre-extracted `.pt` files from `feature_dir` by nuScenes sample token
- Selects layer by `layer_key` (default: `layer_16`)
- Projects features via `nn.Linear(4096, 768)` with kaiming_uniform init
- Returns `(B, N_patches, out_dim)` and `(H_p, W_p)` — same interface as existing PatchEmbed
- Includes in-memory caching (`_cache` dict) for repeated access
- FP16 → FP32 conversion on load

**ViTGiT modifications**:
- Added 3 new init params: `use_preextracted_features`, `preextracted_feature_dir`, `preextracted_layer_key`
- `use_preextracted_features=True` takes priority over `use_dinov3_patch_embed`
- `_freeze_stages`: skips freezing patch_embed when in preextracted mode (proj must train)

**GiT detector modifications** (`mmdet/models/detectors/git.py` L239):
- `forward_visual_modeling`: passes `batch_data_samples` to patch_embed when preextracted mode active
- Backward compatible: non-preextracted mode unchanged

## Task 2: Dataset Adaptation

**File**: `mmdet/datasets/transforms/formatting.py` (PackOccInputs)

Added automatic propagation of `sample_idx` to metainfo:
```python
if 'sample_idx' in results and 'sample_idx' not in img_meta:
    img_meta['sample_idx'] = results['sample_idx']
```

`sample_idx = info['token']` is already set in `NuScenesOccDataset.get_data_info()` (L509). This ensures the nuScenes token reaches `PreextractedFeatureEmbed.forward()` via `batch_data_samples[i].metainfo['sample_idx']`.

## Task 3: P5 Config

**File**: `configs/GiT/plan_h_dinov3_layer16.py`

| Parameter | P4 (plan_g) | **P5 (plan_h)** | Reason |
|-----------|-------------|-----------------|--------|
| load_from | P3@3000 | **P4@500** | Critic: shallowest old-dist adaptation |
| use_preextracted_features | — | **True** | DINOv3 Layer 16 features |
| preextracted_feature_dir | — | `/mnt/SSD/GiT_Yihao/dinov3_features/` | — |
| preextracted_layer_key | — | `layer_16` | Critic: balance detail + semantics |
| use_dinov3_patch_embed | True | **False** | Replaced by preextracted |
| max_iters | 4000 | **6000** | New features need more training |
| warmup | 500 | **1000** | Feature distribution gap |
| milestones | [2500, 3500] | **[4000, 5500]** | Adapted for 6000 iters |
| bg_balance_weight | 2.0 | **2.5** | Critic: full LR bg_FA too high |
| reg_loss_weight | 1.5 | 1.5 | Keep |
| base_lr | 5e-05 | 5e-05 | Keep |
| max_norm | 10.0 | 10.0 | Keep |
| use_rotated_polygon | True | True | Keep AABB fix |

## Task 4: BUG-16 Evaluation

**Result**: **NOT BLOCKING**

Current `train_pipeline` contains NO image-level augmentations:
```
LoadAnnotations3D_E2E → LoadFrontCameraImageFromFile → ResizeForOccInput → GenerateOccFlowLabels → AddMetaInfo → PackOccInputs
```
No flip, rotation, color jitter, or any spatial/color augmentation. Pre-extracted features are compatible as-is.

## Task 5: P5 Training Launch

**PID**: 1572
**GPU**: 0, 2 (as required)
**Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/`
**Memory**: ~20.4 GB per GPU (lower than P4's 22 GB — no 26GB DINOv3 weight loading)

### Feature loading verification:
- Checkpoint load: `patch_embed.proj.weight/bias` missing (expected — randomly initialized)
- Old `dinov3_patch_embed.*` and `proj_layer.*` keys discarded (expected)
- Feature shape confirmed: `(B, 4900, 768)` after projection

### First 50 iterations:

| Iter | base_lr | Loss | loss_cls | loss_reg | grad_norm |
|------|---------|------|----------|----------|-----------|
| 10 | 5.0e-7 | 16.78 | 15.23 | 1.55 | 223.0 |
| 20 | 1.0e-6 | 17.13 | 15.19 | 1.93 | 142.1 |
| 30 | 1.5e-6 | 16.83 | 14.75 | 2.07 | 256.5 |
| 40 | 2.0e-6 | 11.63 | 8.68 | 2.95 | 210.5 |
| 50 | 2.5e-6 | 16.31 | 14.55 | 1.76 | 247.8 |

**Observations**:
- High initial loss (16-17) and grad_norm (140-257) — expected due to random proj initialization
- Loss dropped to 11.6 at iter 40 — adaptation beginning
- All grad_norm heavily clipped (max_norm=10.0)
- 1000-step warmup gives 950 more steps for gradual adaptation
- No NaN, no OOM
- ETA: ~5h08m, completion ~22:40

### Schedule:
- Warmup ends at iter 1000
- First val at iter 500
- Checkpoints every 500 iters
- Milestones: 4000 (LR×0.1), 5500 (LR×0.01)

---

## Verification Checklist

- [x] PreextractedFeatureEmbed: loads .pt, projects 4096→768, kaiming init
- [x] Output shape: (B, 4900, 768) — matches Conv2d PatchEmbed interface
- [x] Dataset: sample_idx propagated to metainfo via PackOccInputs
- [x] BUG-16: no augmentations → not blocking
- [x] P5 config: all parameters match ORCH_008 spec
- [x] P5 training launched on GPU 0,2
- [x] First 50 iters: no NaN/OOM
- [x] GPU memory: 20.4 GB/GPU (reduced vs P4)
- [x] Report written
