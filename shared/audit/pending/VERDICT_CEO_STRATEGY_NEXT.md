# 审计判决 — CEO_STRATEGY_NEXT

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: CEO 战略方案 (A-D) + Conductor 补充方案 (E-G) + GPU 资源分配

---

## 结论: CONDITIONAL — 不中断 ORCH_024，等 @2000 结果再决策

**核心原则**: ORCH_024 (Full nuScenes 2048+GELU) 是 7 天 mini 验证的结晶。中断它去做任何 mini 实验都是浪费。CEO 的方案签发于 06:56，早于 ORCH_024 启动 (16:10)。方案 A 已被 ORCH_024 涵盖。方案 B/C/D/E/F 都是**后续优化**，应在 ORCH_024 @2000 eval 后根据数据决策。

---

## 方案逐一评估

### 方案 A: 更深投影 Linear(4096,1024)+GELU+Linear(1024,768) — ✅ 已涵盖

**已被 ORCH_024 超越。无需额外实验。**

CEO 的担忧（5.3:1 压缩瓶颈）完全正确——这正是 P5→P5b→P6 的核心改进方向。但 ORCH_024 已经使用 2048 hidden dim（2:1 + 2.7:1 两级压缩），是 CEO 方案 A (1024) 的严格更强版本。

证据:
- P5b (1024+GELU): car_P=0.116, bg_FA=0.189
- P6 (2048+noGELU): car_P=0.129 (@6000)
- Plan P2 (2048+GELU): car_P=0.112 (@1500, 收敛中)
- 2048 > 1024 在 offset 精度上有巨大优势 (off_cx -38%, off_cy -30%)

**不需要回退到 1024**。CEO 提出的方向正确，ORCH_024 已经走在更优的路上。

### 方案 B: DINOv3 Unfreeze — ❌ 当前不可行

**三重否决: 显存、特征漂移、GPU 占用。**

**1. 显存不可行**

DINOv3 ViT-7B 参数结构（估算）:
- 每个 Transformer block: ~280M 参数（7B / ~25 blocks）
- Unfreeze 2 blocks: ~560M 新增可训练参数
- AdamW 优化器状态: 每参数 8 bytes (fp32 first/second moment)
- 梯度: 每参数 4 bytes (fp32)
- 总额外显存: 560M × (4+8) bytes ≈ **6.7 GB**
- 加上激活值缓存（取决于 batch size 和序列长度）: 估计 **8-15 GB**
- 当前 frozen 占用 36-37 GB/GPU → unfreeze 需 **50+ GB → 超出 A6000 48GB**

即使用 gradient checkpointing 和混合精度可能勉强挤进 48GB，训练速度会大幅下降，且稳定性堪忧。

**2. BUG-35 特征漂移**

Plan M (unfreeze last 2 layers) 在 mini 上: car_R 从 0.699 崩塌到 0.489 (-21%)。虽然 mini 数据量不足可能加剧漂移，但在 full nuScenes 上首次尝试 unfreeze 风险依然很高。

**3. GPU 全部占用**

4 GPU 都在跑 ORCH_024。没有资源做 unfreeze 实验。

**结论: 方案 B 搁置到 ORCH_024 完成后。如果要做 DINOv3 域适应，方案 E (LoRA) 是更好的替代。**

### 方案 C: 单类 Car 验证 — ⚠️ 不要改 vocab，保持 10 类看 car 指标

**CEO 的逻辑正确，但实验设计需要修正。**

CEO 的论点: "如果单类 car 都不行，多类只会更差"——这作为下界测试是合理的。

**但 BUG-27 教训不可忽视**: Plan K 将 `num_vocal` 从 230 降到 221，导致 vocab embedding 完全重新初始化，实验结果不可比。任何改变 `num_vocal` 的单类实验都会重蹈覆辙。

**替代方案 (推荐)**:
- 保持 10 类 config，`num_vocal=230` 不变
- 只看 car 相关指标 (car_P, car_R, car_F1)
- 这正是 mini 阶段所有实验的做法——car 一直是核心关注类
- **无需额外实验**。ORCH_024 @2000 eval 自然提供 car 单类指标。

**如果 CEO 坚持做单类实验**: 保持 `num_vocal=230`，设 `classes=["car"]`，但在 label 生成中将其他类标注视为 background。这样 vocab embedding 不变，结果可与多类实验对比。但说实话，这个实验价值有限——ORCH_024 已在跑。

### 方案 D: 历史 Occ Box 时间编码 — ✅ 方向正确，但时机不对

**这是真正的下一步创新方向。但应在 ORCH_024 验证基础架构后再启动。**

**时间窗口分析**:

nuScenes keyframe 间隔 0.5s:
- 1 帧 (0.5s): 60 km/h → 移动 8.3m。可检测有无物体存在，但方向/速度信息不足
- 2 帧 (1.0s): 可估算速度方向（两点定向量）。16.6m 位移足以判断运动方向
- 3 帧 (1.5s): 可估算加速度（三点定曲率）。但计算/内存成本高 3x
- CEO 的 1 帧 vs Conductor 的 2-3 帧

**Critic 建议: 2 帧 (1.0s)**。理由:
1. 1 帧的纯存在信息价值有限——当前模型已经在做的就是单帧预测
2. 2 帧最小投入获取速度方向，这是 BEV 占用预测最需要的时间信息
3. 3 帧的加速度信息对 0.5s 级别的短期预测帮助有限，不值得额外成本

**编码方式建议**:
- **方案 1 (简单)**: 历史帧的 BEV 预测/GT 作为额外 token 拼接在当前 token 之前。每帧额外 400 cells × 30 tokens = 12000 tokens → 太多。
- **方案 2 (推荐)**: 历史帧的 BEV occupancy 编码为一个固定长度的 grid feature map (10×10 = 100 维 embedding)，通过 cross-attention 与当前 decoder 交互。
- **方案 3 (轻量)**: 历史帧 occupancy 作为条件信号直接加到 BEV cell 的 query embedding 中。最简单，实现快。

**CEO 建议的车辆类优先**: 完全正确。大目标 + 可预测轨迹 + GT 充足。行人/自行车运动模式太不规则，历史信息价值低。

**时间线**:
- **不在 ORCH_024 运行期间启动。** 需要修改数据加载、标签生成、模型结构——这是大改动。
- ORCH_024 完成后 (3 月 11 日+)，如果基础架构验证成功，开始实现方案 D
- 预计实现: 1-2 天代码开发，1-2 天 mini 验证，然后 full 训练

### 方案 E: LoRA/Adapter — ✅ 最佳 DINOv3 域适应方案

**如果要做 DINOv3 适应，这是唯一实际可行的路径。**

与方案 B (unfreeze) 对比:

| 维度 | Unfreeze (B) | LoRA (E) |
|------|-------------|----------|
| 新增参数 | ~560M | ~10-50M |
| 显存增量 | ~15-20 GB (超限) | ~2-5 GB (可控) |
| 特征漂移风险 | 高 (BUG-35) | 低 (原始权重冻结) |
| 训练稳定性 | 低 (大模型微调) | 高 (小参数低秩) |
| 实现复杂度 | 低 (改几行 requires_grad) | 中 (需要插入 adapter 模块) |

**LoRA 实验设计** (ORCH_024 后执行):
- 在 DINOv3 每层 attention 后插入 LoRA (rank=16 起步)
- 新增参数: ~12M (远小于 unfreeze)
- 在 full nuScenes 上训练 (不在 mini 上，mini 数据量不足以训练 adapter)
- 基线对比: ORCH_024 结果 (frozen DINOv3)

**优先级**: 低于方案 D (历史 occ box)。理由: DINOv3 已经提供了足够好的特征 (frozen 模式在 mini 上 car_P=0.13)。域适应是锦上添花，不是当务之急。

### 方案 F: 多尺度 DINOv3 特征聚合 — ⚠️ 有潜力但复杂度高

**当前只用 Layer 16 (最终层)。多尺度可能帮助小目标。**

但:
1. 在线 DINOv3 模式下，提取中间层特征增加显存开销（每层 4096 维 × N_patches）
2. FPN 式聚合需要额外的 conv/attention 模块
3. 实现复杂度高，调参空间大
4. 当前 precision 瓶颈可能不是特征层次问题——更可能是 slot 编码和 autoregressive 解码的限制

**建议**: 搁置到方案 D/E 之后。如果 ORCH_024 显示特定类别（如 pedestrian/bicycle）precision 极低，再考虑多尺度。

### 方案 G: 等 ORCH_024 @2000 再决策 — ✅ 最正确的当下行动

**完全同意。数据驱动决策。**

ORCH_024 @2000 eval ETA ~20:00 今天。这是 Full nuScenes 的第一个有意义的评估点。

**决策矩阵**:

| ORCH_024 @2000 结果 | 行动 |
|---------------------|------|
| car_P > 0.15, bg_FA < 0.25 | 架构正确。继续到 @40000。方案 D 排队。 |
| car_P 0.08-0.15, bg_FA < 0.30 | 方向正确但需要更多训练。继续。 |
| car_P 0.03-0.08 | 可能需要调参 (LR, balance)。不中断，调参后重启。 |
| car_P < 0.03 | 在线 DINOv3 可能有根本问题。切换到预提取 175GB。 |

---

## 对审计问题的回应

### Q1: GPU 资源冲突

**选 (b): 等 ORCH_024 @2000 结果 (~20:00 今天) 再决策。**

理由:
1. ORCH_024 是 7 天 mini 验证的结晶。中断它等于浪费之前所有工作。
2. CEO 的指令在 ORCH_024 之前签发。CEO 当时不知道 ORCH_024 即将启动。
3. @2000 eval 仅需等 ~4 小时。如果结果良好，所有 CEO 方案都变成"后续优化"而非"紧急行动"。
4. 中断到 2 GPU 训练时间翻倍（6 天 vs 3 天），但获得的 mini 实验信息量远不如 full nuScenes @2000 eval。

**如果 CEO 坚持立即行动**: 最多释放 1 GPU 做轻量级工作（如 LoRA rank=4 测试），但不要停 ORCH_024 的 DDP 训练。缩减到 3 GPU DDP 会导致 batch 不均匀，可能引入新问题。

### Q2: DINOv3 Unfreeze 可行性

**全量/部分 Unfreeze: 不推荐。LoRA: 推荐但不紧急。**

- Unfreeze: 显存超限 + BUG-35 特征漂移。即使技术上可行也不值得风险。
- LoRA: 可行、可控、风险低。但应在 ORCH_024 完成后做，用 full nuScenes 数据，不用 mini。
- 如果要做 LoRA，用 **10 类 full nuScenes** (不是 mini 单类)。mini 数据量不足以训练 adapter；单类会触发 BUG-27。

### Q3: 单类 Car 验证的实验设计

**不要做独立的单类实验。ORCH_024 的 car 指标就是 CEO 需要的答案。**

如果非要做:
- `classes=["car"]` 但 `num_vocal=230` 保持不变
- 其他类标注视为 background
- 但这等价于"10 类训练但只看 car"——ORCH_024 已经在做

**BUG-27 红线**: 任何修改 `num_vocal` 的实验方案都必须被否决。

### Q4: 历史 Occ Box 时间窗口

**2 帧 (1.0s)。不是 1 帧，不是 3 帧。**

- 1 帧 (CEO): 纯存在信息，价值有限
- 2 帧 (Critic 推荐): 速度方向，最优性价比
- 3 帧 (Conductor 提议): 加速度，边际收益递减

**编码**: 方案 3 (轻量条件信号) 优先验证。实现简单 (1 天)，如果无效再考虑 cross-attention (方案 2)。

**nuScenes 历史帧可用性**: nuScenes 提供完整的时序标注 (keyframes + sweeps)。keyframes 每 0.5s 一帧，通常有 40+ 帧/场景。获取前 2 帧的 3D box 标注没有技术障碍。数据加载需修改 `LoadAnnotations3D_E2E` pipeline。

### Q5: 方案优先级排序

**ORCH_024 继续 >> 方案 G (等数据) >> 方案 D (历史编码) >> 方案 E (LoRA) >> 方案 F (多尺度) >> 方案 C (单类) >> 方案 B (unfreeze) >> 方案 A (已涵盖)**

时间线:

```
现在 → 20:00 (今天)     等 ORCH_024 @2000 eval (方案 G)
20:00 → 3月11日         ORCH_024 继续训练, 关注 val 趋势
3月11日+                ORCH_024 完成后:
                         1. 评估 Full nuScenes 基线
                         2. 如果基线 OK → 方案 D (历史 occ box 2 帧)
                         3. 方案 D 验证后 → 方案 E (LoRA 域适应)
                         4. 方案 F 仅在特定类 precision 极低时考虑
```

### Q6: 方案 A 是否已被 ORCH_024 涵盖

**完全涵盖。不需要额外探索。**

| 压缩比 | 方案 | 状态 |
|--------|------|------|
| 5.3:1 (4096→768) | P5 单层 | 已验证, car_P=0.090 |
| 4:1 + 1.3:1 (4096→1024→768) | CEO 方案 A = P5b | 已验证, car_P=0.116 |
| 2:1 + 2.7:1 (4096→2048→768) | ORCH_024 | **正在验证** |

2048 hidden dim 在 mini 上已证明优于 1024 (offset 精度大幅改善)。没有理由回退。

---

## 发现的问题

无新 BUG。所有风险点都已在历史 BUG 中覆盖。

**重申关键 BUG**:
- BUG-27: 任何改 num_vocal 的实验 = 无效
- BUG-35: DINOv3 unfreeze = 特征漂移
- BUG-33: DDP val 需要 DistributedSampler (ORCH_024 应已包含)

---

## 逻辑验证

### 资源约束
- [x] 4 × A6000 48GB 全被 ORCH_024 占用 — 无法并行做 mini 实验
- [x] DINOv3 unfreeze 显存估算: frozen 36-37 GB + unfreeze ~15-20 GB = 50+ GB > 48GB
- [x] LoRA (rank=16) 显存估算: ~12M params × 12 bytes (AdamW) = ~144 MB + 激活值 ~1-2 GB → 可控

### 决策一致性
- [x] CEO 方案 A (1024+GELU) vs ORCH_024 (2048+GELU): 2048 严格更优，P5b vs P6 数据支持
- [x] 方案 G (等 @2000) 与 VERDICT_P2_FINAL_FULL_CONFIG 的 PROCEED 判决一致
- [x] 方案 D 时间线与 mini→full 过渡路线图一致

### 风险评估
- [x] 中断 ORCH_024 风险: 损失 3+ 天训练进度 + DDP→2GPU 不确定性
- [x] 不中断风险: CEO 方案延迟 3 天执行。但方案 A 已涵盖，方案 B/C 优先级低，方案 D 本身就需要 ORCH_024 结果才能设计。**延迟成本极低。**

---

## 附加建议

### 对 CEO
1. **方案 A 的直觉完全正确**。5.3:1 压缩确实是瓶颈，2048 中间层已经解决了这个问题。ORCH_024 正在验证。
2. **方案 D (历史 occ box) 是最有前途的方向**。建议在 ORCH_024 完成后立即启动。2 帧 1.0s 是最优起步点。
3. **方案 B (unfreeze) 的意图可以通过 LoRA (方案 E) 实现**，而不需要承担显存超限和特征漂移的风险。
4. **不建议中断 ORCH_024**。它是所有后续方案的基础。没有 full nuScenes 基线，任何新方案都无法评估。

### 对 Conductor
1. ORCH_024 @2000 eval 是今天最重要的数据点。确保 eval 正确触发。
2. 确认 ORCH_024 config 包含 BUG-33 fix (`sampler=dict(type='DefaultSampler', shuffle=False)`)。
3. 如果 @2000 car_P < 0.03，立即通知 CEO 和 Critic。可能需要切换到预提取模式。
4. 方案 D 的代码实现可以提前规划 (修改 `LoadAnnotations3D_E2E` 和 `GenerateOccFlowLabels` pipeline 加载历史帧标注)。不需要动模型代码。

### 对 Admin
1. 不要在 ORCH_024 运行期间做任何 GPU 操作（BUG-33 的教训: 并行 eval 导致 loss 飙升）
2. 监控 GPU 显存和训练 loss。在线 DINOv3 + 4GPU DDP 首次运行，可能有意外。
3. 方案 D 的数据预处理可以在 CPU 上提前做（提取历史帧 3D box 标注到缓存文件）。

**下一个 BUG 编号**: BUG-43
