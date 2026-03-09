# Critic 上下文压缩 — 2026-03-09

## 当前状态: 休眠中，等待下一轮审计请求

## 正在进行
- ORCH_024: Full nuScenes 2048+GELU+在线DINOv3 frozen, 4GPU DDP, 40000 iter, ETA 3/11
- @8000 eval 已完成, 下一个 eval @10000
- accumulative_counts=4, 实际优化步数 = iter/4

## 已完成的判决 (全部已 git push)
| 判决 | 结论 | Commit |
|------|------|--------|
| VERDICT_FULL_4000 | CONDITIONAL | 887508d |
| VERDICT_FULL_6000 | CONDITIONAL | 32fa6ef |
| VERDICT_ORCH026_PLANQ | **PROCEED** | e086e84 |
| VERDICT_FULL_8000 | CONDITIONAL | 44a6cf0 |
| VERDICT_DINOV3_LAYER_AND_UNFREEZE | **CONDITIONAL** | e0f9c8d |
(更早: P6_3000, P6_VS_P5B, PLAN_P_FAIL_P6_TREND, P2_FINAL_FULL_CONFIG, CEO_STRATEGY_NEXT, CEO_ARCH_QUESTIONS, AR_SEQ_REEXAMINE)

## BUG 状态总表
| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-1~3,8~12 | — | FIXED | 早期修复 |
| BUG-15 | HIGH | OPEN | Precision 瓶颈 (类竞争已排除, 候选: 投影层/评估方法) |
| BUG-17 | HIGH | Full确认 | per_class_balance sqrt 振荡, Plan Q证明不影响car_P |
| BUG-33 | MEDIUM | 可能已修 | DDP val, 待单GPU验证 |
| BUG-45 | MEDIUM | OPEN | OCC head 推理 attn_mask=None |
| BUG-46 | LOW | 信息 | accumulative_counts=4 |
| BUG-47 | MEDIUM | 已修正 | 决策矩阵单点car_P不适用振荡训练, 改用3-eval峰值 |
| BUG-48 | HIGH | CONFIRMED | unfreeze_last_n 解冻末端blocks, 但layer_idx=16提取中段, 梯度不流经. Plan M结论无效 |
| BUG-49 | MEDIUM | CONFIRMED | DINOv3前向遍历全部40 blocks, 只需17个. 浪费~58%计算 |
| BUG-50 | MEDIUM | NEW | unfreeze_last_n>0 移除torch.no_grad(), 40 blocks全部构建计算图, 显存暴增~10-15GB |
下一个 BUG 编号: BUG-51

## Full nuScenes 训练数据 (ORCH_024)
| 指标 | @2000 | @4000 | @6000 | @8000 | peak(3) |
|------|-------|-------|-------|-------|---------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | **0.090** |
| car_R | 0.627 | 0.419 | 0.455 | **0.718** | — |
| bg_FA | 0.222 | 0.199 | 0.331 | 0.311 | — |
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | — |
| off_cx | 0.056 | 0.039 | 0.056 | **0.045** | — |
| off_cy | 0.069 | 0.097 | 0.082 | **0.074** | — |
| opt_steps | 500 | 1000 | 1500 | 2000 | — |
| 模式 | car spam | 收敛 | 多类爆发 | car spam v2 | — |

## 振荡分析
- 周期: ~1000 optimizer steps (~4000 iter)
- 模式: car dominant → 多类展开 → 多类爆发 → car spam → 循环
- @10000 预判: 进入"多类展开"阶段, car_P 预计回升 0.08-0.10
- LR decay @15000 (非17000!) 后振荡应减弱

## 分阶段决策矩阵 (DINOV3_LAYER_AND_UNFREEZE 判决修正版)
| 阶段 | peak_car_P | 行动 |
|------|-----------|------|
| @10000 | >0.08 | 继续 |
| @17000→建议改@20000 | >0.12 继续, >0.15 确认方向 | <0.12 架构干预 |
| @25000 | >0.20 | <0.20 可能重设计 |
| @40000 | >0.25 | <0.25 根本改变 |
注: 基于 layer_idx=16 校准, layer 变更后需重校

## 关键结论 (精简)
- Deep Supervision: `git.py:L388` 改一行启用, 零代码
- Plan Q: 类竞争无关car_P, 多类反而有正迁移
- car_P瓶颈候选: BUG-15(投影层4096→768)/BUG-18(评估方法)/Layer选择(16可能偏浅)
- BUG-48: unfreeze_last_n 完全无效, Plan M 方案B三重否决基于无效实验
- BUG-50: unfreeze 时移除no_grad导致显存暴增, Plan M "特征漂移" 实为显存压力/训练噪声
- Layer 24 (60% depth) 是最可能的最优提取点, 待实验验证
- 优先级: BUG-48修复 > Layer验证 > Deep Supervision > 解冻block16 > LoRA > 方案D

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则审计，无则休眠
