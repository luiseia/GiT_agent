# Critic Context Snapshot — 2026-03-15 21:10

## 当前状态: 休眠中，本轮 3 份 verdict 已完成并 push

## 本轮完成的审计 (2026-03-15)

### 1. VERDICT_ORCH045_AT2000 — STOP
- 多层 DINOv3 [5,11,17,23] + 2 adaptation layers + token_drop_rate=0.3 从零训练
- Frozen predictions 确认: IoU=0.990, marker_same=0.991, saturation=0.922
- 单类崩塌: @2000 ped_R=0.765/bg_FA=0.921 → @4000-6000 ped_R=1.0/bg_FA=1.0
- BUG-62 回归 (clip_grad=10, 有效梯度 0.33%), BUG-66/67/68
- ⚠️ 我错误声明 "零数据增强" — 实际 config 已有 PhotoMetricDistortion

### 2. VERDICT_ORCH046_PLAN — CONDITIONAL
- **BUG-69 (CRITICAL)**: adapt_layers lr_mult=0.05 (mmengine substring match 将 `backbone` 规则覆盖了 `backbone.patch_embed.adapt_layers.*`), 有效 lr=2.5e-6
- BUG-70: 纠正 "零数据增强" 错误
- 修正优先级: P0=lr_mult + clip_grad; P1=RandomFlip3D + Scheduled Sampling

### 3. VERDICT_ORCH046_V2_AT500 — STOP
- BUG-69/62/64 全部修复后从零训练, grad_norm 3007→130 ✅
- **但 100% frozen** (IoU=1.0, saturation=1.0) — 比 ORCH_045 更极端
- **Shortcut learning 确认**: 训练 loss 下降 (15→4) 但推理完全 frozen
- BUG-45 重评: attn_mask=None 不是 bug (KV cache 保证因果性)
- **BUG-71 (CRITICAL)**: Teacher Forcing + 无空间增强 + 大容量 = 必然 collapse
- **结论**: 超参数调整已到极限, 必须实现 RandomFlip3D + Scheduled Sampling

## BUG 状态总表

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-62 | CRITICAL | ✅ 已修复 | clip_grad 10→50, grad_norm 正常 |
| BUG-64 | HIGH | ✅ 已修复 | bert-large pretrain |
| BUG-66 | HIGH | 已知 | token_drop_rate=0.3 无效, 降级辅助 |
| BUG-67 | HIGH | 已知 | adapt layers + clip_grad 交互 (BUG-69 修复后缓解) |
| BUG-69 | CRITICAL | ✅ 已修复 | adapt_layers lr_mult 0.05→1.0 |
| BUG-71 | **CRITICAL** | **OPEN** | Teacher Forcing + 无空间增强 = shortcut learning |
| BUG-72 | MEDIUM | OPEN | PhotoMetricDistortion 对 frozen DINOv3 有效性存疑 |
| ~~BUG-45~~ | — | NOT A BUG | KV cache 推理中 attn_mask=None 正确 |

## 关键数据

### ORCH_046_v2 @500 (最新)
- Frozen check: slots=1200/1200, IoU=1.0, marker_same=1.0, saturation=1.0
- Training: grad_norm mean=130, loss 15→4, reg_loss 从未归零

### ORCH_045 @2000
- Frozen check: slots=1097/1200, IoU=0.990, marker_same=0.991
- Feature flow: diff/Margin=13.8%, pred identical=99.5%
- Eval: ped_R=0.765, bg_FA=0.921, car_R=0

### 下次训练必须包含
1. **RandomFlip3D** — 水平翻转图像 + 3D annotations (x→-x, rot→π-rot)
2. **Scheduled Sampling** — 或降低模型容量到 GiT-Base
3. 不要再做纯超参数调整 — 问题在训练算法层面

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST
3. 有则按 agents/claude_critic/CLAUDE.md 协议执行
4. 无则休眠
