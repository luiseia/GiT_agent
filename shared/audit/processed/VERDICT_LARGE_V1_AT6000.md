# 审计判决 — LARGE_V1_AT6000

## 结论: CONDITIONAL PROCEED

@8000 是绝对最终决策点。如果 car_R 仍为 0，无论 offset 如何，必须 STOP 并重新设计。

---

## 特征流诊断结果

### GPU 诊断仍不可执行

4 张 A6000 全部占满: GPU 0,2 被 GiT-Large v1 训练占用 (~33GB/49GB)，GPU 1,3 被 yl0826 PETR 训练占用 (~31GB/49GB)。无任何空闲 GPU 运行 `diagnose_v3c_single_ckpt.py`。

**连续两次审计 (@4000, @6000) 无法运行 GPU 特征流诊断。Conductor 未履行 VERDICT_LARGE_V1_AT4000 中的条件 3: "预留 GPU 运行特征流诊断"。**

| 检查点                          | cross-sample 相对差异 | 判定   |
|--------------------------------|----------------------|--------|
| patch_embed_input              | N/A (无GPU)          | ❓     |
| grid_interp_feat_layer0        | N/A                  | ❓     |
| image_patch_encoded (backbone) | N/A                  | ❓     |
| pre_kv_layer0_k                | N/A                  | ❓     |
| pre_kv_last_k                  | N/A                  | ❓     |
| decoder_out_pos0               | N/A                  | ❓     |
| logits_pos0                    | N/A                  | ❓     |
| pred_token_pos0 (argmax)       | N/A                  | ❓     |

- diff/Margin 比率: **无法计算**
- 趋势: **无法评估**
- 诊断结论: **数据缺失，无法确认或排除 mode collapse**

### 基于日志的间接诊断

| 指标 | @4000 (修复前) | @6000 (修复后) | 变化 | 判定 |
|------|---------------|---------------|------|------|
| car_R | 0.000 | 0.000 | 持平 | 🔴 |
| ped_R | 0.025 | 0.015 | ↓ 40% | 🔴 |
| bicycle_R | 0.000 | 0.010 | ↑ NEW | ⚠️ |
| bg_FA | 0.115 | 0.025 | ↓ 78% | ⚠️ 见分析 |
| off_th | 0.212 | **0.094** | ↓ 56% (**历史最佳**) | ✅ |
| off_cy | 0.141 | 0.081 | ↓ 43% | ✅ |
| off_cx | 0.193 | 0.273 | ↑ 41% 恶化 | 🔴 |
| off_w | 0.037 | 0.041 | 持平 | ⚠️ |
| off_h | 0.015 | 0.023 | ↑ 53% 恶化 | 🔴 |

**间接诊断结论**: 不是 mode collapse（offset 在改善、新类激活），但分类器收敛严重滞后于回归器。

---

## 配置审查结果

BUG-62/63/17 修复已通过日志验证（`20260314_110933.log`）:
- `clip_grad=dict(max_norm=30.0)` ✅ (L425)
- `filter_invisible=False` ✅ (L617)
- `max_class_weight=3.0` ✅ (L274)

| 检查项 | 状态 | 判定 |
|--------|------|------|
| 数据增强 | `PhotoMetricDistortion` in train | ✅ |
| Pipeline 分离 | train ≠ test | ✅ |
| Position embedding | SKIPPED for occ (`git.py:L334`) | ⚠️ P2 |
| 特征注入频率 | 仅 pos_id==0 (`git_occ_head.py:L1115`) | ⚠️ P3 |
| Scheduled sampling | 无 | ⚠️ P4 |
| clip_grad | 30.0 (已修复) | ✅ |
| filter_invisible | False (已修复) | ✅ |
| max_class_weight | 3.0 (已修复) | ✅ |
| **DINOv3 层数** | 单层 layer_idx=23 | ⚠️ 见下方分析 |
| **bert_embed** | 1024-dim, pretrain_path=None (全随机) | ⚠️ 冷启动瓶颈 |
| **effective batch** | 16 (2 GPU, 原 32) | ⚠️ 收敛速度减半 |

---

## 训练稳定性分析 (iter 4010-6040, 后BUG-62修复)

### 统计摘要

| 指标 | 值 |
|------|-----|
| 总 iter 数 | 204 (logged) |
| mean cls_loss | 54.67 |
| mean reg_loss | 2.25 |
| mean grad_norm (pre-clip) | 653.16 |
| cls_loss 范围 | 0.0 — 343.2 |
| grad_norm 范围 | 0.44 — 1878 |
| reg_loss=0 频率 | 15/204 = **7.4%** |
| ALL-zero 事件 | iter 5760 (cls=0, reg=0, grad_norm=529) |

### 关键发现: 分类与回归的极度不对称

训练日志暴露了一个根本性问题:

- **reg_loss 稳定**: 非零时典型值 1.7-3.0，标准差小，说明回归路径已收敛到可工作的参数空间
- **cls_loss 混沌**: 0.6-343 范围 (>500x 变化)，同一个训练窗口内可以从 11 跳到 142 再回到 25。这不是 "波动"，是 **分类器完全没有收敛**
- **grad_norm**: mean=653 >> clip=30，意味着**平均每步有效梯度仅为原始的 4.6%**。虽然比 BUG-62 修复前的 1.5% 好 3x，但仍然极度受限

### 与 ORCH_024 对比 (同 iter)

| 指标 | GiT-Large v1 @6000 | ORCH_024 @6000 | 对比 |
|------|-------------------|----------------|------|
| **off_th** | **0.094** | 0.169 | ✅✅ v1 优 **44%** (历史最佳!) |
| **off_cy** | **0.081** | 0.082 | ✅ 平局 |
| off_w | 0.041 | 0.038 | ⚠️ 接近 |
| off_cx | 0.273 | 0.056 | 🔴🔴 v1 差 **4.9x** |
| off_h | 0.023 | 0.011 | 🔴 v1 差 2.1x |
| car_R | 0.000 | 0.455 | 🔴🔴🔴 |

**CEO 优先指标 (offset) 解读**:
- off_th = 0.094 击败 ORCH_024 全历史最佳 (0.1275 @12000)，**这是整个项目历史上最好的 theta offset**
- off_cy 与 ORCH_024 @8000 (0.0736) 接近
- 但 off_cx = 0.273 是灾难性的（是 ORCH_024 最差值 0.0723 的 3.8x）
- **结论: offset 表现呈极端分裂——角度和纵向优秀，横向和尺寸很差**

---

## 审计问题回答

### Q1: PROCEED / CONDITIONAL PROCEED / STOP?

**CONDITIONAL PROCEED to @8000。**

理由: off_th=0.094 是项目史上最佳，说明模型确实在学习利用图像特征做空间回归。这不是一个死掉的模型。但 car_R=0 持续 6000 iter 是极度异常的——ORCH_024 @2000 就有 car_R=0.627。

不 STOP 的关键原因:
1. BUG-62 修复后仅经过 2000 iter (effective)，且 batch 从 32 降到 16 → 等效只有 ~1000 "正常 iter" 的学习量
2. off_th/off_cy 显著改善证明模型在利用图像特征
3. bicycle 新激活表明分类路径没有死掉
4. 1024-dim random bert_embed 的冷启动比 768 pretrained 天然慢得多

不 PROCEED 无条件的原因:
1. 6000 iter car_R=0，远超正常冷启动范围
2. off_cx=0.273 严重异常——横向定位能力极差
3. ped_R 下降 (0.025→0.015)
4. BUG-61 未根治 (7.4%)
5. 连续两次审计无法运行 GPU 诊断——存在隐性风险

### Q2: bg_FA 从 0.115 降至 0.025 是好信号还是坏信号?

**中性偏正面，但需要观察 @8000 趋势。**

分析:
- clip_grad 从 10→30 后，模型接收到 3x 更大的有效梯度。这导致模型 "重新校准" 其决策边界
- @4000 的 bg_FA=0.115 是在 clip_grad=10 下的产物——模型缓慢地学会 "预测一些前景"，但精度为零 (precision≈0)
- @6000 的 bg_FA=0.025 说明模型在更强梯度下变得更保守 (精确) ——只预测它更有把握的前景
- 关键指标: bg_R=0.975 (正确识别 97.5% 背景)，bg_FA=0.025 (仅 2.5% 误报)。这是健康的分离
- bg_FA=0.025 仍是 @2000 (0.002) 的 12.5x — 不是回退到初始状态

**但**: 如果 @8000 bg_FA 继续下降到 <0.01，则模型可能正在退化为 "全背景预测器"，那时才是坏信号。

### Q3: bicycle 新激活 + off_th/off_cy 改善是否说明模型在缓慢学习?

**是的。但 "缓慢" 的程度令人担忧。**

- bicycle 新激活 (R=0.010, 1733 GT 中检出 ~18 个)——微弱但非零，说明分类路径在缓慢形成
- off_th 0.212→0.094 (56% 改善) 在仅 2000 iter 内——回归学习速度是正常的
- off_cy 0.141→0.081 (43% 改善) 同理
- 但 car_R=0 持续——分类和回归之间的巨大差距说明: **回归可以在混沌的分类器下独立学习**（因为 offset loss 仅依赖空间位置，不依赖类别正确性），而 **分类需要 bert_embed 先收敛**

根因假设: 1024-dim random bert_embed 是分类收敛的瓶颈。ORCH_024 用 768-dim BERT pretrained 提供了良好的 token embedding 初始化。GiT-Large v1 需要从零学习 230 个 token 的 1024-dim embedding space，这是一个巨大的额外任务。

### Q4: BUG-61 的 5-7% 零梯度事件是否足以解释 car_R=0?

**不。BUG-61 不是 car_R=0 的原因。**

- 7.4% 的 reg_loss=0 事件仅影响回归质量，而 car_R 是分类指标
- 绝大多数 reg_loss=0 事件中 cls_loss > 0 (典型 ~0.68)，分类器仍在学习
- 即使完全修复 BUG-61，如果 bert_embed 冷启动问题不解决，car_R 仍会为零
- 但 BUG-61 的 ALL-zero 事件 (iter 5760: 全零 + grad_norm=529) 依然需要调查——这意味着某些 batch 完全不产生有用的 loss

### Q5: 是否需要运行 diagnose_v3c_single_ckpt.py?

**是的，而且是 MANDATORY。**

连续两次审计被 "GPU 不可用" 挡住。@8000 eval 时必须释放至少 1 张 GPU 运行诊断。方案:
1. @8000 eval 前暂停训练 → 释放 GPU 0 或 2
2. 运行诊断 → 获取 diff/Margin 数据
3. 诊断完成后恢复训练

如果 @8000 仍无法运行诊断: STOP 训练直到诊断完成。没有 diff/Margin 数据的决策是盲人摸象。

### Q6: 下一个决策点?

**@8000，非可协商。**

- @8000 = 实验评判规则 #5 的 "架构决策" 阈值
- 如 car_R > 0.01 → 分类器终于在激活，可 PROCEED
- 如 car_R = 0 但 off_th/off_cy 继续改善且 bg_FA > 0.01 → 考虑是否该放弃分类、只做回归
- 如 car_R = 0 且 offset 不再改善 → **STOP，架构不适合当前配置**

---

## 发现的问题

### 1. **BUG-64**: cls_loss 极端波动导致训练效率低下
- **严重性**: HIGH
- **位置**: 非单点 bug，系统性问题
- **现象**: cls_loss 在同一训练窗口内从 0.6 到 343（>500x 变化），mean=54.7，median 可能在 30 左右。这导致:
  - 大 loss 步 (>100) 产生极大梯度 → 被 clip 到 30 → 有效梯度仅 ~0.3% → 几乎无学习
  - 小 loss 步 (<5) 产生小梯度 → 不被 clip → 正常学习
  - 结果: 模型只在少数 "小 loss" 步中有效学习，大部分计算浪费
- **根因**: 1024-dim random bert_embed + 230-token vocabulary = 巨大的 token 空间中随机初始化 → 分类 loss landscape 极度不平滑
- **修复建议**:
  - 短期: 考虑 warmup cls_loss_weight（从 0.1 逐步升到 1.0）减缓分类学习初期的剧烈波动
  - 中期: 1024-dim BERT pretrained 权重 → 但不存在 1024-dim BERT (标准 BERT-base=768, BERT-large=1024!)
  - **⚠️ 关键发现**: BERT-large 的 hidden_size = 1024，EXACTLY 匹配 GiT-Large embed_dims。`bert_embed=dict(type='bert-base', hidden_size=1024, pretrain_path=None)` — `type='bert-base'` 是错误的！应该用 `type='bert-large'` 并加载 BERT-large 预训练权重。这可能是分类器冷启动极慢的根本原因。

### 2. **BUG-65**: off_cx 异常恶化 — 模型横向定位能力缺失
- **严重性**: HIGH
- **位置**: 非代码 bug，可能是架构/训练问题
- **现象**: off_cx = 0.273，是 ORCH_024 @6000 (0.056) 的 4.9x。其他 offset (off_th, off_cy) 在改善，唯独 off_cx 在恶化 (0.106→0.193→0.273)
- **分析**: off_cx 编码的是 BEV grid 中心到物体中心的 x 方向偏移。@6000 bg_FA=0.025 意味着只有 ~3000 个前景预测，offset 基于这些少量样本。如果这些预测集中在特定区域（如图像中心），off_cx 可能被系统性偏移
- **修复建议**: 需要在 @8000 eval 时分析前景预测的空间分布。如果集中在特定区域 → 可能是 position embedding 缺失 (P2) 导致模型无法区分不同 x 位置

### 3. **BUG-61 维持 HIGH**: 频率稳定但 ALL-zero 事件继续
- **严重性**: HIGH (维持)
- **位置**: `git_occ_head.py:L818-841`
- **数据**: 15/204 = 7.4% reg_loss=0，1 次 ALL-zero (iter 5760)。频率与修复前一致 (7.1%)，BUG-17 cap (max_class_weight=3.0) 未改善此问题。
- **新观察**: ALL-zero 事件 (iter 5760) 的 grad_norm=529 (非零)，说明 accumulative_counts=4 中其他 micro-batch 有梯度。问题出在单个 micro-batch 级别。
- **聚集模式**: reg_loss=0 明显聚集 (4620-4630, 4760-4800, 5700-5760)，非随机分布。可能与特定训练数据批次有关。

---

## 健康检查结果

### A. Mode Collapse 检测
- [x] **数据增强**: PhotoMetricDistortion ✅
- [x] **Pipeline 分离**: train ≠ test ✅
- [ ] **预测多样性**: bg_FA=0.025, ped_R=0.015, bicycle_R=0.010 — 非全背景预测 → ⚠️ 无 mode collapse 迹象，但无 GPU 诊断确认
- [ ] **Marker 分布**: 无详细数据 — ❓
- [ ] **训练趋势**: @4000→@6000 bg_FA 下降但 offset 改善 — ⚠️ 混合信号，需 @8000 确认

### B. Shortcut Learning 检测
- [x] **Loss-指标背离**: cls_loss mean=54.7 (未显著下降) + car_R=0 — ❓ cls_loss 波动太大无法判断趋势
- [x] **Teacher Forcing**: 100% TF, 无 scheduled sampling — ⚠️ MEDIUM

### C. 架构风险检测
- [x] **位置编码**: occ 跳过 PE (`git.py:L334`) — ⚠️ 可能影响 off_cx
- [x] **特征注入**: 仅 pos_id==0 (`git_occ_head.py:L1115`) — ⚠️
- [x] **维度匹配**: 1024→1024 无损 — ✅

### D. 资源浪费检测
- [x] **无效训练**: 模型在学习 (offset 改善)，非无效 — ⚠️ 但 cls 学习极低效
- [x] **Checkpoint 价值**: @6000 off_th=0.094 (历史最佳) > @4000 — ✅ 有增量价值

---

## 需要 Admin 协助验证

### 验证 1: bert_embed 类型与预训练 (BUG-64 关键)
- **假设**: `bert_embed=dict(type='bert-base', hidden_size=1024, pretrain_path=None)` 应改为 `type='bert-large'` 并加载 BERT-large 预训练权重 (hidden_size=1024 完美匹配)
- **验证方法**:
  1. 检查 bert_embed 代码是否支持 `type='bert-large'`
  2. 如支持: 用 BERT-large 预训练权重初始化 bert_embed，从 iter_6000 resume，观察 cls_loss 波动是否减小、car_R 是否在 2000 iter 内激活
- **预期结果**: 预训练 token embedding 应显著减小 cls_loss 波动 (从 0-343 到更窄的范围)，并加速分类器收敛

### 验证 2: @8000 特征流诊断 (MANDATORY)
- **假设**: 模型确实在利用图像特征 (offset 改善作为间接证据)
- **验证方法**: @8000 eval 前暂停训练，释放 1 张 GPU，运行 `python scripts/diagnose_v3c_single_ckpt.py iter_6000 <dir> <config>` (可先诊断 6000，等 8000 后再诊断 8000 并对比趋势)
- **预期结果**: diff/Margin > 10% (off_th=0.094 best-ever 暗示图像信号强)

### 验证 3: off_cx 空间分布分析
- **假设**: off_cx=0.273 异常恶化因为前景预测集中在特定空间区域
- **验证方法**: 写脚本分析 @6000 eval 的前景预测在 20×20 BEV grid 中的空间分布
- **预期结果**: 如果分布不均匀 → 确认 position embedding 缺失是原因

---

## 对 Conductor 计划的评价

### 执行力问题
VERDICT_LARGE_V1_AT4000 的条件 3 ("@6000 eval 时预留 GPU 运行特征流诊断") **未被满足**。Conductor 知道 GPU 1,3 被 yl0826 占用，应该协调 GPU 使用或在 eval 窗口暂停训练释放 GPU。连续两次审计无法诊断是不可接受的。

### 决策树需要更新
当前决策树 "car_R=0 + bg_FA 不增 → STOP" 过于简化。@6000 的情况是: car_R=0 + bg_FA 下降但 offset 大幅改善。决策树需要加入 offset 维度: 如果 offset 在改善 (CEO 最高优先级)，不应仅因 car_R=0 就 STOP。建议重构为:
```
@8000:
├─ car_R > 0 → PROCEED (分类器终于激活)
├─ car_R = 0 + offset 改善 + diff/Margin > 10%
│   → CONDITIONAL: 调查分类器瓶颈 (bert_embed?)
├─ car_R = 0 + offset 停滞/恶化
│   → STOP: 架构根本不工作
├─ car_R = 0 + diff/Margin < 10%
│   → STOP: mode collapse
```

### 遗漏: bert_embed 初始化
**MASTER_PLAN 从未讨论过 bert_embed 初始化策略。** `bert_embed=dict(type='bert-base', hidden_size=1024, pretrain_path=None)` 使用 bert-base 架构但强制 1024-dim 且无预训练。BERT-large (hidden_size=1024, 24 layers, 16 heads) 完美匹配 GiT-Large 的维度。如果 bert_embed 模块支持 BERT-large，这是一个免费的分类加速方案。

### batch size 影响被低估
从 4 GPU (effective batch=32) 降到 2 GPU (effective batch=16) 对收敛速度的影响不可忽略。学习率应该按 linear scaling rule 调整: `lr = lr_base * batch_eff / batch_ref`。当前 lr=5e-5 是为 batch=32 设计的，在 batch=16 下应为 2.5e-5。但 `param_scheduler` 的 warmup 已经结束 (lr=2.5e-6 at backbone base)，所以实际 lr 已经很低了。这不是致命问题但值得关注。

---

## 必须满足的条件才能继续

1. **@8000 是 ABSOLUTE FINAL 决策点**: 如 car_R=0 且 offset 无进一步改善 → STOP，不再续约
2. **@8000 eval 时 MUST 运行特征流诊断**: 暂停训练释放 GPU，先运行 `diagnose_v3c_single_ckpt.py` 对 iter_6000 和 iter_8000。如 diff/Margin < 10% → 立即 STOP
3. **调查 bert_embed 初始化**: 确认是否可用 BERT-large 预训练权重 (BUG-64)。如可行，这是 v2 训练的必要改动
4. **@8000 决策 MUST 基于 offset 全维度对比**: 不只看 off_th (当前最佳)，必须看 off_cx (当前最差)。如 off_cx 继续恶化 → 架构存在方向性盲点

---

*审计时间: 2026-03-14 17:00*
*审计员: claude_critic*
*BUG 编号范围: BUG-64 (cls_loss波动/bert_embed), BUG-65 (off_cx异常)*
*诊断限制: GPU 不可用, 连续第二次无 diff/Margin 数据*
*判决长度: 220+ 行*
