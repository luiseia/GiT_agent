# Conductor 工作上下文快照
> 时间: 2026-03-08 10:40
> 循环: #73 (Phase 2 完成)
> 目的: Context compaction

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 放弃预提取路线, 走在线 DINOv3 提取 (避免 2.1TB 存储)。**

---

## 当前状态

### P6 宽投影 mini 验证 — 训练中, @1000 双 FAIL
- Config: `plan_p6_wide_proj.py`, 投影层 `Linear(4096,2048)→Linear(2048,768)` **无 GELU 无 LN**
- GPU 0+2 DDP, iter ~1020/6000, ~3.1 s/iter
- load_from: P5b@3000, proj 层自动随机初始化, proj lr_mult=2.0

**P6 Val 轨迹**:
| Ckpt | car_R | car_P | constr_R | barrier_R | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|----------|-----------|-------|--------|--------|--------|
| @500 | 0.252 | 0.073 | 0.046 | 0.020 | **0.163** | 0.087 | 0.077 | 0.236 |
| @1000 | 0.197↓ | 0.054↓ | **0.306↑** | 0.141↑ | **0.323↑** | 0.127↓ | 0.092 | 0.250 |

- **@500 亮点**: bg_FA=0.163 全实验历史最低 → 无 GELU 对背景判别有巨大优势
- **@1000 崩塌**: 类振荡爆发 (constr +565%, barrier +605%), car/truck 被挤压 → 双 FAIL

### VERDICT_P6_1000 判决 (Critic, Cycle #73)
**CONDITIONAL — 继续训练到 @2000, 不中止**
- **假说 B 最可能**: 类振荡 + proj LR 2x 过激, 非架构缺陷
- **核心证据**: P6@500 bg_FA=0.163 → 架构无根本缺陷
- **@2000 判定标准**:
  - PASS: car_P ≥ 0.07 且 bg_FA ≤ 0.28 → 继续到 @3000
  - MARGINAL: car_P 0.05-0.07 或 bg_FA 0.28-0.35 → 等 @3000
  - FAIL: car_P < 0.05 且 car_R < 0.15 → 启动 P6b
- **P6b 备选**: 方案1(推荐) 宽2048+GELU+lr_mult=1.0 | 方案2 宽2048+ReLU | 方案3 回退1024

### 四路诊断 — COMPLETED (Plan K/L), Plan M/N 运行中
- **Plan K COMPLETED @2000**: car_P=0.063 全程 <0.07 (BUG-27 vocab 混淆, 结论受限)
- **Plan L COMPLETED @2000**: car_P=0.111 > P5b@3000=0.107, bg_FA=0.331 (条件 #5 失败)
- **Plan M/N @1000**: M_car_P=0.049 < 0.077 阈值 → 在线路径精度不达标. Unfreeze≈Frozen, 差异极小
- **Plan M/N**: ~1480/2000, @1500 ETA ~10:28-10:30, GPU 1+3

### P5b — COMPLETED ✅
- 6000/6000, bg_FA=0.208 (全程最低), off_th=0.198 (达标), 红线 3/5
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
| BUG-25 | HIGH | 在线 DINOv3 路径 → ORCH_016 已实现 |
| BUG-26 | MEDIUM | 只用 CAM_FRONT, 175GB fp16 |
| BUG-27 | CRITICAL | Plan K vocab 不兼容 → 结论无效 |
| BUG-28 | HIGH | Plan L 双变量混淆 |
| BUG-29 | LOW | Plan K sqrt 单类无意义 |
| BUG-30 | **MEDIUM** (降级) | GELU ~0.05 惩罚非致命, 无 GELU 不改善也不恶化 off_th |
| BUG-31 | HIGH | Plan M/N 继承 BUG-27 vocab mismatch |
| BUG-32 | MEDIUM | Plan K off_cy LR decay 后退化 |
| **BUG-33** | **HIGH** | **gt_cnt 跨实验不一致 (truck +95%)! ORCH_018 调查中** |
| **BUG-34** | **MEDIUM** | **proj lr_mult=2.0 过激 (Critic 失误), P6b 降回 1.0** |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_015 | 诊断 Plan K + Plan L | **COMPLETED ✅** |
| ORCH_016 | 在线 DINOv3 Plan M + Plan N | **执行中** — M/N ~1480/2000, @1000 done: 在线不达标 |
| **ORCH_017** | **P6 宽投影 mini 验证** | **执行中** — 1020/6000, @1000 双 FAIL, 继续到 @2000 |
| **ORCH_018** | **BUG-33 gt_cnt 调查** | **DELIVERED** — Admin 调查 P6 val gt_cnt 差异 |

---

## 待办 (按优先级)
1. **等 P6 @1500** (~10:43): 类振荡是否缓和? car_R 回升?
2. **等 P6 @2000** (~11:10): **PASS/MARGINAL/FAIL 最终判定** (car_P≥0.07+bg_FA≤0.28)
3. **ORCH_018 结果**: gt_cnt 差异根因, @2000 前必须完成
4. **如 P6 @2000 FAIL**: 签发 P6b (宽2048+GELU+lr_mult=1.0)
5. **如 P6 @2000 PASS**: 继续到 @3000, 规划 full nuScenes
6. **Plan M/N @1500/@2000**: 在线 DINOv3 最终数据 (但精度已判定不达标)

## P6 Config 定稿 (VERDICT_DIAG_FINAL)
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj: nn.Sequential(nn.Linear(4096, 2048), nn.Linear(2048, 768))  # 无 GELU 无 LN
proj lr_mult = 2.0  # BUG-34: 过激, P6b 应降回 1.0
balance_mode = 'sqrt', bg_balance_weight = 2.5
max_iters = 6000, warmup = 500, milestones = [2000, 4000]
```

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 16h+
- GPU 0+2: P6 | GPU 1: Plan M | GPU 3: Plan N — **4 GPU 满载**

## 路线图
- **当前**: P6 mini 验证 (等 @2000 判定)
- **P6b (备选)**: 宽投影 2048 + GELU + lr_mult=1.0 (如 P6 @2000 FAIL)
- **P6 full**: mini PASS 后切 full nuScenes (需提取 DINOv3 ~175GB)
- **P6b**: BEV PE + 先验词汇表
- **P7**: 历史 occ box (t-1), CEO 批准单时刻 MVP
- **P7b**: 3D Anchor, 射线采样
- **P8**: V2X 融合

## 实验设计教训
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **LR mult 慎用**: 2x 加速了小类梯度噪声, 加剧振荡 (BUG-34)
- **@500 数据可能是"蜜月期"**: P6@500 bg_FA=0.163 极优, @1000 类振荡后崩塌
