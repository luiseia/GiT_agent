# 诊断报告：模型预测固化问题

**日期**: 2026-03-13
**严重级别**: CRITICAL
**影响范围**: ORCH_024 (单层DINOv3) 和 ORCH_035 (多层DINOv3) 全部受影响

---

## 1. 问题描述

模型对不同输入图像产生几乎完全相同的预测（96-99.75%）。不同checkpoint训练越久越严重。

## 2. 根因分析

### 2.1 排除了代码 Bug

通过精准 hook 验证了推理路径的每一步，**图像信息正确流入了 decoder**：

| 检查点 | 跨样本相对差异 | 状态 |
|--------|-------------|------|
| DINOv3 patch_embed | 2.37% | ✅ 变化 |
| grid_interpolate_feats | 2.37% | ✅ 变化 |
| 12层backbone后 | 1.06% | ✅ 变化但减弱 |
| KV cache (最后一层) | 0.51% | ⚠️ 更弱 |
| Decoder output | 1.64% | ✅ 变化 |
| Logits | 1.05% | ✅ 变化 |
| **Argmax prediction** | **98%相同** | 🔴 |

**Logits确实因不同图像而不同（~1%），但差异远小于决策margin（8.05），argmax结果不变。**

### 2.2 确认了训练模式坍缩

| Model | Checkpoint | diff/Margin | 预测相同率 | NEAR/400 |
|-------|-----------|------------|-----------|----------|
| ORCH_024 | iter_4000 (4.6ep) | 7.9% | 97.25% | 156 |
| ORCH_024 | iter_8000 (9.1ep) | 8.7% | 98.00% | 372 |
| ORCH_024 | iter_12000 (13.7ep) | **3.0%** | **99.75%** | 343 |
| ORCH_035 | iter_14000 (15.9ep) | **2.3%** | **99.75%** | **396** |

**训练越久，模型越忽略图像，对固定模式越自信。**

### 2.3 根本原因：**训练 pipeline 完全缺少数据增强**

```python
train_pipeline = [
    LoadAnnotations3D_E2E,
    LoadFrontCameraImageFromFile,
    ResizeForOccInput(1120×1120),  # ← 只做 resize，无任何增强
    pipeline_common,
    AddMetaInfo,
    PackOccInputs
]
test_pipeline = train_pipeline  # ← 训练和测试完全一样！
```

**没有 RandomFlip、RandomCrop、ColorJitter、RandomErasing 等任何数据增强！**

#### 为什么缺少增强会导致坍缩？

1. **空间先验可记忆**: 没有flip/crop，位置(i,j)永远对应相同BEV区域。模型只需记住"位置X的平均物体频率"就能降低loss。
2. **Teacher forcing 加剧**: 自回归训练时用GT token做输入，模型可以不看图像，只根据token频率统计做预测。
3. **无噪声=无探索**: 无增强意味着每个epoch的输入完全一样，梯度方向高度一致，加速收敛到局部极小值（空间先验）。

### 2.4 辅助因素

1. **Marker embedding 过于相似**: NEAR vs END cosine_sim=0.98，模型难以区分
2. **Backbone减小差异**: 12层transformer反而把跨样本差异从2.37%压缩到1.06%
3. **grid_token_initial 是固定task embedding**: occ任务没有加position embedding到grid start

## 3. 修复方案

### 方案 A: 加数据增强（最小改动，必须做）

```python
train_pipeline = [
    LoadAnnotations3D_E2E,
    LoadFrontCameraImageFromFile,
    # ─── 新增数据增强 ───
    dict(type='RandomFlip', prob=0.5, direction='horizontal'),
    dict(type='RandomResize', scale=(1120, 1120), ratio_range=(0.8, 1.2), keep_ratio=True),
    dict(type='RandomCrop', crop_size=(1120, 1120), allow_negative_crop=True),
    dict(type='PhotoMetricDistortion'),  # 颜色抖动
    # ─── 原有 pipeline ───
    ResizeForOccInput(1120×1120),
    pipeline_common,
    AddMetaInfo,
    PackOccInputs
]
```

**注意**: BEV任务的RandomFlip需要同时翻转BEV标注！这需要修改数据pipeline。

### 方案 B: 加 Scheduled Sampling（中等改动）

在训练的self-regression中，按一定概率用模型自己的预测代替GT token作为输入：
- 初始: 100% teacher forcing
- 逐步: 每1000 iter 增加5% scheduled sampling
- 最终: 50% teacher forcing + 50% scheduled sampling

这迫使模型在没有GT提示的情况下，必须依赖图像特征来做正确预测。

### 方案 C: 架构改进（较大改动）

1. **为occ任务添加position embedding**: 当前occ任务的grid_start_embed没有加position encoding（line 334: `if self.mode != 'occupancy_prediction': grid_pos_embed`）
2. **每步注入图像特征**: 当前grid_interpolate_feats只在pos_id=0时注入，改为每步都注入
3. **分离marker预测头**: 不走vocabulary logits，用单独的二分类头预测有无物体

## 4. 推荐行动

1. **立即**: 停止当前所有训练（继续训练只会让坍缩更严重）
2. **优先级 P0**: 实现方案A（数据增强），注意BEV标注需要同步翻转
3. **优先级 P1**: 实现方案C.1（为occ加position embedding）和方案C.2（每步注入图像特征）
4. **验证**: 加增强后，重新训练到iter_4000，运行本诊断脚本检查diff/Margin是否在增加
5. **之后考虑**: 方案B（scheduled sampling）和方案C.3

## 5. 诊断脚本

- `scripts/diagnose_v3_precise.py` — 全链路特征流追踪
- `scripts/diagnose_v3b_logit_analysis.py` — logit/margin分析
- `scripts/diagnose_v3c_single_ckpt.py` — 跨checkpoint趋势比较

所有脚本可复用于验证修复效果。
