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

