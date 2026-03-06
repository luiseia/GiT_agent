# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-06 02:55 (循环 #3)

## 当前阶段: P1 收敛确认 + BUG-9 攻坚

### P1 (Center/Around) 训练状态
- **进度**: iter ~5500/6000, ETA ~03:20 完成
- **GPU**: 0,2 (RTX A6000 x2, 各 ~22GB)
- **工作目录**: `GiT/ssd_workspace/Train/Train_20260305/plan_d_center_around/`
- **状态**: 已收敛，iter 4500-5500 指标趋于稳定

### 红线状态 (iter 5500, BUG-12 修正后估算)
| 指标 | 旧 eval 值 | 修正后估算 | 红线 | 状态 |
|------|-----------|-----------|------|------|
| truck_recall | 0.187 | ~0.32 | < 0.08 | SAFE |
| bg_false_alarm | 0.201 | 0.201 | > 0.25 | SAFE |
| offset_theta | 0.247 | ~0.26 | <= 0.20 | WARN |
| avg_precision | ~0.10 | ~0.13 | >= 0.20 | FAIL(改善中) |

### BUG-12 修复结果 (ORCH_001 COMPLETED)
P1@4000 A/B 对比:
- truck_R: 0.20 → **0.35 (+72%)**，truck_P: 0.11 → **0.19 (+72%)**
- bus_R: 0.48 → **0.62 (+28%)**，bus_P: 0.13 → **0.17 (+28%)**
- 历史数据均用旧 eval 计算，不可直接对比

### 战术评估
- P1 center/around 机制验证成功：truck 稳定、未崩溃
- BUG-12 修复揭示了被掩盖的模型能力：truck 实际远好于显示值
- **当前最大瓶颈**：BUG-9 (100% 梯度裁剪) 限制所有优化上界
- **次要瓶颈**：BUG-8 (cls loss 梯度不对称) + AABB 过估 (precision 天花板)

### 历史审计关键洞察 (CEO 指令 #1 提取)
1. **BUG-9 致命影响**：grad_norm 实测 3.85-59.55，100% 被 clip=0.5 裁剪，AdamW 退化为 Sign-SGD，LR schedule 完全失效
2. **AABB 过估**：truck 在 45° 旋转时覆盖 cell 数是真实的 3.5×，边缘 cell 标签为噪声
3. **梯度三重挤压**：truck 在总梯度中仅占 2.1%，背景拿走 14.3%（7× 差异）
4. **自回归误差级联**：slot 2 有效准确率比 slot 0 低 ~19%
5. ⚠️ 勘误：Construction Vehicle 在 nuScenes-mini 中已独立于 truck，无需拆分

## 活跃任务
| ORCH ID | 目标 | 状态 | 优先级 | 备注 |
|---------|------|------|--------|------|
| 001 | BUG-12 修复 | **COMPLETED** | HIGH | truck +72%, bus +28% |
| 002 | BUG-9 诊断与修复方案 | PENDING | **CRITICAL** | 100% 梯度裁剪是系统瓶颈 |

## 下一步计划 (循环 #4)
1. 确认 ORCH_002 (BUG-9) 进展
2. P1@6000 最终评估（用修正后的 eval）
3. 根据 BUG-9 诊断结果，决定 P2 训练方案

## 历史决策
### [2026-03-06 02:55] 循环 #3 — BUG-12 验收 + CEO 指令执行
- **CEO 指令 #1**: 阅读历史审计报告，提取 5 项关键洞察（见上）
- **CEO 指令 #2**: 转达 Ops 修复 usage_watchdog.sh
- **ORCH_001 验收**: BUG-12 修复成功，truck/bus 指标大幅提升
- **新行动**: 签发 ORCH_002 诊断 BUG-9（clip_grad），这是下一个最大杠杆点
- **判断**: P1 已收敛，允许完成到 6000 iter，无需提前终止

### [2026-03-06 00:57] 循环 #1 — 首轮研判
- 签发 ORCH_001 给 Admin 修复 BUG-12
