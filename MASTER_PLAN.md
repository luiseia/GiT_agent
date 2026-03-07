# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-07 03:10 (循环 #33)

## 当前阶段: P4 训练已启动! ORCH_005 验收通过, AABB+BUG-11 修复完成

### P4 训练状态 — RUNNING
- **PID**: 3929983
- **GPU**: 0,2 (RTX A6000) | CEO 限制只用 0,2
- **Config**: `plan_g_aabb_fix.py`
- **起点**: P3@3000
- **进度**: 前 50+ iter (warmup 阶段)
- **ETA 完成**: ~06:20 (3月7日)
- **首次 val**: P4@500
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_g_aabb_fix/`

### P4 Config 变化 (vs P3)
| 参数 | P3 (plan_f) | P4 (plan_g) | 变化原因 |
|------|-------------|-------------|---------|
| load_from | P2@6000 | **P3@3000** | Critic: @3000 是 P3 最佳点 |
| bg_balance_weight | 3.0 | **2.0** | Critic: 3.0 压制 car_R |
| reg_loss_weight | 1.0 | **1.5** | Critic: 保护 theta 回归 |
| use_rotated_polygon | N/A | **True** | AABB 标签污染修复 |
| max_iters | 4000 | 4000 | — |
| warmup | 500 linear | 500 linear | — |
| milestones | [2500, 3500] | [2500, 3500] | — |

### P4 早期信号 (前 50 iter)
- Warmup 正常: LR 从 ~1e-6 爬升
- loss_reg 偏高: 预期 (reg_loss_weight 1.5x 放大)
- **梯度裁剪率 60%** (3/5 iter clipped) — 比 P3 的 0% 高, 原因:
  - reg_loss_weight 提升放大 reg 梯度
  - 旋转多边形标签分布变化
  - 应在 warmup 完成后稳定
- 无 NaN/OOM, 显存 21.5GB/49.1GB per GPU

### ORCH_005 验收: PASS
| 任务 | 执行结果 | 判定 |
|------|---------|------|
| AABB→旋转多边形 | ConvexHull + cross-product, use_rotated_polygon 参数化 | **PASS** |
| BUG-11 | classes=None + ValueError guard | **PASS** |
| P4 训练 | PID 3929983, GPU 0,2, 前 50 iter 稳定 | **PASS** |

**标签变化验证**: 45° 旋转车辆 AABB 分配 ~2x 多余 cell → 旋转多边形消除约 30-50% 假阳性标签

---

### ORCH_006 — Phase 2: DINOv3 预提取 [DELIVERED, Admin 执行中]
- 与 Phase 1 并行准备
- **触发条件**: Phase 1 avg_P > 0.15 → 低优先级; avg_P < 0.12 → 立即集成

---

### P3@3000 基线 (P4 起点)
| 指标 | P3@3000 | P2@6000 | vs P2 |
|------|---------|---------|-------|
| car_R | 0.614 | 0.596 | +3.0% |
| car_P | 0.082 | 0.079 | +3.8% |
| truck_R | 0.326 | 0.290 | +12.4% |
| truck_P | 0.306 | 0.190 | +61.1% |
| bus_R | 0.636 | 0.623 | +2.1% |
| bus_P | 0.133 | 0.150 | -11.3% |
| trailer_R | 0.622 | 0.689 | -9.7% |
| trailer_P | 0.068 | 0.066 | +3.0% |
| bg_FA | 0.194 | 0.198 | -2.0% |
| avg_P | **0.147** | 0.121 | +21.5% |

---

## 架构审计待办 (VERDICT_ARCH_REVIEW) — 持久追踪

> CEO 指令: 此区域持续追踪, 不随循环删除

### 紧急修复
- [x] BUG-2 → FIXED
- [x] BUG-8 修复 → ORCH_004 完成
- [x] BUG-10 修复 → ORCH_004 完成
- [x] BUG-11 修复 → **ORCH_005 完成!**

### 架构/标签优化 (P4)
- [x] **AABB → 旋转多边形** → **ORCH_005 完成!**
- [ ] **DINOv3 离线预提取** → ORCH_006 进行中
- [ ] Score 区分度改进 (待评估)
- [ ] BUG-14: Grid token 冗余
- [ ] BUG-15: DINOv3 利用率
- [ ] 新增层 12-17 加 global attention

### 未实现历史分析
- [x] 分析 1: AABB → 旋转多边形 → **ORCH_005 实现!**
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
| BUG-11 | LOW | **FIXED (ORCH_005)** |
| BUG-12 | HIGH | **FIXED** |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 |
| BUG-15 | HIGH | 架构层面 |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| **ORCH_005** | P4 Phase 1 | **COMPLETED — 验收通过** |
| **ORCH_006** | P4 Phase 2: DINOv3 预提取 | **DELIVERED (进行中)** |

## 下一步计划 (循环 #34+)
1. **P4@500 (~04:00?)**: 首次 val — 关键! AABB 修复效果验证
   - avg_P 是否显著提升? (P3@3000 基线 0.147)
   - car_P 是否改善? (AABB 修复最直接影响)
   - 梯度裁剪率是否稳定?
2. **ORCH_006 执行进度**: DINOv3 预提取是否完成
3. **Phase 2 触发判断**: P4 首批 val 后根据 avg_P 决定

## 历史决策
### [2026-03-07 03:10] 循环 #33 — ORCH_005 验收通过, P4 训练已启动
- ORCH_005 全部 3 项任务 PASS: AABB 修复 + BUG-11 + P4 训练
- P4 PID 3929983, GPU 0,2, 前 50 iter 稳定
- 梯度裁剪率 60% (高于 P3), 预计 warmup 后稳定
- BUG-11 正式 FIXED
- ORCH_006 DELIVERED, Admin 并行执行中
- 决策: 继续监控, 等待 P4@500

### [2026-03-07 02:55] 循环 #32 — P4 批准, ORCH_005/006 签发
### [2026-03-07 02:40] 循环 #32 — VERDICT_P3_FINAL 处理
### [2026-03-07 01:50] 循环 #31 — P3 完成
### [2026-03-07 01:40] 循环 #30 — P3@3000/@3500
### [2026-03-07 01:10] 循环 #29 — P3@2500 LR decay
### [2026-03-06 23:55] 循环 #28 — P3@2000 + VERDICT_ARCH_REVIEW
### [2026-03-06 21:55] 循环 #24 — P3 启动
### [2026-03-06 21:00] 循环 #23 — ORCH_004 签发
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
