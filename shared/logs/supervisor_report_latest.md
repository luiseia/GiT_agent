# Supervisor 摘要报告
> 时间: 2026-03-17 00:30:38

## 🚨🚨 磁盘告警 — /home 急速下降！
| /mnt/SSD | **100%** | **0 bytes** |
| /home | **100%** | **33 GB** ← (20min内从45GB降了12GB!) |

3 个训练同时写 /home，消耗速率 ~36GB/h。**预计 ~1h 内 /home 将耗尽！**

## 训练状态 — 3 GPU 占满

### 1. slot0_marker_only (GPU 2, 28591 MiB)
- iter **660/40000**, loss: 0.003, reg=0

### 2. imgabs0_500 (GPU 3, 28388 MiB)
- iter **180/500**, loss: 0.0008, ETA ~12min

### 3. imgabs0_clip30_500 (GPU 0, 28388 MiB)
- 刚保存 iter 100 checkpoint

## 🚨 训练质量告警
- [RED] /home 100% 急速消耗 — ~1h 内可能耗尽导致训练崩溃
- [RED] 主训练 loss=0.003 @iter660 — trivial solution 风险
- [RED] 3 个训练同时写 /home 无限制

## GPU 状态
| GPU | 显存 | 利用率 | 用途 |
|-----|------|--------|------|
| 0 | **28388 MiB** | 8% | clip30_500 |
| 1 | 15 MiB | 0% | idle |
| 2 | **28591 MiB** | 99% | slot0_marker_only |
| 3 | **28388 MiB** | 99% | imgabs0_500 |

## 0 PENDING | Agent ✅ UP | Conductor idle #39
