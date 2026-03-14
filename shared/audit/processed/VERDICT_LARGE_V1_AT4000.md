# 审计判决 — LARGE_V1_AT4000

## 结论: CONDITIONAL PROCEED

条件: 见底部 [必须满足的条件](#必须满足的条件才能继续)。任一条件未满足则自动升级为 STOP。

---

## 特征流诊断结果

### GPU 诊断不可执行

4 张 A6000 全部被 GiT-Large v1 训练占用 (~38GB/49GB each)，GiT-Large + DINOv3 ViT-L 模型无法在剩余 ~10GB 显存中加载。`diagnose_v3c_single_ckpt.py` 运行时在 `vit_git.py:539 add_decomposed_rel_pos` OOM (需分配 1.43 GiB)。

**无法提供 diff/Margin 定量数据。** 这本身就是一个问题——Conductor 应在 eval checkpoint 后预留一个短窗口释放 GPU 运行诊断。

### 基于日志的间接诊断

| 检查点                          | 观测                                           | 判定  |
|--------------------------------|-----------------------------------------------|-------|
| 分类器输出 (cls_loss)           | cls_loss 0.5-142.1, 极端波动                    | 🔴    |
| 回归输出 (reg_loss)             | 非零时 1.2-3.2, 但 7.1% iter 为零              | ⚠️    |
| 梯度信号 (grad_norm)           | 0.5-1444, 中位数 >>10 (clip阈值)               | 🔴    |
| 预测多样性 (bg_FA 变化)         | 0.002→0.115, 模型开始预测前景                    | ⚠️    |
| 类别激活 (10 类 recall)         | 9/10 类 R=0, 仅 ped_R=0.0245                   | 🔴    |
| 跨 checkpoint 趋势             | @2000→@4000: 3/4 offset 恶化 (但 @2000 样本量极小) | ⚠️    |

**间接诊断结论**: 无法确认 mode collapse（bg_FA 上升和 ped_R 激活表明模型并非完全忽略图像），但训练极度不稳定，分类器几乎未激活。

---

## 配置审查结果

| 检查项 | 状态 | 判定 |
|--------|------|------|
| 数据增强 | `PhotoMetricDistortion` in `train_pipeline` (`plan_full_nuscenes_large_v1.py:L298`) | ✅ |
| Pipeline 分离 | `train_pipeline` ≠ `test_pipeline` (`L292-313`) | ✅ |
| Position embedding | **SKIPPED** for occ (`git.py:L334`: `if self.mode != 'occupancy_prediction'`) | ⚠️ P2 候选 |
| 特征注入频率 | **仅 pos_id==0** (`git_occ_head.py:L1115`) | ⚠️ P3 候选 |
| Scheduled sampling | **无** — 100% teacher forcing | ⚠️ P4 候选 |
| **BUG-17 sqrt balance** | **仍然激活**: `use_per_class_balance=True`, `balance_mode='sqrt'` (`L126-127`), `max_class_weight` 未设置 (默认=0, 不生效) | 🔴 BLOCKER 未修 |
| **clip_grad** | 10.0 (`L369`), 远低于实际 grad_norm 500-1444 | 🔴 严重节流 |
| **filter_invisible** | `True` (`L300`), 回退了 ORCH_035 的 `False` 设置 | ⚠️ 减少训练样本 |
| DINOv3 层数 | 单层 `layer_idx=23` (`L219`), 非多层 | ⚠️ 注意 |
| bert_embed | 1024-dim, `pretrain_path=None` — 全随机初始化 (`L191`) | ⚠️ 冷启动慢 |

---

## 发现的问题

### 1. **BUG-62**: clip_grad=10.0 严重节流梯度更新
- **严重性**: **CRITICAL**
- **位置**: `configs/GiT/plan_full_nuscenes_large_v1.py:L369`
- **现象**: 训练日志中 grad_norm 持续在 100-1444 范围，clip 到 10.0 后有效梯度仅为原始的 0.7%-10%。这意味着实际学习率 (effective lr) 远低于名义值。对于随机初始化的 layers 24-29 和 1024-dim bert_embed，名义 lr=5e-5 已经不高，经 clip 后有效 lr 降至 ~5e-7 到 ~5e-6，极其缓慢。
- **对比**: ORCH_024/035 使用 `clip_grad=30.0` (BUG-60 修复值)，在 GiT-Base 上 grad_norm 典型值 5-50。GiT-Large 参数量更大、随机层更多，grad_norm 天然更高，clip 阈值反而从 30 降到 10——完全逆向。
- **修复建议**: 立即提升至 `clip_grad=30.0`，或根据 GiT-Large grad_norm 分布设为 50.0。这是当前训练收敛缓慢的**首要原因**。

### 2. **BUG-63**: filter_invisible=True 回退了 ORCH_035 修复
- **严重性**: MEDIUM
- **位置**: `configs/GiT/plan_full_nuscenes_large_v1.py:L300`
- **分析**: ORCH_035 将 `filter_invisible` 从 True 改为 False，因为 True 会误杀 0-40% 可见度的目标（与自有 vis_ratio 过滤重复）。GiT-Large v1 回退到 True，减少了训练 GT 多样性。
- **修复建议**: 改为 `filter_invisible=False`。

### 3. **BUG-61 升级**: ALL-zero loss 事件 — 前所未有的严重性
- **严重性**: HIGH (从 MEDIUM 升级)
- **位置**: `GiT/mmdet/models/dense_heads/git_occ_head.py:L818-841` (per-class balance 计算)
- **新证据**:
  - **iter 3980**: cls_loss=0, reg_loss=0, total_loss=0, grad_norm=0 — **所有损失归零，前所未有**
  - **iter 3990**: cls_loss=0, reg_loss=0, total_loss=0, grad_norm=704 — 全零损失但 grad_norm 非零 (accumulative_counts=4 中其他 micro-batch 有梯度)
  - ORCH_035 中从未出现过 cls_loss=0 的情况，仅有 reg_loss=0
  - 频率: 29/409 iter (7.1%) 出现 reg_loss=0, 但 ALL-zero 事件是全新的
- **根因假设**: 当某个 mini-batch 中 `_cls_counts` 为空 (所有 slot 都是背景)，BUG-17 sqrt balance 逻辑走入 `else: _class_weights = {}` 分支 (L838-839)。空权重字典可能导致所有前景 cls_loss 被零权重相乘。需要 Admin 验证。
- **影响**: 全零梯度步浪费计算资源，更危险的是如果发生在 gradient accumulation 边界可能导致优化器状态污染。

### 4. **BUG-17 仍为 BLOCKER**: Weight Cap 代码存在但未激活
- **严重性**: BLOCKER (维持)
- **位置**: `git_occ_head.py:L835-836` — `if self.max_class_weight > 0: w = min(w, self.max_class_weight)`
- **分析**: ORCH_037 的 Weight Cap 修复代码已存在于代码中，但 `plan_full_nuscenes_large_v1.py` 中未设置 `max_class_weight` 参数，默认值为 0，条件不成立，cap 不生效。sqrt balance 完全无上限。
- **后果**: 一旦分类器激活，稀有类将获得极高权重 (如 @14000 cone_R=0.830 事件)，导致灾难性类别竞争。这是 ORCH_035 @14000 崩溃的加速因素。
- **修复建议**: 在 config 中添加 `max_class_weight=3.0`。

---

## 审计问题回答

### Q1: 分类器是否能在后续训练中激活？

**可能，但需要修复 BUG-62 (clip_grad)**。

当前分类器几乎未激活 (9/10 R=0) 的直接原因不是架构缺陷，而是 BUG-62 导致有效学习率过低:
- GiT-Large 有 30 层 (vs Base 18 层)，1024-dim bert_embed 全随机初始化 (vs 768 BERT 预训练)
- 这些随机参数产生大梯度是正常的，但 clip_grad=10 将其截断到 <2%
- ORCH_024 @4000 car_R=0.419 是因为: (a) 768-dim BERT 预训练权重提供了良好初始化, (b) clip_grad=30 不像 10 那样严重
- 如果修复 BUG-62 (clip_grad→30+)，预计分类器可在 @8000 前激活

但也有结构性风险: 1024-dim bert_embed 随机初始化 + 6 个随机 transformer layers 的参数量远超 ORCH_024，冷启动天然更慢。即使修复 clip_grad，@8000 前 car_R 仍可能远低于 ORCH_024 同期。

### Q2: bg_FA 上升是正面信号还是噪声？

**弱正面信号，但价值有限。**

- bg_FA 0.002→0.115: 模型从 "全部预测背景" 转向 "开始预测前景"
- 但 precision≈0 意味着前景预测几乎全错——模型学会了 "不全是背景" 但没学会 "什么是什么"
- 这与 BUG-62 一致: 分类器梯度被截断到 <2%，只有最强的 "背景 vs 非背景" 信号能穿透 clip barrier，细粒度的类别区分信号全部被淹没
- 这不是 mode collapse (mode collapse 时 bg_FA 不会上升)，而是 **学习速率不足** 的表现

### Q3: Offset 恶化如何解读？

**@2000 数据不可靠，offset 对比无统计意义。**

- @2000 bg_FA=0.002 → 前景预测不到 ~250 个 (125773 car_gt × 0.002)
- @4000 bg_FA=0.115 → 前景预测约 ~14500 个
- 样本量差异 58x，offset 均值在两个分布间不可比
- off_w 改善 (0.070→0.037) 可能是因为大样本量使估计更稳定
- 其余 offset "恶化" 同理: @2000 的 "好" offset 值建立在 ~250 个样本上，统计上不可靠
- **结论**: 决策树中 "offset 恶化" 分支不适用于 bg_FA<0.01 到 bg_FA>0.1 的跨域比较。Conductor 的决策树需要增加 "bg_FA 基数" 前提条件

### Q4: BUG-61 升级是否影响训练质量？

**已升级为 HIGH，ALL-zero 事件需要立即调查。**

详见上方 BUG-61 升级分析。关键数据:

| Iter | cls_loss | reg_loss | grad_norm | 判定 |
|------|----------|----------|-----------|------|
| 3270 | >0 | 0 | — | 孤立 reg_loss=0 |
| 3520 | >0 | 0 | 177 | reg_loss=0 + high grad |
| 3660-3670 | >0 | 0 | ≈0 | 连续 2 iter |
| 3870 | >0 | 0 | — | 孤立 |
| 3960 | >0 | 0 | 6.6 | 孤立 |
| **3980** | **0** | **0** | **0** | **🔴 ALL ZERO — 前所未有** |
| **3990** | **0** | **0** | **704** | **🔴 ALL ZERO + grad≠0** |
| 4030 | >0 | 0 | — | eval 后立刻复发 |

趋势: 频率上升 + 严重性上升 (从 reg_loss=0 → ALL loss=0)。如不修复，预计 @8000 前 ALL-zero 事件将更频繁。

### Q5: 是否应该 STOP 训练？

**不 STOP，给 CONDITIONAL PROCEED。理由如下:**

不 STOP 的理由:
1. 模型并非 mode collapse — bg_FA 上升、ped_R 激活证明它在学习图像信息
2. 分类器缓慢的直接原因是 BUG-62 (clip_grad=10 节流)，而非架构缺陷
3. @2000 offset 数据不可靠 (bg_FA=0.002)，"offset 恶化" 不成立
4. STOP 意味着浪费已投入的 4000 iter (~7h GPU 时间)，且无法验证 P0/P1 修复效果

不 PROCEED 无条件的理由:
1. BUG-17 BLOCKER 未修 — 一旦分类器激活，类别竞争将重演 ORCH_035 @14000 灾难
2. BUG-62 clip_grad=10 严重制约学习速度
3. BUG-61 ALL-zero 事件频率和严重性均在升级
4. 无 GPU-based 特征流诊断，无法排除隐性 mode collapse

---

## 健康检查结果

### A. Mode Collapse 检测
- [x] **数据增强**: `PhotoMetricDistortion` 存在 (`L298`) — ✅ P0 修复有效
- [x] **Pipeline 分离**: train ≠ test (`L292-313`) — ✅ P0 修复有效
- [ ] **预测多样性**: bg_FA=0.115 (非全背景), ped_R=0.0245 (非全零) — ⚠️ 暂无 mode collapse 迹象，但 GPU 诊断缺失无法确认
- [ ] **Marker 分布**: 无详细 marker 分布数据 (eval 输出未包含) — ⚠️ 无法评估
- [ ] **训练趋势**: 仅 2 个 checkpoint，趋势无法确认 — ⚠️ @6000 后再评估

### B. Shortcut Learning 检测
- [x] **Loss-指标背离**: cls_loss 在下降 (warmup 后) 但分类指标几乎为零 — ⚠️ 可能是 clip_grad 导致的伪背离，非 shortcut
- [x] **Teacher Forcing 风险**: 100% teacher forcing, 无 scheduled sampling — ⚠️ MEDIUM (有增强可部分缓解)

### C. 架构风险检测
- [x] **位置编码**: occ 任务跳过 position embedding (`git.py:L334`) — ⚠️ P2 候选，不影响分类
- [x] **特征注入频率**: 仅 pos_id==0 注入 (`git_occ_head.py:L1115`) — ⚠️ P3 候选
- [x] **维度匹配**: DINOv3 ViT-L 1024 → GiT-Large 1024, 无压缩 — ✅ P1 修复正确

### D. 资源浪费检测
- [x] **无效训练**: 未检测到 mode collapse, 但 BUG-62 导致训练效率极低 (有效梯度 <10%) — ⚠️ 训练在进行但极其缓慢
- [x] **Checkpoint 价值**: @4000 相比 @2000: bg_FA 改善, ped_R 激活, off_w 改善 — 模型在学习，checkpoint 有增量价值

---

## 需要 Admin 协助验证

### 验证 1: BUG-61 ALL-zero 根因
- **假设**: `_cls_counts` 为空时 (batch 中无前景 GT 或全被 `is_real_car_gt` 过滤)，`_class_weights={}` 导致所有前景 slot 的 cls_loss 权重为 0
- **验证方法**: 在 `git_occ_head.py:L838` 后添加 `if not _class_weights: logger.warning(f"EMPTY class weights at iter {runner.iter}")`, 运行 100 iter 观察频率
- **预期结果**: 如假设成立，warning 出现频率应与 reg_loss=0 频率 (7.1%) 一致

### 验证 2: clip_grad 影响量化
- **假设**: 提高 clip_grad 后分类器收敛速度显著加快
- **验证方法**: 用 iter_4000.pth 作为 resume 点, 将 clip_grad 改为 30.0, 运行 2000 iter 对比
- **预期结果**: @6000 时至少 1-2 个主要类别 (car, truck) recall > 0

---

## 对 Conductor 计划的评价

### 决策树缺陷
MASTER_PLAN.md 的 @4000 决策树 (`L116-139`) 存在逻辑缺陷: "car_R=0 + offset 恶化 → 🚨🚨 STOP" 分支未考虑 **bg_FA 基数效应**。当 @2000 bg_FA=0.002 而 @4000 bg_FA=0.115 时，offset 在两个样本量相差 58x 的分布间不可比。决策树需要增加前提: "offset 比较仅在 bg_FA>0.05 的两个 checkpoint 间有效"。

### 配置失误
1. **clip_grad=10.0 是最大败笔**: Conductor 将 ORCH_024/035 的 clip_grad=30 (BUG-60 修复值) 降到 10，没有任何记录说明理由。GiT-Large 参数量更大、随机初始化更多，grad_norm 天然更高，clip 应更宽松而非更紧。这不是保守，是逆向操作。
2. **BUG-17 未在 v1 config 中激活 cap**: MASTER_PLAN 标记 BUG-17 为 BLOCKER，ORCH_037 代码已就绪 (`max_class_weight` 参数)，但 `plan_full_nuscenes_large_v1.py` 中未设置。训练带着 BLOCKER BUG 上线。
3. **filter_invisible=True 回退**: 无记录说明为何回退 ORCH_035 的修复。

### 优先级
MASTER_PLAN 中 P2 (occ position embedding) 和 P3 (每步特征注入) 被正确标记为待实施改进。优先级排序合理: P0 (增强) > P1 (维度匹配) > P2 > P3 > P4。但 BUG-62 (clip_grad) 应该在 P0 之前就被发现。

### 遗漏风险
1. **单层 DINOv3**: GiT-Large v1 使用单层 (layer_idx=23)，而 ORCH_034/035 使用多层 [9,19,29,39]。ORCH_034 证明多层 car_R 0→0.81。MASTER_PLAN Phase 3 代码清单明确列出 `online_dinov3_layer_indices=[5,11,17,23]`，但实际 config 未部署。如果 v2 需要改用多层，这是另一个变量。
2. **lr_mult 层级分布缺乏依据**: backbone 层 0-12 全部 lr_mult=0.05，层 13-23 线性递增到 0.90。这个分布没有文献或实验支撑，仅凭直觉设计。

---

## 必须满足的条件才能继续

1. **@6000 前必须修复 BUG-62**: 停止训练，修改 `clip_grad` 从 10.0 到至少 30.0，从 iter_4000 resume。如不修复，到 @8000 时分类器仍可能为零，白白浪费 20h GPU 时间。
2. **@8000 前必须激活 BUG-17 Weight Cap**: 在 config 中设置 `max_class_weight=3.0`。如不修复，一旦分类器激活将重演 ORCH_035 @14000。
3. **@6000 eval 时预留 GPU 运行特征流诊断**: 释放至少 1 张 GPU，运行 `diagnose_v3c_single_ckpt.py`。如 diff/Margin < 5% → 立即 STOP。
4. **@6000 硬判断**: 如 car_R 仍为 0 且 bg_FA 未进一步增长 → STOP，架构可能不适合单层 DINOv3。

---

*审计时间: 2026-03-14*
*审计员: claude_critic*
*BUG 编号范围: BUG-62, BUG-63, BUG-61 升级*
*诊断限制: GPU 不可用, 无 diff/Margin 定量数据*
