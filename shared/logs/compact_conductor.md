# Conductor 工作上下文快照
> 时间: 2026-03-08 13:06
> 循环: #79 (Phase 2 完成)
> 目的: VERDICT_P6_VS_P5B 处理完毕, ORCH_022 签发

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 放弃预提取路线, 走在线 DINOv3 提取 (避免 2.1TB 存储)。**

---

## ★★★ 当前状态: BUG-39 CRITICAL — P6 架构退化! Plan P 是最高优先级

### 核心发现 (Cycle #79, VERDICT_P6_VS_P5B)

**BUG-39 CRITICAL**: P6 的 `Sequential(Linear(4096,2048), Linear(2048,768))` **无激活函数**数学上等价于单层 `Linear(4096,768)`。2048 中间维度不增加任何表达能力。

**BUG-40 HIGH**: Critic 审计链连锁失误: BUG-27→BUG-30→去GELU推荐→P6退化架构→3000iter低效

**BUG-30 INVALID**: GELU 不损害 off_th (P5b=0.195≈P6=0.196)。原假设基于 BUG-27 污染数据。

**P5b@3000 car_P=0.116 >> P6 car_P=0.106 — P6 退化架构导致**

### P6 vs P5b 可信对比 (均为单 GPU)
| 指标 | P5b@3000 | P6@3000 | P6 vs P5b |
|------|----------|---------|-----------|
| car_P | **0.116** | 0.106 | **-8.6% ❌** |
| car_R | 0.675 | 0.617 | -8.6% ❌ |
| bg_FA | **0.189** | 0.297 | **+57% ❌❌** |
| off_th | 0.195 | 0.196 | ≈ |
| off_cx | 0.063 | **0.039** | **-38% ✅✅** |
| off_cy | 0.105 | **0.073** | **-30% ✅✅** |
| truck_P | 0.043 | 0.054 | +26% ✅ |

---

## VERDICT 判决汇总

| ID | 判决 | 关键结论 |
|----|------|---------|
| AUDIT_P5_MID | CONDITIONAL | P5b 必要, 三项修复 |
| AUDIT_INSTANCE_GROUPING | CONDITIONAL | 列入 P6+, BUG-18 |
| AUDIT_P5B_3000 | CONDITIONAL | P6 从 @3000, bus=数据量 (BUG-20) |
| AUDIT_P6_ARCHITECTURE | CONDITIONAL | 诊断优先, D>C>B, BUG-23/26 |
| AUDIT_DIAG_RESULTS | CONDITIONAL | 方向对但混淆, 去 GELU, BUG-27/28/30 |
| AUDIT_DIAG_FINAL | CONDITIONAL | 宽投影获批, 纯双Linear无GELU无LN, BUG-31/32 |
| AUDIT_P6_1000 | CONDITIONAL | 继续到@2000, 假说B(振荡+LR), BUG-33/34 |
| AUDIT_P6_1500 | PROCEED | P6→@3000, 不需P6b, BUG-33确认, BUG-35 |
| AUDIT_P6_3000 | CONDITIONAL | 架构通过但精度不充分, car_P平台化, COND-1/2 BLOCKING |
| **AUDIT_P6_VS_P5B** | **CONDITIONAL** | **BUG-39 CRITICAL! P6退化架构, Plan P修复验证** |

---

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层 (Grid token 冗余) |
| BUG-15~17 | HIGH | P5b 解决 |
| BUG-18 | MEDIUM | 设计层 (GT instance 未跨 cell 关联) |
| BUG-19 | HIGH | FIXED — z+=h/2 删除 |
| BUG-20 | HIGH | bus 振荡=mini 数据量天花板 |
| BUG-21 | MEDIUM | off_th 退化, 真因=双层投影结构差异 (非 GELU) |
| BUG-22 | HIGH | 10 类 ckpt 兼容 ✅ |
| BUG-23~26 | HIGH/MEDIUM | GPU/存储/在线路径相关 |
| BUG-27 | CRITICAL | Plan K vocab 不兼容, 结论无效 |
| BUG-28 | HIGH | Plan L 双变量混淆 |
| BUG-29 | LOW | Plan K sqrt 单类无意义 |
| **BUG-30** | **INVALID** | ~~GELU 损害 off_th~~ 假设不成立 (P5b=0.195≈P6=0.196) |
| BUG-31~32 | HIGH/MEDIUM | Plan M/N vocab / Plan K off_cy |
| BUG-33 | MEDIUM | DDP val GT inflation, 修复完成 |
| BUG-34 | LOW | proj lr_mult, LR decay 缓解 |
| BUG-35 | MEDIUM | DINOv3 unfreeze 特征漂移 |
| BUG-36 | HIGH | Plan M/N vs P6 对比不公平 |
| BUG-37 | HIGH | P5b 基线修正: car_P=0.116 (ORCH_020 完成) |
| BUG-38 | MEDIUM | Critic 预测偏乐观, 根因=BUG-39 |
| **BUG-39** | **CRITICAL** | **双层Linear无激活=单层Linear, P6 2048无效** |
| **BUG-40** | **HIGH** | **Critic审计链失误: BUG-27→BUG-30→去GELU→P6退化** |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_017 | P6 宽投影 mini 验证 | @3000 COND PASS → BUG-39 退化, 负面参考 |
| ORCH_020 | P5b@3000 单GPU re-eval | **COMPLETED ✅ — car_P=0.116** |
| **ORCH_021** | **Plan O 在线+2048+noGELU** | **IN PROGRESS — GPU 3, ETA ~13:45. ⚠️ BUG-39 退化, 仅作 online vs preextract 参考** |
| **ORCH_022** | **Plan P 2048+GELU 验证** | **PENDING — GPU 1, 500 iter, 最高优先级!** |

---

## 待办 (按优先级)
1. **ORCH_022 Plan P**: Admin 执行, GPU 1, 2048+GELU+lr_mult=1.0, 500 iter (~25 min)
2. **ORCH_021 Plan O 结果**: ~13:40-13:45 完成, 收集 online vs preextract 对比数据
3. **Plan P 结果评估**: car_P@500>0.073 + bg_FA<0.200 → full nuScenes 用 2048+GELU
4. **P6 @6000 final** (~14:50): 保险, 负面参考
5. **后续 Plan O2**: 在线+2048+GELU, 与 Plan P 对比 (如需)

## Full nuScenes 决策路径
- **COND-1 DONE**: P5b@3000 car_P=0.116
- **COND-2 待**: Plan P (2048+GELU) → 验证宽投影真实价值
- **COND-3 待**: Plan O GELU 版 → 在线 vs 预提取
- **三步策略**: Plan P → Plan O (GELU) → Full config 选择

## Plan P Config
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))  # 非线性!
proj lr_mult = 1.0
balance_mode = 'sqrt', bg_balance_weight = 2.5
max_iters = 500, warmup = 100
单 GPU, GPU 1
```

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 18h+
- GPU 0+2: P6 (~3600/6000) | GPU 1: **空闲 → Plan P** | GPU 3: Plan O (~13:45 完成)

## 实验设计教训
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **DDP val 必须显式声明 sampler** (BUG-33)
- **DDP 偏差方向不可预测** — 必须单GPU re-eval (BUG-37)
- **car_P 平台化 ~0.11** — mini 数据天花板 (BUG-38)
- **两层 Linear 无激活 = 单层 Linear** — 数学基础不能忽略! (BUG-39)
- **基于被已知BUG污染的数据不应推导新假设** — 审计系统教训 (BUG-40)
- **必须用单GPU re-eval做对比** — DDP 偏差可系统性误导结论 (BUG-37)
