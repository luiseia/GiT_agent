# Critic 上下文压缩 — 2026-03-09

## 当前状态: 休眠中，等待下一轮审计请求

## 正在进行
- ORCH_024: **已判决终止** (VERDICT_12000_TERMINATE: PROCEED)
- ORCH_028: 待 Conductor 签发, overlap-based grid 标签重训, 从零开始
- BUG-51 FIXED: grid_assign_mode='overlap' (GiT commit ec9a035)

## 已完成的判决 (全部已 git push)
| 判决 | 结论 | Commit |
|------|------|--------|
| VERDICT_FULL_4000 | CONDITIONAL | 887508d |
| VERDICT_FULL_6000 | CONDITIONAL | 32fa6ef |
| VERDICT_ORCH026_PLANQ | **PROCEED** | e086e84 |
| VERDICT_FULL_8000 | CONDITIONAL | 44a6cf0 |
| VERDICT_DINOV3_LAYER_AND_UNFREEZE | **CONDITIONAL** | e0f9c8d |
| VERDICT_FULL_10000 | **CONDITIONAL** | 5fa543e |
| VERDICT_12000_TERMINATE | **PROCEED** | 22157d9 |
(更早: P6_3000, P6_VS_P5B, PLAN_P_FAIL_P6_TREND, P2_FINAL_FULL_CONFIG, CEO_STRATEGY_NEXT, CEO_ARCH_QUESTIONS, AR_SEQ_REEXAMINE)

## BUG 状态总表
| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-1~3,8~12 | — | FIXED | 早期修复 |
| BUG-15 | HIGH | OPEN | Precision 瓶颈 (可能部分归因 BUG-51, 待 ORCH_028 验证) |
| BUG-17 | HIGH | Full确认 | per_class_balance sqrt 振荡, Plan Q证明不影响car_P |
| BUG-33 | MEDIUM | 可能已修 | DDP val, 待单GPU验证 |
| BUG-45 | MEDIUM | OPEN | OCC head 推理 attn_mask=None |
| BUG-46 | LOW | 信息 | accumulative_counts=4 |
| BUG-47 | MEDIUM | 已修正 | 决策矩阵用3-eval峰值. **旧阈值全部失效, 需在 ORCH_028 @4000 后重建** |
| BUG-48 | HIGH | CONFIRMED | unfreeze_last_n 解冻末端blocks无效. Plan M结论无效 |
| BUG-49 | MEDIUM | CONFIRMED | DINOv3前向浪费~58%计算 |
| BUG-50 | MEDIUM | NEW | unfreeze移除no_grad显存暴增 |
| BUG-51 | **CRITICAL→FIXED** | **FIXED** | Grid center-based分配: 35.5%物体零cell, 70.1%投影<56px. 修复: overlap模式 |
下一个 BUG 编号: BUG-52 (BUG-51 由 Conductor 发现并编号)

## ORCH_024 最终数据 (center-based 标签, 仅作 baseline 对照)
| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | @12000 | peak |
|------|-------|-------|-------|-------|--------|--------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | 0.081 | **0.090** |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | 0.726 | 0.526 | — |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | 0.407 | **0.278** | — |
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | 0.160 | **0.128** | — |
⚠️ 所有数据基于 BUG-51 缺陷标签, 不可与 overlap 训练直接对比

## ORCH_028 关键原则 (Critic 建议)
1. **只改标签** (overlap), 其他参数不动 → 单一变量对照
2. **从零训练**, 不 resume → 旧知识在新标签下有害
3. **@4000 后重建决策矩阵** → 旧阈值全部失效
4. offset 基线会变 (overlap 边缘 cell 更大) → 不要与 ORCH_024 offset 直接对比
5. bg_weight=2.5 先保持, 观察 bg_FA 后再调

## 关键结论 (精简)
- BUG-51 可能是 car_P 天花板 + bg_FA 膨胀 + 类振荡的最底层根因
- Deep Supervision: 暂缓, 先看 overlap 标签的效果
- Layer 24 验证: 暂缓, 先看 overlap 标签的效果
- 优先级: overlap重训(ORCH_028) >> 其他所有优化

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则审计，无则休眠
