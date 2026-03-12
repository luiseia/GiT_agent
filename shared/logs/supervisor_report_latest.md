# Supervisor 摘要报告
> 时间: 2026-03-11 19:10:00
> Cycle #233

## 训练状态
- 当前实验: **ORCH_029** (Full nuScenes, overlap + vis filter)
- 进度: iter **~250/40000** (0.63%)
- GPU: 0-3 各 ~36.5 GB, 100% 利用率
- 速度: ~6.2-6.5 s/iter (正常)
- 显存: 28849 MB/GPU (正常)
- ETA: ~2d 21h → **~3/14 16:00**
- load_from: P5b@3000
- 训练正常运行: **是 ✅**

## Loss 趋势 (iter 200-250)
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 200 | 4.79 | 2.48 | 2.31 | 25.2 |
| 210 | 4.61 | 2.02 | 2.60 | 43.7 |
| 220 | 6.92 | 3.84 | 3.08 | 47.6 |
| 230 | 4.70 | 2.16 | 2.54 | 34.9 |
| 240 | 0.53 | 0.53 | **0.00** | 37.8 |
| 250 | 9.14 | 6.76 | 2.39 | 33.2 |

- Warmup 阶段, 波动正常, 无 NaN/OOM
- **reg=0 频率: 1/25 = 4.0%** (ORCH_028 was 9.1%, ORCH_024 was 28.6%)

## 重大审计发现: VERDICT_TWO_STAGE_FILTER (18:43)

### BUG-52 (HIGH): IoF/IoB 过滤是死代码
- `use_rotated_polygon=True` 使 99.4% GT 走 convex hull 路径, **完全跳过 IoF/IoB**
- ORCH_029 实际生效的过滤: **overlap + convex hull center-check + vis >= 10%**
- min_iof=0.30, min_iob=0.20 虽已设置但**对训练无影响**
- **结论: CONDITIONAL — 继续训练, 无需改代码/重启**
  - Convex hull 提供等效保护 (Mean IoF=0.845)
  - 实际 FG=33.1/frame (比 explore_final.py 的 41.0 更严格)

### BUG-53 (MEDIUM): 验证脚本与训练行为不一致
- explore_final.py 用 AABB+IoF/IoB, 训练实际用 convex hull
- MASTER_PLAN "FG -30.3%" 数据基于验证脚本, 非训练实际

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001-027 | COMPLETED | 全部完成 |
| ORCH_028 | SUPERSEDED | 被 ORCH_029 取代 |
| **ORCH_029** | **IN PROGRESS** | iter ~250, 训练正常 |

## 审计状态
| 请求 | 状态 | 关键结论 |
|------|------|---------|
| OVERLAP_THRESHOLD | ✅ PROCEED | 无需阈值 |
| TWO_STAGE_FILTER | ✅ CONDITIONAL | BUG-52 IoF/IoB 死代码, 继续训练 |

## 深度监控
- **GPU**: 0-3 ~36.5 GB, 100% ✅
- **磁盘**: /mnt/SSD 253 GB 可用 (93%)
- **进程**: 24 个 train.py 进程存活 ✅
- **无 PENDING ORCH**

## 下一里程碑
| 事件 | 预计时间 |
|------|---------|
| @2000 val (首次 eval) | ~3/12 ~02:00 |
| @4000 val | ~3/12 ~09:00 |
| LR decay @17000 | ~3/13 ~06:00 |

## 异常告警
无。训练健康运行, 审计完成, 无阻塞项。

## Conductor 需知
1. **BUG-52**: IoF/IoB 是死代码, 实际过滤 = convex hull + vis. 不影响训练但需更新认知
2. **@4000 关注**: vis filter 对远处小物体 (ped, cone) 可能有不对称影响, 分类对比时注意
