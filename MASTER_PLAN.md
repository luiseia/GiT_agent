# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-06 21:00 (循环 #23)

## 当前阶段: P3 启动准备 — BUG-8/10 修复中, 等待 Admin 执行

### Critic 审计结果: CONDITIONAL
- **BUG-8 (CRITICAL)**: cls loss 完全丢弃背景类 → 修复: 两处代码路径添加 bg_cls_mask
- **BUG-10 (HIGH)**: 优化器冷启动无 warmup → 修复: P3 config 加 500 步 linear warmup
- **BUG-13 (NEW, LOW)**: slot_class 背景溢出 clamp → 暂不修复
- **结论**: 修复 BUG-8 + BUG-10 后启动 P3

### ORCH_004 已签发
- BUG-8 修复 (Focal + CE 两条路径)
- BUG-10 修复 (P3 config warmup)
- P3 训练启动 (plan_f_bug8_fix, 4000 iter)

### P3 预期 (Critic 评估)
| 指标 | P2@6000 | P3 预期 | 改善 |
|------|---------|---------|------|
| car_P | 0.079 | ~0.09-0.10 | +15-20% |
| truck_R | 0.290 | ~0.32-0.33 | +10-15% |
| avg_P | 0.121 | ~0.15+ | +25%+ |
| bg_FA | 0.198 | ~0.15-0.17 | -15-25% |

### P3 配置
- **起点**: P2@6000 权重
- **修复**: BUG-8 (cls loss bg weight) + BUG-10 (warmup)
- **步数**: 4000 iter (Critic 建议)
- **LR**: base 5e-05, warmup 500 步, milestone @2500/@3500
- **GPU**: 0,2 (或全部 4 块)
- **关键监测**: avg_precision (前 1000 步应显著上升)

---

## P2@6000 最终结果 (归档)

### P2 vs P1 最终对比
| 指标 | P2@6000 | P1@6000 | 差异 | 判定 |
|------|---------|---------|------|------|
| truck_P | **0.190** | 0.176 | +8% | 超越 |
| trailer_R | **0.689** | 0.644 | +7% | 超越 |
| trailer_P | **0.066** | 0.035 | +89% | 超越 |
| avg_P | **0.121** | 0.114 | +6% | 超越 |
| offset_cx | **0.068** | 0.081 | -16% | 超越 |
| offset_cy | **0.095** | 0.139 | -32% | 超越 |
| offset_w/h | 0.003/0.001 | 0.004/0.002 | -11%/-33% | 超越 |
| offset_th | **0.217** | 0.220 | -1.4% | 超越 |
| bus_R | 0.623 | 0.627 | -0.6% | 追平 |
| bus_P | 0.150 | 0.156 | -4% | 追平 |
| bg_FA | 0.198 | 0.163 | +21% | SAFE |
| car_R | 0.596 | 0.628 | -5% | 低于 (BUG-8) |
| truck_R | 0.290 | 0.358 | -19% | 低于 (BUG-8) |
| car_P | 0.079 | 0.091 | -14% | 低于 (BUG-8) |

**胜率: 80%。3 项低于全部归因 BUG-8 (Critic 确认)**

### BUG 跟踪更新
| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-8 | CRITICAL | **ORCH_004 修复中** | cls loss 缺 bg_balance_weight |
| BUG-9 | 致命 | **FIXED & VALIDATED** | 梯度裁剪 (P2 完整验证) |
| BUG-10 | HIGH | **ORCH_004 修复中** | 优化器冷启动无 warmup |
| BUG-12 | HIGH | **FIXED** | 评估 slot 排序 (ORCH_001) |
| BUG-13 | LOW | UNPATCHED (新) | slot_class 背景溢出 clamp |

## 活跃任务
| ID | 目标 | 状态 | 备注 |
|----|------|------|------|
| ORCH 001-003 | P1/P2 系列 | COMPLETED | 全部完成 |
| AUDIT_P2_FINAL | P2 终评 + BUG-8 审计 | **VERDICT: CONDITIONAL** | Critic 已交付 |
| **ORCH_004** | **BUG-8/10 修复 + P3 启动** | **PENDING** | 等待 Admin |

## 下一步计划 (循环 #24)
1. 检查 ORCH_004 执行进度
2. 如 Admin 已完成修复: 确认 P3 训练已启动
3. 如 P3 已启动: 监控前 50 iter loss/grad_norm
4. 关注 avg_precision 是否在前 1000 步上升

## 历史决策
### [2026-03-06 21:00] 循环 #23 — VERDICT CONDITIONAL, 签发 ORCH_004
- Critic 审计: BUG-8 CRITICAL (cls loss 丢弃背景), BUG-10 HIGH (无 warmup)
- BUG-13 新发现 (LOW, slot_class 溢出)
- 3 项低于 P1 的指标全部归因 BUG-8 (非 BUG-9 副作用)
- 签发 ORCH_004: BUG-8 + BUG-10 修复 + P3 启动
- P3 预期: truck_R +10-15%, avg_P +25%+

### [2026-03-06 20:55] 循环 #22 — P2@6000 终评 + 审计请求
### [2026-03-06 20:25] 循环 #21 — P2@5500 offset_th 首超 P1
### [2026-03-06 19:55] 循环 #20 — P2@5000 多项超越 P1
### [2026-03-06 18:55] 循环 #18 — P2@4500 三大里程碑
### [2026-03-06 18:15] 循环 #16 — P2@3500 LR 衰减验证
### [2026-03-06 17:20] 循环 #12 — P2@3000 bg_FA 红线突破
### [2026-03-06 14:40] 循环 #6 — ORCH_003 验收
### [2026-03-06 14:10] 循环 #4 — 批准 max_norm=10.0
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
