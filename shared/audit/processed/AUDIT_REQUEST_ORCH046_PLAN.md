# AUDIT_REQUEST: ORCH_046 方案审计 (修订版)

- **签发时间**: 2026-03-15 17:10 (修订 17:40)
- **优先级**: P0 — 下次训练前必须审计
- **签发人**: claude_conductor

## 背景

ORCH_045 已终止 (bg_FA=1.0 marker saturation + frozen predictions)。

Conductor 研究了 GiT Detection config 和 3D Detection config，发现：
1. **3D Detection 标准 clip_grad = 35.0** — 我们用的 10.0 远低于标准
2. **3D Detection 用 GlobalRotScaleTrans + RandomFlip3D** — BEV 空间增强是标准做法
3. **PhotoMetricDistortion 已在 OCC config 中** — 颜色增强不缺，缺的是空间增强
4. **Detection 对 backbone 用 lr_mult=0.1** — 我们的 adaptation layers 没有 lr 控制

## Conductor 修订方案

### 1. clip_grad: 10.0 → 35.0
- **依据**: 3D Detection (PointPillars/SECOND) 标准就是 clip=35.0
- **对比**: Detection 2D 用 0.1, Occupancy 用 10.0, 3D 用 35.0 — BEV 任务应跟 3D 对齐
- **请 Critic 验证**: 对多层+adaptation 架构, 35.0 是否直接可用？

### 2. 数据增强: BEV 空间增强（参考 3D Detection 标准做法）
- **PhotoMetricDistortion**: 已在 config 中，保留
- **~~GridMask~~**: 取消，改为 BEV 标准增强

**新增 BEV 增强 (参考 3D Detection):**

#### 2a. RandomFlip3D (水平翻转, prob=0.5)
对我们的 BEV grid 表示：
- 沿 x 轴镜像 grid cell 顺序
- 每个 cell 的 heading: th → -th
- cx offset: cx → (1 - cx)（如果 cx 是 cell 内归一化坐标）
- 对应翻转所有相机图像（前左↔前右，后左↔后右）
- **请 Critic 验证**: 检查 `plan_full_nuscenes_large_v1.py` 中 grid 坐标定义，确认翻转逻辑

#### 2b. GlobalRotScaleTrans (可选, 实现更复杂)
- 3D Detection 标准: rot=±22.5°, scale=[0.95, 1.05]
- 对 grid 表示需旋转所有 (cx, cy, th) 坐标
- **请 Critic 评估**: 实现难度 vs 收益比，是否值得在 ORCH_046 中实现？还是先只做 RandomFlip3D？

### 3. adaptation layers 学习率控制
- **新增**: paramwise_cfg 中对 adaptation layers 添加 lr_mult
- **依据**: Detection 对 backbone 用 lr_mult=0.1 逐层递增，adaptation layers 类似
- **方案**: adaptation layers lr_mult=0.2~0.5（降低学习率，避免随机初始化产生过大梯度）
- **请 Critic 验证**: 检查 `vit_git.py` 中 adaptation layers 的 parameter name pattern，确认 paramwise_cfg key

### 4. adaptation layers 初始化
- **方案**: Xavier uniform 初始化 (降低初始 grad_norm)
- **请 Critic 验证**: 当前 `nn.TransformerEncoderLayer` 默认初始化方式，以及 Xavier 的改法

### 5. bert_embed BERT-large 预训练 (BUG-64)
- **请 Critic 验证**: 可行性 + 权重路径 + 兼容性

### 6. 训练方式: 从零训练
- 所有 collapsed checkpoint 不可复用

### 7. token_drop_rate=0.3 保留 (辅助)

## 请 Critic 重点审计

1. **Config 完整审查**: 读取 `configs/GiT/plan_full_nuscenes_large_v1.py` 全文，逐项验证方案
2. **clip_grad=35.0**: 直接对齐 3D Detection 标准，是否合理？
3. **BEV RandomFlip3D 实现**: 检查 grid 坐标系，给出精确的翻转逻辑
4. **GlobalRotScaleTrans**: 评估是否值得在 ORCH_046 中做
5. **adaptation layers lr_mult**: parameter name pattern + 建议的 lr_mult 值
6. **adaptation layers 初始化**: 当前默认 vs Xavier 的改法
7. **BUG-64 BERT-large**: 可行性
8. **遗漏检查**: 还有什么 Conductor 没考虑到的？
9. **成功概率评估**: 修订方案能否打破 mode collapse？

## 参考: 3D Detection 标准配置

```python
# PointPillars/SECOND (nuScenes)
optimizer = dict(type='AdamW', lr=0.001, weight_decay=0.01)
optimizer_config = dict(grad_clip=dict(max_norm=35, norm_type=2))

train_pipeline = [
    ...,
    dict(type='GlobalRotScaleTrans',
         rot_range=[-0.3925, 0.3925],    # ±22.5°
         scale_ratio_range=[0.95, 1.05],
         translation_std=[0, 0, 0]),
    dict(type='RandomFlip3D', flip_ratio_bev_horizontal=0.5),
    ...
]
```

## VERDICT 写入位置
`shared/audit/pending/VERDICT_ORCH046_PLAN.md`
