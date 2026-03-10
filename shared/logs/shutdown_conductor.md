# Conductor 紧急关机快照
> 保存时间: 2026-03-09 ~23:15
> 循环: #152 Phase 2 完成
> 触发: CEO 紧急关机指令

---

## ★ 当前核心状态

### ORCH_028: Full nuScenes overlap-based 重训练 — IN PROGRESS
- **进度**: ~920/40000 (2.3%), warmup 阶段
- **PID**: 1220551 (4 GPU DDP)
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260309/full_nuscenes_overlap`
- **Config**: `configs/GiT/plan_full_nuscenes_gelu.py`
- **唯一改变**: `grid_assign_mode='overlap'` (BUG-51 fix)
- **LR**: 1.15e-6 (warmup 中, 目标 2.5e-6 @2000)
- **显存**: 28849 MB/GPU, 速度 ~6.2-6.5 s/iter
- **reg=0 频率**: 7.7% (5/65 采样) — vs ORCH_024 的 28.6%, 改善 73%
- **@2000 val ETA**: ~3/10 01:00

### ORCH_024: TERMINATED @12000
- 作为 center-based baseline 存档
- Work dir 保留: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu`

---

## @12000 Val 结果 (ORCH_024 最终 baseline)

| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | @12000 | peak |
|------|-------|-------|-------|-------|--------|--------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | **0.081** | **0.090** |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | 0.726 | 0.526 | 0.726 |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | **0.407** | **0.278** | — |
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | 0.160 | **0.128** | **0.128** |
| off_cx | 0.056 | 0.039 | 0.056 | 0.045 | — | **0.038** | **0.038** |

**⚠️ 以上数据基于 center-based 标签 (BUG-51), 不可与 overlap 训练直接对比**

---

## 关键决策记录

### VERDICT_12000_TERMINATE (Critic, Cycle #148): PROCEED
- 终止 ORCH_024, 从零启动 ORCH_028
- 理由: BUG-51 是标签级缺陷, 35.5% 物体被错标为背景
- 必须从零开始 (标签分布根本改变, sqrt balance 权重重算)
- 所有旧决策矩阵阈值作废, ORCH_028 @4000 后重建
- ORCH_028 只改标签 (overlap), 其他参数完全一致 (单一变量对照)

### Critic 关键洞察
1. offset 指标基线会变 — overlap 给更多 cell, 边缘 cell offset 更大, 不代表退化
2. bg_weight=2.5 先不调 — 正样本率变化后观察 bg_FA 再决策
3. BUG-51 可能是 car_P 天花板 + bg_FA 膨胀的最底层根因

---

## ORCH_028 关键对比点

| checkpoint | 对比内容 | ETA |
|------------|---------|-----|
| **@2000** | overlap 即时效果 vs ORCH_024 @2000 (car_P 0.079, bg_FA 0.222) | **~3/10 01:00** |
| @6000 | 是否突破 car_P=0.090 旧天花板 | ~3/10 08:00 |
| @12000 | 同进度完整对比 | ~3/10 18:00 |

---

## BUG-51 修复验证

- **代码**: GiT commit `ec9a035` (generate_occ_flow_labels.py), `996813e` (config)
- **效果**: center→overlap, 零 cell 率 21.1%→0%, 平均 cell 覆盖 +100%
- **训练验证**: reg=0 频率 28.6%→7.7%, 改善 73%
- **Cell 冲突**: 平均 43% occupied cells 有多物体竞争 (待 grid_resolution (8,8) 解决)

---

## 活跃任务

| ID | 状态 |
|----|------|
| **ORCH_028** | IN PROGRESS — ~920/40000, warmup, @2000 val ~01:00 |
| ORCH_024 | TERMINATED @12000, baseline 存档 |

---

## BUG 跟踪 (活跃)

| BUG | 严重性 | 摘要 |
|-----|--------|------|
| **BUG-51** | **CRITICAL → FIXED** | Grid overlap 修复, ORCH_028 验证中 |
| BUG-48 | HIGH | unfreeze_last_n 解冻末端 blocks → 完全无效 |
| BUG-49 | MEDIUM | DINOv3 遍历全 40 blocks, 只需 17 → 58% 浪费 |
| BUG-50 | MEDIUM | unfreeze 移除 no_grad → +10-15GB 显存 |
| BUG-17 | HIGH | sqrt balance ~11x bicycle 权重, 不影响 car_P |

---

## 待办 (按优先级)

1. **★★★ 收集 ORCH_028 @2000 val** (~01:00): 与 ORCH_024 @2000 对比, 量化 overlap 效果
2. **ORCH_028 @4000 后重建决策矩阵**: 新 baseline 校准
3. **考虑 grid_resolution_perwin=(8,8)**: 解决 43% cell 冲突 (ORCH_028 稳定后)
4. **Deep supervision**: aux_weight=0.4, 一行改动
5. **BUG-48/49/50 修复**: Layer 24 验证
6. **BEV 范围扩展**: 低优先级

---

## CEO 已批准优先级

1. 先验证 BUG-51 overlap fix 训练效果 (ORCH_028) ← 进行中
2. 再考虑 grid_resolution_perwin=(8,8)
3. BEV 范围扩展在上述两项稳定后

---

## Supervisor 告警

- Supervisor 报告停滞在 Cycle #227 (仍报告已终止的 ORCH_024)
- 可能需要更新监控路径指向 ORCH_028 work_dir
- 不影响训练, 低优先级

---

## 关键代码位置

- **BUG-51 修复**: `generate_occ_flow_labels.py:313-322`
- **BUG-51 config**: `single_occupancy_base_front.py:285`
- **BUG-48 Unfreeze**: `vit_git.py:L151-159`
- **Deep Supervision**: `git.py:L386-388` → `loss_out_indices=[8,10,11]`
- **OCC head mask**: `git_occ_head.py:L1116` → `attn_mask=None`

## 恢复指令

1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整状态
3. 检查 CEO_CMD.md
4. 检查 ORCH_028 训练进度 (`tail /mnt/SSD/GiT_Yihao/Train/Train_20260309/full_nuscenes_overlap/*.log`)
5. 如 @2000 val 已完成 → 收集结果, 与 ORCH_024 @2000 对比
6. 继续 Phase 1/Phase 2 循环
