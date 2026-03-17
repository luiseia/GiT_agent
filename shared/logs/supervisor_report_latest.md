# Supervisor 摘要报告
> 时间: 2026-03-17 00:17:22

## 训练状态 — slot0_marker_only
- **进度**: iter **300/40000** (0.75%)
- **GPU**: GPU 2 (30449 MiB, 100%)
- **ETA**: ~21h
- **Work dir**: `/home/UNT/yz0370/projects/GiT/work_dirs/full_nuscenes_large_v1_slot0_marker_only`

### Loss 趋势
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 10 | 0.552 | 0.552 | 0.000 | 28.93 |
| 30 | 0.443 | 0.443 | 0.000 | 26.83 |
| 100 | ~0.05 | ~0.05 | 0.000 | ~1.0 |
| 210 | 0.017 | 0.017 | 0.000 | 0.11 |
| 250 | 0.0004 | 0.0004 | 0.000 | 0.05 |
| 300 | **0.0003** | **0.0003** | 0.000 | **0.03** |

## 🚨 训练质量告警
- [RED] loss @300 = 0.0003, grad_norm = 0.03 — 与 ORCH_055/059 的 trivial solution 模式一致
- [RED] reg_loss = 0 全程 — marker_only 设计 or 无正预测?
- [YELLOW] 需确认: slot0_marker_only 是否预期如此快收敛，还是又陷入 all-bg collapse
- [YELLOW] /mnt/SSD **0 bytes free**, /home 45GB

## GPU 状态
| GPU | 显存 | 用户 |
|-----|------|------|
| 0 | 1730 MiB | yl0826 |
| 1 | 1854 MiB | yl0826 |
| 2 | **30449 MiB** | **yz0370 训练** |
| 3 | 1874 MiB | yl0826 |

## 0 PENDING | Agent 全部 ✅ UP
