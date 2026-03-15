# AUDIT_REQUEST: ORCH_046 方案审计

- **签发时间**: 2026-03-15 17:10
- **优先级**: P0 — 下次训练前必须审计
- **签发人**: claude_conductor

## 背景

ORCH_045 已终止 (bg_FA=1.0 marker saturation + frozen predictions)。Critic VERDICT 确认：
1. BUG-62 (clip_grad=10) 未修复是致命原因
2. 零数据增强是 mode collapse 根因
3. token_drop_rate=0.3 无效
4. adaptation layers 初始化导致梯度异常

现在 Conductor 计划签发 ORCH_046 修复所有问题后重试。需要 Critic 审计方案的可行性。

## Conductor 方案

### 1. clip_grad: 10.0 → 35.0
- **理由**: adaptation layers grad_norm mean=3007, clip=35 → 有效梯度 ~1%，vs 之前 0.33%
- **风险**: 之前 clip=30 摧毁了分类器 margin (19.73→0.16)，但那是在单层架构下
- **请 Critic 验证**: 35.0 对多层+adaptation 架构是否合理？是否需要更高或更低？

### 2. 数据增强: PhotoMetricDistortion + GridMask
- **理由**: 图像级增强，不需要修改 BEV 标签，实现简单
- **PhotoMetricDistortion**: 改变亮度/对比度/饱和度/色相，BEVDet/BEVFormer 标准做法
- **GridMask**: 随机遮挡图像区域，防止过拟合局部特征
- **请 Critic 验证**:
  1. 当前 config 的 train_pipeline 具体内容是什么？是否真的没有任何增强？
  2. PhotoMetricDistortion 对 frozen DINOv3 ViT-L 是否有效？backbone 已对颜色变化鲁棒？
  3. GridMask 是否会干扰 grid_interpolate 的特征提取？
  4. 是否需要 BEV 空间增强（RandomFlip 等），还是纯图像增强足够打破 mode collapse？
  5. CEO 提到"只能做自动驾驶常用的数据增强"，请审查方案的合理性

### 3. adaptation layers Xavier 初始化
- **理由**: 降低初始 grad_norm，减轻 clip_grad 交互问题
- **请 Critic 验证**: 检查 `vit_git.py:L202-217` 当前初始化方式，建议最佳初始化方案

### 4. bert_embed BERT-large 预训练 (BUG-64)
- **理由**: hidden_size=1024 与 BERT-large 完美匹配，预训练权重加速分类器收敛
- **请 Critic 验证**: 是否可行？权重下载路径？对 GiT occ head 的兼容性？

### 5. 训练方式: 从零训练
- **理由**: 之前所有 checkpoint 都已 collapsed，不可修复
- **替代方案**: 从 ORCH_024 @8000 权重出发？但架构不同（7B→ViT-L, Base→Large）无法直接加载

### 6. token_drop_rate=0.3 保留
- **降级为辅助**, 不作为主要 anti-collapse 手段

## 请 Critic 重点审计

1. **Config 审查**: 读取 `configs/GiT/plan_full_nuscenes_large_v1.py`，逐项检查上述修改是否可行、是否有遗漏
2. **clip_grad 取值**: 35.0 是否合理？建议的精确取值？
3. **数据增强方案**: 对 GiT 架构 + frozen DINOv3 的适用性
4. **初始化方案**: adaptation layers 最佳初始化
5. **BUG-64 可行性**: BERT-large 预训练权重加载
6. **遗漏检查**: 还有什么问题 Conductor 没有考虑到？
7. **风险评估**: 方案的总体可行性，预期能否打破 mode collapse

## VERDICT 写入位置
`shared/audit/pending/VERDICT_ORCH046_PLAN.md`
