## 执行报告 — ORCH_040: score_thr 消融代码修复
- **状态**: 代码修复完成, 等待 eval 执行
- **完成时间**: 2026-03-13 15:52

### 根因分析
ORCH_036 eval 结果完全相同的两个 Bug:
1. `Occ2DBoxMetric.__init__` 接收 `score_thr` 参数但**从未存储到 self** → 过滤条件永不生效
2. `_predict_single()` 中 `ret_scores = bboxes.new_ones(len(ret_labels))` → 所有 score = 1.0（但此路径仅供 InstanceData，不影响 grid-level 评估）

### 修复方案 (已实施)
**不修改模型训练路径**，仅修改推理+评估管线：

| 文件 | 修改 |
|------|------|
| `git_occ_head.py:decoder_inference` | 已有 `grid_marker_scores: pred_scores[..., 0]` (上轮已加) |
| `git_occ_head.py:predict()` | 新增 `grid_marker_scores=None` 参数，透传到返回 dict |
| `git_occ_head.py:add_pred_to_datasample()` | 注入 `sample.pred_grid_marker_scores` |
| `occ_2d_box_eval.py:__init__` | 添加 `self.score_thr = score_thr` |
| `occ_2d_box_eval.py:process()` | 当 `score_thr > 0` 且有 marker scores 时，过滤 `p_is_pos &= (scores >= thr)` |

### Confidence 来源
marker token 的 softmax probability，在 autoregressive decode 时已计算：
```python
marker_logits = logits[:, marker_near_id : marker_near_id + 4]
marker_probs = F.softmax(marker_logits, dim=-1)
score_abs, absmax = torch.max(marker_probs, dim=-1)
```
共 4 个 marker token (NEAR/MID/FAR/END)，取 max 作为 confidence。

### 向后兼容性
- `score_thr=0.0` (默认): 条件 `self.score_thr > 0` 不满足 → 不执行过滤 → 与原行为完全一致
- `grid_marker_scores=None`: `.get()` 返回 None → 不过滤 → 旧 checkpoint 兼容

### 消融执行计划
GPU 全部被训练占用 (4x ~39.5GB)。消融将在以下时机执行：
- **方案 A**: 下次 val 窗口 (~19:12, iter 14000) 确认基线正确后，等训练下一次 val 或空闲时逐个执行
- **方案 B**: 如 CEO 批准短暂暂停训练，可立即串行执行全部消融

```bash
# 消融命令 (待执行)
for thr in 0.0 0.1 0.2 0.3 0.5; do
  CUDA_VISIBLE_DEVICES=0 python -m torch.distributed.launch --nproc_per_node=1 --master_port=29501 \
    tools/test.py configs/GiT/plan_full_nuscenes_multilayer.py \
    /mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/iter_12000.pth \
    --launcher pytorch \
    --cfg-options test_evaluator.score_thr=$thr
done
```

### Commit
`ae45b0d` - fix: ORCH_040 score_thr filtering - thread marker confidence through predict pipeline
