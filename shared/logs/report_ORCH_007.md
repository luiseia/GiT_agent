# Report: ORCH_007 — DINOv3 Feature Extraction Execution

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-07 05:25
**Status**: COMPLETED

---

## Task 1: Conda Environment

```
Environment: dinov3_extract
Python: 3.10.19
torch: 2.7.1+cu118
CUDA: available
Packages: pillow, scipy
```
Created successfully, DINOv3 source imports work.

## Task 2: Single Image Test

| Metric | Value |
|--------|-------|
| Single image, 2 layers (16+20) | **76.6 MB** |
| Single image, 1 layer (20) | **38.3 MB** |
| Estimated total, 2 layers × 323 | **24.2 GB** |
| Estimated total, 1 layer × 323 | **12.1 GB** |
| GPU memory (model FP16) | 12.5 GB |
| Extraction time per image | ~0.5 sec |

**Decision**: 24.2 GB << 200 GB limit → **Extract 2 layers (Layer 16 + Layer 20)**.

Model load notes:
- Missing keys: 200 (head/projection layers, not needed for feature extraction)
- Unexpected keys: 323 (teacher/student/dino_head weights in checkpoint)
- Backbone weights loaded correctly

## Task 3: Full Extraction

| Metric | Value |
|--------|-------|
| GPU used | **GPU 1 only** (CUDA_VISIBLE_DEVICES=1) |
| Images processed | **323/323** |
| Layers extracted | **Layer 16, Layer 20** |
| Total disk usage | **24.15 GB** |
| Total time | **341 sec (5.7 min)** |
| Speed | 0.9-1.0 img/s |
| Output path | `/mnt/SSD/GiT_Yihao/dinov3_features/` |
| File format | `{nuScenes_token}.pt` with keys `layer_16`, `layer_20` |
| Precision | FP16 |

## Task 4: Verification + GPU Release

### File verification (3 random samples):

| File | layer_16 shape | layer_20 shape | NaN | Inf | Size |
|------|---------------|---------------|-----|-----|------|
| 3f2ddc94...pt | (4900, 4096) | (4900, 4096) | No | No | 76.6 MB |
| 264c5f3a...pt | (4900, 4096) | (4900, 4096) | No | No | 76.6 MB |
| 98fa8199...pt | (4900, 4096) | (4900, 4096) | No | No | 76.6 MB |

All features: dtype=float16, reasonable value ranges (min ~-4.6, max ~6.8).

### GPU Release

| GPU | Before extraction | After extraction |
|-----|-------------------|-----------------|
| 0 | 22434 MiB (P4) | 22434 MiB (P4) |
| 1 | 15 MiB | **15 MiB** (released) |
| 2 | 22967 MiB (P4) | 22967 MiB (P4) |
| 3 | 15 MiB | **15 MiB** (untouched) |

GPU 1 used during extraction, automatically released when process completed. GPU 3 was not needed (single GPU sufficient).

---

## Verification Checklist

- [x] Conda env created (dinov3_extract, Python 3.10, torch 2.7.1)
- [x] Single image test: 76.6 MB/image for 2 layers, 24.2 GB total estimate
- [x] Decision: 2 layers (16+20), well under 200 GB limit
- [x] Full extraction: 323/323 files, 24.15 GB, 5.7 min
- [x] Verification: 3 random files checked, all correct shape/dtype/no NaN/Inf
- [x] Total file count = 323 confirmed
- [x] GPU 1,3 released (15 MiB each)
- [x] P4 training on GPU 0,2 undisturbed
- [x] Report written
