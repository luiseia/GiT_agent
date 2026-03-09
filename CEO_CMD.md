# CEO 指令

请撰写一份完整的项目进展报告，保存到 shared/logs/project_progress_report.md 并 git push。

## 报告要求

### 1. 实验历程总结
按时间线梳理从 Plan A 到当前的所有实验：
- 每个 Plan 的核心改动、起止时间、关键结果
- 每个 Plan 之间的因果关系（为什么从 A 转 B，B 转 C...）
- 标注每个阶段修复了哪些 BUG

### 2. 当前状态
- ORCH_024 Full nuScenes 训练进度和最新指标
- 4 个 GPU 的使用状态
- 所有 Agent 的当前状态
- 待处理的 ORCH 和 AUDIT

### 3. 关键决策回顾
- 列出所有重大转折点的决策及其理由
- 哪些决策被证明是正确的，哪些是错误的
- Critic 纠正了 Conductor 的哪些错误判断

### 4. BUG 完整清单
- BUG-1 到最新 BUG 的完整列表
- 每个 BUG 的当前状态、修复方式、影响评估
- 标注哪些是 Critic 发现的、哪些是 CEO 发现的、哪些是 Admin 发现的

### 5. 架构演化
- 模型架构从最初到现在的变化（投影层、DINOv3 集成、类别扩展等）
- 标签系统的变化（AABB → 旋转多边形、center/around 等）
- Loss 和优化器配置的演化

### 6. 未完成的待办
- 3D Anchor / 历史 occ box 路线图状态
- 自动化测试框架状态
- 所有 DEFERRED 的 BUG 和提案

### 7. 经验教训
- mini 数据集上学到了什么
- Agent 系统运行中发现的问题和改进
- 对后续 Full nuScenes 训练的建议

报告要详尽，预计 200-500 行。可以引用 MASTER_PLAN.md 中的数据但不要简单复制，需要加入你自己的分析和总结。

注意：这是报告任务，不需要签发 ORCH 或 AUDIT。完成后等待 Phase 2 指令。
