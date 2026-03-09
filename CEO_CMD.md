# CEO 指令

两个任务：

## 任务 1：长期化 car_precision_investigation 的结论
我已阅读并认可 shared/logs/car_precision_investigation.md 中的所有判断和建议。
请将其中的关键结论、待办事项、实验计划写入 MASTER_PLAN.md 的持久追踪区域，包括但不限于：
- 单类 car 诊断实验计划（如果你已签发 ORCH 则标注状态）
- 5 类车辆方案的评估结论
- LoRA 方案的优先级和执行条件

## 任务 2：ORCH_024 架构细节报告
请撰写报告保存到 shared/logs/orch024_architecture_detail.md 并 git push。

需要回答以下问题：
1. ORCH_024 Full nuScenes 训练中，DINOv3 的哪些层是冻结的？哪些是可训练的？
2. 投影层的具体结构是什么？（Linear 维度、激活函数、有没有 LayerNorm）
3. 投影层的 lr_mult 是多少？与 backbone 其他参数的学习率比例是怎样的？
4. ViT 的哪些层是冻结的？哪些是可训练的？新增的 Layer 12-17 是什么结构？
5. 总共有多少可训练参数？多少冻结参数？各占多少比例？
6. 显存占用情况（每张 GPU 多少 GB）？
7. 当前训练进度和最新 val 结果

请直接读取 ORCH_024 使用的 config 文件和实际代码来回答，不要从记忆中猜测。如果需要 Admin 协助查看训练中的具体信息，签发 ORCH。

注意：签发 ORCH 必须包含「- **状态**: PENDING」行。
