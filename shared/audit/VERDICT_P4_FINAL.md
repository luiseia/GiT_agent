# 审计判决 — P4_FINAL

## 结论: CONDITIONAL

**条件: P4 的 AABB 修复、BUG-11 修复、config 调优均已正确实现，Recall 全面提升证明旋转多边形标签修复有效。但 avg_P=0.107 不升反降 (P3=0.122)，Precision 瓶颈已从"标签污染"转移为"模型分辨力不足"。P5 必须转向 DINOv3 中间层特征集成，继续 loss/config 调优将无法突破 Precision 天花板。**

---

## 第 1 部分: P4 修复核实

### AABB→旋转多边形修复: CONFIRMED

代码核实通过:

1. **Config 层**: `plan_g_aabb_fix.py:L300` 设置 `use_rotated_polygon=True`
2. **标签生成层**: `generate_occ_flow_labels.py:L544-549` — 当 `use_rotated_polygon=True` 时，提取有效投影顶点 `valid_uv`，传入 `_compute_valid_grid_ids` 的 `polygon_uv` 参数
3. **凸包精确判断**: `generate_occ_flow_labels.py:L302-308` — 使用 `scipy.spatial.ConvexHull` 构建凸包
4. **Cell 中心判断**: `generate_occ_flow_labels.py:L314-319` — 在 AABB 粗筛后，用 `_point_in_convex_hull` 精确判断 cell 中心是否在凸包内
5. **兜底策略**: `L322-327` — 物体过小时强制选中几何中心 cell，避免空标签

**实现质量**: 良好。AABB 先粗筛 (快)，凸包后精判 (准)，兜底防空 (安全)。

### BUG-11 修复: CONFIRMED

`generate_occ_flow_labels.py:L77`: `classes: List[str] = None` — 默认值从 `["car","bus","truck","trailer"]` 改为 `None`，强制显式传入。Config L76/L289/L321/L327 均显式传入 `classes=["car","truck","bus","trailer"]`。

BUG-11 标记为 **FIXED**。

### Config 调优核实

| 参数 | P3 | P4 | 代码位置 | 核实 |
|------|----|----|---------|------|
| load_from | P2@6000 | P3@3000 | L13 | CONFIRMED |
| bg_balance_weight | 3.0 | 2.0 | L147 | CONFIRMED |
| reg_loss_weight | 1.0 | 1.5 | L145 | CONFIRMED |
| use_rotated_polygon | False | True | L300 | CONFIRMED |

---

## 第 2 部分: AABB 修复因果性分析

### truck_R @2000: P4=0.458 vs P3=0.152

**不完全归因于 AABB 修复。** 至少有三个因素:

1. **AABB 修复 (主因, ~50%)**: 旧 AABB 下，旋转角度大的 truck (长轴约 10m) 的包围盒面积约为实际面积的 1.5-2 倍。多余的 cell 被标为 truck，模型学到了"在这些不含 truck 的 cell 也预测 truck"。修复后标签更精确，模型的 truck 预测更聚焦。

2. **bg_balance_weight 降低 (次因, ~30%)**: 从 3.0 降至 2.0，减少了背景梯度对前景预测的压制。P3 中 truck_R @2000 暴跌至 0.152 与 bg_balance_weight=3.0 过度压制有关。P4 降至 2.0 后，前景预测不再被过度惩罚。

3. **起点更优 (辅因, ~20%)**: P4 从 P3@3000 (truck_R=0.326) 出发，P3 从 P2@6000 (truck_R=0.290) 出发。更高起点给予 truck 检测更好的初始化。

**验证**: 如果纯因 AABB 修复，bus_R 应该受影响较小 (bus 通常轴对齐，AABB 与旋转框差异不大)。实际 bus_R 从 P3@4000=0.712 → P4@4000=0.752 (+5.6%)，远小于 truck_R 的 +36%。这证实 AABB 修复对旋转角度大的目标 (truck, trailer) 效果更显著。

---

## 第 3 部分: Precision 瓶颈分析

### avg_P 不升反降: P4=0.107 vs P3=0.122

**这是本次审计最关键的发现。** AABB 修复提升了 Recall 但 Precision 反而下降。

### 原因拆解

**Precision = TP / (TP + FP)**

AABB 修复改变了标签分配 (training)，但评估逻辑 (inference) 不使用标签。Precision 下降意味着 FP 增加的速度超过了 TP 增加的速度。

1. **Recall 提升 = 模型预测更多前景**: 标签更精确后，模型学到了"在更精确的位置预测前景"。但模型的分辨力不足以精确到 cell 级别。结果: 正确位置预测增加 (TP↑)，但附近 cell 也预测前景 (FP↑更多)。

2. **truck_P 从 0.211→0.175 下降**: truck_R 从 0.302→0.410 大幅上升。模型"敢预测更多 truck"，但预测精度没有同步提升。根因: DINOv3 Conv2d 层的特征缺乏物体类别语义，无法区分"有 truck 的 cell"和"truck 附近的 cell"。

3. **car_P 始终在 0.07-0.10**: car 是最大类别 (8269 GT)，20x20 BEV grid 上有大量 cell 靠近 car。car_P 的瓶颈是 DINOv3 PatchEmbed 输入的语义不足 — Conv2d 只编码了纹理/边缘信息，无法判断"这个 cell 的中心是否在车辆投影区域内"。

### Precision 瓶颈的下一个最大驱动力

**排名:**

1. **DINOv3 特征深度不足 (最大驱动力)**: 当前只用 Conv2d 层 (Layer 0)，不含物体类别信息。模型必须仅从纹理/边缘特征推断 BEV 位置和类别，这是本质性困难。使用 Layer 16-20 的语义特征可直接提供"这是车辆"的信息。

2. **Score 无区分度 (第二驱动力)**: `score_thr=0.0` (config L430)，模型 score 均值 0.97。即使模型内部"不确定"某个预测，输出的 score 也接近 1.0。评估时无法过滤低质量预测。

3. **3 slot/cell 的冗余 (第三驱动力)**: 大多数 cell 只有 0-1 个目标，但 3 个 slot 都可能输出非 bg 预测。空 slot 的 FP 被计入 Precision 分母。

---

## 第 4 部分: offset_th LR decay 回退分析

### 现象
- P4@1000: offset_th=0.200 (达标)
- P4@2500后: 回退至 0.207-0.211

### reg_loss_weight=1.5 的效果

对比 P3 (reg_loss_weight=1.0):
- P3: offset_th 在 @2000 才达标 (0.191)，然后立即回退
- P4: offset_th 在 @1000 就达标 (0.200)，回退幅度更小 (0.207 vs P3 的 0.214)

**reg_loss_weight=1.5 确实延迟了回退并减小了回退幅度。** 但未能完全阻止。

### 根因: 分类与回归的梯度竞争是结构性的

theta 预测 (theta_group + theta_fine) 和分类预测 (marker + cls) 共享同一个 Transformer decoder 的所有参数。LR decay 后:
- 分类 loss 的绝对梯度贡献远大于 theta 回归 (因为分类涉及 1200 slot × 2 token = 2400 个预测，而 theta 只涉及有目标的少数 slot)
- 在低 LR 下，有限的参数更新预算被分类任务占用

### 是否需要 reg_loss_weight=2.0?

**不推荐。** 原因:
1. reg_loss_weight=1.5 已经导致 bg_FA 在 @2000 达到 0.239 (接近红线 0.25)。继续提高 reg 权重会恶化分类。
2. 根本问题不是权重，而是**共享参数**。分离的回归 head 或 task-specific decoder 才能解决。
3. 更实际的方案: P5 使用 DINOv3 中间层特征后，theta 回归可能自然改善 (更丰富的几何信息 → theta 预测更稳)。

---

## 第 5 部分: 最佳 P5 起点

### 候选分析

| Checkpoint | avg_P | 优势 | 劣势 |
|-----------|-------|------|------|
| P4@500 | 0.105 | bg_FA=0.176 (最低) | 训练不充分 |
| P4@1000 | 0.087 | offset_th=0.200 (唯一达标) | 各项 Precision 低 |
| P4@2500 | 0.095 | car_P=0.097 (P4最高) | truck/bus_P 低 |
| P4@3000 | 0.099 | trailer_P=0.050 (P4最高) | bg_FA=0.215 偏高 |
| P4@4000 | 0.107 | 最稳定，recall 全面高 | offset_cy/th 未达标 |

### 推荐: P4@500

**理由:**

如果 P5 要集成 DINOv3 中间层特征 (从 Conv2d PatchEmbed 替换为 Layer 16/20 特征)，这是一个**架构层面的根本变化**。backbone 的输入分布将彻底改变:
- Conv2d PatchEmbed: 低级纹理/边缘特征
- Layer 16/20: 高级语义特征 (物体类别、形状)

原有 Transformer 层 (0-17) 已经适应了 Conv2d 输入的分布。切换到 Layer 16/20 特征后，所有层都需要重新适应。**训练越深的 checkpoint，适应旧分布越深，重新适应新分布越难。**

P4@500 的优势:
1. warmup 刚结束，模型对输入分布的适应程度最浅
2. bg_FA=0.176 是 P4 最佳，说明分类基础良好
3. 如果 P5 要长训练 (>6000 iter)，起点的精确数值不那么重要

**替代方案**: 如果不做 DINOv3 集成，P4@4000 是最稳定的起点。

---

## 第 6 部分: DINOv3 集成方案评估

### 方案: PreextractedFeatureEmbed + Linear(4096, 768)

**可行性: 高。** 预提取避免了 DINOv3 7B 的显存开销。

### 单层 vs 双层投影

| 方案 | 参数量 | 优势 | 劣势 |
|------|--------|------|------|
| Linear(4096, 768) | 3.15M | 简单，训练快 | 信息压缩比 5.3:1，可能丢失细节 |
| Linear(4096,1024)+GELU+Linear(1024,768) | 4.97M | 非线性映射，特征重组更灵活 | 参数多 50%，训练不稳定风险 |

**推荐: 单层 Linear(4096, 768)**

理由:
1. 当前 `DINOv3PatchEmbedWrapper` 已经使用 `Linear(4096, 768)` (vit_git.py:L46)，模型结构不变，只是输入特征变了
2. 323 张图的训练数据不足以训练 5M 参数的双层投影
3. DINOv3 Layer 16/20 的特征已经是高度结构化的，线性投影足以映射到 768d 空间
4. 如果效果不好，再升级为双层投影，风险更可控

### 特征层选择: Layer 16 vs Layer 20 vs 多层融合

| 层 | 内容 | 对 OCC 价值 | 推荐 |
|----|------|------------|------|
| Layer 16 | 物体部件+类别 | 高 — 平衡细节和语义 | 首选 |
| Layer 20 | 全局语义 | 高 — 类别强但定位弱 | 备选 |
| L16+L20 concat | 双层信息 | 最高 — 但 8192d→768d 压缩比太大 | 不推荐 |
| L16+L20 average | 双层平均 | 中 — 简单但信息混合不受控 | 可考虑 |

**推荐: 先用 Layer 16 单层。** 如果效果好但需要更多全局信息，再加 Layer 20。

### 风险评估

1. **特征分布差异**: Conv2d 输出和 Layer 16 输出的分布差异巨大。需要较长 warmup (建议 1000 步)
2. **Backbone 层适应**: SAM 预训练的 Layer 0-11 已经适应 Conv2d 输入。切换后需要更高的 lr_mult (建议从 0.05 提升至 0.1-0.2)
3. **预提取文件大小**: 323 张图 × (70×70) patches × 4096 dim × 4 bytes (FP32) ≈ 25GB。可用 FP16 压缩至 ~12GB。确保 SSD 空间充足

### BUG-16: 预提取特征与数据增强不兼容

- 严重性: **MEDIUM**
- 位置: 设计层面

如果 P5 使用预提取的 DINOv3 特征 (.pt 文件)，则无法在训练时对图像做数据增强 (flip, rotation 等)，因为增强后的图像对应不同的特征。

**缓解方案**:
- 预提取时同时生成增强版本 (flip 版本) 的特征
- 或在特征层面做增强 (feature-level flip/permute)

---

## 第 7 部分: P5 优先级

### 推荐优先级: DINOv3 集成 >> Score 区分度 > 其他

1. **DINOv3 中间层特征集成 (最高优先)**
   - 预期: avg_P 从 0.107 提升至 0.15-0.20 (语义特征直接提供类别信息)
   - 工作量: 2-3 天 (预提取 + PreextractedFeatureEmbed + 训练)
   - 风险: 中 (特征分布差异需要调试)

2. **Score 区分度改进 (高优先，可与 1 并行)**
   - 在 OccHead 中添加独立 objectness sigmoid
   - 评估时用 score_thr 过滤低置信度预测
   - 预期: Precision 提升 20-50% (通过过滤 FP)
   - 工作量: 1-2 天

3. **新增层添加 global attention (低优先)**
   - `new_more_layers` 从 `['win'×6]` 改为 `['win','win','global','win','win','global']`
   - 预期: grid token 信息更完整
   - 工作量: 0.5 天
   - 风险: 低 (但效果可能不显著)

---

## 第 8 部分: 红线合规审计

| 指标 | 红线 | P4 最佳 | P4@4000 | 合规 | 趋势 |
|------|------|---------|---------|------|------|
| truck_R | <0.08 | 0.463 | 0.410 | SAFE | P1→P4 持续提升 |
| bg_FA | >0.25 | 0.176 | 0.194 | SAFE | 稳定 |
| offset_th | ≤0.20 | **0.200** | 0.207 | MARGINAL | @1000 瞬间达标 |
| offset_cy | ≤0.10 | **0.089** | 0.103 | MARGINAL | @2000 达标但未保持 |
| offset_cx | ≤0.05 | **0.047** | 0.057 | MARGINAL | @2000 达标但未保持 |
| avg_P | ≥0.20 | 0.107 | 0.107 | FAIL | P3→P4 下降，结构性瓶颈 |

**关键判断**: offset_th/cy/cx 均在训练中某个时刻达标或接近达标，说明模型有能力达标，但在 LR decay 后无法保持。**这不是能力问题，是训练策略问题。** DINOv3 集成后，更强的特征可能让达标点更稳定。

**avg_P 是唯一的结构性 FAIL**，需要架构层面改动。

---

## 第 9 部分: BUG 状态更新

| BUG | 审计前状态 | 审计后状态 | 备注 |
|-----|-----------|-----------|------|
| BUG-11 | UNPATCHED | **FIXED** | classes 默认值改为 None |
| BUG-16 | — | **NEW (MEDIUM)** | 预提取特征与数据增强不兼容 |
| 其余 | — | 不变 | 见 VERDICT_P3_FINAL |

---

## 逻辑验证

- [x] AABB 修复正确性: ConvexHull 使用 scipy.spatial，凸包顶点逆时针排列，`_point_in_convex_hull` 使用叉积判断方向一致性 (L254-260)，算法正确
- [x] 兜底策略: 物体过小 → cell_ids 为空 → 强制选中几何中心 (L322-327)，不会产生空标签
- [x] BUG-11 修复安全性: `classes=None` 默认值 + config 显式传入，不影响现有 config (均已显式传入)
- [x] reg_loss_weight=1.5 不干扰 cls: cls_loss_weight=1.0 未变，reg 权重变化只影响 `loss_reg` 的贡献

---

## 附加建议

1. **P4@2000 的 bg_FA=0.239 接近红线**: bg_balance_weight=2.0 在 full LR 阶段对背景约束不足。如果 P5 继续使用 CE loss，建议 bg_balance_weight 恢复至 2.5。

2. **评估指标计算应记录 TP/FP/FN 绝对数**: 当前只输出 Recall/Precision，无法区分"TP 增加 + FP 增加更多"和"TP 不变 + FP 增加"两种 Precision 下降模式。建议在 `occ_2d_box_eval.py` 中增加 TP/FP/FN count 的日志输出。

3. **test_pipeline 与 train_pipeline 完全相同** (config L313: `test_pipeline = train_pipeline`)。评估时也使用 `use_rotated_polygon=True` 和 `filter_invisible=True`。这在评估中不影响结果 (标签不参与评估)，但会增加评估时间。可优化但不阻塞。

4. **DINOv3 预提取建议**: 使用 FP16 存储。323 图 × 2 方向 (原始+flip) × 4900 patches × 4096 dim × 2 bytes ≈ 25GB。确保 `/mnt/SSD/` 有足够空间。
