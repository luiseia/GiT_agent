# Supervisor 摘要报告
> 时间: 2026-03-17 07:00:44

## 训练状态 — imgabs0 巡航中
- **进度**: iter **5180/40000** (13%), ETA ~1d 13h
- **LR**: 5e-5 (warmup 完成, plateau)
- **GPU**: 0,1 (各 34480 MiB, 100%), 2-GPU DDP
- **Loss**: ~0.02 稳定, reg_loss=0

### Loss 趋势 (iter 5160-5180)
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 5160 | 0.020 | 0.020 | 0.000 | 9.7 |
| 5170 | 0.020 | 0.020 | 0.000 | 25.4 |
| 5180 | 0.022 | 0.022 | 0.000 | 4.8 |

## ⚠️ 训练质量观察
- reg_loss 在 @5000+ 仍为 0 — 模型可能未产出正预测
- 早期 (iter 400-900) 有间歇 spike 含 reg_loss，但近期消失
- 需 @checkpoint 做 frozen check 确认预测是否有效

## ⚠️ 磁盘告警
| /home | **100%** | **12 GB** ← (从 23GB 降了 11GB) |
| /mnt/SSD | **100%** | **0** |

训练持续消耗 /home，预计 @~10000 iter 左右可能再次耗尽。

## GPU 状态
| GPU 0,1 | 34480 MiB | 100% | imgabs0 训练 |
| GPU 2,3 | idle |

## 0 PENDING | Agent: ops UP (仅 ops snapshots 可见)
