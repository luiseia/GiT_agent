
---
## [2026-03-06 01:15] CEO 指令 #1
请在本轮决策中阅读以下历史文件，提取对当前优化有价值的信息：
1. `shared/logs/archive/old_critic/reports/2026-03-05/critique/` — 目录下所有审计报告
2. `shared/logs/archive/old_conductor/reports/2026-03-05/1805_CEO质询_标签分配算法.md`
勘误：Construction Vehicle 和 truck 在 nuScenes-mini 中本就独立，不需要拆分。

## [2026-03-06 01:15] CEO 指令 #2
转达 Ops：修复 usage_watchdog.sh 误报 BUG，扫描限流关键词时跳过 agent-ops。

---
## [2026-03-06 15:20] CEO 指令 #3
请在本轮决策中阅读以下历史文件，提取对当前优化有价值的信息：
1. `shared/logs/archive/old_critic/reports/2026-03-05/critique/` — BUG-1~12 审计报告
2. `shared/logs/archive/old_conductor/reports/2026-03-05/1805_CEO质询_标签分配算法.md`
勘误：Construction Vehicle 和 truck 在 nuScenes-mini 中本就独立。
**执行结果**: 深度重读完成，提取 BUG-8 代码位置、BUG-10 冷启动影响、IBW 歧视量化、理论上界等新洞察。详见 MASTER_PLAN.md 循环 #8。

---
## [2026-03-06 ~21:30] CEO 指令 #4
请避免使用1，3GPU，只使用0，2GPU
**执行结果**: 已确认 P3 训练仅使用 GPU 0,2, 完全符合要求. GPU 1,3 为 yz0364 (UniAD) 占用. 无需额外动作.

---
## [2026-03-06 ~23:30] CEO 指令 #5
VERDICT_ARCH_REVIEW 已产出。要求: 1) 阅读完整内容 2) 在 MASTER_PLAN.md 新增持久架构审计待办区域 3) 根据 P3 状态规划修复顺序并逐步签发 ORCH
**执行结果**: 已阅读 VERDICT_ARCH_REVIEW.md 全文. BUG-8/10 已在 ORCH_004 中修复验证, BUG-2 因此也已完整修复. BUG-11 待 P3 后处理. 架构优化 (方案 A/BUG-14/15) 纳入 P4 规划. MASTER_PLAN.md 已新增持久"架构审计待办"区域.

---
## [2026-03-07 02:50] CEO 指令 #6 (紧急)
批准 P4, Phase 1 + Phase 2 同时推进. GPU 限制: 只用 0,2, 可占满.
Phase 1: AABB→旋转多边形 + BUG-11 + P3@3000 恢复训练
Phase 2: DINOv3 离线预提取 Layer 16-20 为 .pt 文件
评估标准: Phase 1 后 avg_P>0.15 则 Phase 2 低优先级, avg_P<0.12 则立即集成
**执行结果**: 立即签发 ORCH_005 (Phase 1) + ORCH_006 (Phase 2), ORCH_005 已 DELIVERED.

---
## [2026-03-07 ~05:00] CEO 指令 #7
ORCH_006 Phase 2 DINOv3 预提取执行:
1. 批准 GPU 1,3 完成 DINOv3 中间层特征预提取
2. 新建 conda env Python 3.10
3. 存储预估: 先用 1 张图测试, 推算总量. 超 200 GB 只提取 1 层 (Layer 16 or 20)
4. 存储路径: /mnt/SSD/GiT_Yihao/dinov3_features/
5. GPU 1,3 仅用于本次提取, 完成后立即释放
**执行结果**: 立即签发 ORCH_007 给 Admin, 包含 4 项任务: conda env + 单图测试 + 全量提取 + 验证释放.

---
## [2026-03-08 04:38:26] CEO 指令
CEO批准双层投影: Linear(4096,1024)+GELU+Linear(1024,768), 缓解类别子空间干扰。5.3:1 压缩是结构性瓶颈, sqrt 加权无法解决

---
## [2026-03-08 05:08:19] CEO 指令
不再以recall和Precision为最高目标，也不再需要非常注意预警，我们的目标是真正设计出在完整nuscene性能表现优秀的代码，mini数据集只是为了debug

---
## [2026-03-08 06:56] CEO 指令 (DINOv3 适配+3D编码)
方案A: Linear(4096,1024)+GELU+Linear(1024,768). 方案B: DINOv3 unfreeze. 单类car mini验证. 3D空间编码路线图(历史occ box→ego轨迹→V2X). GPU 1,3调试.
**执行结果**: 签发 AUDIT_REQUEST_CEO_STRATEGY_NEXT. VERDICT: CONDITIONAL — 方案A已被ORCH_024涵盖(2048), 方案B三重否决, 方案D(历史occ box 2帧)最有前途, 等@2000再决策.

---
## [2026-03-08 18:30] CEO 指令 (架构疑问+改进思路)
5个技术问题: (1) 30 token AR解码是否car分类根因, (2) Deep Supervision, (3) Slot内Attention Mask设计, (4) 500 iter评判是否草率, (5) 要求Conductor分析后送审
**执行结果**: 签发 AUDIT_REQUEST_CEO_ARCH_QUESTIONS (Cycle #92)

---
## [2026-03-08 ~20:10] CEO 指令 (AR 序列长度归因纠正)
CEO 指出: "原始 GiT 在 COCO 检测上序列更长" 的错误说法不是 Critic 的而是 Conductor 的. Critic 已纠正 (det=5, occ=30, 6x). 但 CEO 要求重新审视 "长序列非瓶颈" 的结论.
**执行结果**: Conductor 代码验证确认 CEO 正确 (dec_length=5 vs 30). 签发 AUDIT_REQUEST_AR_SEQ_REEXAMINE. 澄清: 错误归因是 Conductor 的, 不是 Critic 的. (Cycle #94)

---
## [2026-03-08 ~21:15] CEO 指令 (AR Slot 内错误传播纠正)
CEO 指出: Conductor 说"错误不跨 cell 传播"是对的, 但同一 cell 内 3 层 slot 会从 Slot 1 (最近层) 传播到 Slot 3 (最远层). AR 30 token 的 within-cell exposure bias 应被验证. 等待 per-slot 验证结果.
**执行结果**: CEO 观察正确. Conductor 之前的表述不够精确 — "per-cell 并行, 错误不跨 cell" 掩盖了 cell 内 Slot1→2→3 的串行错误传播. 这正是 per-slot 指标提取 (方案 A) 要验证的目标. 已纳入决策. (Cycle #96)

---
## [2026-03-08 ~23:57] CEO 指令 (自动化测试框架)
签发 ORCH 给 Admin 创建 pytest 测试框架 (GiT/tests/): test_config_sanity.py (config 验证, 防 BUG-42), test_eval_integrity.py (eval 指标正确性, 防 BUG-12), test_label_generation.py (标签生成, 防 AABB regression), test_training_smoke.py (10 iter 微训练验证). 输出路径 /home/UNT/yz0370/projects/GiT/ssd_workspace/test_outputs/.
**执行结果**: 签发 ORCH_025 给 Admin. (Cycle #101)

---
## [2026-03-09 ~01:55] CEO 指令 (完整项目进展报告)
要求撰写 200-500 行的完整项目进展报告, 涵盖: 实验历程、当前状态、关键决策回顾、BUG 完整清单、架构演化、未完成待办、经验教训. 保存到 shared/logs/project_progress_report.md.
**执行结果**: 报告撰写完成. (Cycle #105)

---
## [2026-03-09 ~03:00] CEO 指令 (Car Precision 调查 5 项)
调查: (1) 设计干净单类 car 实验 (2) 5 类车辆方案评估 (3) 特征漂移深度分析 (4) ORCH_024 进展 (5) 行动建议.
**执行结果**: 调查报告已写入 shared/logs/car_precision_investigation.md. 设计 Plan Q (保持 num_vocal=230, 数据管道过滤, 避免 BUG-27). 签发 ORCH_026. (Cycle #107)

---
## [2026-03-09 ~04:20] CEO 指令 (双任务: 长期化结论 + 架构报告)
任务 1: 将 car_precision_investigation.md 关键结论写入 MASTER_PLAN 持久追踪区域 (Plan Q/5 类/LoRA/特征漂移).
任务 2: 撰写 ORCH_024 架构详细报告 (DINOv3 冻结/投影层/LR/ViT 层/参数量/显存).
**执行结果**: 任务 1 写入 MASTER_PLAN "持久追踪: Car Precision 调查结论" 区域. 任务 2 写入 shared/logs/orch024_architecture_detail.md. (Cycle #110)

---
## [2026-03-09 ~04:50] CEO 指令 (Val 数据集调查)
问题: 训练 val 用的是跟 train 一样的数据集吗?
**执行结果**: 不同。Train 28,130 samples (700 scenes) vs Val 6,019 samples (150 scenes), 零重叠, 标准 nuScenes 官方分割. 报告写入 shared/logs/val_dataset.md. (Cycle #111)

---
## [2026-03-09 ~07:45] CEO 指令 (选项 A + OOM 风险)
CEO 选择选项 A: 让 Plan Q 跑完. 询问 OOM 风险.
**执行结果**: OOM 报告写入 shared/logs/oom.log. GPU 1 实际未 OOM, Plan Q ~5h 后正常完成退出. (Cycle #117)

---
## [2026-03-09 ~16:40] CEO 指令 (决策矩阵 + DINOv3 解冻策略)
两个调查:
1. @10000 决策矩阵 peak_car_P 阈值是否太低? 参考 BEVFormer/PETR, 合理标准是什么?
2. DINOv3 解冻重新评估: (a) 部分解冻可行性 + 显存, (b) Layer 16 选择是否正确, (c) LoRA vs 部分解冻
**执行结果**: 完整报告写入 shared/logs/decision_matrix_and_dinov3_review.md. 发现 BUG-48 (unfreeze_last_n 无效) + BUG-49 (58% 计算浪费). 签发 AUDIT_REQUEST_DINOV3_LAYER_AND_UNFREEZE. 提出分阶段阈值 (@17000 > 0.15, @25000 > 0.20, @40000 > 0.25). (Cycle #138)

---
## [2026-03-11 16:14:06] CEO 指令
我觉得应该设置红框与图像grid的重合超过红框的百分之多少？这个grid某一个slot才能算是正样本。审计一下写个报告

---
## [2026-03-12 ~04:15] CEO 指令
为什么BUG-52 ACCEPTED IoF/IoB 死代码, convex hull 等效, 不修复能ACCEPTED，不修复？立刻给我一个report放到shared/logs/reports里。
**执行结果**: 报告写入 shared/logs/reports/bug52_iof_iob_analysis.md。核心原因：Critic 审计定量验证 convex hull 与 IoF/IoB 效果等价（差异 0.1%），修复成本>收益，当前行为无危害。

---
## [2026-03-12 ~04:45] CEO 指令
我不确定Convex hull真的等效，所以我要求部署新的过滤方式Stage 2 的 IoF/IoB 过滤。必须修改，因此之前的实验可能要重做
**执行结果**: 已修复 BUG-52。在 convex hull 分支内追加 IoF/IoB 双重过滤 (`generate_occ_flow_labels.py` L387-401)。当 `min_iof>0 or min_iob>0` 时，cell 必须同时通过 convex hull center-check 和 IoF≥0.30 OR IoB≥0.20。向后兼容：无 IoF/IoB 参数时行为不变。ORCH_033 需要基于此修复重启训练。
