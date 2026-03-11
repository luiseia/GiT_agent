# Critic 审计指令 — TWO_STAGE_FILTER

严格按以下步骤执行：

## 1. PULL
cd /home/UNT/yz0370/projects/GiT_agent && git pull
cd /home/UNT/yz0370/projects/GiT && git pull

## 2. 阅读角色定义
读取 agents/claude_critic/CLAUDE.md，理解你的职责和规则

## 3. 读取审计请求
读取 shared/audit/requests/AUDIT_REQUEST_TWO_STAGE_FILTER.md

## 4. 读取 MASTER_PLAN
读取 MASTER_PLAN.md，审视 Conductor 的计划和决策是否合理

## 5. 深度审查代码
审查 GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py (commit `a64a226`):
- `_compute_valid_grid_ids()` 方法的完整逻辑
- Stage 1 (vis 过滤) 和 Stage 2 (IoF/IoB OR 过滤) 的实现
- 边界条件和兜底策略
- 与调用方的交互 (返回空 cell_ids 的影响)

## 6. 审查可视化验证
查看 GiT/ssd_workspace/VIS/final_v10_IoF30_IoB20_fullbbox/ 中的 20 张对比图
读取 GiT_agent/scripts/explore_final.py 理解验证方法

## 7. 写入判决
写入 shared/audit/pending/VERDICT_TWO_STAGE_FILTER.md
判决必须包含：
- 结论 (PROCEED/STOP/CONDITIONAL)
- 阈值合理性评估
- 发现的问题 (附文件路径+行号)
- bg_weight 是否需要调整的建议
- 对 ORCH_029 训练的预期影响

## 8. 提交
cd /home/UNT/yz0370/projects/GiT_agent
git add shared/audit/pending/ && git commit -m "critic: verdict TWO_STAGE_FILTER" && git push
