# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-06 14:10 (循环 #4)

## 当前阶段: P2 启动 — BUG-9 修复实验

### P1 (Center/Around) 训练结果 — COMPLETED
- **最终迭代**: 6000/6000, 完成于 02:48
- **GPU**: 0,2 已释放
- **Checkpoint**: `iter_6000.pth` (1.97GB)
- **状态**: 完全收敛，iter 5000-6000 指标平台期

### P1@6000 指标 (旧 eval, BUG-12 修正估算)
| 指标 | 旧 eval @6000 | 修正估算 | 红线 | 状态 |
|------|-------------|---------|------|------|
| truck_recall | 0.187 | ~0.32 | < 0.08 | SAFE |
| truck_precision | 0.114 | ~0.20 | - | - |
| bus_recall | 0.463 | ~0.59 | - | - |
| car_recall | 0.567 | 0.567 | - | - |
| bg_false_alarm | 0.201 | 0.201 | > 0.25 | SAFE |
| offset_theta | 0.247 | ~0.247 | <= 0.20 | WARN |
| avg_precision | ~0.10 | ~0.13 | >= 0.20 | FAIL |

**注**: ORCH_003 任务 1 将用修正 eval 代码获取精确值。

### BUG-9 诊断结果 (ORCH_002 COMPLETED, APPROVED)
- **grad_norm 统计**: 均值 14.5, 中位 8.9, P95=45.0, P99=75.0
- **根因**: 8 个 regression sub-losses 的密集梯度在共享 decoder 累积
- **当前状态**: max_norm=0.5 → 100% 裁剪 → AdamW 退化为 Sign-SGD
- **批准方案**: Option A, max_norm=**10.0** (55.7% 迭代恢复自然梯度)
- **否决**: 5.0 (仅 19.2% 通过，不够), Loss scaling (等效降 LR，脆弱), 分层裁剪 (实现复杂)

### P2 计划
- **Config**: `plan_e_bug9_fix.py` (唯一变量: max_norm 0.5→10.0)
- **起点**: P1@6000 权重, 重置优化器状态
- **GPU**: 0,2
- **预期效果**: LR schedule 恢复有效性，AdamW 自适应缩放恢复，收敛质量提升

### 战术评估
- P1 验证了 center/around 机制：truck 稳定不崩溃
- BUG-12 修复揭示模型实际能力远超显示值
- **BUG-9 是当前最大杠杆点** — 修复后所有指标均有上升空间
- **次要瓶颈** (P2 后再处理): BUG-8 (cls 梯度不对称) + AABB 过估

### 历史审计关键洞察 (CEO 指令 #1)
1. **BUG-9 致命影响**: 100% 梯度裁剪，AdamW→Sign-SGD
2. **AABB 过估**: truck 45° 旋转时覆盖 cell 数 3.5×，边缘 cell 标签为噪声
3. **梯度三重挤压**: truck 仅占总梯度 2.1%，背景 14.3%（7× 差异）
4. **自回归误差级联**: slot 2 有效准确率比 slot 0 低 ~19%
5. Construction Vehicle 在 nuScenes-mini 中已独立于 truck

## 活跃任务
| ORCH ID | 目标 | 状态 | 优先级 | 备注 |
|---------|------|------|--------|------|
| 001 | BUG-12 修复 | **COMPLETED** | HIGH | truck +72%, bus +28% |
| 002 | BUG-9 诊断 | **COMPLETED** | CRITICAL | 推荐 max_norm=10.0, APPROVED |
| 003 | P1 最终 eval + P2 启动 | **PENDING** | HIGH | 三个子任务 |

## 下一步计划 (循环 #5)
1. 确认 ORCH_003 进展 (P2 是否成功启动)
2. P2 前 500 iter 监控: grad_norm 分布、裁剪率、loss 趋势
3. 对比 P1 vs P2 同期指标，验证 BUG-9 修复效果

## 历史决策
### [2026-03-06 14:10] 循环 #4 — ORCH_002 验收 + P2 启动决策
- **ORCH_002 验收**: BUG-9 诊断报告优秀，数据充分
- **关键决策**: 批准 max_norm=10.0 (非报告中已有 config 的 5.0)
- **理由**: 5.0 仅让 19.2% 通过，10.0 让 55.7% 通过（中位数水平），兼顾安全与效果
- **P1 完结**: 6000 iter 完成，指标平台期，无需延长
- **签发 ORCH_003**: P1 最终 eval + plan_e config 更新 + P2 训练启动

### [2026-03-06 02:55] 循环 #3 — BUG-12 验收 + CEO 指令执行
- CEO 指令 #1: 阅读历史审计报告，提取 5 项关键洞察
- CEO 指令 #2: 转达 Ops 修复 usage_watchdog.sh
- ORCH_001 验收: BUG-12 修复成功
- 签发 ORCH_002 诊断 BUG-9

### [2026-03-06 00:57] 循环 #1 — 首轮研判
- 签发 ORCH_001 给 Admin 修复 BUG-12
