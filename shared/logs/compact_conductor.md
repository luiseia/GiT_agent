# Conductor 工作上下文快照
> 保存时间: 2026-03-09 ~19:30
> 循环: #141 Phase 2 完成
> 紧急: BUG-51 (CRITICAL) 刚发现, 等 CEO 决策

---

## ★★★★★ BUG-51: Grid 分辨率过粗 — 35.5% 物体零 cell 分配 (CRITICAL)

**发现过程**: CEO 指示可视化完整 nuScenes 10 个随机样本 → 观察到大量有人有车的 grid 被分配为负样本 → Conductor 代码分析+数据量化确认。

**根因** (`generate_occ_flow_labels.py:284-361`):
- 配置: `number_win=5, grid_resolution_perwin=(4,4)` → 20×20 fine grid → 每 cell **56×56 像素**
- 分配逻辑: center-based (cell 中心必须在投影内才算 — L312-315)
- 物体投影 < 56px 时, `c_start > c_end` → 零 cell

**500 帧采样统计**:
- **70.1%** 可见物体投影 < 56px (不足一个 cell)
- **35.5%** 物体获得零 cell (AABB 模式)
- 兜底机制 (L354-360) 只给 1 cell, 但覆盖率仍严重不足

**影响**:
1. 有物体的 cell 被标为背景 → 模型正确检测被惩罚为 FP → **car_P 天花板**
2. DINOv3 看到物体但 GT 说背景 → **训练信号冲突** → bg_FA 膨胀
3. **可能是所有性能问题的最底层根因**, 超过 deep supervision/layer/unfreeze 的重要性

**潜在修复方案** (待 CEO 决策):
1. `grid_resolution_perwin=(8,8)` → 40×40, 每 cell 28px — 覆盖率大幅提升
2. 改用 overlap-based 分配 (cell 与投影有重叠就算, 非要求中心在内)
3. 距离感知 padding

**可视化证据**: `/home/UNT/yz0370/projects/GiT/ssd_workspace/VIS/10sample/` (10 张图)

---

## 当前状态

### ORCH_024 训练
- iter ~10780/40000 (27%), 速度 ~6.3 s/iter, 正常巡航
- @12000 val ETA ~20:30 今晚
- @15000 LR decay (milestones=[15000,25000]) ETA ~3/10 06:00
- @17000 硬性 deadline ETA ~3/10 10:00
- 训练完成 @40000 ETA ~3/12 03:00
- Config: `plan_full_nuscenes_gelu.py`, Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu`

### Full nuScenes Val 历史 (5 eval)
| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | peak | 趋势 |
|------|-------|-------|-------|-------|--------|------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | **0.090** | 振荡, peak 未突破 |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | **0.726** | 0.726 | ✅ 持续攀升 |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | **0.407** | — | ⚠️ 系统性恶化 |
| off_th | 0.174 | **0.150** | 0.169 | **0.140** | 0.160 | **0.140** | 振荡 |

### @10000 新发现
- CV=0.287, motorcycle=0.126 首次出现 (6 类车辆激活)
- pedestrian=0.000 消失
- 振荡 3 种模式: 广泛(5类) → 窄(2类) → 车辆(6类)

### Full nuScenes Config
```python
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))
在线 DINOv3 frozen, ViT-7B fp16, Layer 16
max_iters = 40000, warmup = 2000, milestones = [15000, 25000]
accumulative_counts = 4, effective batch = 32
num_vocal = 230, 10 classes, sqrt balance, bg_weight = 2.5
number_win = 5, grid_resolution_perwin = (4, 4)  # ← BUG-51 根因!
参数: ~180M 可训练, ~7B 冻结
```

---

## VERDICT 判决汇总 (仍有效)

| ID | 判决 | 关键结论 |
|----|------|---------|
| FULL_10000 | CONDITIONAL | 等 LR decay @15000, @17000 硬性 deadline |
| DINOV3_LAYER_AND_UNFREEZE | CONDITIONAL | BUG-48/49/50! Layer 24 推荐 |
| FULL_8000 | CONDITIONAL | BUG-47 修正决策矩阵用 peak |
| CEO_ARCH_QUESTIONS | CONDITIONAL | Deep Supervision 零成本 #1 |
| ORCH026_PLANQ | PROCEED | 类竞争无关! 多类正迁移 |

**@17000 硬性 deadline**:
- peak < 0.12 或 bg_FA > 0.40 → 启动 deep supervision (aux_weight=0.4)
- peak > 0.12 且 bg_FA < 0.40 → 继续到 @25000

**分阶段阈值**: @10000>0.08 ✅, @20000>0.12, @25000>0.20, @40000>0.25

---

## 本轮已完成

- **MASTER_PLAN 清理**: 1260→787 行 (-37%)
- **paper_gap_assessment.md**: NeurIPS 2026 差距评估 (10-12 周工作)
- **ORCH_027 COMPLETED**: VIS/polygon_viz/ (323张迁移) + VIS/10sample/ (10张新)
- **BUG-51 发现+量化**: 35.5% 物体零 cell, 70.1% 投影不足一格

---

## 活跃任务

| ID | 状态 |
|----|------|
| **ORCH_024** | IN PROGRESS — 10780/40000 (27%), @12000 ETA ~20:30 |
| ORCH_001-023, 025-027 | 全部 COMPLETED |

---

## BUG 跟踪 (活跃)

| BUG | 严重性 | 摘要 |
|-----|--------|------|
| **BUG-51** | **CRITICAL (NEW)** | Grid 20×20, 35.5% 物体零 cell, 70.1% 投影<56px |
| BUG-48 | HIGH | unfreeze_last_n 解冻末端 blocks → 完全无效 |
| BUG-49 | MEDIUM | DINOv3 遍历全 40 blocks, 只需 17 → 58% 浪费 |
| BUG-50 | MEDIUM | unfreeze 移除 no_grad → +10-15GB 显存 |
| BUG-17 | HIGH | sqrt balance ~11x bicycle 权重, 不影响 car_P |
| BUG-47 | MEDIUM | 决策矩阵已修正为 peak_car_P |

---

## 待办 (按优先级)

1. **★★★ BUG-51 CEO 决策**: 是否修复 grid 分辨率 (可能需要重新设计+重启训练)
2. **@12000 val (~20:30)**: 收集数据
3. **ORCH_025 deep supervision config**: 提前准备
4. **@17000 hard deadline (~3/10 10:00)**: peak<0.12 或 bg_FA>0.40 → deep supervision
5. **BUG-48/49/50 修复**: ORCH_024 完成后
6. **Layer 验证实验**: layers [12,16,20,24,28]

---

## 优先级排序 (BUG-51 后需重评)

| 排名 | 提案 | 备注 |
|------|------|------|
| **0** | **BUG-51 Grid 分辨率修复** | ★ 最底层标签质量问题, 可能超越所有其他优化 |
| 1 | Deep Supervision (一行改动) | ORCH_024 后 |
| 2 | Layer 24 验证 | BUG-48 修复后 |
| 3 | 方案 D (历史 occ box 2帧) | ORCH_024 后 |
| 4 | 方案 E (LoRA) | 缓解 BUG-15 |
| 5 | BUG-17 修复 | 不影响 car_P |

---

## 关键代码位置

- **BUG-51 Grid 分配**: `generate_occ_flow_labels.py:284-361` (center-based, 兜底 L354-360)
- **BUG-48 Unfreeze**: `vit_git.py:L151-159` (解冻末端 blocks)
- **BUG-49 前向浪费**: `vision_transformer.py:L270-284` (遍历全 40 blocks)
- Deep Supervision: `git.py:L386-388` → `loss_out_indices=[8,10,11]`
- OCC head mask (BUG-45): `git_occ_head.py:L1116` → `attn_mask=None`
- Proj 层: `vit_git.py:L166-171`
- Token layout: 0-167(bins) + 168-177(cls) + 178(bg) + 179-182(markers) + 183-218(θ_G) + 219-228(θ_F) + 229(ignore) = 230

## 实验教训
- 每次只改一个变量 (BUG-27/28)
- vocab 变化 = 实验无效 (BUG-27/31)
- 不读代码就估算 = BUG (BUG-43)
- Mini car_P 天花板 ~0.12-0.13, 不再跑 Mini
- eval 需参考振荡周期, 不做单点决策 (BUG-47)
- 类竞争无关 car_P, 多类正迁移 (ORCH_026)

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整状态
3. 检查 CEO_CMD.md
4. **优先处理 BUG-51 CEO 决策**
5. 继续 Phase 1/Phase 2 循环
