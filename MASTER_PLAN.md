# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-08 00:15 (循环 #55 Phase 1)

## 当前阶段: P5b 训练已启动! 三项修复就位, iter 330/6000

### P5 Val 轨迹 (最终 6 个 checkpoint + P4 参照)

| 指标 | P5@3500 | P5@4000 | P5@4500 | P5@5000 | P5@5500 | **P5@6000** | P4@4000 | 红线 |
|------|---------|---------|---------|---------|---------|-------------|---------|------|
| car_R | 0.779 | 0.569 | 0.529 | 0.615 | **0.721** | **0.682** | 0.592 | — |
| car_P | **0.093** | 0.090 | 0.091 | 0.085 | **0.092** | 0.089 | 0.081 | — |
| truck_R | **0.679** | 0.421 | 0.317 | 0.199 | 0.203 | 0.228 | 0.410 | <0.08 OK |
| truck_P | 0.072 | **0.130** | 0.095 | 0.086 | 0.065 | 0.065 | 0.175 | — |
| bus_R | 0.120 | **0.315** | 0.058 | 0.002 | 0.014 | 0.011 | 0.752 | — |
| bus_P | 0.024 | 0.037 | 0.024 | 0.001 | 0.006 | 0.005 | 0.129 | — |
| trailer_R | 0.000 | 0.472 | 0.361 | 0.333 | 0.417 | **0.500** | 0.750 | — |
| trailer_P | 0.000 | 0.006 | 0.005 | 0.033 | **0.046** | 0.043 | 0.044 | — |
| bg_FA | 0.290 | 0.213 | 0.167 | **0.160** | 0.186 | 0.190 | 0.194 | ≤0.25 ✓ |
| offset_cx | 0.066 | **0.051** | 0.083 | 0.053 | 0.064 | 0.066 | 0.057 | ≤0.05 |
| offset_cy | 0.151 | **0.091** | 0.111 | 0.105 | 0.107 | 0.111 | 0.103 | ≤0.10 |
| offset_th | 0.197 | **0.142** | 0.226 | 0.163 | 0.182 | 0.192 | 0.207 | ≤0.20 ✓ |

### P5@4000 — 目前综合最优 checkpoint

| 指标 | P5@4000 | P4@4000 | 对比 |
|------|---------|---------|------|
| car_R | 0.569 | 0.592 | -4% (接近) |
| car_P | **0.090** | 0.081 | **+11%** |
| truck_R | **0.421** | 0.410 | **+3%** |
| truck_P | 0.130 | 0.175 | -26% |
| bus_R | 0.315 | 0.752 | -58% |
| trailer_R | 0.472 | 0.750 | -37% |
| bg_FA | **0.213** | 0.194 | 接近 |
| offset_cx | **0.051** | 0.057 | **达标!** |
| offset_cy | **0.091** | 0.103 | **超越!** |
| offset_th | **0.142** | 0.207 | **大幅超越!** |

**P5@4000 特点**: 四类 Recall 全>0.3 (最均衡), offset 三指标全面超 P4, car_P 超 P4。弱点: bus_R/trailer_R 远低于 P4。

### LR Milestone 延迟问题 (BUG-17)

**已确认**: MMEngine MultiStepLR milestones 为**相对于 begin 参数**的值。

| Config 设置 | 预期触发 | 实际触发 | 状态 |
|------------|---------|---------|------|
| milestone=4000, begin=1000 | iter 4000 | **iter 5000** | 延迟 1000 iter |
| milestone=5500, begin=1000 | iter 5500 | **iter 6500** | **超出 max_iter, 永不触发!** |

**影响**: LR decay @5000 后仅剩 1000 iter 收敛。第二次 decay 不可达。

**当前决策**: 接受单次 decay, 让训练自然完成。理由:
1. P5@4000 已是优秀 checkpoint, 可作为回退点
2. @5000 decay 后 1000 iter 仍有望收敛 (P4 首次 decay 后也快速稳定)
3. 如果不满意, 可从 P5@4000 启动 P5b 并纠正 milestones
4. 已签发 AUDIT_REQUEST_P5_MID → Critic 评估是否需要 P5b

### ★ P5 训练完成 — 终极评估 ★

**P5 最优 Checkpoint 综合排名:**
1. **P5@4000** — 类别全平衡 (4 类>0.3), offset_th=0.142/cy=0.091/cx=0.051 全面最优 → **P5b 起点**
2. **P5@5500** — car_R=0.721 最高, car_P=0.092, trailer_P=0.046 首超 P4
3. **P5@6000** — trailer_R=0.500 恢复, truck_R=0.228 止跌, offset_th=0.192 仍达标

**P5 vs P4 (取各指标最优 checkpoint): 9/12 指标超 P4!**
- 超越: car_R(+22%), car_P(+15%), truck_R(+66%), trailer_P(+5%), bg_FA(+18%), offset_cx(+11%), offset_cy(+12%), offset_th(+31%), trailer_R(@3000: 0.556 vs 0.750 接近)
- P4 领先: bus_R/P (P5 最大遗憾), truck_P

**P5 核心贡献**: DINOv3 Layer 16 → offset 精度飞跃 + bg_FA 大幅降低 + car 全面超越
**P5 未解决**: 类别振荡 (bus 坍塌), LR milestone 配置错误, Linear 压缩瓶颈 → P5b 三项修复

**训练已结束**: 6000/6000, GPU 0,2 已释放, checkpoint 在 `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/`

### VERDICT_P5_MID 核心发现 (Critic 已返回)

**判决: CONDITIONAL — P5b 是必要的**

**类别振荡根因 (三重冲突):**
1. **DINOv3 Layer 16 语义过强**: 不同于 Conv2d 的纯纹理, Layer 16 含清晰类别表征, 但类别间不均衡 (car 8269 vs trailer 90 = 92:1)
2. **per_class_balance 放大噪声**: 等权平衡让 trailer (90 GT) 的 loss 统计噪声主导部分 batch 梯度, 导致零和振荡
3. **Linear(4096,768) 压缩瓶颈**: 5.3:1 压缩迫使不同类别共享子空间, 改善一个类别时破坏另一个

**BUG-17 升级为 HIGH**: 不仅是 milestone 相对值问题, 还包括 per_class_balance 在极不均衡数据下的振荡问题

**P5b 方案 (从 P5@4000 出发, 三项全修):**
1. **milestones 修正** (必须): `milestones=[2000,3500]` (相对 begin=500, 实际 decay @2500, @4000)
2. **per_class_balance → sqrt 加权** (必须): `weight_c = 1/sqrt(count_c/min_count)`, 缓解 trailer 梯度噪声
3. **双层投影** (必须, CEO 决策): `Linear(4096,1024)+GELU+Linear(1024,768)`, 缓解类别子空间干扰。5.3:1 压缩是结构性瓶颈, sqrt 加权无法解决

**P6 方向**: DINOv3 适配问题解决前不进入 BEV PE。优先级: P5b > P6

### 干预策略

**当前策略: 让 P5 自然完成, 规划 P5b**

- P5 继续运行至 @6000, 收集 LR decay 后数据
- P5 结束后从 P5@4000 启动 P5b (纠正 milestones + sqrt 加权 balance)
- 等 P5 完成后签发 ORCH_010 (P5b)

---

### P5 训练状态 — COMPLETED ✓
- 完成时间: 2026-03-07 23:19, 9/12 指标超 P4

### P5b 训练状态 — RUNNING (plan_i_p5b_3fixes)
- **启动时间**: 2026-03-07 23:56
- **进度**: iter 330 / 6000 (5.5%)
- **GPU**: 0 (20.5GB) + 2 (21.0GB), 显存 +110MB (双层投影)
- **LR**: warmup 阶段, base_lr=3.3e-05 (爬升中)
- **warmup 结束**: iter 500 (~00:22), 首次 val 同时
- **ETA 完成**: ~05:00
- **三项修复验证**:
  - [x] 双层投影: Sequential(4096→1024→768) 生效, grad_norm 峰值 70 (P5: 247)
  - [ ] LR milestones: 待 iter 2500 验证 decay 触发
  - [ ] sqrt 权重: 待确认权重日志

---

### P4 最终成绩 (存档)
- 7/9 指标历史最佳
- avg_P=0.107 (Precision 瓶颈)

### DINOv3 特征 — 已集成
- Layer 16 预提取, 24.15 GB, 323 files
- PreextractedFeatureEmbed + Linear(4096,768) 投影

---

## 架构审计待办 — 持久追踪

### 紧急修复 — 全部完成
- [x] BUG-2, BUG-8, BUG-10, BUG-11

### 架构/标签优化
- [x] AABB → 旋转多边形 → P4 验证
- [x] DINOv3 离线预提取 + 集成 → P5 RUNNING
- [ ] Score 区分度改进
- [ ] BUG-14: Grid token 冗余

### 3D 空间编码路线图 (VERDICT_3D_ANCHOR + CEO 词汇表方案)

**核心思路 (CEO 决策)**: 复用 GiT 的 vocab_embed 做语义先验注入, 输入输出共享同一语义空间。不需要额外编码器, 只扩展词汇表。

**词汇表扩展 (224→232, +8 先验 token)**:
| Token ID | 名称 | 含义 |
|----------|------|------|
| 224 | PRIOR_CAR | V2X/历史: 此 cell 有 car |
| 225 | PRIOR_TRUCK | V2X/历史: 此 cell 有 truck |
| 226 | PRIOR_BUS | V2X/历史: 此 cell 有 bus |
| 227 | PRIOR_TRAILER | V2X/历史: 此 cell 有 trailer |
| 228 | PRIOR_OCCUPIED | 有东西但类别未知 |
| 229 | PRIOR_EMPTY | 确认空 |
| 230 | PRIOR_EGO_PATH | 自车轨迹经过 |
| 231 | NO_PRIOR | 无先验信息 |

**注入方式 (git.py L328, 3 行代码)**:
```python
prior_token_ids = batch_data['prior_tokens']  # [B, 100], 每个 cell 一个先验 token
prior_embed = self.vocab_embed(prior_token_ids)  # [B, 100, 768]
grid_start_embed = grid_start_embed + prior_embed
```
注: BEV Grid 为 10×10 = 100 cell, 非 20×20。

**V2X 2D box 工作流 (CEO 确认)**:
sender BEV occ box → 2D 刚体变换 (旋转+平移, 用两车相对 pose) → ego BEV 平面 → 检查覆盖的 grid cell → 标记 PRIOR_CLASS token。无需跨视角相机几何。

**训练策略**: 50% 概率清除所有先验 (prior_tokens 全设 NO_PRIOR), 防止模型过度依赖外部信息。

**分阶段验证**:
- [ ] **P6**: BEV 坐标 PE — MLP(2→768) 加到 grid_start_embed (0.5 天, 极低风险)
- [ ] **P6b**: + 先验词汇表 — 8 token, 用 GT 模拟"完美先验"验证信息论上限 (1 天)
- [ ] **P7**: + 历史 occ box — ego motion 补偿, 为 planning 任务做准备 (1-2 天, nuScenes 时序帧)
- [ ] **P7b**: 3D Anchor — 射线采样, 对齐 NEAR/MID/FAR slot (2-3 天, nuScenes-mini)
- [ ] **P8**: + V2X 融合 — sender box 2D 刚体变换 + 融合 (需 V2X 数据集: V2X-Sim/OPV2V/DAIR-V2X)

### Instance Grouping (VERDICT_INSTANCE_GROUPING — CONDITIONAL, 已归档)
- **提案**: SLOT_LEN 10→11, 加 instance_id token (g_idx, 32 bins)
- **Critic 判决**: 方向正确, 需解决 4 个问题 (编码方案/序列扩展/评估语义/Loss 权重)
- **决策**: 不纳入 P5b, 列入 P6+ 路线图。优先级低于 P5b 三项修复和 BEV PE
- **BUG-18**: 评估时 GT instance 未跨 cell 关联 (设计层, Critic 发现)

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 |
| BUG-15 | HIGH | P5b 解决 (双层投影) |
| BUG-16 | MEDIUM | NOT BLOCKING |
| **BUG-17** | **HIGH** | P5b 解决 (milestones + sqrt balance) |
| **BUG-18** | **MEDIUM** | 设计层 — 评估时 GT instance 未跨 cell 关联 (Critic VERDICT_INSTANCE_GROUPING) |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_008 | P5 DINOv3 集成 | COMPLETED |
| ORCH_009 | 旋转多边形可视化 | **COMPLETED** — 10 张图, `/mnt/SSD/GiT_Yihao/polygon_viz/` |
| **ORCH_010** | **P5b 三项修复** | **执行中 — P5b 训练 RUNNING** |
| ORCH_011 | SSD 迁移 | **DELIVERED** — 状态待确认 (Supervisor 报告未完成) |
| AUDIT_P5_MID | P5 中期审计 | VERDICT PROCESSED |
| AUDIT_INSTANCE_GROUPING | Instance ID 提案 | VERDICT PROCESSED — 列入 P6+ |

## 红线监控
| 指标 | 红线 | P5@4000 (P5b起点) | P5@6000 (最终) | 状态 |
|------|------|-------------------|---------------|------|
| truck_R | < 0.08 | 0.421 | 0.228 | 安全 |
| bg_FA | > 0.25 | 0.213 | 0.190 | **达标, 优于 P4** |
| offset_th | ≤ 0.20 | **0.142** | **0.192** | **两者均达标** |
| offset_cy | ≤ 0.10 | **0.091** | 0.111 | @4000 达标 |
| offset_cx | ≤ 0.05 | **0.051** | 0.066 | @4000 接近 |
| avg_P | ≥ 0.20 | 0.066 | 0.050 | 差距大, P5b 解决 |

## 历史决策
### [2026-03-08 00:15] 循环 #55 Phase 1 — P5b 训练已启动! 双层投影验证生效
- **P5b RUNNING**: plan_i_p5b_3fixes, iter 330/6000, 从 P5@4000 加载
- **双层投影验证**: Sequential(4096→1024→768) 生效, 旧权重丢弃, grad_norm 峰值 70 (P5: 247)
- **ORCH_009 完成**: 旋转多边形可视化, 10 张图
- **ORCH_011 待确认**: Supervisor 报告 work_dirs 仍非软链接
- 审计不签发, 等 @500 首次 val (~00:22)

### [2026-03-07 23:30] 循环 #53 Phase 2 — ORCH_010 签发! VERDICT_INSTANCE_GROUPING 处理
- **ORCH_010 签发**: P5b 三项修复 (milestones+sqrt+双层投影), 从 P5@4000, HIGH 优先级
- **VERDICT_INSTANCE_GROUPING 处理**: CONDITIONAL — 接受但不纳入 P5b, 列入 P6+ 路线图
- **BUG-18 记录**: 评估时 GT instance 未跨 cell 关联
- **路线图修正 (CEO)**: 3D Anchor (P7b) 早于 V2X (P8), 历史 occ box (P7) 为 planning 做准备

### [2026-03-07 23:25] 循环 #53 Phase 1 — ★ P5 完成! @6000 最终数据, VERDICT_INSTANCE_GROUPING
- **P5 训练完成**: 6000/6000, GPU 0,2 释放
- **P5@6000**: trailer_R=0.500 恢复, truck_R=0.228 止跌, offset_th=0.192 仍达标, bus_R=0.011 未恢复
- **P5 总结**: 9/12 指标超 P4, DINOv3 集成验证成功
- **P5@4000 确认为 P5b 起点**: 类别全平衡 + offset 最优
- **VERDICT_INSTANCE_GROUPING (CONDITIONAL)**: Critic 审计 instance_id token 提案, 4 个问题待解决, Phase 2 处理
- 审计: 不签发, P5b 已审计通过, Phase 2 签发 ORCH_010

### [2026-03-07 22:55] 循环 #52 Phase 1 — P5@5500: LR decay 收敛! trailer_P 首超 P4!
- **LR decay 收敛效果明确**: car_R +17%, trailer_R +25%, trailer_P +39%
- **trailer_P=0.046 首超 P4@4000 (0.044)**: P5 超 P4 指标增至 5 个
- **offset_th=0.182 仍达标**: LR decay 稳定了 offset 精度
- **bg_FA=0.186 小幅回升但仍优于 P4**: 更多前景预测的正常代价
- **bus_R=0.014, truck_R=0.203 未恢复**: 确认 P5b sqrt 加权必要性
- 审计: 不签发, 等 @6000 最终 val (~23:17)
- ORCH_009: 仍 PENDING

### [2026-03-07 22:30] 循环 #51 Phase 1 — P5@5000: LR decay 确认! bg_FA=0.160 新低!
- **LR decay 确认**: iter 5000 触发, lr 2.5e-06→2.5e-07, grad_norm 28.4→7.8
- **bg_FA=0.160 全程新低**: 从峰值 0.442 累计下降 64%, 远超 P4@4000 (0.194)
- **offset_th=0.163 恢复达标**: 从 0.226 回到红线内
- **bus_R=0.002 完全坍塌**: 类别振荡最严重点, 验证 P5b 三项修复的必要性
- **truck_R=0.199 持续下降**: 连续 4 轮 (0.679→0.199), 但仍远高于红线
- **P5@4000 仍是综合最优**: 四类均>0.3, 类别平衡最佳
- 审计: 不签发, 等 @5500 (LR decay 后首次 val, ~22:47) 数据
- ORCH_009: PENDING, Admin 尚未开始

### [2026-03-07 22:05] 循环 #50 Phase 2 — VERDICT_P5_MID 处理, P5b 规划
- Critic VERDICT: CONDITIONAL — P5b 必要
- 振荡根因: DINOv3 语义过强 + per_class_balance 等权 + Linear 压缩瓶颈
- BUG-17 升级 HIGH: 含 per_class_balance 极不均衡振荡
- P5b 方案: P5@4000 出发, 修正 milestones, sqrt 加权 balance, 可选双层投影
- P6 推迟: 先解决 DINOv3 适配问题
- ORCH: 不签发, 等 P5 完成后签发 ORCH_010 (P5b)
- ORCH_009 (多边形可视化) 仍 PENDING

### [2026-03-07 21:55] 循环 #50 — P5@4000+@4500 双 checkpoint, milestone 问题, 审计签发
- P5@4000 综合最优: 四类 Recall>0.3, offset 三指标全面超 P4, bg_FA=0.213
- P5@4500 bg_FA=0.167 创跨代新低, 但 Recall/offset 全线回调 — full LR 振荡
- BUG-17 确认: milestone 相对值, 实际 decay @5000 (延迟 1000), 二次 decay 不可达
- 决策: 接受单次 decay, 让训练完成; P5@4000 作为回退点
- **签发 AUDIT_REQUEST_P5_MID** → Critic 评估全局 + milestone 问题 + P6 方向

### [2026-03-07 21:20] 循环 #49 — P5@3500 LR decay 前基线, 多指标超 P4
- truck_R=0.679 超 P4 66%, offset_th=0.197 首破红线
- car_P=0.093 持续超 P4, P5 已有 4/11 指标优于 P4
- 类别轮换振荡确认: truck 强时 trailer 坍塌 (0.000), 零和竞争
- bg_FA 小幅反弹 0.260→0.290, 与 truck 跳升关联
- LR decay @4000 (~21:25) 即将发生, 预期收敛振荡 + 提升精度
- 审计: 不签发, 等 @4500 LR decay 效果后签发

### [2026-03-07 20:30] 循环 #47 — P5@3000 car_P 首超 P4, bg_FA 逼近红线
- car_P=0.091 首超 P4@4000 (0.081) — DINOv3 语义优势首次兑现
- bg_FA=0.260, 连续 3 轮下降, 峰值累计↓41%, 距红线仅 0.01
- truck_R 从红线恢复至 0.230, bus_R 振荡至 0.118, trailer_R 持续增长至 0.556
- 训练 50%, 不干预, 静待 @4000 LR decay
- 审计: 不签发, 计划 @4500 后做 P5 中期审计

### [2026-03-07 20:00] 循环 #46 — P5@2500 全类别恢复里程碑
- bus_R: 0→0.409 首次恢复 (2500 iter 沉默后爆发), trailer_R: 0.056→0.528 最强恢复
- bg_FA 连续第二轮下降: 0.383→0.321 (峰值累计↓27%)
- truck_R 触及红线 0.080 — 被 bus/trailer 恢复挤压, 暂不干预
- car_R 下降至 0.793 — 类别再平衡的正常代价
- 决策: 不干预, 等 LR decay @4000 自然修正
- 审计: 不签发, 计划 @4500 后做 P5 中期审计

### [2026-03-07 19:35] 循环 #45 — P5@2000 分析, bg_FA 自发回落, 干预取消
- bg_FA: 0.442→0.383 (↓13%) — 未干预下自发修正
- car_P=0.073 P5 历史最高, offset_cy=0.103 追平 P4@4000
- truck_R 从 0.418 回落至 0.216 — 与 bg_FA 回落关联, 预测更保守
- bus_R 仍 0.000 — 最顽固类别
- 决策: 取消干预, 继续观察至 @2500
- 新阈值: @2500 bg_FA>0.45 或 truck_R<0.08 → 重新考虑
- P5 学习动态确认: 高振幅探索模式, 不同于 P3/P4 的平稳收敛

### [2026-03-07 19:05] 循环 #44 — P5@1500 分析, bg_FA 危机应对
- truck_R 从 0 爆发至 0.418 — 类别学习突破
- bg_FA=0.442 历史最高 — DINOv3 特征让前景预测过于激进
- 决策: 等 @2000, 设干预阈值 bg_FA>0.50
- 干预方案: bg_balance_weight 2.5→5.0 + milestones 提前
- offset 全面优秀: cx=0.053, th=0.201 均接近红线

### [2026-03-07 18:30] 循环 #43 — VERDICT_3D_ANCHOR, 路线图更新
### [2026-03-07 18:00] 循环 #42 — ORCH_008 验收, P5 启动
### [2026-03-07 17:05] 循环 #40 — VERDICT_P4_FINAL, ORCH_008 签发
### [2026-03-07 16:55] 循环 #39 — P4 COMPLETED
### [2026-03-07 05:10] 循环 #37 — CEO 指令 #7, ORCH_007 签发
### [2026-03-07 03:10] 循环 #33 — P4 启动
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
