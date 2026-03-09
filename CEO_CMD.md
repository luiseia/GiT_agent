# CEO 指令

两个问题需要调查，撰写报告保存到 shared/logs/decision_matrix_and_dinov3_review.md 并 git push。

## 问题 1：@10000 决策矩阵标准是否太低？

当前决策矩阵 peak_car_P 阈值设在 0.08-0.10，CEO 认为这个标准可能太低。请分析：

1. Full nuScenes 数据集上，car_P 的合理预期是多少？参考 BEVFormer/PETR 等同类方法在 nuScenes 上的表现
2. 我们的 mini 上 car_P 天花板是 ~0.13，Full nuScenes 上应该显著提升——0.10 是否太保守？
3. 如果 @10000 时 car_P 仍然只有 0.10，这是否意味着架构有根本问题而不是"还在收敛"？
4. 建议重新设定决策矩阵的阈值，给出你认为合理的标准和理由
5. 如果需要 Critic 评估，签发 AUDIT_REQUEST

## 问题 2：DINOv3 解冻策略重新评估

之前方案 B (DINOv3 全量 unfreeze) 被三重否决。但 CEO 想重新考虑：

### 2a. 部分解冻可行性
- Plan M 是全量 unfreeze last-2 层导致特征漂移，但如果只解冻最后 1 层呢？
- 或者只解冻投影层后面的 adapter（不动 DINOv3 本体）？
- 显存增量分别是多少？A6000 48GB 能否承受？
- 在 Full nuScenes（数据量远大于 mini）上，特征漂移风险是否降低？

### 2b. Layer 16 选择是否正确
- 当初选 Layer 16 的依据是什么？是实验验证还是经验判断？
- DINOv3 有 32+ 层，Layer 16 是中间层——会不会太深或太浅？
- 有没有快速验证不同层效果的方法？（比如用预提取对比 Layer 12/16/20/24 的特征质量）
- 如果选错了层，对所有后续实验的结论有什么影响？

### 2c. LoRA vs 部分解冻
- LoRA rank=16 约 12M 参数、+2GB 显存，vs 解冻最后 1 层约多少参数和显存？
- 在 Full nuScenes 数据量下，哪个方案更合理？
- 两者能否叠加使用？

请基于代码和实验数据分析，读取 ORCH_024 的 config 确认当前 DINOv3 到底冻结了哪些层。如果需要 Admin 跑对比实验或 Critic 审计，直接签发。

注意：签发 ORCH 必须包含「- **状态**: PENDING」行。
