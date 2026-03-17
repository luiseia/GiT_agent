# Supervisor 摘要报告
> 时间: 2026-03-17 00:26:36

## 训练状态 — 3 个 slot0_marker_only 变体同时运行

### 1. slot0_marker_only (GPU 2)
- iter **560/40000**, ETA ~22h
- loss: 0.0006, grad_norm: 0.06
- 🚨 loss @iter200 已降至 0.0003, 可能 trivial solution

### 2. slot0_marker_only_imgabs0_500 (GPU 3?)
- iter **80/500**, ETA ~16min
- loss: 0.022, grad_norm: 1.08
- 短期实验 (max 500 iter)

### 3. slot0_marker_only_imgabs0_clip30_500 (刚启动)
- 初始化中

### 4. slot0_marker_only_imgabs0_smoke (已完成)
- 1 iter 烟雾测试, loss=0.298

## ⚠️ /home 磁盘快速下降
| /mnt/SSD | **100%** | **0 bytes** | /home | **99%** | **39 GB** ← (从 45GB 降了 6GB) |

3 个训练同时写 /home，消耗速率 ~6GB/20min。**预计 /home 将在数小时内耗尽。**

## 🚨 训练质量告警
- [RED] 主训练 loss=0.0006 @iter560, grad_norm<0.1 — trivial solution 风险
- [RED] /home 磁盘快速消耗中
- [YELLOW] 需确认 CEO 是否在手动操作这些实验

## GPU 状态
| GPU | 显存 | 利用率 | 用途 |
|-----|------|--------|------|
| 0 | 5664 MiB | 21% | yl0826 + ? |
| 1 | 1854 MiB | 20% | yl0826 |
| 2 | **30303 MiB** | **100%** | slot0_marker_only |
| 3 | **30100 MiB** | **100%** | imgabs0_500 |

## 0 PENDING | Agent 全部 ✅ UP | Conductor idle #38
