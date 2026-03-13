# Admin Agent 工作上下文快照
**时间**: 2026-03-12 19:00
**状态**: 训练监控中，无 pending ORCH

---

## 当前活跃任务

### ORCH_035: Label Pipeline 大修后重启训练 — IN PROGRESS
- **Config**: `configs/GiT/plan_full_nuscenes_multilayer.py`
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- **当前 iter**: ~4600/40000 (从 ORCH_034@4000 resume)
- **显存**: 30610 MB/GPU (39.5 GB/GPU 含优化器)
- **速度**: ~6.3-6.7 s/iter
- **ETA**: ~2 days 15h (预计 3/15 ~10:00 完成)
- **Loss**: 3.5-4.5 (label 变化后逐渐回落)
- **4 GPU DDP**, PID 446772

#### 本次训练核心改动 (vs ORCH_034)
1. BUG-19v3: z-convention fix (box bottom, not center)
2. Convex hull + Sutherland-Hodgman IoF/IoB
3. filter_invisible=False (关闭 nuScenes vis_token)
4. min_vis_cell_count=6 组合过滤
5. min_iob=0.10 (从 0.20 降低)

#### Config 关键参数
```
online_dinov3_layer_indices = [9, 19, 29, 39]  # 多层拼接
preextracted_proj_hidden_dim = 4096             # 16384->4096->GELU->768
clip_grad = max_norm=30.0
proj lr_mult = 5.0
load_from = ORCH_034@4000 (resume=True)
grid_assign_mode = 'overlap'
min_iof=0.30, min_iob=0.10, min_vis_cell_count=6
filter_invisible=False
```

#### 下一个 val 检查点
- **@6000 val** (预计 ~3/12 21:20): 新 label pipeline 的首次 eval
  - 关注: car_P 是否改善, bg_FA 是否下降
  - 对比: ORCH_034 @4000 — car_R=0.8195, car_P=0.0451, bg_FA=0.3240

---

## 历史 val 数据对比

| 训练 | iter | car_R | car_P | bg_FA | 备注 |
|------|------|-------|-------|-------|------|
| ORCH_029 (单层) | @2000 | 0.3737 | 0.0514 | 0.1615 | 基线 |
| ORCH_032 (多层v1) | @2000 | 0.0000 | 0.0000 | 0.3181 | 坍缩 (BUG-57/58/59/60) |
| ORCH_034 (多层v3) | @2000 | 0.8124 | 0.0571 | 0.2073 | 暖启动有效 |
| ORCH_034 (多层v3) | @4000 | 0.8195 | 0.0451 | 0.3240 | 更多类出现, bg_FA 升高 |

---

## 本 session 完成的 ORCH

| ORCH | 状态 | 摘要 |
|------|------|------|
| ORCH_030 | COMPLETED | 多层 DINOv3 特征代码实现 + multilayer config |
| ORCH_031 | COMPLETED | BUG-54 (0-indexed) + BUG-55 (load_from=None) |
| ORCH_032 | COMPLETED | 停 ORCH_029, 启动多层训练 v1 → @2000 坍缩 |
| ORCH_033 | COMPLETED | BUG-57/58/59/60 修复, 多层 v2 |
| ORCH_034 | COMPLETED | BUG-52 IoF/IoB 修复, 多层 v3 → @2000 car_R=0.81 |
| ORCH_035 | IN PROGRESS | Label pipeline 大修, resume from @4000 |

---

## 关键文件位置

| 用途 | 路径 |
|------|------|
| ORCH_035 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4` |
| ORCH_034 checkpoint | `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v3/iter_4000.pth` |
| ORCH_029 checkpoint | `/mnt/SSD/GiT_Yihao/Train/Train_20260311/full_nuscenes_filtered/iter_2000.pth` |
| Multilayer config | `configs/GiT/plan_full_nuscenes_multilayer.py` |
| 核心代码 | `mmdet/models/backbones/vit_git.py` (OnlineDINOv3Embed) |
| 标签生成 | `mmdet/datasets/pipelines/generate_occ_flow_labels.py` |

---

## 注意事项

1. **训练进程在后台运行** — 恢复后直接读日志检查进度
2. @6000 val 是新 label pipeline 的首次 eval，结果关键
3. 无未处理的 DELIVERED ORCH 指令
4. 磁盘 `/mnt/SSD` 约 239GB 剩余

---

*Admin Agent 上下文快照 | 2026-03-12 19:00*
