# 审计判决 — ORCH049_MARKER_PATH

## 结论: CONDITIONAL

方向正确（ORCH_048 首次打破全正饱和），但 **BUG-73 仍未修复** 且 marker 模板化的根因是 **fg/bg loss 失衡 + grid_pos_embed 空间先验**，不是 GT prefix 泄漏。必须在 ORCH_049 中修复 BUG-73 并降低空间先验权重，否则模板化无法消除。

---

## 特征流诊断结果

### ORCH_048 iter_500 — 跨样本相对差异

| 检查点                          | cross-sample 相对差异 | 判定  |
|--------------------------------|----------------------|-------|
| patch_embed_input (DINOv3投影后) | 4.96%                | ✅ 正常 |
| grid_interp_feat_layer0        | 4.92%                | ✅ 正常 |
| image_patch_encoded (backbone) | 1.68%                | ✅ 正常 |
| pre_kv_layer0_k                | 1.80%                | ✅ 正常 |
| pre_kv_last_k                  | 1.41%                | ✅ 正常 |
| decoder_out_pos0               | 2.23%                | ✅ 正常 |
| logits_pos0                    | 1.06%                | ✅ 正常 |
| pred_token_pos0 (argmax)       | 97.75% 相同          | 🔴 危险 |

- **diff/Margin 比率**: 9.7% 🔴 (≤10% 阈值)
- **Marker prediction identical**: 97.75% 🔴 (>80% 阈值)
- **NEAR: 226/400, END: 155/400** — 不再全正，但高度模板化
- **趋势**: 无多 checkpoint 对比（ORCH_048 仅 iter_500.pth）
- **诊断结论**: **图像信号到达 logits 层但无法改变 argmax 决策**。问题不在特征流（全程 >1%），而在 **决策边界被 loss 失衡固化为空间模板**。

### 注意力贡献分析

| 组件                   | 幅值   | 说明                         |
|-----------------------|--------|------------------------------|
| grid_interp_feats L0  | 0.9983 | 图像特征（输入依赖）         |
| grid_token_initial    | 0.5609 | 位置编码（输入无关）         |
| **比率 interp/grid**  | **178%** | 图像特征实际 > 位置先验    |

图像特征幅值是位置编码的 1.78 倍。模型在物理上 **接收到了充足的图像信号**，但 loss 的 fg/bg 失衡使其 **没有动力利用这些信号来区分有无目标**。

---

## 配置审查结果

- [x] 数据增强: 有 (PhotoMetricDistortion + RandomFlipBEV) → ✅
- [x] Pipeline 分离: 是 (train_pipeline ≠ test_pipeline) → ✅
- [x] Position embedding: 有 (grid_pos_embed 注入, `git.py:L337-343`) → ✅
- [x] 特征注入频率: 每步注入 (grid_interpolate_feats 每层, `git_occ_head.py` decoder_inference) → ⚠️ 仅 pos_id==0 注入
- [x] Scheduled sampling: 无 (prefix_drop_rate=0.5 替代, `git.py:L517-527`) → ✅ 等效

---

## 发现的问题

### 1. **BUG-73: marker_pos_punish=3.0 / bg_balance_weight=2.5 仍未修复** (CRITICAL, STILL OPEN)

- 严重性: **CRITICAL**
- 位置: `configs/GiT/plan_full_nuscenes_large_v1.py:L117,L129`
- 首次报告: VERDICT_ORCH048_PLAN (2026-03-16)
- 当前状态: **Conductor 在 ORCH_048 中仅修改了 pos_cls_w_multiplier (L115) 和 neg_cls_w (L114)，这两个参数在 per_class_balance 模式下被归一化消除，是空操作**
- 实际 fg/bg 比计算:
  ```
  FG 贡献: 5_classes × marker_pos_punish(3.0) = 15.0
  BG 贡献: bg_balance_weight(2.5) × marker_bg_punish(1.0) = 2.5
  fg/bg ratio = 15.0 / 2.5 = 6x
  ```
- 证据: `git_occ_head.py:L940-958` — `m_weighted = m_ce_raw * marker_weight * m_punish_weight`，在 per-class 循环中 `w_c * m_weighted[mask_c].sum() / marker_weight[mask_c].sum()` 使得 marker_weight 在分子分母中抵消，只留 m_punish_weight
- **修复**: `marker_pos_punish`: 3.0 → 1.0, `bg_balance_weight`: 2.5 → 5.0 → 使 fg/bg = (5×1.0)/(5.0×1.0) = 1x

### 2. **BUG-75: grid_pos_embed 空间先验在 fg/bg 失衡下成为模板快捷通道** (HIGH, NEW)

- 严重性: **HIGH**
- 位置: `git.py:L337-343` (grid_pos_embed 注入), `git.py:L534` (concat 到 seq_embed)
- 机制:
  1. `grid_pos_embed` 从 backbone 的 `pos_embed` 插值而来 (`git.py:L338-342`)
  2. 添加到 `grid_start_embed` 后，通过 `get_grid_feature` 在每一层注入 decoder (`git.py:L343`)
  3. Marker 是第一个预测 token (pos_id=0)，此时 decoder 输入 = task_embedding + grid_pos_embed + grid_interp_feats
  4. **没有 GT prefix** — marker 看不到任何 GT 信息，不存在 teacher forcing 泄漏
  5. 但 grid_pos_embed 编码了 **固定的空间位置**，在 fg/bg=6x 的 loss 下，模型学会 "在统计上常出现目标的空间位置预测 NEAR"
  6. 这就是 IoU=0.9459 (94.6% 相同正样本位置) + marker_same=0.9767 的根因
- **关键认知**: marker 模板不是 GT 泄漏，是 **空间频率先验 + loss 失衡** 的联合效应
- 修复建议:
  1. **首先修 BUG-73** (fg/bg 平衡) — 这是最小可执行修复
  2. 如 BUG-73 修复后仍有模板，考虑在训练时对 grid_pos_embed 施加 dropout (0.1-0.3 概率置零)
  3. 不建议完全去除 grid_pos_embed — 它对回归位置有正面作用

### 3. **BUG-72 存疑: PhotoMetricDistortion 对 frozen DINOv3 有效性** (MEDIUM, OPEN)

- 严重性: MEDIUM
- 位置: `configs/GiT/plan_full_nuscenes_large_v1.py:L303`
- 状态: 未验证但非当前阻断项
- DINOv3 ViT-L 在大规模预训练中已见过各种颜色变换，PhotoMetricDistortion 可能无法对其输出产生有意义的扰动
- 特征流确认: patch_embed_input 跨样本 4.96% 差异 — 图像确实不同，但颜色扰动占比未隔离
- **建议**: BUG-73 修复后观察效果，如 marker 仍模板化再考虑更强的增强

---

## 审计请求逐项回复

### Q1: marker_same=0.9767 是否说明 marker token 仍在走模板 shortcut?

**是的。** 但 shortcut 来源不是 GT prefix 泄漏。

Marker 是第一个预测 token (pos_id=0)。其输入路径 (`git_occ_head.py` decoder_inference):
```
input = task_embedding + grid_pos_embed + grid_interp_feats[layer_id]
```
没有任何 GT context。模板来自:
1. **grid_pos_embed** — 编码固定空间位置 (输入无关)
2. **fg/bg=6x loss 失衡** — 模型在正样本上被惩罚 6 倍于负样本，学会 "宁滥勿缺"
3. 这两个因素的交互: 在统计上高频出现目标的空间位置 (由 grid_pos_embed 编码)，模型学会无条件预测 NEAR

### Q2: occupancy 第一个 marker token 训练路径中是否通过 teacher forcing 间接泄漏 GT 前缀?

**否。** 通过代码验证:
- `git_occ_head.py:L524-528`: input_tokens 右移一位，首位补 0 (Task Token)
- `git.py:L499`: `input_seq = select_input_tokens.view(-1, ...).clone()`
- `git.py:L517-527`: prefix dropout 对 input_seq 操作，但 marker 位置 (pos_id=0) 的输入是 Task Token (0)，不含 GT 信息
- 训练时 marker 和推理时 marker 接收完全相同的输入: task_embedding + grid_pos_embed + grid_interp_feats

**结论**: Teacher forcing 影响的是 pos_id≥1 的 token (class, gx, dx, ...)，不影响 marker 预测。Prefix dropout 对 marker 无效（首位已是 Task Token）。

### Q3: 是否应将 around_weight 从 0.1 进一步降到 0.0?

**建议 0.0 或 0.05，但非当前优先级。**

around_weight=0.1 的效果 (`git_occ_head.py:L504-522`):
- center cell 权重 = base_w × 1.0
- around cell 权重 = base_w × 0.1
- ORCH_048 从 1200/1200 降到 482/1200，确认 around_weight 减少有效

降到 0.0 的利弊:
- 利: 完全消除非中心 cell 的正样本 supervision，减少模板化范围
- 弊: 可能丢失边缘覆盖的物体信息，影响大目标检测

**优先级**: 先修 BUG-73 (fg/bg 平衡)，观察效果后再决定 around_weight

### Q4: 是否应单独提高 marker/head 的负样本压力?

**不需要单独提高。** BUG-73 修复 (marker_pos_punish 3.0→1.0, bg_balance_weight 2.5→5.0) 已经将 fg/bg 从 6x 降到 1x，等效于 **将负样本压力提高 6 倍**。

如果 BUG-73 修复后 marker_same 仍 >0.90，再考虑:
- marker_bg_punish 1.0→2.0 (单独加大 bg 的 marker loss)
- 或将 bg_balance_weight 从 5.0 进一步提高到 8.0

### Q5: 是否应增加 iter_200 quick frozen-check 作为早停闸门?

**强烈推荐。** 理由:
1. ORCH_046/046_v2/047 全在 iter_500 确认 frozen，但已浪费 500 iter 训练时间
2. iter_200 的 frozen-check 可以在 ~10 分钟内给出早期信号
3. 如果 iter_200 就出现 marker_same>0.95，说明配置有根本性问题，无需等到 iter_500
4. 建议阈值: marker_same>0.95 + saturation>0.9 → 立即停训

---

## 健康检查结果

### A. Mode Collapse 检测

- [x] **数据增强检查**: PhotoMetricDistortion + RandomFlipBEV ✅
- [x] **Pipeline 分离检查**: train ≠ test ✅
- [x] **预测多样性**: marker_same=97.75% 🔴 CRITICAL — 模板预测
- [x] **Marker 分布**: NEAR=226/400 (56.5%), END=155/400 (38.8%) — 不再全正但比例固定 ⚠️
- [x] **训练趋势**: 单 checkpoint 无法判断，但与 ORCH_046_v2 (1200/1200 全正) 相比有改善

### B. Shortcut Learning 检测

- [x] **Loss-指标背离**: 无法评估（ORCH_048 @500 未跑 full val, 仅 frozen-check）
- [x] **Teacher Forcing 风险**: prefix_drop_rate=0.5 替代 scheduled sampling ✅ 等效

### C. 架构风险检测

- [x] **位置编码完整性**: grid_pos_embed 正确注入 (`git.py:L337-343`) ✅
- [x] **特征注入频率**: grid_interpolate_feats 每层注入但仅 pos_id==0 ⚠️ (设计如此)
- [x] **维度匹配**: DINOv3 ViT-L 1024 → GiT-Large 1024, 无需投影 ✅

### D. 资源浪费检测

- [x] **无效训练**: ORCH_048 已在 @500 停止，无资源浪费 ✅
- [x] **Checkpoint 价值**: iter_500 有诊断价值但不适合继续训练

---

## 对 Conductor 计划的评价

### MASTER_PLAN.md 决策审查

1. **"marker shortcut / marker teacher forcing leakage" 作为主嫌疑** — ⚠️ **方向正确但措辞不准**
   - 确认 marker 存在 shortcut learning
   - 但 **不是 teacher forcing 泄漏** — marker 作为第一个 token 没有 GT prefix 可泄漏
   - 应修正为: "marker 模板化来源 = grid_pos_embed 空间先验 + fg/bg loss 失衡 (BUG-73)"

2. **ORCH_048 执行评价** — ⚠️ **方向正确，执行有遗漏**
   - grid_assign_mode='center' ✅ 有效
   - around_weight=0.1 ✅ 有效
   - prefix_drop_rate=0.5 ✅ 有效
   - pos_cls_w_multiplier→1.0, neg_cls_w→1.0 — 🔴 **空操作，BUG-73 未修复**
   - **marker_pos_punish=3.0 和 bg_balance_weight=2.5 原封不动** — 这是 VERDICT_ORCH048_PLAN 中明确要求修复的 BUG-73，但 Conductor 未执行

3. **审计请求质量** — ✅ 问题精准
   - 正确识别了 marker_same 仍高的问题
   - 正确列出了需要审查的代码路径
   - 关于 around_weight 和 iter_200 的提问都有价值

### 优先级排序

- **BUG-73 修复应为 ORCH_049 的 P0** — 这是唯一一个可以通过改两行 config 立即验证的修复
- around_weight、grid_pos_embed dropout 等都是 P1
- iter_200 frozen-check 是流程改进，与训练并行实施

### 遗漏的风险

1. Conductor 目前没有跟踪 BUG-74 (GlobalRotScaleTransBEV 已移除，状态应标为 FIXED)
2. BUG-73 在 VERDICT_ORCH048_PLAN 中已报告，但 Conductor 未在 MASTER_PLAN 的 BUG 跟踪表中记录
3. MASTER_PLAN.md 的 BUG 跟踪表最后更新于 2026-03-15，缺少 BUG-73/74/75

---

## 需要 Admin 协助验证

### 验证 1: BUG-73 修复效果

- **假设**: marker_pos_punish=3.0 + bg_balance_weight=2.5 的 6x fg/bg 失衡是 marker 模板化的首因
- **验证方法**: 在 config 中修改 `marker_pos_punish=1.0`, `bg_balance_weight=5.0`，其余不变，训练到 iter_500 跑 frozen-check
- **预期结果**: marker_same < 0.95 (如果是首因则应显著下降)；如果仍 >0.95，说明还有其他因素

### 验证 2: iter_200 early frozen-check

- **假设**: 模板化在 iter_200 已可检测
- **验证方法**: 在 ORCH_049 中，iter_200 时立即运行 `check_frozen_predictions.py`
- **预期结果**: 如果 marker_same >0.95，立即停训重新调参

---

## ORCH_049 最小可执行修复建议

按优先级排序，Conductor 在签发 ORCH_049 时必须包含:

| 优先级 | 修改 | Config 位置 | 修改内容 | 理由 |
|--------|------|-------------|----------|------|
| **P0** | 修复 BUG-73 | L117 | `marker_pos_punish`: 3.0 → **1.0** | fg/bg 6x→1x |
| **P0** | 修复 BUG-73 | L129 | `bg_balance_weight`: 2.5 → **5.0** | fg/bg 6x→1x |
| P1 | 缩小 around | L131 | `around_weight`: 0.1 → **0.0** (或 0.05) | 进一步收紧正样本范围 |
| P1 | 早停闸门 | 训练脚本 | iter_200 运行 frozen-check | 节省 300 iter 训练时间 |
| P2 | grid_pos_embed dropout | `git.py:L343` 之后 | 训练时 10% 概率将 grid_pos_embed 置零 | 削弱空间先验依赖 |

**不推荐做的**:
- 不需要修改 marker 训练路径（已确认无 GT 泄漏）
- 不需要更改 prefix_drop_rate（0.5 已足够）
- 不需要更改 grid_assign_mode（'center' 已确认有效）

---

## 附加建议

1. **BUG 跟踪表更新**: Conductor 应在 MASTER_PLAN.md 中添加 BUG-73 (CRITICAL, OPEN), BUG-74 (HIGH, FIXED in ORCH_048), BUG-75 (HIGH, NEW)
2. **ORCH_048 应标记为 PARTIAL_SUCCESS**: 首次打破全正饱和，但 BUG-73 未修复导致 marker 仍模板化
3. **如 BUG-73 修复后 marker_same 仍 >0.90**: 下一步应考虑 grid_pos_embed dropout 或 temperature scaling marker logits

---

*诊断脚本: `GiT/ssd_workspace/Debug/Debug_20260316/debug_feature_flow_orch048.py`*
*数据来源: ORCH_048 `iter_500.pth`, 跨样本 indices [0, 1203, 2407]*
*审计时间: 2026-03-16 01:00 CDT*
