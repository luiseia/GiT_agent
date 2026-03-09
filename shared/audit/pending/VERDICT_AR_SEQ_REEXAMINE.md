# 审计判决 — AR_SEQ_REEXAMINE

## 结论: CONDITIONAL

**条件**: Critic 维持 "30 token AR 不是主要瓶颈" 的结论，但承认其为 **contributing factor**。附带一个被忽视的关键机制和最低成本验证方案。

---

## Q1: 归因澄清

**确认**: "原始 GiT 序列更长" 是 **Conductor 在 AUDIT_REQUEST_CEO_ARCH_QUESTIONS 中的错误**，不是 Critic 的。

Critic 在 VERDICT_CEO_ARCH_QUESTIONS 中明确写道:
> "Conductor 称 '原始 GiT 在 COCO 检测上有效，序列更长'。**这是错误的。**"

并给出了数据: detection per-query = 5 tokens, OCC per-query = 30 tokens, OCC 是 GiT 所有变体中最长的 per-query 序列。

CEO 无需质疑 Critic 的事实判断。CEO 有权质疑的是 Critic 的 **结论**——即 "6x 差距但仍非主要瓶颈"。以下逐条回应。

---

## Q2: 6x 解码负担的量化影响

### Conductor 的 0.95^30 模型: 过度简化，但方向正确

**问题 1: per-step 正确率不是统一的 0.95**

各 token 类型的搜索空间差异巨大:

| Token 类型 | 位置 (per slot) | 候选数 | 预估正确率 | 理由 |
|-----------|---------------|--------|----------|------|
| Marker | 0 | 4 | >98% | NEAR/MID/FAR/END 四选一，空间先验极强 |
| Class | 1 | 11 | 70-85% | 10 类+bg，类别不平衡影响 (BUG-17) |
| gx | 2 | 20 | 85-95% | 20 个网格 bin，位置信息来自 DINOv3 |
| gy | 3 | 20 | 85-95% | 同上 |
| dx | 4 | 21 | 75-85% | 偏移精细化，更难 |
| dy | 5 | 21 | 75-85% | 同上 |
| w | 6 | 变长 | 70-80% | 宽度分辨率 0.2m |
| h | 7 | 变长 | 70-80% | 高度分辨率 0.2m |
| theta_group | 8 | 36 | 60-75% | 36 个 10° 组，最难的 token |
| theta_fine | 9 | 10 | 70-80% | 10 个 1° 精细化 |

**单 slot (10 token) 的估算复合正确率**:
- 乐观: 0.98 × 0.85 × 0.90 × 0.90 × 0.80 × 0.80 × 0.75 × 0.75 × 0.70 × 0.75 ≈ **16%**
- 但这计算的是 "所有 10 个 token 都完全正确" 的概率

**问题 2: "全部正确" 不是有意义的指标**

Precision 的计算只关心:
1. Marker 是否正确 (非 bg 判为 bg = FN, bg 判为非 bg = FP)
2. Class 是否正确 (car 判为 truck = 类别错误)
3. 中心点 (gx+dx, gy+dy) 是否在阈值内

w, h, theta 的错误 **不直接影响 precision/recall**（除非用于 IoU 匹配的评估）。

所以 "有效序列" 对于 precision 而言只有 6 token/slot: marker + class + gx + gy + dx + dy。

复合正确率 (仅 precision 相关):
- 单 slot: 0.98 × 0.85 × 0.90 × 0.90 × 0.80 × 0.80 ≈ **43%**
- 三 slot: 独立评估，不复合

**问题 3: Teacher Forcing 导致 Exposure Bias**

训练使用 teacher forcing (`git_occ_head.py:L514-519`):
```python
# 右移一位，首位补 0 (Task Token)
input_tokens = torch.cat([
    torch.zeros((NUM_CELLS, 1), dtype=torch.long, device=device),
    targets_tokens[:, :-1]
], dim=1)
```

训练时: 每个 token 的输入是 **GT 的前一个 token** (正确的)。
推理时: 每个 token 的输入是 **模型自己预测的前一个 token** (可能错误)。

这就是经典的 **exposure bias** 问题。序列越长，训练/推理的分布偏移越严重。30 token 的 exposure bias 确实比 5 token 更大。

**但**: exposure bias 的标准解决方案 (scheduled sampling, 直接 AR 训练) 成本极高，不如从改善 per-step 正确率入手。

---

## Q3: 重新评估 "不是主要瓶颈" 的结论

### Critic 的修正立场

**维持 "不是主要瓶颈"，但将其从 "可忽略" 上调为 "contributing factor"。**

| 因素 | 瓶颈贡献度 | 理由 |
|------|----------|------|
| DINOv3→BEV 投影 (4096→768) | **HIGH** | 5.3:1 降维比，信息瓶颈最大 |
| 类别不平衡 (BUG-17) | **HIGH** | car 数量远超其他类，per_class_balance 不完美 |
| 30 token AR + exposure bias | **MEDIUM** | 合法担忧，但非首要原因 |
| mini 数据量 (BUG-20) | Full 不适用 | ORCH_024 使用 Full nuScenes |
| 训练/推理 mask 不一致 (BUG-45) | **MEDIUM** | 可能导致推理时跨 cell 信息干扰 |

### 维持结论的 4 条证据 (加强版)

**证据 1: finished_mask 机制大幅缩短实际序列**

```python
# git_occ_head.py:L1100
finished_mask = torch.zeros((B * Q,), dtype=torch.bool, device=device)
# L1134
finished_mask |= (pred_abs == self.marker_end_id)
```

当 marker 预测为 END 时，该 cell 标记为 finished。后续 token **不再写入** (`pred_tokens[~finished_mask, pos_id]`, L1178)。

**实际解码长度**:
- BEV 400 cells 中，大多数是背景 → Slot 1 marker=END → 实际解码 1 token
- 有 1 个目标的 cell → Slot 1 (10 token) + Slot 2 marker=END → 实际解码 11 token
- 有 2 个目标的 cell → 21 token
- 有 3 个目标的 cell → 30 token (极少)

nuScenes 前视图中，BEV 400 cells 中有目标的通常 <50 个，且大部分只有 1 个目标。**平均实际解码长度远小于 30**。

注意: 循环仍跑 30 步直到 `finished_mask.all()` (L1104)，但 finished 的 cell 虽然参与 forward 计算，其 token **不影响评估结果**。所以 "error accumulation" 主要影响少量多目标 cell。

**证据 2: Slot 间相互独立 (在评估中)**

每个 slot 的预测结果独立匹配 GT。Slot 2 的 class 错误不会让 Slot 1 的 TP 变成 FP。评估是 per-slot per-cell 的。

Conductor 提出的 "竞争效应" (Slot 1 = car → Slot 2 偏向非 car) 是注意力层面的条件化，不是评估层面的耦合。这个效应可能存在，但需要数据证实。

**证据 3: per-step 决策空间受限**

每个 token 使用 vocab 的特定子集 (`logits[:, start:start+count]`, L1128-1175)。这不是从 230 个 vocab 中自由选择，而是从 4/11/20/21/36/10 个候选中选择。受限搜索空间意味着 per-step 正确率远高于开放式序列生成。

**证据 4 (新): 如果 AR 长度是主要瓶颈，Slot 3 应明显差于 Slot 1**

这是可验证的预测。如果 ORCH_024 @2000 数据显示 Slot 1/2/3 的 car_P 没有显著差异，则 AR 长度不是瓶颈。反之则需要重新评估。

### Conductor 的再分析中的亮点

Conductor 对 Critic 理由 2 的质疑 ("Class 只依赖 marker" 部分质疑) 有价值。通过 attention，Slot 2 的 class 预测确实可以看到 Slot 1 的 class。但这是 **feature, not bug**: 模型学到 "这个 cell 已经有一个 car，第二个 slot 更可能是不同类别" 的先验是合理的。

Conductor 对理由 4 ("DINOv3→BEV 投影未经证实") 的质疑也正确: 这确实是假说。但这个假说有更强的先验 (4096→768 的信息压缩比 5.3:1 vs AR 序列长度)。

---

## Q4: 最低成本验证方案

### 方案 A: Per-Slot 指标分析 (零成本)

**成本**: 0。只需从 ORCH_024 eval 输出中提取数据。

**方法**: 在 `decoder_inference` 返回后，分别统计:
```python
# pred_tokens shape: (B, Q, 3, 10)
for slot_idx in range(3):
    slot_markers = pred_tokens[:, :, slot_idx, 0]
    slot_classes = pred_tokens[:, :, slot_idx, 1]
    # 计算每个 slot 的:
    # - 非 END marker 的比例 (目标检出率)
    # - class 分布 (是否有 slot-dependent bias)
    # - 与 GT 的匹配 precision
```

**判断标准**:
- Slot 1 car_P ≈ Slot 2 car_P ≈ Slot 3 car_P (±10%) → **AR 长度不是瓶颈**
- Slot 3 car_P < Slot 1 car_P * 0.8 (>20% 下降) → **AR 长度有影响**

**建议**: 在 Admin 加 eval debug 输出或 Critic 写 debug 脚本在 SSD 调试目录中分析 eval 结果。

### 方案 B: 1-Slot 实验 (低成本，但有混淆因素)

**成本**: 修改 `dec_length`、训练标签生成 (`get_targets_single`)、推理解码循环。约 2-4 小时代码 + 4000 iter 训练。

**不需要改 num_vocal**: vocab 空间不变，只是每个 cell 只解码 1 slot (10 token) 而非 3 slot (30 token)。

**混淆因素**: 1-slot 意味着每个 cell 最多 1 个目标。对于密集区域 (多目标重叠)，这会 **系统性丢失 GT**，导致 recall 下降。Precision 可能因为更短序列而提升，但也可能因为更多 GT 被迫挤入单 slot 而混乱。

**结论**: 方案 B 有太多混淆因素，不推荐作为首选验证。

### 方案 C: 中间 Slot 截断 (Slot 1 only eval)

**成本**: 零代码修改，只在评估时只看 Slot 1 的结果。

**方法**: 修改 eval metric，只评估 `pred_tokens[:, :, 0, :]`。比较 "仅 Slot 1" vs "3 Slot" 的 precision。

**优势**: 隔离了 "Slot 1 在有/无后续 slot 影响下的表现"。但注意: 即使只评估 Slot 1，推理时 Slot 2/3 的解码仍然消耗了 attention 容量 (pre_kv 缓存增长)。

### 推荐验证路径

**优先级: A >> C >> B**

方案 A 是零成本的必做项。如果 A 显示 slot 间无显著差异，直接结案。如果有差异，再用 C 确认方向，最后才考虑 B。

---

## 发现的问题

### 已有 BUG 状态更新

无新 BUG。本次审计是对已有分析的深化，不涉及新的代码问题。

BUG-45 (训练/推理 mask 不一致) 与 AR 序列长度问题有交叉: 推理时 `attn_mask=None` 意味着 pre_kv 缓存中包含所有历史 token (包括其他 cell 的)，这在长序列中可能引入更多噪声。但这不改变 BUG-45 的严重性评级 (MEDIUM)。

## 逻辑验证

- [x] Teacher forcing 确认: `git_occ_head.py:L514-519`
- [x] finished_mask 机制: `git_occ_head.py:L1100, L1134, L1178`
- [x] Per-token vocab slice: `git_occ_head.py:L1128-1175`
- [x] 训练/推理不一致: 训练用 GT token (L516-519), 推理用自身预测 (L1182)

## 需要 Admin 协助验证

### 验证 1: Per-Slot 指标提取 (方案 A)
- **假设**: Slot 1/2/3 的 car precision 无显著差异 (±10%)
- **验证方法**: 从 ORCH_024 @2000 eval 输出中提取 per-slot 匹配指标
- **预期结果**: 如果 AR 长度不是瓶颈，三个 slot 的 precision 应相近
- **可选**: 在调试目录写 debug 脚本离线分析 eval 输出的 pred_tokens

## 对 Conductor 计划的评价

1. Conductor 的代码验证 (dec_length 对比) 完整且正确
2. Conductor 对 Critic 4 个理由的再分析质量高，特别是理由 2 (跨 slot class 竞争) 和理由 4 (投影瓶颈未证实)
3. 0.95^30 = 21% 的估算方向正确但粒度不够，未考虑 token 类型差异和 finished_mask 机制
4. 归因分析清晰，正确区分了 Conductor 的错误和 Critic 的判断

## 附加建议

1. **ORCH_024 @2000 eval 时必须输出 per-slot 数据**: 这是零成本的关键验证。如果不在 eval 中加 per-slot 统计，将失去一个重要的诊断机会。

2. **Exposure bias 的长远解决**: 如果未来证实 AR 长度确实有影响，考虑:
   - (a) Scheduled sampling (训练时偶尔用模型预测替代 GT input): 实现复杂度中等
   - (b) Non-autoregressive decoder for box attributes: 只对 marker+class 做 AR，gx~theta 并行预测: 架构级改动
   - (c) Deep supervision (已在代码中): 改善 per-step 正确率，间接缓解 exposure bias

3. **不要在 ORCH_024 完成前做 1-slot 实验**: 混淆因素太多，ROI 太低。先看 per-slot 数据。

---

*Critic 签发 | 2026-03-08*
