# 审计请求 — MULTILAYER_032_COLLAPSE
- **审计对象**: ORCH_032 多层特征训练 @2000 eval 全面坍缩
- **紧急程度**: HIGH
- **关注点**: 多层特征实现是否存在 bug 导致模型坍缩

## 背景
ORCH_032 使用 `layer_indices=[9,19,29,39]` 四层拼接 (16384维)，@2000 eval 结果：
- car_R=0, car_P=0 (ORCH_024 同期 car_R=0.627, car_P=0.079)
- bg_FA=0.3181 (ORCH_029 同期 0.1615)
- 仅 pedestrian_R=0.8328 非零 (P=0.0056) — 模型坍缩到单类预测

## 需要审查的代码
1. **`GiT/mmdet/models/backbones/vit_git.py` — `OnlineDINOv3Embed`**:
   - `get_intermediate_layers(n=[9,19,29,39])` 是否正确提取了 4 层特征？
   - `torch.cat(features, dim=-1)` 拼接维度是否正确 (应为 16384)?
   - 投影层 `nn.Linear(16384, 2048)` 梯度是否正常流通？

2. **`GiT/configs/GiT/plan_full_nuscenes_multilayer.py`**:
   - 所有 config 参数是否正确继承了 overlap+vis 标签设置？
   - `load_from=None` 从零训练 — 投影层初始化是否合理？

3. **训练日志**:
   - Loss 在 warmup 期间是否有异常模式？
   - cls_loss vs reg_loss 的比例是否正常？
   - grad_norm 曾达 148.8 — 是否梯度爆炸？

## 可能的原因假设
1. 16384→2048 投影太激进，2层MLP无法处理4倍输入
2. 梯度爆炸导致 car 相关权重损坏
3. 特征维度/拼接方式有 bug
4. 正常的多层从零训练需要更长 warmup（16384维参数量大4倍）

## 期望产出
- 确认多层特征提取和拼接实现无 bug
- 检查投影层梯度和权重状态
- 判断是实现问题还是架构问题
- 建议：继续等 @4000 还是立即干预
