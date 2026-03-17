# Supervisor 摘要报告
> 时间: 2026-03-17 02:00:35

## 训练状态 — 新全量训练 plan_full_nuscenes_large_v1_imgabs0
- **Config**: `plan_full_nuscenes_large_v1_imgabs0`
- **进度**: iter **480/40000** (1.2%), ETA ~1d 21h
- **GPU**: 0,1 (各 34480 MiB, 100%), 2-GPU DDP
- **Work dir**: `/home/UNT/yz0370/projects/GiT/work_dirs/plan_full_nuscenes_large_v1_imgabs0`
- **memory**: 28877 MiB

### Loss 趋势
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 440 | 12.82 | 10.54 | 2.28 | 56.2 |
| 450 | 0.90 | 0.65 | 0.26 | 118.4 |
| 460 | 0.010 | 0.010 | 0.000 | 36.0 |
| 470 | 0.009 | 0.009 | 0.000 | 19.2 |
| 480 | 0.012 | 0.012 | 0.000 | 0.5 |

**观察**: 有 reg_loss spike (iter440: 2.28) 说明模型偶尔产出正预测。但 reg 大部分时间=0。与之前 ORCH_055-059 模式类似。

## 已完成的短期实验
| 实验 | 最终 iter | 最终 loss |
|------|-----------|-----------|
| slot0_marker_only | 1010 (磁盘崩溃) | 0.001 |
| imgabs0_500 | 500 | ~0.001 |
| clip30_500 | 500 | 0.023 |
| clip30_retry400 | 400 | 0.018 |

## 磁盘
| /home | **100%** | **22 GB** | /mnt/SSD | **100%** | **0** |

## GPU 状态
| GPU | 显存 | 利用率 | 用途 |
|-----|------|--------|------|
| 0 | **34480 MiB** | **100%** | imgabs0 训练 |
| 1 | **34480 MiB** | **100%** | imgabs0 训练 |
| 2 | 218 MiB | 0% | idle |
| 3 | 15 MiB | 0% | idle |

## 🚨 训练质量告警
- [YELLOW] loss 大部分时间 <0.02 但有间歇 spike 到 12.8 — 模式与之前类似
- [YELLOW] /home 22GB, 训练持续写入, 需监控

## 0 PENDING | 8 tmux sessions UP | Conductor idle
