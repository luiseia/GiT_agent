# 审计判决 — ORCH046_PLAN

## 结论: CONDITIONAL — 方案有重大遗漏，修正后可执行

Conductor 的方案方向正确，但存在两个致命盲点:
1. **PhotoMetricDistortion 已经存在于 config 中** — Conductor 不知道。ORCH_045 是带着数据增强训练的，仍然崩塌了。根因不是"零数据增强"
2. **BUG-69 (NEW): adaptation layers lr_mult=0.05** — 随机初始化的适应层以 5% 学习率训练，等于冻结。这才是 ORCH_045 崩塌的最大原因

---

## 重大纠正: 我之前 VERDICT_ORCH045_AT2000 中的错误

**错误声明**: "数据增强检查: train_pipeline 无 RandomFlip / PhotoMetricDistortion → CRITICAL"

**事实**: commit `26b6f92` (ORCH_045 使用的 config) 的 `train_pipeline` 在 L301 **已包含** `dict(type='PhotoMetricDistortion')`。train_pipeline 和 test_pipeline 也已分离 (L295 vs L309)。

**影响**: 之前审计中"数据增强是 mode collapse 根因"的结论需要修正。PhotoMetricDistortion (颜色增强) 已存在但不足以防止 mode collapse。真正的根因需要重新诊断。

---

## 逐项审计 Conductor 方案

### 1. clip_grad: 10.0 → 35.0

**结论: 合理但需要更高值**

- grad_norm mean=3007, clip=35 → 有效梯度 35/3007 = 1.16%
- 依然丢失 98.8% 的梯度信号
- **建议**: 改为 **50.0** 或更高
  - clip_grad=50: 有效 1.66%, 覆盖 grad_norm < 50 的 iteration (几乎为 0)
  - clip_grad=100: 有效 3.3%, 更激进但之前 clip=30 导致 classifier margin 崩塌的经验需考虑
  - **折中方案**: clip_grad=50, 观察 @2000 的 grad_norm 分布再调整

**风险评估**: Conductor 提到"之前 clip=30 摧毁分类器 margin (19.73→0.16)"。但那是在单层架构下, 当前多层+adaptation 架构的梯度分布完全不同。之前的经验不能直接适用。

**补充**: clip_grad 的问题不仅是数值大小。更根本的问题是 adaptation layers 的 lr_mult (见 BUG-69)。即使 clip_grad 设为 50, 如果 adaptation layers 的 lr_mult 是 0.05, 它们仍然几乎不更新。

### 2. 数据增强: PhotoMetricDistortion + GridMask

**结论: PhotoMetricDistortion 已存在! GridMask 需要评估**

**回答 Conductor 的具体问题:**

> Q1: 当前 config 的 train_pipeline 具体内容是什么？是否真的没有任何增强？

**有!** `configs/GiT/plan_full_nuscenes_large_v1.py:L301` 已包含 `dict(type='PhotoMetricDistortion')`。这个增强从 commit `4eb7cf7` ("add GiT-Large + DINOv3 ViT-L config with data augmentation (P0+P1)") 就已存在。ORCH_045 的整个训练过程中 PhotoMetricDistortion 一直在工作。

**这意味着: PhotoMetricDistortion (颜色增强) 不足以防止 mode collapse。**

> Q2: PhotoMetricDistortion 对 frozen DINOv3 ViT-L 是否有效？backbone 已对颜色变化鲁棒？

**部分有效**: PhotoMetricDistortion 改变亮度/对比度/饱和度/色相 (L896-955 in `mmdet/datasets/transforms/transforms.py`)。DINOv3 ViT-L 的预训练确实使其对颜色变化具有一定鲁棒性, 但不是完全不变的。从 ORCH_045 的特征流诊断看, patch_embed_input 的 cross-sample diff=2.37% — 特征确实在变化。问题不在特征提取, 而在 decoder 的 mode collapse。

> Q3: GridMask 是否会干扰 grid_interpolate 的特征提取？

**可能会**: GridMask 在图像上随机遮挡区域, 这会直接影响 DINOv3 提取的 patch features。被遮挡的 patch 产生的 feature 接近 zero/noise。grid_interpolate 从这些 feature 中插值时会得到降质的值。但这正是 GridMask 的目的 — 迫使模型不依赖特定区域。

**风险**: GridMask 不在当前 codebase 中 (`grep -rn "class GridMask" mmdet/` 无结果)。需要从 mmdet3d 或外部实现。实现复杂度中等。

> Q4: 是否需要 BEV 空间增强（RandomFlip 等）？

**是的, 这是最关键的缺失。** PhotoMetricDistortion 只改变像素值, 不改变空间布局。同一场景的 BEV labels 完全相同。模型可以学到一个固定的 BEV 空间先验 (如"大多数场景的某些位置更可能有行人"), 而 PhotoMetricDistortion 无法打破这个先验。

**RandomFlip (水平翻转) 的实现**:
- 翻转图像: 简单
- 翻转 BEV 标签: 需在 `GenerateOccFlowLabels` 之前翻转 3D annotations 的 x 坐标和 rotation
- 具体: `box_x → -box_x`, `rotation → π - rotation`
- 复杂度: 中 (需修改 pipeline)
- **这应该是 P0 优先级**, 而非 GridMask

> Q5: CEO 提到"只能做自动驾驶常用的数据增强"

PhotoMetricDistortion ✅ (BEVDet/BEVFormer/UniAD 标配)
RandomFlip3D ✅ (BEVDet/BEVFormer 标配, 水平翻转)
GridMask ✅ (PETR/BEVDet 使用过)
RandomScale ⚠️ (需要谨慎, 改变 BEV 分辨率)

**建议优先级**: RandomFlip3D > GridMask > RandomScale

### 3. adaptation layers Xavier 初始化

**结论: 初始化不是问题, lr_mult 才是!**

当前 `nn.TransformerEncoderLayer` 的默认初始化已经合理:
- `self_attn.in_proj_weight`: std=0.0221 (Kaiming uniform, 实际接近 Xavier)
- `linear1.weight`: std=0.0180
- `linear2.weight`: std=0.0090

**真正的问题是 BUG-69 (见下文)**: adaptation layers 的 lr_mult 被意外设为 0.05。

验证方式 — mmengine `DefaultOptimWrapperConstructor.add_params()` 源码:
```python
sorted_keys = sorted(sorted(custom_keys.keys()), key=len, reverse=True)
# ...
for key in sorted_keys:
    if key in f'{prefix}.{name}':  # SUBSTRING MATCH, longest first
        lr_mult = custom_keys[key].get('lr_mult', 1.)
        break
```

`backbone.patch_embed.adapt_layers.0.self_attn.in_proj_weight` 的匹配过程:
1. `backbone.patch_embed.proj` (最长) → **不匹配** (不是子串, `adapt_layers` ≠ `proj`)
2. `backbone.layers.23` → **不匹配**
3. ... (其他层级 keys)
4. `backbone` → **匹配!** → `lr_mult=0.05`

**结果**: adaptation layers 有效学习率 = 5e-5 × 0.05 = **2.5e-6**

对比:
- `backbone.patch_embed.proj` (投影层): lr_mult=2.0 → lr=**1.0e-4** (40× 快于 adaptation)
- `backbone.layers.24-29` (新 backbone 层): lr_mult=1.0 → lr=**5.0e-5** (20× 快于 adaptation)
- `backbone.patch_embed.adapt_layers` (适应层): lr_mult=0.05 → lr=**2.5e-6** (冻结!)

### 4. bert_embed BERT-large 预训练 (BUG-64)

**结论: 可行, 代码已支持**

`mmdet/models/detectors/git.py:L59-60`:
```python
text_embedding_type = bert_embed['type']
assert text_embedding_type in ['bert-base', 'bert-large', 'bert-huge']
```

`git.py:L103-104`:
```python
if 'pretrain_path' in self.bert_embed_cfg.keys() and self.bert_embed_cfg['pretrain_path'] is not None:
    self.embed.load_state_dict(torch.load(self.bert_embed_cfg['pretrain_path'], ...))
```

**实施方案**:
1. 下载 BERT-large 的 embedding 权重 (vocab_embeddings + position_embeddings + token_type_embeddings + LayerNorm)
2. 提取 `BertEmbeddings` 部分的 state_dict
3. Config 改为: `bert_embed=dict(type='bert-large', hidden_size=1024, pretrain_path='<path>')`

**注意**: BERT-large 的 hidden_size=1024, 与当前 config 的 `hidden_size=1024` 完美匹配。权重可以直接加载。

**权重获取**:
```bash
python -c "from transformers import BertModel; m = BertModel.from_pretrained('bert-large-uncased'); torch.save(m.embeddings.state_dict(), 'bert_large_embeddings.pth')"
```

**优先级**: 这是低风险改进, 但不是 mode collapse 的根因。建议 P2。

### 5. 训练方式: 从零训练

**结论: 正确**

所有现有 checkpoint 都已 collapsed, 无法修复。架构也发生了变化 (multi-layer + adaptation), 旧权重不兼容。从零训练是唯一选择。

### 6. token_drop_rate=0.3 保留

**结论: 可保留但降级为辅助**

Token corruption 的逻辑 (`git.py:L503-507`) 是在 GT input sequence 中替换 30% 的 token 为随机值。这是一种输入噪声注入, 类似 scheduled sampling 的弱化版。

**分析**: 它没有效果的原因可能是:
1. 替换的是 GT token (teacher forcing context), 但模型仍然用 GT token 的 embedding 做 attention
2. 30% random tokens 的 embedding 可能被模型学会忽略 (当 token 明显 out-of-distribution 时)
3. 真正的 scheduled sampling 是让模型看到自己的预测, 而非随机 token

**建议**: 保留 token_drop_rate=0.3 作为辅助, 但优先实现真正的 scheduled sampling。

---

## 发现的问题

### 1. **BUG-69: adaptation layers lr_mult=0.05 — 实际冻结** (CRITICAL)
- **描述**: `paramwise_cfg` 中 `'backbone': dict(lr_mult=0.05)` 通过 substring match 应用到所有 backbone 参数, 包括随机初始化的 `backbone.patch_embed.adapt_layers.*` 和 `backbone.patch_embed.adapt_norm.*`。这使得 25.2M 可训练参数的适应层以 2.5e-6 的学习率"训练", 实际等于冻结
- **严重性**: CRITICAL — 这可能是 ORCH_045 失败的**首要原因**
- **位置**: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py:L380` — `'backbone': dict(lr_mult=0.05)` (覆盖所有 backbone.* 参数); 需要在 L376-377 之间添加 adapt_layers 和 adapt_norm 的 lr_mult override
- **修复建议**:
```python
# 在 paramwise_cfg.custom_keys 中添加:
'backbone.patch_embed.adapt_layers': dict(lr_mult=1.0),
'backbone.patch_embed.adapt_norm': dict(lr_mult=1.0),
```
- **验证方法**: 训练开始后打印每个参数组的 lr:
```python
for pg in optimizer.param_groups:
    if 'adapt' in str(pg.get('name', '')):
        print(f"  lr={pg['lr']}")
```

### 2. **BUG-70: VERDICT_ORCH045_AT2000 错误声明"零数据增强"** (CORRECTION)
- **描述**: 我 (claude_critic) 在 VERDICT_ORCH045_AT2000 中错误声明 "数据增强检查: train_pipeline 无 RandomFlip / PhotoMetricDistortion → CRITICAL (未修复，根因仍在)"。事实上 config commit `26b6f92` 已包含 PhotoMetricDistortion (L301), train/test pipeline 已分离。这导致 Conductor 在 MASTER_PLAN 中采纳了错误的根因分析
- **严重性**: HIGH (影响后续决策)
- **位置**: `shared/audit/pending/VERDICT_ORCH045_AT2000.md` 健康检查结果 section
- **影响**: Conductor 基于"零数据增强是根因"制定 ORCH_046 方案, 但实际 PhotoMetricDistortion 已存在且无效。方案优先级需要调整
- **修复建议**: Conductor 应重新评估 mode collapse 根因, 考虑 BUG-69 (lr_mult) 和缺乏空间增强两个方向

### 3. **BUG-62 仍未修复** (CRITICAL, 延续)
- **描述**: clip_grad=10.0 仍在 config L372, 需修复为 50.0
- **位置**: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py:L372`

### 4. **BUG-64 仍未修复** (HIGH, 延续)
- **描述**: bert_embed 使用 type='bert-base' + hidden_size=1024 + pretrain_path=None, 应改为 'bert-large' + 预训练权重
- **位置**: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py:L192`

---

## 健康检查结果

### A. Mode Collapse 检测

- [x] **数据增强检查**: train_pipeline **已有** PhotoMetricDistortion (L301) → ⚠️ 但仅颜色增强, 无空间增强 (RandomFlip)。颜色增强不足以防止 mode collapse
- [x] **Pipeline 分离检查**: train_pipeline ≠ test_pipeline → ✅ 已修复
- [x] **预测多样性**: 97-99% identical → 🔴 CRITICAL (ORCH_045 数据)
- [x] **Marker 分布**: 91.5% 正预测 → 🔴 CRITICAL (ORCH_045 数据)
- [x] **训练趋势**: @2000→@6000 恶化 → 🔴 CRITICAL (ORCH_045 数据)

### B. Shortcut Learning 检测

- [x] **Loss-指标背离**: loss 波动, eval 恶化 → 🔴 HIGH
- [x] **Teacher Forcing 风险**: 100% teacher forcing, token_drop_rate=0.3 证伪, 无 scheduled sampling → ⚠️ MEDIUM

### C. 架构风险检测

- [x] **位置编码完整性**: P2 fix 在位 → ✅
- [x] **特征注入频率**: P3 fix 在位 → ✅
- [x] **维度匹配**: 4×1024→2048→GELU→1024 → ✅
- [x] **学习率匹配**: adaptation layers lr_mult=0.05 → 🔴 **CRITICAL** (BUG-69)

### D. 资源浪费检测

- [x] **无效训练**: ORCH_045 已停止 → ✅
- [x] **Checkpoint 价值**: 无可用 checkpoint → N/A

---

## 配置审查结果

- [x] 颜色增强 (PhotoMetricDistortion): **有** → ✅ (但不够)
- [x] 空间增强 (RandomFlip): **无** → 🔴 CRITICAL (需添加)
- [x] Pipeline 分离: **是** → ✅
- [x] Position embedding: P2 fix 在位 → ✅
- [x] 特征注入频率: 仅首步 (P3 fix) → ✅
- [x] Scheduled sampling: **无** → ⚠️ MEDIUM
- [x] clip_grad: 10.0 → 🔴 CRITICAL (需改为 50+)
- [x] token_drop_rate: 0.3 → ⚠️ 保留但降级
- [x] bert_embed: bert-base, no pretrain → ⚠️ 建议升级
- [x] adapt_layers lr_mult: 0.05 → 🔴 **CRITICAL (BUG-69, 需改为 1.0+)**
- [x] adapt_norm lr_mult: 0.05 → 🔴 CRITICAL (同上)
- [x] load_from: None (从零训练) → ✅

---

## ORCH_045 崩塌根因重新分析

之前归因于"零数据增强"是错误的。综合所有证据, ORCH_045 mode collapse 的根因排序:

| 排名 | 因素 | 证据 | 影响 |
|------|------|------|------|
| **#1** | **BUG-69: adaptation layers lr_mult=0.05** | mmengine substring match 确认, lr=2.5e-6 | 25.2M 适应层参数等于冻结, 多层 DINOv3 特征无法被有效变换 |
| **#2** | **BUG-62: clip_grad=10** | grad_norm=3007, 有效梯度 0.33% | 全模型梯度信号被扼杀 |
| **#3** | **缺乏空间增强** | PhotoMetricDistortion 存在但仍崩塌 | 颜色增强无法打破 BEV 空间先验 |
| **#4** | **100% teacher forcing** | 无 scheduled sampling | 推理时 exposure bias → 崩塌到固定模式 |
| **#5** | token_drop_rate 效果有限 | 单独不足以防 collapse | 辅助措施, 非核心 |

**关键推理**: 如果 adaptation layers 实际冻结, 那么多层 DINOv3 特征 (4096→2048→GELU→1024) 只经过投影层变换, 没有经过适应层的非线性变换。投影层只是线性降维, 可能不足以将 4 层不同语义层级的 DINOv3 特征整合为模型可用的信号。

---

## 对 Conductor 计划的评价

### 错误/盲点

1. **不知道 PhotoMetricDistortion 已存在**: 审计请求问"是否真的没有任何增强", 说明 Conductor 没有仔细读 config。应加强 ORCH 签发前的 config 审查
2. **遗漏 lr_mult 问题**: 这是最影响训练的配置错误。Conductor 正确识别了 clip_grad 和初始化问题, 但遗漏了更基本的学习率问题
3. **优先级排序不准确**: 把"数据增强"放在首位, 但实际上 BUG-69 (lr_mult) 是首要修复项

### 正确判断

1. clip_grad 需要增大 → 正确
2. 从零训练 → 正确
3. token_drop_rate 降级 → 正确
4. bert_embed 升级 → 正确, 但优先级正确 (P2)

### 修正后的优先级排序

| 优先级 | 修复项 | 说明 |
|--------|--------|------|
| **P0** | **BUG-69**: adapt_layers/adapt_norm lr_mult → 1.0 | 让 25.2M 适应层真正参与训练 |
| **P0** | **BUG-62**: clip_grad → 50.0 | 释放梯度信号 |
| **P1** | RandomFlip3D (水平翻转) | 空间增强, 打破 BEV 空间先验 |
| **P1** | Scheduled Sampling (开始比例 0.8→0.5) | 防止 exposure bias |
| **P2** | **BUG-64**: bert_embed → bert-large + pretrain | 加速分类器收敛 |
| **P3** | GridMask (需实现) | 额外图像增强, 非必须 |
| 保留 | token_drop_rate=0.3 | 辅助, 不计入核心措施 |

---

## 需要 Admin 协助验证

### 假设 1: BUG-69 是 ORCH_045 崩塌首因
- **假设**: 修复 lr_mult + clip_grad 后, 即使不添加 RandomFlip, mode collapse 也会显著减轻
- **验证方法**: 修复 BUG-69 + BUG-62 后从零训练 2000 iter, 不添加新增强
- **预期结果**: bg_FA < 0.5, 预测不完全 frozen (IoU < 0.9)

### 假设 2: 打印实际 lr 确认 BUG-69
- **假设**: adaptation layers 的实际 lr 是 2.5e-6 而非 5e-5
- **验证方法**: 在训练启动后加一行 print:
```python
# 在 train loop 开始后
for i, pg in enumerate(runner.optim_wrapper.optimizer.param_groups):
    print(f"param_group[{i}]: lr={pg['lr']:.2e}, params={sum(p.numel() for p in pg['params'])}")
```
- **预期结果**: adapt_layers 参数对应的 param_group lr ≈ 2.5e-6

### 假设 3: RandomFlip3D 实现可行性
- **假设**: 可以在 LoadAnnotations3D_E2E 之后、GenerateOccFlowLabels 之前插入 RandomFlip3D
- **验证方法**: 检查 `LoadAnnotations3D_E2E` 输出的 annotation 格式, 确认 x 坐标和 rotation 的翻转逻辑
- **预期结果**: 翻转后 BEV 标签正确 (目视检查 BEV 可视化)

---

## 附加建议

1. **ORCH_046 执行顺序**: 先修复 BUG-69 + BUG-62 (纯 config 修改, 5 分钟), 启动短训练 (2000 iter) 验证。如果不崩塌, 再添加 RandomFlip3D 和 scheduled sampling 作为 ORCH_047

2. **Conductor 应加强 config 审查**: 本次审计发现 Conductor 对当前 config 的 pipeline 内容不了解。建议每次签发 ORCH 前, 用 diff 工具对比 config 变更

3. **自动 kill switch**: @2000 eval 时如果 bg_FA > 0.7, 立即停止。不要再等到 @4000/@6000

4. **梯度监控**: 在训练初期 (前 100 iter) 打印 adaptation layers 的参数更新幅度:
```python
# 每 10 iter: ||param_new - param_old|| / ||param_old||
```
如果更新幅度 < 1e-5, 说明学习率太低

---

*审计时间: 2026-03-15 16:55-17:15*
*审计人: claude_critic*
*关键代码验证: mmengine DefaultOptimWrapperConstructor.add_params() substring match 逻辑*
