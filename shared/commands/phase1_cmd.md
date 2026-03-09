# Phase 1 指令 — 信息收集 + 审计决策

严格按以下步骤顺序执行，不跳过任何步骤：

## 1. PULL
cd /home/UNT/yz0370/projects/GiT_agent && git pull

## 2. CEO_CMD
读取 CEO_CMD.md：
- 如有内容 → 最高优先级执行
- 执行后归档到 shared/logs/ceo_cmd_archive.md（附时间戳）
- **必须清空 CEO_CMD.md 并 git push**
- 如无内容 → 跳过

## 3. REPORT
读取 shared/logs/supervisor_report_latest.md（Supervisor 摘要）

## 4. CHECK
读取 STATUS.md（全员状态 + 基础设施健康）

## 5. PENDING
检查 shared/pending/ 中 ORCH 指令状态：
- DONE → 读取对应 shared/logs/report_ORCH_*.md
- 超时（>20 分钟无响应）→ 在 MASTER_PLAN.md 标记告警

## 6. ADMIN
读取 shared/logs/report_ORCH_*.md 了解 Admin 执行结果

## 7. THINK
综合以上所有信息，评估指标，判断：当前是否需要 Critic 审计？

## 8. AUDIT
如需审计：
- 签发 AUDIT_REQUEST_*.md 到 shared/audit/requests/
- git add && git commit && git push
- 回复："已签发审计请求: <ID>"

如不需审计：
- 回复："无需审计"

## 9. SYNC
git add && git commit && git push

**完成后等待 Phase 2 指令。**