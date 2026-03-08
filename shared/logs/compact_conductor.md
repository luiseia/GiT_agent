# Conductor 工作上下文快照
> 时间: 2026-03-08 12:55
> 循环: #79 (Phase 1 完成)
> 目的: Context compaction

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 放弃预提取路线, 走在线 DINOv3 提取 (避免 2.1TB 存储)。**

---

## ★★ 当前状态: P5b car_P=0.116 >> P6 car_P=0.106 — P6 评估被颠覆

### 核心发现 (Cycle #79, ORCH_020 COND-1 完成)

**P5b@3000 单 GPU re-eval 结果颠覆了全部 P6 评估:**
- P5b DDP car_P=0.107 → **单GPU car_P=0.116** (DDP 低估 8%)
- P6@3000 单GPU car_P=0.106 → **P6 落后 P5b 约 10%!**
- P5b bg_FA=0.189 >> P6 bg_FA=0.297 — **P5b 远优于 P6**

**P6 vs P5b 可信对比 (均为单 GPU)**:
| 指标 | P5b@3000 | P6@3000 | P6 vs P5b |
|------|----------|---------|-----------|
| car_P | **0.116** | 0.106 | **-8.6% ❌** |
| car_R | 0.675 | 0.617 | -8.6% ❌ |
| bg_FA | **0.189** | 0.297 | **+57% ❌❌** |
| off_th | 0.195 | **0.196** | ≈ |
| off_cx | 0.063 | **0.039** | **-38% ✅✅** |
| off_cy | 0.105 | **0.073** | **-30% ✅✅** |
| truck_P | 0.043 | 0.054 | +26% ✅ |

**P6 宽投影 2048 + 无 GELU 的真实 trade-off**:
- ✅ offset 精度大幅提升 (off_cx -38%, off_cy -30%)
- ✅ 多类精度改善 (truck_P +26%)
- ❌ car_P 下降 -8.6%
- ❌ bg_FA 恶化 +57%
- ≈ off_th 持平

**AUDIT_REQUEST_P6_VS_P5B 已签发**, 等待 Critic 重新评估。

---

### P6 训练状态
- Config: `plan_p6_wide_proj.py`, `Linear(4096,2048)→Linear(2048,768)` **无 GELU 无 LN**
- GPU 0+2 DDP, iter ~3460/6000, ~3.0 s/iter
- load_from: P5b@3000, proj lr_mult=2.0
- LR: 2.5e-07 (post-decay @2500)
- ETA @6000: ~14:50

### P6 完整可信轨迹 (单 GPU re-eval, ORCH_019 + Admin)
| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|---------|-------|-------|--------|--------|--------|
| @500 | 0.231 | 0.073 | 0.019 | 0.008 | 0.173 | 0.079 | 0.072 | 0.259 |
| @1000 | 0.252 | 0.058 | 0.027 | 0.010 | 0.352 | 0.105 | 0.077 | 0.220 |
| @1500 | 0.499 | 0.106 | 0.000 | 0.017 | 0.250 | 0.038 | 0.069 | 0.246 |
| @2000 | 0.376 | 0.110 | 0.032 | 0.018 | 0.300 | 0.085 | 0.067 | 0.234 |
| @2500 | 0.516 | 0.111 | 0.047 | 0.022 | 0.336 | 0.058 | 0.076 | 0.201 |
| **@3000** | **0.617** | **0.106** | **0.054** | **0.027** | **0.297** | **0.039** | **0.073** | **0.196** |

**car_P 平台化 0.106-0.111** @1500-3000 — mini 天花板 (BUG-38)
**bg_FA 改善中**: 0.336(@2500)→0.297(@3000) — LR decay 效果
**off_th=0.196 首次<0.20** — 持续改善

### P5b 可信数据 (ORCH_020, 单 GPU)
| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|---------|-------|-------|--------|--------|--------|
| @3000 | 0.675 | **0.116** | 0.043 | 0.032 | **0.189** | 0.063 | 0.105 | 0.195 |
| @6000 | 0.639 | **0.115** | 0.037 | 0.043 | **0.188** | 0.064 | 0.123 | 0.194 |

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
| **AUDIT_P6_3000** | **CONDITIONAL** | **架构通过但精度不充分, car_P平台化, COND-1/2 BLOCKING** |
| **AUDIT_P6_VS_P5B** | **(待判)** | **P5b car_P=0.116>>P6 0.106, P6评估被颠覆** |

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
| BUG-22 | HIGH | 10 类 ckpt 兼容 ✅ |
| BUG-23 | HIGH | GPU=A6000 48GB |
| BUG-25 | HIGH | 在线 DINOv3 路径已实现 |
| BUG-26 | MEDIUM | 只用 CAM_FRONT, 175GB fp16 |
| BUG-27 | CRITICAL | Plan K vocab 不兼容 → 结论无效 |
| BUG-28 | HIGH | Plan L 双变量混淆 |
| BUG-29 | LOW | Plan K sqrt 单类无意义 |
| BUG-30 | MEDIUM (降级) | GELU ~0.05 惩罚非致命 |
| BUG-31 | HIGH | Plan M/N 继承 BUG-27 vocab mismatch |
| BUG-32 | MEDIUM | Plan K off_cy LR decay 后退化 |
| BUG-33 | MEDIUM (降级) | DDP val GT inflation — **ORCH_019 完成, car_P 也有偏差 (±10%)** |
| BUG-34 | LOW (降级) | proj lr_mult=2.0, LR decay @2500 自动缓解 |
| BUG-35 | MEDIUM | DINOv3 unfreeze 特征漂移 (car_R -21%) |
| **BUG-36** | **HIGH** | **Plan M/N vs P6 对比不公平 (proj 1024 vs 2048), 需 Plan O 验证** |
| **BUG-37** | **HIGH** | **P5b 基线不可信 → ORCH_020 完成: P5b car_P=0.116 (非 0.107)** |
| **BUG-38** | **MEDIUM** | **Critic car_P 预测偏乐观 (0.12-0.13 vs 0.106), mini 天花板 ~0.11** |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_015 | 诊断 Plan K + Plan L | **COMPLETED ✅** |
| ORCH_016 | 在线 DINOv3 Plan M + Plan N | **COMPLETED ✅** |
| ORCH_017 | P6 宽投影 mini 验证 | **@3000 CONDITIONAL PASS** — 继续到 @6000 (保险) |
| ORCH_018 | BUG-33 gt_cnt 调查 | **COMPLETED ✅** |
| ORCH_019 | BUG-33 P6 单GPU re-eval | **COMPLETED ✅** — 5 ckpt + Admin @3000 |
| **ORCH_020** | **P5b@3000 单GPU re-eval** | **COMPLETED ✅ — car_P=0.116! P6落后P5b!** |
| **ORCH_021** | **Plan O 在线+2048+无GELU** | **DELIVERED — GPU 3, 待启动, 500 iter ~1h** |

---

## 待办 (按优先级)
1. **等待 VERDICT_P6_VS_P5B**: Critic 重新评估 P6 vs P5b 对比, 6 个问题
2. **ORCH_021 Plan O**: 在线 DINOv3+2048+无GELU 验证 (COND-2), GPU 3 空闲待启动
3. **P6 @3500 val** (~13:00): 继续监控, 但 mini 价值 @3000 已耗尽 (Critic)
4. **P6 @4500 第二次 LR decay**: 观察效果
5. **P6 @6000 final** (~14:50): 保险确认

## Full nuScenes 决策被阻塞
- **COND-1 DONE**: P5b@3000 re-eval → P5b car_P=0.116 >> P6 car_P=0.106
- **COND-2 待**: Plan O (在线+2048+无GELU) → 在线 vs 预提取路线
- **Critic VERDICT 待**: P6 config 是否仍正确? Full 用 P5b 还是 P6?
- **路线选择**: 在线 vs 预提取 175GB fp16 (BUG-26: 非 2.1TB)

## P6 Config
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj: nn.Sequential(nn.Linear(4096, 2048), nn.Linear(2048, 768))  # 无 GELU 无 LN
proj lr_mult = 2.0
balance_mode = 'sqrt', bg_balance_weight = 2.5
max_iters = 6000, warmup = 500, milestones = [2000, 4000] (相对 begin=500)
LR decay: iter 2500 (5e-5→5e-6) ✅, iter 4500 (5e-6→5e-7)
```

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 18h30m
- GPU 0+2: P6 (~3460/6000) | GPU 1: 空闲 (ORCH_020 完成) | GPU 3: 空闲 (待 ORCH_021)

## car_P 全实验对比 (单 GPU 可信值)
| Iter | Plan K (1类) | Plan L (10类+宽) | **P5b (10类,1024+GELU)** | **P6 (10类,2048+无GELU)** |
|------|-------------|------------------|------------------------|------------------------|
| @500 | 0.064 | 0.054 | 0.080 (DDP) | 0.073 |
| @1000 | 0.047 | 0.140 | 0.089 (DDP) | 0.058 |
| @1500 | 0.060 | 0.103 | 0.091 (DDP) | 0.106 |
| @2000 | 0.063 | 0.111 | 0.094 (DDP) | 0.110 |
| @2500 | — | — | 0.094 (DDP) | 0.111 |
| @3000 | — | — | **0.116 ✅** | 0.106 |
| @6000 | — | — | **0.115 ✅** | (待) |

> P5b @3000/@6000 是单GPU可信值. P5b 其他为 DDP (可能偏差 ±10%). P6 全部为单GPU可信值.

## 实验设计教训
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **DDP val 必须显式声明 sampler** (BUG-33)
- **DDP Precision 也有偏差** — 不是只影响 Recall (ORCH_019)
- **DDP 偏差方向不可预测** — P5b car_P 被低估, P6@1500 被高估
- **DINOv3 unfreeze 不可行** (BUG-35)
- **类振荡是暂态非架构缺陷** (假说 B)
- **car_P 平台化 ~0.11** — mini 数据天花板 (BUG-38)
- **宽投影 trade-off**: offset 改善 vs car_P/bg_FA 退步 — 需要在 full 上验证
- **必须用单GPU re-eval做对比** — DDP 偏差可系统性误导结论 (BUG-37)
