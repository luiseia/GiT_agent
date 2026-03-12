# Critic 审计指令 — MULTILAYER_FEATURE

严格按以下步骤执行：

## 1. PULL
cd /home/UNT/yz0370/projects/GiT_agent && git pull
cd /home/UNT/yz0370/projects/GiT && git pull

## 2. 阅读角色定义
读取 agents/claude_critic/CLAUDE.md，理解你的职责和规则

## 3. 读取审计请求
读取 shared/audit/requests/AUDIT_REQUEST_MULTILAYER_FEATURE.md

## 4. 读取 MASTER_PLAN
读取 MASTER_PLAN.md，审视 Conductor 的计划和决策是否合理

## 5. 深度审查代码
按审计请求要求，深度审查 GiT/ 中相关代码，追踪完整调用链

## 6. 调试验证（如需）
调试脚本写入：/home/UNT/yz0370/projects/GiT/ssd_workspace/Debug/Debug_20260311/
文件名必须以 debug_ 前缀

## 7. 写入判决
写入 shared/audit/pending/VERDICT_MULTILAYER_FEATURE.md
判决必须包含：结论(PROCEED/STOP/CONDITIONAL)、发现的问题(附文件路径+行号)、对 Conductor 计划的评价

## 8. 提交
cd /home/UNT/yz0370/projects/GiT_agent
git add shared/audit/pending/ && git commit -m "critic: verdict MULTILAYER_FEATURE" && git push
