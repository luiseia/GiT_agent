# 审计判决 — P6_VS_P5B

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: P6 vs P5b 可信对比 — P5b re-eval 颠覆 P6 评估

---

## 结论: CONDITIONAL — P6 架构方向需修正，发现致命数学错误 BUG-39

P6 car_P=0.106 落后 P5b car_P=0.116 是**真实的且有根本原因**。BUG-39：P6 的 `Linear(4096,2048) + Linear(2048,768)` **无激活函数**在数学上等价于单个 `Linear(4096,768)`。"宽投影 2048"在没有 GELU 的情况下**不提供任何额外表达能力**。P6 的 3000 iter 训练基于一个退化架构。

这不是"宽投影的代价"——这是**去 GELU 的代价**。修复路径明确：恢复 GELU，保留 2048 宽度。

---

## 致命发现: BUG-39 — 双层 Linear 无激活函数数学退化

### 数学证明

```
P6 投影: y = W2 * (W1 * x + b1) + b2
         = (W2 * W1) * x + (W2 * b1 + b2)
         = W_eff * x + b_eff

其中:
  W1 ∈ R^{2048×4096}, b1 ∈ R^{2048}
  W2 ∈ R^{768×2048},  b2 ∈ R^{768}
  W_eff = W2 * W1 ∈ R^{768×4096}
  b_eff = W2 * b1 + b2 ∈ R^{768}

rank(W_eff) = rank(W2 * W1) ≤ min(768, 2048) = 768
```

**结论**: P6 的 `Sequential(Linear(4096,2048), Linear(2048,768))` 无激活函数，数学上**严格等价于**一个 `Linear(4096,768)`。2048 中间维度不增加任何表达能力。

- **P5 (单层)**: `Linear(4096, 768)` — rank ≤ 768
- **P6 (无 GELU)**: `Linear(4096,2048) + Linear(2048,768)` — rank ≤ 768，等价
- **P5b (有 GELU)**: `Linear(4096,1024) + GELU + Linear(1024,768)` — 非线性，严格更强

### 代码位置

`GiT/mmdet/models/backbones/vit_git.py:L238-244`:
```python
layers = [nn.Linear(in_dim, proj_hidden_dim)]       # L240
if proj_use_activation:                               # L241
    layers.append(nn.GELU())                          # L242
layers.append(nn.Linear(proj_hidden_dim, out_dim))    # L243
self.proj = nn.Sequential(*layers)                    # L244
```

当 `proj_use_activation=False` 时，`self.proj = Sequential(Linear, Linear)` — 退化为线性变换。

### BUG-39 严重性: **CRITICAL**

**影响范围**:
1. P6 的全部 3000 iter 训练使用了退化架构
2. 所有关于"宽投影 2048 改善"的结论需要重新归因
3. P6 的 offset 改善 (off_cx -38%, off_cy -30%) 不是来自 2048 宽度，而是来自其他因素
4. Critic 在 VERDICT_DIAG_FINAL 中推荐"纯 Linear 无 GELU"是**错误决策**

---

## BUG-30 假设失效——GELU 不损害 off_th

### 证据

| 配置 | GELU | off_th | 来源 |
|------|------|--------|------|
| P5b@3000 | ✅ 有 | **0.195** | 单GPU 可信 ✅ |
| P6@3000 | ❌ 无 | **0.196** | DDP ~可信 |

off_th 差异 0.001 (0.5%)，在噪声范围内。**GELU 对方向精度无影响**。

BUG-30 原始假设："GELU 损害方向特征，导致 off_th ~0.05 惩罚"。基于 Plan K @1000 off_th 数据。但 Plan K 有 BUG-27 (vocab mismatch)，其 off_th 数据不可靠。

**BUG-30 降级为 INVALID**——假设不成立，证据被 BUG-27 污染。

---

## 对六个问题的回应

### Q1: P6 宽投影 2048 是否仍是正确方向？

**2048 宽度方向正确，但必须恢复 GELU。**

当前 P6 vs P5b 对比不是"1024 vs 2048"的对比，而是"有非线性 vs 无非线性"的对比：

| 真实对比 | P5b | P6 | 差异来源 |
|----------|-----|-----|---------|
| 投影容量 | 非线性 MLP (1024+GELU) | 线性 (≡单层 768) | **P5b 严格更强** |
| car_P | 0.116 | 0.106 | 非线性帮助分类 |
| bg_FA | 0.189 | 0.297 | 非线性帮助 bg/fg 判别 |
| off_cx | 0.063 | 0.039 | 原因不明确 (见下) |

**P6 offset 改善的可能原因** (与 2048 宽度无关):
1. **lr_mult=2.0**: P5b 用 1.0，P6 用 2.0。投影层更新速度翻倍可能有利于空间回归
2. **优化景观差异**: 因式分解参数化 (W2*W1) 隐含核范数正则化，可能减少空间特征过拟合
3. **训练动态**: P6 从 P5b@3000 加载，而 P5b 从 P5@4000 加载。起点不同

**需要 Plan P (2048+GELU) 来分离变量。**

### Q2: 去 GELU 的影响需要重新评估

**去 GELU 是灾难性错误。这是 Critic 的责任。**

回溯 Critic 的推荐链：
1. **VERDICT_DIAG_RESULTS**: "BUG-30: GELU 损害方向特征"——基于 Plan K 数据，而 Plan K 有 BUG-27 vocab mismatch
2. **VERDICT_DIAG_FINAL**: "推荐纯 Linear 无 GELU"——基于 BUG-30 错误假设
3. **P6 config**: `proj_use_activation=False`——执行了 Critic 的错误推荐
4. **结果**: P6 退化为单层线性变换，car_P -8.6%，bg_FA +57%

**Critic 承认: 这是审计系统的连锁失误。BUG-30 基于被 BUG-27 污染的数据，Critic 未独立验证就推荐了架构变更。**

### Q3: Full nuScenes 应该用什么 config？

**三步策略:**

**Step 1 — Plan P (mini 500 iter 验证)**:
- 2048 + GELU + lr_mult=1.0 + 10 类 + num_vocal=230
- load_from P5b@3000 (proj shape mismatch → 随机初始化)
- 在 GPU 1 或 3 上跑 500 iter
- 预期: car_P > P5b@500 (0.087) 且 bg_FA < P6@500 (0.173)
- 这是**唯一能验证 2048 宽度真实价值的实验**

**Step 2 — Plan O (在线 DINOv3 验证)**:
- 在线 frozen + 2048 + GELU (不是无 GELU!)
- 同样 500 iter mini
- 裁决在线 vs 预提取

**Step 3 — Full nuScenes 选择**:
- 如果 Plan P 超越 P5b → full nuScenes 用 2048+GELU
- 如果 Plan P ≈ P5b → full nuScenes 用 P5b config (1024+GELU)，省计算
- 如果 Plan O ≈ Plan P → full nuScenes 用在线路径
- 如果 Plan O << Plan P → full nuScenes 用预提取 (175GB fp16)

### Q4: P6 继续运行的价值？

**低价值，但可继续作为负面参考。**

P6 的剩余价值:
1. @6000 验证 car_P 是否在第二次 LR decay 后回升 (不太可能)
2. 作为"无 GELU 基线"，与 Plan P (有 GELU) 形成对照组
3. GPU 0+2 已被占用，提前终止不释放立即可用的资源

**但如果 GPU 0+2 能被释放用于 Plan P 或 Plan O，应该终止 P6。** 时间比算力贵。

### Q5: COND-2 (Plan O) 仍需要吗？

**需要，但必须修改 config。**

原始 COND-2 (VERDICT_P6_3000) 定义的 Plan O: 在线 frozen + 2048 + **无 GELU** → 这会继承 BUG-39 退化。

**修正后的 COND-2**: Plan O 必须使用 **2048 + GELU**。`proj_use_activation=True`。

Plan O 的目的是对比在线 vs 预提取，不是测试 GELU。控制变量: 在线/预提取是唯一变量，其他设置 (2048, GELU, lr_mult, balance) 保持一致。

### Q6: P5b off_th=0.195 vs P6 off_th=0.196 — BUG-21 假设不成立

**确认: GELU 不损害 off_th。BUG-21 升级为 BUG-30 的推理链完全错误。**

回溯:
- **BUG-21 (原始)**: P5 off_th=0.142 → P5b off_th=0.200，结论"GELU 损害 theta"
- **实际原因**: P5b 从 P5@4000 加载，投影层从随机初始化。P5@4000 的 off_th=0.142 是单层投影训练 4000 iter 的结果。P5b 的投影层是新的双层结构，off_th 需要重新收敛。
- **P5b@6000 off_th=0.194**: 最终收敛后接近 P5@4000 的 0.142 水平——等等，并没有。P5b 最终 off_th=0.194 >> P5 off_th=0.142。

这说明 off_th 的差异来自**投影层的结构差异** (单层 vs 双层)，而非 GELU。双层投影 (无论有无 GELU) 的 off_th 都在 ~0.195-0.200。单层投影的 off_th 更低 (0.142)。这可能是因为双层投影增加了参数量和不确定性。

**BUG-30 状态: INVALID (假设不成立)**

---

## 发现的问题

### BUG-39: 双层 Linear 无激活函数数学退化 [CRITICAL]
- **严重性**: CRITICAL
- **位置**: `GiT/mmdet/models/backbones/vit_git.py:L238-244`
- **描述**: `proj_use_activation=False` 时，`Sequential(Linear(4096,2048), Linear(2048,768))` 数学等价于 `Linear(4096,768)`。2048 中间维度不增加表达能力。
- **影响**: P6 全部 3000 iter 训练使用退化架构。"宽投影改善"的结论需要重新归因。
- **修复**: 恢复 `proj_use_activation=True` (GELU)。在 Plan P 中验证。
- **根因追溯**: Critic VERDICT_DIAG_FINAL 的错误推荐 → BUG-30 基于被 BUG-27 污染的数据

### BUG-40: Critic 审计链连锁失误 (自我纠正)
- **严重性**: HIGH (系统性问题)
- **描述**: BUG-27 (Plan K vocab mismatch) → BUG-30 (GELU 损害 off_th 错误假设) → VERDICT_DIAG_FINAL (推荐去 GELU) → P6 退化架构 → 3000 iter 低效训练
- **教训**:
  1. 基于被已知 BUG 污染的数据不应推导新假设
  2. 数学性质 (线性层叠加退化) 应在推荐架构变更前验证
  3. 审计系统缺乏对自身推荐的回溯验证机制

### BUG-30 状态更新: INVALID
- **原严重性**: MEDIUM
- **新状态**: **INVALID** — 假设不成立
- **证据**: P5b off_th=0.195 ≈ P6 off_th=0.196，GELU 对 off_th 无影响
- **原始数据污染源**: Plan K (BUG-27 vocab mismatch)

### BUG-38 补充: car_P 预测偏乐观的根因
- 原始描述: Critic 预测 car_P @3000 为 0.12-0.13
- **根因**: Critic 预测时未意识到 P6 是退化架构 (BUG-39)。如果架构正常 (2048+GELU)，0.12-0.13 的预测可能是准确的。

---

## 逻辑验证

### 梯度守恒
- [x] 两个 Linear 层无激活函数的梯度链: ∂L/∂W1 = W2^T * ∂L/∂h，梯度通过 W2 缩放。不存在梯度消失/爆炸的额外风险 (线性传播)。
- [x] lr_mult=2.0 对退化架构的影响: 等效于对单层 Linear 使用更大的初始化和更快的学习率。解释了 P6 offset 改善——不是 2048 的功劳。
- [x] bg_balance_weight=2.5 在 P5b 和 P6 中相同，排除此变量。

### 边界条件
- [x] P5b 使用 `proj_use_activation` 默认值 (True)——确认 `vit_git.py:L233` 默认 True
- [x] P5b proj lr_mult=1.0 vs P6 lr_mult=2.0——这是 P6 offset 改善的主要候选原因
- [x] Plan L (2048+GELU+lr_mult=1.0) car_P@1000=0.140——远高于 P6@1000=0.058。这进一步证实 GELU 的关键性。

### 数值稳定性
- [x] P6 退化架构不导致数值问题 (线性层稳定)，但浪费了参数容量
- [x] P5b@6000 vs @3000: car_P 0.115 vs 0.116, off_th 0.194 vs 0.195——P5b 已完全收敛

---

## 关键证据: Plan L 支持 GELU 必要性

Plan L (2048+GELU+lr_mult=1.0):
- @1000 car_P=0.140 (历史最高)
- 仅跑了 2000 iter 的诊断实验

P6 (2048+无GELU+lr_mult=2.0):
- @1000 car_P=0.058

**同样的 2048 宽度，有无 GELU 的差距**: car_P 0.140 vs 0.058 (2.4x)。

虽然 Plan L 有 BUG-28 (vocab 保留优势) 和不同 lr_mult，但 2.4x 的差距远超这些混淆因素能解释的范围。**GELU 是决定性因素。**

---

## 修正后的条件清单 (替代 VERDICT_P6_3000 的条件)

### COND-1: ✅ 已满足
P5b@3000 单 GPU re-eval 完成。car_P=0.116, bg_FA=0.189。

### COND-2 (修正): Plan P — 2048+GELU 验证 [BLOCKING]
- Config: `preextracted_proj_hidden_dim=2048`, `preextracted_proj_use_activation=True` (GELU)
- lr_mult=1.0 (不是 2.0)
- 其他设置与 P6 相同 (10 类, num_vocal=230, bg_balance_weight=2.5)
- load_from P5b@3000
- 500 iter mini, 单 GPU eval
- **判定标准**: car_P@500 > 0.073 (P6@500 水平) 且 bg_FA < 0.200
- 耗时: ~1h

### COND-3 (修正): Plan O — 在线 DINOv3 验证 [BLOCKING for route decision]
- Config: 在线 frozen + 2048 + **GELU** + 10 类
- **必须用 GELU** (去 GELU 会继承 BUG-39)
- 500 iter mini
- 判定: car_P@500 > 0.05 → 在线可行

### COND-4 (新增): P6 是否终止 [Conductor 决策]
- 如果 GPU 0+2 可以立即释放给 Plan P/O → 终止 P6
- 如果 Plan P/O 在 GPU 1+3 上跑 → P6 可继续到 @6000

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-30 | ~~MEDIUM~~ | **INVALID** | GELU 不损害 off_th (P5b=0.195≈P6=0.196)，假设基于被 BUG-27 污染的数据 |
| BUG-39 | **CRITICAL** | NEW | 双层 Linear 无激活函数 = 单层 Linear，P6 2048 中间维度无效 |
| BUG-40 | HIGH | 自我纠正 | Critic 审计链连锁失误: BUG-27→BUG-30→去 GELU 推荐→P6 退化 |

**下一个 BUG 编号**: BUG-41

---

## 附加建议

### 对 Conductor
1. **Plan P 是当前最高优先级实验**。不要直接跳到 full nuScenes。
2. **Plan P 配置极简**: 复制 `plan_p6_wide_proj.py`，改 `proj_use_activation=True`，改 `lr_mult=1.0`，改 `max_iters=500`。
3. **如果 Plan P@500 car_P > 0.10 且 bg_FA < 0.20**: 2048+GELU 是 full nuScenes 的最终 config。
4. **不要用 P6 的 checkpoint 继续训练**: P6 的投影层在退化架构下学到的是线性映射，对非线性架构没有迁移价值。Plan P 必须从 P5b@3000 重新开始。

### 对 Admin
1. Plan P 配置改动极小——只改 2 行 (`proj_use_activation=True`, proj lr_mult 1.0)
2. Plan L 已验证 2048+GELU 的可行性 (car_P@1000=0.140)，Plan P 只是更长、更严格的版本
3. 如果需要在线 DINOv3 config (Plan O)，从 `plan_n_online_frozen_diag.py` 改: `proj_hidden_dim=2048`, `proj_use_activation=True`, `classes=10类`, `num_vocal=230`

### Critic 自我反省
1. VERDICT_DIAG_FINAL 的"推荐纯 Linear 无 GELU"是本审计系统迄今最严重的错误推荐
2. 根因: 对 Plan K 数据的过度信任 (已知 BUG-27 存在时仍用其推导新假设)
3. 未来: 任何架构推荐前必须做数学验证——两层线性无激活=单层线性这种基础知识不应遗漏
4. BUG-30 假设应在提出时就附加"需要独立验证"的标签，而非直接作为架构决策依据
