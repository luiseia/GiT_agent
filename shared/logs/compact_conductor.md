# Conductor 工作上下文快照
> 时间: 2026-03-08 11:58
> 循环: #76 (Phase 1 完成)
> 目的: Context compaction

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 放弃预提取路线, 走在线 DINOv3 提取 (避免 2.1TB 存储)。**

---

## 当前状态

### ★ P6 宽投影 mini 验证 — @1500 PASS, @2000 振荡回摆, 继续到 @3000
- Config: `plan_p6_wide_proj.py`, 投影层 `Linear(4096,2048)→Linear(2048,768)` **无 GELU 无 LN**
- GPU 0+2 DDP, iter ~2490/6000, ~3.0 s/iter
- load_from: P5b@3000, proj lr_mult=2.0
- **LR decay @2500 即将触发** (milestone[0]=2000, begin=500 → 实际 iter 2500)

**P6 Val 轨迹 (DDP — Precision 可信, Recall/bg_FA 有 BUG-33 偏差)**:
| Ckpt | car_R⚠️ | car_P✅ | truck_R | bus_R | constr_R | barrier_R | bg_FA⚠️ | off_cx | off_cy | off_th |
|------|---------|--------|---------|-------|----------|-----------|---------|--------|--------|--------|
| @500 | 0.252 | 0.073 | 0.116 | 0.009 | 0.046 | 0.020 | 0.163 | 0.087 | 0.077 | 0.236 |
| @1000 | 0.197 | 0.054 | 0.043 | 0.112 | 0.306 | 0.141 | 0.323 | 0.127 | 0.092 | 0.250 |
| @1500 | **0.681** | **0.117** | 0.000 | 0.126 | 0.064 | 0.000 | 0.278 | **0.034** | 0.069 | 0.259 |
| @2000 | 0.428 | **0.111** | 0.180 | 0.267 | 0.194 | 0.000 | 0.327 | 0.084 | 0.068 | 0.230 |

**类振荡周期 ~1000 iter**: @500 car主导 → @1000 小类爆发 → @1500 car反弹 → @2000 小类再反弹
**car_P 趋势**: 0.073→0.054→**0.117**→**0.111** — @1500+ 稳定在 0.11+ (> P5b 0.107)

### VERDICT_P6_1500 判决 (Critic, Cycle #74)
**PROCEED — P6 继续到 @3000, 不需要 P6b**
- 假说 B 完全验证: @1000 崩塌是类振荡暂态, 非架构缺陷
- car_P=0.117 超 P5b 历史最优 (0.107), 投影层仅 1500 iter
- off_cx=0.034 历史最佳, off_cy=0.069 远优于 P5b
- LR decay @2500 后振荡将被压制, 不需要 P6b
- P6 @3000 是 mini 最终评估点
- **BUG-33 修复**: 单 GPU re-eval + 长期加 DistributedSampler
- **P6 @3000 预期**: car_P ~0.12-0.13, off_th ~0.20, bg_FA 0.22-0.28

### BUG-33 — 根因确认, 修复已应用
- **根因**: DDP val 缺 DistributedSampler → 每 GPU 处理全量数据 → zip-interleave 截断 → GT inflation
- **影响**: Precision 不受影响 (car_P 可信), Recall/bg_FA/offset 偏差 ~10%
- **修复**: Admin 已在 config 加 sampler, 但当前 P6 进程用旧 config
- **ORCH_019 签发**: 单 GPU re-eval P6 @500/@1000/@1500/@2000 (GPU 1+3 并行)

### 四路诊断 — 全部 COMPLETED ✅
**Plan K** @2000: car_P=0.063 (BUG-27 vocab 混淆)
**Plan L** @2000: car_P=0.111, bg_FA=0.331
**Plan M** @2000 FINAL: car_R=0.507, car_P=0.049, bg_FA=0.188 — unfreeze 特征漂移 (BUG-35)
**Plan N** @2000 FINAL: car_R=0.513, car_P=0.045, bg_FA=0.198 — frozen 稳定

**诊断最终结论**:
1. 预提取 > 在线 (car_P/car_R/bg_FA 全面领先)
2. Frozen >> Unfreeze (M @1500 car_R 崩塌 -21%, BUG-35)
3. 宽投影 2048 有效 (Plan L/P6 car_P > P5b)
4. 在线路径 car_P ~0.05 不达标 (但 proj=1024, 非 2048; full nuScenes 可能不同)

### P5b — COMPLETED ✅
- 6000/6000, bg_FA=0.208, off_th=0.198, car_P=0.107, 红线 3/5
- P6 load_from: P5b@3000

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
| **AUDIT_P6_1500** | **PROCEED** | **P6→@3000, 不需P6b, BUG-33确认, BUG-35 new** |

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
| BUG-25 | HIGH | 在线 DINOv3 路径已实现 (ORCH_016) |
| BUG-26 | MEDIUM | 只用 CAM_FRONT, 175GB fp16 |
| BUG-27 | CRITICAL | Plan K vocab 不兼容 → 结论无效 |
| BUG-28 | HIGH | Plan L 双变量混淆 |
| BUG-29 | LOW | Plan K sqrt 单类无意义 |
| BUG-30 | MEDIUM (降级) | GELU ~0.05 惩罚非致命 |
| BUG-31 | HIGH | Plan M/N 继承 BUG-27 vocab mismatch |
| BUG-32 | MEDIUM | Plan K off_cy LR decay 后退化 |
| **BUG-33** | **MEDIUM** (降级) | **DDP val GT inflation 根因确认, Precision 可信, 修复已应用, ORCH_019 re-eval** |
| **BUG-34** | **LOW** (降级) | **proj lr_mult=2.0, LR decay @2500 自动缓解** |
| **BUG-35** | **MEDIUM** | **DINOv3 unfreeze last-2 特征漂移 (car_R -21%), 在线必须 frozen** |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_015 | 诊断 Plan K + Plan L | **COMPLETED ✅** |
| ORCH_016 | 在线 DINOv3 Plan M + Plan N | **COMPLETED ✅** — 预提取>在线, Frozen>Unfreeze |
| ORCH_017 | P6 宽投影 mini 验证 | **执行中** — 2490/6000, @2000 done: car_P=0.111, 继续→@3000 |
| ORCH_018 | BUG-33 gt_cnt 调查 | **EXECUTED ✅** — 根因确认+修复, admin_report_bug33.md |
| **ORCH_019** | **BUG-33 P6 单GPU re-eval** | **DELIVERED** — GPU 1+3 并行 re-eval @500/@1000/@1500/@2000 |

---

## 待办 (按优先级)
1. **P6 LR decay @2500** (~11:54): 已触发或即将触发, 观察效果
2. **ORCH_019 re-eval 结果**: ~20min 完成, 获取 P6 可信 Recall/bg_FA/off_th
3. **P6 @2500 val** (~12:04): LR decay 后首个 checkpoint
4. **P6 @3000 val** (~12:24): **P6 mini 最终评估点 — 决定是否切 full nuScenes**
5. **P6 @3000 后决策**: 如 PASS → 签发 ORCH 准备 full nuScenes (DINOv3 提取/在线配置)
6. **P6 继续运行到 @6000**: @4500 第二次 LR decay, @6000 final ~15:00

## P6 Config (VERDICT_DIAG_FINAL + P6_1500)
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj: nn.Sequential(nn.Linear(4096, 2048), nn.Linear(2048, 768))  # 无 GELU 无 LN
proj lr_mult = 2.0  # BUG-34: LR decay @2500 自动缓解
balance_mode = 'sqrt', bg_balance_weight = 2.5
max_iters = 6000, warmup = 500, milestones = [2000, 4000] (相对 begin=500)
LR decay 实际触发: iter 2500 (5e-5→5e-6), iter 4500 (5e-6→5e-7)
```

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 17h30m
- GPU 0+2: P6 (~2490/6000) | **GPU 1+3: 空闲 → ORCH_019 re-eval**

## 路线图
- **当前**: P6 mini 验证 (等 @3000 最终判定)
- **P6b 已取消**: Critic 判定不需要 P6b, LR decay 自动修正
- **P6 full**: mini PASS 后切 full nuScenes (CEO: 在线路径; Critic: mini 预提取, full 重测在线+宽2048+frozen)
- **P7**: 历史 occ box (t-1), CEO 批准单时刻 MVP
- **P7b**: 3D Anchor, 射线采样
- **P8**: V2X 融合

## car_P 全实验对比 (均可信)
| Iter | Plan K (1类) | Plan L (10类+宽) | P5b (10类) | **P6 (宽+无GELU)** |
|------|-------------|------------------|-----------|-------------------|
| @500 | 0.064 | 0.054 | 0.080 | 0.073 |
| @1000 | 0.047 | **0.140** | 0.089 | 0.054 |
| @1500 | 0.060 | 0.103 | 0.091 | **0.117** |
| @2000 | 0.063 | **0.111** | 0.094 | **0.111** |
| @3000 | — | — | **0.107** | (待) |

## 实验设计教训
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **LR mult 慎用**: 2x 加速了小类梯度噪声, 加剧振荡 (BUG-34)
- **@500 数据可能是"蜜月期"**: P6@500 bg_FA=0.163 极优, @1000 类振荡后崩塌
- **DDP val 必须显式声明 sampler** (BUG-33)
- **DINOv3 unfreeze 不可行**: 特征漂移风险 (BUG-35)
- **类振荡是暂态非架构缺陷**: @1000 FAIL → @1500 PASS, Critic 假说 B 验证
