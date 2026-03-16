# 审计请求 — ORCH046_V2_AT500

- **审计对象**: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py`, `GiT/mmdet/models/dense_heads/git_occ_head.py`, `GiT/mmdet/models/detectors/git.py`, `GiT/mmdet/datasets/pipelines/*`
- **关注点**: 在 `lr_mult=1.0`、`clip_grad=50.0`、`bert-large pretrain` 已生效后，为什么模型在 `iter_500` 依然无法跳出 frozen/local optimum？请重点审查：
  1. 缺少 `RandomFlipBEV` / `GlobalRotScaleTrans` 是否仍让模型沿用固定 BEV 空间先验
  2. 推理端 `attn_mask=None` 与训练端 causal mask 不一致是否继续放大模板化输出
  3. DINOv3 四层 `[5,11,17,23]` + adapt layers 路径中，是否还有让 decoder 忽略视觉差异的结构性问题
- **上下文**:
  - `2026-03-15 20:30 CDT` 对 `ORCH_046_v2` 的 `iter_500.pth` 执行 `python scripts/check_frozen_predictions.py`
  - 结果:
    - Avg positive slots = `1200/1200`
    - Positive IoU = `1.0000`
    - Marker same rate = `1.0000`
    - Coord diff = `0.008769`
    - Saturation = `1.000`
  - 当前问题已满足 frozen 判定阈值，请回答：**“在 lr_mult=1.0 后，为何模型依然无法跳出局部最优？”**
