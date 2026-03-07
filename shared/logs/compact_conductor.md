# Conductor 上下文保存 (compact 前)
> 时间: 2026-03-06 22:05
> 循环: #24 完成, 下一轮 #25
> 注意: 包含 Supervisor #103 的 P3@500 新数据 (尚未被 Conductor 正式处理)

## 当前正在做什么
- 执行 Conductor 自主循环 (每 30 分钟)
- P3 训练已启动并运行到 ~iter 500, 首次 val 已完成
- 按 CLAUDE.md 流程: 不直接读 GiT/, 通过 `shared/logs/supervisor_report_latest.md` 获取数据
- 完整循环: PULL → CEO_CMD → REPORT → STATUS → VERDICT → PENDING → ADMIN → THINK → PLAN → ACT → CONTEXT → SYNC

## CEO 未处理指令 (CEO_CMD.md)
- **内容**: "请避免使用1，3GPU，只使用0，2GPU"
- **状态**: 未处理 (循环 #25 需立即处理)
- **影响**: P3 已在 GPU 0,2 上运行, 符合要求, 无需额外动作. 需归档并清空.

## P3 训练状态
- **实验**: Plan F (BUG-8 fix + BUG-10 fix), config `plan_f_bug8_fix.py`
- **修复内容**: BUG-8 (cls loss 添加 bg_balance_weight) + BUG-10 (500 步 warmup)
- **起点**: P2@6000 权重
- **进度**: iter 500/4000 (12.5%), 首次 val 已完成
- **GPU**: 0,2 (RTX A6000) | GPU 1,3 被 yz0364 (UniAD) 占用
- **PID**: 3775971
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/`
- **LR schedule**: base_lr=5e-05, warmup 500 步已完成, milestone @2500/@3500
- **ETA**: ~00:50 (3月7日)
- **下次 val**: P3@1000 (~22:20)

## P3@500 首批 Val 结果 (BUG-8 效果验证!)
| 指标 | P3@500 | P2@6000 | P1@6000 | vs P2 | 状态 |
|------|--------|---------|---------|-------|------|
| truck_R | **0.374** | 0.290 | 0.358 | **+29%** | 已超 P1! |
| truck_P | **0.254** | 0.190 | 0.176 | **+33%** | 历史最佳! |
| bus_R | **0.697** | 0.623 | 0.627 | **+12%** | 历史最佳! |
| bus_P | 0.125 | 0.150 | 0.156 | -17% | 早期偏低 |
| car_R | 0.576 | 0.596 | 0.628 | -3% | 早期正常 |
| car_P | 0.075 | 0.079 | 0.091 | -5% | |
| trailer_R | 0.667 | 0.689 | 0.644 | -3% | 持平 |
| bg_FA | 0.212 | 0.198 | 0.163 | +7% | SAFE |
| offset_th | 0.253 | 0.217 | 0.220 | +17% | 早期偏高 |
| avg_P | **0.125** | 0.121 | 0.114 | **+3%** | 已超 P2! |

**BUG-8 修复效果极其显著**: 仅 500 iter (warmup 刚结束) truck_R 已超越 P2 训练 6000 iter 的最终结果!

## P3 早期信号
- Warmup 已在 iter 500 完成, LR 达到 base_lr=5e-05
- grad_norm 3.0~9.4, 健康
- loss 稳定: cls ~0.10, reg ~0.38, total ~0.50
- offset 指标偏高属正常 (P2 在 @500 也类似, 后续会收敛)

## P3 预期 (Critic 评估)
| 指标 | P2@6000 | P3 预期 | P3@500 实际 |
|------|---------|---------|-------------|
| truck_R | 0.290 | ~0.32-0.33 | **0.374 (已超预期!)** |
| avg_P | 0.121 | ~0.15+ | 0.125 (on track) |
| bg_FA | 0.198 | ~0.15-0.17 | 0.212 (早期偏高, 后续应下降) |

## P2@6000 最终指标 (基线)
| 指标 | P2@6000 | P1@6000 | vs P1 |
|------|---------|---------|-------|
| car_R | 0.596 | 0.628 | -5% |
| car_P | 0.079 | 0.091 | -14% |
| truck_R | 0.290 | 0.358 | -19% |
| truck_P | 0.190 | 0.176 | +8% |
| bus_R | 0.623 | 0.627 | -1% |
| bus_P | 0.150 | 0.156 | -4% |
| trailer_R | 0.689 | 0.644 | +7% |
| trailer_P | 0.066 | 0.035 | +89% |
| bg_FA | 0.198 | 0.163 | +21% SAFE |
| offset_cx | 0.068 | 0.081 | -16% |
| offset_cy | 0.095 | 0.139 | -32% |
| offset_th | 0.217 | 0.220 | -1.4% |
| avg_P | 0.121 | 0.114 | +6% |

## 红线
| 指标 | 红线 | P3@500 | 状态 |
|------|------|--------|------|
| truck_R | < 0.08 | 0.374 | SAFE |
| bg_FA | > 0.25 | 0.212 | SAFE |
| offset_th | <= 0.20 | 0.253 | WARN (早期正常) |
| avg_P | >= 0.20 | 0.125 | BELOW |

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-8 | CRITICAL | **FIXED & VALIDATED (P3@500)** — truck_R +29% |
| BUG-9 | 致命 | **FIXED & VALIDATED (P2)** — max_norm 0.5→10.0 |
| BUG-10 | HIGH | **FIXED & VALIDATED (P3)** — warmup 正常完成 |
| BUG-12 | HIGH | **FIXED (ORCH_001)** — eval slot 排序 |
| BUG-13 | LOW | UNPATCHED — slot_class 背景溢出 clamp |

## 已完成的 ORCH 指令
| ID | 目标 | 报告 |
|----|------|------|
| 001 | BUG-12 修复 (eval slot 排序) | report_ORCH_001.md |
| 002 | BUG-9 诊断 (梯度裁剪) | report_ORCH_002.md |
| 003 | P1 eval + P2 启动 | report_ORCH_003.md |
| 004 | BUG-8/10 修复 + P3 启动 | report_ORCH_004.md |

## Critic 审计
- AUDIT_REQUEST_P2_FINAL → VERDICT_P2_FINAL: **CONDITIONAL**
- 条件已满足 (BUG-8 + BUG-10 已修复, ORCH_004)
- BUG-13 (LOW): slot_class 背景溢出, 暂不修复

## 关键历史洞察
1. BUG-9: 100% 梯度裁剪 → Sign-SGD (P2 修复验证)
2. BUG-8: cls loss 完全丢弃背景 → precision 崩塌 (P3 修复验证, 效果显著)
3. AABB 过估: truck 45° 旋转覆盖 3.5x cell
4. 梯度三重挤压: truck 仅占总梯度 2.1%, bg 14.3%
5. Sign-SGD 是双刃剑: 阻止 LR schedule 但意外保护少数类
6. P2 LR decay @3000 over-prediction: bg_FA 0.284→0.198 回稳
7. P2 训练效率: 3500 iter 追平 P1@6000 (+42% 提速)
8. BUG-8 修复后 truck_R 在仅 500 iter 即超越 P2@6000 (+29%)

## CEO 指令归档
- #1 (03-06 01:15): 读历史审计报告
- #2 (03-06 01:15): 转达 Ops 修 watchdog
- #3 (03-06 15:20): 深度重读历史审计
- #4 (待处理): 避免使用 GPU 1,3, 只用 0,2

## 系统状态
- 全部 Agent UP (conductor, critic, supervisor, admin, ops)
- 基础设施: sync_loop + watchdog 运行正常
- GPU 0,2: P3 训练 | GPU 1,3: yz0364 (UniAD) 占用

## 待办 / 下一步
1. **循环 #25**: 处理 CEO 指令 (GPU 限制, 已符合), 处理 P3@500 val 数据
2. **P3@1000 (~22:20)**: 第二次 val, 关注 offset/bg_FA 是否改善
3. **P3@2500**: 第一次 LR decay
4. **P3@4000**: 最终评估
