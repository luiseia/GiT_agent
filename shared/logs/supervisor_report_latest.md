# Supervisor 摘要报告
> 时间: 2026-03-08 17:42
> Cycle: #170

## ===== Full nuScenes iter 610/40000 训练正常 | 首次 val @2000 ~20:10 =====

---

### ORCH_024: Full nuScenes 训练进度

| 指标 | 值 |
|------|-----|
| 进度 | iter **610/40000** (1.5%) |
| 速度 | ~6.3-6.5 s/iter (稳定) |
| 显存 | 28.8 GB/GPU (稳定) |
| LR | 7.6e-07 (warmup 中, 目标 ~2.5e-05 @2000, 当前仅 3%) |
| Loss @600 | 5.84 (cls=3.00, reg=2.84) |
| ETA | ~3/11 14:30 |

> 训练完全正常. Loss 在 4-8 波动, 偶有全 bg 批次 (loss≈0.5, reg=0), 属正常.
> **修正: val_interval=2000, 首次 val 在 @2000 (非 @500)**

---

### 下一里程碑

| 事件 | iter | ETA |
|------|------|-----|
| warmup 结束 | 2000 | ~20:08 |
| **首次 val** | **2000** | **~20:13** |
| @4000 val | 4000 | 3/9 ~00:50 |
| 第一次 LR decay | 17000 | 3/9 ~22:00 |
| 训练结束 | 40000 | ~3/11 14:30 |

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-023 | COMPLETED | Mini 阶段 |
| **ORCH_024** | **IN PROGRESS** | Full nuScenes (610/40000), 训练正常 |

无新 ORCH 指令.

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 36.5 GB | 100% | Full nuScenes |
| 1 | 36.4 GB | 100% | Full nuScenes |
| 2 | 37.0 GB | 100% | Full nuScenes |
| 3 | 36.5 GB | 100% | Full nuScenes |

## 告警
1. **[NORMAL] 训练稳定**: loss/速度/显存均正常
2. **[CORRECTION] 首次 val @2000**: val_interval=2000, 非 @500. ETA ~20:13
