## 执行报告 — ORCH_032: 停止 ORCH_029 + 启动多层特征训练

### Task 1: 停止 ORCH_029 ✅
- @2000 val 结果 (记录):
  - car_recall: 0.3737, car_P: 0.0514
  - bg_FA: 0.1615
  - truck/bus/ped/motorcycle/traffic_cone/barrier: 全 0
  - bicycle_recall: 0.2380 (异常高, 可能 noise)
- iter_2000.pth checkpoint 保留: `/mnt/SSD/GiT_Yihao/Train/Train_20260311/full_nuscenes_filtered/iter_2000.pth` (15GB)
- 进程已终止, GPU 已释放

### Task 2: 清理磁盘 ✅
- `/mnt/SSD` 剩余 239GB (> 200GB), 无需清理

### Task 3: 启动多层训练 ✅
- Config 验证:
  - `online_dinov3_layer_indices = [9, 19, 29, 39]` ✅
  - `load_from = None` ✅
  - `grid_assign_mode = 'overlap'` ✅ (显式添加)
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer`
- 4 GPU DDP 启动成功
  - 显存: 29789 MB/GPU (比单层多 ~1GB, 可承受)
  - 首条 iter 日志正常: iter 10, loss 7.60, grad_norm 81.5
  - ETA: ~2 days 22h
- pytest test_config_sanity: 166 passed ✅

### GiT commits
- `64c3a10` — config: add grid_assign_mode='overlap' for multilayer config (ORCH_032)

### 耗时
~8 分钟
