# 审计判决 — ORCH046_V2_AT500

## 结论: STOP — 训练算法层面的问题，非超参数可解决

BUG-69 (lr_mult) 和 BUG-62 (clip_grad) 修复已确认生效:
- grad_norm: mean=130 (vs ORCH_045 的 3007) — **下降 23x**
- adapt_layers lr=5e-05, lr_mult=1.0 — 训练日志确认
- reg_loss 从未归零 (vs ORCH_045 的 9.5% 归零)
- 训练 loss: 15.08 → 3.95 — 模型**确实在学习**

**但模型在推理时 100% frozen (IoU=1.0, marker_same=1.0, saturation=1.0)。比 ORCH_045 更极端。**

这不是超参数问题。模型学到了正确的东西 (频率先验)，但学到了错误的策略 (忽略图像)。**必须改变训练算法才能解决。**

---

## 核心诊断: 为什么修复 lr_mult 后模型仍然 frozen？

### 训练 vs 推理的根本矛盾

| 维度 | 训练 | 推理 | 差异影响 |
|------|------|------|---------|
| **上下文** | GT tokens (teacher forcing) | 模型自身预测 | 模型不需要用图像区分场景, 因为 GT 已提供所有信息 |
| **优化目标** | P(token_t \| image, GT_0..GT_{t-1}) | P(token_t \| image, pred_0..pred_{t-1}) | 训练时 image 是冗余信号 — GT context 已足够预测下一个 token |
| **空间布局** | 固定 BEV 坐标系 | 固定 BEV 坐标系 | 模型可记忆每个位置的频率先验 |

**关键推理**: 在 teacher forcing 下, 模型学习 `P(token_t | GT_0..GT_{t-1})`。由于 GT context 已经提供了丰富的信息 (前一个 token 是什么类别、什么位置), 模型可以不看图像, 仅通过 GT 序列的统计规律预测下一个 token。这是经典的 **shortcut learning**:

```
目标: P(token_t | image, GT_0..t-1)
捷径: P(token_t | GT_0..t-1) ≈ P(token_t | position_t)  ← 忽略 image
原因: position_t 的边缘分布在训练集中高度一致 (大多数位置的最常见类别是 pedestrian)
```

### 训练指标 vs 推理指标的背离 (smoking gun)

| 指标 | 值 | 含义 |
|------|-----|------|
| 训练 loss @500 | 3.95-15.8 | 在下降 — 模型在学习 |
| reg_loss @500 | 1.55-3.16 | 始终非零 — 位置回归在工作 |
| grad_norm @500 | 49-382, mean=130 | 健康范围, clip=50 几乎不激活 |
| **推理 IoU** | **1.0000** | **100% frozen — 完全忽略图像** |
| **推理 marker_same** | **1.0000** | **所有样本完全相同** |
| **推理 saturation** | **1.000** | **1200/1200 slots 全正** |

训练在改善但推理完全 frozen → **模型在训练中学到了与推理无关的模式 (GT context 的统计规律)**

### 对比 ORCH_024 baseline (为什么它没有 collapse)

| 维度 | ORCH_024 | ORCH_046_v2 | 影响 |
|------|----------|-------------|------|
| Backbone | DINOv2 7B frozen | DINOv3 ViT-L frozen | ViT-L 特征可能更弱 |
| Model | GiT-Base (768-dim) | GiT-Large (1024-dim, 30 layers) | 更大模型更容易 shortcut |
| Data augmentation | 无 | PhotoMetricDistortion | 颜色增强不破坏空间先验 |
| 特征提取 | 单层 L16 | 多层 [5,11,17,23] + adapt | 复杂度增加 |
| @2000 car_R | 0.627 | 0 | ORCH_024 在学习 |

**ORCH_024 没有 collapse 的可能原因**: GiT-Base 768-dim 模型容量较小, 无法轻松记忆频率先验, 被迫利用图像特征。GiT-Large 1024-dim + 30 layers 有足够容量学习 shortcut。

---

## BUG-45 重新评估: attn_mask=None — 非真正 BUG

### 分析

经深入代码审查, `attn_mask=None` 在推理中是**正确的**:

1. 推理使用 KV cache 方式 (`git_occ_head.py:L1124-1128`)
2. `pre_kv_list[layer_id]` 在每步更新, 累积之前的 token KV
3. 当前 token 的 query 只能 attend 到 KV cache 中的内容
4. KV cache 只包含 [image patches + text + token_0..token_{t-1}] — 自然没有未来 token
5. 因此不需要 causal mask

**对比训练**: 训练用 full sequence + causal mask (`git.py:L613-657`), 推理用 KV cache + no mask — 这是标准的 decoder 实现方式, **数学上等价**。

### 结论

~~BUG-45~~ **不是真正的 bug**。Conductor 和之前的审计中将其标记为问题是错误的。推理端 attn_mask=None 是 KV cache 自回归的正确实现。

---

## 发现的问题

### 1. **BUG-71: Teacher Forcing Mode Collapse — GiT-Large 架构不耐受** (CRITICAL)
- **描述**: GiT-Large (1024-dim, 30 layers) 有足够模型容量学习 shortcut (位置频率先验)。在 100% teacher forcing + 无空间增强条件下, 模型在 iter_500 即完全收敛到固定输出。token_drop_rate=0.3 和 PhotoMetricDistortion 无法阻止此捷径
- **严重性**: CRITICAL — 阻断所有后续实验
- **位置**: 训练算法层面, 非特定代码位置
- **修复方案 (二选一或组合)**:
  1. **RandomFlip3D (水平翻转)**: 打破 BEV 空间频率先验。翻转图像+翻转 3D annotations (x→-x, rotation→π-rotation)。位置: `train_pipeline` 中 `LoadAnnotations3D_E2E` 之后、`GenerateOccFlowLabels` 之前
  2. **Scheduled Sampling**: 训练时以概率 p 使用模型自身预测代替 GT token。位置: `git.py:L503-517` 附近, 在 token embedding 之后进行采样

### 2. **BUG-72: PhotoMetricDistortion 对 frozen DINOv3 的有效性存疑** (MEDIUM)
- **描述**: PhotoMetricDistortion 改变亮度/对比度/饱和度/色相。DINOv3 ViT-L 经过大规模预训练, 对颜色扰动具有一定鲁棒性。特征流诊断显示 patch_embed_input 的 cross-sample diff 仅 2.37% — 虽然非零但偏低
- **严重性**: MEDIUM
- **位置**: `configs/GiT/plan_full_nuscenes_large_v1.py:L301` — PhotoMetricDistortion
- **影响**: 颜色增强可能无法为 frozen DINOv3 提供足够的训练信号多样性
- **验证方法**: 对比加/不加 PhotoMetricDistortion 的 DINOv3 特征差异

### 3. BUG-69 修复确认 (已修复)
- adapt_layers lr=5e-05, lr_mult=1.0 ✅
- 训练日志 `19:19:06` 确认
- grad_norm 从 3007 降至 130 ✅

### 4. BUG-62 修复确认 (已修复)
- clip_grad=50.0 ✅
- grad_norm range 49-382, clip 几乎不激活 ✅

### 5. BUG-64 修复确认 (已修复)
- bert_embed type='bert-large', pretrain_path='/home/UNT/yz0370/projects/GiT/bert_embed_large.pt' ✅

---

## 健康检查结果

### A. Mode Collapse 检测

- [x] **数据增强检查**: PhotoMetricDistortion 有 ✅, 但无空间增强 (RandomFlip) → 🔴 **CRITICAL**
- [x] **Pipeline 分离检查**: train ≠ test → ✅
- [x] **预测多样性**: 100% identical → 🔴 **CRITICAL** (比 ORCH_045 更极端)
- [x] **Marker 分布**: 1200/1200 positive, saturation=1.0 → 🔴 **CRITICAL**
- [x] **训练趋势**: iter_500 已 100% frozen, 无需等更久 → 🔴 **CRITICAL**

### B. Shortcut Learning 检测

- [x] **Loss-指标背离**: 训练 loss 下降 (15→4) 但推理 100% frozen → 🔴 **CRITICAL** — 经典 shortcut learning
- [x] **Teacher Forcing 风险**: 100% TF + 大模型容量 → 🔴 **CRITICAL**

### C. 架构风险检测

- [x] **位置编码完整性**: P2 fix 在位 → ✅
- [x] **特征注入频率**: P3 fix 在位 (每步注入) → ✅
- [x] **维度匹配**: 4096→2048→GELU→1024 → ✅
- [x] **学习率匹配**: adapt_layers lr_mult=1.0 → ✅

### D. 资源浪费检测

- [x] **无效训练**: 模型在学习 shortcut, 继续训练无意义 → 🔴 建议停止
- [x] **Checkpoint 价值**: iter_500 已 frozen, 无可用 checkpoint → 无

---

## 特征流诊断结果

未对 ORCH_046_v2 iter_500 运行完整特征流诊断。但基于 check_frozen_predictions.py 结果:
- Positive IoU=1.0000, marker_same=1.0000 → 比 ORCH_045 @2000 (IoU=0.990) 更极端
- 预计特征流结果与 ORCH_045 类似但更严重

可能的原因是 BERT-large 预训练权重提供了更结构化的初始 logit 分布, 使得模型更快收敛到频率先验。

---

## 对 Conductor 计划的评价

### Conductor 的修复正确但不充分

Conductor 正确执行了 VERDICT_ORCH046_PLAN 中的修复:
- BUG-69 ✅ (adapt_layers lr_mult)
- BUG-62 ✅ (clip_grad=50)
- BUG-64 ✅ (bert-large pretrain)
- val_interval=500 ✅ (早期诊断)

**但缺少了 P1 优先级的修复**:
- RandomFlip3D ❌ (未实现)
- Scheduled Sampling ❌ (未实现)

VERDICT_ORCH046_PLAN 明确将 RandomFlip3D 和 Scheduled Sampling 列为 P1 (仅次于 P0 的 lr_mult 和 clip_grad)。Conductor 只修了 P0, 没做 P1, 就启动了训练。这再次浪费了 GPU 时间。

### 关键教训

**超参数修复 (lr, clip_grad) 解决了梯度流问题, 但不解决训练算法问题。** Mode collapse 的根因是:
1. Teacher forcing → 模型不需要用图像
2. 无空间增强 → 位置频率先验稳定不变
3. 大模型容量 → 容易学到 shortcut

必须**同时**解决这三个问题中的至少两个。

---

## 修正后的行动方案

| 优先级 | 行动 | 复杂度 | 说明 |
|--------|------|--------|------|
| **MUST** | **RandomFlip3D** | 中 (1-2天) | 水平翻转图像 + 翻转 3D annotations (x→-x, rot→π-rot)。在 `GenerateOccFlowLabels` 之前执行。这是打破空间先验的**唯一**有效方法 |
| **MUST** | **Scheduled Sampling** (或降低模型容量) | 中 (0.5-1天) | 以概率 p=0.3 用模型预测替代 GT token。或: 用 GiT-Base 768-dim 替代 GiT-Large 1024-dim |
| 建议 | 先用 GiT-Base 测试 RandomFlip3D | 低 | GiT-Base + 7B 已证明能学习; 先在此架构上验证 RandomFlip3D 效果 |

### 替代方案: 回退到 GiT-Base + 7B

如果 RandomFlip3D 实现耗时过长, **可考虑暂时回退到已证明可工作的架构**:
- GiT-Base (768-dim) + DINOv2 7B frozen + 多层特征
- 这个组合在 ORCH_034/035 中 car_R=0.81, 证明可以学习
- 先在这个基础上验证 RandomFlip3D 的效果
- 然后再迁移到 GiT-Large + ViT-L

---

## 需要 Admin 协助验证

### 假设 1: RandomFlip3D 能打破 frozen predictions
- **假设**: 水平翻转破坏 BEV 空间先验, 迫使模型利用图像区分翻转 vs 非翻转场景
- **验证方法**: 实现 RandomFlip3D, 在 ORCH_046_v2 config 上从零训练 500 iter, 运行 check_frozen_predictions.py
- **预期结果**: IoU < 0.95, marker_same < 0.95, saturation < 0.95

### 假设 2: GiT-Base 不会 collapse
- **假设**: GiT-Base (768-dim) 容量不足以学习 shortcut, 即使无 RandomFlip3D 也能正常训练
- **验证方法**: 使用 GiT-Base config (如 ORCH_024 类似配置) + PhotoMetricDistortion + 当前 multi-layer DINOv3 设置, 训练 2000 iter
- **预期结果**: car_R > 0 at @2000, bg_FA < 0.5

---

## 附加建议

1. **STOP 当前训练**: ORCH_046_v2 已确认 frozen, 继续训练浪费 GPU。立即停止并释放 GPU 给 RandomFlip3D 实现和测试

2. **不要再尝试纯超参数调整**: lr_mult, clip_grad, bert_embed 都已修复。问题不在超参数, 在训练算法。下次 ORCH 必须包含 RandomFlip3D 或 Scheduled Sampling

3. **自动 kill switch 再次建议**: 在 iter_500 eval 后如果 saturation > 0.9, 自动停止训练。不要等人工检查

4. **BUG-45 降级**: 经深入分析, attn_mask=None 在 KV cache 推理中是正确的。建议 Conductor 在 MASTER_PLAN 中将 BUG-45 标记为 "NOT A BUG — KV cache 自然保证因果性"

---

*审计时间: 2026-03-15 20:30-21:05*
*审计人: claude_critic*
*训练日志: nohup_orch046_v2.out (iter 10-500)*
*诊断: check_frozen_predictions.py @iter_500*
