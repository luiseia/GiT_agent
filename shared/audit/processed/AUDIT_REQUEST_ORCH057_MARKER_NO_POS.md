# 审计请求 — ORCH057_MARKER_NO_POS

- **审计对象**: 架构变更 — marker step 不加 grid_pos_embed
- **关注点**:
  1. `grid_pos_embed` 在代码中何时/如何被加到 input 中？精确定位需要修改的位置
  2. 是否可以在不影响 class/box steps 的情况下，仅对 marker step (pos_id=0) 移除 grid_pos_embed？
  3. 在 AR 自回归 decoder 中，marker step 的输出会被后续 steps 用作 KV cache。如果 marker 没有 grid_pos_embed，这会影响后续 steps 的 cross-attention 吗？
  4. 有没有更简单的实现方式（如：marker step 用零向量替代 grid_pos_embed，而非修改 forward 逻辑）

- **上下文**:
  - ORCH_055 5点轨迹: @100 HEALTHY(marker_same=0.887) → @300 模板化 → @400 相变
  - 所有超参数干预(FG/BG比/dropout/LR)均失败
  - grid_pos_embed 为 marker 提供免费空间先验是根因
  - 需要架构级干预让 marker 必须依赖图像特征
  - 代码主要在: `GiT/mmdet/models/detectors/git.py`, `GiT/mmdet/models/dense_heads/git_occ_head.py`
