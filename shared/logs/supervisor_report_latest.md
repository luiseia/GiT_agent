# Supervisor 摘要报告
> 时间: 2026-03-11 16:20:00
> Cycle #231

## 训练状态
- 当前实验: **ORCH_028** (Full nuScenes, overlap-based grid, BUG-51 fix)
- 进度: iter **1180/40000** (2.95%) — **已停止**
- 停止原因: Spring break 停电, SIGTERM @ 2026-03-09 23:40
- GPU 使用: 全部空闲 (15 MiB / 49 GB × 4)
- 训练是否正常运行: **否 — 等待审计结论后重启**
- 无 checkpoint (首次 @2000, 训练在 @1180 中断)

## 阻塞项: AUDIT_REQUEST_OVERLAP_THRESHOLD
- **签发者**: Conductor (CEO 指令)
- **内容**: 审计 overlap grid 分配是否需要最低重叠比例阈值
- **状态**: 🔴 等待 Critic VERDICT (sync_loop 正在通知 Critic)
- **影响**: ORCH_028 重启参数取决于审计结论 (是否加阈值、是否调 bg_weight)

## 核心指标 — ORCH_024 @12000 (参考基线)
| 指标 | @12000 值 | 红线 | 触碰? |
|------|----------|------|-------|
| truck_R | 0.0000 | < 0.08 | ⚠️ 是 |
| bg_FA | 0.2777 | > 0.25 | ⚠️ 是 |
| off_th | **0.1275** | ≤ 0.20 | ✅ 历史最佳 |
| off_cx | **0.0383** | — | ✅ 历史最佳 |
| car_P | 0.0813 | — | — |
| car_R | 0.5263 | — | — |

## ORCH_028 早期观察 (iter 0-1180, 参考)
- reg=0 频率 ~6.7% (vs ORCH_024 的 28.6%) — BUG-51 修复有效
- loss/速度/显存均正常

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
| **ORCH_028** | **BLOCKED** | 停电中断 @1180; 等待 AUDIT_OVERLAP_THRESHOLD 后重启 |

## 审计状态
| 请求 | 状态 | 备注 |
|------|------|------|
| AUDIT_OVERLAP_THRESHOLD | 🔴 等待 VERDICT | Critic 尚未响应, sync_loop 持续通知中 |

## Conductor 最新活动
```
edde81a supervisor: cycle #230 post-shutdown recovery report
f70a39a conductor: update MASTER_PLAN — ORCH_028 interrupted, overlap threshold audit pending
1c951ea conductor: executed CEO command — audit overlap threshold
28bf3fd ops: snapshot 20260311_160539
```

## 深度监控
- **GPU**: 0-3 全空闲 (15 MiB)
- **磁盘**: /mnt/SSD 253 GB 可用 (93%)
- **训练进程**: 无
- **ORCH_024 checkpoints**: 6 个 × ~15 GB = ~87 GB (完好, 保留中)

## 异常告警
1. ⚠️ **训练停滞** — 等待审计, GPU 闲置中
2. ⚠️ **Critic 尚未响应** AUDIT_REQUEST_OVERLAP_THRESHOLD — 可能需要人工启动 Critic
3. ⚠️ 停机累计 ~41 小时
