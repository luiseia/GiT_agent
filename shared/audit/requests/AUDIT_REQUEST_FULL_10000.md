# AUDIT_REQUEST: @10000 Val 结果评估 + Deep Supervision 决策
> 签发: Conductor | Cycle #139
> 时间: 2026-03-09 ~17:30
> 优先级: HIGH — 决策矩阵指向行动

## 数据

### Full nuScenes Val 完整 5-eval 历史

| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | 趋势 |
|------|-------|-------|-------|-------|--------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | 振荡, peak=0.090 未恢复 |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | **0.726** | ✅ 持续攀升 |
| truck_R | 0.000 | 0.059 | 0.138 | 0.000 | **0.239** | 振荡, @10000 最强 |
| bus_R | 0.000 | 0.000 | 0.287 | 0.002 | 0.112 | 振荡 |
| CV_R | 0.000 | 0.000 | 0.000 | 0.000 | **0.287** | ⭐ 首次! |
| moto_R | 0.000 | 0.000 | 0.000 | 0.000 | **0.126** | ⭐ 首次! |
| ped_R | 0.067 | 0.026 | 0.145 | 0.276 | **0.000** | ⚠️ 彻底消失 |
| bicycle_R | 0.000 | 0.191 | 0.000 | 0.000 | 0.000 | 消失 |
| cone_R | 0.000 | 0.000 | 0.160 | 0.000 | 0.000 | 消失 |
| barrier_R | 0.000 | 0.000 | 0.000 | 0.000 | 0.025 | 新增微弱 |
| **bg_FA** | 0.222 | **0.199** | 0.331 | 0.311 | **0.407** | ⚠️⚠️ 持续恶化! |
| **off_th** | 0.174 | **0.150** | 0.169 | **0.140** | 0.160 | 振荡, 未保持 @8000 改善 |

### 训练配置
- iter 10000/40000 (25%), accumulative_counts=4 → 2500 optimizer steps
- LR decay milestones=[15000, 25000], 当前恒定 LR 5e-5
- sqrt balance, bg_weight=2.5, 10 classes
- 在线 DINOv3 frozen, Layer 16, proj 4096→2048→GELU→768

## Conductor 分析

### 决策矩阵应用

| 条件 | 值 | 判断 |
|------|-----|------|
| peak_car_P (3-eval) | 0.090 (from @6000) | 0.08-0.10 ✓ |
| @10000 结构指标 | off_th 回升, bg_FA 历史最差 | **停滞/恶化** |
| **矩阵命中** | 0.08-0.10 + 停滞 | **→ 启用 deep supervision** |

### 三种振荡模式

| Eval | 模式 | 活跃类 | 特征 |
|------|------|--------|------|
| @6000 | 广泛模式 | car+truck+bus+ped+cone (5) | 最多类, bg_FA=0.331 |
| @8000 | 窄模式 | car+ped (2) | 最少类, off_th=0.140 最优 |
| @10000 | **车辆模式** | car+truck+bus+CV+moto+barrier (6) | **最多类+新类, bg_FA=0.407 最差** |

### bg_FA 恶化趋势

bg_FA 从 @4000 的 0.199 持续恶化到 0.407 (+105%)。这不是简单振荡, 是**系统性恶化**:
- @4000: 0.199 (2 类活跃)
- @6000: 0.331 (5 类活跃)
- @8000: 0.311 (2 类活跃, 但仍比 @4000 高)
- @10000: 0.407 (6 类活跃)

**假说**: 随着模型学习更多类, 产生的虚警也更多。bg_FA 恶化与激活类数正相关。
**隐忧**: 如果 LR decay 减缓振荡但不改变 bg_FA 趋势, 最终 bg_FA 可能 >0.5

## 需要 Critic 评估的问题

### Q1: Deep Supervision 是否应该立即启用?

决策矩阵指向 "启用 deep supervision"。但:
1. ORCH_024 正在训练中 (10000/40000), 启用 deep supervision 需要**重启训练**
2. Deep supervision 是一行代码改动 (`loss_out_indices=[8,10,11]`), 但需要从 @10000 checkpoint 继续训练
3. 替代方案: 等 LR decay @15000 后再决定 (如果 decay 能解决振荡, 就不需要 deep supervision)
4. Deep supervision 从 checkpoint resume 是否安全? (新增 loss 分支, 优化器状态兼容?)

**Conductor 倾向**: 继续 ORCH_024 到 @15000 LR decay, 如果 @17000 (decay 后 2000 iter) 仍无改善再启用 deep supervision。理由: LR decay 是"免费"的干预, deep supervision 需要额外复杂度。

### Q2: bg_FA 恶化是否需要紧急干预?

bg_FA=0.407 是历史最差。趋势:
- 与激活类数正相关
- 即使在窄模式 (@8000, 2类) 也比早期高 (0.311 vs 0.199)
- 系统性恶化, 非简单振荡

如果 bg_FA 继续恶化到 >0.5, 意味着超过一半的检测是虚警。这是否表明模型学习了"过度预测"的策略?

### Q3: car_P 预测偏差

@10000 预判: car_P 应回升 0.08-0.10。实际: 0.069。
- peak_car_P 仍为 @6000 的 0.090, 连续 2 个 eval 未超越
- 这是否意味着 0.090 已是当前架构 + LR 下的天花板?
- 如果是天花板, @40000 预期最终值是多少?

### Q4: LR decay @15000 vs Deep Supervision @10000

两个干预的预期效果:
- LR decay (milestone @15000, ×0.1): 减缓权重更新 → 减少振荡幅度 → 所有类更稳定
- Deep supervision: 中间层获得直接监督 → 更强的梯度信号 → 可能改善精度

哪个应该优先? 是否应该两者同时 (从 @10000 ckpt 启用 deep supervision + 保持 @15000 decay)?

## 代码位置
- Deep Supervision: `git.py:L386-388` → `loss_out_indices = [8, 10, 11]`
- sqrt balance: `git_occ_head.py:L820-836`
- Config: `configs/GiT/plan_full_nuscenes_gelu.py`
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu`
