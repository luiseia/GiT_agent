# Conductor 上下文快照
> 时间: 2026-03-14 16:40
> 原因: compact 前上下文保存

## 当前状态

**GiT-Large v1 @6000 eval 运行中** — 1230/1505 (82%), 预计 **~17:00** 完成
- 从 iter_4000 resume，BUG-62/63/17 已修复 (commit `4ad3b0f`)
- 2 GPU (0,2) — GPU 1,3 被 yl0826 PETR 训练占用
- 日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1_resume4k.out`

### 时间线 (03/14)
1. **00:30**: 修改 supervisor/critic/all_loops 加入训练质量健康检查
2. **00:45**: 创建 `plan_full_nuscenes_large_v1.py` (P0+P1)
3. **01:05**: 杀掉 ORCH_035 训练 (mode collapse 确认)
4. **01:08**: GiT-Large v1 训练启动 (4 GPU)
5. **01:10-04:50**: Warmup 期，loss 极度波动
6. **05:10**: iter 2000, warmup 完成
7. **05:40**: @2000 eval: 9/10类 R=0, bg_FA=0.002, off_th=0.078
8. **09:41**: **@4000 到达**, checkpoint 保存, eval 开始
9. **10:36**: **@4000 eval 完成**: 9/10类 R=0, ped_R=0.025, bg_FA=0.115
10. **10:42**: Critic 判决: **CONDITIONAL PROCEED** — 发现 BUG-62 (clip_grad=10 节流)
11. **10:45**: 签发 ORCH_042: 修复 BUG-62/63/17 + resume
12. **~11:08**: Admin 停止旧训练 (SIGTERM)
13. **11:10**: **修复后 resume 启动** — 2 GPU (0,2), iter 4010 确认, grad_norm 3x 提升
14. **11:10-15:10**: 巡航监控，BUG-61 波动 (3.3%→13.3%→7%→15%→0%→7%)
15. **15:10**: **@6000 到达**, checkpoint 保存, eval 开始
16. **~16:40**: eval 运行中 1230/1505 (82%), ~20min 剩余

## ⭐ @4000 Eval 结果

| 指标 | @2000 | **@4000** | ORCH_024 @4000 |
|------|-------|-----------|----------------|
| car_R | 0.000 | **0.000** | 0.419 |
| ped_R | 0.000 | **0.025** | — |
| 其他 8 类 | 全 0 | **全 0** | — |
| bg_FA | 0.002 | **0.115** | — |
| off_cx | 0.106 | **0.193** | 0.039 |
| off_cy | 0.029 | **0.141** | — |
| off_w | 0.070 | **0.037** | — |
| off_h | — | **0.015** | — |
| off_th | 0.078 | **0.212** | 0.150 |

**Critic 分析**: offset @2000→@4000 "恶化" 是伪信号 (bg_FA 0.002→0.115, 样本量差 58x)。分类器未激活的首要原因是 BUG-62。

## 🔧 BUG-62/63/17 修复 (ORCH_042 — COMPLETED)

| BUG | 修复 | 影响 |
|-----|------|------|
| **BUG-62** (CRITICAL) | clip_grad 10→**30** | 有效梯度提升 3x，分类器应加速激活 |
| **BUG-63** (MEDIUM) | filter_invisible True→**False** | 恢复被误杀的训练样本 |
| **BUG-17** (BLOCKER) | max_class_weight=**3.0** | 防止分类器激活后类别竞争崩溃 |

GiT commit: `4ad3b0f` | Admin report: `shared/logs/report_ORCH_042.md`

## BUG-61 监控 (CRITICAL 观察)

Resume 后 BUG-61 (reg_loss=0 + grad_norm 崩溃) 持续出现，频率波动:

| 窗口 | reg=0 频率 | grad_norm≈0 | 备注 |
|------|-----------|-------------|------|
| 4010-4100 | 0% | 0% | 首窗口干净 |
| 4100-4480 | 3.3→13.3% | 0% | 连续 reg=0 出现 |
| 4480-4960 | 6.9-8% | 3.4-12% | ALL-zero 变体 (grad_norm<1) |
| 4960-5450 | 0% | 0% | 干净窗口 |
| 5450-5690 | 6.7% | 3.3% | ALL-zero 再现 |
| 5690-5930 | 15% | — | **完全零 loss** iter 5760 (cls=0,reg=0,grad=530) |
| 5930-6000 | 0% | 0% | eval 前干净 |

**BUG-17 max_class_weight=3.0 缓解但未根治。@6000 eval 将判断 BUG-61 是否影响学习质量。**

## CEO 核心指示

1. **"解决frozen predictions优先级高于一切"** → P0+P1 已实施
2. **"在 ViT-L 上改 P0-P4"** → P0+P1 done, P2-P4 待实施
3. **offset 指标优先** — 5 个 offset 直接影响 mIoU

## 训练详情

| 项目 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_large_v1.py` (已修复) |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1` |
| 日志 (resume) | `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1_resume4k.out` |
| 架构 | GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen |
| 修复 | clip_grad=30, filter_invisible=False, max_class_weight=3.0 |
| GPU | ⚠️ 2 GPU (0,2) — GPU 1,3 被 yl0826 PETR 占用 |
| batch | 2/GPU × 2 GPU × accumulative_counts=4 = **effective 16** (原 32) |
| iters | 40000, val@2000 |
| 当前进度 | **@6000 eval 运行中** (82%, ~17:00 完成) |
| lr | 2.5e-6 (稳定) |
| 显存 | ~27GB/49GB per GPU |
| PID | 1312401 |

### 架构 (vs ORCH_024)
| 参数 | ORCH_024 (旧) | GiT-Large v1 (新) |
|------|--------------|-------------------|
| backbone | ViT-Base (768, 12+6层) | **ViT-Large (1024, 24+6层)** |
| DINOv3 | ViT-7B (4096) | **ViT-L (1024)** |
| 投影 | 4096→2048→GELU→768 | **1024→1024 Linear (无损)** |
| bert_embed | 768 | **1024** |
| 数据增强 | 无 | **PhotoMetricDistortion** |
| clip_grad | 30 | **30** (修复前是 10) |

## ⭐ 当前关键里程碑: @6000 eval (运行中)

### @6000 决策树 (Critic 条件)
```
├─ car_R > 0 + bg_FA 增长 → ✅ PROCEED to @8000
│   → BUG-62 修复见效，分类器开始激活
│
├─ car_R = 0 + bg_FA 继续增长 → ⚠️ CONDITIONAL PROCEED
│   → 分类器仍慢但模型在学习
│   → 签发审计请求 (含 BUG-61 数据)
│   → 预留 GPU 运行 diagnose_v3c_single_ckpt.py
│
├─ car_R = 0 + bg_FA 不增 → 🚨🚨 STOP
│   → 架构可能不适合单层 DINOv3
│
└─ 必须: @6000 eval 时预留 GPU 运行特征流诊断
```

### 正面信号 (训练中观察到)
- BUG-62 修复后 grad_norm 从 10 提升到 200-1400 范围 (3x+ 有效梯度)
- loss_cls 出现 1-4 低值 iter，分类器可能开始对部分样本正确预测
- @6000 前最后 10 iter 全部干净 (零 BUG-61)

## 待办

### 紧急 (等 @6000 eval 结果)
- 读取 @6000 eval 结果，按决策树执行
- 如 CONDITIONAL PROCEED: 签发审计请求 + GPU 诊断
- 如 STOP: 全面审计 + 考虑架构回退

### 训练期间 (可并行准备代码)
- **P2**: 给 occ 任务加 position embedding — `git.py:334`
- **P3**: 每步注入 grid_interpolate_feats — `git_occ_head.py` L1111,1115
- **P4**: Scheduled Sampling

### 已知问题
- **BUG-61** (CRITICAL 观察): reg=0 + grad_norm 崩溃，频率波动 0-15%，完全零 loss 新变体
- **Supervisor 报告过时**: 仍报告 ORCH_035@9450 (03-13 05:26)

## ORCH 状态
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_042 | BUG-62/63/17 修复 + resume | ✅ **COMPLETED** — commit `4ad3b0f`, 2-GPU resume |

## 关键文件索引
- Config: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py` (已修复 `4ad3b0f`)
- Resume 日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1_resume4k.out`
- Checkpoint: `iter_6000.pth`, `iter_4000.pth`, `iter_2000.pth`
- Critic 判决: `shared/audit/processed/VERDICT_LARGE_V1_AT4000.md`
- Admin 报告: `shared/logs/report_ORCH_042.md`
- MASTER_PLAN: 已更新到 ORCH_042 完成 + BUG-61 CRITICAL 观察

## 恢复指令
1. 读取本文件恢复上下文
2. 检查训练进度: `tail -20 /mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1_resume4k.out`
3. 检查 CEO_CMD.md
4. **如 @6000 eval 已完成**: 搜索日志中 `occupancy_prediction` 关键字获取 eval 结果，按 @6000 决策树执行
5. **如 @6000 eval 未完成**: 等待完成 (1505 val batches, ~4.36s/batch)
6. 如 iter > 6000 且 eval 已完成: 训练已自动继续，读取结果并决策
7. BUG-61 关注: 检查 resume 后 reg=0 频率是否继续升高
