# Supervisor 摘要报告
> 时间: 2026-03-11 16:10:00
> 恢复 Cycle #230 (post-shutdown)

## 训练状态
- 当前实验: **ORCH_028** (Full nuScenes, overlap-based grid, BUG-51 fix)
- 进度: iter **1180/40000** (2.95%) — **已停止**
- 停止原因: Spring break 停电, SIGTERM (signal 15) @ 2026-03-09 23:40
- GPU 使用: 全部空闲 (15 MiB / 49 GB × 4)
- 训练是否正常运行: **否 — 需要重启**
- 无 checkpoint 保存 (首次 checkpoint @2000, 训练在 @1180 中断)

## ORCH_028 训练观察 (iter 0-1180)
- **reg=0 频率极低** (~2/30 ≈ 6.7%, 远低于 ORCH_024 的 28.6%) — BUG-51 修复有效
- loss 范围: 0.43 ~ 7.58, 典型 warmup 阶段波动
- 速度: ~6.2-6.5 s/iter, 正常
- 显存: 28849 MB/GPU, 正常
- warmup 进行中 (LR 从 1.13e-6 渐升, 目标 2.5e-06 @iter 2000)

## ORCH_024 (center-based) 存档状态
- **已终止** (per Critic VERDICT_12000_TERMINATE)
- Checkpoint 完好: iter_2000 ~ iter_12000 (6 个, 各 ~15 GB)
- 位置: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/`

## 核心指标 — ORCH_024 @12000 (最终 val, 参考基线)
| 指标 | @12000 值 | 红线 | 触碰红线? |
|------|----------|------|----------|
| car_P | 0.0813 | — | — |
| car_R | 0.5263 | — | — |
| truck_R | 0.0000 | < 0.08 | ⚠️ 是 |
| bus_R | 0.2217 | — | — |
| ped_R | 0.0000 | — | ⚠️ 连续 2 次为 0 |
| bg_FA | 0.2777 | > 0.25 | ⚠️ 是 |
| off_th | 0.1275 | ≤ 0.20 | ✅ 历史最佳 |
| off_cx | 0.0383 | — | ✅ 历史最佳 |

## Loss 趋势 (ORCH_028, iter 1100-1180)
- cls_loss: 1.17 ~ 5.21 (warmup 波动正常)
- reg_loss: 1.11 ~ 2.76 (大部分 batch > 0, 修复有效)
- total_loss: 2.53 ~ 7.58

## 代码变更 (最近 5 条 GiT commit)
```
59b8195 ops: emergency shutdown - spring break power outage
996813e config: add grid_assign_mode='overlap' for BUG-51 fix
ec9a035 fix: BUG-51 overlap-based grid assignment for small objects
6655b06 Add full nuScenes 10-sample visualization script (ORCH_027)
5e7af1e Add Plan Q single-car diag config + class_filter support (ORCH_026)
```

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001-027 | COMPLETED | 全部完成 |
| **ORCH_028** | **IN PROGRESS** | 停电中断 @1180, 需重启 (从零, 无 ckpt) |

## 深度监控
- **GPU**: 0-3 全空闲 (15 MiB)
- **磁盘**: /mnt/SSD 253 GB 可用 (93% used)
- **训练进程**: 无 train.py 进程存活
- **tmux 会话**: 需 Conductor 确认各 Agent 状态

## 异常告警
1. ⚠️ **ORCH_028 训练已死** — 停电导致 SIGTERM, iter 1180, 无 checkpoint, 需从零重启
2. ⚠️ **停机时长 ~40 小时** (3/09 23:40 → 3/11 16:10), 损失 ~1180 iter (~2 小时训练)
3. ⚠️ ORCH_024 占用 ~87 GB 磁盘 (6 checkpoints), /mnt/SSD 仅剩 253 GB

## 建议 (供 Conductor 参考)
- **立即重启 ORCH_028** — 从零训练, 使用相同 config + overlap grid_assign_mode
- 考虑是否清理部分 ORCH_024 早期 checkpoint (iter_2000, iter_4000) 释放 ~30 GB 空间
- ORCH_028 新训练 ETA ~2.9 天 (40000 iter × 6.4 s/iter ÷ 4 GPU)
