# 审计判决 — ORCH059_LOSS_INIT

## 结论: CONDITIONAL

**条件**: 实施 BUG-82 (marker negative bias init) 作为 ORCH_059 唯一改动。不得同时修改 Focal Loss 或 bg_balance_weight。

---

## 特征流诊断结果

本次审计无新训练运行。引用 ORCH_055 (2-GPU DDP, ORCH_049 精确配置) 和 ORCH_057/058 (marker_no_grid_pos) 的已有诊断数据。

### ORCH_055 特征流 (最近的 HEALTHY checkpoint)

| 检查点 | cross-sample 相对差异 | 判定 |
|--------|----------------------|------|
| patch_embed_input | 4.96% | ✅ |
| grid_interp_feat_layer0 | ~5% | ✅ |
| image_patch_encoded | ~3% | ✅ |
| decoder_out_pos0 | ~2% | ✅ |
| logits_pos0 | ~1% | ✅ |
| pred_token_pos0 | 88.7% 相同 (@100), 98.8% 相同 (@500) | ⚠️→🔴 |

- **diff/Margin @100**: 54.6% ✅ — 模型在利用图像特征
- **diff/Margin @500**: 4.2% 🔴 — 图像信号无法改变决策
- **趋势**: 急剧减小 (54.6% → 4.2%)，@300→@400 发生相变
- **诊断结论**: 模型在 @100 健康，但 LR 升高后 grid_pos_embed 空间先验 shortcut 主导，@400 后不可逆

### ORCH_057/058 (marker_no_grid_pos=True)

| iter | marker_same | saturation | 结果 |
|------|-------------|-----------|------|
| 100 | 0.992 🔴 | 1.000 🔴 | ALL-POSITIVE DEAD ON ARRIVAL |

- **无法运行特征流诊断** — 模型在 iter 40 即 reg_loss=0，从未产生有意义的预测
- **对比 ORCH_055 @100**: marker_same=0.887 (HEALTHY) vs 0.992 (DEAD)
- **结论**: 移除 grid_pos_embed 后，所有 cell 输入趋同 → 立即收敛到全正平凡解

---

## 配置审查结果

- [x] **数据增强**: 有 (PhotoMetricDistortion + RandomFlipBEV) → ✅
- [x] **Pipeline 分离**: 是 (train_pipeline ≠ test_pipeline) → ✅
- [x] **Position embedding**: 有 (grid_pos_embed 注入 grid_start_embed, `git.py:L355`) → ✅
- [x] **特征注入频率**: 每步 (P3 修复后 grid_interpolate_feats 注入每个 pos_id, `git_occ_head.py:L1137-1138`) → ✅
- [x] **Scheduled sampling**: 无显式 scheduled sampling, 但 prefix_drop_rate=0.5 提供类似功能 (`git.py:L512-537`) → ⚠️ MEDIUM (可接受)

---

## 发现的问题

### 1. **BUG-81**: Focal Loss alpha 配置方向完全错误 — FG 权重 3× 于 BG

- **严重性**: HIGH
- **位置**: `configs/GiT/plan_full_nuscenes_large_v1.py:L123` (`focal_alpha_marker = 0.75`)
- **问题**:
  - 当前配置: FG markers 得到 α=0.75, BG marker (end) 得到 1-α=0.25
  - 这给 FG 的权重是 BG 的 **3 倍**
  - RetinaNet 标准实践: α=0.25 for FG, 0.75 for BG (因为 BG 是多数类但 focal weight 已自动降权)
  - **如果天真地开启 Focal Loss，all-positive collapse 会加速**
- **代码证据**: `git_occ_head.py:L759-763`
  ```python
  alpha_t = torch.where(safe_targets < C - 1,
                        logits.new_tensor(alpha),      # FG: 0.75
                        logits.new_tensor(1.0 - alpha)) # BG: 0.25
  ```
- **修复**: 若要开启 Focal Loss，`focal_alpha_marker` 必须设为 0.25 (或更低)。`focal_alpha_cls` 同理。

### 2. **BUG-82**: Marker 输出层无 bias — 初始化结构性偏向 all-positive (75%)

- **严重性**: CRITICAL
- **位置**: `git.py:L589` (训练), `git_occ_head.py:L1148` (推理)
- **问题**:
  - Logits 计算方式: `logits = x @ vocabulary_embed.T` — **纯点积，无 bias 项**
  - Marker 词表: 4 token (near=179, mid=180, far=181, end/bg=182)
  - 3 个 FG token vs 1 个 BG token → **初始 P(FG) = 75.0%, P(BG) = 25.0%**
  - 4 个 marker embedding 的余弦相似度 ≥ 0.94 (BERT 连续 token)，logit 差异极小
  - 经验证: 对 1000 个随机 hidden state, **100% 预测 FG** — 无任何初始多样性
- **诊断脚本验证**: `ssd_workspace/Debug/Debug_20260316/debug_marker_init_bias.py`
  ```
  P(NEAR)=0.2500, P(MID)=0.2501, P(FAR)=0.2500, P(END)=0.2500
  P(FG) = 0.7500 ± 0.0011, P(BG) = 0.2500 ± 0.0011
  100% of cells predict FG at initialization
  ```
- **根因分析**:
  1. 模型初始化时全部 cell 预测 FG (P=75%)
  2. Warmup LR 极低 (iter 40 时 LR=1.05e-6)，梯度信号微弱
  3. Per-class balance 下 BG 每样本梯度仅 FG 的 1/39 (39x 稀释)
  4. 在足够的 BG 梯度积累之前，模型已锁定 all-positive 模式
  5. ORCH_055 中 grid_pos_embed 在早期提供了空间多样性 (marker_same=0.887)，延缓了崩塌
  6. ORCH_058 移除 grid_pos_embed 后，所有 cell 输入趋同，iter 40 即崩塌
- **修复方案**: 在 OccHead 中添加可学习 marker bias:
  ```python
  # git_occ_head.py __init__ (L214 之后):
  import math
  # RetinaNet-style prior: P(bg) ≈ 0.80 at init
  self.marker_init_bias = nn.Parameter(torch.tensor([-2.0, -2.0, -2.0, +0.5]))

  # loss_by_feat_single (L857, L931): marker_logits 计算后加 bias
  marker_logits = logits_flat[:, 0, marker_start : marker_start + 4] + self.marker_init_bias

  # decoder_inference (L1155): 推理路径也加 bias
  marker_logits = logits[:, self.marker_near_id : self.marker_near_id + 4] + self.marker_init_bias
  ```
  - bias 值 [-2.0, -2.0, -2.0, +0.5] 产生初始 P(BG)=80.2%, P(each FG)=6.6%
  - 等价于 RetinaNet 的 `b = -log((1-π)/π)` prior π=0.20
  - 可作为 nn.Parameter 自适应学习，训练后期 bias 会调整到数据分布
- **影响范围**: 仅影响 marker (pos_id%10==0) 的 logit 计算，不触及 class/regression/theta 路径

### 3. **BUG-83**: Per-class balance 下 BG 每样本梯度极度稀释

- **严重性**: MEDIUM
- **位置**: `git_occ_head.py:L944-960` (CE mode), `git_occ_head.py:L871-886` (Focal mode)
- **问题**:
  - BG cells: `marker_weight = neg_cls_w = 1.0` (`git_occ_head.py:L439`)
  - FG center cells: `final_w ≈ IBW * energy_scale * 1.0 * 1.0 ≈ 1.0` (`git_occ_head.py:L514`)
  - Per-class balance 归一化后:
    - 每 FG 样本梯度权重: `w_c / (total_weight × count_c)` = 0.050
    - 每 BG 样本梯度权重: `bg_w / (total_weight × bg_count)` = 0.001282
    - **FG/BG per-sample = 39x**
  - 典型场景: 10 FG cells vs 390 BG cells, 50/50 aggregate loss 但 per-sample 极不平衡
  - 结果: 共享模型参数 (backbone, decoder) 主要被 FG 梯度驱动
- **诊断脚本验证**: `debug_marker_init_bias.py`
  ```
  Per-FG-sample gradient weight: 0.050000
  Per-BG-sample gradient weight: 0.001282
  FG/BG per-sample ratio: 39.0x
  ```
- **修复**: BUG-82 的 negative bias init 间接缓解此问题（初始 CE(bg) 降低，CE(fg) 升高，梯度方向正确）。若仍不足，可考虑提升 `neg_cls_w` 或增加 `bg_balance_weight`，但参考 ORCH_049-053 历史，这些参数空间极窄。

---

## ORCH_059 最小改动优先级排序

| 优先级 | 改动 | 代码量 | 风险 | 预期效果 |
|--------|------|--------|------|----------|
| **#1 ⭐** | **BUG-82: marker negative bias init** | ~5 行 | 极低 — 仅影响 marker logit | 初始 P(BG) 从 25% → 80%; 打破 all-positive 初始化; 让模型从"无目标"开始学习 |
| #2 | BUG-81: 修正 focal_alpha 后开启 Focal Loss | 1 行 config | 中 — 需同时修正 alpha 方向 | Focal γ=2 自动降权 easy BG samples; 但不如 bias init 直接 |
| #3 | 调整 bg/fg balance 公式 | 0 行 config | **高** — ORCH_049-053 证明可行窗口极窄 | 不推荐单独做; 已证明无法根本解决 |

**强烈建议**: ORCH_059 仅实施 #1 (negative bias init)，**不要**同时开启 Focal Loss 或改 bg_balance_weight。原因:
1. 单变量实验原则 — 一次只改一件事，才能确定因果
2. BUG-82 是 root cause (初始化偏向 all-positive)，直接修复比间接补偿更可靠
3. Focal Loss 的 alpha 配置有 BUG-81，需要先修正才能安全使用
4. bg_balance_weight 调参空间已穷尽 (ORCH_049-053)

---

## 逻辑验证

- [x] **梯度守恒**: marker_init_bias 是可学习参数，梯度正常传播。不改变 CE loss 的数学形式，只添加 logit offset → 守恒 ✅
- [x] **边界条件**: bias 值 [-2, -2, -2, +0.5] 使初始 P(each FG)=6.6%, P(BG)=80.2%。随训练 bias 会被梯度调整，不会永久锁定 → 安全 ✅
- [x] **数值稳定性**: softmax(-2, -2, -2, +0.5) = [0.066, 0.066, 0.066, 0.802]。无 overflow/underflow 风险 → 稳定 ✅
- [x] **训练/推理一致性**: 需在 loss_by_feat_single (L857/L931) 和 decoder_inference (L1155) 两处同时添加 bias → 必须检查实现

---

## 需要 Admin 协助验证

### 验证 1: Marker negative bias init 实验

- **假设**: 初始化 P(FG)=75% 是 all-positive 崩塌的主因；添加 negative bias init 使 P(BG)=80% 后，模型能在 warmup 期维持 BG 预测，避免全正平凡解
- **验证方法**:
  1. 在 `git_occ_head.py` 的 `__init__` 中添加 `self.marker_init_bias = nn.Parameter(torch.tensor([-2.0, -2.0, -2.0, +0.5]))`
  2. 在 `loss_by_feat_single` (L857 和 L931) 的 `marker_logits` 计算后加 `+ self.marker_init_bias`
  3. 在 `decoder_inference` (L1155) 的 `marker_logits` 计算后加 `+ self.marker_init_bias`
  4. **保持所有其他参数不变** (marker_no_grid_pos=False, 回到 ORCH_055 配置)
  5. 2-GPU DDP 训练, 多点 frozen-check @100, @200, @300, @400, @500
- **预期结果**:
  - @100: marker_same < 0.95 (非 all-positive), saturation < 0.90
  - @200-300: 仍维持多样性 (区别于 ORCH_055 @200 的 marker_same=0.962)
  - @500: 如果 bias init 有效, marker_same 应显著优于 ORCH_055 @500 (0.988)
- **成功标准**: @500 时 marker_same < 0.95 且 diff/Margin > 20%

### 验证 2 (可选): marker_no_grid_pos + bias init 组合

- **假设**: ORCH_058 的失败是因为初始化偏向 all-positive + 所有 cell 输入趋同的双重打击。如果 bias init 修复了初始化问题，marker_no_grid_pos 可能重新变得可行
- **验证方法**: 在验证 1 确认有效后，重复实验但开启 `marker_no_grid_pos=True`
- **预期结果**: @100 时 marker_same < 0.95 (区别于 ORCH_058 的 0.992)

---

## 健康检查结果

### A. Mode Collapse 检测
- [x] **数据增强**: 有 (PhotoMetricDistortion + RandomFlipBEV) → ✅
- [x] **Pipeline 分离**: 是 → ✅
- [x] **预测多样性**: ORCH_055 @100 marker_same=0.887 ✅, @500 marker_same=0.988 🔴; ORCH_058 @100 marker_same=0.992 🔴 → **MODE COLLAPSE 已确认**
- [x] **Marker 分布**: ORCH_058 @100 1200/1200 all-positive → 🔴 CRITICAL
- [x] **训练趋势**: ORCH_055 marker_same 0.887→0.988 (恶化); ORCH_058 iter 40 即 reg_loss=0 → 🔴 CRITICAL (collapse 在加速)

### B. Shortcut Learning 检测
- [x] **Loss-指标背离**: ORCH_055 loss 下降但 marker 模板化 → ⚠️ HIGH (grid_pos_embed shortcut)
- [x] **Teacher Forcing 风险**: 无 scheduled sampling, 但 prefix_drop_rate=0.5 → ⚠️ MEDIUM (可接受)

### C. 架构风险检测
- [x] **位置编码完整性**: grid_pos_embed 正确注入 → ✅ (但 BUG-75 仍 OPEN: 这是模板化来源)
- [x] **特征注入频率**: 每步注入 (P3 修复) → ✅
- [x] **维度匹配**: DINOv3 ViT-L 1024 → GiT-Large 1024, 无需投影 → ✅

### D. 资源浪费检测
- [x] **无效训练**: 无训练进程运行 → N/A
- [x] **Checkpoint 价值**: ORCH_055 @100 是唯一有价值的 checkpoint (HEALTHY)

---

## 对 Conductor 计划的评价

### 决策合理性

**正确的判断**:
1. 认识到"所有直接改 grid_pos_embed 的路线都已证伪" — 准确
2. "grid_pos_embed 在早期帮助维持预测多样性" — ORCH_058 实验证实
3. "转向 loss/init 审计" — 正确的战略转向

**需要修正的认知**:
1. MASTER_PLAN 中"方向 C: Focal Loss 是否更适合作为首个最小改动" — **不是**。当前 focal_alpha_marker=0.75 配置方向错误 (BUG-81)，天真开启会加速崩塌。Focal Loss 应排在 bias init 之后
2. "bg_balance_weight、marker_bg_punish 在 warmup 低 LR 阶段是否实际提供了足够的背景梯度" — **提供了 aggregate 50/50，但 per-sample 稀释 39x**。问题不在 bg_balance_weight 不够大 (已经 5.0)，而在于初始化已经把模型推向 all-positive

### 优先级修正

| Conductor 原排序 | Critic 修正排序 | 原因 |
|---|---|---|
| 方向 A, B, C 并列 | **A (bias init) >> B (balance) > C (focal)** | A 是 root cause 修复; B 已穷尽; C 有 BUG-81 |

### 遗漏的风险

1. **BUG-81 (focal_alpha 方向错误)** 在 MASTER_PLAN 中未被识别。如果 Admin 在不修正 alpha 的情况下开启 Focal Loss，会直接恶化问题
2. ORCH_059 如果同时做多个改动 (bias + focal + balance)，将无法区分哪个有效。**必须单变量实验**

---

## 附加建议

### 1. bias 值选择的理论依据

RetinaNet (Lin et al., 2017) 使用 `b = -log((1-π)/π)` 初始化 classifier bias，其中 π=0.01 (稀有前景先验):
- π=0.01 → b = -4.6 (极端背景偏向)

我们的场景: ~80% BG cells, ~20% FG cells，比检测任务的 FG 比例高得多:
- π=0.20 → b_end - b_fg = ln(12) ≈ 2.5
- 建议: bias = [-2.0, -2.0, -2.0, +0.5] → P(BG)=80.2%, 与实际数据分布匹配

如果实验仍 all-positive, 可加大 bias 差值:
- 更激进: [-3.0, -3.0, -3.0, +1.0] → P(BG)=98.2%
- 但过大可能导致 FG 永远学不出来, 建议从 [-2.0, -2.0, -2.0, +0.5] 开始

### 2. 长期方向: 二元 marker head

当前 4-class marker (near/mid/far/end) 的根本问题是 3:1 结构失衡。长期可以考虑:
- 将 marker 改为 2-class: FG (有目标) vs BG (无目标)
- 近/中/远信息用 depth slot 的回归值隐式编码
- 这消除了 3:1 结构偏差，使 FG/BG 平衡更自然

但这是架构变更，不适合作为 ORCH_059 的最小改动。

---

## BUG 状态总表

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-73 | CRITICAL | PARTIAL | fg/bg 调参空间穷尽 (ORCH_049-053) |
| BUG-75 | HIGH | OPEN | grid_pos_embed 空间先验 shortcut |
| BUG-77 | CRITICAL | CONFIRMED | cell-level dropout 破坏定位 |
| BUG-78 | HIGH | CONFIRMED | 单 GPU batch 致 mode collapse |
| BUG-79 | MEDIUM | CONFIRMED | 训练/推理 grid_token 注入不对称 |
| BUG-80 | LOW | NEW | decoder_inference 参数名误导 |
| **BUG-81** | **HIGH** | **NEW** | **focal_alpha_marker=0.75 方向错误，FG 权重 3× BG** |
| **BUG-82** | **CRITICAL** | **NEW** | **marker 无 bias init，初始 P(FG)=75%，100% all-positive** |
| **BUG-83** | **MEDIUM** | **NEW** | **per_class_balance 下 BG per-sample 梯度稀释 39x** |
