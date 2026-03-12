# 审计请求 — MULTILAYER_FEATURE
- **审计对象**: GiT/mmdet/models/backbones/vit_git.py (commit `8a961de`)
- **关注点**:
  1. `OnlineDINOv3Embed` 多层拼接实现正确性: `get_intermediate_layers(n=[10,20,30,40])` 返回值处理、拼接维度
  2. 向后兼容性: `layer_indices=None` 时是否完全等价于修改前行为
  3. 投影层维度自动适配: 16384→2048 vs 4096→2048 的初始化
  4. 显存影响评估: 多存 3 个中间层输出的实际开销
  5. `plan_full_nuscenes_multilayer.py` config 与代码的一致性
- **上下文**: CEO 阅读 DINOv3 论文发现所有下游任务用多层特征 [10,20,30,40]，Layer 16 单层在几何任务上远未达峰。此改动是为后续 Full nuScenes 多层特征训练做准备。详细分析见 `shared/logs/reports/dinov3_paper_analysis.md`
