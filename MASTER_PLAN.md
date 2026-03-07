# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-07 02:55 (循环 #32, CEO 紧急指令)

## 当前阶段: P4 已批准! Phase 1 + Phase 2 并行推进, ORCH_005/006 已签发

### CEO 紧急指令 #6 (2026-03-07 02:50)
- **批准 P4**, Phase 1 + Phase 2 同时推进
- **GPU 限制**: 只用 0,2, 可占满
- **评估标准**: Phase 1 后 avg_P > 0.15 → Phase 2 低优先级; avg_P < 0.12 → 立即集成 Phase 2

---

### ORCH_005 — Phase 1: AABB 修复 + BUG-11 + P4 训练 [DELIVERED]

| 任务 | 内容 | 状态 |
|------|------|------|
| 任务 1 | AABB → 旋转多边形 (generate_occ_flow_labels.py) | PENDING |
| 任务 2 | BUG-11 修复 (删除默认类别顺序) | PENDING |
| 任务 3 | P4 训练: P3@3000 恢复, 4000 iter, GPU 0,2 | PENDING |

**P4 Config (plan_g_aabb_fix.py):**
- 起点: P3@3000
- max_iters: 4000, val_interval: 500
- bg_balance_weight: **2.0** (从 3.0 降)
- reg_loss_weight: **1.5** (从 1.0 升)
- warmup: 500 步 linear
- lr: base_lr=5e-05, milestones [2500, 3500]
- max_norm: 10.0
- use_rotated_polygon: True

### ORCH_006 — Phase 2: DINOv3 离线特征预提取 [PENDING]

| 任务 | 内容 | 状态 |
|------|------|------|
| 预提取脚本 | DINOv3 Layer 16-20 → .pt 文件 (323 张图) | PENDING |
| GiT 集成 | 修改 vit_git.py 加载 .pt 替代 Conv2d | 等待触发条件 |

**触发条件**: Phase 1 avg_P < 0.12 → 立即集成

---

### P3 训练 — COMPLETED (基线)

| 指标 | P3@4000 | P3@3000 (P4起点) | P2@6000 |
|------|---------|-----------------|---------|
| car_R | 0.570 | **0.614** | 0.596 |
| car_P | 0.084 | 0.082 | 0.079 |
| truck_R | 0.302 | 0.326 | 0.290 |
| truck_P | 0.211 | **0.306** | 0.190 |
| bus_R | 0.712 | 0.636 | 0.623 |
| bus_P | 0.153 | 0.133 | 0.150 |
| trailer_R | 0.622 | 0.622 | 0.689 |
| trailer_P | 0.041 | **0.068** | 0.066 |
| bg_FA | **0.185** | 0.194 | 0.198 |
| offset_cy | **0.087** | 0.123 | 0.095 |
| offset_th | 0.214 | 0.214 | 0.217 |
| avg_P | 0.122 | **0.147** | 0.121 |

**P3@3000 选为 P4 起点**: avg_P=0.147 (P3最佳), truck_P=0.306 (历史最高)

---

## 架构审计待办 (VERDICT_ARCH_REVIEW) — 持久追踪

> CEO 指令: 此区域持续追踪, 不随循环删除

### 紧急修复
- [x] BUG-2 → FIXED
- [x] BUG-8 修复 → ORCH_004 完成
- [x] BUG-10 修复 → ORCH_004 完成
- [ ] BUG-11 修复 → **ORCH_005 任务 2 (进行中)**

### 架构/标签优化 (P4)
- [ ] **AABB → 旋转多边形** → **ORCH_005 任务 1 (进行中)**
- [ ] **DINOv3 离线预提取** → **ORCH_006 (进行中)**
- [ ] Score 区分度改进 (待评估)
- [ ] BUG-14: Grid token 冗余
- [ ] BUG-15: DINOv3 利用率
- [ ] 新增层 12-17 加 global attention

### 未实现历史分析
- [x] 分析 1: AABB → 旋转多边形 → **升级为 ORCH_005 任务 1!**
- [ ] 分析 2: 2D-3D 视觉对齐
- [ ] 分析 4: Token 合并
- [x] 分析 3: Center/Around

---

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2 | CRITICAL | **FIXED** |
| BUG-8 | CRITICAL | **FIXED & VALIDATED** |
| BUG-9 | 致命 | **FIXED (P2+P3 config)** |
| BUG-10 | HIGH | **FIXED & VALIDATED** |
| BUG-11 | LOW | **ORCH_005 修复中** |
| BUG-12 | HIGH | **FIXED** |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 |
| BUG-15 | HIGH | 架构层面 |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| **ORCH_005** | **P4 Phase 1: AABB+BUG-11+P4训练** | **DELIVERED** |
| **ORCH_006** | **P4 Phase 2: DINOv3 预提取** | **PENDING** |
| AUDIT_P3_FINAL | P3 终审 | VERDICT: CONDITIONAL (已处理) |

## 下一步计划 (循环 #33+)
1. **监控 ORCH_005 执行**: AABB 修复 → BUG-11 → 标签重生成 → P4 训练启动
2. **监控 ORCH_006 执行**: DINOv3 预提取准备
3. **P4 首次 val (~P4@500)**: 关注 avg_P 是否超过 Phase 2 触发阈值
4. **Phase 2 触发判断**: avg_P > 0.15 → 低优先级; avg_P < 0.12 → 立即集成

## 历史决策
### [2026-03-07 02:55] 循环 #32 (CEO 紧急) — P4 批准, ORCH_005/006 签发
- CEO 紧急指令: 批准 P4, Phase 1+2 并行, GPU 0,2 only
- ORCH_005: AABB→旋转多边形 + BUG-11 + P4 训练 (P3@3000, 4000 iter)
- ORCH_006: DINOv3 离线预提取 Layer 16-20
- P4 config: bg_balance_weight=2.0, reg_loss_weight=1.5
- 评估标准: avg_P>0.15→P2低优; avg_P<0.12→立即集成

### [2026-03-07 02:40] 循环 #32 — VERDICT_P3_FINAL 处理
### [2026-03-07 01:50] 循环 #31 — P3 完成, 签发 Critic 终审
### [2026-03-07 01:40] 循环 #30 — P3@3000/@3500, offset_cy 首破红线
### [2026-03-07 01:10] 循环 #29 — P3@2500 LR decay 验证成功
### [2026-03-06 23:55] 循环 #28 — P3@2000 + VERDICT_ARCH_REVIEW
### [2026-03-06 22:30] 循环 #25 — P3@500 首次评估
### [2026-03-06 21:55] 循环 #24 — P3 启动成功
### [2026-03-06 21:00] 循环 #23 — ORCH_004 签发
### [2026-03-06 20:55] 循环 #22 — P2@6000 终评
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
