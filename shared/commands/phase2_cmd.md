# Phase 2 指令 — 读取判决 + 决策 + 行动

严格按以下步骤顺序执行，不跳过任何步骤：

## 1. PULL
git pull（获取 Critic 可能产出的 VERDICT）

## 2. RE-THINK
读取 shared/audit/pending/ 下所有 VERDICT_*.md：
- 有 → 逐个读取内容，纳入本轮决策
- 无 → 记录"无审计反馈"，基于已有信息决策

## 3. ARCHIVE
将已读取的 VERDICT 和对应的 AUDIT_REQUEST 移到 shared/audit/processed/：
```bash
mkdir -p shared/audit/processed
for f in shared/audit/pending/VERDICT_*.md; do
  [ -f "$f" ] || continue
  id=$(basename "$f" | sed 's/VERDICT_//' | sed 's/\.md//')
  mv "$f" shared/audit/processed/
  [ -f "shared/audit/requests/AUDIT_REQUEST_${id}.md" ] && \
    mv "shared/audit/requests/AUDIT_REQUEST_${id}.md" shared/audit/processed/
done
```

## 4. PLAN
更新 MASTER_PLAN.md

## 5. ACT
决定是否签发 ORCH 指令：
- 如需签发：ORCH 文件**必须**包含 `- **状态**: PENDING` 行，否则不会被投递给 Admin
- 如不需要：不做任何动作

## 6. CONTEXT
检查 Context 剩余：
- < 10% → 保存状态到 shared/logs/CONTEXT_LOW_conductor.md → git push → 退出

## 7. SYNC
git add && git commit && git push

**Phase 2 完成。等待下一轮循环。**