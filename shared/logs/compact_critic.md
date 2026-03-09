# Critic 上下文压缩 — 2026-03-09

## 当前状态: 休眠中，等待下一轮审计请求

## 正在进行
- ORCH_024: Full nuScenes 2048+GELU+在线DINOv3 frozen, 4GPU DDP, 40000 iter, ETA 3/11
- @10000 eval 已完成, 下一个 eval @12000 (建议加密)
- accumulative_counts=4, 实际优化步数 = iter/4
- LR decay milestone @15000, 当前恒定 LR 5e-5

## 已完成的判决 (全部已 git push)
| 判决 | 结论 | Commit |
|------|------|--------|
| VERDICT_FULL_4000 | CONDITIONAL | 887508d |
| VERDICT_FULL_6000 | CONDITIONAL | 32fa6ef |
| VERDICT_ORCH026_PLANQ | **PROCEED** | e086e84 |
| VERDICT_FULL_8000 | CONDITIONAL | 44a6cf0 |
| VERDICT_DINOV3_LAYER_AND_UNFREEZE | **CONDITIONAL** | e0f9c8d |
| VERDICT_FULL_10000 | **CONDITIONAL** | 5fa543e |
(更早: P6_3000, P6_VS_P5B, PLAN_P_FAIL_P6_TREND, P2_FINAL_FULL_CONFIG, CEO_STRATEGY_NEXT, CEO_ARCH_QUESTIONS, AR_SEQ_REEXAMINE)

## BUG 状态总表
| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-1~3,8~12 | — | FIXED | 早期修复 |
| BUG-15 | HIGH | OPEN | Precision 瓶颈 (类竞争已排除, 候选: 投影层/评估方法/Layer选择) |
| BUG-17 | HIGH | Full确认 | per_class_balance sqrt 振荡+bg_FA恶化根因, Plan Q证明不影响car_P |
| BUG-33 | MEDIUM | 可能已修 | DDP val, 待单GPU验证 |
| BUG-45 | MEDIUM | OPEN | OCC head 推理 attn_mask=None |
| BUG-46 | LOW | 信息 | accumulative_counts=4 |
| BUG-47 | MEDIUM | 已修正 | 决策矩阵单点car_P不适用振荡训练, 改用3-eval峰值 |
| BUG-48 | HIGH | CONFIRMED | unfreeze_last_n 解冻末端blocks, 但layer_idx=16提取中段, 梯度不流经. Plan M结论无效 |
| BUG-49 | MEDIUM | CONFIRMED | DINOv3前向遍历全部40 blocks, 只需17个. 浪费~58%计算 |
| BUG-50 | MEDIUM | NEW | unfreeze_last_n>0 移除torch.no_grad(), 40 blocks全部构建计算图, 显存暴增~10-15GB |
下一个 BUG 编号: BUG-51

## Full nuScenes 训练数据 (ORCH_024, 5-eval)
| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | peak(5) |
|------|-------|-------|-------|-------|--------|---------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | **0.090** |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | **0.726** | — |
| truck_R | 0.000 | 0.059 | 0.138 | 0.000 | **0.239** | — |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | **0.407** | — |
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | 0.160 | — |
| opt_steps | 500 | 1000 | 1500 | 2000 | 2500 | — |
| 模式 | car spam | 收敛 | 广泛(5类) | 窄(2类) | 车辆(6类) | — |

@10000 新现象: CV_R=0.287, moto_R=0.126 首次出现; ped_R=0.000 消失; bg_FA=0.407 历史最差

## 振荡分析
- 周期: ~4000-6000 iter (可能在变长)
- 模式: car dominant → 多类展开 → 窄收敛 → 车辆扩展 → 循环
- bg_FA 世俗性上升趋势: 与类数正相关 + 基线漂移 (sqrt balance 套利行为)
- LR decay @15000 后振荡应减弱

## 关键决策点
| 触发 | 条件 | 行动 |
|------|------|------|
| @12000 eval | peak_car_P < 0.090 且 bg_FA > 0.40 | Early warning, 准备 ORCH_025 |
| **@17000 eval** | **peak_car_P < 0.12 或 bg_FA > 0.40** | **立即启动 ORCH_025 (deep supervision)** |
| @17000 eval | peak_car_P > 0.12 且 bg_FA < 0.40 | 继续 ORCH_024 到 @25000 |
注: @17000 是最后决策点, 不可再推迟

## Deep Supervision 准备 (ORCH_025)
- `git.py:L388`: loss_out_indices = [8, 10, 17] (backbone 18 layers)
- `git_occ_head.py:L621-624`: 辅助loss必须降权 aux_weight=0.4, 否则~4× loss跳变
- 从头训练优于 resume (避免辅助层未监督的不稳定)

## 关键结论 (精简)
- car_P 0.090 非硬天花板, 但当前配置下难超 0.12
- bg_FA 恶化是 sqrt balance 套利行为 (BUG-17 延伸), 非新 BUG
- LR decay 优先于 deep supervision (免费, 无风险, 可诊断)
- Layer 24 (60% depth) 是最可能的最优提取点
- 优先级: LR decay(自动) > BUG-48修复 > Layer验证 > Deep Supervision > 解冻 > LoRA

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则审计，无则休眠
