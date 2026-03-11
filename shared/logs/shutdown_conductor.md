# Conductor Context Snapshot — 2026-03-11 ~19:00
> 保存时间: 2026-03-11 ~19:00
> 触发: CEO 指令保存上下文

---

## 1. MASTER_PLAN 当前状态摘要

**当前阶段**: ORCH_029 从零重训（两阶段过滤标签）

**本次会话完成的核心工作**:
- CEO 指出 overlap 模式边缘 cell 噪声问题
- 经 5 轮迭代探索确定最终方案: `vis>=10% + (IoF>=30% OR IoB>=20%)`
- 两阶段过滤代码已合入 GiT master (commit `a64a226`)
- 20 样本可视化验证: FG -30.3%, 对象保留 96.9%, 0% IoF 丢失
- ORCH_029 已签发, AUDIT_REQUEST_TWO_STAGE_FILTER 已签发
- MASTER_PLAN 已更新 (BUG-51 v2 修复 + 下一步行动计划)

**关键里程碑**:
- ORCH_024 (center-based): 终止 @12000, baseline 数据保留
- BUG-51 v1 (overlap 无阈值): commit `ec9a035`
- BUG-51 v2 (两阶段过滤): commit `a64a226` ← 当前 master
- ORCH_028 (overlap 无阈值): 断电 kill @1180, TERMINATED
- ORCH_029 (两阶段过滤): DELIVERED, 等待 Admin 启动

**CEO 战略转向**:
- 不追求图像 grid 级 recall/precision, 主目标是 BEV box 属性
- 多余 FP/FN 通过置信度阈值或 loss 加权处理
- 图像 grid 与 2D bbox 无法完美对齐是固有限制

---

## 2. CEO 指令处理情况

**已完成的 CEO 指令** (本次会话):

CEO 原始问题: "大量只与目标2d图像box重叠了一点点的区域被设置为了前景，完全没有目标相关像素"

探索过程:
1. IoF 探索 (intersection/cell_area) → CEO 纠正: 应该是占2d框的百分比
2. IoB 探索 (intersection/bbox_area) → 发现 IoB 对大物体不公平 (100-cell 车每 cell IoB=1%)
3. 全 bbox vs 裁剪 bbox → CEO 指出出画面物体的处理
4. 两阶段 v1 (vis + IoF) → IoF 不保护小目标 (26×35 < 56×56 cell)
5. 两阶段 v2 (vis + IoF|IoB OR) → CEO 确认 v10+IoB20 好, IoF 需调
6. IoF 扫描 (10%-40%) → 确定 IoF=30% 为最佳拐点
7. IoB 分母: CEO 指出应用 full bbox (IoF 已保护大车, IoB 只管小目标)
8. 最终 20 样本可视化确认 → CEO 确认 → 直接改 GiT 代码
9. Commit + push → 签发 ORCH_029 + 审计请求

**CEO_CMD.md**: 不存在 (无新指令)

---

## 3. 已签发的 ORCH 和 AUDIT

### ORCH_029 (DELIVERED, 等待 Admin 执行)
- 文件: `shared/pending/ORCH_0311_1830_029.md`
- 内容: Full nuScenes 从零训练, 两阶段过滤标签, 4×A6000 DDP
- Config: `plan_full_nuscenes_gelu.py` (不改, 新参数走默认值)
- work-dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260311/full_nuscenes_filtered`
- 与 ORCH_024 唯一区别: 标签过滤 (min_vis=0.10, min_iof=0.30, min_iob=0.20)

### AUDIT_REQUEST_TWO_STAGE_FILTER (等待 Critic)
- 文件: `shared/audit/requests/AUDIT_REQUEST_TWO_STAGE_FILTER.md`
- Critic 指令: `shared/commands/critic_cmd.md` (已更新指向新审计)
- 审查: 阈值合理性, IoB 分母, bg_weight, 代码实现, 边界 case
- 不 block 训练启动

---

## 4. ORCH 最新进展

| ORCH | 状态 | 说明 |
|------|------|------|
| ORCH_024 | TERMINATED @12000 | center-based baseline, 数据保留 |
| ORCH_028 | TERMINATED @1180 | 断电, 无 checkpoint, 被 ORCH_029 替代 |
| ORCH_029 | **DELIVERED** | 两阶段过滤, 等待 Admin 启动 |

**ORCH_024 最终数据 (center-based baseline)**:

| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | @12000 | peak |
|------|-------|-------|-------|-------|--------|--------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | 0.081 | **0.090** |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | 0.726 | 0.526 | 0.726 |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | 0.407 | 0.278 | — |
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | 0.160 | **0.128** | **0.128** |

**GPU 状态**: 4× A6000 全部空闲, 等待 ORCH_029 启动

---

## 5. 所有未完成的待办事项

### 立即 (Admin 执行)
- [ ] Admin 执行 ORCH_029: `git pull` + 启动训练
- [ ] Supervisor 需更新监控路径指向 ORCH_029 work_dir

### 等待中
- [ ] Critic 完成 AUDIT_REQUEST_TWO_STAGE_FILTER 审计
- [ ] ORCH_029 @2000 第一次 eval → 与 ORCH_024 @2000 对比
- [ ] ORCH_029 @4000 第一个可信评估点 → 重建决策矩阵

### 中期 (训练期间可并行准备)
- [ ] Soft loss 加权方案设计 (CEO 提出: 边缘 cell 给更小的 loss 贡献)
- [ ] Deep supervision config 准备 (`loss_out_indices=[8,10,11]`, `aux_weight=0.4`)
- [ ] 置信度阈值后处理评估
- [ ] 考虑 grid_resolution_perwin=(8,8) 解决 43% cell 冲突

### 长期
- [ ] BUG-48/49/50 修复 (DINOv3 unfreeze 未生效, 遍历浪费, 显存暴增)
- [ ] BEV 范围扩展
- [ ] Attention mask 一致性 (BUG-45)

### 已作废
- ~~AUDIT_REQUEST_OVERLAP_THRESHOLD~~ → 被 TWO_STAGE_FILTER 替代
- ~~所有旧决策矩阵阈值~~ → 基于 center-based 标签, 需 ORCH_029 数据重建
- ~~ORCH_028~~ → TERMINATED

---

## 6. BUG 跟踪 (活跃)

| BUG | 严重性 | 摘要 |
|-----|--------|------|
| **BUG-51** | **CRITICAL → FIXED v2** | 两阶段过滤 commit `a64a226` |
| BUG-48 | HIGH | unfreeze_last_n 解冻末端 blocks → 完全无效 |
| BUG-49 | MEDIUM | DINOv3 遍历全 40 blocks, 只需 17 → 58% 浪费 |
| BUG-50 | MEDIUM | unfreeze 移除 no_grad → +10-15GB 显存 |
| BUG-17 | HIGH | sqrt balance ~11x bicycle 权重 |
| BUG-45 | MEDIUM | OCC head 推理 attn_mask=None vs 训练有 mask |

---

## 7. 关键文件索引

| 文件 | 说明 |
|------|------|
| `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py` | 两阶段过滤实现 (commit `a64a226`) |
| `GiT_agent/scripts/explore_final.py` | 最终可视化脚本 (20 样本, IoB full bbox) |
| `GiT_agent/scripts/explore_iof_sweep.py` | IoF 阈值扫描脚本 |
| `GiT_agent/scripts/explore_two_stage_v2.py` | 两阶段 v2 探索脚本 (OR 逻辑) |
| `GiT/ssd_workspace/VIS/final_v10_IoF30_IoB20_fullbbox/` | 最终可视化 (20 样本) |
| `GiT/configs/GiT/plan_full_nuscenes_gelu.py` | ORCH_029 训练 config |
| `GiT_agent/MASTER_PLAN.md` | 完整项目状态 |

---

## 8. 恢复指令

1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整状态
3. 检查 CEO_CMD.md 是否有新指令
4. 检查 ORCH_029 训练进度
5. 检查 Critic 审计是否完成 (`shared/audit/pending/VERDICT_TWO_STAGE_FILTER.md`)
6. 如 ORCH_029 有 eval 结果 → 与 ORCH_024 baseline 对比, 更新 MASTER_PLAN
7. 继续 Phase 1/Phase 2 循环
