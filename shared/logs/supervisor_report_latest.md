# Supervisor 摘要报告
> 时间: 2026-03-06 17:18
> Cycle: #91 (深度检查)

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 配置: `configs/GiT/plan_e_bug9_fix.py`
- 进度: iter 3050 / 6000 (50.8%)
- GPU 使用: GPU 0 (22.4GB/49GB, 100%) + GPU 2 (23GB/49GB, 100%)
- 训练是否正常运行: **是** — 无 NaN、无 OOM
- ETA 完成: ~19:43 (剩余 ~2h26m)
- **LR 已衰减!** base_lr: 5e-05 → 5e-06 (10x 降低), effective lr: 2.5e-06 → 2.5e-07
- 下次 val: iter 3500 (~18:08)
- 下次 LR milestone: iter 5000

## 核心指标（P2@3000 — 最新可用 val）

| 指标 | P2@3000 | P2@2500 | P1@6000 | 红线 | 状态 |
|------|---------|---------|---------|------|------|
| car_recall | **0.7308** | 0.5506 | 0.6283 | — | +33% ↑ 大幅回升 |
| truck_recall | **0.4019** | 0.3812 | 0.3579 | < 0.08 | SAFE, 历史新高 |
| bus_recall | 0.4793 | 0.6363 | 0.6265 | — | -25% ↓ 但 > 0.40 |
| trailer_recall | **0.9556** | 0.5778 | 0.6444 | — | **达标! (target 0.95)** |
| bg_false_alarm | **0.2840** | 0.2029 | 0.1628 | > 0.25 | **🔴 已突破红线!** |
| truck_precision | 0.1017 | 0.2987 | 0.1756 | — | -66% ↓ |
| bus_precision | 0.1152 | 0.1736 | 0.1555 | — | -34% ↓ |
| avg_offset_cx | 0.0531 | 0.0582 | 0.0805 | ≤ 0.05 | 持续改善 |
| avg_offset_cy | 0.0890 | 0.0874 | 0.1392 | ≤ 0.10 | SAFE |
| avg_offset_th | 0.2439 | 0.2570 | 0.2197 | ≤ 0.20 | **⚠️ 超红线, 但在改善** |
| avg_precision | ~0.081 | ~0.158 | ~0.114 | ≥ 0.20 | 远低于目标 |

**分析**: recall↑ + precision↓ + bg_FA↑ = 模型 over-predict。LR 已在 iter 3000 衰减 10x, @3500 是验证是否收敛的关键观察点。

## Loss 趋势 (iter 3010-3050, LR 衰减后)
- cls_loss: 0.08~0.25, 典型 ~0.15 (**较衰减前显著降低!**)
- reg_loss: 0.27~0.66, 典型 ~0.45
- total_loss: 0.35~0.81, 典型 ~0.61 (**较衰减前 ~0.68 有所下降**)
- grad_norm: 6.0~32.6, 多数 < 10.0
- **LR 衰减效果初现**: cls_loss 明显下降, total_loss 开始收窄

## 代码变更（最近 5 条 GiT commit）
```
157fee4 Conductor: MASTER_PLAN updated - Plan D terminated, P1 Center/Around strategy
e8063bc MASTER_PLAN: Plan D @500 data added, P1 deferred, GPU strategy updated
242acbc MASTER_PLAN: Plan D + Center/Around parallel launch, CEO corrections
6bfb9ea MASTER_PLAN: Plan C terminated, Plan D launching
7322488 Update MASTER_PLAN: iter 1500 RED LINE, Plan D ordered
```
无新代码变更。

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001 | COMPLETED | BUG-12 eval slot ordering fix |
| ORCH_002 | COMPLETED | BUG-9 grad clip diagnosed |
| ORCH_003 | COMPLETED | P1 eval + P2 launched |

无 PENDING 指令，无积压。

## Admin 最新活动
- 最后活动: ORCH_003 完成 (14:18), 此后 idle
- Admin tmux session: UP

## 异常告警
1. **🔴 bg_false_alarm = 0.284 — 已突破 0.25 红线!** Conductor 干预阈值 0.30。@3500 val 是关键判断点
2. **⚠️ offset_th = 0.244 > 0.20 红线**: 仍超标但趋势改善 (0.257→0.244)
3. **⚠️ avg_precision = 0.081**: 远低于 0.20 目标
4. **ℹ️ LR 衰减已生效**: 5e-05 → 5e-06, cls_loss 初步下降, 有望缓解 over-predict
5. **ℹ️ GPU 1/3 完全释放**: 外部任务已结束 (15MB), 可用于后续实验
6. **ℹ️ BUG-10 未修复**: optimizer cold start

## Checkpoint 清单 (6 个, 共 ~11.8 GB)
| Checkpoint | 时间 |
|-----------|------|
| iter_500.pth | 14:39 |
| iter_1000.pth | 15:09 |
| iter_1500.pth | 15:39 |
| iter_2000.pth | 16:09 |
| iter_2500.pth | 16:39 |
| iter_3000.pth | 17:09 |

## GPU 状态
| GPU | 已用 | 总量 | 利用率 | 任务 |
|-----|------|------|--------|------|
| 0 | 22.4 GB | 49.1 GB | 100% | P2 训练 |
| 1 | 15 MB | 49.1 GB | 0% | **空闲 (已释放)** |
| 2 | 23.0 GB | 49.1 GB | 100% | P2 训练 |
| 3 | 15 MB | 49.1 GB | 0% | **空闲 (已释放)** |

## Agent 状态
| Agent | tmux | 状态 |
|-------|------|------|
| conductor | UP (attached) | 监控 P2 |
| admin | UP | idle |
| critic | UP | idle |
| ops | UP (attached) | idle |
| supervisor | UP (attached) | cycle #91 |

## BUG 状态
| BUG | 状态 | 影响 |
|-----|------|------|
| BUG-9 | FIXED (max_norm=10.0) | ~35% iters unclipped |
| BUG-10 | UNPATCHED | optimizer cold start |
| BUG-12 | FIXED | eval slot ordering |
