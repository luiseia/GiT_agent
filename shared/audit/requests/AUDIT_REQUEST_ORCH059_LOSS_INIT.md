# 审计请求 — ORCH059_LOSS_INIT

- **审计对象**: `GiT/mmdet/models/dense_heads/git_occ_head.py`, `GiT/configs/GiT/plan_full_nuscenes_large_v1.py`, `GiT/mmdet/models/detectors/git.py`（仅在与 marker logits/init 直接相关时）
- **关注点**:
  1. `ORCH_058` 证明移除 `grid_pos_embed` 会在 `@100` 直接 all-positive。请审计 **marker trivial all-positive solution** 的更可能根因是否在 loss / init，而非位置编码。
  2. 检查 `OccHead.loss_by_feat_single()` 中 marker/class loss 的归一化与加权逻辑：`use_per_class_balance=True`、`bg_balance_weight=5.0`、`marker_bg_punish=1.0`、`use_focal_loss=False` 的组合，在 warmup 低 LR 阶段是否实际上削弱了背景梯度。
  3. 检查 marker 相关 logits/head 是否存在默认偏向前景的初始化；是否值得在 **不破坏后续 box/class 路径** 的前提下，为 marker 引入显式负偏置初始化。
  4. 在当前代码基础上，给出 **ORCH_059 的单一最小改动优先级排序**：`负偏置初始化`、`开启 focal loss`、`调整 bg/fg punish 或 balance 公式`，哪一个最值得先做，为什么。
- **上下文**:
  - `ORCH_055 @100`: `marker_same=0.887`, `saturation=0.703`
  - `ORCH_056 @200`: `saturation=0.998`，降 LR 更差
  - `ORCH_058 @100`: `marker_same=0.992`, `saturation=1.000`, `reg_loss` 自 iter 40 起为 0
  - 当前判断：`grid_pos_embed` 在早期反而提供了预测多样性；真正问题是 marker 在 warmup 期过快收敛到全正平凡解

