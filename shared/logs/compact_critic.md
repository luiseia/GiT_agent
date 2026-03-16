# Critic Context Snapshot — 2026-03-16 01:15

## 当前状态: 休眠中，本轮 5 份 verdict 已完成并 push

## 本轮完成的审计

### 5. VERDICT_ORCH049_MARKER_PATH — CONDITIONAL (2026-03-16 01:15)
- **BUG-73 (CRITICAL, STILL OPEN)**: marker_pos_punish=3.0 / bg_balance_weight=2.5 在 ORCH_048 中未修复，fg/bg=6x 仍存在
- **BUG-75 (HIGH, NEW)**: grid_pos_embed 空间先验 + fg/bg 失衡 = marker 模板快捷通道
- **核心发现**: marker 训练路径无 GT 泄漏（首 token 看不到 GT prefix），模板来源是固定空间先验
- **特征流**: 全程 >1% rel_diff ✅，但 diff/Margin=9.7% 🔴 — 图像信号到达但无法改变决策
- **ORCH_049 修复建议**: marker_pos_punish 3.0→1.0, bg_balance_weight 2.5→5.0, around_weight 0.1→0.0, iter_200 early check

### 4. VERDICT_ORCH048_PLAN — CONDITIONAL (2026-03-16)
- **BUG-73 (CRITICAL)**: pos_cls_w_multiplier 和 neg_cls_w 在 per_class_balance 模式下被归一化消除 — Conductor 提议的修改是空操作
- **BUG-74 (HIGH)**: GlobalRotScaleTransBEV 不改图像, 只调外参 — 虚拟增强
- **核心发现**: 真正控制 fg/bg 平衡的是 marker_pos_punish (3.0) + bg_balance_weight (2.5), 当前 FG/BG 比 = 6x
- **修复建议**: marker_pos_punish 3.0→1.0, bg_balance_weight 2.5→5.0

### 1-3. 前轮审计 (2026-03-15)
- VERDICT_ORCH045_AT2000 — STOP (frozen, BUG-62/66/67/68)
- VERDICT_ORCH046_PLAN — CONDITIONAL (BUG-69/70)
- VERDICT_ORCH046_V2_AT500 — STOP (shortcut learning, BUG-71)

## BUG 状态总表

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-62 | CRITICAL | ✅ 已修复 | clip_grad 10→50 |
| BUG-64 | HIGH | ✅ 已修复 | bert-large pretrain |
| BUG-69 | CRITICAL | ✅ 已修复 | adapt_layers lr_mult 0.05→1.0 |
| BUG-71 | **CRITICAL** | **OPEN** | Teacher Forcing + 无空间增强 = shortcut learning |
| BUG-72 | MEDIUM | OPEN | PhotoMetricDistortion 对 frozen DINOv3 有效性存疑 |
| **BUG-73** | **CRITICAL** | **OPEN (2次报告)** | marker_pos_punish=3.0/bg_balance_weight=2.5 使 fg/bg=6x |
| **BUG-74** | **HIGH** | ✅ 已修复 | GlobalRotScaleTransBEV 已在 ORCH_048 移除 |
| **BUG-75** | **HIGH** | **NEW** | grid_pos_embed 空间先验 + BUG-73 失衡 = marker 模板 |
| ~~BUG-45~~ | — | NOT A BUG | KV cache 推理中 attn_mask=None 正确 |

## 关键数据

### ORCH_048 @500 特征流诊断
- patch_embed: 4.96%, image_patch: 1.68%, decoder_out: 2.23%, logits: 1.06% — 全 ✅
- pred_token identical: 97.75% 🔴
- diff/Margin: 9.7% 🔴 (≤10% 阈值)
- NEAR: 226/400, END: 155/400 — 不再全正但模板化
- grid_interp/grid_token ratio: 178% — 图像信号幅值 > 位置先验

### Loss 权重分析 (BUG-73 核心)
- 当前: fg/bg = (5×3.0)/(2.5×1.0) = 6x → 模板化
- 修复: fg/bg = (5×1.0)/(5.0×1.0) = 1x → 平衡

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则按 agents/claude_critic/CLAUDE.md 协议执行
4. 无则休眠
