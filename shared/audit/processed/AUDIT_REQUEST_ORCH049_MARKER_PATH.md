# 审计请求 — ORCH049_MARKER_PATH

- **审计对象**: `GiT/mmdet/models/detectors/git.py`, `GiT/mmdet/models/dense_heads/git_occ_head.py`, `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py`, `GiT/configs/GiT/plan_full_nuscenes_large_v1.py`
- **关注点**:
  1. `ORCH_048 @500` 已将全正饱和从 `1200/1200` 降到 `482/1200`，但 `marker_same=0.9767` 仍严重超阈值，是否说明 marker token 仍在走模板 shortcut
  2. occupancy 第一个 marker token 的训练路径中，是否仍通过 teacher forcing、prefix 构造、query 设计或 target 对齐方式间接泄漏 GT 前缀
  3. 若要打断当前失败模式，是否应：
     - 让 marker 决策完全不看 GT prefix，只靠图像特征和 query
     - 将 `around_weight` 从 `0.1` 进一步降到 `0.0`
     - 单独提高 marker/head 的负样本压力，而不是继续整体调 loss
     - 增加 `iter_200` quick frozen-check 作为早停闸门
- **上下文**:
  - `ORCH_046_v2 @500`: `1200/1200`, IoU `1.0000`, marker_same `1.0000`
  - `ORCH_047 @500`: `1200/1200`, IoU `1.0000`, marker_same `1.0000`
  - `ORCH_048 @500`: `482/1200`, IoU `0.9459`, marker_same `0.9767`, saturation `0.426`
  - 当前判断: `ORCH_048` 证明方向有效，但仍属于“稀疏模板”而非真正条件化预测；需要 Critic 给出最小可执行修复建议，供 `ORCH_049` 采用
