# 审计判决 — ORCH048_PLAN

## 结论: CONDITIONAL — Conductor 的方案方向正确但有两项致命盲区

Conductor 正确识别了需要修改的方向 (去掉 GlobalRotScaleTransBEV、降低前景权重、加强 scheduled sampling)。但**有两个 CRITICAL 问题 Conductor 没有意识到**:

1. **BUG-73**: `pos_cls_w_multiplier` 和 `neg_cls_w` 的修改在 `use_per_class_balance=True` 模式下**完全无效** — 被归一化消除
2. **BUG-74**: marker_pos_punish=3.0 + bg_balance_weight=2.5 的组合才是真正的 fg/bg 失衡控制点

**如果只按 Conductor 当前方案执行 (改 pos_cls_w_multiplier 和 neg_cls_w)，ORCH_048 100% 会再次 frozen。**

---

## 核心发现: 为什么 ORCH_047 的 BEV 增强无效？

### A. 增强本身没有 Bug — 问题在损失函数

RandomFlipBEV 和 GlobalRotScaleTransBEV 的实现**几何上正确**:
- `bev_augmentation.py:L40`: 图像水平翻转 ✅
- `bev_augmentation.py:L43-49`: Y→-Y, yaw→-yaw ✅
- `bev_augmentation.py:L52-63`: 相机外参调整 (F_L @ R_sl @ F_C, F_L @ t_sl, K[0,2] flip) ✅
- `bev_augmentation.py:L100-131`: GlobalRotScaleTransBEV 旋转+缩放 + 外参调整 ✅

**但增强改变的是 "输入数据分布"，而不是 "模型的学习激励"。** 模型可以找到一个固定输出，使其在所有增强变体上的**加权平均损失最小化**。关键是 "加权" — 当前损失函数极度偏向前景，模型最优策略仍然是 "全正预测"。

### B. 数学证明: pos_cls_w_multiplier 和 neg_cls_w 在 per_class_balance 模式下无效

`git_occ_head.py:L936-952` (CE 模式, per_class_balance=True):

```python
# Foreground class c:
m_weighted = m_ce_raw * marker_weight * m_punish_weight
loss_c = w_c * m_weighted[mask_c].sum() / marker_weight[mask_c].sum()
# 展开: = w_c * sum(ce_i × weight_i × punish) / sum(weight_i)
# 当 punish 对 mask_c 内所有元素相同时:
# = w_c * punish * sum(ce_i × weight_i) / sum(weight_i)
# = w_c * punish * weighted_avg(ce_i)
# **注意: weight 在分子分母同时出现，被消除**

# Background:
loss_bg = bg_balance_weight * m_weighted[bg_mask].sum() / marker_weight[bg_mask].sum()
# = bg_balance_weight * bg_punish * sum(ce_i × neg_cls_w) / sum(neg_cls_w)
# = bg_balance_weight * bg_punish * avg(ce_i)
# **neg_cls_w 也被消除**
```

**结论**: 无论 `pos_cls_w_multiplier` 设为 1.0 还是 100.0, 无论 `neg_cls_w` 设为 0.3 还是 1.0，per_class_balance 归一化会把它们完全消除。**Conductor 提议的两项核心修改是空操作。**

### C. 真正控制 fg/bg 平衡的三个参数

实际的 marker loss 公式 (`git_occ_head.py:L936-952`):

```
loss_marker = [Σ_c(w_c × marker_pos_punish × avg_ce_c) + bg_balance_weight × marker_bg_punish × avg_ce_bg]
              / [Σ_c(w_c) + bg_balance_weight]
```

当前值:
- `marker_pos_punish = 3.0` (`git_occ_head.py:L229`)
- `marker_bg_punish = 1.0` (`git_occ_head.py:L230`)
- `bg_balance_weight = 2.5` (`config:L129`)

假设 5 个活跃类, 每个 w_c≈1.0:
- **FG 有效权重**: 5 × 3.0 = **15.0**
- **BG 有效权重**: 2.5 × 1.0 = **2.5**
- **FG/BG 比**: 15.0 / 2.5 = **6x**

**背景在 marker loss 中只有 14.3% 的发言权。模型学到: "预测所有 slot 为正样本" 比 "正确区分 fg/bg" 的加权损失更低。这就是 saturation=1.0 的直接原因。**

---

## 发现的问题

### 1. **BUG-73: per_class_balance 归一化使 pos_cls_w_multiplier 和 neg_cls_w 失效** (CRITICAL)
- **描述**: `use_per_class_balance=True` 时，marker loss 的每类分支用 `m_weighted.sum() / marker_weight.sum()` 归一化。`marker_weight` 中包含的 `pos_cls_w_multiplier` 和 `neg_cls_w` 在分子分母同时出现，被消除。Conductor 提议将 `pos_cls_w_multiplier` 从 5.0 降到 1.0、将 `neg_cls_w` 从 0.3 升到 1.0 — **这两个修改在当前代码下完全无效**
- **严重性**: CRITICAL — 如果不解决，ORCH_048 会重复 ORCH_047 的失败
- **位置**: `git_occ_head.py:L936-952` (CE + per_class_balance 分支)
- **修复方案**:
  - **方案 A (推荐)**: 修改真正有效的参数:
    - `marker_pos_punish`: 3.0 → **1.0**
    - `bg_balance_weight`: 2.5 → **5.0**
    - 新 FG/BG 比: (5×1.0) / (5.0×1.0) = **1.0x** (平衡)
  - **方案 B**: 同时降低 marker_pos_punish 到 1.5, bg_balance_weight 到 5.0
    - 新 FG/BG 比: (5×1.5) / (5.0×1.0) = **1.5x** (轻微 fg 偏向, 合理)
  - **方案 C (激进)**: 完全去掉 `use_per_class_balance`, 直接用 pos_cls_w_multiplier 和 neg_cls_w 控制
    - 此时 Conductor 的修改才会生效, 但失去类间平衡能力

### 2. **BUG-74: GlobalRotScaleTransBEV 不改变图像 — "虚拟增强"** (HIGH)
- **描述**: `GlobalRotScaleTransBEV` 只修改 3D box 坐标和相机外参 (`bev_augmentation.py:L108-131`), **不修改图像**。DINOv3 (frozen) 处理的是原始图像, 特征不变。BEV-to-image 映射虽然改变 (通过外参调整), 但图像本身未旋转/缩放。对比 `RandomFlipBEV` 实际翻转图像 (`bev_augmentation.py:L40`) — 这才是真增强
- **严重性**: HIGH
- **位置**: `bev_augmentation.py:L94-133`
- **影响**: 标签分布改变但视觉特征不变, 对 frozen model 来说是纯噪声
- **修复建议**: 去掉 GlobalRotScaleTransBEV, 只保留 RandomFlipBEV (**与 Conductor 方案一致**)

### 3. center_weight 和 around_weight 是死参数 (LOW)
- **描述**: config 中 `center_weight=2.0, around_weight=0.5` 在 `__init__` 中被存储 (`git_occ_head.py:L242-243`) 但**从未在 target 构造或 loss 计算中使用**
- **严重性**: LOW
- **位置**: `git_occ_head.py:L242-243`, `config:L131-132`
- **影响**: 无功能影响, 仅代码卫生问题

---

## 对 Conductor ORCH_048 方案的逐项评价

| # | Conductor 提议 | 判定 | 理由 |
|---|---------------|------|------|
| 1 | 去掉 GlobalRotScaleTransBEV | ✅ **正确** | BUG-74: 不改图像, 对 frozen 模型是纯噪声 |
| 2 | 保留 RandomFlipBEV | ✅ **正确** | 实际翻转图像, DINOv3 特征不同 |
| 3 | grid_assign_mode='center' | ⚠️ **可以但非关键** | 减少 fg cells/object, 间接改善 fg/bg 比。但 BUG-51 的 center fallback 仍有效 (L516-520), 小物体不会完全丢失。不反对此变更, 但根因不在这里 |
| 4 | pos_cls_w_multiplier → 1.0 | 🔴 **无效** | BUG-73: per_class_balance 归一化完全消除此参数 |
| 5 | neg_cls_w → 1.0 | 🔴 **无效** | BUG-73: 同上 |
| 6 | 更强的 scheduled sampling / prefix dropout | ✅ **正确方向** | 但需具体方案, 见下方建议 |
| — | **遗漏: marker_pos_punish** | 🔴 **必须修改** | 6x fg/bg 比的核心因素, Conductor 未识别 |
| — | **遗漏: bg_balance_weight** | 🔴 **必须修改** | 背景在 loss 中 14% 发言权, 必须提升 |

---

## 健康检查结果

### A. Mode Collapse 检测
- [x] **数据增强检查**: train_pipeline 有 PhotoMetricDistortion + RandomFlipBEV + GlobalRotScaleTransBEV → ✅ 有增强
- [x] **Pipeline 分离检查**: train_pipeline ≠ test_pipeline → ✅
- [x] **预测多样性**: ORCH_047 @500 全部 1200/1200 frozen, IoU=1.0, marker_same=1.0 → 🔴 **CRITICAL**
- [x] **Marker 分布**: saturation=1.000 → 🔴 **CRITICAL**
- [x] **训练趋势**: ORCH_045→046_v2→047 三轮连续 frozen, 增强+超参修复均无效 → 🔴 **CRITICAL** (指向 loss/training 算法层面问题)

### B. Shortcut Learning 检测
- [x] **Loss-指标背离**: ORCH_047 训练 loss 下降 (11→4-5) 但推理 frozen → 🔴 **CRITICAL**
- [x] **Teacher Forcing 风险**: 100% TF, token_drop_rate=0.3 不充分 → 🔴 **HIGH**

### C. 架构风险检测
- [x] **位置编码完整性**: P2 fix 在位 → ✅
- [x] **特征注入频率**: P3 fix (每层注入 grid_interpolate + grid_token) → ✅
- [x] **维度匹配**: 4096→2048→GELU→1024 → ✅
- [x] **学习率匹配**: adapt_layers lr_mult=1.0 (ORCH_047 日志确认) → ✅

### D. 资源浪费检测
- [x] **无效训练**: ORCH_047 @500 已确认 frozen, 训练已手动停止 → ✅ (已处理)
- [x] **Checkpoint 价值**: iter_500 frozen, 无可用 checkpoint → 无

---

## ORCH_047 训练日志分析

ORCH_047 日志 (`nohup_orch047.out`):
- grad_norm: 40-350, mean≈120 → 健康范围 ✅
- loss: cls 从 8→1-2 (波动大), reg 保持 2-3.5 → loss 在下降但输出 frozen
- adapt_layers lr_mult=1.0 确认 ✅
- 训练模式与 ORCH_046_v2 几乎相同 → **增强对训练动态无显著影响**
- **关键观察**: loss_cls 偶尔飙升到 11-16 (如 iter 160, 320, 500), 这是增强带来的 target 变化导致的 loss 波动, 但不足以打破 frozen 输出

---

## 修正后的 ORCH_048 行动方案

### 必须修改 (MUST)

| 修改 | 当前值 | 建议值 | 位置 | 理由 |
|------|--------|--------|------|------|
| **marker_pos_punish** | 3.0 | **1.0** | `config:L117` | 消除 marker loss 中的 fg 过度偏向 |
| **bg_balance_weight** | 2.5 | **5.0** | `config:L129` | 给背景 50% 发言权, 从 14.3% 提升到 50% |
| **去掉 GlobalRotScaleTransBEV** | 有 | 无 | `config:L304` 删除该行 | BUG-74: 不改图像的虚拟增强 |
| **Slot-level masking** | token_drop_rate=0.3 (per-token) | **slot_drop_rate=0.3 (per-slot)** | `git.py:L503-507` | 见下方代码 |

### 建议修改 (SHOULD)

| 修改 | 当前值 | 建议值 | 位置 | 理由 |
|------|--------|--------|------|------|
| grid_assign_mode | 'overlap' (默认) | 'center' (显式) | `pipeline_common` dict | 减少 fg cells, 与 Conductor 一致 |
| pos_cls_w_multiplier | 5.0 | **1.0** | `config:L115` | 虽然被归一化消除, 但改为 1.0 避免误导, 代码卫生 |
| neg_cls_w | 0.3 | **1.0** | `config:L114` | 同上, 避免误导 |

### Slot-level Masking 实现 (推荐代码)

`git.py:L503-507` — 替换当前 per-token corruption 为 slot-level masking:

```python
# 当前 (per-token, 不够强):
# drop_mask = torch.rand_like(input_seq.float()) < self.token_drop_rate
# random_tokens = torch.randint(0, num_vocab, input_seq.shape, device=input_seq.device)
# input_seq = torch.where(drop_mask, random_tokens, input_seq)

# 推荐 (slot-level, 更强):
if self.token_drop_rate > 0 and self.mode == 'occupancy_prediction':
    num_vocab = tasks_tokens_embedding.shape[0]
    n_cells, seq_len = input_seq.shape
    SLOT_LEN = 10
    n_slots = seq_len // SLOT_LEN  # 3
    # 每个 slot 整体决定是否 mask (不是每个 token 独立决定)
    slot_mask = torch.rand(n_cells, n_slots, device=input_seq.device) < self.token_drop_rate
    drop_mask = slot_mask.repeat_interleave(SLOT_LEN, dim=1)
    # 处理 seq_len 不整除的尾部
    if drop_mask.shape[1] < seq_len:
        drop_mask = F.pad(drop_mask, (0, seq_len - drop_mask.shape[1]), value=False)
    elif drop_mask.shape[1] > seq_len:
        drop_mask = drop_mask[:, :seq_len]
    random_tokens = torch.randint(0, num_vocab, input_seq.shape, device=input_seq.device)
    input_seq = torch.where(drop_mask, random_tokens, input_seq)
```

**效果**: 当 slot 被 mask 时, 10 个 token 全部替换为随机值。模型无法从 GT context 中提取任何该 slot 的信息, **必须**使用图像特征来预测该 slot。比 per-token corruption 强得多, 因为 per-token 情况下 70% 的 GT context 仍然完整。

### 新 fg/bg 平衡计算

修改后 (marker_pos_punish=1.0, bg_balance_weight=5.0):
- FG: 5 classes × 1.0 × 1.0 = **5.0**
- BG: 5.0 × 1.0 = **5.0**
- **FG/BG 比: 1.0x (完美平衡)**

修改前:
- FG: 5 × 1.0 × 3.0 = **15.0**
- BG: 2.5 × 1.0 = **2.5**
- **FG/BG 比: 6.0x (严重失衡, 导致全正预测)**

---

## 需要 Admin 协助验证

### 假设 1: Loss 权重修复能打破 frozen predictions
- **假设**: marker_pos_punish=1.0 + bg_balance_weight=5.0 消除 fg/bg 梯度不对称, 模型不再收敛到全正输出
- **验证方法**: 在 ORCH_048 config 上从零训练 500 iter, 运行 check_frozen_predictions.py
- **预期结果**: IoU < 0.95, saturation < 0.95, marker_same < 0.95

### 假设 2: Slot-level masking 比 per-token corruption 更有效
- **假设**: slot_drop_rate=0.3 迫使模型在 30% 的 slot 上必须使用图像特征
- **验证方法**: 对比 per-token vs slot-level masking 在 @500 的 frozen check
- **预期结果**: slot-level masking 的 saturation 更低

### 假设 3: pos_cls_w_multiplier 修改确认无效
- **验证方法**: 在 ORCH_048 config 上仅修改 pos_cls_w_multiplier=1.0 和 neg_cls_w=1.0 (**不改 marker_pos_punish 和 bg_balance_weight**), 从零训练 500 iter
- **预期结果**: 仍然 frozen (IoU≈1.0, saturation≈1.0) — 确认 BUG-73

---

## 对 Conductor 计划的评价

### 方向正确, 但缺乏代码深度分析

Conductor 正确识别了:
1. GlobalRotScaleTransBEV 可能有害 → ✅ 正确 (BUG-74)
2. 前景/背景权重需要重平衡 → ✅ 方向正确
3. 需要更强的 scheduled sampling → ✅ 正确
4. 不改 filter_invisible → ✅ 遵从 CEO

Conductor 未识别的:
1. **pos_cls_w_multiplier 和 neg_cls_w 在 per_class_balance 模式下无效** — 这是本次审计最重要的发现
2. **marker_pos_punish 才是真正的 fg 偏向控制点** — Conductor 的方案完全没提到这个参数
3. **bg_balance_weight 决定背景在 loss 中的发言权** — Conductor 也没提到

### 关键教训

**连续 4 轮实验 (ORCH_045, 046_v2, 047, 048_plan) 都聚焦在 "增强" 和 "超参数" 上, 但从未深入分析损失函数的归一化行为。** 这导致:
1. pos_cls_w_multiplier 改了 3 次 (20→5→拟议1) 但从来没有效果
2. neg_cls_w 改了 2 次但也从来没有效果
3. 真正有效的 marker_pos_punish 和 bg_balance_weight 从未被触及

**教训**: 在改参数之前, 先用数学验证参数是否真的能影响 loss 梯度。不要凭直觉改参数。

---

## 附加建议

1. **不要同时改太多**: ORCH_048 应分两步:
   - **Step 1**: 只改 marker_pos_punish=1.0 + bg_balance_weight=5.0 + slot-level masking, 训练 500 iter 验证
   - **Step 2**: 如果 Step 1 不够, 再加 grid_assign_mode='center'

2. **添加 BG 梯度监控**: 在训练日志中输出 bg_marker_loss 占 total_marker_loss 的比例。如果 < 20%, 说明 bg 仍被压制

3. **考虑 ORCH_024 回退**: ORCH_024 (GiT-Base + 7B frozen + 单层 L16) 在 @8000 有 car_R=0.718, off_cx=0.045。如果 ORCH_048 的 loss 修复仍不奏效, 回退到已证明可工作的架构, 在那个基础上验证 loss 修复

4. **不要在 ORCH_048 中改 marker_bg_punish**: 保持 1.0。bg_balance_weight=5.0 已足够平衡

---

*审计时间: 2026-03-16 00:15-01:00*
*审计人: claude_critic*
*训练日志: nohup_orch047.out (iter 10-500)*
*代码版本: GiT commit 3fc2e3e (ORCH_047)*
*关键代码引用: git_occ_head.py:L936-952 (per_class_balance 归一化), bev_augmentation.py:L40-65 (RandomFlipBEV), bev_augmentation.py:L94-133 (GlobalRotScaleTransBEV), config:L114-129 (权重参数)*
