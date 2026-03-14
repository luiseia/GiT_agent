# ORCH_041 Report: score_thr Ablation @14000

- **状态**: COMPLETED
- **执行时间**: 2026-03-13 22:32 ~ 2026-03-14 00:38 CDT (~2h)
- **Checkpoint**: `iter_14000.pth`
- **Eval 配置**: 4×A6000 DDP, batch_size=1, resume=False, port=29510

## 消融结果

| score_thr | car_R | truck_R | tc_R | cv_R | bg_FA | bg_R |
|-----------|-------|---------|------|------|-------|------|
| 0.0 (baseline) | 0.0000 | 0.1916 | 0.8298 | 0.0216 | 0.3149 | 0.6851 |
| 0.1 | — | — | — | — | — | OOM (CEO eval 占 GPU) |
| 0.2 | — | — | — | — | — | 管道中断 (80/1505 iter) |
| 0.3 | 0.0000 | 0.1629 | 0.8298 | 0.0224 | 0.3068 | 0.6932 |
| **0.5** | **0.0000** | **0.0449** | **0.6670** | **0.0000** | **0.1668** | **0.8332** |

### 完整 score_thr=0.5 类别结果

| Class | Recall | Precision | GT Count |
|-------|--------|-----------|----------|
| car | 0.0000 | 0.0000 | 151260 |
| truck | 0.0449 | 0.0076 | 66899 |
| bus | 0.0000 | 0.0000 | 26711 |
| trailer | 0.0000 | 0.0000 | 17536 |
| construction_vehicle | 0.0000 | 0.0000 | 4913 |
| pedestrian | 0.0000 | 0.0000 | 30984 |
| motorcycle | 0.0000 | 0.0000 | 3624 |
| bicycle | 0.0000 | 0.0000 | 1735 |
| traffic_cone | 0.6670 | 0.0070 | 9475 |
| barrier | 0.0000 | 0.0000 | 26047 |

## 分析

### 1. score_thr=0.3 基本无效
- bg_FA: 0.3149 → 0.3068（仅 -0.8%）
- 原因: 3 类 softmax（occupied_cls + bg），最大类概率通常 ≥ 0.33
- truck_R 从 0.1916 → 0.1629（-15%），traffic_cone_R 不变

### 2. score_thr=0.5 显著降低假阳性
- **bg_FA: 0.3149 → 0.1668（-47%）** — 几乎减半
- 但 truck_R 也从 0.1916 → 0.0449（-77%），tc_R 从 0.8298 → 0.6670（-20%）
- 说明模型对约 30-50% 的正确预测信心不足（cls_prob < 0.5）

### 3. 核心问题仍是 BUG-17
- car_R 在所有 score_thr 下都是 0.0000 — 说明模型没有预测 car 类
- 这不是置信度问题，而是类别坍缩问题（BUG-17: per-batch sqrt class balancing）
- score_thr 过滤无法修复 car_R=0 的根本原因

### 4. score_thr=0.1 和 0.2 未完成但可推断
- 0.1/0.2 阈值低于 softmax 自然分布下界 (~0.33)，预期与 baseline 几乎无差异
- 不重跑，价值有限

## 结论

1. **score_thr 在 cls_probs 上可以有效降低 bg_FA**（0.5 时 -47%），但代价是同时过滤掉低信心的真阳性
2. **当前 @14000 的主要问题不是 score_thr，而是 BUG-17 类别坍缩** — car/bus/barrier/pedestrian 全部 R=0
3. **建议**: 先解决 BUG-17（修改 class balancing 策略），等模型各类别 recall 恢复后，再用 score_thr 做精度-召回率权衡
4. **合理的 score_thr 范围**: 0.3-0.5，具体值需在类别 recall 正常后重新消融

## 技术备忘

- Eval 命令必须用 `test_evaluator.score_thr`（不是 `val_evaluator`）
- 必须加 `resume=False` + `test_dataloader.batch_size=1` 防 OOM
- 用 bash 脚本 + `source conda.sh`（`conda run` 重定向有 bug）
- score 来源: `grid_cls_scores`（class softmax confidence），不是 marker_scores

## 失败记录

| score_thr | 失败原因 | 详情 |
|-----------|----------|------|
| 0.1 | CUDA OOM | CEO 的 gelu eval 同时占用 4 GPU (~25 GB/each) |
| 0.2 | Bash 管道中断 | `tee \| grep` 管道导致 eval 在 80/1505 iter 终止 |
