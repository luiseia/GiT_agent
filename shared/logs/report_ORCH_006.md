# Report: ORCH_006 — DINOv3 Offline Feature Pre-extraction

**Executed by**: Admin Agent (Opus 4.6)
**Timestamp**: 2026-03-07 03:20
**Status**: PARTIAL — Script written, blocked by Python version, awaiting P4 eval trigger

---

## 1. DINOv3 Weights

- **Path**: `/mnt/SSD/yz0370/dinov3_weights/dinov3_vit7b16_pretrain_lvd1689m.pth`
- **Size**: 26 GB
- **Status**: Already downloaded, symlinked at `dinov3/weights/dinov3_vit7b16_pretrain_lvd1689m.pth`

## 2. Model Architecture

DINOv3 ViT-7B (`vit_7b` in `dinov3/dinov3/models/vision_transformer.py`):
- `embed_dim` = 4096
- `depth` = 40 layers
- `num_heads` = 32
- `ffn_ratio` = 3
- `patch_size` = 16
- Position encoding: RoPE (not learned, no interpolation needed)
- Built-in API: `model.get_intermediate_layers(x, n=[16, 20])` extracts any layer

## 3. Storage Estimation

| Layers | Per Image | Total (323 images) |
|--------|-----------|-------------------|
| Layer 16 + 20 (2 layers) | 76.6 MB | **24.2 GB** |
| Layer 16-20 (5 layers) | 191.4 MB | **60.4 GB** |
| Layer 20 only | 38.3 MB | **12.1 GB** |

Feature shape per layer per image: `(4900, 4096)` in FP16 (4900 = 70×70 patches for 1120×1120 input).

Available SSD: **609 GB** free — sufficient for any option.

**Recommendation**: Start with 2 layers (16 + 20) = 24.2 GB. Add more if needed.

## 4. Extraction Script

**File**: `scripts/extract_dinov3_features.py`

Features:
- Loads DINOv3 ViT-7B, extracts specified intermediate layers
- Saves per-image `.pt` files keyed by nuScenes token
- Supports `--dry-run` for verification
- Resumable (skips existing files)
- FP16 by default

Usage:
```bash
CUDA_VISIBLE_DEVICES=0 python scripts/extract_dinov3_features.py \
    --layers 16 20 \
    --output-dir /mnt/SSD/GiT_Yihao/dinov3_features/ \
    --batch-size 1
```

## 5. BLOCKER: Python 3.8 Incompatibility

DINOv3 source code uses PEP 604 union type syntax (`Tensor | Tuple[Tensor, Tensor]`), which requires **Python 3.10+**.

Current GiT conda environment: **Python 3.8.20** — INCOMPATIBLE.

**Existing workaround in GiT**: `vit_git.py` only imports `patch_embed.py` via `importlib` (this file doesn't use PEP 604). But the full transformer model needs `attention.py`, `block.py`, etc., which all use the new syntax.

### Resolution Options

| Option | Effort | Risk |
|--------|--------|------|
| A: Create new conda env (Python 3.10 + torch 2.x) | ~30 min | Low — isolated, no impact on training |
| B: Monkey-patch `from __future__ import annotations` into DINOv3 source files | ~15 min | Medium — modifies external code |
| C: Port needed DINOv3 classes into a standalone file | ~1 hour | Low — self-contained |

**Recommendation**: Option A (new conda env). Extraction is a one-time task, separate from training.

```bash
conda create -n dinov3_extract python=3.10 -y
conda activate dinov3_extract
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
pip install pillow
```

## 6. GPU Usage

- DINOv3 7B FP16: ~14 GB GPU memory
- P4 training (current): ~22 GB per GPU on GPU 0, 2
- **Cannot co-locate** extraction with P4 training (22 + 14 = 36 GB fits in 49 GB, but leaves no headroom for activations)
- **Extraction must wait** for P4 to free at least one GPU, OR use GPU 1/3 (requires CEO approval, currently limited to 0,2)

### Estimated Extraction Time
- ~3 sec/image (7B model forward pass at FP16, batch=1)
- 323 images × 3 sec = ~16 minutes

## 7. GiT Integration Plan (Deferred)

When triggered (avg_P < 0.12), modifications needed:

1. **`vit_git.py`**: Add `use_preextracted_features` parameter to ViTGiT
   - New `PreextractedFeatureEmbed` class: loads `.pt` file, applies `Linear(4096, 768)` projection
   - Replaces `DINOv3PatchEmbedWrapper` forward pass
   - Projection layer is trainable (replaces current `proj_layer`)

2. **Dataset pipeline**: Add image token → feature path mapping
   - Modify `NuScenesOccDataset` to pass feature path in data dict

3. **Config**: New parameter `preextracted_feature_dir`

## 8. Decision Gate

| P4 Result | Action |
|-----------|--------|
| avg_P > 0.15 | Phase 2 LOW PRIORITY — script ready, no execution needed |
| avg_P < 0.12 | EXECUTE: create conda env → run extraction → integrate into GiT |
| 0.12 ≤ avg_P ≤ 0.15 | Conductor decision |

P4 first validation at iter 500 (ETA ~03:45). Decision can be made after that.

---

## Verification Checklist

- [x] DINOv3 weights confirmed (26 GB, `/mnt/SSD/yz0370/dinov3_weights/`)
- [x] Model architecture analyzed (depth=40, embed_dim=4096, RoPE)
- [x] Storage estimation complete (24.2 GB for 2 layers)
- [x] Extraction script written (`scripts/extract_dinov3_features.py`)
- [x] Python 3.8 blocker identified and documented with 3 resolution options
- [x] GPU constraint analyzed — cannot co-locate with P4
- [x] Integration plan drafted (deferred until P4 eval trigger)
- [x] Report written to `shared/logs/report_ORCH_006.md`
