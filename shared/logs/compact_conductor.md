# Conductor 工作上下文快照
> 时间: 2026-03-08 13:55
> 循环: #81 (Phase 1 完成)
> 目的: Context compaction

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 放弃预提取路线, 走在线 DINOv3 提取 (避免 2.1TB 存储)。**

---

## ★★ 当前状态: Plan P FAIL (超参) | P6@3500 car_P=0.121 首超P5b | Plan P2 签发

### 核心局势 (Cycle #81)

**Plan P @500 FAIL — 超参问题非架构缺陷**:
- car_P=0.004, car_R=0.002 — 几乎为零
- 原因: lr_mult=1.0 (P6 用 2.0) + warmup=100 (P6 用 500) + LR decay@300 + 仅 500 iter
- **bg_FA=0.165 历史最低!** — GELU 对 bg/fg 判别极强, car 没来得及学
- Plan L 证据: 同 2048+GELU+lr_mult=1.0, @500=0.054, **@1000=0.140** → 需 ≥1000 iter
- **结论**: 不能基于此否定 2048+GELU 架构

**P6 突破平台 (BUG-39 退化架构反而超越 P5b!)**:
| Ckpt | car_P (真实) | bg_FA | truck_P | vs P5b 0.116 |
|------|-------------|-------|---------|--------------|
| @3000 | 0.106 | 0.297 | 0.054 | -8.6% ❌ |
| @3500 | **0.121** | 0.287 | 0.069 | **+4.5% ✅** |
| @4000 DDP | **0.123** | 0.285 | 0.077 | **+6% ✅** |

**BUG-41 NEW**: Plan O warmup=max_iters=500, 全程在 warmup 中, 结果不可信

---

## P5b 可信基线 (单 GPU, ORCH_020)
| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| @3000 | 0.675 | **0.116** | 0.043 | 0.032 | **0.189** | **0.195** |
| @6000 | 0.639 | **0.115** | 0.037 | 0.043 | **0.188** | **0.194** |

## P6 完整可信轨迹 (单 GPU, 除 @4000 为 DDP)
| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|---------|-------|-------|--------|--------|--------|
| @500 | 0.231 | 0.073 | 0.019 | 0.008 | 0.173 | 0.079 | 0.072 | 0.259 |
| @1000 | 0.252 | 0.058 | 0.027 | 0.010 | 0.352 | 0.105 | 0.077 | 0.220 |
| @1500 | 0.499 | 0.106 | 0.000 | 0.017 | 0.250 | 0.038 | 0.069 | 0.246 |
| @2000 | 0.376 | 0.110 | 0.032 | 0.018 | 0.300 | 0.085 | 0.067 | 0.234 |
| @2500 | 0.516 | 0.111 | 0.047 | 0.022 | 0.336 | 0.058 | 0.076 | 0.201 |
| @3000 | 0.617 | 0.106 | 0.054 | 0.027 | 0.297 | 0.039 | 0.073 | 0.196 |
| @3500 | 0.577 | **0.121** | **0.069** | 0.029 | 0.287 | 0.039 | 0.072 | 0.196 |
| @4000⚠️DDP | 0.616 | **0.123** | **0.077** | 0.052 | 0.285 | 0.043 | 0.076 | 0.202 |

## car_P 全实验对比
| Iter | Plan K (1类) | Plan L (2048+GELU) | P5b (1024+GELU) | P6 (2048+noGELU) |
|------|-------------|-------------------|-----------------|------------------|
| @500 | 0.064 | 0.054 | 0.080 (DDP) | 0.073 |
| @1000 | 0.047 | **0.140** | 0.089 (DDP) | 0.058 |
| @1500 | 0.060 | 0.103 | 0.091 (DDP) | 0.106 |
| @2000 | 0.063 | 0.111 | 0.094 (DDP) | 0.110 |
| @3000 | — | — | **0.116 ✅** | 0.106 |
| @3500 | — | — | — | **0.121 ✅** |
| @6000 | — | — | **0.115 ✅** | (待) |

---

## VERDICT 判决汇总

| ID | 判决 | 关键结论 |
|----|------|---------|
| AUDIT_P5_MID | CONDITIONAL | P5b 必要, 三项修复 |
| AUDIT_INSTANCE_GROUPING | CONDITIONAL | 列入 P6+ |
| AUDIT_P5B_3000 | CONDITIONAL | P6 从 @3000 |
| AUDIT_P6_ARCHITECTURE | CONDITIONAL | 诊断优先, D>C>B |
| AUDIT_DIAG_RESULTS | CONDITIONAL | 去 GELU, BUG-27/28/30 |
| AUDIT_DIAG_FINAL | CONDITIONAL | 宽投影获批, 纯双Linear无GELU |
| AUDIT_P6_1000 | CONDITIONAL | 继续到@2000, 假说B |
| AUDIT_P6_1500 | PROCEED | P6→@3000 |
| AUDIT_P6_3000 | CONDITIONAL | 架构通过, car_P平台化, COND-1/2 |
| AUDIT_P6_VS_P5B | CONDITIONAL | BUG-39 CRITICAL! P6退化架构 |
| **PLAN_P_FAIL_P6_TREND** | **(待判)** | Plan P 超参失败, P6 突破, Plan P2 |

---

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层 (Grid token 冗余) |
| BUG-15~17 | HIGH | P5b 解决 |
| BUG-18 | MEDIUM | GT instance 未跨 cell 关联 |
| BUG-19 | HIGH | FIXED — z+=h/2 删除 |
| BUG-20 | HIGH | bus 振荡=mini 数据量天花板 |
| BUG-21 | MEDIUM | off_th 退化, 真因=双层投影结构差异 |
| BUG-22~26 | HIGH/MEDIUM | ckpt/GPU/存储/在线路径 |
| BUG-27 | CRITICAL | Plan K vocab 不兼容, 结论无效 |
| BUG-28 | HIGH | Plan L 双变量混淆 |
| BUG-29 | LOW | Plan K sqrt 单类无意义 |
| **BUG-30** | **INVALID** | GELU 不损害 off_th (P5b=0.195≈P6=0.196) |
| BUG-31~32 | HIGH/MEDIUM | Plan M/N vocab / off_cy |
| BUG-33 | MEDIUM | DDP val GT inflation, 修复完成 |
| BUG-34 | LOW | proj lr_mult, LR decay 缓解 |
| BUG-35 | MEDIUM | DINOv3 unfreeze 特征漂移 |
| BUG-36 | HIGH | Plan M/N vs P6 对比不公平 |
| BUG-37 | HIGH | P5b 基线修正: car_P=0.116 |
| BUG-38 | MEDIUM | Critic 预测偏乐观, 根因=BUG-39 |
| **BUG-39** | **CRITICAL** | 双层Linear无激活=单层Linear, P6退化. 但 P6@3500 仍超P5b |
| **BUG-40** | **HIGH** | Critic审计链失误: BUG-27→BUG-30→去GELU→P6退化 |
| **BUG-41** | **HIGH** | Plan O warmup=max_iters=500, 全程warmup, 结果不可信 |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_017 | P6 宽投影 mini | @4000+ 运行中, 负面参考→但实际超P5b |
| ORCH_020 | P5b re-eval | **COMPLETED ✅ — car_P=0.116** |
| ORCH_021 | Plan O 在线+noGELU | **COMPLETED — BUG-39+BUG-41, 不可信** |
| ORCH_022 | Plan P 2048+GELU | **COMPLETED (FAIL) — car_P=0.004, 超参问题** |
| **ORCH_023** | **P6@4000 re-eval + Plan P2** | **DELIVERED — GPU 1, re-eval~10min + Plan P2 2000iter~2h** |

---

## 待办 (按优先级)
1. **等待 VERDICT_PLAN_P_FAIL_P6_TREND**: Critic 评估 Plan P 失败归因 + BUG-39 重评
2. **ORCH_023 执行**: P6@4000 re-eval (10 min) → Plan P2 启动 (2000 iter ~2h)
3. **Plan P2 监控**: @500, @1000, @1500, @2000 各 val 与 P6 同 iter 对比
4. **P6 @4500 LR decay** (~13:52): 第二次 decay 2.5e-07→2.5e-08
5. **P6 @6000 final** (~15:00): 保险确认
6. **~16:00 Plan P2@2000 完成**: Full nuScenes config 最终决策

## Full nuScenes 决策路径
- **COND-1 DONE**: P5b car_P=0.116
- **COND-2 (再修正)**: Plan P2 (2048+GELU+lr_mult=2.0, 2000 iter)
  - P2@2000 > P6@2000 (0.110) → full 用 2048+GELU
  - P2@2000 ≈ P6@2000 → full 用 P6 config (simpler)
- **COND-3 待**: 在线路径 (Plan O BUG-41 阻塞, 需后续 GELU 版)
- **三步**: Plan P2 → config 选择 → Full nuScenes (~24-48h)

## P6 Config (仍在运行, ~4500/6000)
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj: nn.Sequential(nn.Linear(4096, 2048), nn.Linear(2048, 768))  # 无 GELU = BUG-39 退化
proj lr_mult = 2.0
balance_mode = 'sqrt', bg_balance_weight = 2.5
max_iters = 6000, warmup = 500, milestones = [2000, 4000] (相对 begin=500)
LR decay: @2500 ✅, @4500 (~13:52 即将)
```

## Plan P2 Config (ORCH_023, 待启动)
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))  # 非线性!
proj lr_mult = 2.0  # 与 P6 一致!
balance_mode = 'sqrt', bg_balance_weight = 2.5
max_iters = 2000, warmup = 500, milestones = [2000, 4000] (相对 begin=500)
单 GPU, GPU 1
```

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 19h+
- GPU 0+2: P6 (~4500/6000) | GPU 1: **空闲→ORCH_023** | GPU 3: Plan O val 完成中

## 实验设计教训
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **DDP val 必须显式声明 sampler** (BUG-33)
- **DDP 偏差方向不可预测** — 必须单GPU re-eval (BUG-37)
- **两层 Linear 无激活 = 单层 Linear** — BUG-39, 但实际性能仍可超P5b
- **warmup 不能等于 max_iters** — 全程 warmup = 从未正常训练 (BUG-41)
- **超参改太多 = 实验无效** — Plan P 同时改 lr_mult+warmup+max_iters, 无法归因
- **500 iter 不够验证 2048+GELU** — Plan L @500=0.054, @1000=0.140, 需 ≥1000 iter
- **bg_FA 是 GELU 最大受益指标** — Plan P bg_FA=0.165 (历史最低, 即使 car 全崩)
