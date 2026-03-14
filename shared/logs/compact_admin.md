# Admin Agent 上下文快照
- **时间**: 2026-03-14 00:46
- **当前任务**: 训练已恢复，等待下一个 ORCH

---

## 训练状态
- **训练运行中**: 从 iter 14000 resume，当前 iter 14010+
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- **日志**: `/tmp/train_resume_14000.log`
- **速度**: ~6.3 sec/iter, ETA ~1.9 天
- **GPU**: 4×A6000, ~31-39 GB/GPU
- **Resume 命令**:
```bash
source ~/anaconda3/etc/profile.d/conda.sh && conda activate GiT && cd ~/projects/GiT
python -m torch.distributed.launch --nproc_per_node=4 --master_port=29500 \
  tools/train.py configs/GiT/plan_full_nuscenes_multilayer.py \
  --resume /mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/iter_14000.pth \
  --work-dir /mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4 \
  --launcher pytorch
```

---

## ORCH_041 消融结果 (COMPLETED)

| score_thr | car_R | truck_R | tc_R | bg_FA | 状态 |
|-----------|-------|---------|------|-------|------|
| 0.0 (baseline) | 0.0000 | 0.1916 | 0.8298 | 0.3149 | 完成 |
| 0.1 | — | — | — | — | OOM 失败 |
| 0.2 | — | — | — | — | 管道中断 |
| 0.3 | 0.0000 | 0.1629 | 0.8298 | 0.3068 | 完成 |
| 0.5 | 0.0000 | 0.0449 | 0.6670 | 0.1668 | 完成 |

### 关键结论
- score_thr=0.3 无效（bg_FA -0.8%），因 3 类 softmax 最大值通常 ≥ 0.33
- score_thr=0.5 有效降低 bg_FA -47%，但 truck_R -77%, tc_R -20%
- **核心问题是 BUG-17 类别坍缩（car_R=0），不是置信度过滤**
- 报告: `shared/logs/report_ORCH_041.md`

---

## 关键技术细节

### Eval 独立运行必须参数
- `--cfg-options resume=False` (否则 16GB checkpoint 含 optimizer → OOM)
- `test_dataloader.batch_size=1` (batch=2 在 DINOv3 attention OOM)
- `test_evaluator.score_thr=X` (不是 `val_evaluator`，深拷贝)
- 用 bash 脚本直接运行（`conda run` 重定向有 bug）

### CEO 代码修正 (commit 9974e3a)
- score 来源: `grid_marker_scores` → `grid_cls_scores` (class softmax)
- 变量名: `pred_grid_marker_scores` → `pred_grid_cls_scores`

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
- ORCH_041: COMPLETED (score_thr 消融 d990b24)

---

*Admin Agent 上下文快照 | 2026-03-14 00:46*
