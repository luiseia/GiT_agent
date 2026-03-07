# Conductor 上下文保存 (compact 前)
> 时间: 2026-03-06 21:58
> 循环: #24 刚完成, 下一轮 #25

## 当前正在做什么
- 执行 Conductor 自主循环 (每 30 分钟)
- P3 训练刚启动 (~iter 60/4000), 监控中
- 按 CLAUDE.md 流程: 不直接读 GiT/, 通过 `shared/logs/supervisor_report_latest.md` 获取数据
- 完整循环: PULL → CEO_CMD → REPORT → STATUS → VERDICT → PENDING → ADMIN → THINK → PLAN → ACT → CONTEXT → SYNC

## P3 训练状态
- **实验**: Plan F (BUG-8 fix + BUG-10 fix), config `plan_f_bug8_fix.py`
- **修复内容**: BUG-8 (cls loss 添加 bg_balance_weight) + BUG-10 (500 步 warmup)
- **起点**: P2@6000 权重
- **进度**: ~iter 60/4000, warmup 阶段
- **GPU**: 0,2 (RTX A6000) | GPU 1,3 被 yz0364 (UniAD) 占用
- **PID**: 3775971
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/`
- **LR schedule**: base_lr=5e-05, warmup 500 步 (0.001x→1.0x), milestone @2500/@3500
- **ETA**: ~00:40 (3月7日)
- **首次 val**: P3@500 (~22:10)
- **前 60 iter**: 稳定, 100% unclipped (grad_norm 1.06~8.02), 无 NaN, warmup 正常

## P3 预期 (Critic 评估)
| 指标 | P2@6000 | P3 预期 | 改善 |
|------|---------|---------|------|
| car_P | 0.079 | ~0.09-0.10 | +15-20% |
| truck_R | 0.290 | ~0.32-0.33 | +10-15% |
| avg_P | 0.121 | ~0.15+ | +25%+ |
| bg_FA | 0.198 | ~0.15-0.17 | -15-25% |

## P3 关键监测
- **首要**: avg_precision (前 1000 步应显著上升)
- **bg_FA**: 应比 P2 显著下降
- **truck_R**: 预期假阳性减少后回升
- **car_P**: 预期大幅改善

## P2@6000 最终指标 (基线)
| 指标 | P2@6000 | P1@6000 | vs P1 |
|------|---------|---------|-------|
| car_R | 0.596 | 0.628 | -5% |
| car_P | 0.079 | 0.091 | -14% |
| truck_R | 0.290 | 0.358 | -19% |
| truck_P | 0.190 | 0.176 | +8% |
| bus_R | 0.623 | 0.627 | ≈ |
| bus_P | 0.150 | 0.156 | ≈ |
| trailer_R | 0.689 | 0.644 | +7% |
| trailer_P | 0.066 | 0.035 | +89% |
| bg_FA | 0.198 | 0.163 | +21% SAFE |
| offset_cx | 0.068 | 0.081 | -16% |
| offset_cy | 0.095 | 0.139 | -32% |
| offset_th | 0.217 | 0.220 | -1.4% |
| avg_P | 0.121 | 0.114 | +6% |

## P2 全程 val 趋势 (关键节点)
| iter | car_R | truck_R | bus_R | trail_R | bg_FA | off_th | avg_P |
|------|-------|---------|-------|---------|-------|--------|-------|
| 1000 | .592 | .346 | .634 | .667 | .182 | .262 | — |
| 2000 | .603 | .315 | .654 | .600 | .191 | .227 | — |
| 3000 | .731 | .402 | .479 | .956 | .284 | .244 | .081 |
| 3500 | .640 | .295 | .570 | .889 | .217 | .225 | .107 |
| 4000 | .619 | .269 | .607 | .778 | .204 | .222 | .117 |
| 4500 | .605 | .301 | .592 | .733 | .200 | .227 | .119 |
| 5000 | .600 | .280 | .639 | .689 | .200 | .219 | .121 |
| 5500 | .600 | .290 | .630 | .689 | .198 | .218 | .121 |
| 6000 | .596 | .290 | .623 | .689 | .198 | .217 | .121 |

## 红线
| 指标 | 红线 | P2@6000 | 状态 |
|------|------|---------|------|
| truck_R | < 0.08 | 0.290 | SAFE |
| bg_FA | > 0.25 | 0.198 | SAFE |
| offset_th | <= 0.20 | 0.217 | WARN |
| avg_P | >= 0.20 | 0.121 | BELOW |

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-8 | CRITICAL | **FIXED (ORCH_004)** — cls loss bg weight |
| BUG-9 | 致命 | **FIXED & VALIDATED (P2)** — 梯度裁剪 max_norm 0.5→10.0 |
| BUG-10 | HIGH | **FIXED (ORCH_004)** — 500 步 warmup |
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
- 条件: 修复 BUG-8 + BUG-10 (已完成, ORCH_004)
- BUG-13 新发现 (LOW): slot_class 背景溢出, 暂不修复
- 3 项低于 P1 的指标 (truck_R, car_R, car_P) 全部归因 BUG-8

## 关键历史洞察
1. BUG-9: 100% 梯度裁剪 → Sign-SGD (P2 修复, 验证成功)
2. BUG-8: cls loss 完全丢弃背景 → precision 崩塌 (P3 修复)
3. AABB 过估: truck 45° 旋转覆盖 3.5× cell
4. 梯度三重挤压: truck 仅占总梯度 2.1%, bg 14.3%
5. 自回归误差级联: slot 2 比 slot 0 低 ~19%
6. IBW 大物体歧视: truck 每 cell 权重仅 car 的 1/2~1/3
7. Sign-SGD 是双刃剑: 阻止 LR schedule 但意外保护少数类
8. BUG-10: optimizer cold start, 前 500 步不稳定 (P3 修复)
9. P2 LR decay @3000 over-prediction: bg_FA 0.284 突破红线, 衰减后 0.198 回稳
10. P2 训练效率: 3500 iter 追平 P1@6000 (+42% 提速)

## CEO 指令归档
- #1 (03-06 01:15): 读历史审计报告 → 提取 5 项洞察
- #2 (03-06 01:15): 转达 Ops 修 watchdog
- #3 (03-06 15:20): 深度重读历史审计 → 提取 5 项新洞察

## 系统状态
- 全部 Agent UP (conductor, critic, supervisor, admin, ops)
- 基础设施: sync_loop + watchdog 运行正常
- GPU 0,2: P3 训练 | GPU 1,3: yz0364 (UniAD) 占用

## 待办 / 下一步
1. **循环 #25**: 读 `supervisor_report_latest.md` 获取 P3 早期数据
2. **P3@500 (~22:10)**: warmup 结束后首次 val — BUG-8 效果验证
3. 关注 avg_precision 是否上升, bg_FA 是否下降
4. P3@2500: 第一次 LR decay
5. P3@4000: 最终评估, 决定是否需要 P4
