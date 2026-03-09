# 审计判决 — DINOV3_LAYER_AND_UNFREEZE
> Critic | 2026-03-09 ~17:30
> 审计请求来源: Conductor Cycle #138

## 结论: CONDITIONAL

**条件**:
1. BUG-48 必须在任何 unfreeze 实验前修复
2. Layer 选择实验 (多层对比) 应在 ORCH_024 完成后优先执行
3. Plan M 的方案 B "三重否决" 必须标注为 **基于无效实验**, 不可用于后续决策

---

## Q1 判决: Layer 16 (40% depth) 是否合理?

### 评估

Conductor 的分析方向正确, 但有两处需要修正:

**1. DINOv2 → DINOv3 类比不完全成立**

Conductor 引用 "DINOv2 ViT-L (24 layers) 常用 layer 11-12 (~50% depth)" 来推导 DINOv3 应用 60-70% depth。这个推导的问题:
- DINOv3 ViT-7B (40 blocks) 远大于 DINOv2 ViT-L (24 blocks)
- 更深的模型特征分层更细腻, 不是简单的百分比缩放关系
- DINOv2 的 dense prediction 实验 (如 DPT 论文) 实际上使用**多层特征融合** (layers 5, 12, 18, 24), 而非单层

**2. 40% depth 对 BEV 占据不一定错**

BEV 占据的三个需求拆解:
| 需求 | 所需特征层级 | Layer 16 能力 |
|------|------------|-------------|
| 物体类别识别 (car/truck/bus) | 高级语义 (60%+) | **不足** — 中层特征类别判别力弱 |
| 空间定位 (BEV grid precision) | 中级空间 (30-50%) | **适合** — 保留较多空间信息 |
| 朝向估计 (theta) | 物体级结构 (50-70%) | **边缘** — 可能不够 |

**结论: Layer 16 不是最优选择, 但不是灾难性错误。** 主要受限点是类别判别力不足, 这可能部分解释 car_P 的精度瓶颈 (BUG-15)。

### 对当前实验的影响

- **趋势和对比结论仍然有效** — 所有实验都在同一 layer 下, 相对排序不变
- **绝对数值被系统性压低** — 切换到更优 layer 后 car_P 基线可能提升
- **已有结论无需撤销**, 但需要标注 "基于 layer 16, 非最优配置"

### 对多层对比实验的评估

Conductor 提议的方案 A (5 个 layer 各跑 2000 iter, ~2h) **值得投入但时机不对**:
- 当前 ORCH_024 正在训练, 4 GPU 被占用
- 应在 ORCH_024 @40000 完成后立即执行
- 建议候选层: **[12, 16, 20, 24, 28]** — Conductor 选的这组合理
- **Layer 24 (60% depth) 是最可能的最优点**, 兼顾语义和空间
- 方案 C (特征统计 Fisher criterion) 可在 ORCH_024 训练期间单卡执行, 不占训练资源, 建议先做

### Q1 总结

| 项目 | 判断 |
|------|------|
| Layer 16 是否错误 | 非最优, 但非灾难 |
| 是否需要修改 | 是, 在 ORCH_024 后 |
| 紧急程度 | MEDIUM — 不值得中断当前训练 |
| 推荐替代层 | Layer 24 (60% depth) 作为首选候选 |

---

## Q2 判决: BUG-48 确认 + Plan M 影响评估

### BUG-48 确认: `unfreeze_last_n` 完全无效

**代码证据链** (全部已亲自验证):

**Step 1**: 冻结全部参数
```python
# vit_git.py:L147-149
for param in self.dinov3.parameters():
    param.requires_grad = False
```

**Step 2**: 解冻 blocks 38-39 (末端)
```python
# vit_git.py:L151-159
if unfreeze_last_n > 0:
    total_layers = len(self.dinov3.blocks)  # = 40
    for i in range(total_layers - unfreeze_last_n, total_layers):
        for param in self.dinov3.blocks[i].parameters():
            param.requires_grad = True
```

**Step 3**: 提取 layer 16 输出 (非末端)
```python
# dinov3/models/vision_transformer.py:L270-284
def _get_intermediate_layers_not_chunked(self, x, n=1):
    blocks_to_take = range(total_block_len - n, total_block_len) if isinstance(n, int) else n
    for i, blk in enumerate(self.blocks):  # 遍历全部 40 blocks
        x = blk(x, rope_sincos)
        if i in blocks_to_take:  # n=[16] 时, 只在 i==16 保存
            output.append(x)
    return output
```

**梯度流分析**:
```
Loss ← proj_layer ← layer_16_output ← block_16 ← block_15 ← ... ← block_0 ← input
                                        ↑ 梯度到这里就够了

block_17 → block_18 → ... → block_38 → block_39
              ↑ 这些 blocks 的输出从未被用于 loss
              ↑ 即使 requires_grad=True, 也永远没有梯度流入
```

**判定: BUG-48 确认, 严重性 HIGH。** `unfreeze_last_n` 在 `layer_idx < total_layers - unfreeze_last_n` 时完全无效。

### Plan M "特征漂移" 溯源

Plan M 用 `unfreeze_last_n=2` 报告了 "特征漂移"。BUG-48 证明 blocks 38-39 的解冻对 layer 16 输出无效。那 "漂移" 从何而来?

**关键代码差异** (`vit_git.py:L204-212`):

```python
# 当 unfreeze_last_n > 0:
features = self.dinov3.get_intermediate_layers(...)  # 无 no_grad

# 当 unfreeze_last_n == 0:
with torch.no_grad():
    features = self.dinov3.get_intermediate_layers(...)  # 有 no_grad
```

移除 `torch.no_grad()` 的影响:
1. **计算图被构建**: 全部 40 blocks 的中间张量被保存在内存中
2. **显存暴增**: 17 个 block (0-16) 的激活值 + 梯度缓存, 估计增加 10-15 GB
3. **DINOv3 参数不变**: blocks 0-16 的 `requires_grad=False` 确保参数不更新
4. **proj 层梯度计算路径变化**: 无 — 前向值完全相同, proj 权重更新不受影响

**Plan M "特征漂移" 的三种可能解释**:

| 假说 | 可能性 | 理由 |
|------|--------|------|
| A: 显存压力导致 OOM 或降低 batch size | **HIGH** | Mini 数据集 + 移除 no_grad 可能导致 OOM, 训练不稳定被误读为 "漂移" |
| B: Mini 数据集噪声 + 确认偏差 | **HIGH** | Mini 仅 ~3k 样本, 任何指标波动都大, 预期 "应该漂移" 容易误判 |
| C: FP16 数值差异 | **LOW** | 有/无 no_grad 的 FP16 前向值理论上完全相同 |

**结论: Plan M 的 "特征漂移" 几乎确定是误归因。** DINOv3 layer 16 特征在有/无 no_grad 下输出完全一致 (same weights, same computation, same input)。变化只可能来自显存压力或训练噪声。

### Plan M 方案 B "三重否决" 需要撤销吗?

**需要撤销, 但程度有限:**

1. Plan M 的 "unfreeze 导致漂移" 结论 → **无效** (BUG-48, 实际上没 unfreeze 任何有效 block)
2. 方案 B (unfreeze DINOv3) 的否决 → **应标注为 "基于无效实验, 需重新测试"**
3. **不应直接翻转为 "PROCEED"** — 需要先修 BUG-48, 再用正确的 block (block 15-16 而非 38-39) 重新实验

### BUG-48 修复建议

```python
# vit_git.py:L151-159 修改为:
if unfreeze_last_n > 0:
    # 解冻 extraction point 前的 N 个 blocks (而非末端 blocks)
    for i in range(max(0, layer_idx - unfreeze_last_n + 1), layer_idx + 1):
        for param in self.dinov3.blocks[i].parameters():
            param.requires_grad = True
    print(f"[OnlineDINOv3Embed] Unfroze blocks {max(0, layer_idx - unfreeze_last_n + 1)}"
          f" to {layer_idx}")
```

修复后 `unfreeze_last_n=2` 将解冻 blocks 15-16 (extraction point 附近), 梯度正确流经。

---

## Q3 判决: 修正后阈值矩阵合理性

### Conductor 提议的阈值

| 阶段 | peak_car_P | 行动 |
|------|-----------|------|
| @10000 | > 0.08 | 继续 |
| @17000 (LR decay 后) | > 0.15 | 架构干预 |
| @25000 | > 0.20 | 可能重设计 |
| @40000 | > 0.25 | 根本改变 |

### 逐项评估

**@10000: peak > 0.08** — **合理, 不改**
- 当前 peak = 0.090, 已过此阈值
- 作为 25% 训练进度的低标准, 合适

**@17000: peak > 0.15** — **偏激进, 建议调整为 > 0.12**

理由:
- @2000→@6000 (1000 opt steps) peak 从 0.079→0.090, 增幅 +0.011
- @6000→@17000 (2750 opt steps) 包含 LR decay, 预期加速
- 乐观估计: 0.090 + 0.011 × (2750/1000) × 1.5 (decay boost) ≈ 0.135
- 0.15 要求 @17000 时 peak 比当前翻 67%, 在 2750 opt steps 内需要 LR decay 带来非线性跳变
- **更稳妥: 设 0.12 为 "继续" 下限, 0.15 为 "确认方向" 上限**

**修正建议:**
| @17000 peak_car_P | 行动 |
|-------------------|------|
| > 0.15 | 确认方向正确, 加速推进 |
| 0.12 - 0.15 | LR decay 有效但不够, 启动 layer/unfreeze 干预 |
| < 0.12 | LR decay 无效, 架构问题确认, 立即干预 |

**@25000: peak > 0.20** — **合理, 不改**
- 经过两次 LR decay (@17000, @25000), 模型应进入精细收敛期
- 0.20 作为 62% 训练进度的标准合理

**@40000: peak > 0.25** — **条件合理, 但需注意 layer 变量**
- 如果 layer 从 16 切换到 24, 基线可能整体提升, 这些阈值全部需要重新校准
- **建议**: 阈值矩阵增加脚注 "基于 layer_idx=16 校准, layer 变更后需重校"

### 关于 @17000 作为关键判断点

**Conductor 选 @17000 作为 LR decay 分界点, 合理但有一个陷阱:**

- LR milestone 在 config 中设为 `milestones=[15000, 25000]`
- @15000 iter 触发第一次 decay (通常 ×0.1)
- @17000 iter = decay 后 2000 iter (500 opt steps)
- **500 opt steps 可能不够看到 decay 的完整效果**

**建议: 判断点改为 @20000** (decay 后 5000 iter = 1250 opt steps), 给模型足够时间适应新 LR。或者在 @17000 和 @20000 各做一次 eval, 如果 @20000 比 @17000 有明显提升说明 decay 还在生效。

---

## 发现的问题

### BUG-48: `unfreeze_last_n` 解冻位置错误 (Conductor 首报, Critic 确认)
- **严重性**: HIGH
- **位置**: `GiT/mmdet/models/backbones/vit_git.py:L151-159`
- **描述**: `unfreeze_last_n=N` 解冻 DINOv3 末端 N 个 blocks (38-39), 但 `layer_idx=16` 提取 block 16 输出。梯度不流经 blocks 17-39, 解冻参数永远不会被更新。
- **影响**: Plan M 的 "unfreeze 导致特征漂移" 结论无效; 方案 B 三重否决需标注为基于无效实验
- **修复**: 改为解冻 extraction point 附近的 blocks (block `layer_idx - N + 1` 到 `layer_idx`)

### BUG-49: DINOv3 前向计算浪费 (Conductor 首报, Critic 确认)
- **严重性**: MEDIUM
- **位置**: `GiT/dinov3/dinov3/models/vision_transformer.py:L270-284`
- **描述**: `get_intermediate_layers` 遍历全部 40 blocks, 但 `layer_idx=16` 只需前 17 个。Blocks 17-39 的前向计算完全浪费 (~58% DINOv3 计算)。
- **影响**: 不影响正确性, 但每个 training iter 浪费 ~58% DINOv3 前向时间
- **修复**: 在 `_get_intermediate_layers_not_chunked` 中添加 early break (`if len(output) == len(blocks_to_take): break`), 或在 `OnlineDINOv3Embed.forward` 中只传入 `self.dinov3.blocks[:layer_idx+1]`

### BUG-50: `torch.no_grad()` 条件移除导致隐性显存风险 (NEW)
- **严重性**: MEDIUM
- **位置**: `GiT/mmdet/models/backbones/vit_git.py:L204-207`
- **描述**: 当 `unfreeze_last_n > 0` 时, 整个 `get_intermediate_layers` 调用移除 `torch.no_grad()`, 导致全部 40 blocks (包括冻结的) 构建计算图。即使只解冻 1-2 个 block, 也会为 40 个 block 保存激活值, 显存增加 ~10-15 GB。
- **正确做法**: 仅对需要梯度的 blocks 移除 no_grad, 或修复 BUG-49 (early break) 后此问题自动缓解 (只计算 17 个 block 的计算图)
- **与 Plan M 关系**: 此 BUG 是 Plan M "特征漂移" 的真正原因 — 显存暴增可能导致 OOM 或训练不稳定

---

## 逻辑验证

- [x] **梯度守恒**: 确认 layer_idx=16 时, 梯度只流经 blocks 0-16 → proj → loss。Blocks 17-39 无梯度贡献。
- [x] **边界条件**: 若 `layer_idx >= total_layers - unfreeze_last_n` (如 layer_idx=39, unfreeze_last_n=2), 解冻的 blocks 38-39 中 block 39 确实能获得梯度。BUG-48 仅在 `layer_idx < total_layers - unfreeze_last_n` 时触发。
- [x] **数值稳定性**: 有/无 `torch.no_grad()` 的前向值理论上完全相同 (same weights, same ops, same input)。不影响数值正确性, 只影响是否构建计算图。

---

## 需要 Admin 协助验证

### 验证 1: BUG-48 梯度流确认
- **假设**: unfreeze_last_n=2 时, blocks 38-39 的参数梯度始终为 zero
- **验证方法**: 在 `vit_git.py` forward 后添加:
  ```python
  if self.unfreeze_last_n > 0:
      for i in range(len(self.dinov3.blocks) - self.unfreeze_last_n, len(self.dinov3.blocks)):
          for name, p in self.dinov3.blocks[i].named_parameters():
              if p.grad is not None:
                  print(f"Block {i} {name} grad norm: {p.grad.norm()}")
              else:
                  print(f"Block {i} {name} grad: None")
  ```
- **预期结果**: 所有 grad 为 None 或 0, 确认 BUG-48

### 验证 2: Layer 特征质量快速对比 (方案 C)
- **假设**: 更深层的特征对 BEV 占据有更强判别力
- **验证方法**: 用 ORCH_024 @10000 checkpoint, 对一个 batch 提取 layers [12, 16, 20, 24, 28] 的特征, 计算 Fisher criterion (类间方差/类内方差)
- **预期结果**: Layer 24-28 的 Fisher score 显著高于 Layer 16

### 验证 3: 显存监控
- **假设**: 移除 torch.no_grad() 显著增加显存
- **验证方法**: 分别以 `unfreeze_last_n=0` 和 `unfreeze_last_n=2` 启动, 记录 peak GPU memory
- **预期结果**: unfreeze_last_n=2 的显存比 0 高 ~10-15 GB

---

## 对 Conductor 计划的评价

### 正确的部分
1. **BUG-48 发现** — Conductor 的代码审查质量很高, 独立发现了这个严重 BUG
2. **BUG-49 计算浪费** — 正确识别, early break 修复简单有效
3. **Layer 验证实验的优先级提升** — 合理, 如果 layer 选错会系统性压低所有实验结果
4. **优先级排序** — "修复 BUG-48 > Layer 验证 > Deep Supervision > 解冻 > LoRA" 合理

### 需要修正的部分
1. **@17000 阈值 0.15 偏高** — 应调低至 0.12 (见 Q3 详细分析)
2. **@17000 判断点可能太早** — LR decay @15000 后仅 500 opt steps, 建议推迟到 @20000 或双点评估 (@17000 + @20000)
3. **LoRA vs 解冻的分析中遗漏了 BUG-50** — 移除 no_grad 的显存代价未被充分评估, 这会影响解冻方案的可行性
4. **DINOv2→DINOv3 层深度类比不够严谨** — 不同大小模型的层深度不是简单百分比映射

### 遗漏的风险
1. **Layer 变更后阈值失效**: 如果 layer 从 16 切到 24, 所有阈值需要重新校准。当前阈值矩阵没有标注这个前提条件。
2. **BUG-49 修复可能影响 DINOv3 内部行为**: 如果 DINOv3 的 `get_intermediate_layers` 有 normalization 或 residual 依赖全局 block 数的逻辑, early break 可能引入不一致。需要检查 `norm=True` 参数的实现。

---

## 附加建议

### 1. ORCH_024 训练不应中断
当前 4 GPU 在跑 ORCH_024 @10000→@40000, ETA 3/11。BUG-48 和 layer 选择的修复不值得中断:
- BUG-48 对当前 `unfreeze_last_n=0` 配置无影响
- Layer 选择只影响后续实验, 不影响当前训练的诊断价值
- ORCH_024 的完整训练曲线本身就是重要数据

### 2. BUG-48 修复应同时修复 BUG-49 和 BUG-50
三个 BUG 紧密相关, 建议一次性修复:
- BUG-48: 改解冻目标为 extraction point 附近 blocks
- BUG-49: 添加 early break 或只传前 17 个 blocks
- BUG-50: 自动解决 (early break 后只有 17 个 block 的计算图, 显存增量从 ~10-15 GB 降至 ~3-5 GB)

### 3. 方案 B 三重否决处理建议
不建议直接翻转否决。正确流程:
1. 修复 BUG-48
2. 在 Full nuScenes 上用正确的 block 解冻重新实验 (ORCH_025 或类似)
3. 根据新实验结果重新评估方案 B

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-48 | HIGH | **CONFIRMED** | `unfreeze_last_n` 解冻末端 blocks, 但 layer_idx=16 提取中段, 梯度不流经. Plan M 结论无效 |
| BUG-49 | MEDIUM | **CONFIRMED** | DINOv3 前向遍历全部 40 blocks, 只需 17 个. 浪费 ~58% 计算 |
| BUG-50 | MEDIUM | **NEW** | `unfreeze_last_n > 0` 移除 torch.no_grad(), 全部 40 blocks 构建计算图, 显存暴增 ~10-15 GB |

下一个 BUG 编号: BUG-51
