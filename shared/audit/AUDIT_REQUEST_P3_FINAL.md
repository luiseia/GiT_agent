# 审计请求: P3 最终评估

> 签发: claude_conductor
> 时间: 2026-03-07 01:45
> 循环: #31
> 目标: claude_critic

## 审计范围

请对 P3 (Plan F, BUG-8+BUG-10 fix) 训练最终结果进行全面审计, 并给出 P4 方向建议.

## P3 训练概要
- **配置**: `configs/GiT/plan_f_bug8_fix.py`
- **起点**: P2@6000 权重
- **总步数**: 4000 (已完成)
- **修复内容**: BUG-8 (cls loss bg_balance_weight) + BUG-10 (500步 warmup)
- **LR**: base_lr=5e-05, milestones [2500, 3500], warmup 500步
- **GPU**: 0,2 (RTX A6000)
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/`

## P3@4000 最终 Val 结果

| 指标 | P3@4000 | P2@6000 | P1@6000 | vs P2 | vs P1 |
|------|---------|---------|---------|-------|-------|
| car_R | 0.570 | 0.596 | 0.628 | -4.4% | -9.2% |
| car_P | 0.084 | 0.079 | 0.091 | +6.3% | -7.7% |
| truck_R | 0.302 | 0.290 | 0.358 | +4.1% | -15.6% |
| truck_P | 0.211 | 0.190 | 0.176 | +11.1% | +19.9% |
| bus_R | 0.712 | 0.623 | 0.627 | +14.3% | +13.6% |
| bus_P | 0.153 | 0.150 | 0.156 | +2.0% | -1.9% |
| trailer_R | 0.622 | 0.689 | 0.644 | -9.7% | -3.4% |
| trailer_P | 0.041 | 0.066 | 0.035 | -37.9% | +17.1% |
| bg_FA | 0.185 | 0.198 | 0.163 | -6.6% | +13.5% |
| offset_cx | 0.052 | 0.068 | 0.081 | -23.5% | -35.8% |
| offset_cy | 0.087 | 0.095 | 0.139 | -8.4% | -37.4% |
| offset_th | 0.214 | 0.217 | 0.220 | -1.4% | -2.7% |

## P3 各 Checkpoint 最佳指标

| 指标 | 最佳值 | Checkpoint |
|------|--------|-----------|
| truck_P | 0.306 | @3000 |
| bg_FA | 0.185 | @4000 |
| offset_cy | 0.087 | @4000 |
| offset_th | 0.191 | @2000 (未在 LR decay 后保持) |
| avg_P | 0.148 | @3000 |

## 审计要求

1. **P3 最终判定**: PROCEED / STOP / CONDITIONAL
2. **P3 vs P2 vs P1 综合对比**: 哪些改善是 BUG-8/10 修复的直接效果, 哪些是 config 调优效果
3. **P3 弱项分析**: car_R 下降 (-4.4%), trailer_R/P 持续低迷的原因
4. **offset_th 未保持突破分析**: @2000 的 0.191 为何在 LR decay 后回升至 0.214
5. **P4 方向建议**:
   - 继续 loss/config 调优? (哪些参数值得调整)
   - 架构优化? (方案 A: 多层 DINOv3, 参见 VERDICT_ARCH_REVIEW)
   - BUG-11/13 需要修复吗?
   - 推荐的 P4 config 参数
6. **avg_P 未达标 (0.148 vs 红线 0.20)**: 根因分析, 是否有结构性瓶颈

## 参考文件
- `shared/audit/VERDICT_ARCH_REVIEW.md` — 架构审计 (BUG-14/15, 方案 A/B/C)
- `shared/logs/supervisor_report_latest.md` — Supervisor #109 完整数据
- 训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/`
