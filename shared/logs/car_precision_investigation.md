# Car Precision 调查报告
> 撰写: Conductor | 时间: 2026-03-09 ~03:00 | Cycle #107
> CEO 指令: 单类实验设计 + 5 类评估 + 特征漂移分析 + ORCH_024 进展

---

## 1. 干净的单类 Car 实验设计

### Plan K 失败原因回顾
Plan K 用 `num_classes=1, num_vocal=221`，而 P5b 用 `num_vocal=230`。加载 checkpoint 时 vocab_embed 形状不匹配 (221 vs 230) → 随机重新初始化 → 结果不可信 (BUG-27)。

### 新设计: Plan Q (Single-Car Diagnostic)

**核心思路**: 保持模型架构完全不变 (num_vocal=230, num_classes=10)，**只在数据管道中过滤标注**。

```python
# plan_q_single_car_diag.py — 基于 plan_full_nuscenes_gelu.py
# 模型配置: 完全不改
num_vocal = 230      # 与 ORCH_024 完全相同
num_classes = 10     # 保持 10 类 slot
preextracted_proj_hidden_dim = 2048
preextracted_proj_use_activation = True  # GELU

# 数据管道: 只加载 car 类标注
# 方法: 在 GenerateOccFlowLabels 中添加 class_filter=['car']
# 或: 在 LoadAnnotations3D_E2E 中过滤 gt_labels != 0 (car=0)

# 训练配置 (mini 诊断)
max_iters = 3000     # 比 Plan K 更长, 允许充分收敛
val_interval = 500
dataset = 'nuscenes_mini'
load_from = 'P5b@3000'  # 或 ORCH_024@4000
accumulative_counts = 1  # mini 不需要梯度累积
```

**关键优势**:
1. **vocab_embed 完全兼容** — 可从任何 230-vocab checkpoint 加载, 零 shape mismatch
2. **干净对照** — 与 P6/Plan P2 (10 类 mini) 直接可比
3. **BUG-27 完全避免** — 架构零修改

### 判定标准

| Plan Q 单类 car_P | 对比 P6@4000 (0.126) | 结论 |
|-------------------|---------------------|------|
| > 0.20 | +59%+ | **类竞争是主要瓶颈** → 优先解决类平衡 |
| 0.15-0.20 | +19-59% | 类竞争是 contributing factor → BUG-17 修复优先级上升 |
| 0.12-0.15 | ±20% | **类竞争不是瓶颈** → 瓶颈在投影/解码/特征 |
| < 0.12 | 持平或更差 | 类竞争无关 → 瓶颈在其他地方 |

### 实现工作量

**代码修改**: 在 `GenerateOccFlowLabels` 中添加 class filter 参数 (约 10 行代码):
```python
# git_occ_head.py 或标签生成 pipeline
if self.class_filter is not None:
    mask = torch.tensor([name in self.class_filter for name in gt_class_names])
    gt_bboxes = gt_bboxes[mask]
    gt_labels = gt_labels[mask]
```
或更简单：在 config 中用 `filter_classes=['car']` 参数控制数据加载。

**Config**: 复制 plan_full_nuscenes_gelu.py → plan_q_single_car_diag.py，改训练数据集为 mini，加 class_filter。

**预计工时**: 2-3 小时 (含代码修改 + 验证 + 训练)。

### ⚠️ GPU 约束

**当前 ORCH_024 占用全部 4 GPU (每卡 37 GB / 48 GB)**。CEO 建议用 GPU 1 或 3，但:
- 每卡仅剩 ~11 GB 空闲
- 如果使用**预提取特征** (不加载 DINOv3 7B 模型)，mini 实验约需 8-10 GB → **可能可以共享 GPU** (batch_size=1)
- 如果使用**在线 DINOv3**，需额外 ~20 GB → **无法共享**
- 建议: 用预提取特征 + GPU 共享 (有 OOM 风险) 或等 @6000 val 间隙暂停 ORCH_024 跑诊断

### 是否值得现在做?

**我的判断: 值得做，但建议用预提取特征在 mini 上快速诊断。**

理由:
1. Plan K 因 BUG-27 无效 → "类竞争是否是瓶颈" 这个问题从未被干净回答
2. 答案直接影响后续策略: 如果类竞争是瓶颈 → BUG-17 修复 (balance_mode) 应立即优先; 如果不是 → 继续等 @8000
3. Mini 诊断不违反 Rule #5 — 这是"诊断/BUG 发现"而非"架构决策"
4. 预提取特征避免加载 DINOv3, VRAM 需求低，可与 ORCH_024 共享 GPU

**但要注意**: 即使 mini 上类竞争显著，Full nuScenes 的结论可能不同 (数据量 100x)。Mini 结果只提供方向性信号。

---

## 2. 5 类车辆方案评估

### 方案概述
只训练 5 类车辆: car, truck, bus, trailer, construction_vehicle。
移除: pedestrian, motorcycle, bicycle, traffic_cone, barrier。

### 优势
1. **类间相似性高**: 5 类都是车辆，几何属性相似 (长方体、有朝向)，减少类间混淆
2. **BUG-17 缓解**: 车辆类别数量比更均衡 (car:100K, truck:12K, bus:4K, trailer:3K, CV:2K)。sqrt balance 的极端比值从 ~124:1 (car:bicycle) 降到 ~50:1 (car:CV)
3. **移除干扰类**: bicycle (154K FP!) 和 pedestrian (形态完全不同) 被移除，不再分散模型容量
4. **BEV 表示更一致**: 车辆在 BEV 下的 footprint 都是矩形旋转体，非车辆类 (行人=点、锥桶=点) 的 BEV 表示与车辆差异大

### 风险
1. **最终仍需 10 类**: nuScenes 基准要求 10 类，5 类只是中间步骤
2. **迁移成本**: 从 5 类训好的模型扩展到 10 类可能需要重新调参
3. **丢失信息**: 非车辆类的标注作为背景噪声，可能干扰 bg/fg 判别

### Vocab 调整

**推荐方案: 保持 num_vocal=230, num_classes=10 不变**

与单类实验相同策略: 模型架构零修改，只在数据管道中过滤标注。

```python
# 方案 A (推荐): 数据过滤
class_filter = ['car', 'truck', 'bus', 'trailer', 'construction_vehicle']
# 非车辆类标注被忽略，对应 cell 视为背景

# 方案 B (不推荐): 修改 num_classes
num_classes = 5
num_vocal = 225  # → BUG-27 再现! vocab_embed 不兼容!
```

### Checkpoint 加载

- **从 ORCH_024 @4000+ 加载**: ✅ 完全兼容 (方案 A)。模型已学到部分 car/truck/bus 检测能力
- **从头开始**: ❌ 不推荐。浪费已有训练成果
- **注意**: 加载后非车辆类 slot 不再收到正样本，对应权重会逐渐退化但不影响车辆类

### 显存和速度差异

**几乎无差异。** 原因:
- AR 序列长度由 grid 和 slot 数决定 (400 cells × 30 tokens)，与类别数无关
- 分类 logits 维度 (10 vs 5) 在总计算量中可忽略
- DINOv3 backbone 计算量完全不变
- 显存: 标注数量减少 ~30% → 正样本 loss 计算略少，但对总显存影响 <1%

### 我的评估

**5 类方案作为诊断有价值，但不建议作为主训练策略。**

理由:
1. ORCH_024 已经在学习多类 (truck 出现)，5 类方案会丢弃这个进展
2. 最终目标是 10 类，中间切 5 类增加迁移成本
3. **更好的替代**: 修复 BUG-17 (balance_mode='log') 直接解决类竞争，而不是回避它
4. 如果要做，建议作为 mini 诊断 (类似 Plan Q)，不在 Full 上执行

---

## 3. 特征漂移深度分析

### Plan M 崩溃回顾

| 指标 | Plan M (unfreeze) | Plan N (frozen) | 差异 |
|------|-------------------|-----------------|------|
| car_R | 0.489 | 0.699 | -30% ❌ |
| car_P | ~0.05 | ~0.05 | 持平 |

**注意**: Plan M/N 都有 BUG-31 (num_vocal=221 继承自 BUG-27)。绝对值不可信，但 M vs N 的**相对差异**有效。

### 漂移发生在哪些层?

Plan M 配置: `online_dinov3_unfreeze_last_n=2`，即解冻 DINOv3 ViT-7B 的最后 2 个 transformer block。

DINOv3 ViT-7B 结构:
- 40 个 transformer blocks (layers 0-39)
- Plan M 解冻 layer 38-39
- 特征提取在 layer 16 (`online_dinov3_layer_idx=16`)

**关键发现**: 解冻的是 layer 38-39，但特征提取在 layer 16。这意味着:
- Layer 16 的输出**不直接受 unfreeze 层的梯度影响** (Layer 16 << Layer 38)
- 但反向传播会穿过 layer 16 到更早层，间接改变 layer 16 的特征
- `lr_mult=0.02` → 实际 LR = 5e-5 × 0.02 = 1e-6，非常保守
- **即使如此仍发生崩溃**: 说明 DINOv3 的预训练表示非常脆弱，任何微调都会破坏中间层特征的分布

### Plan N (frozen) car_P=0.05 的含义

**不能简单解读为 "DINOv3 与任务有本质 gap"**:
1. Plan N 受 BUG-27/31 影响 (num_vocal=221)，绝对性能被拖累
2. Plan N 用 proj_dim=1024 (非 ORCH_024 的 2048)，投影容量更低 (BUG-36)
3. ORCH_024 @4000 car_P=0.078 > Plan N (在更公平条件下)
4. ORCH_024 用 2048+GELU + frozen DINOv3 + num_vocal=230，是真正公平的测试

**结论**: DINOv3 frozen 特征是可用的，car_P=0.078 证明了这一点。Plan N 低是因为多个 BUG 叠加，不是特征 gap。

### LoRA 方案评估 (方案 E)

| 参数 | 值 |
|------|-----|
| LoRA rank | 16 |
| 额外参数量 | ~12M |
| 额外 VRAM | ~2 GB |
| 应用位置 | DINOv3 最后 N 层的 QKV projection |
| 预期效果 | 域适应不破坏预训练特征分布 |

**LoRA 优势**:
1. 不修改原始权重 → 不会像 Plan M 那样漂移
2. 低秩适配器学习 task-specific 残差
3. 可与 frozen backbone 兼容: DINOv3 frozen + LoRA adapters trainable
4. VRAM 增加可控 (~2 GB)

**LoRA 风险**:
1. 需要实现 DINOv3 backbone 的 LoRA 集成 (代码工作量: 中等, 1-2 天)
2. LoRA 作用在 layer 38-39 但特征提取在 layer 16 → 可能无效
3. 需要将 LoRA 应用到 layer 14-18 (围绕提取层) 才有意义

**我的建议**: LoRA 在 ORCH_024 完成后评估。当前优先级: BUG-17 修复 >> 方案 D (历史 occ box) >> LoRA。

---

## 4. ORCH_024 Full nuScenes 进展

### 当前状态
- **进度**: 4720/40000 (11.8%)
- **实际训练量**: 1180 optimizer steps (因 accumulative_counts=4, BUG-46), 其中 post-warmup 仅 680 steps
- **ETA**: ~3/11 13:58

### Val 结果汇总

| 指标 | @2000 (0.57 ep) | @4000 (1.14 ep) | 趋势 |
|------|-----------------|-----------------|------|
| car_P | 0.079 | 0.078 | → 持平 |
| car_R | 0.627 | 0.419 | ↓ 停止 spam |
| truck_P | 0.000 | 0.057 | ↑ 新类! |
| bicycle_R | 0.000 | 0.191 | ↑ (但 P=0.001, 154K FP) |
| bg_FA | 0.222 | 0.199 | ↓ ✅ |
| off_th | 0.174 | 0.150 | ↓ ✅✅ |

### 类竞争是否缓解?

**@4000 呈现典型的类竞争展开过程**:
1. car_R 从 0.627 降到 0.419 — 模型不再只 spam car，开始分配容量给其他类
2. truck 首次出现 (P=0.057) — 模型开始学习第二大类
3. bicycle 大量 FP (154K) — BUG-17 的 sqrt balance 导致稀有类被过度激励
4. car_P 持平 — 可能是类竞争暂时消耗了 car 精度的提升空间

**但 Critic (VERDICT_FULL_4000) 指出**:
- 500 post-warmup optimizer steps 远不够下结论
- Mini 经验显示 car_P 突破在 LR decay 后
- Full 第一次 LR decay @17000，距当前还有 12000+ iter
- **应等 @8000 (1500 post-warmup steps) 再评估**

### 类竞争的间接证据

| 证据 | 支持类竞争 | 反对类竞争 |
|------|----------|----------|
| car_P 持平 | ✓ 被其他类分散 | 也可能是训练不足 |
| bicycle 154K FP | ✓ BUG-17 过度激励稀有类 | BUG-17 问题, 不是类竞争本身 |
| truck 出现 | ✓ 模型开始分配容量 | 正常多类学习 |
| car_R 下降 | ✓ 不再单一聚焦 car | 再平衡是健康的 |

**结论**: 有间接证据但不充分。@4000 太早下结论 (BUG-46)。

---

## 5. 行动建议

### 推荐: 签发 Plan Q 单类诊断 (ORCH_026)

**理由**:
1. "类竞争是否为瓶颈" 从未被干净回答 (Plan K = BUG-27)
2. 答案影响 BUG-17 修复优先级和 @8000 策略选择
3. Mini 诊断 = 代码验证/BUG 发现, 不违反 Rule #5
4. 使用**预提取特征** + **单 GPU** (不加载 DINOv3)，可与 ORCH_024 共享 GPU

### GPU 方案

**方案 A (推荐)**: 预提取特征 + GPU 共享
- 不加载 DINOv3 7B → VRAM 需求 ~8-10 GB
- ORCH_024 每卡 37/48 GB → 剩余 ~11 GB
- batch_size=1, workers=2 → 可能刚好塞下
- 风险: OOM → 减小 batch 或换 GPU

**方案 B**: 等 @6000 val 间隙
- @6000 val (ETA ~05:30) 时 ORCH_024 暂时释放计算资源但不释放 VRAM
- 不可行: ORCH_024 不会释放 GPU

**方案 C**: 等 ORCH_024 完成后做
- 最安全但要等 ~2.5 天

### ⚠️ 不签发 ORCH 的情况

如果 CEO 认为:
1. @4000 数据 + VERDICT_FULL_4000 已足够回答类竞争问题 (Critic 认为 500 optimizer steps 太早)
2. 应严格遵循 Critic 建议 "不做任何修改直到 @8000"
3. GPU 共享风险不可接受

则不签发，等 @8000 再决策。

---

## 总结决策矩阵

| 行动 | 时机 | 依赖 | 建议 |
|------|------|------|------|
| **Plan Q 单类 car 诊断 (mini)** | **立即** | 需代码修改 + GPU 共享 | **✅ 推荐** |
| 5 类方案 (mini 诊断) | Plan Q 后 | Plan Q 结果 | ⚠️ 可选 |
| 5 类方案 (Full 训练) | @8000+ | Plan Q + @8000 结果 | ❌ 暂不推荐 |
| BUG-17 修复 (balance_mode) | @8000 | @8000 car_P | 准备 config |
| LoRA (方案 E) | ORCH_024 后 | 方案 D 后 | 排队 |

---

*Conductor 签发 | 2026-03-09 ~03:00*
