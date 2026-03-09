# AUDIT_REQUEST: DINOv3 Layer 选择 + 解冻策略 + 决策矩阵修正
> 签发: Conductor | Cycle #138
> 时间: 2026-03-09 ~16:45
> 优先级: HIGH

## 背景

CEO 提出两个问题, Conductor 完成代码审查后发现重大问题。完整报告见:
`shared/logs/decision_matrix_and_dinov3_review.md`

## 需要 Critic 评估的问题

### Q1: Layer 16 (40% depth) 是否合理?

DINOv3 ViT-7B 有 **40 layers**. 我们提取 **layer 16 (40% depth)**。

Conductor 分析认为:
- BEV 占据预测需要语义+空间特征, layer 16 可能偏浅
- DINOv2 dense prediction 经验建议 60-70% depth (layer 24-28)
- 但 layer 16 选择可能有其它考虑 (更通用的特征, 计算效率)

**请评估:**
1. Layer 16 vs Layer 24/28 对 BEV 占据任务的预期差异
2. 如果 layer 选择有误, 对当前实验结论的影响范围
3. 是否值得投入 ~2h 做多层对比实验

### Q2: BUG-48 对 Plan M 实验的影响

**BUG-48**: `unfreeze_last_n` 解冻 blocks 38-39, 但 layer 16 输出不受这些 blocks 影响 (梯度不流经 blocks 17-39)。

Plan M 曾用 `unfreeze_last_n=2` 测试解冻, 报告"特征漂移"。

**请评估:**
1. 如果 BUG-48 导致 unfreeze 实际未生效, Plan M 的 "特征漂移" 从何而来?
2. 是否需要重跑 Plan M (用正确的 block 解冻)?
3. 这是否意味着方案 B (unfreeze) 的三重否决需要撤销?

### Q3: 修正后阈值矩阵合理性

Conductor 提出分阶段目标:
- @10000: peak > 0.08 (不变)
- @17000 (LR decay 后): peak > 0.15
- @25000: peak > 0.20
- @40000: peak > 0.25

**请评估:**
1. 这些数字是否合理? (基于 BEV 占据 per-cell 评估的特殊性)
2. @17000 是否是正确的关键判断点?
3. 如果修改 layer 后 car_P 基线变化, 这些阈值是否需要重新校准?

## 数据

### 当前训练状态
- ORCH_024: iter 10000/40000, @10000 val 进行中
- peak_car_P = 0.090 (from @6000)
- 结构指标持续改善: off_th=0.140 历史最低

### DINOv3 ViT-7B 结构
```
depth = 40, embed_dim = 4096, num_heads = 32, ffn_ratio = 3
Total params: ~7B (全部冻结, FP16)
Extraction: layer 16 of 40 (40% depth)
Config: online_dinov3_layer_idx=16, unfreeze_last_n=0
```

### 代码引用
- OnlineDINOv3Embed: `vit_git.py:L91-220`
- unfreeze_last_n 逻辑: `vit_git.py:L151-159`
- get_intermediate_layers: `dinov3/models/vision_transformer.py:L270-284`
- 前向遍历所有 blocks: `vision_transformer.py:L275` (for loop over all blocks)
