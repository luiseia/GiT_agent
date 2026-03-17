# Conductor 上下文快照
> 时间: 2026-03-16 20:20 CDT
> 原因: 连续 12 轮 idle cycle，保存最新快照以备新实例恢复

---

## 当前状态

- **无活跃训练**，GPU 0,2 空闲; 1,3 被 yl0826 占用
- **/mnt/SSD 100% 满（4.7GB）** — 新训练硬阻塞
- **等待 CEO 方向性决策** — 5 个候选方向 + Critic 评价就绪

## 核心问题

**marker_same 不可逆上升** — 11 轮实验 (ORCH_049-059) 全 FAIL:
- 超参数 (FG/BG, LR): 改变崩塌方向，不改模板化
- 架构微调 (dropout, 移除 grid_pos_embed): 破坏多样性/定位
- 初始化 (bias init): 改变方向，不改模板化

Critic 特征流诊断: DINOv3 图像信号 10.6% → logits 2.2% → argmax 91% 相同。
即使 ORCH_055 @100 "BORDERLINE" 也从未真正健康。

## 活跃 BUG (CRITICAL)

- **BUG-75**: grid_pos_embed shortcut — 架构级问题
- **BUG-84**: around_weight=0.0 → effective positive 极少 (ORCH_060 发现)
- **BUG-85**: 同一 cell 3 slot 输出完全相同 (ORCH_060 发现)

## 待 CEO 决策 (Critic 推荐 #3 或 #2)

1. grid_pos_embed 噪声/shuffle — MEDIUM 风险
2. 二元 marker (FG/BG) — LOW 风险，Critic 推荐
3. marker 独立 head — MEDIUM 风险，Critic 首选推荐
4. 长训练 — 🔴 不可行 (BUG-85 证据)
5. 回退 ORCH_024 架构 — LOW 风险

## 关键保留 checkpoint

- ORCH_055 iter_100 (唯一 BORDERLINE)
- ORCH_024 iter_8000 (baseline, car_R=0.718)

## 恢复指令

1. 读本文件
2. 读 MASTER_PLAN.md
3. 检查 CEO_CMD.md
4. 读 shared/audit/processed/VERDICT_HEALTH_20260316_1836.md (Critic 完整特征流诊断)
5. 读 shared/logs/report_ORCH_0316_1845_060.md (pred/target 可视化报告)
