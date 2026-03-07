# 审计判决 — ARCH_REVIEW

## 结论: CONDITIONAL

**条件: BUG-2 标记为 FIXED 实为半修状态 (cls 路径仍有 BUG-8), BUG-9 仅在 P2 config 修复, BUG-11 默认类别顺序仍有地雷。修复这些后方可认为代码库处于健康状态。架构层面有重大优化空间但不阻塞当前训练。**

---

## 第 1 部分: ViT 输入审查

### Q/K/V 构成

单一线性层生成 q, k, v:
```python
# vit_git.py:L334
self.qkv = nn.Linear(embed_dims, embed_dims * 3, bias=qkv_bias)

# vit_git.py:L354
q, k, v = qkv.reshape(3, B * self.num_heads, N, -1).unbind(0)
```

**q, k, v 全部来自同一输入 x 的线性投影。** x 是 image_patch 和 grid_token 的拼接:
```python
# vit_git.py:L485
x = torch.cat([flatten_image_patch, flatten_grid_token], dim=1)
```

### 三层视野分析

| 层级 | 实现方式 | 输入来源 | 代码位置 |
|------|---------|---------|---------|
| **Grid** | 4x4 grid tokens per window, 通过 `grid_window_partition` 分配到对应窗口 | DINOv3 投影特征 (间接) | vit_git.py:L476-477 |
| **Window** | 14x14 patches 的窗口注意力 (`window_size=14`) | DINOv3 patch embeddings → 768d | vit_git.py:L474-475 |
| **Global** | 全图注意力 (`window_size=0`), Layer [2,5,8,11] | 同上 | vit_git.py:L829-830 |

**结论: 三层视野全部来自 DINOv3 PatchEmbed 的单一投影。** 没有任何层使用其他特征来源。Grid token 是可学习参数，通过注意力机制间接吸收 image_patch 信息，但初始化时不含 DINOv3 语义。

### 详细数据流追踪: flatten_image_patch 与 flatten_grid_token

拼接发生在 `vit_git.py:L485`:
```python
x = torch.cat([flatten_image_patch, flatten_grid_token], dim=1)
```

#### flatten_image_patch 来源

完整链路:

1. **DINOv3 Conv2d PatchEmbed** (`git.py:L239`):
   ```python
   patch_embed, patch_resolution = self.backbone.patch_embed(batch_inputs)
   # batch_inputs: 原始图像 (B, 3, H, W)
   # patch_embed: (B, N, 768) — DINOv3 的 Conv2d(3→4096) + Linear(4096→768)
   ```

2. **加入位置编码** (`git.py:L250`):
   ```python
   patch_embed = patch_embed + img_pos_embed
   ```

3. **进入 ViT 层循环** (`git.py:L508`):
   ```python
   patch_embed = layer(patch_embed, grid_token, ...)
   ```
   每层 TransformerLayer 内部 (`vit_git.py:L469-485`):
   - `flatten_image_patch` 直接来自上一层输出的 `patch_embed`
   - 经过 window_partition 展平后参与注意力计算

**结论: flatten_image_patch 100% 来自 DINOv3 Conv2d PatchEmbed → Linear(4096,768) → pos_embed，然后逐层通过 Transformer 更新。**

#### flatten_grid_token 来源

完整链路:

1. **初始化 — 可学习 task_embedding** (`git.py:L325-326`):
   ```python
   grid_start_embed = self.task_embedding[self.mode_id][None, None, :].repeat(B, num_grids, 1)
   # task_embedding: nn.Parameter, 随机初始化, 与 DINOv3 无关
   ```

2. **赋值** (`git.py:L449`):
   ```python
   grid_token = grid_start_embed  # (B, num_grids, 768)
   ```

3. **每层更新 — 从 patch_embed 空间采样** (`git.py:L508-510`):
   ```python
   for layer in self.backbone.layers:
       grid_feature = self.get_grid_feature(memory, grid_position)  # L509
       # memory = patch_embed (来自 DINOv3)
       # get_grid_feature 内部使用 F.grid_sample (git.py:L591-592):
       #   grid_feature = F.grid_sample(memory_2d, grid_pos_norm, ...)
       grid_token = torch.cat([grid_feature, grid_token], dim=2)  # L510 拼接
       # 然后送入 Transformer layer, grid_token 通过注意力被更新
   ```

**结论: flatten_grid_token 的初始值是随机可学习参数 (与 DINOv3 无关)，但在每一层通过 `F.grid_sample` 从 DINOv3 patch_embed 中空间采样特征并拼接，间接获取 DINOv3 信息。**

#### 关键区别总结

| 属性 | flatten_image_patch | flatten_grid_token |
|------|--------------------|--------------------|
| **初始来源** | DINOv3 Conv2d PatchEmbed (直接) | task_embedding (随机可学习参数) |
| **DINOv3 关系** | 直接投影 | 间接 (每层 F.grid_sample 从 patch_embed 采样) |
| **位置编码** | img_pos_embed (直接加) | grid_position (采样坐标) |
| **语义丰富度 (初始)** | 中 (Conv2d 级别的空间特征) | 零 (随机初始化) |
| **逐层更新** | Transformer self-attention | Transformer attention + F.grid_sample 注入 |

**BUG-14: Grid token 与 image patch 的信息冗余**

- 严重性: **MEDIUM**
- 位置: `GiT/mmdet/models/backbones/vit_git.py:L485`

Grid token 和 image patch 拼接后通过同一个 qkv 投影，在窗口注意力中互相交互。但 grid token 是随机初始化的可学习参数，在训练初期不含有意义的信息。18 层 Transformer 中只有 4 层 (L2,5,8,11) 是全局注意力，其余 14 层的 grid token 只能看到局部窗口内的 image patch。

**影响:** Grid token 可能需要大量训练步数才能学到有用的空间表征，而 image patch 已经从 DINOv3+SAM 预训练中获得了丰富的特征。这导致训练效率低下。

---

## 第 2 部分: DINOv3 特征层选择

### 当前使用方式

**只使用了 DINOv3 的 PatchEmbed (Conv2d) 层。**

```python
# vit_git.py:L40-46
self.dinov3_patch_embed = DINOv3PatchEmbed(
    img_size=img_size,
    patch_size=patch_size,
    in_chans=in_chans,
    embed_dim=dinov3_embed_dim,      # 4096
    flatten_embedding=True,
)
# 然后 Linear(4096, 768) 投影到 ViT-Base 的 embed_dims
```

**这是 DINOv3 的第 0 层** — 原始像素到 patch embedding 的 Conv2d 映射。DINOv3 7B 模型包含 32+ 个 Transformer 层的深层语义特征，但当前实现完全没有使用任何中间层特征。

### BUG-15: DINOv3 特征严重浪费

- 严重性: **HIGH** (架构层面，非 bug)
- 位置: `GiT/mmdet/models/backbones/vit_git.py:L28-87`

DINOv3 7B 在 LVD-1689M 数据上预训练，其中间层特征包含丰富的语义信息:
- **低层 (Layer 1-8)**: 边缘、纹理、局部结构
- **中层 (Layer 9-16)**: 物体部件、形状
- **高层 (Layer 17-32)**: 物体类别、场景语义

当前只用 Conv2d patch embedding (4096d → 768d)，等于只用了 DINOv3 学到的"如何切patch"的知识。

**合理性判断:** 不合理。选择只用 Conv2d 层可能是工程简便性考虑（避免运行完整 DINOv3 前向传播），但代价是丢失了 DINOv3 最核心的能力 — 深层语义理解。

### 不同层特征对 OCC 任务的价值

| 特征层 | 内容 | 对 BEV OCC 的价值 |
|--------|------|------------------|
| PatchEmbed (当前) | 像素到 patch 的线性投影 | 低 — 只是空间下采样 |
| Layer 8-12 (中层) | 物体部件和形状 | 高 — 车辆几何形状对 BEV 旋转预测关键 |
| Layer 16-24 (中高层) | 物体类别和空间关系 | 极高 — 类别判断和深度估计依赖语义 |
| Layer 28-32 (最高层) | 全局场景理解 | 高 — 但过于抽象，可能丢失定位细节 |

**推荐:** 使用 DINOv3 Layer 16-20 的特征作为 GiT 的输入，或多层融合。

---

## 第 3 部分: 架构层面性能提升方案

### 方案 A: 多层 DINOv3 特征提取

**描述:** 运行 DINOv3 前向传播到中间层，提取特征图作为 GiT 输入，替代当前只用 Conv2d PatchEmbed。

**实现:**
1. 加载 DINOv3 ViT-7B 模型
2. 前向传播到目标层 (如 Layer 16)
3. 输出 (B, N, 4096) 的中间特征
4. Linear(4096, 768) 投影给 GiT

**预估工作量:** 2-3 天
- 修改 DINOv3PatchEmbedWrapper 为 DINOv3FeatureExtractor
- 冻结 DINOv3 参数 (不需要训练)
- 调整显存策略 (7B 模型约 14GB FP16)

**风险:**
- 显存压力: DINOv3 7B FP16 需 ~14GB，4 GPU 可行但需优化
- 推理延迟增加约 50%
- 收益不确定: 需要实验验证最佳提取层

**预期收益:** 显著。DINOv3 中层特征已包含物体类别和形状信息，可直接提升分类精度和 BEV 位置估计。

### 方案 B: 异构 Q/K/V — Grid Token 用不同来源

**描述:** 当前 grid_token 和 image_patch 共享 qkv 投影。可以让 grid_token 作为 Query，image_patch 作为 Key/Value (交叉注意力)，类似 DETR 的 decoder。

**实现:**
1. 在 TransformerLayer 中增加 cross-attention 模块
2. Grid token Q 从可学习参数生成
3. Image patch K/V 从 DINOv3 特征生成
4. 新增层 12-17 使用 cross-attention 替代 self-attention

**预估工作量:** 3-5 天
- 需要重写 TransformerLayer.forward()
- 需要新的预训练策略 (Layer 12-17 本来就是随机初始化)

**风险:** 中等。改动较大，但 Layer 12-17 本来就没有预训练权重，不存在权重兼容问题。

**预期收益:** 中等。让 grid token 更高效地从 image patch 中提取空间信息。

### 方案 C: 多尺度特征融合 (FPN-like)

**描述:** 当前只有单一尺度 (1120→70x70 patches)。添加 FPN-style 的多尺度特征融合。

**实现:**
1. 从不同层 (如 Layer 6, 12, 17) 提取特征
2. 上采样/下采样对齐
3. 逐层融合

**预估工作量:** 4-6 天
**风险:** 高。需要大量架构改动，与 GiT 的 grid/window 机制交互复杂。
**预期收益:** 对小目标 (远处车辆) 提升显著。

### 推荐优先级: A > B > C

方案 A 投入产出比最高，且与当前架构改动最小。

---

## 第 4 部分: BUG 状态核实

| BUG | 声称状态 | 实际状态 | 核实依据 |
|-----|---------|---------|---------|
| **BUG-1** | FIXED | **FIXED** | `git_occ_head.py:L1006,L1015`: theta_fine 调用 `periodic=False`; L711-716 正确分支 |
| **BUG-2** | FIXED | **PARTIALLY FIXED** | Marker loss bg 正确 (L862-865), 但 cls loss bg 仍缺失 (=BUG-8)。BUG-2 的修复不完整 |
| **BUG-3** | FIXED | **FIXED** | Score 链完整: L1090 创建 pred_scores → L1170 记录 → L1294 输出 grid_scores → occ_2d_box_eval.py:L74 读取 → L126 过滤 |
| **BUG-8** | UNPATCHED | **UNPATCHED** | cls loss per-class balance 循环 `range(self.num_classes)` 跳过 bg (L886-896). 见 VERDICT_P2_FINAL |
| **BUG-9** | UNPATCHED | **FIXED (仅 P2 config)** | plan_e_bug9_fix.py:L371 `max_norm=10.0`. 但 plan_a/b/c/d 仍为 0.5 |
| **BUG-10** | UNPATCHED | **UNPATCHED** | plan_e:L13 `resume=False`, L344-352 无 warmup |
| **BUG-11** | UNPATCHED | **UNPATCHED** | generate_occ_flow_labels.py:L77 默认 `["car","bus","truck","trailer"]` vs config L75 `["car","truck","bus","trailer"]` — 顺序不一致 |
| **BUG-12** | URGENT | **FIXED** | occ_2d_box_eval.py:L142-163 cell 内 class-based 匹配替代了 slot 对齐 |

**关键发现: BUG-2 被标记为 FIXED 但实际只修了一半。** Marker loss 的 bg_balance_weight 正确实现，但 cls loss 完全遗漏了背景 (即 BUG-8)。BUG-2 和 BUG-8 本质上是同一个问题的两面——Per-class 背景梯度压制在 marker loss 中修复了，在 cls loss 中没有。

---

## 第 5 部分: 历史分析方案核实

### 分析 1: Grid 分配逻辑 (AABB → 旋转多边形)

**状态: 未实现。**

当前仍使用 AABB (轴对齐包围盒):
```python
# generate_occ_flow_labels.py:L507
cell_ids, center_uv, _ = self._compute_valid_grid_ids(min_u, max_u, min_v, max_v, cur_w, cur_h)
```
参数 `min_u, max_u, min_v, max_v` 是 3D 投影角点的 AABB，非旋转多边形。对大角度旋转的车辆 (如 45 度)，AABB 会覆盖大量不包含车辆的 cell，导致假阳性标签。

### 分析 2: 2D-3D 视觉对齐 (2D 投影框权重调制)

**状态: 未实现。**

没有基于 2D 投影面积或 IoU 的权重调制。当前只有 center/around 二元权重和 IBW (Instance Balance Weight)。

### 分析 3: Center/Around 采样策略

**状态: 已实现。**

- 标签生成: `center_cell_id` 计算 (generate_occ_flow_labels.py:L517-527)
- 权重应用: `center_weight=2.0, around_weight=0.5` (git_occ_head.py:L509-511, config L147-148)
- 完整链路: labels → head → loss，功能正常。

### 分析 4: Token 与类别优化 (合并 marker+class)

**状态: 未实现。**

当前 10-token slot 结构: `[marker, class, gx, gy, dx, dy, w, h, theta_group, theta_fine]`
- marker (pos 0): NEAR/MID/FAR/END
- class (pos 1): car/truck/bus/trailer/bg

合并方案 (marker+class → 单个 token) 未实现。当前结构中 marker 和 class 是独立预测的，存在不一致风险 (如 marker=NEAR 但 class=bg)。

---

## 逻辑验证

- [x] 梯度守恒: DINOv3 PatchEmbed 的 `lr_mult=0.0` (config L375) 确保冻结; proj_layer 的 `lr_mult=1.0` (L376) 确保可训练。梯度不会回传到 DINOv3 Conv2d
- [x] 边界条件: window_partition (L89) 有 padding 处理; grid_window_partition 有 scatter_indices 保证反向恢复
- [x] 数值稳定性: Attention 缩放 `self.scale = head_embed_dims**-0.5` (L332) 防止 dot-product 溢出

---

## 附加建议

1. **BUG 状态表需要修正**: BUG-2 应标记为 PARTIALLY_FIXED, BUG-9 应标记为 FIXED_P2_ONLY, BUG-12 应从 URGENT 改为 FIXED

2. **BUG-11 是一个静默地雷**: 如果任何新 config 忘记显式传入 classes 参数，默认值 `["car","bus","truck","trailer"]` 会导致 truck 和 bus 的标签互换。修复方案: 删除默认值，强制显式传入。位置: `generate_occ_flow_labels.py:L77`

3. **DINOv3 利用率极低是当前架构的最大制约因素**: 花费 14GB 显存加载 7B 模型却只用一个 Conv2d 层，投入产出极不合理。如果显存限制不允许运行完整 DINOv3，至少应离线预提取中间层特征存为 .pt 文件，训练时直接加载，绕过显存问题

4. **新增层 (12-17) 全部是 window attention**: config L229 `new_more_layers=['win','win','win','win','win','win']`。这意味着新增层完全没有全局感受野，grid token 在这 6 层中只能看到局部窗口。考虑将至少 1-2 层改为 global attention: `['win','win','global','win','win','global']`
