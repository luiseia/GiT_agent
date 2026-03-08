# 审计判决 — 3D_ANCHOR

## 结论: CONDITIONAL

**条件: 3D Anchor 和 V2X 融合是有价值的长期方向，但当前 avg_P=0.107 的核心瓶颈是 DINOv3 特征深度不足，而非缺少 3D 空间编码。建议分阶段推进: 第一步先完成 DINOv3 中间层特征集成 (P5)，第二步再引入 3D Anchor。直接跳到 3D Anchor 会在尚未解决的 Precision 基础问题上叠加新的复杂度。**

---

## 第 1 部分: 当前架构的 3D 信息流分析

### 当前 Grid Token 的空间编码

```
grid_reference = grid_norm (2D 归一化坐标, 范围 [0,1])
  → git.py:L326: grid_reference = grid_norm.view(B, -1, 2).detach()

grid_start_embed = task_embedding (纯语义, 无空间信息)
  → git.py:L329: self.task_embedding[self.mode_id][None, None, :].repeat(...)

每层 Transformer:
  grid_feature = grid_forward + grid_start_embed  (L591)
  grid_feature += F.grid_sample(patch_embed_2d, grid_reference * 2 - 1)  (L596)
```

**关键发现: 当前 grid_reference 是纯 2D 图像坐标 (u, v)，没有任何 3D 空间信息。** 模型不知道每个 grid cell 对应的 BEV 物理坐标，也不知道从相机到该 cell 的深度或方向。3D 信息完全依赖模型从 2D 特征中隐式学习。

### 当前文本编码流程

```python
# git.py:L719-749: concept_generation()
1. tokenizer(concept_list) → token_ids  (BERT tokenizer)
2. embed.word_embeddings(token_ids) → token_embeddings
3. 多片段概念通过 self-attention 融合
4. 取第 2 个 token 的 embedding 作为概念表示
```

`concept_list` 当前仅包含任务名称 (如 `['occupancy_prediction', ...]`) 和词表 token。文本编码器已存在且功能完整，但未用于编码空间信息。

---

## 第 2 部分: 方案 A vs 方案 B 对比

### 方案 A: 射线 Anchor + 全文本 Token

**描述**: 从相机光心出发，向每个 grid cell 方向发射射线，在射线上等距/非均匀采样 3D 点作为 Anchor。每个 Anchor 的 3D 坐标编码为文本 token，送入 BERT 文本编码器，注入 ViT 的 K/V。

**优势**:
1. **深度方向精度高**: 射线采样可以覆盖不同深度的目标 (近处 5m 和远处 50m 的车辆)
2. **与 GiT 架构兼容**: GiT 已有文本编码器 (`concept_generation`)，注入 K/V 的机制已存在 (`text_embed` 参与 attention mask)
3. **灵活性高**: 可以自由编码任意 3D 信息 (坐标、方向、速度等)

**劣势**:
1. **射线长度不一致**: 不同方向的射线在场景中覆盖的有效范围不同。朝地面的射线只有几米 (到地面交点)，朝天空的射线理论上无穷长。需要截断策略。
2. **Token 数量爆炸**: 20x20 grid × N 个采样点/射线 = 400N 个 Anchor token。如果 N=5，则 2000 个额外 token，极大增加计算量。
3. **文本编码器的语义鸿沟**: BERT 的文本编码器是为自然语言设计的。"x=10.5, y=3.2" 这样的坐标字符串不在 BERT 的预训练分布内，编码质量存疑。

### 方案 B: BEV Grid 中心 Anchor

**描述**: 不使用射线，直接用 BEV grid 中心点的 3D 坐标 (x_bev, y_bev, z=0) 作为 Anchor，投影到 BEV grid 上融合 ego 和 sender 信息。

**优势**:
1. **与现有 grid 结构完美对齐**: 20x20 BEV grid 已存在，每个 cell 中心天然就是 Anchor
2. **无射线长度问题**: BEV 空间是 2D 平面 (z=0)，无需处理深度方向
3. **实现简单**: 只需给现有 grid_token 添加 BEV 物理坐标的 positional encoding

**劣势**:
1. **丢失深度信息**: BEV 是 2D 的。同一个 BEV cell 在不同高度可能有多个目标 (立交桥上下)
2. **分辨率受限于 grid**: 5m x 5m 的 BEV cell 内无法区分不同位置的目标
3. **与相机视角脱节**: BEV Anchor 不知道从相机角度看某个 cell 是否被遮挡

### 综合判断

**推荐方案 B 作为第一步**, 原因:
1. 当前 `grid_reference` 已经是 2D 坐标 (git.py:L326)，只需从图像坐标改为 BEV 物理坐标
2. 实现复杂度低 (1-2 天 vs 方案 A 的 5-7 天)
3. 深度信息的缺失在当前任务 (单目前视相机 → BEV 预测) 中影响有限——模型本来就需要从单目图像推断深度
4. 方案 B 验证有效后，再在 BEV Anchor 基础上叠加射线采样 (混合方案)

---

## 第 3 部分: 射线长度不一致的解决方案

### 方案 3a: 固定范围截断

将所有射线截断到 [d_min, d_max] 范围 (如 [1m, 50m])，在范围内等距采样 N 个点。

- 优点: 简单
- 缺点: 近处目标 (1-10m) 和远处目标 (40-50m) 的采样密度相同，但近处需要更高精度

### 方案 3b: 非均匀采样 (对数间隔)

在 [d_min, d_max] 范围内使用对数间隔: `depths = d_min * (d_max/d_min)^(k/N)`, k=0,...,N-1

- 优点: 近处密、远处疏，符合相机成像特性 (近大远小)
- 缺点: 与 BEV grid 的均匀间隔不一致

### 方案 3c: 基于 BEV grid 边界的自适应采样

每条射线只采样到它穿过的 BEV grid 范围 (100m × 100m)。射线与 BEV 边界的交点决定最大深度。

- 优点: 物理上最合理
- 缺点: 每条射线的采样点数不同，需要 padding

### 推荐: 方案 3b (对数间隔)

物理合理且实现简单。与 BEVDet、DETR3D 等方法中的深度离散化策略一致。

---

## 第 4 部分: 混合方案评估

**"BEV 平面用 grid 中心，深度方向用射线采样"**

这本质上就是 **BEVFormer 的 spatial cross-attention** 机制:
1. 每个 BEV query 的参考点是 BEV grid 中心 (x, y)
2. 在参考点垂直方向 (z 轴) 的不同高度采样 3D 点
3. 将 3D 点投影回图像平面，从图像特征中采样

**与当前 GiT 的区别**:
- GiT 当前: grid_reference 是 2D 图像坐标 → `F.grid_sample` 从图像特征采样
- BEVFormer: 3D 参考点投影到图像 → deformable attention 从图像特征采样

**可行性**: 高。实现方式:
1. 将 `grid_reference` 从 2D 图像坐标改为 3D BEV 坐标 `(x_bev, y_bev, z_k)`, k=0,...,K-1
2. 在 `get_grid_feature` 中将 3D 坐标通过相机内外参投影到图像坐标
3. 使用 `F.grid_sample` 从图像特征采样 (替代当前的 2D 采样)

**预估工作量**: 3-5 天
- 需要相机内参 (已有) 和外参 (需确认数据流)
- 需要修改 `get_grid_feature` 和 `forward_transformer`

---

## 第 5 部分: V2X 信息融合可行性

### Sender OCC Box 的 Token 化

**推荐: Embedding 而非文本**

文本编码 ("sender_1: car at grid(5,8), NEAR") 有三个问题:
1. BERT 不理解数字坐标 ("5,8" 没有空间语义)
2. Tokenizer 会把数字切成子 token，破坏连续性
3. 文本编码器的容量有限 (max_position_embeddings=512)

**更好的方案**: 将 sender 的 occ box 直接投影到 BEV grid 上，生成一个 (20, 20, C) 的 feature map (类似 BEV 特征)，其中 C 包含类别 one-hot、置信度、方向等。然后将这个 feature map 与 ego 的 patch_embed 通过 cross-attention 或 concatenation 融合。

### 时序信息编码

**推荐: 轨迹级特征 (而非逐帧 token)**

逐帧 token 方案 ("ego_t-1: x=10.5, y=3.2, heading=45°") 存在 token 数量膨胀问题 (每帧 3+ token × 历史帧数)。

轨迹级特征方案:
1. ego 过去 N 帧的位姿 `(x, y, heading)` 组成序列 `(N, 3)`
2. 通过小型 1D Conv 或 MLP 编码为单个 embedding `(1, 768)`
3. 作为附加 token 拼接到 grid_token 或 text_embed 中

### 与当前 GiT 架构的兼容性

**高度兼容。** GiT 的 Transformer 已支持多种输入拼接:
- `patch_embed` (图像)
- `text_embed` (文本)
- `grid_token` (grid query)
- `seq_embed` (序列 token)

V2X 和时序信息可以作为新的 token 类型，通过 attention mask 控制可见性。

### 相关文献对比

| 方法 | V2X 编码方式 | 融合位置 | 适用性 |
|------|-------------|---------|--------|
| V2X-ViT | Agent-aware attention | Transformer 中间层 | 高 — 与 GiT 的多层 Transformer 兼容 |
| Where2comm | 通信感知特征选择 | BEV 特征层 | 中 — 需要 BEV 特征图 |
| CoBEVT | Fused Axial Attention | BEV Transformer | 中 — 需要独立的 BEV encoder |
| DiscoNet | 知识蒸馏 | 特征压缩 | 低 — 需要 teacher 模型 |

**GiT 最适合 V2X-ViT 的方式**: 将 sender 信息编码为 token，在 Transformer 层中通过 attention 融合。

---

## 第 6 部分: 分阶段实现建议

### 第一步: BEV 坐标 Positional Encoding (最小可行实验)

**目标**: 验证显式 3D 空间信息是否比隐式学习更有效。

**改动 (最小化)**:
1. 将 `grid_reference` 从 2D 图像坐标 `(u_norm, v_norm)` 扩展为 BEV 物理坐标 `(x_bev, y_bev)`
2. 用可学习的 MLP 将 BEV 坐标编码为 positional embedding
3. 加到 `grid_start_embed` 上: `grid_start_embed += bev_pos_embed`

**代码位置**: `git.py:L329-340`

**当前**:
```python
grid_start_embed = self.task_embedding[self.mode_id][None, None, :].repeat(B, num_grids, 1)
# 所有 grid 共享同一个 task_embedding, 无位置区分
```

**改动后**:
```python
grid_start_embed = self.task_embedding[self.mode_id][None, None, :].repeat(B, num_grids, 1)
bev_coords = self.get_bev_coords(grid_reference)  # (B, num_grids, 2) → BEV物理坐标
bev_pos_embed = self.bev_pos_mlp(bev_coords)      # MLP(2→768)
grid_start_embed = grid_start_embed + bev_pos_embed
```

**预估工作量**: 0.5-1 天
**风险**: 极低 (添加性改动，不破坏现有逻辑)
**验证**: 对比 offset_cx/cy 是否改善 (3D 空间编码应直接提升位置预测精度)

### 第二步: 相机投影的 3D Anchor (在第一步验证后)

1. 在每个 BEV grid 中心，沿 z 轴采样 K=4 个高度点: z = [-1, 0, 1, 2] m
2. 通过相机内外参投影到图像坐标
3. 替代 `get_grid_feature` 中的 `F.grid_sample` 位置

**预估工作量**: 2-3 天

### 第三步: V2X 融合 (在第二步验证后)

1. sender occ box → BEV feature map (20, 20, C)
2. 通过 cross-attention 与 ego 的 grid_token 融合
3. ego 轨迹 → MLP → 附加 token

**预估工作量**: 3-5 天

### 关键原则: 每步验证后再进入下一步

不要同时实现 3D Anchor + V2X + 时序。每个改动独立验证，才能确定因果关系。

---

## 第 7 部分: 与 DINOv3 集成的优先级关系

### 当前最大瓶颈

| 瓶颈 | 影响 | 解决方案 | 优先级 |
|------|------|---------|--------|
| DINOv3 只用 Conv2d | avg_P=0.107 (语义不足) | 中间层特征提取 | **P5 (最高)** |
| 无 3D 空间编码 | offset_cx/cy/th 不达标 | 3D Anchor / BEV PE | **P6 (次高)** |
| Score 无区分度 | Precision 被 FP 拖累 | Objectness head | P6-P7 |
| V2X 融合 | 单视角遮挡问题 | Sender 信息注入 | **P7+ (长期)** |

**判断**: DINOv3 集成解决的是"模型能不能看懂图像"的基础问题。3D Anchor 解决的是"模型知不知道在预测哪里"的空间理解问题。前者是后者的前提——如果模型连图像中的车辆都识别不好 (car_P=0.08)，给它 3D 坐标信息也帮助有限。

**建议**: P5 做 DINOv3 集成，P6 做 BEV 坐标 PE + 3D Anchor (第一步+第二步)，P7+ 做 V2X。

---

## BUG 状态

本次审计未发现新 BUG。下一个 BUG 编号: BUG-17。

---

## 逻辑验证

- [x] 当前 grid_reference 确认为纯 2D 坐标 (git.py:L326): `grid_norm.view(B, -1, 2)` 是归一化图像坐标，无 3D 信息
- [x] 文本编码器确认可用 (git.py:L719-749): BERT tokenizer + word_embeddings + multi-piece attention，功能完整
- [x] Attention mask 确认支持扩展 (git.py:L603-639): `get_attn_mask` 已处理 `text_embed` 的可选注入，新增 token 类型可复用此机制
- [x] `get_grid_feature` 的 `F.grid_sample` (git.py:L596) 使用 `grid_reference[:, :, :2]`，只取前 2 维，扩展到 3D 需要修改此函数

---

## 附加建议

1. **BEV 坐标 PE 是最值得先做的实验**: 工作量 0.5 天，风险极低，可以与 DINOv3 集成并行实施。如果 offset 指标改善，证明 3D 空间编码有价值。

2. **避免用 BERT 编码数字坐标**: BERT 的 tokenizer 对数字的处理是字符级的 ("10.5" → ["10", ".", "5"])，失去数值语义。用 MLP 或 sinusoidal positional encoding 编码坐标更合理。

3. **V2X 融合的数据问题**: nuScenes-mini 只有 323 张图，单车视角。V2X 需要多车数据 (OPV2V、DAIR-V2X 等数据集)。在当前数据上无法验证 V2X 效果。建议 V2X 方案设计先行，实验验证等切换到支持 V2X 的数据集后再做。

4. **concept_generation 的复用性**: 当前 `concept_generation` 将文本列表编码为 embedding (git.py:L719-749)。如果要用文本编码 3D 信息，应绕过此函数，直接用可学习的 embedding 层，避免 BERT tokenizer 的限制。
