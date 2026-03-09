# Critic 上下文压缩 — 2026-03-08

## 当前状态: 休眠中，等待 ORCH_024 @2000 eval 或新审计请求

## 正在进行
- ORCH_024: Full nuScenes 2048+GELU+在线DINOv3 frozen, 4GPU DDP, 40000 iter, ETA 3/11
- @2000 eval ETA ~20:00 今天 — 第一个有意义的 Full nuScenes 评估点
- Mini 验证阶段已完成，所有 mini 实验结束

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

## 历史判决 (前几次会话)
P2_FINAL, ARCH_REVIEW, P3_FINAL, P4_FINAL, 3D_ANCHOR, P5_MID,
INSTANCE_GROUPING, P5B_3000(×2), P6_ARCHITECTURE, DIAG_RESULTS,
DIAG_FINAL, P6_1000, P6_1500 — 全部 CONDITIONAL 或 PROCEED

## BUG 状态总表
| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-1~3,8~12 | 中~致命 | FIXED | 早期修复 (theta, bg梯度, score链, cls_loss, clip_grad, warmup, classes, 匹配) |
| BUG-13 | LOW | 暂不修 | slot_class bg clamp |
| BUG-14 | MEDIUM | 架构层 | grid token 与 image patch 冗余 |
| BUG-15 | HIGH | OPEN | Precision 瓶颈 |
| BUG-16 | MEDIUM | 设计层 | 预提取特征与数据增强不兼容 |
| BUG-17 | HIGH | OPEN | per_class_balance 极不均衡数据零和振荡 |
| BUG-18 | MEDIUM | 设计层 | 评估未跨 cell 关联 GT instance |
| BUG-19 | HIGH | FIXED | proj_z0 标签问题 |
| BUG-20 | HIGH | 数据层 | mini 样本不足导致类振荡 |
| BUG-27 | CRITICAL | 教训 | 改 num_vocal = 实验无效 |
| BUG-30 | — | **INVALID** | GELU不损害off_th, 假设错误 |
| BUG-33 | MEDIUM | 确认 | DDP val GT重复, P不受影响, R偏差~10% |
| BUG-35 | MEDIUM | 教训 | DINOv3 unfreeze = 特征漂移 |
| BUG-39 | MEDIUM | 设计层 | 双层Linear无激活=单层, 但因式分解有优化优势 |
| BUG-41 | HIGH | 确认 | Plan O 全程warmup, 结果不可信 |
| BUG-42 | MEDIUM | 记录 | Plan P2 全程无LR decay (max_iters<milestone) |
| BUG-43 | MEDIUM | 确认 | Conductor 未查代码即估算 deep supervision 实现难度 |
| BUG-44 | LOW | 理论层 | Deep supervision 各层共享 vocab embedding |
| BUG-45 | MEDIUM | OPEN | OCC head 推理 attn_mask=None, 训练/推理不一致 |

## 下一个 BUG 编号: BUG-46

## CEO 架构问题审计结论 (VERDICT_CEO_ARCH_QUESTIONS)
- **Q1 (30 Token AR)**: 非主要瓶颈, 低优先级. 但 Conductor 误称"原始 GiT 序列更长"
- **Q2 (Deep Supervision)**: **已在代码中实现!** `git.py:L388` 改一行即可启用. Conductor 严重误判
- **Q3 (Attention Mask)**: CEO 硬 mask 方案优于 Conductor 软权重方案. 发现 BUG-45 (训练/推理 mask 不一致)
- **Q4 (评判标准)**: 基本合理, 补充规则5(不从mini做架构决策)和规则6(Full首次有意义eval需1epoch后)
- **优先级修正**: Deep Supervision(零成本) >> 评判标准 >> 方案D >> Attention Mask >> LoRA >> 解码长度
- **AR 序列复核**: 维持"非主要瓶颈"但上调为 contributing factor. 关键新发现: finished_mask 缩短实际序列, exposure bias 是合法担忧但非首要. 零成本验证: per-slot 指标分析

## ORCH_024 @2000 决策矩阵
| 结果 | 行动 |
|------|------|
| car_P > 0.15 | 架构正确, 继续训练, 排队方案D |
| car_P 0.08-0.15 | 方向正确, 继续 |
| car_P 0.03-0.08 | 需调参, 不中断 |
| car_P < 0.03 | 在线DINOv3可能有根本问题, 切预提取175GB |

## 训练代际谱系 (精简)
```
P1→P2→P3→P4→P5(DINOv3 L16)→P5b(双层1024+GELU)
→P6(2048+noGELU, BUG-39退化但@3500超P5b)
→Plan P2(2048+GELU, 收敛快72%)
→ORCH_024(Full nuScenes, 2048+GELU+在线DINOv3 frozen)
→下一步: Deep Supervision(零成本) + 方案D(历史occ 2帧)
```

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST (无对应 pending/VERDICT 且无 processed/VERDICT)
3. 有则审计，无则休眠
4. ORCH_024 @2000 eval 后可能有新审计请求
