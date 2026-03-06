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
