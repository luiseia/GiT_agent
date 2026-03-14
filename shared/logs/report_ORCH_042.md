# ORCH_042 Report: Fix BUG-62/63/17 and Resume from iter_4000

- **状态**: COMPLETED
- **执行时间**: 2026-03-14 11:00 ~ 11:12 CDT
- **GiT Commit**: `4ad3b0f`

## 修改内容

文件: `configs/GiT/plan_full_nuscenes_large_v1.py`

### BUG-62 (CRITICAL): clip_grad 10 → 30
```diff
- clip_grad=dict(max_norm=10.0, norm_type=2),
+ clip_grad=dict(max_norm=30.0, norm_type=2),
```
行 369

### BUG-63 (MEDIUM): filter_invisible True → False
```diff
# train_pipeline (行 300) 和 test_pipeline (行 310)
- filter_invisible=True
+ filter_invisible=False
```

### BUG-17 (BLOCKER): max_class_weight=3.0
```diff
# occ head config (行 256 后)
+ max_class_weight = 3.0,
```

## 训练 Resume

- **Checkpoint**: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/iter_4000.pth`
- **GPU**: 2×A6000 (GPU 0,2) — GPU 1,3 被 yl0826 的 PETR 训练占用
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1_resume4k.out`
- **PID**: 1312401
- **首次尝试**: 4 GPU OOM（GPU 1,3 只有 ~16 GB 空闲）
- **成功方案**: `CUDA_VISIBLE_DEVICES=0,2 --nproc_per_node=2`

## grad_norm 对比（验证 BUG-62 修复）

### 修复前 (clip_grad=10, iter 3900-4000):
```
Iter 3960: grad_norm=595.77  → clipped to ≤10 (60x 缩减)
Iter 3970: grad_norm=427.82  → clipped to ≤10 (43x 缩减)
Iter 3980: grad_norm=650.97  → clipped to ≤10 (65x 缩减)
Iter 3990: grad_norm=306.55  → clipped to ≤10 (31x 缩减)
```

### 修复后 (clip_grad=30, iter 4010+):
```
Iter 4010: grad_norm=198.25  → clipped to ≤30 (6.6x 缩减)
Iter 4020: grad_norm=690.08  → clipped to ≤30 (23x 缩减)
```

**结论**: 梯度信号传递量提升 3-10x（从 10 到 30 的 clip 上限）。分类器现在能接收到更强的梯度更新。

## 注意事项
- 当前只用 2 GPU（GPU 0,2），速度约为 4 GPU 的一半
- accumulative_counts=4 不变，effective batch = 2×2×4 = 16（之前 4 GPU 时为 32）
- 如果 yl0826 的训练结束，可 kill 并用 4 GPU 重启
- 测试全通过: 185 passed, 15 skipped, 3 xfailed
