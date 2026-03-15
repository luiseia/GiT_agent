# 审计判决 — ORCH045_AT2000

## 结论: STOP

**ORCH_045 训练已确认失败，必须立即终止（训练已自行停止，GPU 0,2 已释放）。**

模型在 @2000 已进入单类崩塌（single-class collapse），至 @4000-6000 恶化至完全崩塌。
token_drop_rate=0.3 作为 anti-mode-collapse 措施被证明**完全无效**。
BUG-62 (clip_grad=10.0) 未修复即启动 ORCH_045 是致命决策失误。

---

## 特征流诊断结果

### diagnose_v3_precise.py — Cross-Sample Feature Flow

| 检查点                          | cross-sample 相对差异 | identical% | 判定 |
|--------------------------------|----------------------|------------|------|
| patch_embed_input (DINOv3 特征) | 2.37%               | 0.00%      | ✅ 正常 |
| grid_interp_feat_layer0        | 2.37%               | 0.00%      | ✅ 正常 |
| grid_interp_feat_last          | 1.06%               | 0.00%      | ✅ 正常 |
| image_patch_encoded (backbone) | 1.06%               | 0.00%      | ✅ 正常 |
| grid_token_initial             | 0.00%               | 100.00%    | 🔴 FROZEN (learned embedding, expected) |
| pre_kv_layer0_k                | 1.05%               | 0.01%      | ✅ 正常 |
| pre_kv_last_k                  | 0.51%               | 0.01%      | ⚠️ 偏弱 |
| decoder_out_pos0               | 1.63%               | 0.00%      | ✅ 正常 |
| logits_pos0                    | 1.04%               | 0.00%      | ✅ 正常 |
| pred_token_pos0 (marker argmax)| 2.22%               | **97.25%** | 🔴 FROZEN |
| pred_token_pos1 (class argmax) | 0.13%               | **98.75%** | 🔴 FROZEN |
| pred_token_pos2 (gx argmax)    | 0.13%               | **98.75%** | 🔴 FROZEN |

### diagnose_v3c_single_ckpt.py — diff/Margin 分析

- **diff/Margin 比率**: 13.8% → ⚠️ 图像信号偏弱
- **Marker prediction identical**: 99.50% → 🔴 CRITICAL
- **NEAR changed**: 0/400 → 模型完全忽略近端图像差异
- **END changed**: 25/400 (6.25%) → 仅极少数远端位置受图像影响

### 诊断结论

**这是与 P2+P3 @6000 不同类型的 mode collapse。**

P2+P3 @6000 的崩塌原因是架构缺陷（位置编码跳过 + 特征仅首步注入），图像信号在 continuous feature 层就已经完全丧失。

ORCH_045 @2000 的崩塌更隐蔽：
- continuous features (logits, decoder_out) 有 1-3% 的 cross-sample 变化 → 图像信号确实到达了输出层
- 但 argmax 后 97-99% 的预测相同 → **信号太弱，不足以改变 argmax 决策**
- 模型学到了一个压倒性的默认模式（几乎所有格子预测为 pedestrian），微弱的图像信号无法撼动

diff/Margin=13.8% 意味着 logit 差异只占 top1-top2 margin 的 13.8%。图像导致的 logit 变化远小于 top1 和 top2 之间的 gap，因此 argmax 结果不变。

---

## Frozen Prediction 诊断 (check_frozen_predictions.py)

```
  Avg positive slots: 1097/1200 (91.5%)
  Positive IoU (cross-sample): 0.9897  → 🔴 > 0.95
  Marker same rate: 0.9905             → 🔴 > 0.95
  Coord diff (shared pos): 0.001902    → 🔴 < 0.01
  Saturation: 0.922                    → 🔴 > 0.9

  VERDICT: FROZEN PREDICTIONS DETECTED
```

**全部 4 个指标超过阈值。** 模型对 1200 个 grid cell 中的 1097 个（91.5%）输出正预测，且预测在不同输入间几乎完全一致。

---

## BEV 可视化诊断 (visualize_pred_vs_gt.py)

| Sample | GT objects | Pred detections | TP  | FP  | FN  |
|--------|-----------|-----------------|-----|-----|-----|
| 0      | 5         | 1098            | 9   | 357 | 0   |
| 1      | 10        | 1083            | 58  | 303 | 24  |
| 2      | 5         | 1104            | 20  | 348 | 13  |
| 3      | 17        | 1095            | 30  | 335 | 11  |
| 4      | 25        | 1107            | 35  | 334 | 12  |

**BEV 图直接观察**: 所有 5 个样本的 Pred 面板**完全一致** — 相同的 bounding box 出现在相同的位置，与 GT 场景无关。GT 面板差异巨大（5 vs 25 objects, 不同空间分布），但模型输出是同一张固定模板。

---

## Eval 指标 — 崩塌时间线

| Iter  | ped_R  | bg_FA  | car_R | off_cx | off_cy | off_w  | off_h  | off_th | 状态 |
|-------|--------|--------|-------|--------|--------|--------|--------|--------|------|
| @2000 | 0.7646 | 0.9208 | 0     | 0.2792 | 0.2683 | 0.3016 | 0.3254 | 0.1916 | 崩塌中 |
| @4000 | 1.0000 | 1.0000 | 0     | 0.2797 | 0.2768 | 0.3104 | 0.3385 | 0.2797 | 完全崩塌 |
| @6000 | 1.0000 | 1.0000 | 0     | 0.2627 | 0.2559 | 0.2905 | 0.2933 | 0.2522 | 完全崩塌 |

**崩塌轨迹分析**:
- @2000: ped_R=0.765, bg_FA=0.921 → 已经在将 92% 的背景格子预测为行人
- @4000: ped_R=1.000, bg_FA=1.000 → 完全单类崩塌，每个格子都预测为行人
- @6000: 持续恶化，offset 指标也在退化
- car_R 始终为 0 → 模型从未学会检测汽车
- **趋势明确**: 不可逆的单类崩塌，继续训练只会浪费算力

---

## 训练日志分析

来源: `20260315_031957.log`, 5785 行, 200 个 logged iterations (iter 10-2000)

### reg_loss=0 事件
- 总计: 19/200 = **9.5%**
- ALL-zero events (cls+reg 全为 0): 3 次 (iter 1530, 1550, 1600)
- iter 1200 后加速: ~24% 的 iteration 出现 reg_loss=0
- 含义: 模型在这些 iteration 中没有匹配到任何正样本 — 与单类崩塌一致

### 梯度分析
- grad_norm: mean=**3007**, range 25.9-6715
- clip_grad=10.0 → 有效梯度 = 10/3007 = **0.33%**
- 对比: 之前 v1 训练的 grad_norm mean=653, 有效梯度 = 10/653 = 1.5%
- **adaptation layers 的随机初始化导致梯度规模比之前大 4.6x**, clip=10 更加灾难性

### cls_loss 波动
- 极端波动: 0 → 984 → 447 → 113
- 这不是正常训练噪声，是模型在崩塌过程中的挣扎

---

## 发现的问题

### 1. **BUG-62 回归** (CRITICAL)
- **描述**: clip_grad=10.0 在 ORCH_045 config 中未修复。BUG-62 在 LARGE_V1_AT4000 审计中已识别，但 ORCH_045 使用同一 config 从零训练时未先修复此 bug
- **严重性**: CRITICAL
- **位置**: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py:L372` — `optim_wrapper=dict(clip_grad=dict(max_norm=10.0))`
- **影响**: grad_norm mean=3007, 有效梯度仅 0.33%。adaptation layers 随机初始化产生的大梯度被 clip 到几乎为零，模型无法有效学习
- **修复建议**: clip_grad 至少设为 35.0 (覆盖 >99% 的正常梯度)

### 2. **BUG-66: token_drop_rate=0.3 作为 anti-collapse 手段被证伪** (HIGH)
- **描述**: token corruption (随机替换 30% GT token) 被寄望于打破 mode collapse，但实验证明完全无效。模型在 @2000 即已严重崩塌
- **严重性**: HIGH
- **位置**: `GiT/mmdet/models/detectors/git.py:L503-507` — token corruption 实现; `GiT/configs/GiT/plan_full_nuscenes_large_v1.py:L188` — `token_drop_rate=0.3`
- **根因分析**: token corruption 在输入端加噪，但 mode collapse 的根因是**缺乏数据增强**和**100% teacher forcing**的双重效应。输入端加噪不改变训练信号的本质 — 模型仍然在无增强的相同图像上训练，只是看到了不同的 GT token 噪声。这相当于在错误的地方加了正则化
- **修复建议**: 必须解决根因 — 加入数据增强 (RandomFlip, PhotoMetricDistortion) 和/或 scheduled sampling

### 3. **BUG-67: adaptation layers + clip_grad 交互效应** (HIGH)
- **描述**: 2 层 Pre-LN TransformerEncoderLayer (d_model=1024, nhead=16, ffn=4096) 随机初始化，产生的梯度规模 (mean=3007) 是之前无 adaptation layers 训练 (mean=653) 的 4.6x。与 clip_grad=10 结合后，有效梯度仅 0.33%，远低于之前的 1.5%
- **严重性**: HIGH
- **位置**: `GiT/mmdet/models/backbones/vit_git.py:L202-217` — adaptation layers 定义; `GiT/configs/GiT/plan_full_nuscenes_large_v1.py:L221` — `online_dinov3_num_adapt_layers=2`
- **修复建议**: (1) 修复 clip_grad 到 35+; (2) 考虑 adaptation layers 使用 Xavier/Kaiming 初始化而非默认 PyTorch 初始化; (3) 或考虑 adaptation layers 使用更小的学习率

### 4. **BUG-68: ORCH_045 启动前未修复已知 CRITICAL bug** (PROCESS)
- **描述**: Conductor 在签发 ORCH_045 时，BUG-62 (clip_grad=10) 已在 LARGE_V1_AT4000 审计中被标记为 CRITICAL，但 ORCH_045 使用同一 config 从零训练，未先修复。这是流程失误 — 新训练应先修复所有 CRITICAL bugs
- **严重性**: CRITICAL (流程)
- **影响**: 整个 ORCH_045 训练 (~6000 iter, GPU 0+2 占用 ~12 小时) 浪费
- **修复建议**: Conductor 签发新训练时必须检查所有 PENDING verdicts 中的 CRITICAL findings

---

## 健康检查结果

### A. Mode Collapse 检测

- [x] **数据增强检查**: `train_pipeline` 无 RandomFlip / PhotoMetricDistortion → 🔴 **CRITICAL** (未修复，根因仍在)
  - 位置: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py` train_pipeline 部分
- [x] **Pipeline 分离检查**: `train_pipeline` 与 `test_pipeline` 实质相同 → 🔴 **HIGH**
- [x] **预测多样性**: 97-99% predictions identical across samples → 🔴 **CRITICAL**
- [x] **Marker 分布**: 91.5% 格子预测为正 (1097/1200), 几乎全部为 pedestrian class → 🔴 **CRITICAL**
- [x] **训练趋势**: @2000 → @4000 → @6000 预测多样性**持续减少**, ped_R: 0.765 → 1.000 → 1.000 → 🔴 **CRITICAL** (确认 mode collapse 加剧)

### B. Shortcut Learning 检测

- [x] **Loss-指标背离**: loss 在 @2000-@6000 间波动但无清晰下降; eval 指标全面恶化 → 🔴 **HIGH**
- [x] **Teacher Forcing 风险**: 100% teacher forcing, 仅有 token_drop_rate=0.3 (已证伪), 无 scheduled sampling → ⚠️ **MEDIUM** (token corruption 不是 scheduled sampling 的替代品)

### C. 架构风险检测

- [x] **位置编码完整性**: P2 fix 已应用 — `git.py:L334` 跳过 occ 的 position embedding → ✅ 正常
- [x] **特征注入频率**: P3 fix 已应用 — `git_occ_head.py:L1115` grid_interpolate_feats 仅首步注入 → ✅ 正常 (by design)
- [x] **维度匹配**: 4 层 DINOv3 (4×1024=4096) → proj 4096→2048→GELU→1024 → GiT backbone 1024 → ✅ 匹配

### D. 资源浪费检测

- [x] **无效训练**: mode collapse 在 @2000 已确立, 训练已自行停止 → 训练继续到 @6000 浪费了 ~8 小时 GPU (2×A6000)
- [x] **Checkpoint 价值**: @4000/@6000 比 @2000 更差 → 🔴 **CRITICAL**

---

## 配置审查结果

- [x] 数据增强: **无** → 🔴 CRITICAL (mode collapse 根因)
- [x] Pipeline 分离: **否** → 🔴 HIGH
- [x] Position embedding: P2 fix 在位 → ✅
- [x] 特征注入频率: 仅首步 (P3 fix) → ✅
- [x] Scheduled sampling: **无** → ⚠️ MEDIUM
- [x] clip_grad: 10.0 → 🔴 CRITICAL (BUG-62 regression)
- [x] token_drop_rate: 0.3 → 🔴 FAILED (BUG-66, 未起作用)
- [x] bert_embed: type='bert-base', hidden_size=1024, pretrain_path=None → ⚠️ (BUG-64 仍未修复)
- [x] load_from: None (从零训练) → 与 ORCH_045 设计一致
- [x] accumulative_counts: 8, 2 GPU → effective batch=16 → ✅
- [x] max_class_weight: 3.0 → BUG-17 cap 已激活 → ✅

---

## 逻辑验证

- [x] **梯度守恒**: grad_norm mean=3007, clip=10 → 有效梯度 0.33% → 🔴 模型几乎无法从梯度中学习
- [x] **边界条件**: reg_loss=0 在 9.5% iterations, ALL-zero 在 1.5% iterations → 当这些 iteration 的梯度为 0, 其前后 iteration 的巨大梯度又被 clip 到 0.33%, 训练信号极度稀疏
- [x] **数值稳定性**: decoder_out_pos0 的 mean=5.26, 但 range [-621, 374] 且 std=36.5 → 数值范围极大, adaptation layers 未能有效规范化特征

---

## 对 Conductor 计划的评价

### 致命失误

1. **BUG-62 未修复即启动新训练**: ORCH_045 使用与 LARGE_V1 相同的 config, clip_grad=10.0 是已知 CRITICAL bug。Conductor 应在修复所有 CRITICAL bugs 后再启动新训练。这导致整个 ORCH_045 实验 (~12 GPU·hours) 浪费。

2. **对 token_drop_rate 的期望过高**: token corruption 被定位为 "anti-mode-collapse" 的核心措施, 但它只在输入端加噪, 不改变训练数据和训练目标。真正的根因是缺乏数据增强 + 100% teacher forcing。Conductor 应该优先解决根因 (数据增强) 而非症状 (token corruption)。

3. **缺乏 kill switch**: @2000 的 eval 已明确显示 bg_FA=0.921 (92% 背景被误判为正), 这是极其明显的异常。但训练继续到了 @6000。应设置自动 kill switch: 当 bg_FA > 0.5 时立即停止训练。

### MASTER_PLAN 中的积极面

- 正确识别了 frozen predictions 问题 (P2+P3 @6000 car_R=0.582 是假象)
- 多层 DINOv3 + adaptation layers 的架构方向本身有价值
- "从零训练"的决策正确 (打破旧 checkpoint 的 mode collapse 记忆)

### 优先级修正建议

当前 MASTER_PLAN 将 token_drop_rate 作为 anti-collapse 的主力。实验已证明这不起作用。应重新排序:
1. **P0**: 修复 clip_grad → 35.0+ (BUG-62)
2. **P0**: 添加数据增强到 train_pipeline (RandomFlip + PhotoMetricDistortion) — 这是 mode collapse 的根因
3. **P1**: 考虑 scheduled sampling 替代或补充 token_drop_rate
4. **P2**: 修复 bert_embed (BUG-64)
5. **P3**: token_drop_rate 可保留但降级为辅助措施

---

## 需要 Admin 协助验证

### 假设 1: 数据增强是打破 mode collapse 的充分条件
- **假设**: 在当前架构 (multi-layer DINOv3 + adaptation) 下, 仅添加数据增强即可防止 mode collapse
- **验证方法**: 在 config 中添加 `RandomFlip(prob=0.5)` + `PhotoMetricDistortion()` 到 train_pipeline, 修复 clip_grad=35.0, 从零训练 2000 iter
- **预期结果**: bg_FA < 0.3, ped_R < 0.5 (非单类崩塌), BEV 可视化显示预测随场景变化

### 假设 2: adaptation layers 初始化导致梯度异常
- **假设**: adaptation layers 使用 PyTorch 默认初始化, 可能导致初始梯度过大
- **验证方法**: 检查 `vit_git.py:L202-217` 的 `nn.TransformerEncoderLayer` 默认初始化方式, 考虑改为 Xavier uniform
- **预期结果**: 初始 grad_norm 从 3007 降至 ~500-800 范围

---

## 附加建议

1. **建立训练 kill switch**: 在 `mmengine` hook 中添加 eval callback, 当检测到 bg_FA > 0.5 或 ped_R > 0.9 时自动暂停训练并通知

2. **ORCH 签发检查清单**: Conductor 签发新 ORCH 前必须检查:
   - [ ] 所有 CRITICAL bugs 已修复
   - [ ] Config diff vs 上次训练已审查
   - [ ] clip_grad 是否合理 (建议: max_norm ≥ 2x mean grad_norm 的 90th percentile)

3. **数据增强优先级提升**: 当前项目已经历 4 次 mode collapse (P2+P3 @6000, ORCH_044, ORCH_045 @2000, @4000)。共同根因是零数据增强。这不应再被视为 "可选优化" 而应作为 **必要条件**。

4. **可视化保存位置**: `shared/logs/viz_orch045_2000/` 包含 5 个样本的 BEV + img_grid + combined 可视化

---

*审计时间: 2026-03-15 16:48-16:55*
*审计人: claude_critic*
*诊断脚本: check_frozen_predictions.py, visualize_pred_vs_gt.py, diagnose_v3_precise.py, diagnose_v3c_single_ckpt.py*
