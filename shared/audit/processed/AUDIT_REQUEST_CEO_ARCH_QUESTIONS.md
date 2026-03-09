# AUDIT_REQUEST: CEO 架构疑问与改进思路
- 签发: Conductor | Cycle #92 Phase 1
- 时间: 2026-03-08 ~18:45
- 优先级: HIGH — CEO 明确要求送审

---

## 背景

ORCH_024 Full nuScenes 训练中 (1160/40000, warmup). 首次 val @2000 ETA ~20:10.
CEO 提出 4 个架构层面的疑问，要求 Conductor 分析后统一送审。

---

## CEO 问题 1: 30 Token 自回归解码是否是 Car 分类困难的根因？

**CEO 原文**: 每个 cell 3 slot × 10 token = 30 token AR 解码，序列越长前面错误累积。需验证是否是解码长度导致 car 分类不稳定。

**Conductor 分析**:

这是一个合理的担忧，但我认为**不是主要瓶颈**，理由如下：

1. **Token 布局实际结构**: 每个 cell 的 30 token 中，marker+class 在前 (slot 的第 1-2 个 token)，box 属性在后。分类 (class token) 的错误累积风险主要来自**前面 slot** 的解码，而不是同 slot 内部。

2. **GiT 原始论文设计**: GiT 就是为长序列 AR 解码设计的。原始 GiT 在 COCO 检测上有效，序列更长 (全图数百个目标)。BEV 每 cell 最多 3 slot 已经是简化版。

3. **实际瓶颈更可能是**:
   - DINOv3 特征到 BEV 空间的映射质量 (投影层)
   - Mini 数据量不足 (323 图, BUG-20 类振荡)
   - 类别不平衡 (car 数量远超其他类)

4. **缩短序列的可行性**:
   - 合并 token (如 gx+gy 为单 token): 需改 num_vocal (BUG-27 风险!)
   - 并行解码部分属性: 不再是 AR，需要改架构为 masked/parallel prediction
   - 减少 slot 数 (3→2): 会丢失密集区域的多目标检测能力

5. **可行的验证方式**: 分析 ORCH_024 @2000 eval 中，每个 slot 位置的 precision/recall 分布。如果 slot 3 明显差于 slot 1，则序列长度确实有影响。

**Conductor 结论**: 值得关注但低优先级。Full nuScenes 数据量应能缓解 mini 上的分类不稳定。建议先看 ORCH_024 结果，再决定是否需要架构级改动。

---

## CEO 问题 2: Deep Supervision (深度监督)

**CEO 原文**: 在 Transformer 最后几层都算 loss (浅层粗粒度、深层细粒度)。能否在中间层就开始监督 marker/class 预测？

**Conductor 分析**:

1. **技术可行性**: 是。可在 Transformer decoder 的第 20/22/24 层 (共 24 层) 各加一个辅助预测头，计算同样的 AR loss。

2. **潜在收益**:
   - 改善梯度流，缓解深层网络训练困难
   - 中间层 marker/class 监督可作为"课程学习"——先学分类，再精调几何属性
   - 在分割任务 (DeepLabV3+, HRNet) 中效果显著

3. **风险和代价**:
   - 显存增加: 每个辅助头需额外计算+存储 logits (num_vocal=230 × seq_len)。当前 36-37 GB/GPU，余量 ~11 GB，估计 1-2 个辅助头可行
   - 训练速度下降: ~5-15% (取决于辅助头数量)
   - 实现复杂度: 中等。需修改 Transformer decoder forward 和 loss 计算

4. **与 AR 解码的兼容性**: AR 解码通常只用最后一层输出做 next-token prediction。Deep supervision 在 AR 中不如在 dense prediction 中常见，因为中间层可能还没有足够的上下文来做准确的 token 预测。但作为辅助 loss (较低权重) 仍可能有正则化效果。

**Conductor 结论**: 中等优先级。实现需 1-2 天，值得在 ORCH_024 后尝试。建议辅助 loss 权重从 0.1 起步，只在最后 2-3 层加。

---

## CEO 问题 3: Slot 内 Attention Mask 设计

**CEO 原文**: box 属性解码时能看到所有前面 token。但 slot 的 box 属性应只跟自己 slot 的 marker/class 强相关。能否设计 attention mask 让 box 属性只关注本 slot + 全局 marker/class？

**Conductor 分析**:

1. **当前 mask**: 标准 causal mask。Token i 可以 attend to token 0..i-1。跨 slot 和跨 cell 都可以看到。

2. **CEO 提案的直觉**: 一个 slot 的 w/h/theta 不应该受到同 cell 其他 slot 的 w/h/theta 影响。合理的先验。

3. **具体设计方案**:
   ```
   Cell token 结构: [S1_marker, S1_class, S1_gx, S1_gy, S1_w, S1_h, S1_tg, S1_tf, S1_cx, S1_cy,
                      S2_marker, S2_class, ...]

   方案 A (CEO): S2_gx 只能 attend to:
   - S2_marker, S2_class (本 slot 的类型信息)
   - S1_marker, S1_class, S2_marker, S2_class (所有 slot 的 marker/class)
   - S2_gx 之前的本 slot token
   - BEV query (全局上下文)

   方案 B (Conductor): 保持 causal mask 但降低跨 slot attention 权重
   - 软约束，不硬切断信息流
   - 实现更简单，风险更低
   ```

4. **可行性**: **高**。Attention mask 修改只需改 `generate_attention_mask()` 函数。代码层面 1-2 小时可实现。

5. **风险**: 完全切断跨 slot 信息可能有害 — 同一 cell 中多个目标可能存在空间约束 (不重叠)。Slot 2 知道 Slot 1 占了哪些空间对它有帮助。

6. **验证方案**: Mini 上快速 A/B 测试 (2000 iter)，对比有/无 structured mask 的 precision。

**Conductor 结论**: **最有潜力的快速验证项**。实现简单、风险可控、代码改动小。建议 ORCH_024 后优先尝试。

---

## CEO 问题 4: 500 Iter 评判是否太草率？

**CEO 原文**: 323 图 / batch_size=2 ≈ 160 iter/epoch, 500 iter 才 3 epoch。小幅指标波动 (±2%) 有无统计意义？需不需要最小显著性阈值？

**Conductor 分析**:

**CEO 完全正确。这是 Mini 阶段的核心教训之一。**

历史证据:
| 实验 | @500 判断 | 后续真实表现 | 教训 |
|------|----------|-------------|------|
| Plan O | car_P=0.000, 判为无效 | BUG-41: warmup=max_iters=500 | @500 全是 warmup, 不是真实训练 |
| Plan P | car_P=0.004, 判为失败 | 超参问题 (lr_mult=1.0), 非架构问题 | @500 不足以判断架构 |
| Plan L | car_P=0.054 @500 | @1000=0.140 (+159%!) | @500 严重低估 |
| Plan P2 | car_P=0.069 @500 | @1000=0.100, @1500=0.112 | @500 仅 62% of peak |

**建议的最小评判标准**:

| 数据集 | 最小 iter | 最小 epoch | 阈值 |
|--------|----------|-----------|------|
| Mini (323 图) | 2000 | ~12 | 相对变化 ≥10%, 连续 2 个 eval 点一致 |
| Full nuScenes (28130 图) | 4000 | ~1.1 | 相对变化 ≥5%, 连续 2 个 eval 点一致 |

**显著性判断规则** (Conductor 提案):
1. 单次 eval 指标变化 <5%: **不做任何决策**，标记为"波动"
2. 单次 eval 指标变化 5-15%: **条件性结论**，需下一个 eval 确认
3. 单次 eval 指标变化 >15%: **可能有意义**，但仍需排除超参/BUG 原因
4. 连续 2 个 eval 同向变化 >5%: **可做结论**

**Conductor 结论**: 强烈同意。应将此规则写入 MASTER_PLAN.md 作为永久实验评判标准。

---

## Conductor 补充观察

### 关于 CEO 问题的优先级排序 (Conductor 建议):

| 排名 | 提案 | 实现难度 | 预期收益 | 建议时机 |
|------|------|---------|---------|---------|
| 1 | **问题 3 (Attention Mask)** | 低 (1-2h 代码) | 中-高 | ORCH_024 后首先尝试 |
| 2 | **问题 4 (评判标准)** | 零 (只改流程) | 高 (避免错误决策) | 立即采纳 |
| 3 | **问题 2 (Deep Supervision)** | 中 (1-2d 代码) | 中 | ORCH_024 后第二批 |
| 4 | **问题 1 (解码长度)** | 高 (架构级改动) | 低-中 | 仅在其他方案无效时 |

### 与 VERDICT_CEO_STRATEGY_NEXT 的整合:
- CEO 问题 3 (Attention Mask) 可与方案 D (历史 occ box) 并行开发
- CEO 问题 2 (Deep Supervision) 可与方案 E (LoRA) 并行验证
- CEO 问题 1 (解码长度) 仅在 ORCH_024 结果不佳时考虑

---

## 审计问题 (请 Critic 逐一回答)

### Q1: 30 Token AR 解码
- 序列长度是否是当前 precision 瓶颈？
- 有无不改 num_vocal 的缩短方案？
- Slot 位置 (1/2/3) 是否有显著性能差异？如何验证？

### Q2: Deep Supervision
- AR 解码中 deep supervision 是否有先例和理论依据？
- 辅助 loss 应加在哪些层？权重多少？
- 显存增量估算？是否在 A6000 48GB 范围内？

### Q3: Slot Attention Mask
- CEO 的硬 mask (方案 A) vs Conductor 的软权重 (方案 B)，哪个更好？
- 跨 slot 信息是否对空间去重有价值？完全切断是否有害？
- 在 mini 上 2000 iter A/B 测试是否足够验证？

### Q4: 评判标准
- Conductor 提出的 4 条显著性规则是否合理？
- 是否需要引入统计检验 (如 bootstrap confidence interval)？
- Full nuScenes 上多少 iter 后的指标才有决策价值？

### Q5: 优先级排序
- 上述 4 个提案 + VERDICT_CEO_STRATEGY_NEXT 中的方案 D/E，如何综合排序？
- 应该在 ORCH_024 后先做哪个？

---

## 期望输出

1. 每个 CEO 问题的独立评估 (可行性、收益、风险)
2. 综合优先级排序 (含之前的方案 D/E)
3. 问题 3 (Attention Mask) 的具体实现建议
4. 评判标准规则的修正建议
5. 是否需要在 ORCH_024 完成前就开始准备代码？
