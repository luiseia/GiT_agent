# Admin Agent 上下文快照
- **时间**: 2026-03-14 00:01
- **当前任务**: ORCH_041 — score_thr 消融 @14000

---

## 训练状态
- **训练已暂停**: 在 iter 14010 被 kill（为了释放 GPU 跑消融）
- **Resume checkpoint**: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/iter_14000.pth`
- **Resume 命令**:
```bash
conda run -n GiT python -m torch.distributed.launch --nproc_per_node=4 --master_port=29500 \
  tools/train.py configs/GiT/plan_full_nuscenes_multilayer.py \
  --resume /mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/iter_14000.pth \
  --launcher pytorch
```
- **日志目录**: `20260313_154113`

---

## @14000 Val Baseline (score_thr=0.0)
```
car_R=0.0000  car_P=0.0000   (从 @12000 的 0.62 坍缩！BUG-17 典型表现)
truck_R=0.1916  truck_P=0.0136
traffic_cone_R=0.8298  traffic_cone_P=0.0054
bg_FA=0.3149
bus/trailer/pedestrian/motorcycle/bicycle/barrier: 全部 R=0.0000
construction_vehicle_R=0.0216
```

## ORCH_041 消融进度

| score_thr | car_R | truck_R | tc_R | bg_FA | 状态 |
|-----------|-------|---------|------|-------|------|
| 0.0 (baseline) | 0.0000 | 0.1916 | 0.8298 | 0.3149 | val 自动完成 |
| 0.1 | - | - | - | - | OOM 失败 (需重跑) |
| 0.2 | - | - | - | - | 管道中断 (需重跑) |
| 0.3 | 0.0000 | 0.1629 | 0.8298 | 0.3068 | 完成 |
| 0.5 | - | - | - | - | 运行中 (480/1505, eta ~37min) |

### 关键发现
- **score_thr=0.3 vs baseline 几乎无差异**: bg_FA 仅从 0.3149→0.3068
- **结论**: cls_probs 几乎全部 >= 0.3，score_thr 对 cls_probs 过滤无效
- 可能原因: softmax 后最大类别概率通常很高（>0.5）

---

## 待办（按优先级）
1. **等 score_thr=0.5 完成** → 提取结果 (后台 be2ls9vzq)
2. **重跑 score_thr=0.1 和 0.2** → GPU 干净时跑
3. **写 ORCH_041 报告** → `shared/logs/report_ORCH_041.md`
4. **恢复训练** → 从 iter_14000 resume
5. **标记 ORCH_041 COMPLETED**

---

## 关键技术细节

### Eval 独立运行必须参数
- `--cfg-options resume=False` (否则 16GB checkpoint 含 optimizer → OOM)
- `test_dataloader.batch_size=1` (batch=2 在 DINOv3 attention OOM)
- `test_evaluator.score_thr=X` (不是 `val_evaluator`，深拷贝)
- 用 bash 脚本直接运行（`conda run` 重定向有 bug）
- 正确的 eval 命令模板:
```bash
source ~/anaconda3/etc/profile.d/conda.sh && conda activate GiT && cd ~/projects/GiT
python -m torch.distributed.launch --nproc_per_node=4 --master_port=29510 \
  tools/test.py configs/GiT/plan_full_nuscenes_multilayer.py \
  /mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/iter_14000.pth \
  --launcher pytorch \
  --cfg-options test_evaluator.score_thr=X resume=False test_dataloader.batch_size=1
```

### CEO 代码修正 (commit 9974e3a)
- score 来源: `grid_marker_scores` → `grid_cls_scores` (class softmax)
- 变量名: `pred_grid_marker_scores` → `pred_grid_cls_scores`

### 消融日志位置
- `/tmp/eval_thr_0.1.log` — OOM 失败
- `/tmp/eval_thr_0.2.log` — 管道中断 (只 80 iter)
- `/tmp/eval_thr_0.3.log` — 完整结果
- `/tmp/eval_thr_0.5.log` — 正在写入
- `/tmp/run_ablation.sh` — 消融脚本 (有管道 bug)

---

## 历史 val 数据

| iter | car_R | car_P | bg_FA | 备注 |
|------|-------|-------|-------|------|
| @4000 | 0.8195 | 0.0451 | 0.3240 | ORCH_034 暖启动 |
| @6000 | 0.2287 | 0.0565 | 0.2519 | 新 label 首次 |
| @8000 | 0.6015 | 0.0727 | 0.2599 | 恢复中 |
| @10000 | 0.4198 | 0.0862 | 0.2879 | 振荡 |
| @12000 | 0.6159 | 0.0999 | 0.2831 | 最佳 car_P |
| @14000 | 0.0000 | 0.0000 | 0.3149 | car 坍缩 BUG-17 |

## 已完成的 ORCH
- ORCH_036: COMPLETED (superseded by 040)
- ORCH_037: COMPLETED (BUG-17 weight cap code)
- ORCH_038/039: COMPLETED (训练恢复)
- ORCH_040: COMPLETED (score_thr 代码修复 ae45b0d)
- ORCH_041: IN PROGRESS (消融)

---

*Admin Agent 上下文快照 | 2026-03-14 00:01*
