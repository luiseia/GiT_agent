# Conductor 工作上下文快照
> 保存时间: 2026-03-09 ~20:30
> 循环: #146 Phase 2 完成
> 状态: BUG-51 FIXED, @12000 val 正在进行, 等结果后决策重启

---

## ★★★★★ BUG-51: Grid 分辨率过粗 — FIXED (Cycle #141-#143)

**根因**: `generate_occ_flow_labels.py:312-315` center-based 分配, 20×20 grid 每 cell 56×56px, 物体投影 <56px → 零 cell (兜底仅给 1 cell)

**修复**: `grid_assign_mode='overlap'` — 任何与投影有重叠的 cell 都分配
- GiT commit `ec9a035` (代码), `996813e` (config)
- 复现脚本: `scripts/repro_bug51.py`, 验证脚本: `scripts/verify_bug51_fix.py`
- 效果: 30px 行人 1→4 cells, 零 cell 率 21.1%→0%, 平均 cell 覆盖 +100%

**可视化**:
- `VIS/bug51_fix/` — 10 张 center vs overlap 对比 (左=旧, 右=新)
- `VIS/enhanced/` — 10 张增强版: cell 冲突热力图 + BEV 俯视 GT box

**新发现 — cell 冲突问题**:
- overlap 修复后, 平均 **43% 的 occupied cells 有多物体竞争** (2+ 物体共享同一 cell)
- 样本 #8 冲突率高达 76.5% (25 物体, 51 cells, 39 冲突)
- 根因: 20×20 grid 太粗, 远距离物体在图像上堆叠
- 进一步支持 `grid_resolution_perwin=(8,8)` 提升到 40×40

**BEV 范围分析** (CEO 提问):
- 当前 BEV [-50,50]m **不过滤 GT** — 50m 外物体仍参与 image grid 训练
- 但 BEV 回归目标被 clip 到边界 → 远距离物体 BEV offset 不准
- 扩展 BEV 范围优先级低于 grid 分辨率提升

---

## 当前状态

### ORCH_024 训练
- iter **~11880/40000** (29.7%), 速度 ~6.3 s/iter
- **@12000 val 正在触发** (~20:31), 预计 ~21:30 完成
- @15000 LR decay ETA ~3/10 06:00
- @17000 硬性 deadline ETA ~3/10 10:00
- 纯背景 batch (reg=0) 频率升高 (最近 15 iter 中 4 次, 之前 ~1/50) — BUG-51 表征
- Config: `plan_full_nuscenes_gelu.py`
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu`

### Full nuScenes Val 历史 (5 eval, @12000 进行中)
| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | peak | 趋势 |
|------|-------|-------|-------|-------|--------|------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | **0.090** | 振荡, peak 未突破 |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | **0.726** | 0.726 | ✅ 持续攀升 |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | **0.407** | — | ⚠️ 系统性恶化 |
| off_th | 0.174 | **0.150** | 0.169 | **0.140** | 0.160 | **0.140** | 振荡 |

### Full nuScenes Config
```python
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))
在线 DINOv3 frozen, ViT-7B fp16, Layer 16
max_iters = 40000, warmup = 2000, milestones = [15000, 25000]
accumulative_counts = 4, effective batch = 32
num_vocal = 230, 10 classes, sqrt balance, bg_weight = 2.5
number_win = 5, grid_resolution_perwin = (4, 4)
grid_assign_mode = 'overlap'  # BUG-51 fix (下次训练生效)
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

**@17000 硬性 deadline** (可能已被 BUG-51 修复 supersede):
- peak < 0.12 或 bg_FA > 0.40 → 启动 deep supervision
- peak > 0.12 且 bg_FA < 0.40 → 继续到 @25000

---

## 本轮 (#141-#146) 已完成

- **BUG-51 FIXED**: overlap-based grid assignment (GiT commits ec9a035, 996813e)
- **BUG-51 可视化**: VIS/bug51_fix/ (10 张对比), VIS/enhanced/ (10 张冲突+BEV)
- **Cell 冲突量化**: 平均 43% cells 有多物体竞争
- **BEV 范围分析**: [-50,50]m 不过滤 GT, 扩展优先级低
- **MASTER_PLAN 更新**: BUG-51 记录, 活跃任务状态更新

---

## 活跃任务

| ID | 状态 |
|----|------|
| **ORCH_024** | IN PROGRESS — ~11880/40000 (29.7%), @12000 val 进行中 |
| ORCH_001-023, 025-027 | 全部 COMPLETED |

---

## BUG 跟踪 (活跃)

| BUG | 严重性 | 摘要 |
|-----|--------|------|
| **BUG-51** | **CRITICAL → FIXED** | Grid 20×20, overlap-based 修复. Cell 冲突率 43% 待解决 (需 8×8 grid) |
| BUG-48 | HIGH | unfreeze_last_n 解冻末端 blocks → 完全无效 |
| BUG-49 | MEDIUM | DINOv3 遍历全 40 blocks, 只需 17 → 58% 浪费 |
| BUG-50 | MEDIUM | unfreeze 移除 no_grad → +10-15GB 显存 |
| BUG-17 | HIGH | sqrt balance ~11x bicycle 权重, 不影响 car_P |
| BUG-47 | MEDIUM | 决策矩阵已修正为 peak_car_P |

---

## 待办 (按优先级)

1. **★★★ @12000 val 结果** (~21:30): 收集旧标签 baseline → 决策是否终止 ORCH_024
2. **ORCH_028 签发**: BUG-51 修复后重启训练 (grid_assign_mode='overlap')
3. **考虑 grid_resolution_perwin=(8,8)**: 解决 43% cell 冲突 (需评估 OCC head 影响)
4. **Deep supervision**: aux_weight=0.4, 一行改动
5. **BUG-48/49/50 修复**: ORCH_024 后
6. **Layer 验证实验**: layers [12,16,20,24,28]
7. **BEV 范围扩展**: 低优先级, 在 grid 分辨率稳定后

---

## 优先级排序

| 排名 | 提案 | 备注 |
|------|------|------|
| **1** | **BUG-51 overlap 训练验证** | ORCH_028, 最底层标签质量修复 |
| **2** | **grid_resolution (8,8)** | 40×40 grid, 解决冲突率 43%, 需检查 OCC head 兼容性 |
| 3 | Deep Supervision | 一行改动, 可与 overlap 同时启用 |
| 4 | Layer 24 验证 | BUG-48 修复后 |
| 5 | 方案 D (历史 occ box 2帧) | ORCH_024 后 |
| 6 | 方案 E (LoRA) | 缓解 BUG-15 |
| 7 | BEV 范围扩展 | 等 grid 分辨率稳定后 |

---

## 关键代码位置

- **BUG-51 修复**: `generate_occ_flow_labels.py:313-322` (overlap vs center mode)
- **BUG-51 config**: `single_occupancy_base_front.py:285` (grid_assign_mode='overlap')
- **BUG-48 Unfreeze**: `vit_git.py:L151-159`
- **BUG-49 前向浪费**: `vision_transformer.py:L270-284`
- Deep Supervision: `git.py:L386-388` → `loss_out_indices=[8,10,11]`
- OCC head mask: `git_occ_head.py:L1116` → `attn_mask=None`
- Token layout: 0-167(bins) + 168-177(cls) + 178(bg) + 179-182(markers) + 183-218(θ_G) + 219-228(θ_F) + 229(ignore) = 230

## 实验教训
- 每次只改一个变量 (BUG-27/28)
- vocab 变化 = 实验无效 (BUG-27/31)
- 不读代码就估算 = BUG (BUG-43)
- Mini car_P 天花板 ~0.12-0.13, 不再跑 Mini
- eval 需参考振荡周期, 不做单点决策 (BUG-47)
- 类竞争无关 car_P, 多类正迁移 (ORCH_026)
- **可视化脚本注意**: use_rotated_polygon=False 在训练中, polygon_uv=None (纯 AABB)
- **BEV 范围不过滤 GT**, 只影响 BEV 回归目标归一化

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整状态
3. 检查 CEO_CMD.md
4. **收集 @12000 val 结果** → 决策是否终止 ORCH_024 并签发 ORCH_028
5. 继续 Phase 1/Phase 2 循环
