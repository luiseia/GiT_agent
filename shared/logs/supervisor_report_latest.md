# Supervisor 摘要报告
> 时间: 2026-03-12 18:18:00
> Cycle #276

## 训练状态 — ORCH_035 (multilayer_v4, label pipeline 大修, resume from 034@4000)
- 进度: iter **4210/40000** (10.5%)
- Resume: ✅ 从 `iter_4000.pth` 成功加载, iter 4001 开始
- LR: 2.5e-6 (稳定)
- ETA: ~2d 15h 45min
- GPU: 0-3 各 ~39.5 GB, 100% ✅
- 磁盘: /mnt/SSD 95% (194GB free), /home 99% (69GB free) ⚠️
- ORCH_035 状态: COMPLETED (Admin 已执行)

## ORCH_035 变更概要
Label Pipeline 5 项大修:
1. BUG-19v3 z-convention fix (box BOTTOM vs center)
2. Convex hull 替代 AABB
3. Sutherland-Hodgman hull-based IoF/IoB
4. filter_invisible=False
5. vis+cell_count 组合过滤 (vis<10% AND cells<6)

## Loss 趋势 (iter 4010-4210, 新标签)
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 4010 | 5.55 | 3.75 | 1.80 | 19.3 |
| 4050 | 3.76 | 1.56 | 2.20 | 24.1 |
| 4100 | 4.81 | 2.76 | 2.05 | 14.8 |
| 4150 | 3.30 | 1.34 | 1.96 | 14.7 |
| 4200 | 6.24 | 4.12 | 2.12 | 19.6 |
| 4210 | 5.83 | 3.57 | 2.26 | 42.8 |

### 分析
1. **Resume 成功** — 从 ORCH_034@4000 继续, 无 unexpected keys 问题
2. **Loss 正常** — 均值 ~5.0, 比 ORCH_034 同位置略高 (预期: 标签变了, 模型需 re-adapt)
3. **reg 均值 ~2.1** — 高于 ORCH_034 的 ~1.7 (新标签覆盖更准确, reg target 更有意义)
4. **零 reg=0** — 21 iter 全部 reg>0 ✅
5. **VRAM 30.6 GB** (mmengine) / ~39.5 GB (nvidia-smi, 含 DDP workers)
6. 有 2 个 loss spike @4080=7.66, @4160=7.70 — 但立即恢复, 正常

## 异常告警
- ⚠️ /home 磁盘 99% (69GB free) — 需关注
- 训练无异常

## ORCH 投递
- 0 个 PENDING
