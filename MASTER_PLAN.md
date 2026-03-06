# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-06 14:40 (循环 #6)

## 当前阶段: P2 训练监控 — BUG-9 修复验证

### P1 (Center/Around) 最终结果 — COMPLETED
- **最终迭代**: 6000/6000
- **Checkpoint**: `/mnt/SSD/GiT_Yihao/Train/Train_20260305/plan_d_center_around/iter_6000.pth`

### P1@6000 精确指标 (BUG-12 修正 eval, ORCH_003 确认)
| 指标 | 值 | 红线 | 状态 |
|------|-----|------|------|
| truck_recall | **0.358** | < 0.08 | SAFE |
| truck_precision | 0.176 | - | - |
| bus_recall | **0.627** | - | GOOD (超 0.40 目标) |
| bus_precision | 0.156 | - | - |
| car_recall | 0.628 | - | - |
| car_precision | 0.091 | - | LOW |
| trailer_recall | 0.644 | - | - |
| bg_false_alarm | **0.163** | > 0.25 | SAFE |
| offset_cx | 0.081 | <= 0.05 | WARN |
| offset_cy | 0.139 | <= 0.10 | WARN |
| offset_th | **0.220** | <= 0.20 | WARN (接近) |

### P2 (BUG-9 Fix) 训练状态 — RUNNING
- **进度**: iter ~450/6000, ETA ~19:15
- **GPU**: 0,2 (RTX A6000 x2, 各 ~22GB)
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_e_bug9_fix/`
- **Config**: `plan_e_bug9_fix.py` (唯一变量: max_norm 0.5→10.0)
- **起点**: P1@6000 权重, 优化器状态已重置
- **首次 val**: iter 500 (~14:55)

### P2 BUG-9 修复效果 (前 450 iter)
| 指标 | P1 (max_norm=0.5) | P2 (max_norm=10.0) |
|------|-------------------|-------------------|
| 未裁剪率 | **0%** | **48.9%** |
| grad_norm 典型范围 | 2.3-19.6 (全部裁剪到 0.5) | 3.1-45.7 (一半自然通过) |
| LR schedule 效果 | 无效 (常数步长) | **恢复有效** |
| 训练稳定性 | 稳定 | 稳定 (偶发尖峰被裁剪) |

**BUG-9 修复确认成功**: 48.9% 迭代使用自然梯度 (预测 55.7%)，AdamW 自适应行为已恢复。

### 战术评估
- P1 center/around 验证成功，P1 数据可作为 baseline
- BUG-9 修复是从 Sign-SGD 恢复到真正 AdamW 的质变
- P2 训练初期偶发高 grad_norm 尖峰 (39-46)，但被正确裁剪
- **关键观察点**: P2@500 首次 val 将揭示 BUG-9 修复对指标的早期影响
- **次要瓶颈** (P2 后): BUG-8 (cls 梯度不对称) + AABB 过估 + 低 precision

### BUG-9 诊断总结 (ORCH_002)
- grad_norm: 均值 14.5, 中位 8.9, P95=45.0, P99=75.0
- 根因: 8 个 regression sub-losses 通过共享 decoder 累积密集梯度
- 批准方案: max_norm=10.0 (55.7% 自然通过)

### 历史审计关键洞察
1. BUG-9: 100% 梯度裁剪 → AdamW 退化为 Sign-SGD (已修复)
2. AABB 过估: truck 45° 旋转覆盖 3.5× cell
3. 梯度三重挤压: truck 仅占总梯度 2.1%
4. 自回归误差级联: slot 2 比 slot 0 低 ~19%
5. Construction Vehicle 在 nuScenes-mini 中已独立于 truck

## 活跃任务
| ORCH ID | 目标 | 状态 | 优先级 | 备注 |
|---------|------|------|--------|------|
| 001 | BUG-12 修复 | **COMPLETED** | HIGH | truck +72%, bus +28% |
| 002 | BUG-9 诊断 | **COMPLETED** | CRITICAL | max_norm=10.0, APPROVED |
| 003 | P1 eval + P2 启动 | **COMPLETED** | HIGH | P2 已运行, 裁剪率 48.9% |

## 下一步计划 (循环 #7)
1. P2@500 首次 val 结果分析 (ETA ~14:55)
2. 对比 P2@500 vs P1@500 指标变化
3. 确认 grad_norm 分布趋势 (是否随训练稳定)

## 历史决策
### [2026-03-06 14:40] 循环 #6 — ORCH_003 验收 + P2 监控
- **ORCH_003 验收**: 三个任务全部完成，P2 训练稳定运行
- P1@6000 精确指标优于估算: truck_R=0.358, bg_FA=0.163, offset_th=0.220
- BUG-9 修复已验证: 48.9% 迭代未裁剪 (P1=0%)
- P2 训练无异常，等待首次 val

### [2026-03-06 14:15] 循环 #5 — ORCH_003 执行中确认
- Admin 在执行中，ssd_workspace 为 /mnt/SSD/GiT_Yihao/ 符号链接

### [2026-03-06 14:10] 循环 #4 — ORCH_002 验收 + P2 启动决策
- 批准 max_norm=10.0, 签发 ORCH_003

### [2026-03-06 02:55] 循环 #3 — BUG-12 验收 + CEO 指令
- CEO 指令执行, ORCH_002 签发

### [2026-03-06 00:57] 循环 #1 — 首轮研判
- 签发 ORCH_001 (BUG-12)
