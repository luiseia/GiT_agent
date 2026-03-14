# Phase 2 指令 — 读取判决 + 决策 + 行动

严格按以下步骤顺序执行，不跳过任何步骤：

## 1. PULL
git pull（获取 Critic 可能产出的 VERDICT）

## 2. RE-THINK
读取 shared/audit/pending/ 下所有 VERDICT_*.md：
- 有 → 逐个读取内容，纳入本轮决策
- 无 → 记录"无审计反馈"，基于已有信息决策

### ⚠️ 紧急停止规则（优先于一切）
读取 VERDICT 时，如果发现以下任一条件，**立即停止训练**，不需等待其他分析：
1. **FROZEN PREDICTIONS / mode collapse 确认**: Critic 判定跨样本预测一致 → 立即 kill 训练进程
2. **diff/Margin < 10%**: 图像特征无法影响决策 → 立即 kill 训练进程
3. **VERDICT 结论为 STOP**: → 立即 kill 训练进程

停止训练的方式：
```bash
# 找到训练 PID 并终止
ps aux | grep train.py | grep -v grep
kill <PID>
```
停止后记录原因到 MASTER_PLAN.md，然后继续 Phase 2 剩余步骤（ARCHIVE → PLAN → ACT）。

**绝对不要因为"等 @8000 再看"或"可能还有转机"而推迟停止。浪费 GPU 时间是不可接受的。**

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
更新 MASTER_PLAN.md（仅更新路线图/ORCH状态/BUG表格等活跃内容，历史数据归档到 shared/logs/archive/，保持 MASTER_PLAN 精简）

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