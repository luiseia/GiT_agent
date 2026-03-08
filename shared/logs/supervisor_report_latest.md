# Supervisor 摘要报告
> 时间: 2026-03-08 18:12
> Cycle: #171

## ===== Full nuScenes iter 890/40000 训练正常 | 首次 val @2000 ETA ~20:10 =====

---

### ORCH_024: Full nuScenes 训练进度

| 指标 | 值 |
|------|-----|
| 进度 | iter **890/40000** (2.2%) |
| 速度 | ~6.3-6.5 s/iter (稳定) |
| 显存 | 28849 MB/GPU (恒定) |
| LR | 1.11e-06 (warmup 中, 目标 ~2.5e-05, 当前约 4.5%) |
| Loss @890 | 5.92 (cls=3.92, reg=1.99) |
| ETA | ~3/11 14:30 |

> 训练完全正常. Loss 在 3.5-8.5 波动, 偶有纯 bg 批次 (loss<1, reg=0), 属正常.
> grad_norm 偶有尖峰 (132 @790), 总体 20-80, 不影响训练.

---

### 下一里程碑

| 事件 | iter | ETA |
|------|------|-----|
| warmup 结束 | 2000 | ~20:08 |
| **首次 val** | **2000** | **~20:10** |
| @4000 val | 4000 | 3/9 ~00:50 |
| 第一次 LR decay | 17000 | 3/9 ~22:00 |
| 训练结束 | 40000 | ~3/11 14:30 |

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-023 | COMPLETED | Mini 阶段 |
| **ORCH_024** | **IN PROGRESS** | Full nuScenes (890/40000), 训练正常 |

无新 ORCH 指令.

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 36.5 GB | 100% | Full nuScenes |
| 1 | 36.4 GB | 100% | Full nuScenes |
| 2 | 37.0 GB | 100% | Full nuScenes |
| 3 | 36.5 GB | 100% | Full nuScenes |

## 告警
1. **[NORMAL] 训练稳定**: loss/速度/显存/LR 均正常, warmup 按预期进行
2. **[INFO] 首次 val @2000 ETA ~20:10**: 约 2 小时后, warmup 结束 + 首次 eval
