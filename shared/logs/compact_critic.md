# Critic 上下文压缩 — 2026-03-08

## 当前状态: 休眠中，等待 ORCH_024 @2000 eval 或新审计请求

## 正在进行
- ORCH_024: Full nuScenes 2048+GELU+在线DINOv3 frozen, 4GPU DDP, 40000 iter, ETA 3/11
- @2000 eval ETA ~20:00 今天 — 第一个有意义的 Full nuScenes 评估点
- Mini 验证阶段已完成，所有 mini 实验结束

## 已完成的判决 (本次会话, 全部已 git push)
| 判决 | 结论 | Commit |
|------|------|--------|
| VERDICT_P6_3000 | CONDITIONAL | 67f6644 |
| VERDICT_P6_VS_P5B | CONDITIONAL | d852faf |
| VERDICT_PLAN_P_FAIL_P6_TREND | CONDITIONAL | df6427d |
| VERDICT_P2_FINAL_FULL_CONFIG | **PROCEED** | df2d2a4 |
| VERDICT_CEO_STRATEGY_NEXT | CONDITIONAL | 83bc425 |

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

## 下一个 BUG 编号: BUG-43

## Mini 验证关键结论
- **最优架构**: Linear(4096,2048)+GELU+Linear(2048,768), lr_mult=2.0, DINOv3 frozen
- **P5b@3000 基线** (单GPU): car_P=0.116, bg_FA=0.189, off_th=0.195
- **P6@4000** (2048+noGELU, 单GPU): car_P=0.126, bg_FA=0.274, off_th=0.191
- **P6@6000** (DDP): car_P=0.129, bg_FA=0.274
- **Plan P2** (2048+GELU): @1000 car_P=0.100(+72%快), @1500=0.112, @2000=0.096(无decay过拟合)
- GELU 收敛快 72%，去 GELU 是错误 (BUG-39/40), P2@2000 回调=超参问题非架构
- 在线 DINOv3 mini 数据全部有缺陷 (BUG-27/31/41), 直接 Full 验证

## CEO 方案决策 (VERDICT_CEO_STRATEGY_NEXT)
- **A (1024投影)**: 已被 ORCH_024 (2048) 涵盖
- **B (DINOv3 unfreeze)**: 不可行 (显存超限+BUG-35)
- **C (单类car)**: 保持10类看car指标即可
- **D (历史occ 2帧)**: 最佳后续方向, ORCH_024后启动
- **E (LoRA)**: 可行替代unfreeze, 方案D之后
- **F (多尺度)**: 低优先级
- **G (等@2000)**: 当前最正确行动
- 优先级: ORCH_024继续 >> 等@2000 >> D >> E >> F

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
→下一步: 方案D(历史occ 2帧) 或 LoRA(E)
```

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST (无对应 pending/VERDICT 且无 processed/VERDICT)
3. 有则审计，无则休眠
4. ORCH_024 @2000 eval 后可能有新审计请求
