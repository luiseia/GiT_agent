# Critic Context Snapshot — 2026-03-16 08:00

## 当前状态: 休眠中，本轮 6 份 verdict 已完成并 push

## 正在做什么
- 无活跃任务。本轮所有审计请求均已处理完毕。
- 最后完成: VERDICT_ORCH057_MARKER_NO_POS (commit `5afb4f9`)
- 之前完成: VERDICT_ORCH049_MARKER_PATH (commit `ca183dd`)

## 待办
- 无待处理的 AUDIT_REQUEST
- 等待 Conductor 签发新审计请求或 Admin 实现 ORCH_057 后的训练结果审计

## 本轮完成的审计 (按时间倒序)

### 6. VERDICT_ORCH057_MARKER_NO_POS — CONDITIONAL (2026-03-16 07:50)
- **审计对象**: 架构变更提案 — marker step 不加 grid_pos_embed
- **方向正确**: grid_pos_embed 是 marker 模板化的根因, 所有超参实验已失败
- **BUG-79 (MEDIUM, NEW)**: 训练/推理路径 grid_token 注入方式不对称 (attention vs 直接加法)
- **BUG-80 (LOW)**: decoder_inference 参数名 grid_pos_embed 实际是 grid_start_embed
- **实现方案**: 减法替代 (~20行), 传递 grid_pos_embed_raw, pos_id=0 时减去
- **关键数据**: ORCH_055 diff/Margin @100=54.6%✅ → @500=4.2%🔴 — 13x 下降
- **风险**: 训练路径需同步修改, 不能只改推理
- **代码位置**: 推理改 `git_occ_head.py:L1120,L1125-1126`; 训练改 `git.py:L553` + `get_grid_feature:L627-641`

### 5. VERDICT_ORCH049_MARKER_PATH — CONDITIONAL (2026-03-16 01:15)
- **BUG-73 (CRITICAL, STILL OPEN)**: marker_pos_punish=3.0/bg_balance_weight=2.5 fg/bg=6x
- **BUG-75 (HIGH)**: grid_pos_embed 空间先验 + fg/bg 失衡 = marker 模板
- **核心**: marker 无 GT 泄漏, 模板来源是空间先验 + loss 失衡
- **特征流**: 全程 >1% rel_diff ✅, 但 diff/Margin=9.7% 🔴
- **修复建议**: marker_pos_punish 3.0→1.0, bg_balance_weight 2.5→5.0

### 4. VERDICT_ORCH048_PLAN — CONDITIONAL (2026-03-16 ~00:30)
- **BUG-73 (CRITICAL)**: per_class_balance 归一化使 pos_cls_w/neg_cls_w 无效
- **BUG-74 (HIGH)**: GlobalRotScaleTransBEV 不改图像

### 1-3. 前轮审计 (2026-03-15)
- VERDICT_ORCH045_AT2000 — STOP (frozen, BUG-62/66/67/68)
- VERDICT_ORCH046_PLAN — CONDITIONAL (BUG-69/70)
- VERDICT_ORCH046_V2_AT500 — STOP (shortcut learning, BUG-71)

## BUG 状态总表

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-62 | CRITICAL | ✅ FIXED | clip_grad 10→50 |
| BUG-64 | HIGH | ✅ FIXED | bert-large pretrain |
| BUG-69 | CRITICAL | ✅ FIXED | adapt_layers lr_mult 0.05→1.0 |
| BUG-71 | CRITICAL | OPEN | Teacher Forcing + 无空间增强 = shortcut |
| BUG-73 | CRITICAL | PARTIAL | fg/bg=1x 方向正确但崩塌; 调参空间已用尽 |
| BUG-74 | HIGH | ✅ FIXED | GlobalRotScaleTransBEV 已移除 |
| BUG-75 | HIGH | OPEN→ORCH_057 | grid_pos_embed 空间先验 = marker 模板根因 |
| BUG-77 | CRITICAL | CONFIRMED | cell-level grid_pos_embed dropout 破坏定位 |
| BUG-78 | HIGH | CONFIRMED | 单 GPU batch 致 mode collapse (需 DDP) |
| BUG-79 | MEDIUM | NEW | 训练/推理 grid_token 注入不对称 |
| BUG-80 | LOW | NEW | decoder_inference 参数名误导 |

## 关键诊断数据

### ORCH_055 崩塌轨迹 (决定性证据)
| iter | diff/Margin | marker_same | 模式 |
|------|-----------|-------------|------|
| 100 | 54.6% ✅ | 0.887 | HEALTHY |
| 500 | 4.2% 🔴 | 0.988 | 崩塌 |

### ORCH_048 @500 特征流
- patch_embed: 4.96%, image_patch: 1.68%, decoder_out: 2.23%, logits: 1.06% — 全 ✅
- pred_token identical: 97.75% 🔴, diff/Margin: 9.7% 🔴
- grid_interp/grid_token ratio: 178% — 图像信号幅值 > 位置先验

### ORCH_049-056 实验总结 (超参空间已穷尽)
| ORCH | FG/BG | 结果 |
|------|-------|------|
| 048 | 6x | @500 模板化 (marker_same=0.977) |
| 049 | 1x | @200 TP=112 唯一存活 → @500 all-neg |
| 051 | 3.3x | @200 all-positive |
| 052 | 1.67x | @200 all-negative |
| 053 | 1.25x | @200 all-negative |
| 055 | 1x (DDP) | @100 健康 → @400 相变 |
| 056 | 低LR | @200 更差 (sat=0.998) |

## 恢复指引
1. `cd /home/UNT/yz0370/projects/GiT_agent && git pull`
2. `cd /home/UNT/yz0370/projects/GiT && git pull`
3. 检查 `shared/audit/requests/` 是否有新 AUDIT_REQUEST
4. 有则按 `agents/claude_critic/CLAUDE.md` 协议执行
5. 无则休眠
