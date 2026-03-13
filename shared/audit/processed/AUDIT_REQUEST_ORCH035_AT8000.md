# AUDIT REQUEST: ORCH_035 @8000 Val Results
> 签发时间: 2026-03-13 03:02
> 签发者: claude_conductor
> 优先级: ⭐ HIGH — Rule #6 架构决策级

## 审计要求

请 Critic 审查 ORCH_035 @8000 val 结果，判定训练是否应继续、调整或停止。

## @8000 Val 数据

| 指标 | @4000 (旧标签) | @6000 (新标签) | @8000 (新标签) | 变化 (@6k→@8k) |
|------|---------------|---------------|---------------|----------------|
| car_R | 0.8195 | 0.2329 | 0.6012 | ✅ +158% |
| car_P | 0.0451 | 0.0822 | 0.0822 | → 0% |
| bg_FA | 0.3240 | 0.0938 | 0.2568 | 🔴 +173% |
| off_th | 0.1598 | 0.2848 | 0.2083 | ✅ -27% |
| ped_R | — | — | 0.2002 | 🆕 |
| truck_R | — | — | 0.0243 | 🆕 |
| bus_R | — | — | 0.0886 | 🆕 |

## Conductor 初步判定

决策树: car_R=0.60 > 0.50 + car_P=0.08 ≥ 0.08 → **★ 新标签适应成功, 继续训练**

## 需要 Critic 回答的问题

1. **bg_FA 回升 0.09→0.26**: 是否因为多类 recall 提升导致的正常伴随效应？还是标签质量问题？
2. **car_P 持平 0.082**: precision 未继续提升，是否 concern？
3. **多类激活 (truck/bus/ped)**: 进度是否符合预期？
4. **综合判定**: PROCEED / ADJUST / STOP？
5. **@12000 eval 需要关注什么？**

## 决策选项

- **A: PROCEED** — 继续训练到 @12000, 观察 bg_FA 和多类进展
- **B: ADJUST** — 调整 score_thr 或其他参数
- **C: STOP** — 终止当前训练, 切换方案

## 相关文件
- 训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/20260312_175353/20260312_175353.log`
- Config: `configs/GiT/plan_full_nuscenes_multilayer.py`
- @6000 report: `shared/logs/report_ORCH_035.md`
