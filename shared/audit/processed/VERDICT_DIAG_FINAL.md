# 审计判决 — DIAG_FINAL

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: 四路诊断最终数据 + P6 Config 定稿

---

## 结论: CONDITIONAL

宽投影 2048 作为 P6 方向获批，但须满足以下条件。Conductor 对条件 #5 失败的缓和分析**基本成立但过于乐观**。BUG-30 (GELU) 须降级修正。

---

## 通过条件

1. **P6 投影层必须是 Linear(4096,2048) + Linear(2048,768) 无激活函数**——不用 GELU 也不用 LayerNorm（见下方 Q4 分析）
2. **P6 必须先跑 mini 3000 iter**——验证新投影架构有效后再投入 full nuScenes
3. **P6 从 P5b@3000 加载**——proj 层 shape mismatch 将随机初始化，其余完整保留
4. **P6 用 10 类 num_vocal=230**——保持 vocab embedding 兼容
5. **Plan M/N @1000 数据到达后做最终在线 DINOv3 评估**——但不阻塞 P6 启动
6. **bg_balance_weight 考虑从 2.5 提升到 3.0**——宽投影增加了模型容量，bg 误检风险更高

---

## 对 Conductor 七个问题的逐一审计

### Q1: 条件 #5 失败 (bg_FA=0.331)——是否仍批准宽投影?

**批准，但有保留。** Conductor 的五点缓和分析中，前四点成立，第五点部分成立:

1. ✅ 趋势收敛 (0.447→0.331) — 最后 1000 iter 下降 26%，方向正确
2. ✅ 10 类增加误检 — 合理，更多类别 = 更多潜在 FP 来源
3. ✅ 投影层随机初始化 — Plan L proj 从零开始，分类边界不成熟
4. ✅ P6 起点更好 — backbone+head+vocab 完整，优于 Plan L 的起点
5. ⚠️ "bg_FA 不是投影宽度的问题" — **此点需要证据**

关于第 5 点: 宽投影 (2048) 将 DINOv3 4096 维特征压缩到 2048 中间层，保留了更多原始信息。更多信息 = 更强的检测能力，但也意味着更多噪声信号被保留，可能增加 FP。P5b 的 1024 窄投影相当于做了更激进的信息筛选，天然抑制了一些弱信号（包括 FP）。

**结论**: bg_FA=0.331 不构成阻塞条件，但 P6 须设置 bg_FA 监控红线 @1000: bg_FA ≤ 0.30。如果 P6@1000 仍 > 0.30，考虑提升 bg_balance_weight 或 marker_bg_punish。

### Q2: Plan L 宽投影净效果

**正面，但信号弱于 Conductor 声称。**

| 指标 | Plan L @2000 | P5b @2000 | 差值 | 方向 |
|------|-------------|-----------|------|------|
| car_P | 0.111 | 0.094 | +0.017 | ✅ 正面 |
| car_R | 0.512 | 0.856 | -0.344 | ❌ 严重退化 |
| bg_FA | 0.331 | 0.282 | +0.049 | ❌ 恶化 |
| off_cy | 0.074 | 0.113 | -0.039 | ✅ 改善 |
| off_th | 0.205 | 0.208 | -0.003 | ≈ 持平 |

**Plan L car_R=0.512 << P5b car_R=0.856**: 这个 34% 的 Recall 崩塌不能忽视。car_P 的 +18% 提升是以 Recall 严重损失为代价的。Plan L 的 Precision "提升" 部分原因是预测更少 (预测数下降 → FP 减少 → Precision 上升)。

但这可能是投影层随机初始化的暂态效应——P6 从 P5b@3000 加载 (car_R=0.835)，backbone 保持完整，car_R 不应这么低。

**净评估**: 宽投影有潜力 (off_cy 改善显著)，但 Plan L 的数据不能直接预测 P6 的表现。P6 的关键优势是 vocab+backbone 完整加载，这是 Plan L 不具备的。

### Q3: mini 还是直接 full nuScenes?

**先 mini 3000 iter。** 理由:

1. P6 引入新投影架构 (2048 无 GELU)，需要验证基本功能
2. DINOv3 全量特征尚未提取 (BUG-26: ~175GB CAM_FRONT)
3. mini 上 3000 iter 约 4 小时，成本极低
4. 如果 mini@1000 car_P < P5b@1000 (0.089)，说明新架构有问题，避免浪费 full 训练时间
5. CEO 战略是 mini 做 debug，这正是 debug 用途

**mini 通过标准**: P6@1000 car_P ≥ 0.10 且 bg_FA ≤ 0.30。满足则切 full nuScenes。

### Q4: LayerNorm 位置

**都不用。P6 投影层应为纯双 Linear，无激活无归一化。**

分析:
- `Linear(4096,2048) + LN + Linear(2048,768)`: LayerNorm 不是真正的非线性变换。它做的是 normalize + affine，等效于让两层 Linear 的中间表示有单位方差。但 LN 会**抹除通道间的尺度差异**，而 DINOv3 不同通道的尺度差异可能编码了重要的语义信息（如方向、尺度）。
- `Linear(4096,2048) + Linear(2048,768)`: 纯线性组合，等效于一个 rank-2048 的矩阵分解。数学上这等价于 `Linear(4096,768)` 但有更好的优化条件：两个较小矩阵比一个大矩阵更容易用 Adam 优化，且 rank-2048 比 rank-768 保留更多信息。
- 位置: `GiT/mmdet/models/backbones/vit_git.py:L104-109`

**推荐**: `nn.Sequential(nn.Linear(4096, 2048), nn.Linear(2048, 768))`

理由:
1. P5 单层 Linear 的 off_th=0.142 证明线性投影对方向信息友好
2. 宽中间层 (2048) 提供更大的信息容量
3. 无 GELU/ReLU 避免 BUG-30
4. 无 LayerNorm 避免通道尺度信息丢失
5. `kaiming_uniform_` 初始化 (现有代码 L113) 保持不变

### Q5: Plan M/N @500 评估

**不能得出"在线劣于预提取"的结论。** 原因:

1. **BUG-31**: Plan M/N 继承 Plan K 的 BUG-27——`num_vocal=221`，vocab embedding 随机初始化。这意味着 M/N 的性能同样受 vocab reinit 拖累，而非在线 DINOv3 的问题。
2. **@500 在 warmup 期内**: config 的 `end=500` 就是 warmup 结束点，模型刚开始真正训练
3. **M ≈ N**: unfreeze 2 层 vs frozen 无差异 @500，这说明 DINOv3 的 unfreeze 梯度还没来得及产生效果
4. **K > M ≈ N @500**: Plan K 的 preextracted 特征 .pt 文件是确定性加载，而在线 DINOv3 需要 forward pass 计算，可能存在 fp16 精度差异

**建议**: 等 @1000 再判断。如果 @1000 M/N 仍然 ≤ K，则在线路径在 mini 数据上无优势，P6 继续用预提取。

### Q6: GPU 利用与启动时机

**立即创建 P6 config，Plan M/N @1000 到达后（~09:22）启动训练。**

理由:
1. P6 config 创建是零成本操作（不占 GPU）
2. Plan M/N @1000 数据 ~15 分钟后到达，等待成本低
3. 如果 M/N @1000 显示在线 DINOv3 显著优于预提取（car_P 差 >0.03），则 P6 需要改用在线路径，此时已创建的 config 需要修改
4. 如果 M/N @1000 与 K @1000 持平或更差，则 P6 config 确认，立即启动

**但 Conductor 不应等太久**。如果 M/N @1000 在 09:30 前仍未到达，直接启动 P6（预提取路径风险更低）。

### Q7: BUG-30 (GELU) 重新评估

**BUG-30 维持但降级为 MEDIUM。**

Plan K @2000 off_th=0.191 确实在 GELU 下达标了。但需要注意:

| 实验 | 投影 | GELU | off_th 最优 | 备注 |
|------|------|------|------------|------|
| P5 | 4096→768 单层 | ❌ | **0.142** | 无 GELU 基准 |
| P5b | 4096→1024→768 | ✅ | 0.200 | +0.058 vs P5 |
| Plan K | 4096→1024→768 | ✅ | 0.191 | +0.049 vs P5 |
| Plan L | 4096→2048→768 | ✅ | 0.205 | +0.063 vs P5 |

**GELU 一致性惩罚**: 所有 GELU 实验的 off_th 比 P5 差 0.05-0.06。Plan K@2000 的 0.191 虽然达标 (≤0.20)，但仍比 P5 无 GELU 差 0.049。

**BUG-30 修正结论**: GELU 不是"系统性致命损害"，而是"一致性 ~0.05 惩罚"。在宽投影+无 GELU 下，off_th 有望恢复到 P5 水平 (0.14-0.15)，但不确定。降级为 MEDIUM，标注"一致性惩罚但非阻塞"。

---

## 发现的问题

### 1. BUG-31: Plan M/N 继承 BUG-27 的 vocab 不兼容
- **严重性**: HIGH
- **位置**: `GiT/configs/GiT/plan_m_online_dinov3_diag.py:L63-64`, `plan_n_online_frozen_diag.py:L63-64`
- **证据**: `classes = ["car"]`, `num_classes = 1`, `num_vocal = 221` — 与 P5b@3000 的 230 不兼容
- **影响**: M/N 的绝对性能受 vocab reinit 拖累，但 M vs N 的相对比较仍有效（两者损失相同权重）
- **影响 2**: M/N vs K 的 "在线 vs 预提取" 比较仍有效（三者均有相同 vocab reinit）
- **修复建议**: 已完成实验无需修复。仅记录，避免误读数据。

### 2. BUG-32: Plan K @2000 off_cy=0.171 严重退化
- **严重性**: MEDIUM
- **位置**: 数据观察（非代码 BUG）
- **证据**:
  - Plan K off_cy 轨迹: @500(0.082) → @1000(0.073) → @1500(**0.206**) → @2000(**0.171**)
  - @1500 突然跳变 0.073→0.206，与 LR decay @1500 时间吻合
  - P5b off_cy 最优 0.085 (@500)，全程 <0.15
  - Plan K 的 off_cy 退化可能是 vocab reinit + 单类训练的副作用
- **影响**: 不直接影响 P6（P6 不用单类），但暗示 LR decay 后模型可能在某些回归维度上退化
- **对 P6 的警示**: P6 的 LR milestones 设定需谨慎，关注 offset 指标在 decay 后是否退化

### 3. BUG-30 状态更新: GELU 一致性惩罚 (降级 HIGH→MEDIUM)
- **严重性**: MEDIUM (从 HIGH 降级)
- **位置**: `GiT/mmdet/models/backbones/vit_git.py:L108`
- **修正**: 不再称"系统性损害"，修正为"一致性 ~0.05 惩罚"。Plan K@2000 off_th=0.191 证明 GELU 下仍可达标，但比无 GELU 差约 0.05。
- **P6 决策**: 仍建议去掉 GELU（恢复 off_th 空间），但不再是"致命"理由。

---

## 逻辑验证

### Plan L @2000 趋势分析
- car_P 轨迹: 0.054 → **0.140** → 0.103 → 0.111 — @1000 峰值后轻微回落，@2000 回升
- bg_FA 轨迹: 0.237 → 0.407 → 0.447 → 0.331 — **@1500 峰值后急速收敛**，方向正确
- off_th 轨迹: 0.277 → 0.242 → 0.225 → 0.205 — **单调下降**，趋势良好
- truck_R: 0→0.263→0.015→0.360 — 典型振荡 (BUG-20, mini 数据不足)
- [x] Plan L 各指标趋势一致性验证通过

### Checkpoint 加载预测 (P6 from P5b@3000)
- [x] backbone.layers.0-17: ✅ 完整加载
- [x] head (OccHead): ✅ num_vocal=230 一致
- [x] vocabulary_embed: ✅ (230,768) 一致
- [x] backbone.patch_embed.proj: ❌ shape mismatch (1024→2048)，随机初始化
  - 第一层: (1024,4096) → (2048,4096) — 不兼容
  - 第二层: (768,1024) → (768,2048) — 不兼容
- [x] 预计 P6 行为: backbone 和 head 保持 P5b@3000 的能力，仅投影层从零学习

### P6 LR 策略验证
- Conductor 建议"沿用 P5b 策略"：LR=5e-5, warmup 500, milestones 相对
- [⚠] 投影层从随机初始化，可能需要更大的初始 LR (如 1e-4 for proj, 5e-5 for rest)
- [⚠] 或者更长的 warmup (1000 iter) 让 proj 层追上已训练的 backbone
- **建议**: `'backbone.patch_embed.proj': dict(lr_mult=2.0)` — 投影层 LR 倍率提升到 2x

---

## P6 Config 定稿建议

```python
# P6 关键参数
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
preextracted_proj_hidden_dim = 2048
proj 层结构: nn.Sequential(nn.Linear(4096, 2048), nn.Linear(2048, 768))  # 无 GELU, 无 LN
backbone.patch_embed.proj lr_mult = 2.0  # 加速投影层收敛
balance_mode = 'sqrt'
bg_balance_weight = 2.5 (或 3.0 如 bg_FA @1000 > 0.30)
数据: nuScenes-mini (前 3000 iter 验证)
max_iters = 6000 (mini) 或 36000 (full)
warmup = 500
milestones = [2000, 4000] (相对 begin=500)
val_interval = 500

# 监控红线
P6@1000: car_P ≥ 0.10 且 bg_FA ≤ 0.30 → PASS, 否则 STOP 检查
P6@3000: off_th ≤ 0.18 (测试无 GELU 是否恢复方向精度)
```

---

## 附加建议

1. **Plan M/N @1000 快速评判标准**: 如果 M_car_P > K_car_P (0.047) + 0.03 = 0.077，则在线路径有价值；否则在 mini 数据上无优势
2. **off_th 恢复测试**: P6 的核心看点是无 GELU 投影能否恢复 off_th 到 0.14-0.15 水平。如果 P6@2000 off_th > 0.19，则投影宽度本身也是 off_th 退化的因素（非仅 GELU）
3. **不要在 P6 config 中加 LayerNorm**: 信息论角度，LN 抹除通道尺度差异可能破坏 DINOv3 编码的语义信息。纯线性投影是最安全的选择。
4. **Plan L 的 car_P@1000=0.140 峰值**: 可能是学习率在 warmup 结束时的最优点。P6 的 warmup 长度和 milestones 需要仔细设定以利用这个窗口。

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-30 | **MEDIUM** (降级) | OPEN | GELU ~0.05 一致性惩罚 (非致命, Plan K@2000 达标 0.191) |
| BUG-31 | HIGH | 记录 | Plan M/N 继承 BUG-27 vocab mismatch (M vs N 对比仍有效) |
| BUG-32 | MEDIUM | 记录 | Plan K @1500 off_cy 跳变 0.073→0.206 (LR decay 后退化) |

**下一个 BUG 编号**: BUG-33
