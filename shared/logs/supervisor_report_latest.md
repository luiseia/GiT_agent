# Supervisor 摘要报告
> 时间: 2026-03-08 18:40
> Cycle: #172

## ===== Full nuScenes iter 1160/40000 训练正常 | 首次 val @2000 ETA ~20:10 =====

---

### ORCH_024: Full nuScenes 训练进度

| 指标 | 值 |
|------|-----|
| 进度 | iter **1160/40000** (2.9%) |
| 速度 | ~6.27-6.54 s/iter (稳定) |
| 显存 | 28849 MB/GPU (恒定) |
| LR | 1.45e-06 (warmup 中, 目标 ~2.5e-05, 当前约 5.8%) |
| Loss @1160 | 5.54 (cls=3.43, reg=2.10) |
| ETA | ~3/11 14:30 |

> 训练完全正常. 已过 iter 1000 里程碑.
> Loss 趋势略有下降 (近期 2.3-6.3 vs 早期 3.5-8.5), warmup 中正常.
> 纯 bg batch 仍偶现 (iter 1050: loss=0.41, iter 1130: loss=0.53), 正常.

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
| **ORCH_024** | **IN PROGRESS** | Full nuScenes (1160/40000), 训练正常 |

无新 ORCH 指令.

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 36.5 GB | 100% | Full nuScenes |
| 1 | 36.4 GB | 100% | Full nuScenes |
| 2 | 37.0 GB | 100% | Full nuScenes |
| 3 | 36.5 GB | 100% | Full nuScenes |

## 告警
1. **[NORMAL] 训练稳定**: 已过 iter 1000, loss/速度/显存/LR 均正常
2. **[INFO] 首次 val @2000 ETA ~20:10**: 约 90 分钟后, warmup 结束 + 首次 eval
