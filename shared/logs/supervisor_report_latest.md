# Supervisor 摘要报告
> 时间: 2026-03-06 21:52
> Cycle: #102

## ===== P3 训练已启动! (Plan F, BUG-8 + BUG-10 修复) =====

### ORCH_004 — COMPLETED (21:28)
- BUG-8 修复: cls loss 添加背景类 (bg_balance_weight=3.0)
- BUG-10 修复: warmup 添加 (LinearLR 500 iters, 0.001x→1.0x)
- P3 训练已启动, PID 3775971

### P3 训练状态
- 配置: `configs/GiT/plan_f_bug8_fix.py`
- 进度: iter 500 / 4000 (12.5%) — **首次 val 进行中**
- Load from: P2@6000
- GPU: 0 (22.4GB, 97%) + 2 (23GB, 97%)
- 总迭代: 4000 (比 P2 少 2000)
- Warmup: 前 500 iter 完成, LR 已达 base_lr=5e-05
- LR milestones: iter 2500, 3500
- Val 间隔: 每 500 iter
- ETA 完成: ~00:45 (剩余 ~3h)

### P3 vs P2 config 差异
| 参数 | P2 (plan_e) | P3 (plan_f) |
|------|-------------|-------------|
| load_from | P1@6000 | **P2@6000** |
| max_iters | 6000 | **4000** |
| warmup | 无 | **LinearLR 500 iter** |
| milestones | [3000, 5000] | **[2500, 3500]** |
| BUG-8 | 未修复 | **已修复 (bg cls loss)** |
| BUG-10 | 未修复 | **已修复 (warmup)** |

### P3 早期 Loss 趋势 (iter 270-500, warmup 尾段)
- total_loss: 0.24~1.13, 典型 ~0.52
- cls_loss: 0.03~0.49, 典型 ~0.15
- reg_loss: 0.19~0.64, 典型 ~0.38
- grad_norm: 3.0~20.7, 大部分 < 10.0
- **warmup 运行正常**, LR 线性递增中
- iter 500: loss=0.364, grad_norm=5.49 (健康)

## 核心指标 (P2@6000 最终, P3 val 待出)

| 指标 | P2@6000 | P1@6000 | 红线 |
|------|---------|---------|------|
| car_R | 0.596 | 0.628 | — |
| truck_R | 0.290 | 0.358 | <0.08 |
| bus_R | 0.623 | 0.627 | — |
| trailer_R | 0.689 | 0.644 | — |
| bg_FA | 0.198 | 0.163 | >0.25 |
| truck_P | 0.190 | 0.176 | — |
| offset_th | 0.217 | 0.220 | ≤0.20 |

**P3@500 val 正在运行**, 首批结果即将出炉。

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001 | COMPLETED | BUG-12 fix |
| ORCH_002 | COMPLETED | BUG-9 diagnosed |
| ORCH_003 | COMPLETED | P2 launched |
| **ORCH_004** | **COMPLETED** | **BUG-8 + BUG-10 fix, P3 launched** |

无 PENDING，无积压。

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 97% | **P3 训练** |
| 1 | 3.3 GB | 0% | 外部: yz0364 UniAD |
| 2 | 23.0 GB | 97% | **P3 训练** |
| 3 | 18 MB | 0% | 空闲 |

## Agent 状态
全 5 agent tmux UP。

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-8 | **FIXED in P3** (bg cls loss) |
| BUG-9 | FIXED (max_norm=10.0) |
| BUG-10 | **FIXED in P3** (warmup) |
| BUG-12 | FIXED |

**全部已知 BUG 均已修复!**

## 告警
1. **ℹ️ P3@500 val 进行中**: 首批指标即将可用
2. **ℹ️ BUG-8 效果待验证**: Critic 预期 avg_precision 应显著上升
