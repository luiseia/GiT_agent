# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-12 ~17:55
>
> **归档索引**: 历史 VERDICT/训练数据/架构审计详情 → `shared/logs/archive/verdict_history.md`
> **归档索引**: 指标参考/历史决策日志 → `shared/logs/archive/experiment_history.md`

---

## CEO 战略方向

- **目标**: 设计出在完整 nuScenes 上性能优秀的代码。mini 数据集仅用于 debug
- 图像 grid 与 2D bbox 无法完美对齐是固有限制。主目标是 **BEV box 属性**
- 周边 grid 的 FP/FN 通过置信度阈值或 loss 加权处理
- **不再以 Recall/Precision 为最高目标，不再高度预警红线**

---

## 当前阶段: ORCH_035 等待 Admin 执行 (Label Pipeline 大修)

### ⭐ ORCH_035 Label Pipeline 改动清单

CEO 亲自审核并确认的 5 项 label 生成改动 (GiT commit `80b1e23`):

| # | 改动 | 原因 | BUG |
|---|------|------|-----|
| 1 | **BUG-19v3 z-fix**: z = box BOTTOM (mmdet3d) | 修复前车辆只覆盖下半部分 cell | BUG-19v3 |
| 2 | **Convex hull 替代 AABB** | AABB 对斜角车辆过大 ~25% | — |
| 3 | **IoF/IoB 对 hull 多边形计算** (Sutherland-Hodgman) | 对 AABB 计算 IoF 永远 ~1.0, 过滤失效 | BUG-52v2 |
| 4 | **filter_invisible=False** | nuScenes vis_token 过滤误杀可见车辆 | — |
| 5 | **vis + cell_count 组合过滤** | 纯 vis<10% 误杀 29-cell 大目标 | — |

### 最终 config 参数
```python
filter_invisible=False,
use_rotated_polygon=True,        # convex hull
min_vis_ratio=0.10,              # vis < 10% 且 cells < 6 才过滤
min_vis_cell_count=6,            # vis 低但占 >=6 cell 的大目标保留
min_iof=0.30,                    # IoF/IoB 对 hull polygon 计算
min_iob=0.10,
grid_assign_mode='overlap',
```

### 训练计划
- **Resume from ORCH_034@4000** (backbone/projection 有效, head 适应新标签)
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- 评估点: @8000 (从 resume 算 @4000 新 iter)

### ORCH_034 eval 参考 (修复前标签, 仅供对比)

| 指标 | ORCH_034 @2000 | ORCH_034 @4000 |
|------|---------------|---------------|
| car_R | 0.8124 | 0.8195 |
| car_P | 0.0571 | 0.0451 |
| bg_FA | 0.2073 | 0.3240 |
| off_th | 0.1655 | 0.1598 |

> 注: ORCH_034 使用旧 label pipeline (BUG-19v3 未修, AABB IoF/IoB, filter_invisible=True)。数值不直接可比。

## 实验路线图

| 阶段 | 时间 | 实验 | 内容 | 决策依据 |
|------|------|------|------|---------|
| ✅ | 03/11 23:15 | ORCH_029 @2000 | bg_FA -27%, off_th -17% | 标签改进确认 |
| ❌ | 03/12 ~04:00 | ORCH_032 @2000 | 全面坍缩 | BUG-57/58/59/60 |
| ✅ | 03/12 09:47 | ORCH_034 @2000 | car_R=0.8124, bg_FA=0.2073 | 多层特征方向正确 |
| ✅ | 03/12 14:18 | ORCH_034 @4000 | car_R=0.82, 4类激活 | Critic: PROCEED |
| **当前** | 03/12 17:50 | ORCH_035 | Label pipeline 大修 + resume 034@4000 | DELIVERED |
| **里程碑 6** | ~03/13 | ORCH_035 @8000 | 新标签效果评估 | 重点: car_P 改善, bg_FA |

### @8000 决策树

```
ORCH_035 @8000 (新 label pipeline):
│
├─ car_P > 0.08 + bg_FA < 0.35 → ★ 标签+特征双重改进成功
│
├─ car_P > 0.06 → 进步中, 继续训练到 LR decay
│
├─ car_P 不变 (~0.045) → 标签改进未传导到 precision, 分析原因
│
└─ car_P 下降 → z-fix 可能改变 recall/precision 平衡, 检查 recall
```

---

## 关键发现

### ★★★★★ Label Pipeline 大修 (2026-03-12, CEO 亲审)

CEO 对 label generation pipeline 逐项审查, 发现多个问题:
- BUG-19v3: z-convention 错误导致所有车辆只有下半部分被覆盖
- IoF/IoB 对 AABB 计算完全无效 (hull 内部 IoF ≈ 1.0)
- filter_invisible 误杀可见度 0-40% 的车辆 (与自有 vis_ratio 重复)
- 纯 vis < 10% 对画面内大目标过于激进
- 详细可视化: `ssd_workspace/Debug/progressive_filter/`

### ★★★★★ DINOv3 多层特征 (2026-03-11, CEO 论文分析)

> 详细分析: `shared/logs/reports/dinov3_paper_analysis.md`

- 论文 4/4 下游任务都用 **[10,20,30,40] 四层拼接** (16384维)
- Layer 16 在几何任务上远未达峰 (Layer 30-35 最优)
- ORCH_034 验证: car_R 0→0.81, 4 个新类别激活

### BUG-51 标签修复 (overlap + vis filter)

- center-based 分配导致 35.5% 物体零 cell, 是 car_P 天花板根因之一
- overlap + vis + convex hull 修复 (commits `ec9a035`, `a64a226`)
- ORCH_029 @2000 验证: bg_FA -27%, off_th -17%

### ORCH_024 baseline 数据 (center-based, 已终止 @12000)

| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | @12000 | peak |
|------|-------|-------|-------|-------|--------|--------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | 0.081 | **0.090** |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | 0.726 | 0.526 | 0.726 |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | 0.407 | 0.278 | — |
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | 0.160 | **0.128** | **0.128** |

### 实验评判规则 (永久)

1. 单次 eval 变化 <5%: 不做决策，标记"波动"
2. 单次 5-15%: 需下一个 eval 同向确认
3. 连续 2 次同向 >5%: 可做结论
4. Mini 永远不做架构决策
5. Full: @2000 仅趋势参考, @4000 第一可信点, @8000 架构决策
6. 振荡训练用 peak_car_P (最近 3-eval 峰值) 而非单点 (BUG-47)

---

## ORCH 状态

| ID | 目标 | 状态 |
|----|------|------|
| ORCH_024 | Full nuScenes center-based baseline | TERMINATED @12000 |
| ORCH_029 | Full nuScenes overlap + vis + convex hull | STOPPED @2000 |
| ORCH_034 | 多层 + BUG-52 IoF/IoB + BUG-57/58/59/60 修复 | STOPPED @4000, ckpt 保留 |
| **ORCH_035** | **Label pipeline 大修 + resume 034@4000** | **DELIVERED, 等 Admin** |
| ORCH_030 | 多层特征代码实现 | ✅ DONE (commit `8a961de`) |
| ORCH_031 | BUG-54/55 修复 | ✅ DONE (commit `dba4760`) |

已完成归档: ORCH_001-033 (详见 `shared/logs/archive/verdict_history.md`)

---

## BUG 跟踪

### 活跃 BUG

| BUG | 严重性 | 摘要 |
|-----|--------|------|
| **BUG-17** | HIGH | bicycle sqrt balance ~11x 权重, 不影响 car_P 但导致 bg_FA 膨胀/振荡 |
| **BUG-45** | MEDIUM | OCC head 推理 attn_mask=None vs 训练有 mask, 不一致 |
| **BUG-48** | HIGH | unfreeze_last_n 解冻 blocks 38-39 但 layer 16 不受影响, 梯度不流经 |
| **BUG-49** | MEDIUM | DINOv3 遍历全 40 blocks 但只需前 17 个, 浪费 58% |
| **BUG-50** | MEDIUM | unfreeze 时移除 no_grad, 全部 40 blocks 构建计算图, +10-15GB |

### 已修复 BUG (本轮)

| BUG | 修复 |
|-----|------|
| BUG-19v3 | z = box BOTTOM, corners z ∈ [z, z+h] (commit `80b1e23`) |
| BUG-51v2 | overlap + vis + convex hull |
| BUG-52v2 | IoF/IoB 对 hull polygon 计算 (Sutherland-Hodgman) (commit `80b1e23`) |
| BUG-57 | proj lr_mult=5.0 |
| BUG-58 | load_from=ORCH_029@2000 |
| BUG-59 | proj 4:1 compression |
| BUG-60 | clip_grad=30.0 |

### 已关闭 BUG (BUG-2~46, 详见 `shared/logs/archive/verdict_history.md`)

---

## 未来方向 (低优先级, 不阻塞当前)

| 方向 | 说明 | 触发条件 |
|------|------|---------|
| LoRA/Adapter | DINOv3 域适应, rank=16, ~12M 参数 | 多层特征验证后 |
| 历史 occ box (方案 D) | 2 帧 1.0s, CEO 最有前途 | 特征问题解决后 |
| 3D 空间编码 | 词汇表扩展 230→238, 先验 token 注入 | 长期 |
| V2X 融合 | BEV 2D 刚体变换 | 长期 |
| Instance Grouping | SLOT_LEN 10→11, instance_id token | 低优先级 |
