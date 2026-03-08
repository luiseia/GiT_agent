# Conductor 工作上下文快照
> 时间: 2026-03-08 16:15
> 循环: #86 (Phase 2 完成)
> 目的: Context compaction — Mini 阶段结束, Full nuScenes 启动

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 放弃预提取路线, 走在线 DINOv3 提取 (避免 2.1TB 存储)。**

---

## ★★★★ 当前状态: VERDICT PROCEED! Full nuScenes 2048+GELU 启动! ORCH_024 DELIVERED

### 核心局势 (Cycle #86)

**Mini 验证阶段正式结束!** 所有 mini 实验 (P1-P6 + Plan K/L/M/N/O/P/P2) 全部 COMPLETED。

**VERDICT_P2_FINAL_FULL_CONFIG: PROCEED**
- Full nuScenes 使用 **2048+GELU + 在线 DINOv3 frozen**
- ORCH_024 已签发并 DELIVERED, Admin 正在准备

**Full nuScenes Config (Critic 推荐)**:
```python
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))
在线 DINOv3 frozen (不 unfreeze, BUG-35)
lr_mult = 2.0 for proj
max_iters = 40000, warmup = 2000, milestones = [15000, 25000]
num_vocal = 230, 10 classes, sqrt balance, bg_weight = 2.5
BUG-33 fix: val DistributedSampler
4 GPU DDP (0+1+2+3)
```

---

## P5b 可信基线 (单 GPU, ORCH_020)
| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| @3000 | 0.675 | **0.116** | 0.043 | 0.032 | **0.189** | **0.195** |

## P6 完整可信轨迹 (单 GPU, @4500+ 为 DDP)
| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| @500 | 0.231 | 0.073 | 0.019 | 0.008 | 0.173 | 0.259 |
| @1000 | 0.252 | 0.058 | 0.027 | 0.010 | 0.352 | 0.220 |
| @1500 | 0.499 | 0.106 | 0.000 | 0.017 | 0.250 | 0.246 |
| @2000 | 0.376 | 0.110 | 0.032 | 0.018 | 0.300 | 0.234 |
| @2500 | 0.516 | 0.111 | 0.047 | 0.022 | 0.336 | 0.201 |
| @3000 | 0.617 | 0.106 | 0.054 | 0.027 | 0.297 | 0.196 |
| @3500 | 0.577 | **0.121** | **0.069** | 0.029 | 0.287 | 0.196 |
| @4000✅ | 0.546 | **0.1263** | **0.0749** | 0.035 | **0.2741** | **0.1907** |
| @6000 DDP | 0.541 | **0.129** | 0.076 | 0.048 | 0.274 | 0.200 |

## Plan P2 完整轨迹 (单 GPU, 2048+GELU)
| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| @500 | 0.202 | 0.069 | — | — | 0.256 | 0.252 |
| @1000 | 0.299 | **0.100** | 0.031 | 0.030 | 0.328 | 0.227 |
| @1500 | 0.513 | **0.112** | 0.017 | 0.073 | 0.279 | 0.251 |
| @2000 | **0.801** | 0.096 | 0.027 | 0.035 | 0.295 | 0.208 |

> BUG-42: P2 max_iters=2000 < first milestone@2500, 全程 full LR 无 decay. @2000 回调=LR问题非架构

## P2 vs P6 iter-by-iter 对比
| iter | P6 car_P | P2 car_P | P2 lead | P6 bg_FA | P2 bg_FA |
|------|----------|----------|---------|----------|----------|
| @500 | **0.073** | 0.069 | -5.6% | **0.173** | 0.256 |
| @1000 | 0.058 | **0.100** | **+72%** | 0.352 | **0.328** |
| @1500 | 0.106 | **0.112** | **+5.7%** | **0.250** | 0.279 |
| @2000 | **0.110** | 0.096 | -12.8% | 0.300 | **0.295** |

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
| AUDIT_P6_VS_P5B | CONDITIONAL | BUG-39→MEDIUM, P6因式参数化有效 |
| PLAN_P_FAIL_P6_TREND | CONDITIONAL | Plan P超参失败, P2签发, BUG-42 |
| **P2_FINAL_FULL_CONFIG** | **PROCEED** | **Full nuScenes 2048+GELU! Mini 阶段结束!** |

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
| BUG-35 | MEDIUM | DINOv3 unfreeze 特征漂移 — frozen only |
| BUG-36 | HIGH | Plan M/N vs P6 对比不公平 |
| BUG-37 | HIGH | P5b 基线修正: car_P=0.116 |
| **BUG-38** | **LOW** | Critic 预测准确, 仅延迟 500 iter |
| **BUG-39** | **MEDIUM** | 因式参数化有优化优势, P6 car_P=0.1263 超 P5b. 退化≠无效 |
| **BUG-40** | **HIGH** | Critic审计链失误: BUG-27→BUG-30→去GELU→P6退化 |
| **BUG-41** | **HIGH** | Plan O warmup=max_iters=500, car_P=0.000, 完全无效 |
| **BUG-42** | **MEDIUM** | Plan P2 max_iters < first milestone, 全程full LR无decay |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_017 | P6 宽投影 mini | **COMPLETED ✅ — @6000 car_P=0.129 (DDP)** |
| ORCH_020 | P5b re-eval | **COMPLETED ✅ — car_P=0.116** |
| ORCH_021 | Plan O 在线+noGELU | **COMPLETED (INVALID) — car_P=0.000, BUG-41** |
| ORCH_022 | Plan P 2048+GELU | **COMPLETED (FAIL) — car_P=0.004, 超参问题** |
| ORCH_023 | P6@4000 re-eval + Plan P2 | **COMPLETED ✅ — P6@4000=0.1263, P2 GELU confirmed** |
| **ORCH_024** | **Full nuScenes 2048+GELU+在线DINOv3** | **DELIVERED — 4 GPU DDP, ~40000 iter** |

---

## 待办 (按优先级)
1. **ORCH_024 执行监控**: Admin 准备 Full nuScenes config + 在线代码验证 + 训练启动
2. **Full nuScenes @500 early eval**: 确认在线路径正常 (car_P > 0)
3. **Full nuScenes @1000 eval**: car_P > 0.02 → 在线路径可用; < 0.02 → 切预提取
4. **每 2000 iter val**: 与 mini 对比, 监控收敛
5. **风险缓解**: 如在线 DINOv3 显存不够或代码缺失, 备选预提取 175GB fp16

## Full nuScenes 预期 (Critic)
- car_P: 0.20-0.35 (Full 数据量 40x, 类振荡大幅缓解)
- 训练时间: ~40000 iter × 8 s/iter ≈ 89h ≈ 3.7 天
- val_interval = 2000 iter

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 21h+
- **4 GPU 全部空闲**: 等待 ORCH_024 执行

## 实验设计教训 (Mini 阶段总结)
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **DDP val 必须显式声明 sampler** (BUG-33)
- **DDP 偏差方向不可预测** — 必须单GPU re-eval (BUG-37)
- **两层 Linear 无激活 = 单层 Linear** — BUG-39, 但因式参数化仍可超P5b
- **warmup 不能等于 max_iters** — 全程 warmup = 从未正常训练 (BUG-41)
- **max_iters 必须大于 first milestone** — 否则全程 full LR 无 decay (BUG-42)
- **超参改太多 = 实验无效** — Plan P 同时改 lr_mult+warmup+max_iters, 无法归因
- **500 iter 不够验证 2048+GELU** — Plan L @500=0.054, @1000=0.140, 需 ≥1000 iter
- **GELU 加速收敛** — P2@1000 car_P=0.100 vs P6@1000=0.058 (+72%)
- **Mini car_P 天花板 ~0.12-0.13** — 323 图数据量极限
- **off_th 收敛到 ~0.19-0.20 与 GELU 无关** (Critic 纠正)
