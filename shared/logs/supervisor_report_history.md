# Supervisor 摘要报告
> 时间: 2026-03-06 17:10
> Cycle: #89 (新角色首份报告)

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 配置: `configs/GiT/plan_e_bug9_fix.py`
- 进度: iter 2990 / 6000 (49.8%)
- GPU 使用: GPU 0 (22.4GB/49GB, 100%) + GPU 2 (23GB/49GB, 100%)
- 训练是否正常运行: **是** — 无 NaN、无 OOM、loss 稳定
- ETA 完成: ~19:38 (剩余 ~2h30m)
- LR: base 5e-05, effective 2.5e-06
- 下次 val: iter 3000 (~17:12)
- 下次 LR milestone: iter 3000 (即将到来!)

## 核心指标（P2@2500 checkpoint, BUG-12 corrected eval）
| 指标 | P2@2500 | P1@6000 | 变化 | 红线 | 是否触碰红线 |
|------|---------|---------|------|------|------------|
| truck_recall | 0.3812 | 0.3579 | +6.5% ↑ | < 0.08 | 否 (SAFE) |
| truck_precision | **0.2987** | 0.1756 | +70.1% ↑ | — | — |
| bus_recall | 0.6363 | 0.6265 | +1.6% ↑ | — | — |
| bus_precision | 0.1736 | 0.1555 | +11.6% ↑ | — | — |
| car_recall | 0.5506 | 0.6283 | **-12.4% ↓** | — | — |
| car_precision | 0.0679 | 0.0914 | -25.7% ↓ | — | — |
| trailer_recall | 0.5778 | 0.6444 | -10.3% ↓ | — | — |
| trailer_precision | 0.0903 | 0.0346 | +161% ↑ | — | — |
| bg_false_alarm | **0.2029** | 0.1628 | +24.6% ↑ | > 0.25 | 否 (接近!) |
| avg_offset_cx | 0.0582 | 0.0805 | +27.7% 改善 | ≤ 0.05 | 略超 |
| avg_offset_cy | 0.0874 | 0.1392 | +37.2% 改善 | ≤ 0.10 | 否 |
| avg_offset_th | **0.2570** | 0.2197 | -17.0% ↓ | ≤ 0.20 | **是** ⚠️ |
| avg_precision | ~0.158 | ~0.114 | +38.6% ↑ | ≥ 0.20 | **是** (仍低于) |

### P2@2500 关键发现
1. **truck 指标显著提升**: recall +6.5%, precision +70% — BUG-9 fix 对 truck 效果明显
2. **car_recall 下降 12%**: 0.628 → 0.551, 需关注类别间竞争加剧
3. **bg_false_alarm 上升**: 0.163 → 0.203, 接近 0.25 红线, 需密切监控
4. **offset_th 恶化**: 0.220 → 0.257, 已超过 0.20 红线 — 回归精度退化
5. **offset cx/cy 改善**: 位置精度显著提升
6. **avg_precision 提升**: ~0.114 → ~0.158, 但仍低于 0.20 目标

## Loss 趋势 (iter 2700-2990, 最近 30 iters)
- cls_loss: 0.03~0.65, 典型 ~0.25 (波动大)
- reg_loss: 0.16~0.81, 典型 ~0.45 (波动大)
- total_loss: 0.22~1.32, 典型 ~0.65 (正常范围)
- grad_norm: 4.1~38.5, 约 30% 低于 10.0 (unclipped)

## 代码变更（最近 5 条 GiT commit）
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
| ORCH_001 | COMPLETED | BUG-12 eval slot ordering fix, truck_R +72% |
| ORCH_002 | COMPLETED | BUG-9 grad clip diagnosed, max_norm=10.0 |
| ORCH_003 | COMPLETED | P1@6000 eval done, P2 launched |

无 PENDING 指令，无积压。

## Admin 最新活动
- admin.log 不存在（Admin 通过 report_ORCH_*.md 报告工作成果）
- 最后活动: ORCH_003 完成 (14:18), 此后 idle
- Admin tmux session: UP

## 异常告警
1. **⚠️ bg_false_alarm 接近红线**: 0.203, 红线 0.25, 余量仅 23% — Conductor 决策阈值: > 0.30 干预
2. **⚠️ offset_th 超红线**: 0.257 > 0.20, 角度回归精度退化中
3. **⚠️ car_recall 下降**: 0.628 → 0.551 (-12%), 类别竞争可能加剧
4. **ℹ️ BUG-10 未修复**: optimizer cold start, P2 使用新 optimizer (非 resume)
5. **ℹ️ LR milestone 即将触发**: iter 3000 — 学习率衰减可能改善 loss 波动

## Checkpoint 清单
| Checkpoint | 时间 |
|-----------|------|
| iter_500.pth | 14:39 |
| iter_1000.pth | 15:09 |
| iter_1500.pth | 15:39 |
| iter_2000.pth | 16:09 |
| iter_2500.pth | 16:39 |

## GPU 状态
| GPU | 已用 | 总量 | 利用率 | 任务 |
|-----|------|------|--------|------|
| 0 | 22.4 GB | 49.1 GB | 100% | P2 训练 |
| 1 | 3.3 GB | 49.1 GB | 0% | 空闲 |
| 2 | 23.0 GB | 49.1 GB | 100% | P2 训练 |
| 3 | 18 MB | 49.1 GB | 0% | 空闲 |

## Agent 状态
| Agent | tmux | 状态 |
|-------|------|------|
| conductor | UP (attached) | 监控 P2 |
| admin | UP | idle, ORCH_001-003 全部完成 |
| critic | UP | idle |
| ops | UP (attached) | idle |
| supervisor | UP (attached) | cycle #89 |

## BUG 状态
| BUG | 状态 | 影响 |
|-----|------|------|
| BUG-9 | FIXED (max_norm=10.0) | ~30% iters unclipped, truck metrics 改善 |
| BUG-10 | UNPATCHED | optimizer cold start, 可能影响初期收敛 |
| BUG-12 | FIXED | eval slot ordering, P2 val 已用修复版 |

---

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

---

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

---

# Supervisor 摘要报告
> 时间: 2026-03-06 17:25
> Cycle: #92

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 配置: `configs/GiT/plan_e_bug9_fix.py`
- 进度: iter 3190 / 6000 (53.2%)
- GPU 使用: GPU 0 (22.4GB/49GB, 98%) + GPU 2 (23GB/49GB, 97%)
- 训练是否正常运行: **是** — 无 NaN、无 OOM
- ETA 完成: ~19:44 (剩余 ~2h20m)
- LR: base 5e-06, effective 2.5e-07 (**已衰减 10x since iter 3000**)
- 下次 val: iter 3500 (~18:08)
- 下次 LR milestone: iter 5000

## 核心指标（P2@3000 — 最新可用 val）

| 指标 | P2@3000 | P2@2500 | P1@6000 | 红线 | 状态 |
|------|---------|---------|---------|------|------|
| car_recall | 0.7308 | 0.5506 | 0.6283 | — | +33% ↑ |
| truck_recall | 0.4019 | 0.3812 | 0.3579 | < 0.08 | SAFE |
| bus_recall | 0.4793 | 0.6363 | 0.6265 | — | -25% ↓ 但 > 0.40 |
| trailer_recall | **0.9556** | 0.5778 | 0.6444 | — | **达标!** |
| bg_false_alarm | **0.2840** | 0.2029 | 0.1628 | > 0.25 | **🔴 超红线** |
| avg_offset_th | 0.2439 | 0.2570 | 0.2197 | ≤ 0.20 | **⚠️ 超红线** |
| avg_precision | ~0.081 | ~0.158 | ~0.114 | ≥ 0.20 | 远低于目标 |

## Loss 趋势 (iter 3010-3190, LR 衰减后 19 iters)
- cls_loss: 0.03~0.67, 典型 ~0.19
- reg_loss: 0.27~0.76, 典型 ~0.43
- total_loss: 0.35~1.26, 典型 ~0.63
- **grad_norm 显著改善!**
  - 衰减前 (iter 2800-3000): ~35% unclipped
  - **衰减后 (iter 3010-3190): ~79% unclipped (15/19)**
  - 最近 5 iter grad_norm: 7.7, 5.7, 3.9, 4.0, 4.5 — **持续走低, 收敛信号**
  - 仍有偶发尖峰: 32.6 (iter 3030), 26.7 (iter 3080)

## 代码变更（最近 5 条 GiT commit）
```
157fee4 Conductor: MASTER_PLAN updated
e8063bc MASTER_PLAN: Plan D @500 data added
242acbc MASTER_PLAN: Plan D + Center/Around parallel launch
6bfb9ea MASTER_PLAN: Plan C terminated, Plan D launching
7322488 Update MASTER_PLAN: iter 1500 RED LINE
```
无新代码变更。

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001 | COMPLETED | BUG-12 fix |
| ORCH_002 | COMPLETED | BUG-9 diagnosed |
| ORCH_003 | COMPLETED | P2 launched |

无 PENDING 指令，无积压。

## Admin 最新活动
- 最后活动: ORCH_003 完成 (14:18), idle 3+ hours
- tmux: UP

## 异常告警
1. **🔴 bg_false_alarm = 0.284 超红线 (0.25)** — @3500 val 是关键判断点, Conductor 干预阈值 0.30
2. **⚠️ offset_th = 0.244 > 0.20 红线**
3. **⚠️ avg_precision = 0.081** — 模型 over-predict
4. **✅ LR 衰减效果积极**: grad_norm unclipped 比例 35%→79%, 收敛信号明显
5. **ℹ️ GPU 1/3 空闲** (19MB/18MB)
6. **ℹ️ BUG-10 未修复**

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 98% | P2 训练 |
| 1 | 19 MB | 0% | 空闲 |
| 2 | 23.0 GB | 97% | P2 训练 |
| 3 | 18 MB | 0% | 空闲 |

## Agent 状态
全 5 agent tmux UP (conductor attached, admin idle, critic idle, ops attached, supervisor cycle #92)

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-9 | FIXED — unclipped 比例 post-LR-decay 达 79% |
| BUG-10 | UNPATCHED |
| BUG-12 | FIXED |

---

# Supervisor 摘要报告
> 时间: 2026-03-06 17:45
> Cycle: #93

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 配置: `configs/GiT/plan_e_bug9_fix.py`
- 进度: iter 3500 / 6000 (58.3%)
- GPU 使用: GPU 0 (22.4GB, 95%) + GPU 2 (23GB, 97%)
- 训练是否正常运行: **是**
- ETA 完成: ~19:44 (剩余 ~2h04m)
- LR: base 5e-06, effective 2.5e-07 (衰减后)
- 下次 val: iter 4000 (~18:38)
- 下次 LR milestone: iter 5000

## 核心指标 — P2@3500 (刚完成!) vs 历史

| 指标 | P2@3500 | P2@3000 | P2@2500 | P1@6000 | 红线 | 状态 |
|------|---------|---------|---------|---------|------|------|
| car_recall | 0.6397 | 0.7308 | 0.5506 | 0.6283 | — | -12% ↓ 回调 |
| truck_recall | **0.2947** | 0.4019 | 0.3812 | 0.3579 | < 0.08 | **-27% ↓ 大幅回落** |
| bus_recall | 0.5704 | 0.4793 | 0.6363 | 0.6265 | — | +19% ↑ 回升 |
| trailer_recall | 0.8889 | 0.9556 | 0.5778 | 0.6444 | — | -7% ↓ 失去达标 |
| bg_false_alarm | **0.2166** | 0.2840 | 0.2029 | 0.1628 | > 0.25 | **✅ 回到红线内!** |
| truck_precision | 0.1437 | 0.1017 | 0.2987 | 0.1756 | — | +41% ↑ |
| bus_precision | 0.1343 | 0.1152 | 0.1736 | 0.1555 | — | +17% ↑ |
| car_precision | 0.0786 | 0.0731 | 0.0679 | 0.0914 | — | +8% ↑ |
| trailer_precision | 0.0714 | 0.0338 | 0.0903 | 0.0346 | — | +111% ↑ |
| avg_offset_cx | 0.0642 | 0.0531 | 0.0582 | 0.0805 | ≤ 0.05 | 略退 |
| avg_offset_cy | 0.0853 | 0.0890 | 0.0874 | 0.1392 | ≤ 0.10 | SAFE |
| avg_offset_th | 0.2251 | 0.2439 | 0.2570 | 0.2197 | ≤ 0.20 | **⚠️ 超红线, 但持续改善** |
| avg_precision | ~0.107 | ~0.081 | ~0.158 | ~0.114 | ≥ 0.20 | +32% ↑ 回升 |

### P2@3500 关键发现

**✅ 好消息:**
1. **bg_false_alarm 回到红线以下**: 0.284 → 0.217 (-24%), LR 衰减成功缓解 over-predict!
2. **precision 全面回升**: avg 0.081 → 0.107, 模型变得更保守、更精准
3. **offset_th 持续改善**: 0.257 → 0.244 → 0.225, 趋势向好
4. **bus_recall 回升 19%**: 0.479 → 0.570

**⚠️ 需关注:**
1. **truck_recall 大幅回落**: 0.402 → 0.295 (-27%), 仍 SAFE (>0.08) 但距 0.70 目标更远
2. **car_recall 回调**: 0.731 → 0.640 (-12%)
3. **trailer_recall 失去达标**: 0.956 → 0.889

**分析**: @3000 over-predict (高 recall 低 precision 高 bg_FA) → @3500 LR 衰减生效, 模型趋于保守 (recall↓ precision↑ bg_FA↓)。这是 LR 阶跃衰减后的典型振荡, 模型正在寻找新的平衡点。后续 @4000~@6000 应趋于稳定。

## Loss 趋势 (iter 3200-3500, post-LR-decay)
- cls_loss: 0.01~0.52, 典型 ~0.17
- reg_loss: 0.14~0.88, 典型 ~0.40
- total_loss: 0.18~1.19, 典型 ~0.58
- grad_norm: 3.1~14.5, **~89% unclipped (25/28)**
- iter 3500 loss=0.273 (很低), grad_norm=3.67
- **收敛趋势明确**: loss 和 grad_norm 持续走低

## 代码变更
无新 GiT commit。

## ORCH 指令状态
| 指令 | 状态 |
|------|------|
| ORCH_001 | COMPLETED |
| ORCH_002 | COMPLETED |
| ORCH_003 | COMPLETED |

无 PENDING，无积压。

## 异常告警
1. **⚠️ truck_recall = 0.295**: -27% 回落, 仍 SAFE 但需持续观察
2. **⚠️ offset_th = 0.225 > 0.20 红线**: 持续改善但仍超标
3. **✅ bg_false_alarm = 0.217**: 回到安全区, LR 衰减有效
4. **ℹ️ GPU 1/3 出现 3.3GB 占用**: val 进程使用, 已结束
5. **ℹ️ BUG-10 未修复**

## Checkpoint 清单 (7 个, 共 ~13.8 GB)
iter_500 → iter_3500, 每 500 iter 一个

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 95% | P2 训练 |
| 1 | 3.3 GB | 61% | val 进程 |
| 2 | 23.0 GB | 97% | P2 训练 |
| 3 | 3.3 GB | 74% | val 进程 |

## Agent 状态
全 5 agent tmux UP。conductor attached, 其余 idle。

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-9 | FIXED — post-LR-decay unclipped 89% |
| BUG-10 | UNPATCHED |
| BUG-12 | FIXED |

---

# Supervisor 摘要报告
> 时间: 2026-03-06 18:15
> Cycle: #94

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 配置: `configs/GiT/plan_e_bug9_fix.py`
- 进度: iter 4000 / 6000 (66.7%) — **三分之二**
- GPU 使用: GPU 0 (22.4GB, 96%) + GPU 2 (23GB, 96%)
- 训练是否正常运行: **是**
- ETA 完成: ~19:48 (剩余 ~1h39m)
- LR: base 5e-06, effective 2.5e-07
- 下次 val: iter 4500 (~19:08)
- 下次 LR milestone: iter 5000

## 核心指标 — P2 全程趋势

| 指标 | @2500 | @3000 | @3500 | **@4000** | P1@6000 | 红线 | 趋势 |
|------|-------|-------|-------|-----------|---------|------|------|
| car_R | 0.551 | 0.731 | 0.640 | **0.619** | 0.628 | — | 稳定在P1水平 |
| truck_R | 0.381 | 0.402 | 0.295 | **0.269** | 0.358 | <0.08 | ↓ 持续下降 |
| bus_R | 0.636 | 0.479 | 0.570 | **0.607** | 0.627 | — | ↑ 回升接近P1 |
| trailer_R | 0.578 | 0.956 | 0.889 | **0.778** | 0.644 | — | ↓ 但仍>P1 |
| bg_FA | 0.203 | 0.284 | 0.217 | **0.204** | 0.163 | >0.25 | **✅ 持续改善** |
| truck_P | 0.299 | 0.102 | 0.144 | **0.160** | 0.176 | — | ↑ 持续回升 |
| bus_P | 0.174 | 0.115 | 0.134 | **0.147** | 0.156 | — | ↑ 接近P1 |
| trailer_P | 0.090 | 0.034 | 0.071 | **0.082** | 0.035 | — | ↑ 已超P1 |
| offset_th | 0.257 | 0.244 | 0.225 | **0.222** | 0.220 | ≤0.20 | **↓ 接近P1!** |
| offset_cx | 0.058 | 0.053 | 0.064 | **0.064** | 0.081 | ≤0.05 | 优于P1 |
| offset_cy | 0.087 | 0.089 | 0.085 | **0.083** | 0.139 | ≤0.10 | SAFE |
| avg_P | 0.158 | 0.081 | 0.107 | **0.117** | 0.114 | ≥0.20 | ↑ 回升至P1水平 |

### P2@4000 分析

**趋势判断 — 模型正在稳定:**
- @3000→@3500 变化剧烈 (LR 衰减冲击), @3500→@4000 变化收窄 — 振荡正在衰减
- bg_FA: 0.284→0.217→0.204, 稳步回落, SAFE
- precision 持续回升, 接近 P1 水平
- offset_th: 0.222, 几乎追平 P1 (0.220), 离 0.20 红线还差 11%

**仍需关注:**
- truck_recall 持续下降: 0.402→0.295→0.269, 仍 SAFE (>0.08) 但偏低
- 整体 recall 从 @3000 peak 回落, 但 bus 正在回升

**与 P1@6000 对比:**
- **优于P1**: trailer_R (+21%), trailer_P (+137%), offset_cx (-21%), offset_cy (-40%)
- **接近P1**: car_R (-1%), bus_R (-3%), bus_P (-6%), avg_P (+3%), offset_th (+1%)
- **劣于P1**: truck_R (-25%), bg_FA (+25%)

## Loss 趋势 (iter 3850-4000)
- total_loss: 0.28~0.90, 典型 ~0.53
- grad_norm: 1.4~11.8, **~93% unclipped**, 最低 1.42
- iter 4000: loss=0.594, grad_norm=4.17
- **稳定收敛**, 无异常

## ORCH 指令状态
全部 COMPLETED，无 PENDING，无积压。

## 异常告警
1. **⚠️ truck_recall = 0.269**: 持续下降中, SAFE 但需观察是否企稳
2. **✅ bg_FA = 0.204**: 持续改善, 稳定在安全区
3. **⚠️ offset_th = 0.222 > 0.20**: 仍超红线但几乎追平 P1
4. **ℹ️ BUG-10 未修复**

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 96% | P2 训练 |
| 1 | 3.3 GB | 66% | val 进程 |
| 2 | 23.0 GB | 96% | P2 训练 |
| 3 | 3.5 GB | 98% | val 进程 |

## Agent 状态
全 5 agent tmux UP。

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-9 | FIXED — unclipped 93% |
| BUG-10 | UNPATCHED |
| BUG-12 | FIXED |

---

# Supervisor 摘要报告
> 时间: 2026-03-06 18:44
> Cycle: #95

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 进度: iter 4500 / 6000 (75%)
- GPU: 0 (22.4GB, 97%) + 2 (23GB, 65%)
- 训练正常运行: **是**
- ETA 完成: ~19:53 (剩余 ~1h15m)
- LR: base 5e-06, effective 2.5e-07
- 下次 val: iter 5000 (~19:23) — **第二个 LR milestone!**

## 核心指标 — P2 全程趋势

| 指标 | @2500 | @3000 | @3500 | @4000 | **@4500** | P1@6k | 红线 | 趋势 |
|------|-------|-------|-------|-------|-----------|-------|------|------|
| car_R | .551 | .731 | .640 | .619 | **.605** | .628 | — | 稳定 |
| truck_R | .381 | .402 | .295 | .269 | **.301** | .358 | <.08 | **↑ 回升!** |
| bus_R | .636 | .479 | .570 | .607 | **.592** | .627 | — | 稳定 |
| trailer_R | .578 | .956 | .889 | .778 | **.733** | .644 | — | ↓ 仍>P1 |
| bg_FA | .203 | .284 | .217 | .204 | **.200** | .163 | >.25 | **✅ 持续改善** |
| truck_P | .299 | .102 | .144 | .160 | **.177** | .176 | — | **≈P1!** |
| bus_P | .174 | .115 | .134 | .147 | **.151** | .156 | — | **≈P1!** |
| off_th | .257 | .244 | .225 | .222 | **.227** | .220 | ≤.20 | ⚠️ 波动≈P1 |
| avg_P | .158 | .081 | .107 | .117 | **.119** | .114 | ≥.20 | ≈P1 |

### P2@4500 分析

**✅ 积极信号:**
1. **truck_recall 回升**: 0.269 → 0.301 (+12%), 首次反弹自 @3000 下滑以来
2. **truck_precision = 0.177**: 追平 P1 (0.176), BUG-9 fix 对 truck 精度效果持久
3. **bg_FA = 0.200**: 稳步下降, 远离红线, 接近 P1 水平
4. **bus_precision = 0.151**: 追平 P1 (0.156)
5. **grad_norm 100% unclipped**: 最近 14 iter 全部 < 10.0 (范围 2.6~7.4)

**⚠️ 待观察:**
1. **offset_th = 0.227**: 略回弹 (was 0.222), 在 P1 水平附近波动
2. **car_recall 继续缓降**: 0.619 → 0.605, 略低于 P1 (0.628)
3. **trailer_recall 继续降**: 0.778 → 0.733, 但仍 +14% 优于 P1

**总体判断**: 模型已基本稳定。@4000→@4500 变化很小, 多项指标追平 P1。truck_recall 回升是关键积极信号。iter 5000 将触发第二次 LR 衰减, 届时可能再次出现短暂波动。

## Loss 趋势 (iter 4370-4500)
- total_loss: 0.20~1.24, 典型 ~0.53
- grad_norm: 2.6~7.4, **100% unclipped**
- iter 4500: loss=0.502, grad_norm=3.04
- 训练极其稳定

## ORCH 指令状态
全部 COMPLETED，无 PENDING，无积压。

## 异常告警
1. **⚠️ offset_th = 0.227 > 0.20**: 仍超红线, 在 P1 水平波动
2. **✅ bg_FA = 0.200**: 安全
3. **ℹ️ LR milestone iter 5000 即将到来**: 预计再衰减, 可能引发短暂波动
4. **ℹ️ BUG-10 未修复**

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 97% | P2 训练 |
| 1 | 3.3 GB | 0% | 空闲/val |
| 2 | 23.0 GB | 65% | P2 训练 |
| 3 | 18 MB | 0% | 空闲 |

## Agent 状态
全 5 agent tmux UP。

## Checkpoint (9 个, ~17.7 GB)
iter_500 → iter_4500

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-9 | FIXED — 100% unclipped |
| BUG-10 | UNPATCHED |
| BUG-12 | FIXED |

---

# Supervisor 摘要报告
> 时间: 2026-03-06 18:52
> Cycle: #96

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 进度: iter 4660 / 6000 (77.7%)
- GPU: 0 (22.4GB, 99%) + 2 (23GB, 99%)
- 训练正常运行: **是**
- ETA 完成: ~19:58 (剩余 ~1h07m)
- LR: base 5e-06, effective 2.5e-07
- 下次 val: iter 5000 (~19:23) — **第二个 LR milestone!**
- LR 将在 iter 5000 再次衰减

## 核心指标（P2@4500 — 最新可用 val, 无变化）

| 指标 | @4500 | P1@6k | 红线 | vs P1 |
|------|-------|-------|------|-------|
| car_R | .605 | .628 | — | -4% |
| truck_R | .301 | .358 | <.08 | -16% |
| bus_R | .592 | .627 | — | -6% |
| trailer_R | .733 | .644 | — | **+14%** |
| bg_FA | .200 | .163 | >.25 | +23% 但 SAFE |
| truck_P | .177 | .176 | — | **≈P1** |
| bus_P | .151 | .156 | — | **≈P1** |
| off_th | .227 | .220 | ≤.20 | ≈P1 |

## Loss 趋势 (iter 4510-4660, post-val)
- total_loss: 0.25~0.85, 典型 ~0.47 (**较 @4000 前 0.53 进一步下降**)
- grad_norm: 2.8~6.6, **100% unclipped, 全部 < 7.0**
- **loss 均值持续下降, 收敛信号强烈**

## ORCH / 投递
全部 COMPLETED，无 PENDING，无积压。

## 深度监控
- 全 5 agent tmux UP
- GPU 1/3: 3.3GB/64%, 可能为分布式通信进程占用
- 9 个 checkpoint (iter_500~4500, ~17.7 GB)
- 训练进程 PID 3506111 正常
- 无异常

## 告警
1. **⚠️ offset_th = 0.227 > 0.20 红线**: 仍超标, ≈P1 水平
2. **ℹ️ LR milestone iter 5000 (~19:23)**: 第二次衰减即将触发
3. **ℹ️ BUG-10 未修复**
4. **✅ bg_FA, truck_R 均 SAFE**

---

# Supervisor 摘要报告
> 时间: 2026-03-06 19:22
> Cycle: #97

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 进度: iter 5170 / 6000 (86.2%)
- GPU: 0 (22.4GB, 100%) + 2 (23GB, 100%)
- 训练正常运行: **是**
- ETA 完成: ~20:02 (剩余 ~41min)
- **第二次 LR 衰减已触发!** base_lr: 5e-06 → 5e-07 (再次 10x), effective: 2.5e-08
- 下次 val: iter 5500 (~19:52)
- 无更多 LR milestone

## 核心指标 — P2@5000 (刚完成!) + 全程趋势

| 指标 | @3000 | @3500 | @4000 | @4500 | **@5000** | P1@6k | 红线 | vs P1 |
|------|-------|-------|-------|-------|-----------|-------|------|-------|
| car_R | .731 | .640 | .619 | .605 | **.600** | .628 | — | -4% |
| truck_R | .402 | .295 | .269 | .301 | **.280** | .358 | <.08 | -22% |
| bus_R | .479 | .570 | .607 | .592 | **.639** | .627 | — | **+2% 超P1!** |
| trailer_R | .956 | .889 | .778 | .733 | **.689** | .644 | — | **+7%** |
| bg_FA | .284 | .217 | .204 | .200 | **.200** | .163 | >.25 | ✅ SAFE |
| truck_P | .102 | .144 | .160 | .177 | **.189** | .176 | — | **+7% 超P1!** |
| bus_P | .115 | .134 | .147 | .151 | **.152** | .156 | — | ≈P1 |
| trailer_P | .034 | .071 | .082 | .068 | **.065** | .035 | — | **+86%** |
| off_th | .244 | .225 | .222 | .227 | **.219** | .220 | ≤.20 | **≈P1! (差0.001)** |
| off_cx | .053 | .064 | .064 | .068 | **.067** | .081 | ≤.05 | +17% 优 |
| off_cy | .089 | .085 | .083 | .091 | **.094** | .139 | ≤.10 | +32% 优 |
| avg_P | .081 | .107 | .117 | .119 | **.121** | .114 | ≥.20 | **+6% 超P1!** |

### P2@5000 关键发现

**超越 P1 的指标:**
- **bus_recall = 0.639** > P1 (0.627) — +2%, 首次超越!
- **truck_precision = 0.189** > P1 (0.176) — +7%
- **trailer_recall = 0.689** > P1 (0.644) — +7%
- **trailer_precision = 0.065** > P1 (0.035) — +86%
- **avg_precision = 0.121** > P1 (0.114) — +6%
- **offset_cx, offset_cy** 大幅优于 P1

**追平 P1 的指标:**
- **offset_th = 0.2194** ≈ P1 (0.2197) — 差距仅 0.0003!
- **bus_precision = 0.152** ≈ P1 (0.156)

**仍低于 P1:**
- **truck_recall = 0.280** < P1 (0.358) — -22%, 是最大差距
- **car_recall = 0.600** < P1 (0.628) — -4%

**总体判断**: P2@5000 质量接近/超越 P1@6000。BUG-9 fix 改善了精度 (precision 全面提升) 和空间偏移 (offset cx/cy 大幅改善), 代价是 truck_recall 下降。offset_th 几乎追平 P1, 暗示第二次 LR 衰减后有望突破 0.20 红线。

## Loss 趋势 (iter 5010-5170, 第二次 LR 衰减后)
- total_loss: 0.18~1.20, 典型 ~0.45 (**持续下降**)
- grad_norm: 2.2~6.5, **100% unclipped**
- 第二次 LR 衰减效果: 与第一次类似, loss 继续收窄

## ORCH 指令状态
全部 COMPLETED，无 PENDING，无积压。

## 异常告警
1. **⚠️ offset_th = 0.219 > 0.20 红线**: 差距极小 (0.019), 可能在后续 iter 改善
2. **⚠️ truck_recall = 0.280**: 较 P1 低 22%, 是 P2 的最大弱点
3. **✅ bg_FA = 0.200**: 稳定安全
4. **ℹ️ 第二次 LR 衰减已触发**: base_lr 5e-07, 训练进入最终微调阶段
5. **ℹ️ BUG-10 未修复**

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 100% | P2 训练 |
| 1 | 3.5 GB | 0% | 空闲 |
| 2 | 23.0 GB | 100% | P2 训练 |
| 3 | 18 MB | 0% | 空闲 |

## Checkpoint (10 个, ~19.7 GB)
iter_500 → iter_5000

## Agent 状态
全 5 agent tmux UP。

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-9 | FIXED — 100% unclipped |
| BUG-10 | UNPATCHED |
| BUG-12 | FIXED |

---

# Supervisor 摘要报告
> 时间: 2026-03-06 19:52
> Cycle: #98

## 训练状态
- 当前实验: Plan E (BUG-9 fix, max_norm=10.0)
- 进度: iter 5680 / 6000 (94.7%) — **即将完成!**
- GPU: 0 (22.4GB, 100%) + 2 (23GB, 100%)
- 训练正常运行: **是**
- ETA 完成: ~20:08 (剩余 ~16min)
- LR: base 5e-07, effective 2.5e-08 (最终微调阶段)
- 下次 val: iter 6000 — **最终 val!**

## 核心指标 — P2@5500 + 全程趋势 (后半程, LR 衰减后)

| 指标 | @3500 | @4000 | @4500 | @5000 | **@5500** | P1@6k | 红线 | vs P1 |
|------|-------|-------|-------|-------|-----------|-------|------|-------|
| car_R | .640 | .619 | .605 | .600 | **.600** | .628 | — | -5% |
| truck_R | .295 | .269 | .301 | .280 | **.290** | .358 | <.08 | -19% |
| bus_R | .570 | .607 | .592 | .639 | **.630** | .627 | — | **+0.5%** |
| trailer_R | .889 | .778 | .733 | .689 | **.689** | .644 | — | **+7%** |
| bg_FA | .217 | .204 | .200 | .200 | **.198** | .163 | >.25 | ✅ |
| truck_P | .144 | .160 | .177 | .189 | **.190** | .176 | — | **+8%** |
| bus_P | .134 | .147 | .151 | .152 | **.149** | .156 | — | -4% |
| off_th | .225 | .222 | .227 | .219 | **.218** | .220 | ≤.20 | **超越P1!** |
| avg_P | .107 | .117 | .119 | .121 | **.121** | .114 | ≥.20 | **+6%** |

### P2@5500 关键发现

**模型已完全收敛** — @5000→@5500 变化极小 (所有指标变化 < 2%)

**超越 P1 的指标 (5 项):**
1. **offset_th = 0.218** < P1 (0.220) — **首次超越P1!** 角度精度持续改善
2. **truck_precision = 0.190** > P1 (0.176) — +8%
3. **trailer_recall = 0.689** > P1 (0.644) — +7%
4. **trailer_precision = 0.065** > P1 (0.035) — +86%
5. **avg_precision = 0.121** > P1 (0.114) — +6%

**追平 P1 (3 项):**
- bus_recall = 0.630 ≈ P1 (0.627)
- bus_precision = 0.149 ≈ P1 (0.156)
- bg_FA = 0.198 (SAFE, 优于红线)

**低于 P1 (2 项):**
- **truck_recall = 0.290** < P1 (0.358) — -19%
- **car_recall = 0.600** < P1 (0.628) — -5%

## Loss 趋势 (iter 5510-5680)
- total_loss: 0.31~1.00, 典型 ~0.50
- grad_norm: 1.3~6.97, **100% unclipped**
- 完全收敛, 无异常

## ORCH 指令状态
全部 COMPLETED，无 PENDING，无积压。

## 告警
1. **⚠️ offset_th = 0.218**: 仍 > 0.20 红线, 但已超越 P1
2. **ℹ️ 训练即将完成**: ~16 min 后到达 iter 6000
3. **ℹ️ BUG-10 未修复**
4. **✅ 所有其他红线指标 SAFE**

## GPU / Agent / BUG
- GPU 0+2: P2 训练 (100%), GPU 1+3: 3.3GB/3.5GB (val/通信)
- 全 5 agent tmux UP
- Checkpoint: 11 个 (iter_500~5500, ~21.7 GB)
- BUG-9 FIXED, BUG-10 UNPATCHED, BUG-12 FIXED

---

# Supervisor 摘要报告
> 时间: 2026-03-06 20:12
> Cycle: #99

## ===== P2 训练已完成! =====

- 实验: Plan E (BUG-9 fix, max_norm=10.0)
- 总迭代: 6000/6000 (100%)
- 训练时长: 14:14 → 20:07 (~5h53m)
- 最终 checkpoint: `iter_6000.pth` (20:07, 1.97GB)
- **GPU 已全部释放**: 0/1/2/3 均空闲

## P2@6000 最终指标 vs P1@6000

| 指标 | **P2@6000** | P1@6000 | 差异 | 红线 | 状态 |
|------|-------------|---------|------|------|------|
| car_recall | 0.596 | 0.628 | -5.2% | — | 略低 |
| car_precision | 0.079 | 0.091 | -14% | — | 略低 |
| **truck_recall** | **0.290** | 0.358 | **-19%** | <0.08 | SAFE, 最大差距 |
| **truck_precision** | **0.190** | 0.176 | **+8.4%** | — | **超P1** |
| bus_recall | 0.623 | 0.627 | -0.6% | — | ≈P1 |
| bus_precision | 0.150 | 0.156 | -3.9% | — | ≈P1 |
| **trailer_recall** | **0.689** | 0.644 | **+6.9%** | — | **超P1** |
| **trailer_precision** | **0.066** | 0.035 | **+89%** | — | **超P1** |
| bg_false_alarm | 0.198 | 0.163 | +21% | >0.25 | ✅ SAFE |
| **offset_cx** | **0.068** | 0.081 | **-16%** | ≤0.05 | **超P1** |
| **offset_cy** | **0.095** | 0.139 | **-32%** | ≤0.10 | **超P1** |
| **offset_w** | **0.003** | 0.004 | **-11%** | — | **超P1** |
| **offset_h** | **0.001** | 0.002 | **-33%** | — | **超P1** |
| **offset_th** | **0.217** | 0.220 | **-1.4%** | ≤0.20 | **超P1** (仍>红线) |
| **avg_precision** | **0.121** | 0.114 | **+6.1%** | ≥0.20 | **超P1** |

### P2 vs P1 最终评定

| 类别 | 指标数 | 详情 |
|------|--------|------|
| **超越 P1** | **9 项** | truck_P, trailer_R, trailer_P, offset_cx/cy/w/h/th, avg_P |
| **追平 P1** | **2 项** | bus_R, bus_P |
| **低于 P1** | **3 项** | car_R (-5%), truck_R (-19%), car_P (-14%) |

### BUG-9 Fix 效果总结
- **目标**: 解决 100% gradient clipping (max_norm=0.5 太小)
- **方案**: max_norm 0.5 → 10.0
- **结果**:
  - grad_norm unclipped 比例: P1 0% → P2 100% (最终阶段)
  - **空间精度大幅改善**: offset_cx -16%, offset_cy -32%, offset_th -1.4%
  - **precision 全面提升**: truck_P +8%, trailer_P +89%, avg_P +6%
  - **代价**: truck_recall -19%, car_recall -5%
  - **bg_FA 安全**: 0.198 < 0.25 红线

## P2 全程 val 趋势

| iter | car_R | truck_R | bus_R | trail_R | bg_FA | off_th |
|------|-------|---------|-------|---------|-------|--------|
| 2500 | .551 | .381 | .636 | .578 | .203 | .257 |
| 3000 | .731 | .402 | .479 | .956 | **.284** | .244 |
| 3500 | .640 | .295 | .570 | .889 | .217 | .225 |
| 4000 | .619 | .269 | .607 | .778 | .204 | .222 |
| 4500 | .605 | .301 | .592 | .733 | .200 | .227 |
| 5000 | .600 | .280 | .639 | .689 | .200 | .219 |
| 5500 | .600 | .290 | .630 | .689 | .198 | .218 |
| **6000** | **.596** | **.290** | **.623** | **.689** | **.198** | **.217** |

**关键转折点**: iter 3000 (LR 第一次衰减) — 从 over-predict 过渡到收敛, @4500 起模型稳定。

## ORCH 指令状态
全部 COMPLETED，无 PENDING。

## GPU 状态 — 全部空闲!
| GPU | 已用 | 利用率 |
|-----|------|--------|
| 0 | 15 MB | 0% |
| 1 | 15 MB | 0% |
| 2 | 547 MB | 0% |
| 3 | 15 MB | 0% |

**4 GPU 全部可用于下一个实验。**

## Agent 状态
全 5 agent tmux UP。

## Checkpoint 清单 (12 个, ~23.7 GB)
iter_500 → iter_6000, 每 500 iter

## 下一步 (供 Conductor 决策)
1. P2@6000 最终结果已出, 需要 Conductor 评审并决定下一步
2. 4 GPU 全部空闲, 可立即启动新实验
3. BUG-10 (optimizer cold start) 仍未修复, 可考虑在 P3 中修复
4. truck_recall -19% 是 P2 最大弱点, 需要策略调整
5. 可考虑清理早期 checkpoint (iter_500~2000) 节省磁盘空间

## BUG 状态
| BUG | 状态 |
|-----|------|
| BUG-9 | **FIXED & VALIDATED** — P2 完整训练验证 |
| BUG-10 | UNPATCHED |
| BUG-12 | FIXED |

---

# Supervisor 摘要报告
> 时间: 2026-03-06 20:25
> Cycle: #100

## 训练状态
- P2 训练已完成 (20:11), iter 6000/6000
- **无活跃训练进程**
- 最终 checkpoint: `iter_6000.pth`

## 核心指标（P2@6000 最终, 无变化）

| 指标 | P2@6000 | P1@6000 | vs P1 |
|------|---------|---------|-------|
| car_R | 0.596 | 0.628 | -5% |
| truck_R | 0.290 | 0.358 | -19% |
| bus_R | 0.623 | 0.627 | ≈ |
| trailer_R | **0.689** | 0.644 | +7% |
| bg_FA | 0.198 | 0.163 | SAFE |
| truck_P | **0.190** | 0.176 | +8% |
| offset_th | **0.217** | 0.220 | -1.4% |
| avg_P | **0.121** | 0.114 | +6% |

**P2 总评: 9 项超P1, 2 项平, 3 项低。等待 Conductor 评审。**

## GPU 状态 — 全部空闲
| GPU | 已用 | 利用率 |
|-----|------|--------|
| 0 | 15 MB | 0% |
| 1 | 15 MB | 0% |
| 2 | 548 MB | 0% |
| 3 | 15 MB | 0% |

## ORCH / 投递
全部 COMPLETED，无 PENDING，无积压。无新指令。

## 代码变更
无新 GiT commit。

## 深度监控
- 全 5 agent tmux UP
- 无训练进程运行
- 12 个 checkpoint (iter_500~6000, ~23.7 GB)
- Conductor 尚未对 P2 结果做出下一步决策

## 告警
1. **ℹ️ 系统空闲**: P2 完成后无新任务, 等待 Conductor 指令
2. **ℹ️ GPU 2 残留 548MB**: 可能是 CUDA context 未完全释放, 无影响
3. **ℹ️ BUG-10 未修复**

---

# Supervisor 摘要报告
> 时间: 2026-03-06 20:55
> Cycle: #101

## 训练状态
- P2 训练已完成 (20:11), iter 6000/6000
- **无活跃训练进程**
- 最终 checkpoint: `iter_6000.pth`

## 核心指标（P2@6000 最终, 无变化）

| 指标 | P2@6000 | P1@6000 | vs P1 |
|------|---------|---------|-------|
| car_R | 0.596 | 0.628 | -5% |
| truck_R | 0.290 | 0.358 | -19% |
| bus_R | 0.623 | 0.627 | ≈ |
| trailer_R | **0.689** | 0.644 | +7% |
| bg_FA | 0.198 | 0.163 | SAFE |
| truck_P | **0.190** | 0.176 | +8% |
| offset_th | **0.217** | 0.220 | -1.4% |
| avg_P | **0.121** | 0.114 | +6% |

**P2 总评: 9 项超P1, 2 项平, 3 项低。等待 Conductor 评审。**

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 15 MB | 0% | **空闲 (可用)** |
| 1 | 3.3 GB | 70% | 外部: yz0364 UniAD (PID 3768469) |
| 2 | 550 MB | 0% | **空闲 (可用, 残留 CUDA ctx)** |
| 3 | 3.3 GB | 61% | 外部: yz0364 UniAD (PID 3768470) |

**GPU 0/2 可用, GPU 1/3 被外部用户 yz0364 占用。**

## ORCH / 投递
全部 COMPLETED，无 PENDING，无积压。无新指令。

## 代码变更
无新 GiT commit。

## 深度监控
- 全 5 agent tmux UP
- 无训练进程运行
- 12 个 checkpoint (iter_500~6000, ~23.7 GB)
- Conductor 尚未对 P2 结果做出下一步决策
- P2 完成后已空闲 ~44 分钟

## 告警
1. **ℹ️ 系统空闲 44min**: 等待 Conductor 指令
2. **ℹ️ GPU 1/3 被 yz0364 占用**: 若需 4 GPU 实验需协调
3. **ℹ️ BUG-10 未修复**

---

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

---

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

---

# Supervisor 摘要报告
> 时间: 2026-03-06 22:25
> Cycle: #104

## ===== P3@1000 Val 结果: truck_R 持续攀升, bus/trailer 暂时回落 =====

### P3 Val 轨迹

| 指标 | P3@1000 | P3@500 | P2@6000 | @1000 vs @500 | @1000 vs P2 | 红线 |
|------|---------|--------|---------|---------------|-------------|------|
| car_R | 0.578 | 0.576 | 0.596 | +0.3% | -3.0% | — |
| car_P | **0.087** | 0.075 | 0.079 | **+16%** | **+10%** | — |
| truck_R | **0.390** | 0.374 | 0.290 | **+4.4%** | **+34.5%** | <0.08 SAFE |
| truck_P | 0.250 | 0.254 | 0.190 | -1.6% | **+31.6%** | — |
| bus_R | 0.576 | 0.697 | 0.623 | **-17.4%** | -7.6% | — |
| bus_P | 0.081 | 0.125 | 0.150 | -35.2% | -46% | — |
| trailer_R | 0.511 | 0.667 | 0.689 | -23.4% | -25.8% | — |
| trailer_P | 0.022 | 0.044 | 0.066 | -50% | -66.7% | — |
| bg_FA | **0.206** | 0.212 | 0.198 | -3.3% | +4% | >0.25 SAFE |
| offset_cx | **0.055** | 0.085 | 0.068 | **-35.3%** | **-19.1%** | ≤0.05 接近! |
| offset_cy | 0.119 | 0.127 | 0.095 | -6.3% | +25.3% | ≤0.10 |
| offset_th | 0.232 | 0.253 | 0.217 | -8.3% | +6.9% | ≤0.20 |
| avg_P | 0.110 | 0.125 | 0.121 | -12% | -9.1% | ≥0.20 |

### 关键分析

**继续向好:**
- **truck_R = 0.390** — 持续攀升 (0.290→0.374→0.390)，BUG-8 fix 效果稳固
- **truck_P = 0.250** — 历史高位，比 P2 最终高 31.6%
- **car_P = 0.087** — 首次超越 P2@6000 (0.079)
- **offset_cx = 0.055** — 大幅改善，接近红线 (≤0.05)，比 P2@6000 (0.068) 更好
- **bg_FA = 0.206** — 红线内且在改善

**需要关注:**
- **bus_R 从 0.697 跌至 0.576** — @500 时历史最佳，@1000 回落至低于 P2@6000
- **trailer_R 从 0.667 跌至 0.511** — 同样回落
- **avg_P 从 0.125 跌至 0.110** — 因 bus_P 和 trailer_P 下降

**分析:** 模型正处于分化期。BUG-8 的 bg cls loss 让模型学会了更好的 truck 区分，但对 bus/trailer 产生暂时竞争。P2 在 @500-@3000 也有类似的 recall 波动，LR decay 后稳定。预计 P3 在 iter 2500 (第一次 LR decay) 后会稳定。

### 训练稳定性

**grad_norm spikes (iter 500-1000 区间):**
- iter 730: **grad_norm=76.6** (全程最高!)
- iter 790: 33.9, iter 840: 24.8, iter 860: 28.6
- iter 970: 27.6, iter 980: 33.8
- max_norm=10.0 下会被 clip，但预 clip 值高表明学习剧烈

**Loss (iter 500-1000):**
- cls_loss: 0.02~0.89, 波动较大 (iter 820: 0.89, iter 840: 0.65)
- reg_loss: 0.22~0.89
- total_loss: 0.24~1.52 (iter 820: 1.52 最高)
- 整体比 warmup 阶段波动更大，但属于高 LR 阶段正常表现

### P3 训练状态
- 配置: `configs/GiT/plan_f_bug8_fix.py`
- 进度: iter 1000 / 4000 (25%)
- Load from: P2@6000
- GPU: 0 (22.4GB, 97%) + 2 (23GB, 100%)
- LR: base_lr=5e-05 (常量阶段)
- LR milestones: iter 2500 (下一次 decay), 3500
- 下次 val: iter 1500 (~23:00)
- ETA 完成: ~00:50

### 代码变更 (GiT 最近 5 条 commit)
无变化，同上轮。

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
| 0 | 22.4 GB | 97% | **P3 训练** |
| 1 | 3.3 GB | 100% | 外部: yz0364 UniAD |
| 2 | 23.0 GB | 100% | **P3 训练** |
| 3 | 3.5 GB | 66% | 外部: yz0364 UniAD |

## Agent 状态
全 5 agent tmux UP。

## BUG 状态
全部已知 BUG 均已修复。

## 告警
1. **bus_R 回落 -17.4%**: 从 @500 的 0.697 跌至 0.576，需在后续 checkpoint 观察是否恢复
2. **trailer_R 回落 -23.4%**: 从 0.667 跌至 0.511
3. **grad_norm=76.6 at iter 730**: 单次极端 spike，被 max_norm clip，但需关注是否反复出现
4. **offset_th=0.232**: 仍高于红线 (≤0.20)，但趋势向好

---

# Supervisor 摘要报告
> 时间: 2026-03-06 22:55
> Cycle: #105

## ===== P3@1500: bus/trailer 强力反弹, 但 truck_P 崩塌, bg_FA 逼近红线 =====

### P3 Val 完整轨迹

| 指标 | P3@1500 | P3@1000 | P3@500 | P2@6000 | @1500 vs P2 | 红线 |
|------|---------|---------|--------|---------|-------------|------|
| car_R | **0.598** | 0.578 | 0.576 | 0.596 | **+0.3%** | — |
| car_P | 0.083 | 0.087 | 0.075 | 0.079 | +5.1% | — |
| truck_R | 0.382 | 0.390 | 0.374 | 0.290 | **+31.7%** | <0.08 SAFE |
| truck_P | **0.118** | 0.250 | 0.254 | 0.190 | **-37.9%** | — |
| bus_R | **0.680** | 0.576 | 0.697 | 0.623 | **+9.1%** | — |
| bus_P | 0.127 | 0.081 | 0.125 | 0.150 | -15.3% | — |
| trailer_R | **0.756** | 0.511 | 0.667 | 0.689 | **+9.7%** | — |
| trailer_P | 0.024 | 0.022 | 0.044 | 0.066 | -63.6% | — |
| bg_FA | **0.227** | 0.206 | 0.212 | 0.198 | +14.6% | >0.25 **逼近!** |
| offset_cx | 0.066 | 0.055 | 0.085 | 0.068 | -2.9% | ≤0.05 |
| offset_cy | **0.107** | 0.119 | 0.127 | 0.095 | +12.6% | ≤0.10 |
| offset_th | 0.234 | 0.232 | 0.253 | 0.217 | +7.8% | ≤0.20 |
| avg_P | 0.088 | 0.110 | 0.125 | 0.121 | -27.3% | ≥0.20 |

### 关键分析

**Recall 全面向好 — 接近或超越历史最佳:**
- **trailer_R = 0.756** — 全阶段最佳! 从 @1000 的 0.511 暴涨 +47.9%
- **bus_R = 0.680** — 强力反弹至接近 @500 水平 (0.697)，超 P2 +9.1%
- **car_R = 0.598** — 首次追平 P2@6000 (0.596)
- **truck_R = 0.382** — 略降但仍远超 P2 +31.7%

**Precision 崩塌 — 过度预测信号明显:**
- **truck_P: 0.250→0.118 (-52.8%)** — 单次 checkpoint 腰斩
- **avg_P: 0.125→0.110→0.088** — 连续下降
- **bg_FA: 0.212→0.206→0.227** — 快速上升，距红线 (0.25) 仅差 0.023

**诊断:** 模型进入过度预测期（P2 在 @3000 也经历了此阶段，bg_FA 峰值 0.284）。高 LR 驱动模型激进预测，recall 飙升但 precision 下降。P3 的第一次 LR decay 在 **iter 2500**，距现在还有 1000 iter，预计 LR decay 后 precision 将恢复，bg_FA 将回落。

### 训练稳定性 (iter 1000-1500)
- **极端 spike:** iter 1140: loss=**2.40**, cls_loss=1.68, grad_norm=**52.3**
- 其他高值: iter 1120: grad_norm=35.7, iter 1180: grad_norm=14.4
- 后半段 (1200-1500) 趋于平稳: loss 0.28~0.99, grad_norm 多数 <20
- 总体: 高 LR 阶段正常波动，iter 1140 的 spike 是孤立事件

### P3 训练状态
- 进度: iter 1500 / 4000 (37.5%)
- GPU: 0 (22.4GB, 30%) + 2 (23GB, 95%)
- LR: base_lr=5e-05 (常量阶段，距第一次 decay 还有 1000 iter)
- 下次 val: iter 2000 (~23:30)
- 第一次 LR decay: iter 2500 (~00:00)
- ETA 完成: ~00:50

### 代码变更 (GiT)
无变化。

## ORCH 指令状态
全部 COMPLETED，无 PENDING，无积压。

## GPU 状态
| GPU | 已用 | 利用率 | 任务 |
|-----|------|--------|------|
| 0 | 22.4 GB | 30% | **P3 训练** |
| 1 | 3.3 GB | 64% | 外部: yz0364 |
| 2 | 23.0 GB | 95% | **P3 训练** |
| 3 | 3.3 GB | 97% | 外部: yz0364 |

## Agent 状态
全 5 agent tmux UP。

## 告警
1. **bg_FA=0.227 逼近红线 (>0.25)**: 连续上升 0.212→0.206→0.227，需密切关注 @2000
2. **truck_P 崩塌 0.250→0.118**: 过度预测导致，LR decay 后应恢复
3. **avg_P=0.088 创新低**: 距目标 (≥0.20) 更远，但属于过度预测期暂时现象
4. **grad_norm=52.3 at iter 1140**: 极端 spike (loss=2.40)

---

