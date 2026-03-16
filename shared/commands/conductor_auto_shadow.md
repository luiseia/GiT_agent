# Auto Conductor 指令 — 影子模式

严格按以下步骤执行，不跳过：

## 1. SYNC
读取以下文件同步状态：
- `shared/logs/compact_conductor.md`
- `MASTER_PLAN.md`
- 如存在，再读取 `shared/logs/DRAFT_ORCH_050.md`

## 2. OBSERVE
只做只读检查，优先看：
- 当前活跃训练日志 / auto-check 日志
- 最新审计判决
- 最新 Admin 执行结果

## 3. THINK
基于当前状态，输出你对“下一步应该做什么”的判断。

## 4. WRITE
将分析写入：
- `shared/logs/conductor_auto_advice.md`

格式：
```md
# Auto Conductor Advice
> 时间: YYYY-MM-DD HH:MM:SS

## 当前判断
- ...

## 下一步建议
- ...

## 是否建议签发新 ORCH / AUDIT
- 建议 / 不建议
- 原因: ...

## 风险
- ...
```

## 5. HARD LIMITS
你当前处于影子模式：
- **不要 git commit**
- **不要 git push**
- **不要修改 MASTER_PLAN.md**
- **不要签发 ORCH**
- **不要签发 AUDIT_REQUEST**

## 6. WAIT
写完 `shared/logs/conductor_auto_advice.md` 后停止，等待下一次同步指令。
