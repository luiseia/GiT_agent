# 审计判决 — DIAG_RESULTS

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: 四路诊断实验 @1000 结果与 P6 方向决策

---

## 结论: CONDITIONAL

Conductor 的核心结论——"投影层容量是瓶颈"——**方向正确但论证不可靠**。Plan K 和 Plan L 的实验设计存在致命混淆变量，不能直接用于因果归因。P6 可以采用 2048 宽投影，但必须满足以下条件。

---

## 通过条件（必须全部满足方可定稿 P6）

1. **必须认识到 Plan L 结论是混淆的**——car_P=0.140 的提升无法干净归因于投影宽度，可能部分来自 10 类→10 类的 vocab embedding 保留优势 (BUG-27)
2. **P6 必须使用 10 类**——Plan K 已证明减少类别会破坏预训练特征空间，1 类和 4 类方案均不可取
3. **P6 宽投影须去掉 GELU**——Plan L off_th=0.242 + P5b off_th=0.200 的双重退化趋势指向 GELU 损害方向信息 (BUG-21 升级)
4. **等待 Plan M/N @1000 数据再最终决策**——在线 DINOv3 如果显著优于预提取，则 P6 路径需要改变
5. **Plan L 须跑完 @2000 确认趋势**——@1000 的 bg_FA=0.407 如果到 @2000 不回落到 <0.30，说明宽投影存在假阳性放大问题

---

## 发现的问题

### 1. BUG-27: Plan K 词表不兼容导致实验结论无效 (致命设计缺陷)
- **严重性**: CRITICAL
- **位置**: `GiT/configs/GiT/plan_k_car_only_diag.py:L97` + `GiT/mmdet/models/dense_heads/git_occ_head.py:L261-299`
- **证据**:
  - P5b@3000 checkpoint: `num_vocal=230` (10 类, cls_start=168, marker_near=179, marker_end=182, theta_group_start=183, theta_fine_start=219, ignore_id=229)
  - Plan K config: `num_vocal=221` (1 类, cls_start=168, marker_near=170, marker_end=173, theta_group_start=174, theta_fine_start=210, ignore_id=220)
  - **所有词表偏移量发生位移**: marker 位从 179→170, theta_group 从 183→174，偏移 9 位 (= 9 个被移除的类别)
  - `reset_hyparameter()` (L261-299) 在每次 forward 时重新计算偏移，所以运行时偏移正确
  - **但 vocabulary_embed 矩阵从 (230, 768) 变为 (221, 768)**，shape mismatch 导致 mmdet 加载时跳过该权重，从随机初始化开始
  - `decoder_inference` L1121: `logits = (x @ vocabulary_embed.transpose(0, 1))`——这个 vocab embedding 是全新的随机矩阵
  - **Plan K 的 car_P=0.047 不代表"单类训练更差"，它代表的是"词表重建后仅 1000 iter 的冷启动性能"**
- **影响**: Conductor 的结论 "类竞争诊断: 否定" **不成立**。Plan K 根本没有测试类竞争假说，它测试的是词表兼容性。
- **修复建议**: 如果确实要测试单类效果，必须保持 num_vocal=230 不变，只在 label generation pipeline 中过滤非 car GT。这样 vocab embedding 可以完整加载。

### 2. BUG-28: Plan L 实验设计双变量混淆
- **严重性**: HIGH
- **位置**: 实验设计层面（非代码 BUG）
- **证据**:
  - ORCH_015 原始指定: 4 类 + 宽投影 2048
  - Admin 实际执行: **10 类** + 宽投影 2048 (审计请求已承认此偏差)
  - Plan L 同时改变了: ① 投影宽度 1024→2048 ② 投影层随机初始化 (shape mismatch)
  - Plan L **保留了** 10 类 vocab embedding (num_vocal=230 不变, 可以从 P5b@3000 完整加载)
  - Plan K **丢失了** vocab embedding (num_vocal 230→221, 强制随机初始化)
  - **Plan L vs Plan K 不是"宽投影 vs 窄投影"，而是"保留 vocab + 随机 proj" vs "随机 vocab + 保留 proj"**
- **正确的因果链**:
  - Plan L car_P=0.140 > P5b@1000 car_P=0.089: 可能是宽投影的功劳，也可能是 @1000 时 backbone transformer 已经足够强，加宽投影只是让 proj 更快收敛
  - Plan K car_P=0.047 < P5b@1000 car_P=0.089: 几乎确定是 vocab embedding 丢失导致的，而非单类训练的负面效应
- **修复建议**: 记录此混淆，不要将 Plan L 结果视为"宽投影 = 精度提升"的因果证据。它只是"宽投影 + 多类 vocab 保留 = 好结果"的相关证据。

### 3. BUG-29: Plan K 的 `use_per_class_balance=True` + `balance_mode='sqrt'` 对单类无意义
- **严重性**: LOW
- **位置**: `GiT/configs/GiT/plan_k_car_only_diag.py:L124-125`
- **证据**:
  - config 中 `use_per_class_balance=True`, `balance_mode='sqrt'`
  - 只有 1 个类 (car)，`_cls_counts` 最多只有 1 个 key
  - sqrt 权重公式 `1/sqrt(1/1) = 1.0`，实际上等价于 `balance_mode='equal'`
  - 不影响训练结果，但体现了 Plan K 是机械复制 P5b config 而非针对性设计
- **修复建议**: 无需修复，仅记录

### 4. BUG-30: off_th 持续恶化——GELU 非线性的系统性问题
- **严重性**: HIGH
- **位置**: `GiT/mmdet/models/backbones/vit_git.py:L106-109`
- **证据**:
  - P5 单层 Linear(4096→768): off_th=0.142 (@4000, 历史最优)
  - P5b 双层 GELU(4096→1024→768): off_th=0.200 (@3000)
  - Plan K 双层 GELU(4096→1024→768): off_th=0.254 (@1000, 但有 vocab reinit 干扰)
  - Plan L 双层 GELU(4096→**2048**→768): off_th=0.242 (@1000, proj 随机初始化)
  - **趋势**: 所有使用 GELU 双层投影的实验 off_th 均 > 0.200，而 P5 的单层 Linear 达到 0.142
  - theta 编码 (`theta_group * 10 + theta_fine`) 是高度方向敏感的特征，GELU 的非线性会扰乱角度方向信息
  - `vit_git.py:L108`: `nn.GELU()` 位于两个 Linear 之间，对所有通道施加相同非线性
- **BUG-21 升级**: 不再是"疑似"，现在有三组实验交叉印证
- **修复建议**: P6 的宽投影方案改为 `Linear(4096, 2048) + LayerNorm + Linear(2048, 768)`，用 LayerNorm 替代 GELU，保持特征归一化但不引入非线性失真。或直接用 Linear(4096, 2048) + Linear(2048, 768) 无激活函数。

---

## 逻辑验证

### Checkpoint 加载兼容性分析

| 组件 | P5b@3000 shape | Plan K shape | Plan L shape | 加载结果 |
|------|----------------|-------------|-------------|----------|
| backbone.patch_embed.proj (投影层) | (1024,4096)+(768,1024) | (1024,4096)+(768,1024) | **(2048,4096)+(768,2048)** | K: ✅加载, L: ❌随机 |
| vocabulary_embed | (230, 768) | **(221, 768)** | (230, 768) | K: ❌随机, L: ✅加载 |
| backbone.layers.0-17 (transformer) | — | — | — | K: ✅加载, L: ✅加载 |
| head 权重 (loss_cls 等) | (230,) | (221,) | (230,) | K: ❌随机, L: ✅加载 |

**关键发现**: Plan K 丢失的权重远多于 Plan L。Plan K 不仅丢失 vocab embedding，还丢失 head 中所有与 num_vocal 相关的参数。这是 Plan K 性能差的最可能原因。

### 梯度守恒检查
- [x] 两个 config 的 `clip_grad`, `accumulative_counts`, `optim_wrapper` 与 P5b 完全一致
- [x] LR schedule 合理: warmup 500, milestones [1000, 1500]，2000 iter 诊断窗口
- [x] `reg_loss_weight=1.5` 两者一致

### 边界条件检查
- [x] Plan K `num_vocal=221` 计算正确: (167+1) + 1 + 1 + 4 + 36 + 10 + 1 = 221
- [x] Plan L `num_vocal=230` 与 P5b 一致
- [⚠] Plan K 的 `marker_end_id` = 173 (config L99), 与 P5b 的 182 不同。`reset_hyparameter` 动态计算修正了这点，但 config 中的硬编码值仍传给了 evaluator (L382)。如果 evaluator 使用 config 值而非 head 的动态值，可能导致评估错误。
  - 检查: `val_evaluator` 确实使用 `marker_end_id=marker_end_id` (config L382)，即 173。而 `process()` 用 `self.marker_end_id` 判断背景 (L114)。**Plan K evaluator marker_end_id=173 是正确的**，因为它与 Plan K 的词表一致。

### 数值稳定性检查
- [x] 两个实验使用相同的 loss 计算路径
- [x] 无新的数值风险

---

## 对 Conductor 六个问题的逐一回应

### Q1: 结论可靠性——Plan L 的精度能否归因于投影宽度?
**不能干净归因。** Plan L 改变了投影宽度但保留了 vocab embedding；Plan K 保留了投影宽度但丢失了 vocab embedding。两个实验的 confound 是对称的。Plan L car_P=0.140 是"宽投影 + 保留 vocab embedding"的联合效果。

**但有一个弱推理**: Plan L 的 proj 层是随机初始化的，仅训练 1000 iter 就达到 0.140，而 P5b 的 1024 proj 经过 3000 iter 也只有 0.107。这暗示 2048 的信息容量确实更优，因为随机初始化的 2048 > 训练好的 1024。但这不是严格证明。

### Q2: Plan K 失败分析
**主因是 vocab embedding 重建，而非多类协同丢失。** (BUG-27)

Plan K 的 vocabulary_embed (221, 768) 与 P5b (230, 768) shape 不匹配，被跳过。这意味着 decoder_inference 中的 `logits = x @ vocabulary_embed.T` 从随机矩阵开始。1000 iter 不足以训练好一个全新的 vocab embedding。

如果要干净地测试单类效果：保持 `num_vocal=230` 和 10 类词表，只在 pipeline 中 `classes=["car"]` 过滤 GT。这样 vocab embedding 完整加载，只是标签只有 car 类。

### Q3: Plan L bg_FA=0.407——10 类还是 4 类?
**bg_FA=0.407 在 @1000 不构成警报。** P5b @1000 的 bg_FA=0.302，Plan L @1000 的 0.407 只高了 35%，且 Plan L 的 proj 是随机初始化的（分类边界尚未收敛）。

**建议 P6 用 10 类。** 理由:
1. Plan K 证明减少类别会破坏 vocab embedding 兼容性
2. Plan L 10 类 car_P=0.140 已超越 P5b 4 类的所有历史记录
3. 多类提供正则化效果——更多监督信号帮助 backbone 学习更通用的特征

### Q4: P6 具体建议
```
Config:  plan_p6_wide_proj.py
类别:    10 类 (保持 vocab 兼容)
投影层:  Linear(4096, 2048) + LayerNorm + Linear(2048, 768)  ← 去掉 GELU!
数据:    nuScenes-mini (暂时), 后续切 full
load_from: P5b@3000
预期:    backbone+head+vocab 完整加载, 只有 proj 随机初始化
```

**不用 GELU 的理由**: BUG-30——三组实验一致显示 GELU 损害 off_th。用 LayerNorm 保持归一化但不引入非线性，或完全去掉激活函数让两层 Linear 等效于一个更宽的线性映射（但有更好的初始化条件和训练动态）。

### Q5: Plan M/N 是否还有等待价值?
**有，但优先级降低。** Plan M (在线 unfreeze) 和 Plan N (在线 frozen) 测试的是 DINOv3 在线提取路径。即使 P6 采用宽投影预提取，未来 P7 可能需要在线路径（如果要做数据增强或 full nuScenes 存储不足）。建议等 @1000 数据到达后评估，但不阻塞 P6 启动。

### Q6: off_th 持续恶化
**这是系统性问题，不是随机波动。** (BUG-30)

| 实验 | 投影 | off_th @1000 | GELU |
|------|------|-------------|------|
| P5b | 4096→1024→GELU→768 | 0.168 | ✅ |
| Plan K | 4096→1024→GELU→768 | 0.254 | ✅ |
| Plan L | 4096→2048→GELU→768 | 0.242 | ✅ |
| P5 | 4096→768 (单层) | 0.142* | ❌ |

*P5 的 0.142 是 @4000 非 @1000

Plan K 和 Plan L 的 off_th 都比 P5b @1000 (0.168) 差，但两者都有随机初始化的因素干扰。宽投影不一定会进一步恶化 off_th——Plan L 0.242 vs Plan K 0.254 反而略好。真正的嫌犯是 GELU，但需要 P6 的无 GELU 对比实验来最终确认。

---

## 附加建议

1. **设计控制实验的原则**: 每次只改一个变量，且确保 checkpoint 加载兼容性。词表大小变化 = 无效实验。
2. **Plan L @2000 关注指标**: bg_FA 是否回落到 <0.30, off_th 是否改善，car_P 是否继续上升。如果 car_P @2000 > 0.15 且 bg_FA < 0.30，则宽投影的效果得到强化确认。
3. **P6 投影层初始化策略**: 可以尝试将 P5b@3000 的 1024 维 proj 权重部分复用——例如将 (768, 1024) 的权重 pad 到 (768, 2048)，让一半通道有预训练值。但这需要代码修改，收益不确定。
4. **考虑 no-GELU 的 Plan L 变体 (Plan L')**: 在已有 Plan L 上改一行 config，去掉 GELU，从 Plan L @1000 继续训 1000 iter。这可以直接验证 BUG-30。

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-21 | HIGH | **升级→BUG-30** | GELU 损害 off_th，已从"疑似"升级为"三组交叉印证" |
| BUG-27 | CRITICAL | NEW | Plan K vocab mismatch (230→221) 导致 vocab embedding 随机初始化，实验结论无效 |
| BUG-28 | HIGH | NEW | Plan L 双变量混淆 (投影宽度 + vocab 保留 vs Plan K 的 vocab 丢失) |
| BUG-29 | LOW | 记录 | Plan K 的 sqrt balance 对单类无意义 (不影响结果) |
| BUG-30 | HIGH | OPEN | GELU 非线性系统性损害方向特征 (off_th)，三组实验一致 |

**下一个 BUG 编号**: BUG-31
