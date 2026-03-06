# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-06 00:57 (循环 #1)

## 当前阶段: P1 训练监控 + BUG 热修复

### P1 (Center/Around) 训练状态
- **进度**: iter 4210/6000, ETA ~02:27
- **GPU**: 0,2 (RTX A6000 x2, 各 ~22GB)
- **工作目录**: `GiT/ssd_workspace/Train/Train_20260305/plan_d_center_around/`
- **配置**: `configs/GiT/plan_d_reg_w1.py`, seed=2025
- **检查点**: iter_500, 1000, 1500, 2000, 2500, 3000, 3500, 4000

### 红线状态 (iter 4000)
| 指标 | 值 | 红线 | 状态 |
|------|-----|------|------|
| truck_recall | 0.193 | < 0.08 | SAFE |
| bg_false_alarm | 0.198 | > 0.25 | SAFE (iter 3000 曾触 0.265) |
| offset_theta | 0.246 | ≤ 0.20 | WARN |
| avg_precision | ~0.099 | ≥ 0.20 | FAIL |

### 战术评估
- P1 的 center/around 机制验证成功: truck_R 从未跌破 0.15（Plan D 曾崩到 0.019）
- 但精度仍是系统性瓶颈，需要 BUG-12 修复后重新评估
- BUG-9 (100% 梯度裁剪) 限制所有优化上界

## 活跃任务
| ORCH ID | 目标 | 状态 | 优先级 | 备注 |
|---------|------|------|--------|------|
| 001 | BUG-12 修复 (评估 slot 排序) | PENDING | HIGH | ~15 行代码，影响精度指标真实性 |

## 下一步计划 (循环 #2, ~01:27)
1. 确认 BUG-12 修复完成
2. 用修正后的 eval 重新评估 P1@4000 检查点
3. P1 训练完成后(6000 iter)全面评估
4. 评估 BUG-9 修复方案 (clip_grad max_norm 调整或 loss scaling)

## 历史决策
### [2026-03-06 00:57] 循环 #1 — 首轮研判
- **判断**: P1 训练稳定运行，truck_R 未触红线，允许继续到 6000 iter
- **行动**: 签发 ORCH_001 给 Admin 修复 BUG-12（最高 ROI 的快速修复）
- **理由**: BUG-12 导致 eval slot 排序不一致，修复后 precision 可能翻倍
- **风险**: bg_FA 在 iter 3000 触过 0.265，需监控后续趋势
