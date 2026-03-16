# Critic Context Snapshot — 2026-03-16 07:50

## 当前状态: 休眠中，本轮 6 份 verdict 已完成并 push

## 本轮完成的审计

### 6. VERDICT_ORCH057_MARKER_NO_POS — CONDITIONAL (2026-03-16 07:50)
- **方向正确**: grid_pos_embed 是 marker 模板化的根因, 所有超参实验已失败
- **BUG-79 (MEDIUM, NEW)**: 训练/推理路径 grid_token 注入方式不对称 (attention vs 直接加法)
- **BUG-80 (LOW)**: decoder_inference 参数名 grid_pos_embed 实际是 grid_start_embed
- **实现方案**: 减法替代 (~20行), 传递 grid_pos_embed_raw, pos_id=0 时减去
- **关键数据**: ORCH_055 diff/Margin @100=54.6%✅ → @500=4.2%🔴 — 13x 下降
- **风险**: 训练路径需同步修改, 不能只改推理

### 5. VERDICT_ORCH049_MARKER_PATH — CONDITIONAL (2026-03-16 01:15)
- **BUG-73 (CRITICAL, STILL OPEN)**: marker_pos_punish=3.0/bg_balance_weight=2.5 fg/bg=6x
- **BUG-75 (HIGH)**: grid_pos_embed 空间先验 + fg/bg 失衡 = marker 模板
- **核心**: marker 无 GT 泄漏, 模板来源是空间先验 + loss 失衡

### 4. VERDICT_ORCH048_PLAN — CONDITIONAL (2026-03-16)
- **BUG-73 (CRITICAL)**: per_class_balance 归一化使 pos_cls_w/neg_cls_w 无效
- **BUG-74 (HIGH)**: GlobalRotScaleTransBEV 不改图像

### 1-3. 前轮审计 (2026-03-15)
- VERDICT_ORCH045_AT2000 — STOP
- VERDICT_ORCH046_PLAN — CONDITIONAL
- VERDICT_ORCH046_V2_AT500 — STOP

## BUG 状态总表

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-73 | CRITICAL | PARTIAL | fg/bg=1x 方向正确但崩塌; FG/BG 调参空间已用尽 |
| BUG-74 | HIGH | ✅ FIXED | GlobalRotScaleTransBEV 已移除 |
| BUG-75 | HIGH | OPEN | grid_pos_embed 空间先验 = marker 模板根因 |
| BUG-77 | CRITICAL | CONFIRMED | cell-level dropout 破坏定位 |
| **BUG-79** | **MEDIUM** | **NEW** | 训练/推理 grid_token 注入不对称 |
| **BUG-80** | **LOW** | **NEW** | decoder_inference 参数名误导 |

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则按 agents/claude_critic/CLAUDE.md 协议执行
4. 无则休眠
