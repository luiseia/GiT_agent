# Critic Context Snapshot — 2026-03-16 15:00

## 当前状态: 休眠中，本轮 7 份 verdict 已完成并 push

## 正在做什么
- 无活跃任务。本轮所有审计请求均已处理完毕。
- 最后完成: VERDICT_ORCH059_LOSS_INIT (commit `dd964fb`)
- 之前完成: VERDICT_ORCH057_MARKER_NO_POS (commit `5afb4f9`)

## 待办
- 无待处理的 AUDIT_REQUEST
- 等待 Conductor 基于 ORCH_059 verdict 签发实验 ORCH

## 本轮完成的审计 (按时间倒序)

### 7. VERDICT_ORCH059_LOSS_INIT — CONDITIONAL (2026-03-16 ~15:00)
- **审计对象**: marker all-positive 根因是否在 loss/init 而非位置编码
- **核心发现 — BUG-82 (CRITICAL)**: marker 无 bias init，初始 P(FG)=75%，100% cell 预测 FG
  - logits = x @ vocab_embed.T — 纯点积无 bias
  - 4 marker token (near/mid/far/end) 3:1 结构偏向 FG
  - 4 个 marker embedding 余弦相似度 ≥ 0.94，几乎无法区分
  - 验证: 1000 个随机 hidden state, 100% 预测 FG
- **BUG-81 (HIGH)**: focal_alpha_marker=0.75 方向错误 (FG 3× BG)，开启会加速崩塌
- **BUG-83 (MEDIUM)**: per_class_balance 下 BG per-sample 梯度稀释 39x
- **修复方案**: 添加 marker_init_bias = [-2.0, -2.0, -2.0, +0.5] → P(BG)=80.2%
- **优先级**: bias init (#1) >> focal loss (#2, 需先修 alpha) > bg_balance 调整 (#3, 已穷尽)

### 1-6. 前轮审计 (2026-03-15~16)
- VERDICT_ORCH045_AT2000 — STOP (frozen, BUG-62/66/67/68)
- VERDICT_ORCH046_PLAN — CONDITIONAL (BUG-69/70)
- VERDICT_ORCH046_V2_AT500 — STOP (shortcut learning, BUG-71)
- VERDICT_ORCH048_PLAN — CONDITIONAL (BUG-73/74)
- VERDICT_ORCH049_MARKER_PATH — CONDITIONAL (BUG-75)
- VERDICT_ORCH057_MARKER_NO_POS — CONDITIONAL (BUG-79/80)

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
| BUG-79 | MEDIUM | CONFIRMED | 训练/推理 grid_token 注入不对称 |
| BUG-80 | LOW | NEW | decoder_inference 参数名误导 |
| BUG-81 | HIGH | NEW | focal_alpha_marker=0.75 方向错误 |
| BUG-82 | CRITICAL | NEW | marker 无 bias init，P(FG)=75% |
| BUG-83 | MEDIUM | NEW | per_class_balance BG 梯度稀释 39x |

## 关键诊断数据

### 初始化 bias 验证 (debug_marker_init_bias.py)
| 配置 | P(FG) | P(BG) | % cells predict FG |
|------|-------|-------|-------------------|
| 无 bias (当前) | 75.0% | 25.0% | 100% |
| bias [-2,-2,-2,+0.5] | 19.8% | 80.2% | 0% |

### per_class_balance 梯度分析
- 典型场景: 10 FG cells, 390 BG cells
- Aggregate loss: FG 50%, BG 50%
- Per-sample gradient: FG=0.050, BG=0.001 → FG/BG = 39x

## 恢复指引
1. `cd /home/UNT/yz0370/projects/GiT_agent && git pull`
2. `cd /home/UNT/yz0370/projects/GiT && git pull`
3. 检查 `shared/audit/requests/` 是否有新 AUDIT_REQUEST
4. 有则按 `agents/claude_critic/CLAUDE.md` 协议执行
5. 无则休眠
