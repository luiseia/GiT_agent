# CEO 调查报告: 决策矩阵阈值 + DINOv3 解冻策略
> 时间: 2026-03-09 ~16:40
> 作者: Conductor (Cycle #138)
> 状态: 基于代码审查 + 实验数据分析

---

## 问题 1: @10000 决策矩阵阈值是否太低?

### 1.1 当前阈值回顾

| peak_car_P | 行动 |
|-----------|------|
| > 0.10 | 确认方向, 继续到 @17000 |
| 0.08-0.10 | 继续, @12000 再评估 |
| < 0.08 | 必须调参 |

### 1.2 car_P 指标本质分析

我们的 car_P **不是标准 nuScenes mAP**。关键差异:

| | 标准 nuScenes mAP | 我们的 car_P |
|--|---|---|
| 评估方式 | IoU 匹配 3D box → AP 曲线 | per-cell BEV 占据网格 (200×200) |
| 正样本率 | ~20 cars/frame, 每个 1 box | ~720 cells/frame (40000 中 1.8%) |
| False Positive 代价 | 1 box | 1 cell (极细粒度) |
| 典型值 | BEVFormer ~0.42, PETR ~0.36 | **与 box mAP 不可比** |

**因此不能用 BEVFormer 的 0.42 来衡量我们的 car_P 应该是多少。** 这是两个完全不同的指标。

### 1.3 当前 car_P=0.09 意味着什么?

以 @6000 最佳点 (car_P=0.090, car_R=0.627) 估算:
- **TP ≈ 451 cells** (0.627 × ~720 positive cells)
- **FP ≈ 4561 cells** (451/0.090 - 451)
- 模型预测 ~5012 个 car cells, 仅 9% 正确

这确实偏低。一个成熟模型应该:
- car_P > 0.30, car_R > 0.50 → FP ≈ 840, 更合理的 FP/TP 比

### 1.4 CEO 的直觉正确吗?

**是的, 0.10 作为标准确实太低。** 但需要区分:

**A) 作为 @10000 (25% 训练) 的早期 checkpoint 阈值:**
- 0.08-0.10 **在训练早期是合理的**, 因为:
  - LR 还没 decay (第一次 @17000)
  - 类间振荡导致 precision 波动 ±30%
  - 模型还在探索阶段

**B) 作为最终性能的预期:**
- 如果 @40000 最终 car_P 只有 0.10, **那确实说明架构有根本问题**

### 1.5 car_P 增长率分析

| Eval | peak_car_P | 相对 @2000 增幅 |
|------|-----------|----------------|
| @2000 | 0.079 | baseline |
| @4000 | 0.078 | -1% |
| @6000 | 0.090 | +14% |
| @8000 | 0.060 | (振荡低点) |

**增长率确实很慢。** 4000 iter (1000 opt steps) 仅提升 ~14%。如果这个趋势持续:
- @17000 (pre-decay): 估计 peak ~0.10-0.12
- @25000 (post-first-decay): 估计 peak ~0.13-0.18 (decay 带来非线性提升)
- @40000 (最终): 估计 peak ~0.15-0.25

### 1.6 修正后决策矩阵

**保留 @10000 阈值不变** (早期训练合理), 但新增 **分阶段目标**:

| 阶段 | 训练进度 | peak_car_P 预期 | 低于此值的行动 |
|------|---------|----------------|---------------|
| @10000 | 25% | > 0.08 | 调参/deep supervision |
| **@17000 (新)** | **42%, LR decay 后** | **> 0.15** | **架构干预 (LoRA/解冻)** |
| **@25000 (新)** | **62%, 第二次 decay 后** | **> 0.20** | **可能需要重新设计** |
| **@40000 (最终)** | **100%** | **> 0.25** | **架构需要根本改变** |

**关键分界点: @17000 LR decay 后。** 如果 decay 没有带来显著 precision 提升 (peak 从 ~0.10 跳到 ~0.15+), 说明不是优化问题而是架构问题。

### 1.7 结论

1. **@10000 当前阈值 0.08-0.10 作为早期 checkpoint 是合理的** — 不需要改
2. **CEO 正确的直觉是: 我们需要更严格的后续阈值** — 已补充 @17000/@25000/@40000 目标
3. **如果 @10000 时 car_P 仍然只有 0.10, 答案是"可能还在收敛, 但需要关注"** — 真正的判断点在 @17000
4. **如果 @17000 后 peak_car_P < 0.15 → 这是架构问题信号**, 需要立即干预

---

## 问题 2: DINOv3 解冻策略

### 2a. 部分解冻可行性

#### ★★ 重大发现: BUG-48 — `unfreeze_last_n` 参数完全无效!

审查代码后发现 **一个严重的设计缺陷**:

**当前代码** (`vit_git.py:L151-159`):
```python
# Optionally unfreeze last N layers
if unfreeze_last_n > 0:
    total_layers = len(self.dinov3.blocks)  # = 40
    for i in range(total_layers - unfreeze_last_n, total_layers):
        # 解冻 blocks[38], blocks[39], ...
        for param in self.dinov3.blocks[i].parameters():
            param.requires_grad = True
```

**DINOv3 特征提取** (`dinov3/models/vision_transformer.py:L270-284`):
```python
def _get_intermediate_layers_not_chunked(self, x, n=1):
    blocks_to_take = [16]  # n=[16]
    for i, blk in enumerate(self.blocks):  # 遍历所有 40 个 block
        x = blk(x, rope_sincos)
        if i in blocks_to_take:  # 只在 i==16 时保存
            output.append(x)
    return output
```

**问题链**:
1. 我们提取 **layer 16** 的输出
2. Loss 的梯度只流经 **blocks 0-16** (因为只有 block 16 的输出被用于后续计算)
3. `unfreeze_last_n` 解冻的是 **blocks 38-39** (模型末端)
4. Blocks 17-39 的参数 **对 loss 没有梯度贡献** — 即使解冻也不会被更新!
5. **`unfreeze_last_n` 参数在我们的使用场景下完全无效**

**额外发现: 计算浪费**
- 循环遍历所有 40 个 block, 但只需要 block 0-16 (17 个)
- **Blocks 17-39 (23 个) 的前向计算完全浪费** — ~58% 的 DINOv3 计算被白白消耗
- 这不影响正确性, 但浪费了 ~58% 的 DINOv3 前向时间

#### 正确的部分解冻实现

要正确解冻, 必须解冻 **extraction point 附近的 blocks** (block 15, 16 等):

```python
# 正确做法: 解冻 extraction point 前的 N 个 blocks
if unfreeze_near_extraction > 0:
    for i in range(layer_idx, layer_idx - unfreeze_near_extraction, -1):
        if i >= 0:
            for param in self.dinov3.blocks[i].parameters():
                param.requires_grad = True
```

#### 解冻 1 层 vs 2 层的 VRAM 估算

DINOv3 ViT-7B 每个 block 参数量:
- Attention (Q/K/V/O): 4 × 4096 × 4096 = **67.1M**
- FFN (ratio=3): 4096 × 12288 + 12288 × 4096 = **100.7M**
- LayerNorms: ~16K
- **总计: ~168M params/block**

| 方案 | 解冻参数 | 显存增量 (梯度+优化器) | 预计总显存 | A6000 可行? |
|------|---------|---------------------|-----------|-----------|
| 当前 frozen | 0 | 0 | ~37 GB | ✅ |
| 解冻 1 block (block 16) | ~168M | ~2-3 GB | ~39-40 GB | ✅ 安全 |
| 解冻 2 blocks (15-16) | ~336M | ~4-6 GB | ~41-43 GB | ⚠️ 紧张 |
| 解冻 3 blocks (14-16) | ~504M | ~6-9 GB | ~43-46 GB | ❌ 风险 |

**显存增量计算**:
- 梯度存储: 168M × 2 bytes (fp16) = ~336 MB
- 优化器状态 (AdamW): 168M × 4 bytes × 2 (momentum + variance) = ~1.34 GB
- 激活存储 (for backward): ~1-2 GB (取决于 batch size)
- **单 block 总增量: ~2-3 GB**

**结论: 解冻 1 个 block (block 16) 是安全的, 2 个紧张但可能可行。** 但需要修复 BUG-48 才能使解冻真正生效。

#### Full nuScenes 数据量下特征漂移风险

- Mini: 3k 样本, 高漂移风险 (数据不足以约束)
- **Full: 28k 样本, 漂移风险显著降低** (~10× 数据约束)
- Plan M 在 Mini 上 unfreeze last-2 层导致漂移, 但:
  1. 那是在 Mini 数据上 (不足)
  2. 解冻的是 block 38-39 (无梯度, BUG-48! 实际可能是 grad 泄漏导致的意外更新)
  3. Full nuScenes 数据量足以支持 1-2 block 微调

### 2b. Layer 16 选择

#### 选择依据

**Layer 16 是经验判断, 非实验验证。** 依据:
- DINOv2 论文中, ViT-L (24 layers) 常用 layer 11-12 (~50% depth) 做 dense prediction
- 类比到 40 层: 50% ≈ layer 20, 40% ≈ layer 16
- 选择偏保守 (浅层), 原因可能是: 浅层特征更通用, 深层可能过于 task-specific

#### Layer 16 (40% depth) 是否合适?

**可能偏浅。** 分析:

| 深度 | DINOv3 层 | 特征特性 | 适合任务 |
|------|----------|---------|---------|
| 20-30% | 8-12 | 低级: 边缘、纹理 | 重建、超分 |
| **40%** | **16 (当前)** | **中级: 部件、局部结构** | **可能不够语义** |
| 60-70% | 24-28 | 高级: 语义、物体级 | 检测、分割 (推荐) |
| 80%+ | 32+ | 抽象: 类别、关系 | 分类 |

**BEV 占据预测需要:**
1. 物体识别 (car/truck/bus 区分) → 需要高级语义特征 (60%+ depth)
2. 精确空间定位 → 需要中级空间特征 (40-60% depth)
3. 朝向估计 → 需要物体级结构特征 (50-70% depth)

**推测: Layer 24 (60%) 或 Layer 28 (70%) 可能显著优于 Layer 16。**

如果 Layer 16 选错了:
- 模型获得的语义信息不足 → car_P precision 天花板被压低
- 所有后续实验的绝对数值被拉低, 但 **趋势和对比仍然有效** (因为都在同一 layer 下)
- **不影响已有结论的有效性**, 但可能让我们低估了架构潜力

#### 快速验证方案

**方案 A: 多层特征质量对比 (推荐, ~2h)**
```
Layer candidates: [12, 16, 20, 24, 28]
方法: 修改 config 的 online_dinov3_layer_idx, 各跑 2000 iter
比较: car_P@2000 在不同 layer 下的值
```

**方案 B: 线性探测 (更快, ~30min)**
```
用训练好的 @10000 checkpoint 的 DINOv3
对 5 个不同 layer 提取特征
跑 linear probe: 能否区分前景/背景 + 分类
```

**方案 C: 特征统计 (最快, ~10min, 但不够可靠)**
```
提取一个 batch 在不同 layer 的特征
计算: 类间方差/类内方差比 (Fisher criterion)
```

**建议: 先做方案 C 快速筛选, 然后对 top 2-3 candidates 做方案 A。**

### 2c. LoRA vs 部分解冻

| | LoRA (rank=16) | 解冻 1 block | 解冻 2 blocks |
|--|---------------|-------------|-------------|
| 额外参数 | ~9-12M | ~168M | ~336M |
| 显存增量 | ~1-2 GB | ~2-3 GB | ~4-6 GB |
| 灵活性 | 可选择应用到哪些层 | 只能解冻整个 block | 只能解冻整个 block |
| 漂移风险 | 低 (低秩约束) | 中 | 高 |
| 表达能力 | 有限 (rank=16 子空间) | 完整 (全参数) | 完整 |
| 实现复杂度 | 需要修改模型 | 修 BUG-48 后改 1 行 config | 同上 |

**LoRA 参数估算** (rank=16, 应用到 layers 8-16 的 Q/K/V/O):
- 每层每矩阵: (4096 × 16 + 16 × 4096) × 2 = ~262K
- Q/K/V/O × 9 layers = 4 × 9 × 262K = ~9.4M params
- 显存: 模型 ~38 MB + 梯度 ~38 MB + 优化器 ~150 MB + 激活 ~0.5-1 GB ≈ ~1-2 GB

**能否叠加?**
- 技术上可以: LoRA + 解冻 block 16 → LoRA 微调 blocks 8-15, 解冻 block 16 全参数
- 但需要分开验证, 防止过拟合或训练不稳定
- **建议不叠加**, 而是二选一:
  - 数据充足 (Full nuScenes 28k) → **解冻 1 block** (更简单, 表达能力更强)
  - 如果 1 block 解冻漂移 → **回退到 LoRA** (更安全)

### 2d. 当前 DINOv3 冻结配置确认

从 config 文件确认:
```python
online_dinov3_layer_idx = 16        # 提取第 16 层
online_dinov3_unfreeze_last_n = 0   # 全部冻结
online_dinov3_dtype = 'fp16'        # FP16 推理
online_dinov3_weight_path = '/mnt/SSD/yz0370/dinov3_weights/dinov3_vit7b16_pretrain_lvd1689m.pth'
```

DINOv3 ViT-7B 结构:
- **40 blocks** (depth=40), embed_dim=4096, num_heads=32, ffn_ratio=3
- **~7B 总参数, 全部冻结, 无梯度, FP16**

---

## 综合建议

### 优先级重排 (基于本次调查)

| 排名 | 行动 | 理由 | 时机 |
|------|------|------|------|
| **0** | **修复 BUG-48** (unfreeze_last_n 无效) + **添加 early break** (节省 58% DINOv3 计算) | 任何解冻实验的前提 | 立即 |
| **1** | **Layer 验证实验** (多层对比) | 如果 layer 16 是错的, 后续所有实验都在次优基础上 | ORCH_024 后优先 |
| 2 | Deep Supervision (已计划) | 零成本, 与 layer 实验独立 | ORCH_024 后 |
| 3 | 解冻 block 16 (单层) | 需要先修 BUG-48 + 确认最优 layer | Layer 验证后 |
| 4 | LoRA | 如果解冻漂移, 作为备选 | 解冻实验后 |
| 5 | 方案 D (历史 occ) | 与解冻独立 | 可并行 |

### 需要 Critic 评估的问题

1. **Layer 16 vs 更深层**: 我的分析基于 DINOv2 经验, 需要 Critic 验证是否适用于 DINOv3 ViT-7B
2. **@17000 阈值 0.15**: 这个数字基于趋势外推, 需要 Critic 评估合理性
3. **BUG-48 影响范围**: 需确认 Plan M 的 unfreeze 实验是否受此 BUG 影响 (如果是, 结论需修正)

### 新 BUG

| BUG | 严重性 | 描述 |
|-----|--------|------|
| **BUG-48** | **HIGH** | `unfreeze_last_n` 解冻模型末端 blocks, 但我们只用 layer 16 的输出. 梯度不流经 blocks 17-39, 解冻参数永远不会被更新. 任何基于此参数的 unfreeze 实验结果无效 |
| **BUG-49** | **MEDIUM** | `get_intermediate_layers` 遍历全部 40 blocks 但只需前 17 个. 浪费 ~58% DINOv3 前向计算. 不影响正确性但影响速度 |

---

## 附录: 签发审计请求

已签发 AUDIT_REQUEST_DINOV3_LAYER_AND_UNFREEZE, 请 Critic 评估:
1. Layer 16 选择的合理性
2. BUG-48 对历史实验 (Plan M) 的影响
3. 修正后阈值矩阵的合理性
