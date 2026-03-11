# 审计请求 — OVERLAP_THRESHOLD
- **审计对象**: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py:313-360` (grid cell 分配逻辑)
- **关注点**: Overlap-based grid 分配的阈值设计
- **上下文**:

## CEO 原始指令
> 我觉得应该设置红框与图像grid的重合超过红框的百分之多少？这个grid某一个slot才能算是正样本。审计一下写个报告

## 背景
BUG-51 修复后，当前 `grid_assign_mode='overlap'` 将所有与物体投影 AABB 有任何重叠的 cell 都标记为正样本候选（再经凸包过滤）。CEO 质疑：是否需要设置最低重叠比例阈值，避免边缘微量重叠的 cell 被错误标为正样本。

## 需要 Critic 分析的问题

1. **阈值定义**: 合理的阈值度量是什么？
   - 选项 A: `overlap_area / bbox_projection_area` — 重叠占红框投影面积的比例
   - 选项 B: `overlap_area / cell_area` — 重叠占 cell 面积的比例 (IoF - Intersection over Foreground)
   - 选项 C: IoU — 交并比
   - 推荐哪种？为什么？

2. **当前问题量化**:
   - 在 overlap 模式下，有多少比例的正样本 cell 与物体投影仅有 <10%, <20%, <30% 重叠？
   - 这些边缘 cell 的 offset 标签质量如何？(offset 指向 cell 中心 → 物体中心的偏移)

3. **阈值建议**:
   - 建议合适的阈值范围
   - 阈值过高的风险（回归到 BUG-51 类似问题，小物体再次丢失 cell）
   - 阈值过低的风险（噪声正样本，模型困惑）

4. **对训练的影响**:
   - 引入阈值是否需要调整 `bg_weight=2.5` 和 sqrt balance 权重？
   - 预期对 reg=0 频率的影响？
   - 是否需要从零重训，还是可以在 ORCH_028 基础上继续？

5. **实现建议**: 如果推荐引入阈值，给出具体参数名和默认值

## 数据资源
- nuScenes 完整训练集标签
- 当前 BUG-51 修复代码: GiT commit `ec9a035`
- ORCH_024 @12000 val baseline (center-based, 已废弃)
- ORCH_028 因断电终止于 iter 1180, 无 checkpoint

## 截止时间
尽快完成，ORCH_028 重启等待此审计结论
