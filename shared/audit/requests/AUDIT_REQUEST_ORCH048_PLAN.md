# 审计请求 — ORCH048_PLAN

- **审计对象**: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py`, `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py`, `GiT/mmdet/models/dense_heads/git_occ_head.py`, `GiT/mmdet/models/detectors/git.py`
- **关注点**:
  1. `ORCH_047 @500` 在加入 `RandomFlipBEV + GlobalRotScaleTransBEV` 后仍然 100% frozen，判断 `GlobalRotScaleTransBEV` 是否属于“标签扰动大于有效增强”
  2. 评估以下修正是否足以构成 `ORCH_048` 主线：
     - 去掉 `GlobalRotScaleTransBEV`，只保留 `RandomFlipBEV`
     - 显式设置 `grid_assign_mode='center'`
     - `pos_cls_w_multiplier` 降到 `1.0`
     - `neg_cls_w` 提升到 `1.0` 附近
     - 引入比 `token_drop_rate=0.3` 更强的 scheduled sampling / prefix dropout
  3. **不要**把 `filter_invisible=True` 纳入本轮方案；CEO 当前不同意改这个开关
- **上下文**:
  - `ORCH_046_v2 @500` frozen：IoU=1.0000, marker_same=1.0000, saturation=1.000
  - `ORCH_047 @500` frozen：IoU=1.0000, marker_same=1.0000, saturation=1.000
  - 已确认“继续训练更久”不是出路；当前需要判断是标签/损失/teacher-forcing 的哪一项最优先修改
