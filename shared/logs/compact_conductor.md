# Conductor 上下文快照
> 时间: 2026-03-14 07:50
> 原因: CEO 请求上下文保存

## 当前状态

**GiT-Large v1 训练中** — iter 3070/40000 (7.7%), PID 1169092, 4 GPU DDP

### 时间线 (03/14)
1. **00:30**: 修改 supervisor/critic/all_loops 加入训练质量健康检查
2. **00:45**: 创建 `plan_full_nuscenes_large_v1.py` (P0+P1)
3. **01:05**: 杀掉 ORCH_035 训练 (mode collapse 确认)
4. **01:08**: GiT-Large v1 训练启动
5. **01:10-04:50**: Warmup 期，loss 极度波动 (0.0~479.7)，含 grad_norm=0 和 loss=0 异常
6. **05:10**: **iter 2000 到达**, warmup 完成 (lr=2.5e-6), checkpoint 保存
7. **05:10-05:40**: @2000 eval 运行
8. **05:40**: **@2000 eval 结果**: 9/10类 recall=0, bg_FA=0.002 (全预测背景), 但 off_th=0.078 优于 ORCH_024
9. **05:40-07:50**: 训练继续，loss 持续收敛 (上界从 479→142→86→49, grad_norm 从 5000→1000→700)

## ⭐ @2000 Eval 结果 (关键数据)

| 指标 | GiT-Large v1 @2000 | ORCH_024 @2000 | 对比 |
|------|-------------------|----------------|------|
| car_R | **0.0000** | 0.627 | 🔴 未激活 |
| bus_R | 0.0017 | — | 唯一非零类 |
| 其他 8 类 | 全部 0.000 | — | 🔴 |
| bg_FA | 0.002 | 0.222 | 全预测背景 |
| **off_cy** | **0.029** | 0.069 | ✅ 优 58% |
| **off_th** | **0.078** | 0.174 | ✅✅ 优 55% |
| off_cx | 0.106 | 0.056 | 🔴 |
| off_w | 0.070 | 0.020 | 🔴 |

**诊断**: 分类器冷启动慢 (bert_embed 1024-dim 随机 + layers 24-29 随机), 非 mode collapse。Offset 回归已在学习。

## CEO 核心指示

1. **"解决frozen predictions优先级高于一切"** → P0+P1 已实施
2. **"在 ViT-L 上改 P0-P4"** → P0+P1 done, P2-P4 待实施
3. **"修改 critic/all_loops 更早发现问题"** → 已完成
4. **offset 指标优先** — 5 个 offset 直接影响 mIoU

## 训练详情

| 项目 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_large_v1.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1` |
| 日志 | `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1.out` |
| 架构 | GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen |
| 数据增强 | PhotoMetricDistortion (P0 fix) |
| train/test 分离 | ✅ (P0 fix) |
| batch | 2/GPU × 4 GPU × accumulative_counts=4 = effective 32 |
| iters | 40000, val@2000 |
| 当前进度 | **iter 3070/40000** (7.7%) |
| 当前 loss | 22~84 (收敛中), grad_norm 367~1321 |
| lr | 2.5e-6 (warmup 完成, 稳定) |
| 显存 | 26.9GB/49GB per GPU |
| ETA | ~3 天 2 小时 |
| PID | 1169092 |

### 架构变化 (vs ORCH_024)
| 参数 | ORCH_024 (旧) | GiT-Large v1 (新) |
|------|--------------|-------------------|
| backbone | ViT-Base (768, 12+6层) | **ViT-Large (1024, 24+6层)** |
| DINOv3 | ViT-7B (4096) | **ViT-L (1024)** |
| 投影 | 4096→2048→GELU→768 | **1024→1024 Linear (无损)** |
| bert_embed | 768 | **1024** |
| 数据增强 | 无 | **PhotoMetricDistortion** |
| train=test | 是 (BUG) | **否 (修复)** |

## ⭐ 下一个关键里程碑: @4000 (硬决策点)

预计 ~11:00 03/14 (约 3h 后)

### @4000 决策树
```
├─ car_R > 0.10 → ✅ PROCEED to @8000
├─ car_R 0.001-0.10 + offset 改善 → ⚠️ CONDITIONAL PROCEED
├─ car_R = 0 + offset 改善 → 🚨 签发审计, 检查分类路径
├─ car_R = 0 + offset 不变/恶化 → 🚨🚨 STOP, 全面审计
└─ 参照: ORCH_024 @4000 car_R=0.419, off_cx=0.039, off_th=0.150
```

## 待办

### 训练期间 (可并行准备代码)
- **P2**: 给 occ 任务加 position embedding — `git.py:334`
- **P3**: 每步注入 grid_interpolate_feats — `git_occ_head.py` L1111,1115 去掉 `pos_id==0`
- **P4**: Scheduled Sampling (较大改动)

### 已知问题
- **BUG-61**: reg_loss=0 在新训练中也出现（iter 620,630,1130,1600,1710-1740 连续 4 次）
- **Supervisor 报告过时**: 仍报告 ORCH_035@9450 (03-13 05:26)，未切换到新训练
- **Warmup 异常**: iter 1750 grad_norm=0, iter 1760 loss=0 (已过去, 训练恢复正常)

## 关键文件索引
- Config: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py`
- 训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1.out`
- Checkpoint: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/iter_2000.pth`
- DINOv3 ViT-L: `/mnt/SSD/yz0370/dinov3_weights/dinov3_vitl16_pretrain_lvd1689m.pth`
- 诊断脚本: `GiT/scripts/diagnose_v3_precise.py`, `diagnose_v3c_single_ckpt.py`
- MASTER_PLAN: 已更新到 @2000 eval 结果 + @4000 决策树
- Memory: `diagnosis_mode_collapse.md`

## 恢复指令
1. 读取本文件恢复上下文
2. 检查训练进度: `tail -20 /mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1.out`
3. 检查 CEO_CMD.md
4. 如 iter ≥ 4000: 读取 eval 结果，按 @4000 决策树执行
5. 如 iter < 4000: 继续 Phase 1/2 巡航循环
