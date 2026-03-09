# AUDIT_REQUEST: AR 序列长度瓶颈重新审视
- 签发: Conductor | Cycle #94 Phase 1
- 时间: 2026-03-08 ~20:15
- 优先级: MEDIUM — CEO 要求复核

---

## 背景

CEO 指出 VERDICT_CEO_ARCH_QUESTIONS 中关于 GiT 序列长度的归因问题。

### 归因澄清

**错误说法 "原始 GiT 序列更长" 是 Conductor 的错误 (AUDIT_REQUEST_CEO_ARCH_QUESTIONS 中)**。Critic 在 VERDICT 中已经纠正了 Conductor:
- Critic 明确说: "Conductor 称 '原始 GiT 在 COCO 检测上有效，序列更长'。**这是错误的。**"
- Critic 确认: detection per-query = 5 tokens, OCC per-query = 30 tokens, 是 GiT 所有变体中最长的

**CEO 不需要怀疑 Critic 的事实判断**——Critic 的事实判断与 CEO 完全一致。但 CEO 有权质疑 Critic 的**结论**: 即便承认 6x 差距, Critic 仍判定 "30 token AR 序列不是 precision 主要瓶颈"。这个结论是否站得住？

### Conductor 代码验证 (已完成)

```python
# git_det_head.py: detection
for pos_id in range(0, self.dec_length + 1):  # dec_length=5
    # pos_id=0: grid token (skip)
    # pos_id=1: class label
    # pos_id=2-5: bbox coords (cx, cy, w, h)
    # 有效解码: 5 token

# git_occ_head.py: OCC (我们)
pred_tokens = torch.full((B * Q, 30), ...)  # L1098
for pos_id in range(30):  # L1103
    # 3 slot × 10 token = 30 token 解码

# configs 确认:
# detection: dec_length=5
# OCC: dec_length=30
# segmentation: dec_length=1+4+2+ray_num (~7-39)
# caption: dec_length=16 or 20
# depth: dec_length=4
```

**结论: OCC 的 per-query 解码长度是 GiT 所有任务中最长的, 是 detection 的 6x。CEO 的理解完全正确。**

---

## CEO 的核心质疑

Critic 在 VERDICT 中给出了 4 个理由认为 "不是主要瓶颈":
1. Marker token 选择几乎不受前面 slot 影响
2. Class token 只依赖 marker
3. 几何属性用独立 logits 子空间
4. 真正瓶颈是 DINOv3→BEV 投影

**CEO 质疑**: 6x 的解码负担是否真的可以忽略？Critic 的 4 个理由是否每一条都站得住？

### Conductor 对 Critic 4 个理由的再分析

**理由 1 (Marker 不受前 slot 影响)**: 基本正确。Marker 决策主要取决于 BEV cell 的空间位置与目标的关系, 不太依赖前面 slot 的解码结果。

**理由 2 (Class 只依赖 marker)**: **部分质疑**。Class token (pos_id=1/11/21) 虽然是每个 slot 的第二个 token, 但它通过 attention 可以看到所有前面 slot 的 class 预测。如果 Slot 1 预测了 "car", Slot 2 的 class 预测是否会被偏向 "非 car" (竞争效应)？这在 BEV occ 中可能有意义, 因为同一 cell 通常不太可能有两个相同类别的目标。

**理由 3 (几何属性独立 logits 子空间)**: 正确。`L1142-1175` 的 slice 操作确实将不同属性映射到 vocab 的不同区间。但这不意味着前面的解码错误不影响后面——错误的 class 会导致后续几何属性的 conditioning 信号有误。

**理由 4 (DINOv3→BEV 投影是真正瓶颈)**: **可能正确但未经证实**。这是一个假说, 不是已验证的结论。ORCH_024 @2000 结果将提供更多证据。

### Conductor 补充: 6x 负担的实际影响

1. **训练效率**: 30 step AR vs 5 step, 每个 cell 的计算量线性增长 6x。但 per-cell 并行 (B*Q) 缓解了延迟——只增加显存, 不增加 wall-clock (因为所有 cell 同步解码)。

2. **错误累积的实际概率**: 如果每步 argmax 正确率 95%, 5 step 后正确率 = 0.95^5 = 77%, 30 step 后 = 0.95^30 = **21%**。这是一个**巨大差距**。当然实际正确率取决于任务难度, 但 CEO 的直觉——更长序列=更多错误累积——在数学上是成立的。

3. **但 Critic 的 per-cell 并行论点也成立**: 30 步错误只影响单个 cell 内的预测, 不跨 cell 传播。每个 cell 独立失败不会系统性降低全局 precision。

---

## 审计问题 (请 Critic 回答)

### Q1: 归因澄清确认
请 Critic 确认: "原始 GiT 序列更长" 的错误说法是 Conductor 的 (在 AUDIT_REQUEST 中), 不是 Critic 的。Critic 在 VERDICT 中已正确纠正。CEO 的误解需要被澄清。

### Q2: 6x 解码负担的量化影响
Conductor 给出了一个简化的错误累积模型 (0.95^30 = 21%)。这个模型是否合理？实际 per-step 正确率估算是多少？30 step 后的有效信息保留率?

### Q3: 重新评估 "不是主要瓶颈" 的结论
考虑到:
- 6x 解码长度 (CEO+Critic+Conductor 三方确认)
- 潜在的错误累积效应
- CEO 提到的 car 分类不稳定

Critic 是否维持 "不是主要瓶颈" 的结论？如果是, 是否能提供更强的证据 (而非仅靠理论分析)？

### Q4: 可验证的实验方案
如果要验证 "序列长度是否是瓶颈", 最低成本的实验方案是什么？
- 例如: 将 3 slot 减少到 1 slot (dec_length=10), 看 car precision 是否显著提升?
- 这需要改 num_vocal 吗?

---

## 期望输出
1. 归因澄清
2. 6x 负担的量化评估
3. "非瓶颈" 结论的维持/修正
4. 最低成本验证实验方案
