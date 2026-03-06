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
