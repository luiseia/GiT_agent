# Supervisor 摘要报告
> 时间: 2026-03-06 17:16
> Cycle: #90 (深度检查)

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 配置: `configs/GiT/plan_e_bug9_fix.py`
- 进度: iter 3000 / 6000 (50%) — **半程!**
- GPU 使用: GPU 0 (22.4GB/49GB, 97%) + GPU 2 (23GB/49GB, 98%)
- 训练是否正常运行: **是** — 无 NaN、无 OOM
- ETA 完成: ~19:38 (剩余 ~2h29m)
- LR: base 5e-05, effective 2.5e-06
- **LR milestone iter 3000 已到达** — 学习率应在此衰减
- 下次 val: iter 3500 (~18:08)

## 核心指标（P2@3000 checkpoint — 刚刚完成!）

### P2@3000 vs P2@2500 vs P1@6000

| 指标 | P2@3000 | P2@2500 | P1@6000 | 红线 | 状态 |
|------|---------|---------|---------|------|------|
| car_recall | **0.7308** | 0.5506 | 0.6283 | — | **+33% ↑ 大幅回升!** |
| truck_recall | **0.4019** | 0.3812 | 0.3579 | < 0.08 | SAFE, 持续攀升 |
| bus_recall | 0.4793 | 0.6363 | 0.6265 | — | -25% ↓ 但仍 > 0.40 |
| trailer_recall | **0.9556** | 0.5778 | 0.6444 | — | **达标! (target 0.95)** |
| bg_false_alarm | **0.2840** | 0.2029 | 0.1628 | > 0.25 | **⚠️ 突破红线!** |
| truck_precision | 0.1017 | 0.2987 | 0.1756 | — | -66% ↓ 大幅回落 |
| bus_precision | 0.1152 | 0.1736 | 0.1555 | — | -34% ↓ |
| car_precision | 0.0731 | 0.0679 | 0.0914 | — | 基本持平 |
| trailer_precision | 0.0338 | 0.0903 | 0.0346 | — | 大幅回落 |
| avg_offset_cx | 0.0531 | 0.0582 | 0.0805 | ≤ 0.05 | 持续改善, 接近达标 |
| avg_offset_cy | 0.0890 | 0.0874 | 0.1392 | ≤ 0.10 | SAFE |
| avg_offset_th | 0.2439 | 0.2570 | 0.2197 | ≤ 0.20 | **⚠️ 仍超红线, 但较@2500改善** |
| avg_precision | ~0.081 | ~0.158 | ~0.114 | ≥ 0.20 | **↓ 精度大幅下降** |

### P2@3000 关键发现

**利好:**
1. **car_recall 大幅回升**: 0.551 → 0.731 (+33%), 接近 0.85 目标
2. **trailer_recall 达标**: 0.956 (target 0.95) — **首次达标!**
3. **truck_recall 持续攀升**: 0.402, 历史最高
4. **offset cx/cy 持续改善**: 位置精度稳步提升

**⚠️ 告警:**
1. **bg_false_alarm = 0.284 — 突破 0.25 红线!** 距 Conductor 干预阈值 (0.30) 仅 5.6% 余量
2. **precision 全面下降**: 所有类别精度骤降, avg_precision 从 0.158 降至 0.081
3. **bus_recall 下降 25%**: 0.636 → 0.479, 但仍高于 0.40 目标
4. **truck_precision 暴跌 66%**: 0.299 → 0.102

**分析**: recall 全面上升 + precision 全面下降 + bg_FA 上升 = **模型倾向于过度预测 (over-predict)**。LR milestone 3000 刚触发衰减, 后续 iters 可能收敛, 需密切观察 @3500。

## Loss 趋势 (iter 2800-3000, 最近 20 iters)
- cls_loss: 0.13~0.61, 典型 ~0.28 (波动大)
- reg_loss: 0.24~0.63, 典型 ~0.42
- total_loss: 0.37~1.20, 典型 ~0.68
- grad_norm: 5.1~22.8, 约 35% 低于 10.0 (unclipped)
- iter 3000 loss=0.434 (较低), grad_norm=6.05 (unclipped)

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
- admin.log 不存在（通过 report_ORCH_*.md 报告）
- 最后活动: ORCH_003 完成 (14:18), 此后 idle
- Admin tmux session: UP

## 异常告警
1. **🔴 bg_false_alarm = 0.284 — 已突破 0.25 红线!** Conductor 干预阈值 0.30, 余量仅 5.6%。若 @3500 继续上升需立即干预
2. **⚠️ offset_th = 0.244 > 0.20 红线**: 仍超标但较 @2500 (0.257) 有所改善
3. **⚠️ avg_precision = 0.081**: 全面下降, 远低于 0.20 目标, 模型 over-predict 倾向明显
4. **ℹ️ LR milestone 3000 已触发**: 后续 loss 应逐步降低, 可能缓解 over-predict
5. **ℹ️ BUG-10 未修复**: optimizer cold start

## Checkpoint 清单
| Checkpoint | 时间 | 大小 |
|-----------|------|------|
| iter_500.pth | 14:39 | ~1.97 GB |
| iter_1000.pth | 15:09 | ~1.97 GB |
| iter_1500.pth | 15:39 | ~1.97 GB |
| iter_2000.pth | 16:09 | ~1.97 GB |
| iter_2500.pth | 16:39 | ~1.97 GB |
| iter_3000.pth | **17:09** | ~1.97 GB |

## GPU 状态
| GPU | 已用 | 总量 | 利用率 | 任务 |
|-----|------|------|--------|------|
| 0 | 22.4 GB | 49.1 GB | 97% | P2 训练 |
| 1 | 3.3 GB | 49.1 GB | 0% | 空闲 |
| 2 | 23.0 GB | 49.1 GB | 98% | P2 训练 |
| 3 | 18 MB | 49.1 GB | 0% | 空闲 |

## Agent 状态
| Agent | tmux | 状态 |
|-------|------|------|
| conductor | UP (attached) | 监控 P2 |
| admin | UP | idle |
| critic | UP | idle |
| ops | UP (attached) | idle |
| supervisor | UP (attached) | cycle #90 |

## BUG 状态
| BUG | 状态 | 影响 |
|-----|------|------|
| BUG-9 | FIXED (max_norm=10.0) | ~35% iters unclipped |
| BUG-10 | UNPATCHED | optimizer cold start |
| BUG-12 | FIXED | eval slot ordering |
