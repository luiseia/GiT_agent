# Critic 上下文压缩 — 2026-03-09

## 当前状态: 休眠中，等待 ORCH_024 @8000 eval 或新审计请求

## 正在进行
- ORCH_024: Full nuScenes 2048+GELU+在线DINOv3 frozen, 4GPU DDP, 40000 iter, ETA 3/11
- @6000 eval 已完成, 下一个 eval @8000 (ETA ~3/9 21:00)
- accumulative_counts=4, 实际优化步数 = iter/4

## 已完成的判决 (全部已 git push)
| 判决 | 结论 | Commit |
|------|------|--------|
| VERDICT_P6_3000 | CONDITIONAL | 67f6644 |
| VERDICT_P6_VS_P5B | CONDITIONAL | d852faf |
| VERDICT_PLAN_P_FAIL_P6_TREND | CONDITIONAL | df6427d |
| VERDICT_P2_FINAL_FULL_CONFIG | **PROCEED** | df2d2a4 |
| VERDICT_CEO_STRATEGY_NEXT | CONDITIONAL | 83bc425 |
| VERDICT_CEO_ARCH_QUESTIONS | CONDITIONAL | dd215af |
| VERDICT_AR_SEQ_REEXAMINE | CONDITIONAL | 5b2c714 |
| VERDICT_FULL_4000 | CONDITIONAL | 887508d |
| VERDICT_FULL_6000 | CONDITIONAL | 32fa6ef |
| VERDICT_ORCH026_PLANQ | **PROCEED** | e086e84 |

## BUG 状态总表
| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-1~3,8~12 | 中~致命 | FIXED | 早期修复 |
| BUG-13 | LOW | 暂不修 | slot_class bg clamp |
| BUG-14 | MEDIUM | 架构层 | grid token 与 image patch 冗余 |
| BUG-15 | HIGH | OPEN | Precision 瓶颈 |
| BUG-17 | **HIGH** | Full确认 | per_class_balance sqrt 振荡, 但Plan Q证明不影响car_P. 降级CRITICAL→HIGH |
| BUG-18 | MEDIUM | 设计层 | 评估未跨 cell 关联 GT instance |
| BUG-27 | CRITICAL | 教训 | 改 num_vocal = 实验无效 |
| BUG-33 | MEDIUM | 可能已修 | DDP val DefaultSampler, 待 @8000 单GPU验证 |
| BUG-39 | MEDIUM | 设计层 | 双层Linear无激活=单层, 因式分解有优化优势 |
| BUG-43 | MEDIUM | 确认 | Conductor 未查代码即估算 deep supervision 实现难度 |
| BUG-45 | MEDIUM | OPEN | OCC head 推理 attn_mask=None, 训练/推理不一致 |
| BUG-46 | LOW | 信息 | accumulative_counts=4, 实际优化步数=iter/4 |
下一个 BUG 编号: BUG-47

## Full nuScenes 训练数据 (ORCH_024)
| 指标 | @2000 | @4000 | @6000 | 趋势 |
|------|-------|-------|-------|------|
| car_P | 0.079 | 0.078 | **0.090** | ↑ 突破 |
| car_R | 0.627 | 0.419 | 0.455 | ↗ 回升 |
| truck_P | 0 | 0.057 | 0.019 | ↓ FP增 |
| bus_R | 0 | 0 | 0.287 | ↑ 新类 |
| ped_P | 0.001 | 0.001 | 0.024 | ↑ 新类 |
| bg_FA | 0.222 | 0.199 | **0.331** | ↑ ❌ 多类代价 |
| off_cx | 0.056 | 0.039 | 0.056 | ↗ 新类拉偏 |
| off_cy | 0.069 | 0.097 | 0.082 | ↘ 改善 |
| off_th | 0.174 | 0.150 | 0.169 | ↗ 新类拉偏 |
| opt_steps | 500 | 1000 | 1500 | — |

## ORCH_024 @8000 决策矩阵
| car_P | bg_FA | 行动 |
|-------|-------|------|
| >0.12 | <0.30 | 架构验证, 继续到 @17000 |
| 0.08-0.12 | <0.35 | 方向正确, 继续 |
| 0.05-0.08 | any | 调参 per_class_balance |
| <0.05 | any | 严重问题 |

## 关键架构审计结论 (精简)
- Deep Supervision: 已在代码中, `git.py:L388` 改一行启用
- Attention Mask: CEO 硬 mask > Conductor 软权重, BUG-45 待修
- AR 序列: 非主要瓶颈, contributing factor, per-slot 分析待做
- 优先级: Deep Supervision >> 方案D >> LoRA >> BUG-17修复 >> Attention Mask
- Plan Q: 类竞争无关car_P (单类0.083 < 10类0.112). car_P瓶颈候选: BUG-15投影层/BUG-18评估方法

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则审计，无则休眠
