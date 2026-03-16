# Critic Context Snapshot — 2026-03-16 01:05

## 当前状态: 休眠中，本轮 4 份 verdict 已完成并 push

## 本轮完成的审计

### 4. VERDICT_ORCH048_PLAN — CONDITIONAL (2026-03-16)
- **BUG-73 (CRITICAL)**: pos_cls_w_multiplier 和 neg_cls_w 在 per_class_balance 模式下被归一化消除 — Conductor 提议的修改是空操作
- **BUG-74 (HIGH)**: GlobalRotScaleTransBEV 不改图像, 只调外参 — 虚拟增强
- **核心发现**: 真正控制 fg/bg 平衡的是 marker_pos_punish (3.0) + bg_balance_weight (2.5), 当前 FG/BG 比 = 6x
- **修复建议**: marker_pos_punish 3.0→1.0, bg_balance_weight 2.5→5.0, slot-level masking 替代 per-token corruption
- ORCH_047 训练日志确认增强对 frozen 输出无影响

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
| **BUG-73** | **CRITICAL** | **NEW** | per_class_balance 归一化使 pos_cls_w_multiplier/neg_cls_w 无效 |
| **BUG-74** | **HIGH** | **NEW** | GlobalRotScaleTransBEV 不改图像 — 虚拟增强 |
| ~~BUG-45~~ | — | NOT A BUG | KV cache 推理中 attn_mask=None 正确 |

## 关键数据

### ORCH_047 @500
- Frozen check: slots=1200/1200, IoU=1.0, marker_same=1.0, saturation=1.0
- 加入 RandomFlipBEV + GlobalRotScaleTransBEV 后仍然 frozen
- 训练日志: loss 下降 (11→4-5), grad_norm 40-350 健康

### Loss 权重分析 (BUG-73 核心)
- per_class_balance 归一化: loss_c = w_c × punish × avg(ce) — weight 被消除
- 当前 fg/bg marker 比: (5×3.0) / (2.5×1.0) = 6x → 全正预测
- 修复后: (5×1.0) / (5.0×1.0) = 1x → 平衡

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则按 agents/claude_critic/CLAUDE.md 协议执行
4. 无则休眠
