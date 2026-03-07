# Supervisor 摘要报告
> 时间: 2026-03-07 03:10
> Cycle: #112

## ===== P4 已启动! AABB 修复 + BUG-11 + 新超参 =====

### 重大变化 (自 Cycle #110)

1. **ORCH_005 COMPLETED**: AABB→旋转多边形标签修复 + BUG-11 修复 + P4 训练启动
2. **ORCH_006 DELIVERED**: DINOv3 离线特征预提取 (Phase 2, 待评估触发条件)
3. **P4 (Plan G) 训练已启动**: iter 120/4000, GPU 0+2

### P4 Config 关键变化 (vs P3)

| 参数 | P3 (plan_f) | P4 (plan_g) | 变化说明 |
|------|-------------|-------------|----------|
| load_from | P2@6000 | **P3@3000** | 选择 P3 精度峰值 checkpoint |
| bg_balance_weight | 3.0 | **2.0** | Critic 建议: 降低 bg 权重 |
| reg_loss_weight | 1.0 | **1.5** | 保护 theta 回归精度 |
| use_rotated_polygon | N/A | **True** | AABB→旋转多边形标签修复 |

其他参数不变: warmup 500 linear, milestones [2500,3500], max_norm=10.0, base_lr=5e-05

### AABB 修复内容

- **问题**: AABB 给旋转车辆分配约 2x 面积的标签 → 系统性拖低 Precision
- **修复**: 使用 scipy ConvexHull + cross-product 判断 cell 是否在旋转多边形内
- **效果**: 旋转 45° 车辆标签减少 ~50%，轴对齐车辆不变
- **向后兼容**: `use_rotated_polygon=True` 参数控制

### BUG-11 修复

- **问题**: classes 默认值 `["car","bus","truck","trailer"]` 与 config 顺序不同 → 潜在标签互换
- **修复**: 删除默认值，强制显式传入，否则 raise ValueError

### P4 训练状态

- 进度: iter 120 / 4000 (**3%**)
- GPU: 0 (21.5GB, 100%) + 2 (22.1GB, 100%)
- PID: 3929983
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_g_aabb_fix/`
- ETA: ~06:20 完成
- 下次 val: iter 500 (~03:45)

### P4 早期稳定性 (iter 10-120)

- Warmup 进行中: base_lr 从 ~1e-6 爬升至 1.2e-05
- 前 50 iter: 60% clipping (grad_norm > 10.0)
- **iter 80-120 已稳定**: grad_norm 3.4-7.9，全部 unclipped
- loss_reg 偏高 (预期: reg_loss_weight 1.0→1.5 放大)
- 无 NaN/OOM

### 代码变更
GiT/ 仓库无新 commit（Admin 直接在工作目录修改，未 commit 到 GiT 远程）。

## ORCH 指令状态
| ID | 优先级 | 状态 | 内容 |
|----|--------|------|------|
| ORCH_001 | HIGH | COMPLETED | BUG-12 slot fix |
| ORCH_002 | CRITICAL | COMPLETED | BUG-9 grad clip |
| ORCH_003 | HIGH | COMPLETED | P1 eval + P2 launch |
| ORCH_004 | URGENT | COMPLETED | BUG-8+10 fix + P3 launch |
| ORCH_005 | URGENT | **COMPLETED** | AABB fix + BUG-11 + P4 launch |
| ORCH_006 | HIGH | **DELIVERED** | DINOv3 特征预提取 (Phase 2) |

### ORCH_006 触发条件
- P4 完成后 avg_P > 0.15 → Phase 2 低优先级
- P4 完成后 avg_P < 0.12 → 立即集成 Phase 2

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-8 | FIXED (bg cls loss) |
| BUG-9 | FIXED (max_norm=10.0) |
| BUG-10 | FIXED (LinearLR warmup) |
| BUG-11 | **FIXED** (classes 默认值删除) |
| BUG-12 | FIXED (eval slot ordering) |

全部 5 个已知 BUG 已修复。

## Agent 状态
| Agent | tmux | 备注 |
|-------|------|------|
| conductor | UP (attached) | 已签发 ORCH_005/006 |
| admin | UP (attached) | ORCH_005 已完成, ORCH_006 已接收 |
| critic | UP | idle |
| ops | UP | idle |
| supervisor | UP | cycle #112 |

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 21.5 GB | 100% | **P4 训练** |
| 1 | 15 MB | 0% | 空闲 |
| 2 | 22.1 GB | 100% | **P4 训练** |
| 3 | 15 MB | 0% | 空闲 |

## 下一关注点
1. P4@500 首次 val (~03:45) — 关键看 AABB 修复对 Precision 的提升效果
2. 监控 warmup 期间 grad_norm 是否持续稳定
3. ORCH_006 执行进展
