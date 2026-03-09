# GiT OCC 项目进展报告
> 撰写: claude_conductor | 时间: 2026-03-09 02:00
> 项目: 基于 DINOv3 特征的 BEV Grid Occupancy Prediction

---

## 1. 实验历程总结

### Phase 0: 基础建设 (P1-P3, ~3/5-3/6)

**P1-P3** 为早期探索阶段，建立了 BEV 10×10 grid + 3 depth slot 的 occupancy 预测框架。主要贡献是确立了 AR 解码结构（每 cell 30 token = 3 slot × 10 token）和评估指标体系。这些实验在 4 类（car/truck/bus/trailer）上运行，使用原始 CNN 特征。

**关键成果**: 确立 AR 解码框架、BEV grid 结构、评估流程。

### Phase 1: P4 — AABB→旋转多边形 + BUG 修复 (3/7 02:50-06:00)

P4 是第一个可信的 baseline。核心改动：
- **AABB→旋转多边形**: 标签生成从轴对齐包围盒改为旋转多边形覆盖判定，修复了大角度车辆标签缺失问题
- **BUG-11 (z+=h/2)**: 发现并修复了将 3D box 中心移到顶部的 bug，导致投影只覆盖上半身
- **BUG-2/8/10**: 多项早期 bug 修复（评估逻辑、冷启动影响等）

**P4@4000 成绩**: car_P=0.081, truck_P=0.175, bus_R=0.752, offset_th=0.207。7/9 指标历史最佳。

**转 P5 原因**: CEO 决策引入 DINOv3 特征替代 CNN 特征，预期提升特征质量。

### Phase 2: P5 — DINOv3 集成 (3/7 06:00-23:00)

P5 引入 DINOv3 ViT-7B Layer 16 预提取特征（4096 维），通过 Linear(4096, 768) 投影到 GiT 输入空间。

- **DINOv3 离线预提取**: Layer 16, CAM_FRONT, fp16, mini 24.15 GB (BUG-26: 全量仅 ~175 GB, 非最初估计的 2.1 TB)
- **核心发现**: offset 精度飞跃（off_th: 0.207→0.142, off_cy: 0.103→0.091），bg_FA 大幅降低

**P5@4000 成绩**: 四类 Recall 全>0.3（最均衡），9/12 指标超 P4。但发现类别振荡问题和 LR milestone 配置错误 (BUG-17)。

**P5 未解决**: 类别振荡（bus 崩塌）、Linear 5.3:1 压缩瓶颈、LR milestone 错误。

**转 P5b 原因**: Critic VERDICT_P5_MID 诊断了三重冲突根因（DINOv3 语义过强 + per_class_balance 放大噪声 + 压缩瓶颈），推荐三项修复。

### Phase 3: P5b — 三项修复 (3/7 23:30 - 3/8 06:36)

从 P5@4000 出发，同时应用三项修复：
1. **双层投影**: Linear(4096,1024)+GELU+Linear(1024,768)（CEO 决策）
2. **sqrt 加权 balance**: 替代 per_class_balance，缓解小类梯度噪声
3. **LR milestones 修正**: `milestones=[2000,3500]` 相对 `begin=500`

**P5b 结论**: 三项修复均按设计运行，红线 3/5 达标（truck_R=0.240, bg_FA=0.208, off_th=0.198）。但 mini 数据上 car_P 已触顶 ~0.104-0.108，bus 振荡未根治（BUG-20: 数据量天花板）。

**转 P6 原因**: Critic VERDICT_P5B_3000 建议从 P5b@3000 启动 P6，扩展到 10 类，加宽投影到 2048。

### Phase 4: 诊断实验 — Plan K/L/M/N (3/8 06:00-12:00)

四路并行诊断实验，确认瓶颈来源：
- **Plan K** (单类 car, 预提取): car_P~0.06, 证明类竞争不是唯一瓶颈
- **Plan L** (10 类+宽投影 2048, 预提取): car_P=0.111, 宽投影有效但信号弱
- **Plan M** (在线 DINOv3, unfreeze): car_R 崩塌 0.699→0.489, 特征漂移确认 (BUG-35)
- **Plan N** (在线 DINOv3, frozen): car_P~0.05, 在线路径 mini 上不达标

**关键结论**: Frozen >> Unfreeze, 预提取 > 在线 (mini 上), 宽投影有轻微帮助。但 Plan K/M/N 都有 vocab 不兼容问题 (BUG-27/31)。

### Phase 5: P6 — 宽投影 2048 mini 验证 (3/8 07:00-16:00)

从 P5b@3000 启动，proj 扩展到 2048 维（无 GELU, 因式参数化）:
- **@3500**: car_P=0.121, 首次超越 P5b (0.116)
- **@4000 单 GPU**: car_P=0.1263 (+8.9% vs P5b), truck_P=0.0749 (+74%)
- **@6000 FINAL**: car_P=0.129 (DDP), +11% vs P5b, plateau 确认

**BUG-39 降级**: 双层 Linear 无 GELU 数学上等价单层，但因式参数化有独立优化优势（9.96M vs 3.15M 参数，梯度更平滑）。退化≠无效。

### Phase 6: Plan P/P2 — GELU 验证 (3/8 12:00-16:00)

- **Plan P** (2048+GELU, lr_mult=1.0): FAIL, car_P=0.004, 但 bg_FA=0.165 历史最低 → GELU 对 bg/fg 判别有独立强贡献。失败归因超参问题
- **Plan P2** (2048+GELU, lr_mult=2.0): @1000 car_P=0.100 (+72% vs P6!), @1500 car_P=0.112 (+5.7% vs P6@1500). @2000 回调到 0.096 (BUG-42: 全程无 LR decay)

**GELU 确认**: 收敛速度约 P6 的 1.3x，off_th 始终优于 P6。

**Critic VERDICT_P2_FINAL_FULL_CONFIG: PROCEED** → Full nuScenes 使用 2048+GELU。Mini 验证阶段正式结束。

### Phase 7: ORCH_024 — Full nuScenes 训练 (3/8 16:10 - 进行中)

**Config**: Linear(4096,2048)+GELU+Linear(2048,768), 在线 DINOv3 frozen, ViT-7B fp16, 4 GPU DDP, max_iters=40000, warmup=2000, milestones=[15000,25000], 10 类 (num_vocal=230), train=28130, val=6019。

**@2000 val** (0.57 epochs): car_P=0.079, car_R=0.627, bg_FA=0.222, off_th=0.174。决策矩阵边界值, 继续训练。

**@4000 val** (1.14 epochs, 第一个可信评估点):
- car_P=0.078 (持平), car_R=0.419 (停止 spam, 类别再平衡)
- truck_P=0.057, bicycle_R=0.191 — 新类出现!
- bg_FA=0.199 (首次<0.20), off_th=0.150 (大幅改善)
- off_cy=0.097 恶化 (vs @2000=0.069), 需关注

**当前进度**: 4170/40000 (10.4%), ETA ~3/11 15:00

---

## 2. 当前状态

### ORCH_024 Full nuScenes 训练
| 指标 | 值 |
|------|-----|
| 进度 | 4170/40000 (10.4%) |
| 速度 | ~6.3 s/iter |
| 显存 | 28849 MB/GPU (训练) |
| LR | 2.5e-06 (恒定至 milestone @17000) |
| ETA | ~3/11 15:00 |
| 下一 val | @6000, ETA ~3/9 05:30 |
| 磁盘 | 322 GB 可用 |

### GPU 状态
| GPU | 占用 | 任务 |
|-----|------|------|
| 0 | 36.8 GB | ORCH_024 训练 |
| 1 | 36.8 GB | ORCH_024 训练 |
| 2 | 37.3 GB | ORCH_024 训练 |
| 3 | 36.8 GB | ORCH_024 训练 |

### Agent 状态
| Agent | 状态 | 职责 |
|-------|------|------|
| conductor | ✅ UP | 决策中枢, 两阶段循环 |
| critic | ✅ UP | 被动审计, VERDICT 签发 |
| supervisor | ✅ UP | 训练监控, 摘要报告 |
| admin | ✅ UP | 代码执行, ORCH 完成 |
| ops | ✅ UP | 基础设施监控, watchdog |

### 待处理
| 类型 | ID | 状态 |
|------|-----|------|
| AUDIT | AUDIT_REQUEST_FULL_4000 | 等待 Critic VERDICT |
| ORCH | ORCH_024 | IN PROGRESS (4170/40000) |
| ORCH | ORCH_025 | COMPLETED (测试框架) |

---

## 3. 关键决策回顾

### 正确的决策

| 决策 | 时间 | 理由 | 结果 |
|------|------|------|------|
| AABB→旋转多边形 | P4 | 修复大角度车辆标签缺失 | P4 7/9 指标最佳 |
| DINOv3 Layer 16 集成 | P5 | 更强的语义特征 | offset 精度飞跃, 9/12 超 P4 |
| sqrt 加权 balance | P5b | 缓解小类梯度噪声 | truck_R 6x 提升 |
| 宽投影 2048 | P6 | 缓解 5.3:1 压缩瓶颈 | car_P +8.9% vs P5b |
| GELU 激活 | P2/ORCH_024 | 非线性容量 + 收敛加速 | @1000 +72% vs P6 |
| 在线 DINOv3 frozen | ORCH_024 | 避免 2.1TB 存储, 避免特征漂移 | 训练正常运行 |
| Mini 不做架构决策 | 规则 #5 | 数据量不足, 振荡不可避免 | 避免了多次过早结论 |
| 6 条评判规则 | Cycle #92 | 规范化评估流程 | 防止 500-iter 草率决策 |

### 错误的决策

| 决策 | 发现者 | 错误 | 影响 |
|------|--------|------|------|
| Plan K/L vocab 不兼容 | Critic | BUG-27/28: vocab 230→221 + 双变量混淆 | 诊断结论受污染 |
| Plan O warmup=max_iters | Critic | BUG-41: 全程 warmup, LR 未达正常值 | 在线路径验证失败 |
| Plan P lr_mult=1.0 | Admin | 与 P6 (lr_mult=2.0) 不一致 | Plan P FAIL |
| Plan P2 max_iters<milestone | Critic | BUG-42: 全程无 LR decay | @2000 回调 |
| Conductor 去 GELU 建议 | Critic | BUG-40: 审计链连锁失误 | P6 用退化架构 3000 iter |
| Deep Supervision 估算 | Critic | BUG-43: 未读代码估 "1-2 天" | 优先级误排 |

### Critic 纠正 Conductor 的关键错误

1. **BUG-43**: Conductor 估算 Deep Supervision 实现需 "1-2 天, 中等复杂度", 实际一行代码 (`git.py:L386-388`). Conductor 未读代码就估算.
2. **off_th 对比误导**: Conductor 暗示 GELU 损害 off_th, Critic 纠正: P5b=0.195 ≈ P6=0.196, 无影响.
3. **AR 序列长度**: Conductor 说 "原始 GiT 序列更长 (数百目标)", 实际 GiT det per-query=5 token, OCC per-query=30 token.
4. **BUG-39 过度反应**: Conductor 在 @3000 将因式参数化退化评为 CRITICAL, Critic 纠正为 MEDIUM (退化≠无效, P6 仍超 P5b).

---

## 4. BUG 完整清单

| BUG | 严重性 | 状态 | 描述 | 发现者 | 修复/影响 |
|-----|--------|------|------|--------|----------|
| BUG-2 | HIGH | FIXED | 评估逻辑错误 | Critic (旧) | 代码修复 |
| BUG-3~7 | — | FIXED | 早期 bug 批量修复 | 多方 | 代码修复 |
| BUG-8 | HIGH | FIXED | 代码位置错误 | Critic (旧) | ORCH_004 修复 |
| BUG-10 | HIGH | FIXED | 冷启动影响 | Critic (旧) | ORCH_004 修复 |
| BUG-11 | HIGH | FIXED | z+=h/2 顶部偏移 | Critic | P4 修复, commit `965b91b` |
| BUG-12 | HIGH | FIXED | cell 内匹配逻辑 | Admin | 评估代码修复 |
| BUG-13 | LOW | UNPATCHED | 未指定, 低优先级 | — | 暂不处理 |
| BUG-14 | MEDIUM | OPEN | Grid token 冗余 | Critic | 架构层面, 待后续 |
| BUG-15 | HIGH | FIXED | 压缩瓶颈 | Critic | P5b 双层投影修复 |
| BUG-16 | MEDIUM | NOT BLOCKING | — | — | — |
| BUG-17 | HIGH | FIXED | LR milestone 相对 begin | Conductor | P5b milestones 修正 |
| BUG-18 | MEDIUM | OPEN | GT instance 未跨 cell 关联 | Critic | 设计层, P6+ 路线图 |
| BUG-19 | HIGH | FIXED | z+=h/2 投影偏移 | Critic | 删除该行, commit `965b91b` |
| BUG-20 | HIGH | ACKNOWLEDGED | bus 振荡 = mini 数据量天花板 | Critic | 无法在 mini 修复 |
| BUG-21 | MEDIUM | EXPLAINED | off_th 退化 (双层投影结构差异) | Conductor | 非 GELU 相关 |
| BUG-22 | HIGH | VERIFIED | 10 类 ckpt 兼容性 | Conductor | Admin 验证通过 |
| BUG-23 | HIGH | FIXED | GPU 显存信息错误 (48GB 非 24GB) | Critic | 约束大幅放松 |
| BUG-24 | MEDIUM | FIXED | 缺少单类诊断 config | Critic | Plan K 创建 |
| BUG-25 | HIGH | FIXED | 无在线 DINOv3 路径 | Critic | Admin 实现在线提取 |
| BUG-26 | MEDIUM | FIXED | DINOv3 存储过估 (175GB 非 2.1TB) | Critic | BLOCKER 降级 |
| BUG-27 | CRITICAL | ACKNOWLEDGED | Plan K vocab 不兼容 (230→221) | Critic | 诊断结论受污染 |
| BUG-28 | HIGH | ACKNOWLEDGED | Plan L 双变量混淆 | Critic | 无法干净归因 |
| BUG-29 | LOW | N/A | Plan K sqrt 单类无意义 | Critic | 不影响结果 |
| BUG-30 | INVALID | CLOSED | GELU 不损害 off_th | Critic 自纠 | 基于 BUG-27 污染数据 |
| BUG-31 | HIGH | ACKNOWLEDGED | Plan M/N 继承 vocab 问题 | Critic | M vs N 对比仍有效 |
| BUG-32 | MEDIUM | NOTED | Plan K off_cy LR decay 后退化 | Critic | P6 LR 配置注意 |
| BUG-33 | MEDIUM | FIXED | DDP val 缺 DistributedSampler | Admin | config 修复, ±10% 偏差 |
| BUG-34 | LOW | MITIGATED | proj lr_mult 过高 | Critic | LR decay 后自动缓解 |
| BUG-35 | MEDIUM | CONFIRMED | DINOv3 unfreeze 特征漂移 | Critic | frozen only 策略 |
| BUG-36 | HIGH | ACKNOWLEDGED | M/N vs P6 对比不公平 (1024 vs 2048) | Critic | CEO 基于不公平对比 |
| BUG-37 | HIGH | FIXED | P5b 基线不可信 (DDP 偏差) | Critic | ORCH_020 单 GPU re-eval |
| BUG-38 | LOW | CLOSED | Critic 预测准确, 延迟 500 iter | Critic 自纠 | — |
| BUG-39 | MEDIUM | ACKNOWLEDGED | 因式参数化退化但有效 | Critic | 降级 CRITICAL→MEDIUM |
| BUG-40 | HIGH | ACKNOWLEDGED | Critic 审计链连锁失误 | Critic 自纠 | BUG-27→30→去 GELU |
| BUG-41 | HIGH | CONFIRMED | Plan O warmup=max_iters | Critic | 在线路径验证无效 |
| BUG-42 | MEDIUM | CONFIRMED | Plan P2 全程无 LR decay | Critic | @2000 回调不归因 GELU |
| BUG-43 | MEDIUM | ACKNOWLEDGED | Conductor 未读代码估算难度 | Critic | 优先级误排已纠正 |
| BUG-44 | LOW | NOTED | Deep supervision 各层共享 vocab | Critic | 理论风险, 暂不处理 |
| BUG-45 | MEDIUM | OPEN | OCC head 推理 attn_mask=None | Critic | 训练/推理不一致, 待修复 |

**BUG 统计**: 45 个 BUG, 其中 FIXED/CLOSED 22 个, OPEN/ACKNOWLEDGED 18 个, INVALID 1 个, LOW/N/A 4 个

**发现者分布**: Critic 发现 ~25 个 (最多), Conductor ~10 个, Admin ~5 个, CEO ~5 个

---

## 5. 架构演化

### 投影层
```
P1-P4: 无 DINOv3
P5:    Linear(4096, 768)              # 5.3:1 压缩, 瓶颈
P5b:   Linear(4096, 1024)+GELU+Linear(1024, 768)  # CEO 决策, 双层+非线性
P6:    Linear(4096, 2048)+Linear(2048, 768)        # 宽投影, 无 GELU (BUG-39 因式参数化)
ORCH_024: Linear(4096, 2048)+GELU+Linear(2048, 768)  # 最终版: 宽+非线性
```

### DINOv3 集成
```
P1-P4: CNN 特征
P5-P5b: 预提取 Layer 16, 24.15 GB (mini), fp16
Plan M/N: 在线提取实验 (mini), frozen vs unfreeze
ORCH_024: 在线提取 frozen, ViT-7B fp16, 4096 维
```

### 类别扩展
```
P1-P5b: 4 类 (car, truck, bus, trailer)
P6+:   10 类 (+construction_vehicle, pedestrian, motorcycle, bicycle, traffic_cone, barrier)
       num_vocal: 224→230
```

### 标签系统
```
P1-P3: AABB 包围盒投影
P4+:   旋转多边形覆盖判定 (Shapely convex hull)
       BUG-19 修复: z+=h/2 删除
       center/around 标记
```

### Loss 和优化器
```
P5:    per_class_balance, Linear LR warmup, MultiStepLR
P5b:   sqrt 加权 balance (缓解小类噪声), 修正 milestones
P6:    lr_mult=2.0 for proj, bg_weight=2.5
ORCH_024: warmup=2000, milestones=[15000,25000], max_iters=40000
```

### Token 布局 (num_vocal=230)
```
Bins:    0-167   (168 bins, 空间量化)
Classes: 168-177 (10 类)
BG:      178     (背景)
Markers: 179-182 (START/END/SEP 等)
Theta_G: 183-218 (36 粗角度 bins)
Theta_F: 219-228 (10 细角度 bins)
Ignore:  229
```

---

## 6. 未完成的待办

### 高优先级 (ORCH_024 后)

| 待办 | 难度 | 说明 |
|------|------|------|
| **Deep Supervision** | 零 (一行改动) | `git.py:L386-388`, `loss_out_indices=[8,10,11]`. 第一个实验 |
| **BUG-45 修复** | 低 (2-4h) | OCC head 推理 attn_mask=None, 参考 det head 修复 |
| **Structured Attention Mask** | 低 | CEO 建议 hard mask, 与 deep supervision 同测 |

### 中优先级

| 待办 | 难度 | 说明 |
|------|------|------|
| **方案 D (历史 occ box 2 帧)** | 高 (1-2 周) | 最有前途的下一步, 修改 LoadAnnotations3D_E2E + GenerateOccFlowLabels |
| **方案 E (LoRA)** | 中 (2-3 天) | DINOv3 域适应, rank=16, ~12M 参数, +2 GB 显存 |
| **Per-slot 指标提取** | 低 | 验证 Slot 1→3 错误累积 (CEO 观察), 需修改 eval 代码 |
| **@4000 单 GPU re-eval** | 低 | 确认 DDP 偏差 (BUG-33), 需 GPU 空闲 |

### 低优先级 / 长期

| 待办 | 说明 |
|------|------|
| BUG-14: Grid token 冗余 | 架构层面优化 |
| BUG-18: GT instance 跨 cell 关联 | 评估系统改进 |
| 方案 F: 多尺度特征 | 复杂度高, 搁置 |
| AR 解码长度优化 | 仅在其他方案无效时考虑 |
| 3D Anchor / 射线采样 (P7b) | 长期路线图 |
| V2X 融合 (P8) | 需外部数据支持 |

### 自动化测试框架 (ORCH_025)
**已完成**: 177 passed, 12 skipped, 3 xfailed
- test_config_sanity.py: 24 config × 6 验证项, 防 BUG-41/42 回归
- test_eval_integrity.py: 合成数据验证, 防 BUG-12 回归
- test_label_generation.py: 旋转多边形 + BEV 量化验证
- test_training_smoke.py: OccHead 结构 + 维度 + 词表验证

---

## 7. 经验教训

### Mini 数据集上学到了什么

1. **Mini 只能做代码验证和 bug 发现，不能做架构决策** — bus 振荡 (BUG-20) 是数据量天花板，非模型 bug。car_P 天花板 ~0.12-0.13。
2. **类别振荡是结构性问题** — 92:1 的类别不平衡 + 5.3:1 压缩瓶颈导致零和博弈。sqrt 加权缓解但不根治。
3. **500 iter 不够验证** — 需 ≥2000 iter on mini。多次 500-iter 早停决策被证明错误。
4. **@500 数据无判定价值** — Plan L @500=0.054→@1000=0.140，@500 仅反映初始化效应。
5. **GELU 加速收敛** — P2@1000 +72% vs P6，但需足够的 LR decay 时间才能看到真正效果。

### Agent 系统运行中发现的问题和改进

1. **Over-engineering**: 初期用 TaskCreate 做简单操作，后改为直接执行。`cat` 约定多次未被理解。
2. **Script bugs**: watchdog、capture-pane 等自动化脚本经历 3-4 轮修复。教训: 部署前 step-by-step trace。
3. **BUG-43 (不读代码估算)**: Conductor 估算 Deep Supervision "1-2 天"，实际一行代码。**永远先读代码再估算**。
4. **Critic 审计链失误 (BUG-40)**: BUG-27 污染数据→错误假设→去 GELU 建议→3000 iter 低效。审计也会出错，需交叉验证。
5. **归因精确性**: Conductor 多次错误归因（AR 序列长度、off_th 与 GELU 关系），CEO 和 Critic 纠正。
6. **DDP 偏差 (BUG-33)**: 不可预测方向，最大 ±10%。关键 checkpoint 必须单 GPU re-eval。
7. **两阶段循环**: Phase 1 信息收集 + Phase 2 决策行动的分离有效避免了 "收到数据立即冲动决策" 的问题。

### 对后续 Full nuScenes 训练的建议

1. **@4000 是第一个可信评估点, @8000 才适合架构决策** — 不要在 @2000 做任何结论。
2. **类别再平衡是正常过程** — @4000 car_R 下降 + truck/bicycle 出现，是模型从 car-only 向多类学习的正常转换。
3. **off_th 改善显著** (0.174→0.150) — Full nuScenes 数据多样性对朝向估计有巨大帮助，远超 mini。
4. **off_cy 恶化需关注** (0.069→0.097) — 其他 offset 指标改善而 cy 恶化，可能有特定原因。
5. **LR decay @17000 是关键转折点** — mini 经验显示 LR decay 后指标会有显著变化。当前 LR=2.5e-06 恒定至 @17000。
6. **单 GPU re-eval 至少做 1 次** — 确认 DDP 偏差方向和幅度，建议在 @6000 或 @8000。
7. **Deep Supervision 是 ORCH_024 后第一个实验** — 零成本一行改动，潜在收益大。

---

## 附: 实验因果链图

```
P4 (AABB→旋转多边形, BUG修复)
 └→ P5 (DINOv3 Layer 16, offset飞跃)
     ├→ P5b (三项修复: 双层投影+sqrt+milestones)
     │   └→ P6 (宽投影2048, 10类, car_P=0.129)
     │       ├→ Plan P (GELU+lr_mult=1.0) → FAIL (超参)
     │       ├→ Plan P2 (GELU+lr_mult=2.0) → GELU确认! (+72%)
     │       └→ ★ ORCH_024 (Full nuScenes, 2048+GELU+在线DINOv3) → 进行中
     └→ 诊断实验
         ├→ Plan K (单类car) → BUG-27 污染
         ├→ Plan L (宽投影预提取) → 有效但弱
         ├→ Plan M (在线unfreeze) → 特征漂移! BUG-35
         └→ Plan N (在线frozen) → mini不达标, BUG-31
```

---

*报告完毕。所有数据来源: MASTER_PLAN.md, Supervisor 报告, VERDICT 判决, ORCH 执行报告。*
