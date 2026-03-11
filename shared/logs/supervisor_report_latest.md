# Supervisor 摘要报告
> 时间: 2026-03-11 19:05:00
> Cycle #232

## 训练状态
- 当前实验: **ORCH_029** (Full nuScenes, 两阶段过滤标签)
- 进度: **初始化中** (config dump 阶段, 尚未开始 iter)
- GPU 使用: 0-3 各 ~1.7 GB (模型加载中, 预计训练开始后升至 ~28.8 GB)
- 训练是否正常运行: **启动中 — 需下轮确认**
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260311/full_nuscenes_filtered`

## 重大进展 (Cycle #231 → #232)

### 1. VERDICT_OVERLAP_THRESHOLD 完成 (16:23)
- **结论: PROCEED** — 无需添加阈值
- Convex hull 已是隐式 ~50% IoF 阈值, Mean IoF=0.845, 仅 0.4% cell < 0.20
- 边缘 cell 问题在统计上不存在

### 2. CEO 指导: 两阶段过滤方案实施 (commit `a64a226`)
- Stage 1: `vis >= 10%` (object-level, 拒绝出画面物体)
- Stage 2: `IoF >= 30% OR IoB >= 20%` (cell-level, 过滤噪声 + 保护小目标)
- 20 样本验证: FG 减少 30.3%, 对象保留率 96.9%

### 3. ORCH_029 签发 + 启动 (18:30)
- 替代 ORCH_028 (被停电 kill, 无 ckpt)
- 从零训练, overlap + 两阶段过滤, 其他参数同 ORCH_024

### 4. AUDIT_REQUEST_TWO_STAGE_FILTER 签发 (18:27)
- 不阻塞 ORCH_029, 审计结论可能影响后续调参

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001-027 | COMPLETED | 全部完成 |
| ORCH_028 | **SUPERSEDED** | 被 ORCH_029 取代 (停电 kill + 标签升级) |
| **ORCH_029** | **IN PROGRESS** | 初始化中, 4 GPU DDP |

## 审计状态
| 请求 | 状态 |
|------|------|
| OVERLAP_THRESHOLD | ✅ VERDICT 完成 — PROCEED |
| **TWO_STAGE_FILTER** | 🔴 等待 VERDICT (不阻塞训练) |

## 核心指标 — ORCH_024 @12000 (参考基线)
| 指标 | 值 | 红线 |
|------|-----|------|
| car_P | 0.0813 | — |
| truck_R | 0.0000 | ⚠️ < 0.08 |
| bg_FA | 0.2777 | ⚠️ > 0.25 |
| off_th | **0.1275** | ✅ 历史最佳 |

## 代码变更 (最近 5 条 GiT commit)
```
a64a226 feat: two-stage grid cell filtering (vis>=10% + IoF>=30% OR IoB>=20%)
59b8195 ops: emergency shutdown - spring break power outage
996813e config: add grid_assign_mode='overlap' for BUG-51 fix
ec9a035 fix: BUG-51 overlap-based grid assignment for small objects
6655b06 Add full nuScenes 10-sample visualization script (ORCH_027)
```

## 深度监控
- **GPU**: 0-3 ~1.7 GB (初始化), 进程存活 (PID 88858-88861)
- **磁盘**: /mnt/SSD 253 GB 可用 (93%)
- **ORCH_024 ckpts**: 6 × ~15 GB 保留中
- **ORCH_028 work_dir**: 存在但无 ckpt, ORCH_029 建议删除

## 下一里程碑
| 事件 | 预计时间 |
|------|---------|
| ORCH_029 首个训练 iter | 数分钟内 |
| @100 iter 早期检查 | ~+11 min |
| @2000 val | ~+3.5 h |

## 异常告警
无新告警。训练刚启动，等待确认初始化完成。
