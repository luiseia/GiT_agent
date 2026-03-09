# 审计判决 — CEO_ARCH_QUESTIONS

## 结论: CONDITIONAL

**条件**: Conductor 对 Q2 (Deep Supervision) 的实现难度判断完全错误。代码已存在，只需改一行配置。优先级排序需修正。

---

## 逐题审计

### Q1: 30 Token AR 解码是否是 Precision 瓶颈？

**判决: Conductor 方向正确，但分析有两处事实错误。**

#### 错误 1: "GiT 原始论文序列更长"

Conductor 称 "原始 GiT 在 COCO 检测上有效，序列更长"。**这是错误的**。

原始 GiT detection head (`git_det_head.py:L432-439`) 每个 query 解码序列:
- pos_id=0: grid token (跳过, L433 `continue`)
- pos_id=1: class label
- pos_id=2~5: box coordinates (cx, cy, w, h)
- 总共 **5 个有意义的 token/query**

OCC head 每个 query 解码 **30 token** (3 slot × 10 token)。这是 GiT 所有变体中 **最长的 per-query 序列**，是 detection 的 6 倍。Conductor 拿 "全图数百个目标" 来类比是偷换概念——GiT 的 "长序列" 是指 query 数量多 (全图扫描)，而非单个 query 内 token 数量多。

参考: `git_det_head.py:L433-436` vs `git_occ_head.py:L1103` (`range(30)`)

#### 错误 2: 未区分 "per-cell 并行" 与 "全局序列"

30-step AR 是 **per-cell 独立解码**。400 个 cell 在 batch 维度并行 (`B*Q = B*400`)，互不干扰。

```python
# git_occ_head.py:L1098
pred_tokens = torch.full((B * Q, 30), self.ignore_id, ...)
```

所以 "error accumulation" 仅在单个 cell 的 30 步内发生，不会跨 cell 传播。CEO 的担忧范围应限定在: **Slot 3 (pos 20-29) 是否因前 20 步的错误累积而退化**。

#### Critic 评估

30 token AR 序列长度 **不是当前 precision 的主要瓶颈**。理由:

1. **Marker token (pos 0/10/20)** 是每个 slot 的第一个 token，只需从 4 个候选 (NEAR/MID/FAR/END) 中选择。这个决策几乎不受前面 slot 影响——它主要取决于 cell 位置与目标的空间关系。

2. **Class token (pos 1/11/21)** 是第二个 token，只依赖 marker。跨 slot 的 class 预测是独立的空间事件。

3. **几何属性 (pos 2-9)** 是同 slot 内部的精细化，误差累积有限 (每个属性用独立的 logits 子空间，见 L1142-1175 的 slice 操作)。

4. **真正的 precision 瓶颈**: BUG-15 (Precision 瓶颈) 更可能源于 DINOv3→BEV 投影层的信息瓶颈 (4096→2048→768 的降维比 5.3:1)，而非解码长度。

**不改 num_vocal 的缩短方案**: 理论上可以合并 dx+dy 或 theta_group+theta_fine 为单 token (扩大对应 bin 数)，但这需要重新设计量化方案并重训。**不建议现阶段尝试**。

**Slot 位置验证**: 同意 Conductor 建议。从 ORCH_024 @2000 eval 中提取 per-slot precision/recall:
```python
# 在 decoder_inference 返回后，按 slot 位置分析:
# slot_1: pred_tokens[:, :, 0, :]  (pos 0-9)
# slot_2: pred_tokens[:, :, 1, :]  (pos 10-19)
# slot_3: pred_tokens[:, :, 2, :]  (pos 20-29)
# 如果 slot_3 的 car_P 显著低于 slot_1 (>20% 差距)，才值得进一步调查
```

---

### Q2: Deep Supervision (深度监督)

**判决: Conductor 的核心判断 "实现需 1-2 天" 完全错误。代码已存在，只需改一行。**

#### BUG-43: Conductor 未读代码就给出实现估算

**严重性: MEDIUM (影响优先级排序)**

**位置**: `GiT/mmdet/models/detectors/git.py:L386-388`

```python
# [修改] 关闭 Deep Supervision (回归单层 Loss)
loss_out_indices = [len(self.backbone.layers) - 1]
```

**事实**:
1. Deep supervision 的完整基础设施 **已经在代码中实现**
2. `git.py:L536-538`: 根据 `loss_out_indices` 自动收集指定层的 logits
3. `git_occ_head.py:L600-608`: `multi_apply` 自动对每层计算 loss
4. `git_occ_head.py:L620-624`: 辅助 loss 命名为 `d0.loss_cls`, `d0.loss_reg` 等
5. 注释明确写 "关闭 Deep Supervision" — 说明之前启用过

**启用方法**: 只需将 L388 改为:
```python
loss_out_indices = [8, 10, 11]  # base 架构 12 层, 在第 9/11/12 层加监督
```

不需要任何其他代码修改。Conductor 说 "中等实现复杂度，需修改 Transformer decoder forward 和 loss 计算" 是 **完全没读过这段代码** 的表现。

#### 显存估算

当前架构: `arch='base'` → 12 层 Transformer。

辅助 loss 的额外显存:
- 每个辅助层需计算: `pred_seq_logits = seq_embed @ tasks_tokens_embedding.T`
- 形状: `(B, Q, 30, num_vocal)` = `(2, 400, 30, 230)` = 5.52M floats
- 每个辅助头: ~22 MB (FP32) 或 ~11 MB (混合精度)
- 2 个辅助头总增量: ~44 MB

当前使用 36-37 GB/GPU，余量 ~11 GB。**辅助 loss 的显存增量可以忽略不计 (<0.5%)**。

Conductor 的 "1-2 个辅助头可行" 判断结论正确，但推理路径错误 (他以为需要新建辅助预测头，实际上复用同一个 vocab embedding)。

#### 潜在风险

**BUG-44: Deep supervision 共享 vocab embedding 的适用性问题**

**严重性: LOW (理论层面)**

所有辅助层使用同一个 `tasks_tokens_embedding` 做投影。对于浅层 (如第 9 层)，表征可能尚未成熟到足以被这个 embedding 正确解码。但这恰恰是 deep supervision 的目的——强迫中间层也学习有意义的表征。

实际上 GiT 原始论文 (DETR-like 架构) 在检测任务中就使用了 deep supervision，效果验证过。Occ 任务中值得一试。

#### 建议

- **优先级应从 "第 3" 提升到 "第 1"**: 零代码修改，只改一行配置。可以在 ORCH_024 结束后的下一次训练中直接启用。
- **推荐层**: `[8, 10, 11]` (12 层架构的最后 4 层)
- **辅助 loss 权重**: 默认与主 loss 相同 (权重=1.0)。建议先不改，看 DDP 训练是否自动收敛。如需降低权重，需在 `loss_by_feat` 中加系数。

---

### Q3: Slot Attention Mask

**判决: CEO 的直觉有价值，但 Conductor 遗漏了一个关键的训练/推理不一致问题。**

#### 当前 Attention Mask 机制 (训练 vs 推理)

**训练** (`git.py:L603-647`, `get_attn_mask`):
- 标准 causal mask: `torch.triu(ones(embed_len, embed_len), diagonal=1)` (L638)
- 跨 cell 隔离: 不同 cell 的 token 互相屏蔽 (L640-646)
- 每个 cell 内部: token i 可以 attend to token 0..i-1 (标准因果)

**推理** (`git_occ_head.py:L1114-1117`):
```python
curr_x, pre_kv_update = layer.token_forward(
    ..., attn_mask=None, ...)  # ← None!
```
- 因果性通过 pre_kv 缓存隐式实现 (新 token 的 Q 对所有历史 K/V attend)
- **没有跨 cell 隔离**——推理时每个 cell 的新 token 可以 attend to 所有其他 cell 的历史 KV

#### BUG-45: 训练/推理 Attention Mask 不一致

**严重性: MEDIUM (可能影响推理质量)**

**位置**: `git_occ_head.py:L1116` (`attn_mask=None`)

训练时: Slot 2 的 gx 只能看到 **同 cell** 内 Slot 1 的所有 token + Slot 2 的 marker/class。
推理时: Slot 2 的 gx 可以看到 **所有 cell** 已解码的全部 token (通过 pre_kv 缓存)。

这个不一致是否有影响取决于:
1. `global_only_image=True` (L163) — 训练时 global attention 层不处理 grid token，只处理 image
2. Window attention 层中 grid token 按空间分配到 window，跨 window 的 grid 本来就看不到

对比 `git_det_head.py:L417-427`: detection head 推理时 **显式构建** attn_mask。OCC head 跳过了这一步，可能是简化实现时的疏忽。

**建议**: 在 occ_head 推理中也构建显式 mask (参考 det_head 实现)，确保训练/推理一致。

#### CEO 方案 A (Hard Mask) vs Conductor 方案 B (Soft Weights)

**Critic 推荐: 方案 A (Hard Mask)，但带修改。**

Conductor 的方案 B ("降低跨 slot attention 权重") 听起来优雅但实现困难:
- 需要引入可学习的 attention bias 参数
- 这些参数在 pre-trained ViT 中不存在，需要从头学习
- 引入新的超参数 (bias 初始化值、学习率)

方案 A 更简洁:
- 修改 `get_attn_mask` 中的 causal mask 即可
- 当前 causal mask 是 `embed_len × embed_len` 的上三角矩阵
- CEO 方案: 在跨 slot 的几何属性位置加额外 mask
- 实现: 在 L638 之后，对 mask 的特定位置设为 1

**具体实现** (训练 mask 修改):
```python
# 当前 (git.py:L638):
self_token_attn_mask = torch.triu(torch.ones(embed_len, embed_len), diagonal=1)

# CEO 修改: 在 slot 边界处加额外 mask
# embed_len = 1(grid) + 1(task) + 30(tokens) = 32
# slot 结构: [grid, task, M1,C1,gx1,gy1,dx1,dy1,w1,h1,tg1,tf1, M2,C2,..., M3,C3,...]
# 需要 mask: Slot2 的几何 token (pos 14-21) 不看 Slot1 的几何 token (pos 4-11)
#            Slot3 的几何 token (pos 24-31) 不看 Slot1/2 的几何 token
# 但保留: 所有 slot 的 marker/class 始终可见
```

#### 跨 slot 信息的价值

Conductor 正确指出: 同 cell 内多目标可能有空间约束。但这个约束在 BEV occ 中是 **弱约束**:
- 同 cell 不同 slot 的目标可以重叠 (不同高度的目标投影到同一 BEV cell)
- "不重叠" 约束更适用于 2D 检测，不适用于 3D→BEV 投影

**结论**: 跨 slot 几何信息的价值有限，CEO 的 hard mask 值得尝试。

#### Mini 验证 2000 iter 是否够？

**不够。** 根据 BUG-42/CEO 问题 4 的教训，mini 上任何 <3000 iter 的实验都不可靠。但 structured mask 的效果 **不适合在 mini 上验证**:
- Mini 数据太少 (323 图)，大部分 cell 只有 1 个目标 → Slot 2/3 几乎都是 END marker → mask 差异体现不出来
- **应直接在 Full nuScenes 上验证**，附加在 deep supervision 等改动中一起测试

---

### Q4: 评判标准

**判决: Conductor 的 4 条规则基本合理，但需要修正。**

#### 规则审查

| 规则 | Conductor 原文 | Critic 修正 |
|------|---------------|------------|
| 1 | 单次 <5%: 不决策 | **同意**。但需指定: 5% 是相对变化 (relative)，非绝对变化 |
| 2 | 单次 5-15%: 条件性 | **修改**: 应为 **连续方向一致** 才条件性。单次 5-15% 在 mini 上可能是噪声 |
| 3 | 单次 >15%: 可能有意义 | **同意**，但加条件: 排除前 500 iter 的任何数据 |
| 4 | 连续 2 次同向 >5%: 可结论 | **修改**: 两个 eval 点之间需间隔 ≥500 iter，否则相关性太高 |

#### 补充规则

**规则 5 (Critic 新增)**: 永远不从 mini 实验做架构决策。Mini 只能做:
- 代码正确性验证 (loss 是否正常下降)
- 明确的 BUG 发现 (如 BUG-41 全程 warmup)
- 粗略趋势判断 (收敛速度对比)

**规则 6 (Critic 新增)**: Full nuScenes 上，第一个有意义的 eval 点应在 **1 full epoch 之后** (batch_per_gpu=2 × 4GPU = 8 samples/iter, 28130/8 ≈ 3516 iter/epoch)。所以 **Full 上 @2000 的评判也是偏早的**——但作为趋势参考可接受。

#### 统计检验

**不需要。** Bootstrap CI 适用于有多次独立实验的场景。当前每个配置只跑一次，没有统计基础。Visual trend analysis 足够。

#### Full nuScenes 多少 iter 有决策价值？

- @2000 (~0.57 epoch): 趋势参考，不做架构决策
- @4000 (~1.14 epoch): 第一个可信评估点
- @8000 (~2.27 epoch): 可做架构级决策
- @20000 (~5.68 epoch): 可做最终性能判断

---

### Q5: 综合优先级排序

**Conductor 排序有重大错误。修正如下:**

| 排名 | 提案 | 实现难度 | 理由 |
|------|------|---------|------|
| 1 | **Q2 Deep Supervision** | **零** (改一行配置) | Conductor 说 "1-2天"，实际 5 分钟。应在 ORCH_024 后第一个实验中启用 |
| 2 | **Q4 评判标准** | 零 (流程) | 立即写入 MASTER_PLAN.md |
| 3 | **方案 D (历史 occ 2帧)** | 高 (1-2周) | 最大潜在收益，需要代码开发 |
| 4 | **Q3 Attention Mask** | 低 (2-4h) | 与 deep supervision 一起测试 |
| 5 | **方案 E (LoRA)** | 中 (2-3天) | DINOv3 frozen 的替代微调方案 |
| 6 | **Q1 解码长度** | 高 (架构级) | 仅在 ORCH_024 证明有问题时考虑 |
| 7 | **方案 F (多尺度)** | 中 | 低优先级 |

**关键修正**: Q2 从第 3 位升至第 1 位 (零成本)，Q3 从第 1 位降至第 4 位 (需配合 deep supervision 测试)。

**ORCH_024 后第一个实验建议**:
```
plan_full_nuscenes_gelu_v2.py:
  - Deep supervision: loss_out_indices = [8, 10, 11]
  - 其他配置不变
  - 这给出一个无风险的 baseline 对比
```

---

## 发现的问题

### BUG-43: Conductor 未查代码即估算 Deep Supervision 实现难度

- **严重性**: MEDIUM
- **位置**: AUDIT_REQUEST 第 59 行 "实现复杂度: 中等"
- **实际情况**: `git.py:L386-388` 已有完整实现，只需改一行
- **影响**: 导致优先级排序错误 (Q2 被排在 Q3 之后)

### BUG-44: Deep supervision 各层共享 vocab embedding

- **严重性**: LOW (理论层面)
- **位置**: `git.py:L537` — `seq_embed @ tasks_tokens_embedding.transpose(0, 1)` 用于所有层
- **影响**: 中间层表征可能不够成熟，辅助 loss 初期可能噪声较大
- **修复建议**: 暂不修。实验观察辅助 loss 曲线再决定

### BUG-45: OCC Head 推理时 attn_mask=None (训练/推理不一致)

- **严重性**: MEDIUM
- **位置**: `git_occ_head.py:L1116` — `attn_mask=None`
- **对比**: `git_det_head.py:L417-427` 推理时构建显式 mask
- **影响**: 推理时 cell 间的 pre_kv 可能引入训练中不存在的跨 cell 信息
- **修复建议**: 在 occ_head 的 `decoder_inference` 中参考 det_head 实现构建显式 mask

## 逻辑验证

- [x] 30 token AR: 确认 per-cell 并行 (B*Q), 非全局序列
- [x] Deep supervision: 确认代码存在 (`git.py:L536-538`, `git_occ_head.py:L600-624`)
- [x] Attention mask: 确认训练 (causal+cross-cell isolation) vs 推理 (None) 不一致
- [x] 架构层数: `arch='base'` = 12 层 (plan_full_nuscenes_gelu.py:L197)

## 需要 Admin 协助验证

### 验证 1: Deep Supervision 快速验证
- **假设**: 启用 deep supervision (layers [8,10,11]) 能改善收敛速度
- **验证方法**: 在 ORCH_024 结束后，仅修改 `git.py:L388` 为 `loss_out_indices = [8, 10, 11]`，其他配置不变，跑 Full nuScenes 4000 iter
- **预期结果**: 如果有效，@2000 的 car_P 应高于 ORCH_024 同 iter 的值

### 验证 2: Per-slot 性能分析
- **假设**: Slot 3 精度不显著低于 Slot 1
- **验证方法**: 从 ORCH_024 @2000 eval 输出中提取 per-slot 指标
- **预期结果**: Slot 1/2/3 的 precision 差异 <20%

### 验证 3: 推理 mask 一致性检查
- **假设**: 加显式 mask 后推理结果应有变化
- **验证方法**: 在 occ_head 推理中添加与训练一致的 mask，对比有/无 mask 的 eval 指标
- **预期结果**: 如果 BUG-45 有影响，加 mask 后 precision 应改善

## 对 Conductor 计划的评价

1. **Q1 分析**: 方向正确但有事实错误 (原始 GiT 序列长度误导)。结论 "低优先级" 正确。
2. **Q2 分析**: **重大失误**。未读代码就估算实现难度，导致优先级被低估。
3. **Q3 分析**: 分析质量最高。方案 A/B 的对比合理，但遗漏了训练/推理 mask 不一致 (BUG-45)。
4. **Q4 分析**: 数据引用准确，规则设计合理。
5. **优先级排序**: 需重大修正 — Q2 应排第一 (零成本)。

## 附加建议

1. **ORCH_024 后的实验计划应为**:
   - 实验 A: 仅启用 deep supervision (1 行改动, 风险零)
   - 实验 B: deep supervision + structured attention mask (2 个改动同时测试)
   - 这样 A 是 baseline, B 是 ablation, 可以隔离 mask 的贡献

2. **不建议在 ORCH_024 完成前写代码**: 等 @2000 和 @4000 eval 结果出来，根据 ORCH_024 @2000 决策矩阵 (compact_critic.md) 确定方向后再动手。唯一例外: deep supervision 配置改动可以提前准备 (就一行)。

3. **将 BUG-45 列入 ORCH_024 后的修复清单**: 训练/推理 mask 不一致可能是当前推理质量的一个隐性瓶颈。

---

## 下一个 BUG 编号: BUG-46

*Critic 签发 | 2026-03-08*
