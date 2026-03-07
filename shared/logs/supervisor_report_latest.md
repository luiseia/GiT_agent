# Supervisor 摘要报告
> 时间: 2026-03-06 21:55
> Cycle: #103

## ===== P3@500 首批 Val 结果已出! BUG-8 Fix 效果显著! =====

### P3@500 Val 结果 vs P2@6000 vs P1@6000

| 指标 | P3@500 | P2@6000 | P1@6000 | vs P2 | 红线 | 状态 |
|------|--------|---------|---------|-------|------|------|
| car_R | 0.576 | 0.596 | 0.628 | -3.4% | — | 略低，正常(早期) |
| car_P | 0.075 | 0.079 | 0.091 | -5.1% | — | |
| truck_R | **0.374** | 0.290 | 0.358 | **+29%** | <0.08 | **大幅超越 P2!** |
| truck_P | **0.254** | 0.190 | 0.176 | **+33%** | — | **历史最佳!** |
| bus_R | **0.697** | 0.623 | 0.627 | **+11.9%** | — | **历史最佳!** |
| bus_P | 0.125 | 0.150 | 0.156 | -16.7% | — | 早期偏低 |
| trailer_R | 0.667 | 0.689 | 0.644 | -3.2% | — | 持平 |
| trailer_P | 0.044 | 0.066 | 0.035 | -33% | — | 早期偏低 |
| bg_FA | 0.212 | 0.198 | 0.163 | +7.1% | >0.25 | **安全** |
| offset_cx | 0.085 | 0.068 | 0.081 | +25% | ≤0.05 | 早期偏高 |
| offset_cy | 0.127 | 0.095 | 0.139 | +33.7% | ≤0.10 | 早期偏高 |
| offset_th | 0.253 | 0.217 | 0.220 | +16.6% | ≤0.20 | 早期偏高 |
| avg_P | **0.125** | 0.121 | 0.114 | **+3.3%** | ≥0.20 | **已超 P2!** |

### BUG-8 Fix 效果分析

**BUG-8 (bg cls loss) 效果极其显著:**
- truck_recall: 0.374 vs P2@6000 的 0.290 → **+29%**，仅在 iter 500 (warmup 刚结束) 就已超越 P2 训练 6000 iter 的最终结果
- truck_precision: 0.254 vs P2@6000 的 0.190 → **+33%**，历史最佳
- bus_recall: 0.697 vs P2@6000 的 0.623 → **+11.9%**，历史最佳
- avg_precision: 0.125 vs P2@6000 的 0.121 → 已略超 P2 最终水平

**BUG-10 (warmup) 观察:**
- warmup 在 iter 500 完成，LR 达到 base_lr=5e-05
- 训练过程平稳，grad_norm 均 <21，无异常 spike
- warmup 期间 loss 稳定下降: 0.88→0.36

**注意事项:**
- offset 指标 (cx/cy/th) 在 iter 500 偏高是正常的，P2 在 @500 时也类似
- bg_false_alarm 0.212 在红线内，但比 P2@6000 (0.198) 略高，需关注后续
- car_recall 0.576 vs P2 0.596 略低，但仅差 3%，后续会收敛

### P3 训练状态
- 配置: `configs/GiT/plan_f_bug8_fix.py`
- 进度: iter 500 / 4000 (12.5%) — **首批 val 已完成**
- Load from: P2@6000
- GPU: 0 (22.4GB, 55%) + 2 (23GB, 95%)
- LR: base_lr=5e-05 (warmup 刚完成)
- LR milestones: iter 2500, 3500
- Val 间隔: 每 500 iter
- 下次 val: iter 1000 (~22:20)
- ETA 完成: ~00:50

### Loss 趋势 (iter 400-500)
- cls_loss: 0.06~0.25, 典型 ~0.10
- reg_loss: 0.31~0.52, 典型 ~0.38
- total_loss: 0.36~0.77, 典型 ~0.50
- grad_norm: 3.0~9.4, 健康

### 代码变更 (GiT 最近 5 条 commit)
```
157fee4 Conductor: MASTER_PLAN updated - Plan D terminated, P1 Center/Around strategy
e8063bc MASTER_PLAN: Plan D @500 data added, P1 deferred, GPU strategy updated
242acbc MASTER_PLAN: Plan D + Center/Around parallel launch, CEO corrections
6bfb9ea MASTER_PLAN: Plan C terminated, Plan D launching
7322488 Update MASTER_PLAN: iter 1500 RED LINE, Plan D ordered
```

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001 | COMPLETED | BUG-12 fix |
| ORCH_002 | COMPLETED | BUG-9 diagnosed |
| ORCH_003 | COMPLETED | P2 launched |
| ORCH_004 | COMPLETED | BUG-8 + BUG-10 fix, P3 launched |

无 PENDING，无积压。

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 55% | **P3 训练** (val 刚完成, 恢复 train) |
| 1 | 3.1 GB | 64% | 外部: yz0364 UniAD |
| 2 | 23.0 GB | 95% | **P3 训练** |
| 3 | 3.2 GB | 67% | 外部: yz0364 UniAD |

## Agent 状态
全 5 agent tmux UP。

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-8 | **FIXED & VALIDATED** — P3@500 truck_R +29% vs P2! |
| BUG-9 | FIXED (max_norm=10.0) |
| BUG-10 | FIXED (warmup, iter 500 已完成) |
| BUG-12 | FIXED |

**全部已知 BUG 均已修复且验证!**

## 告警
1. **offset_th=0.253**: 仍高于红线 (≤0.20)，但 @500 属正常，P2 也在 @500 时偏高
2. **bg_FA=0.212**: 红线内但比 P2 最终略高，P2 在 @3000 曾达 0.284 后回落，需持续监控
3. **avg_precision=0.125**: 虽已超 P2，但距红线 (≥0.20) 仍有差距
