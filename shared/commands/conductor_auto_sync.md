# Auto Conductor 指令 — 同步模式

严格按以下步骤执行，不跳过：

## 1. SYNC
读取以下文件同步最新人工 Conductor 状态：
- `shared/logs/compact_conductor.md`
- `MASTER_PLAN.md`
- 如存在，再读取 `shared/logs/DRAFT_ORCH_050.md`

## 2. ACK
用 3-6 行简洁总结你已同步到的当前状态，包括：
- 当前活跃训练
- 最近 frozen-check 结论
- 下一步预案

## 3. WAIT
同步完成后等待下一次明确指令。
- 不要在这一步自行签发 ORCH / AUDIT
- 不要修改 `MASTER_PLAN.md`
- 不要 git commit / push

注意：
- 这只是**同步上下文**，不是 Phase 1 / Phase 2 决策
- 当后续收到 `cat shared/commands/phase1_cmd.md` 或 `phase2_cmd.md` 时，按正式 Conductor 权限执行
