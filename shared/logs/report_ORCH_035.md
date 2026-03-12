## 执行报告 — ORCH_035: Label Pipeline 大修后重启训练

### Task 1: 同步代码 ✅
5 项 label pipeline 改动全部确认存在:
1. BUG-19v3 z-convention fix ✅
2. Convex hull (`use_rotated_polygon=True`) ✅
3. `_polygon_rect_intersection_area` (Sutherland-Hodgman) ✅
4. `filter_invisible=False` ✅
5. `min_vis_cell_count=6` 组合过滤 ✅

Config 确认: `resume=True`, `load_from=iter_4000.pth`, `min_iof=0.30`, `min_iob=0.10`

### Task 2: Kill ORCH_034 ✅
- 进程终止, GPU 全部释放
- ORCH_034 checkpoint/日志保留在 `full_nuscenes_multilayer_v3/`

### Task 3: 启动训练 ✅
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- 4 GPU DDP

### Task 4: 验证 ✅
| 检查项 | 结果 |
|--------|------|
| Resume | 从 iter 4010 开始 ✅ |
| GPU | 4×A6000, 39.5 GB/GPU (含优化器状态) |
| iter 4010 loss | 5.55 (标签变化导致短暂升高, 预期中) ✅ |
| iter 4010 grad_norm | 19.3 ✅ |
| VRAM (日志) | 31740 MB/GPU ✅ |

### 耗时
~7 分钟
