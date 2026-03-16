# ORCH_047 执行报告

- **状态**: COMPLETED
- **执行者**: Admin Agent
- **时间**: 2026-03-15 20:31 — 23:14

## 执行内容

### 代码实现
1. **新增 `mmdet/datasets/pipelines/bev_augmentation.py`**:
   - `RandomFlipBEV`: 水平翻转图像 + 3D boxes Y→-Y, yaw→-yaw + 相机参数 (F_L@R_sl@F_C, F_L@t_sl, K[0,2]=img_w-K[0,2])
   - `GlobalRotScaleTransBEV`: Z轴旋转 ±22.5° + 缩放 0.95-1.05，相机外参同步 (R_z@R_sl, s*R_z@t_sl)
2. **Config 修改**: train_pipeline 中 PhotoMetricDistortion 后插入两个 BEV 增强
3. **验证脚本**: `scripts/verify_bev_augmentation.py` 确认增强几何正确性

### 训练
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch047`
- **从零训练**: load_from=None, 2×A6000 (GPU 0,2)
- **初始指标**: loss=11-15, grad_norm=243-352 (极好，vs ORCH_045 loss=172)
- **训练在 @500 val 期间被外部 SIGTERM 终止** (val 1060/1505)

### GiT Commit
- `3fc2e3e` — feat: add RandomFlipBEV + GlobalRotScaleTransBEV augmentations (ORCH_047)

## @500 Frozen Check 结果

```
============================================================
MODE COLLAPSE DIAGNOSIS
============================================================
Checkpoint: iter_500.pth
Samples checked: 5

  Avg positive slots: 1200/1200 (100.0%)
  Positive IoU (cross-sample): 1.0000
  Marker same rate: 1.0000
  Coord diff (shared pos): 0.008062
  Saturation: 1.000

  VERDICT: 🔴 FROZEN PREDICTIONS DETECTED
============================================================
```

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| Positive IoU | < 0.95 | 1.0000 | ❌ FAIL |
| Marker same rate | < 0.90 | 1.0000 | ❌ FAIL |
| 不得 1200/1200 饱和 | < 1200 | 1200/1200 | ❌ FAIL |

## 分析

尽管多项改进同时生效 (BUG-69 fix + BUG-62 fix + bert-large + BEV augmentation + token_drop=0.3)：
- Loss 从 ORCH_045 的 172 降至 11-15 (15x 改善)
- Grad norm 从 6122 降至 243-352 (20x 改善)

**但 @500 仍然 100% mode collapse**。这表明问题根源不在 lr、embedding、或数据增强，可能是：
1. **架构层面**: 解码器过度依赖位置编码而非输入特征
2. **BUG-45 未修复**: 推理时缺少 causal attention mask，训练/推理不一致
3. **训练策略**: 500 iter 可能太早，模型还在学习 trivial pattern

## 可视化
保存在 `/home/UNT/yz0370/projects/GiT_agent/shared/logs/VIS/047_iter500_frozen_check/`
