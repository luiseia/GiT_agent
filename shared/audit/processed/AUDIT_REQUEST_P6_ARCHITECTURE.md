# 审计请求 — P6_ARCHITECTURE
- **状态**: PENDING
- **审计对象**: P6 架构改进方案 (CEO + Conductor)
- **签发人**: Conductor (Cycle #65)
- **签发时间**: 2026-03-08

---

## 背景

P5b 即将完成 (iter 5910/6000)。P5b 使用双层投影 Linear(4096,1024)+GELU+Linear(1024,768)，三项修复后模型在 @3000 后冻结。关键问题：

1. **car_P 仅 0.105** — 检测到的 car 中仅 10.5% 精度，说明特征区分度不足
2. **off_cx/cy/th 红线未达标** — 偏移精度受限，可能与特征压缩有关
3. **bus 振荡 (BUG-20)** — 已确认为 mini 数据量天花板，非模型 bug
4. **DINOv3 2.1TB 存储 BLOCKER** — P6 全量训练的前置障碍

P5b 完整轨迹 (供 Critic 分析):

| Ckpt | car_R | car_P | truck_R | bus_R | trailer_R | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|---------|-------|-----------|-------|--------|--------|--------|
| @500 | 0.856 | 0.080 | 0.153 | 0.014 | 0.000 | 0.235 | 0.068 | 0.085 | 0.210 |
| @1000 | 0.760 | 0.089 | 0.568 | 0.368 | 0.000 | 0.302 | 0.049 | 0.122 | 0.168 |
| @1500 | 0.924 | 0.091 | 0.390 | 0.000 | 0.000 | 0.333 | 0.064 | 0.144 | 0.203 |
| @2000 | 0.856 | 0.094 | 0.340 | 0.085 | 0.028 | 0.282 | 0.055 | 0.113 | 0.208 |
| @2500 | 0.831 | 0.094 | 0.287 | 0.470 | 0.444 | 0.283 | 0.073 | 0.112 | 0.212 |
| @3000 | 0.835 | 0.107 | 0.205 | 0.051 | 0.389 | 0.217 | 0.059 | 0.112 | 0.200 |
| @3500 | 0.819 | 0.108 | 0.234 | 0.053 | 0.417 | 0.214 | 0.060 | 0.116 | 0.206 |
| @4000 | 0.792 | 0.105 | 0.229 | 0.060 | 0.417 | 0.211 | 0.059 | 0.132 | 0.196 |
| @4500 | 0.788 | 0.105 | 0.238 | 0.059 | 0.417 | 0.210 | 0.059 | 0.130 | 0.202 |
| @5000 | 0.788 | 0.105 | 0.239 | 0.059 | 0.417 | 0.210 | 0.059 | 0.132 | 0.201 |
| @5500 | 0.777 | 0.104 | 0.243 | 0.058 | 0.417 | 0.209 | 0.058 | 0.134 | 0.202 |

---

## 一、CEO 方案 — DINOv3 适配层改进

### 方案 A: 增加适配层
- **提议**: Linear(4096,1024)+GELU+Linear(1024,768)
- **Conductor 注**: ⚠️ **P5b 已经实现了这个方案**。P5b 的双层投影就是 Linear(4096,1024)+GELU+Linear(1024,768)。结果表明：bg_FA 从 baseline 显著改善 (0.209), 但 car_P 仍然只有 0.105, off_th 在红线边缘。
- **如果 CEO 意指在此基础上进一步增加层数**，需评估边际收益。

### 方案 B: DINOv3 Unfreeze (部分层)
- **提议**: 解冻 DINOv3 部分层 + 更多适配层
- **Conductor 补充分析见下方 §三**

### 验证策略
- **提议**: nuScenes-mini 上 car 单类训练验证
- **目的**: 确认类别竞争是否是 Recall/Precision 无法同时提升的原因

---

## 二、CEO 方案 — 3D 空间编码路线图

### 历史 Occ Box 编码
- **范围**: 先做车辆相关类 (car/truck/bus/trailer/construction_vehicle)
- **时间窗口**: CEO 建议只用最近 1 个时刻
- **分阶段**: 历史 occ box → ego 轨迹 → V2X

### Conductor 对时间窗口的补充见 §三.4

---

## 三、Conductor 补充方案与分析

### 1. DINOv3 适配层 — 进阶方案

**现状**: P5b 双层投影 (4096→1024→768) 已实现，压缩比从 5.3:1 降至 5.3:1→1.3:1 (两步)。

**Conductor 替代方案 C: LoRA Adapter**
- 在 DINOv3 最后 2-4 层加 LoRA (rank=16~64)，而非 full unfreeze
- 优势:
  - 参数增量极小 (~0.5-2M vs DINOv3 全量 ~1B)
  - GPU 显存增加有限 (比 full unfreeze 节省 80%+)
  - 不会导致 DINOv3 预训练知识灾难性遗忘
  - PyTorch 实现成熟 (peft 库)
- 劣势:
  - 需要引入新依赖 (peft)
  - LoRA rank 和目标层选择需要调优
- **建议**: 如果方案 B (full unfreeze) 显存不可行，LoRA 是更实际的替代

**Conductor 替代方案 D: 宽中间层**
- 将中间维度从 1024 提升到 2048: Linear(4096,2048)+GELU+Linear(2048,768)
- 优势: 最小代码改动，减少信息压缩损失
- 劣势: 参数量从 ~5M 增至 ~10M，训练稍慢
- 比 LoRA 更简单，可作为 LoRA 前的快速尝试

### 2. DINOv3 Unfreeze 风险与收益分析

**收益**:
- 特征直接适配 BEV 占用检测任务，理论上上限更高
- 消除 frozen backbone 作为信息瓶颈
- 在完整 nuScenes (28K samples) 上有足够数据支撑微调

**风险**:
- **显存爆炸**: DINOv3 (ViT-G/14) 约 1.1B 参数。Unfreeze 后半部分 (~6 层) 需额外 ~8-12 GB 显存/GPU，当前 20.5 GB 已接近 24 GB 上限
- **训练变慢**: 反向传播通过 DINOv3 层，每 iter 时间大幅增加
- **灾难性遗忘**: 学习率需要极低 (1e-6 量级)，否则破坏预训练特征
- **与 DINOv3 预提取冲突**: 如果 unfreeze，就不能使用预提取特征 — 这反而**解决了 2.1TB 存储 BLOCKER**
- **调参维度爆炸**: backbone LR, head LR, unfreeze 层数, warmup 策略都需要调

**Conductor 建议**: 风险高，但如果走在线提取路线 (即不预提取特征)，unfreeze 反而是自然选择。建议:
1. 先试方案 D (宽中间层)，最小改动验证瓶颈
2. 如果方案 D 仍无显著改善，再走 LoRA (方案 C)
3. Full unfreeze (方案 B) 作为最后手段，且仅在完整 nuScenes 上尝试

### 3. 单类 Car 验证 — Conductor 扩展建议

CEO 提议在 mini 上做 car 单类验证是正确的诊断方向。Conductor 建议:

- **实验 α**: 单类 car (mini) — 验证无竞争时 car_P 能否显著提升
- **实验 β**: 4 类 (car/truck/bus/trailer, mini) — 当前 baseline 对照
- **对比指标**: 重点看 car_P 和 off_th
- **如果 α car_P >> β car_P**: 确认类别竞争是瓶颈 → 需要 per-class head 或类别解耦策略
- **如果 α car_P ≈ β car_P**: 竞争不是主因 → 瓶颈在特征质量或架构层面

Mini 的 car 标注约 3000 个，足以做诊断性验证 (非性能评估)。训练 1000-2000 iter 即可观察趋势。

### 4. 历史 Occ Box 时间窗口 — Conductor 批判

**CEO 建议**: 只用最近 1 个时刻 (t-1)

**Conductor 分析**:
- nuScenes 标注频率 2Hz → t-1 = 0.5 秒前
- 0.5 秒内，60 km/h 的车移动 ~8.3 米 (约 1 个 cell)
- 单时刻 (t-1) 能提供: 空间占用先验 + 粗略运动方向
- 无法提供: 准确速度估计、加减速判断

**Conductor 同意 CEO 方案**:
- 1 时刻是正确的 MVP 起点
- 原因: 实现简单、验证快、token 序列长度增加可控
- 如果 t-1 有效，P7b 再扩展到 t-2, t-3 (1-1.5 秒窗口)
- ⚠️ 注意: 时间窗口越长，输入 token 序列越长，self-attention 计算量 O(n²) 增长

### 5. DINOv3 存储 BLOCKER 解决方案 (Conductor 补充)

**Conductor 推荐方案: 在线提取 (fp16) + 缓存策略**
- 将 DINOv3 以 fp16 常驻 GPU 1 或 GPU 3 (空闲)
- 训练时在线提取特征，不存盘
- 用 LRU 缓存 (内存级) 缓存最近 N 个样本的特征
- 优势: 零存储开销，完美解决 2.1TB 问题
- 劣势: 训练速度下降 ~30-50%，需占用 1 个 GPU 给 DINOv3
- **注**: 如果走方案 B (unfreeze)，在线提取是必须的，BLOCKER 自然消失

---

## 请 Critic 审计的关键问题

1. **方案 A (P5b 双层投影) 是否已触顶**？P5b@3000 后模型冻结，car_P 0.105 是否为此架构上限？
2. **方案 B (unfreeze) vs C (LoRA) vs D (宽中间层)**，哪个性价比最高？
3. **单类 car 实验是否值得做**？还是应直接上完整 nuScenes 跳过诊断？
4. **历史 occ box 单时刻 MVP 是否足够**？
5. **在线 DINOv3 提取是否可行**？显存预算和训练速度影响评估
6. **P6 整体优先级排序**: (a) 完整 nuScenes 训练 vs (b) 架构改进实验 vs (c) 历史 occ box，应该先做哪个？

---

## 上下文文件
- P5b config: `GiT/configs/GiT/plan_i_p5b_3fixes.py`
- P6 config: `GiT/configs/GiT/plan_j_full_nuscenes.py`
- DINOv3 投影: `GiT/mmdet/models/detectors/git.py` (concept_generation + DINOv3 projector)
- Occ head: `GiT/mmdet/models/dense_heads/git_occ_head.py`
- ORCH_014 结果: `shared/pending/ORCH_0308_0610_014.md`
- VERDICT_P5B_3000: `shared/audit/processed/VERDICT_P5B_3000.md`
