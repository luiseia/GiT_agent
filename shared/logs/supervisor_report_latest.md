# Supervisor 摘要报告
> 时间: 2026-03-17 00:08:07

## ⚡ 新训练已启动！
- **Config**: `plan_full_nuscenes_large_v1_slot0_marker_only.py`
- **Work dir**: `/home/UNT/yz0370/projects/GiT/work_dirs/full_nuscenes_large_v1_slot0_marker_only`
- **GPU**: GPU 2 (30015 MiB, 99% util), 单 GPU 训练
- **启动时间**: 00:07 CDT
- **进度**: iter 30/40000, ETA ~20h
- **注意**: work_dir 在 /home (非 /mnt/SSD)，因 SSD 已满

### 早期 Loss
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 10 | 0.552 | 0.552 | 0.000 | 28.93 |
| 20 | 0.457 | 0.457 | 0.000 | 28.59 |
| 30 | 0.443 | 0.443 | 0.000 | 26.83 |

**观察**: loss 正常下降 (0.55→0.44)，reg=0（仅 marker 分类，符合 slot0_marker_only 设定），memory 26139 MiB

## 🚨 磁盘
/mnt/SSD **100%** (0 bytes!) | /home **99%** (45GB)
⚡ /mnt/SSD 完全满了 (0 free)，训练写入 /home

## GPU 状态
| GPU | 显存 | 利用率 | 用户 |
|-----|------|--------|------|
| 0 | 1436 MiB | 0% | yl0826 |
| 1 | 1420 MiB | 0% | yl0826 |
| 2 | **30015 MiB** | **99%** | **yz0370 训练中** |
| 3 | 1440 MiB | 0% | yl0826 |

## 🚨 训练质量告警
- [YELLOW] reg_loss=0 — 但这是 slot0_marker_only 设计，需确认是否预期
- [YELLOW] /home 仅 45GB，训练 checkpoint 会消耗空间

## ORCH 指令状态
0 PENDING | ORCH_060 COMPLETED | 新训练可能由 CEO 手动启动

## Agent: 全部 ✅ UP (8 sessions)
## Conductor idle #36
