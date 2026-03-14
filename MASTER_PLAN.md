# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-13 20:35
>
> **归档索引**: 历史 VERDICT/训练数据/架构审计详情 → `shared/logs/archive/verdict_history.md`
> **归档索引**: 指标参考/历史决策日志 → `shared/logs/archive/experiment_history.md`
> **审计全集**: `shared/audit/processed/VERDICT_*.md`

---

## CEO 战略方向

- **目标**: 设计出在完整 nuScenes 上性能优秀的代码。mini 数据集仅用于 debug
- 图像 grid 与 2D bbox 无法完美对齐是固有限制。主目标是 **BEV box 属性**
- 周边 grid 的 FP/FN 通过置信度阈值或 loss 加权处理
- **不再以 Recall/Precision 为最高目标，不再高度预警红线**
- **⭐ Offset 指标优先 (CEO 2026-03-13 指示)**: 5 个 offset (cx,cy,w,h,th) 直接影响 occ 图 mIoU，是最重要的评估标准。优先级: offset > car_R > car_P/bg_FA

---

## 当前阶段: ORCH_035 训练中 (Label Pipeline 大修)

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

### 训练状态
- **Resume from ORCH_034@4000**, ✅ 训练恢复 iter 12200 (15:41 resume from iter_12000)
- 新训练日志: `20260313_154113/20260313_154113.log`
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- 下一评估点: **@14000** (快速检查) → **@16000** (决策级)
- **@12000 ckpt 已标记为重要存档** (car_P=0.100 历史最佳)

### ⭐ ORCH_035 @6000 Val 结果 (新标签首次评估)

| 指标 | ORCH_034@4000 (旧标签) | ORCH_035@6000 (新标签) | 变化 |
|------|----------------------|----------------------|------|
| car_R | 0.8195 | 0.2329 | 🔴 -71.6% |
| car_P | 0.0451 | **0.0822** | ✅ **+82.3%** |
| bg_FA | 0.3240 | **0.0938** | ✅✅ **-71.1%** |
| off_th | 0.1598 | 0.2848 | 🔴 +78.2% |
| cv_R | 0.1095 | 0.2581 | ✅ +136% |

**解读**:
1. bg_FA 0.32→0.09 — label pipeline 修复**核心目标达成**
2. car_P 0.045→0.082 — 预测质量大幅提升, **@6000 已达到 @8000 决策树的最优分支**
3. car_R 大幅下降 — 新标签更严格 + 仅 2000 iter 适应, 预期内
4. off_th 恶化 — z-convention fix 改变角度参考, 需更多 iter
5. 注意: 新旧标签评估标准不同, 数值不直接可比

**决策: 继续到 @8000** (Rule #5: @6000 仅趋势参考)

### ⭐⭐ ORCH_035 @8000 Val 结果 (Rule #6 架构决策级)

| 指标 | @6000 (新标签) | @8000 (新标签) | 变化 |
|------|---------------|---------------|------|
| car_R | 0.2329 | **0.6012** | ✅✅ **+158%** |
| car_P | 0.0822 | **0.0822** | → 持平 |
| bg_FA | 0.0938 | **0.2568** | 🔴 +173% (类别激活FP) |
| off_th | 0.2848 | **0.2083** | ✅ -27% |
| ped_R | — | **0.2002** | 🆕 新类激活 |
| truck_R | — | **0.0243** | 🆕 |
| bus_R | — | **0.0886** | 🆕 |

**Critic VERDICT: PROCEED** — 继续到 @12000
- bg_FA 回升由类别激活 FP 完全解释，非标签问题
- car 预测 46% cells (FP 工厂)，但在 ORCH_024 参照范围内
- 4 类活跃 > ORCH_024 同期 3 类
- grad_norm 30→14 持续下降，训练稳定

---

## 短期实验路线图

| 阶段 | 时间 | 实验 | 内容 | 决策依据 |
|------|------|------|------|---------|
| ✅ | 03/11 23:15 | ORCH_029 @2000 | bg_FA -27%, off_th -17% | 标签改进确认 |
| ❌ | 03/12 ~04:00 | ORCH_032 @2000 | 全面坍缩 | BUG-57/58/59/60 |
| ✅ | 03/12 09:47 | ORCH_034 @2000 | car_R=0.8124, bg_FA=0.2073 | 多层特征方向正确 |
| ✅ | 03/12 14:18 | ORCH_034 @4000 | car_R=0.82, 4类激活 | Critic: PROCEED |
| ⭐ | 03/12 22:20 | ORCH_035 @6000 | bg_FA -71%, car_P +82% | 标签修复成功 |
| ⭐⭐ | 03/13 02:52 | ORCH_035 @8000 | car_R 0.60, 4类激活 | Critic: PROCEED |
| ⚠️ | 03/13 07:22 | ORCH_035 @10000 | car_R 0.42 🔴, car_P 0.053 🔴, cone 新激活 | Critic: CONDITIONAL PROCEED |
| ⭐⭐⭐ | 03/13 11:47 | ORCH_035 @12000 | **car_R 0.62 car_P 0.100 历史最佳!** off_th 0.162 | Critic: PROCEED |
| 🔴🔴 | 03/13 20:09 | ORCH_035 @14000 | **car_R=0.000! cone_R=0.830** BUG-17 灾难性崩溃 | 训练已终止 |
| ❌ | 03/13 12:05-15:36 | score_thr 消融 (ORCH_036) | **失败**: 模型无置信度, evaluator 未实现过滤 | 无效 |
| ✅ | 03/13 18:15 | score_thr 代码修复 (CEO 修正) | commit `9974e3a`: cls_probs 替代 marker_probs | 代码完成 |
| **进行中** | 03/13 20:27 | **score_thr 消融 (ORCH_041)** | ORCH_024@8k + ORCH_035@12k × thr={0.1,0.2,0.3,0.5} | ~16h, ETA 03/14 ~12:30 |
| 待执行 | — | BUG-17 weight cap (ORCH_037) | mini 数据验证 max_w=3.0 | BLOCKER — @14000 证明必须修复 |

### ✅ @12000 决策树 — 已完成: ★ 最优分支命中
- car_R=0.620 ≥ 0.55 ✅, car_P=0.100 ≥ 0.06 ✅, bg_FA=0.283 < 0.40 ✅
- **决策: 继续训练 + 并行开发 BUG-17 修复**

### @16000 决策树 (Critic @12000 VERDICT)

```
ORCH_035 @16000:
│
├─ car_P ≥ 0.08 + car_R ≥ 0.50 + bg_FA < 0.40
│   → ★ PROCEED + 部署 BUG-17 fix (ORCH_038 resume from best ckpt)
│
├─ car_P ≥ 0.06 + car_R ≥ 0.45
│   → PROCEED, 但 BUG-17 fix 为必要前提
│
├─ car_R < 0.40 (低于 @10k 底)
│   → STOP, 回退到 @12k, 部署 BUG-17 fix 再训练
│
├─ car_P < 0.04 (FP 失控)
│   → STOP, 审查 loss 权重
│
├─ bg_FA > 0.40
│   → CONDITIONAL, 先跑 score_thr 消融判断是否可后处理挽救
│
└─ peak_car_P(@12k) = 0.100 (Rule #6 参照)
```

### @14000 快速检查 (非决策级)
- car_R < 0.35 → 提前预警
- car_P < 0.03 → 考虑提前 STOP
- 否则继续到 @16k

### ⚠️ BUG-17: CRITICAL — 并行修复中
- **证据汇总**: @10k cone 449K FP 挤压 car; @12k bus 922K FP 成最大 FP 源; 总 FP 1.88M→2.06M 持续上升
- **跷跷板周期**: ~2000 iter, @10k cone↑car↓, @12k car↑cone↓bus↑
- **修复方案**: Weight Cap max_w=3.0 (一行改动), mini 验证后 @16k 部署
- **ped_R 连续 3 eval ≈ 0**: BUG-17 系统性压制, 修复后关注

---

## 长期战略路线图

> 综合所有 VERDICT 审计结论。按阶段排列，每阶段内按优先级排序。
> 各阶段之间有依赖关系，但同阶段内的项目可并行或独立决策。

### Phase 1: 基础修正 (当前 — ORCH_035)
> 目标: 修正 label pipeline 根本性错误, 建立可靠 baseline

| 项目 | 难度 | 影响 | 状态 | 审计来源 |
|------|------|------|------|---------|
| BUG-19v3 z-convention fix | 低 | 极高 | ✅ 已部署 | CEO 审查 |
| Hull-based IoF/IoB (Sutherland-Hodgman) | 中 | 高 | ✅ 已部署 | VERDICT_TWO_STAGE_FILTER, VERDICT_OVERLAP_THRESHOLD |
| filter_invisible=False | 低 | 中 | ✅ 已部署 | CEO 审查 |
| vis + cell_count 组合过滤 | 低 | 中 | ✅ 已部署 | CEO 审查 |
| score_thr 消融 (0.1/0.2/0.3/0.5) | 零 (代码已就绪) | 中 | ✅ 代码完成 (`9974e3a`): cls_probs softmax 置信度过滤。**消融待执行** (GPU 被训练占满) | VERDICT @8k/@10k/@12k |

### Phase 2: 训练优化 (ORCH_035 @12000 eval 后部署)
> 目标: 零/低成本的训练改进, 不改模型架构
> 注: 原计划 @8000 后启动, 因 Conductor 决策遗漏推迟。将在 @12000 eval 后作为 ORCH_036 统一部署

| 项目 | 难度 | 影响 | 依赖 | 审计来源 |
|------|------|------|------|---------|
| **Deep Supervision** `loss_out_indices=[8,10,11]` | **零** (改一行) | 中-高 | 无 | VERDICT_CEO_ARCH_QUESTIONS (P1) |
| **BUG-45 fix**: 推理时加显式 attn_mask | 低 (2-4h) | 中 | ⏳ **可立即开发** (不影响训练) | VERDICT_CEO_ARCH_QUESTIONS |
| **Per-slot 性能分析**: Slot 1/2/3 的 car_P 对比 | 零 | 诊断 | eval 数据 | VERDICT_AR_SEQ_REEXAMINE (P1) |
| **🔴 BUG-17 修复**: Weight Cap max_w=3.0 | 低 (一行) | **极高 (CRITICAL)** | ⏳ **ORCH_037 签发, mini 验证中** → @16k 后部署 | VERDICT @10k/@12k |

### Phase 3: ★ DINOv3 ViT-L Finetune (CEO 优先, Phase 2 后立即启动)
> 目标: 从 7B frozen + 10M adapter 切换到 ViT-L finetune, 解决 adapter 容量瓶颈
> 依据: DINOv3 论文 VGGT 实验 — ViT-L finetune 仅做最小改动即在 3 项 3D 任务超越 SOTA
> CEO 决策: 2026-03-12, 分析论文后确认优先路线 B

#### 核心论据

| 方案 | Backbone | Adapter 规模 | 训练方式 | 结果 |
|------|----------|-------------|---------|------|
| Plain-DETR (论文) | 7B | **100M** (6L enc+dec) | frozen | COCO SOTA |
| VGGT (论文) | ViT-L (300M) | 整个 backbone | **finetune** | 3D SOTA |
| **我们 (当前)** | **7B** | **~10M** MLP | **frozen** | **car_P 瓶颈** |
| **我们 (目标)** | **ViT-L (300M)** | 全部可训练 | **finetune** | — |

**瓶颈分析**: 论文用 7B frozen 时需 100M 解码器; 我们只有 10M, 差 10x。ViT-L finetune 让 300M 参数全部可训练, 彻底解决适配能力不足问题。

#### 显存对比

| 组件 | 7B frozen (当前) | ViT-L finetune (目标) |
|------|-----------------|---------------------|
| Backbone 权重 (fp16) | ~14 GB | ~0.6 GB |
| 梯度 | 0 (frozen) | ~0.6 GB |
| 优化器状态 (Adam fp32) | 0 | ~2.4 GB |
| Activations (backprop) | 0 | ~3-6 GB (可 gradient checkpoint) |
| **小计** | **~14 GB** | **~4-10 GB** |
| 投影层 | 16384→4096→768 (~70M) | 4096→768 (~3M) |

**结论: ViT-L finetune 显存 ≤ 7B frozen, A6000 48GB 完全可行**

#### 代码改动清单

| 文件 | 改动 | 难度 |
|------|------|------|
| `vit_git.py` L137 | `vit_7b()` → `vit_large()` (需加 config param 控制) | 低 |
| `vit_git.py` L158-170 | `unfreeze_last_n=24` (finetune 全部 24 层) | 零 |
| config | `online_dinov3_layer_indices=[5,11,17,23]` (ViT-L 24 层) | 零 |
| config | `online_dinov3_weight_path` → ViT-L 权重 | 零 |
| config | 投影层 4096→768 (4 层×1024=4096, 无需 hidden dim) | 零 |
| config | backbone LR=1e-4 (VGGT 做法), task head LR 更高 | 低 |
| `vision_transformer.py` | 确认 `vit_large()` 工厂函数可用 (已存在 L357-366) | 零 |

**权重**: `dinov3_vitl16_pretrain_lvd1689m-8aa4cbdd.pth` (~1.2GB, 链接在 `dinov3/ckpts.md`)

#### 实验计划

| 步骤 | 内容 | 预计耗时 |
|------|------|---------|
| 3a | 下载 ViT-L 权重, 修改代码支持 ViT-L variant 选择 | 2-3h |
| 3b | Mini 数据 smoke test: ViT-L finetune 能否正常训练 | 1h |
| 3c | Full nuScenes 训练, 继承 Phase 1-2 的 label pipeline 改动 | 从头训练 |
| 3d | @4000 eval 对比 7B frozen baseline | 决策点 |

#### VGGT 论文要点 (D.12)
1. 图像分辨率 518→592 (适配 patch_size=16)
2. 学习率 0.0002→0.0001 (更保守, 防漂移)
3. **4 层中间层拼接** (DINOv3 有收益, DINOv2 无收益)
4. 即使不调参, 仅替换 backbone 也超越原 VGGT

### Phase 4: Attention 机制优化 (Phase 3 验证后)
> 目标: 改善 AR 解码质量, 提升 precision

| 项目 | 难度 | 影响 | 依赖 | 审计来源 |
|------|------|------|------|---------|
| **Slot Attention Mask** (CEO Hard Mask 方案) | 低 (2-4h) | 中 | Deep Supervision baseline | VERDICT_CEO_ARCH_QUESTIONS (P4) |
| Exposure Bias 缓解 (Scheduled Sampling) | 中 (2-3天) | 中 | Per-slot 分析确认问题 | VERDICT_AR_SEQ_REEXAMINE (P5) |

### Phase 5: 3D 空间编码 (Phase 3-4 训练稳定后)
> 目标: 引入 3D 先验, 从根本改善 BEV 预测质量
> 审计来源: VERDICT_3D_ANCHOR

| 项目 | 难度 | 影响 | 依赖 | 说明 |
|------|------|------|------|------|
| **BEV 坐标 Positional Encoding** | 低 (0.5-1天) | 中-高 | 无 | 最小可行实验: grid_reference 从 2D 图像坐标扩展为 BEV 物理坐标, MLP 编码为 PE |
| **相机投影 3D Anchor** | 中 (2-3天) | 高 | BEV PE 验证 | 每个 BEV grid 中心沿 z 轴采样 K=4 高度点, 通过相机内外参投影到图像, 替代 grid_sample 位置 |

### Phase 6: 时序信息 (Phase 5 基础稳定后)
> 目标: 引入历史帧信息, 理解运动模式
> 审计来源: VERDICT_CEO_STRATEGY_NEXT (方案 D, CEO 评为最有前途)

| 项目 | 难度 | 影响 | 依赖 | 说明 |
|------|------|------|------|------|
| **历史 Occ Box 时间编码 (2帧, 1.0s)** | 高 (1-2周) | 极高 | 数据加载修改, 标签生成修改 | CEO 最看好方向。编码历史 2 帧 BEV 占据为条件信号, 推荐轻量条件信号方案 |

### Phase 7: 架构扩展 (长期, 需要数据支撑决策)
> 目标: 更精细的实例理解和预测

| 项目 | 难度 | 影响 | 依赖 | 审计来源 |
|------|------|------|------|---------|
| **Instance Grouping** (SLOT_LEN 10→11, instance_id token) | 中 (2-3天) | 中 | BUG-17 修复 | VERDICT_INSTANCE_GROUPING |
| Instance Consistency 指标 | 低 | 诊断 | 无 | VERDICT_INSTANCE_GROUPING |
| 异构 Q/K/V cross-attention (DETR decoder 风格) | 高 (3-5天) | 中 | 架构重构 | VERDICT_ARCH_REVIEW |
| FPN 多尺度特征融合 | 高 (4-6天) | 中 | 小目标性能瓶颈时 | VERDICT_CEO_STRATEGY_NEXT (方案 F) |
| LoRA 域适应 (rank=16, ~12M) | 中 (2-3天) | 中 | 仅在保留 7B frozen 时适用 | VERDICT_CEO_STRATEGY_NEXT (方案 E) |

### Phase 8: 多车协作 (远期, 需要 V2X 数据集)
> 目标: 利用多视角信息解决遮挡问题
> 审计来源: VERDICT_3D_ANCHOR

| 项目 | 难度 | 影响 | 依赖 | 说明 |
|------|------|------|------|------|
| **V2X 融合**: Sender OCC box → BEV 特征图, cross-attention 融合 | 高 (3-5天) | 极高 | Phase 5 完成, V2X 数据集可用 | 多车协作的核心模块 |
| V2X 轨迹编码: 历史轨迹→条件信号 | 高 | 高 | V2X 融合基础 | 利用协作车辆轨迹预测 |

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

### ⭐ ORCH_024 baseline 数据 (center-based, 单层 L16, 已终止 @12000)
> **综合最优: @8000** — 5 个 offset 全面优于 ORCH_035 @12000 (CEO 2026-03-13 确认)
> 权重: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/iter_8000.pth`
> 技术规格: DINOv3 ViT-7B frozen, 单层 L16, center-based target, preextracted_proj 2048

| 指标 | @2000 | @4000 | @6000 | **@8000** | @10000 | @12000 | peak |
|------|-------|-------|-------|----------|--------|--------|------|
| **off_cx** | 0.0558 | **0.0392** | 0.0556 | 0.0446 | 0.0723 | **0.0383** | **0.0383** |
| **off_cy** | **0.0693** | 0.0971 | 0.0818 | 0.0736 | 0.0916 | 0.0812 | **0.0693** |
| **off_w** | 0.0201 | **0.0156** | 0.0378 | 0.0251 | 0.0389 | 0.0230 | **0.0156** |
| **off_h** | **0.0049** | **0.0049** | 0.0107 | 0.0064 | 0.0171 | 0.0142 | **0.0049** |
| **off_th** | 0.1739 | 0.1499 | 0.1685 | 0.1399 | 0.1597 | **0.1275** | **0.1275** |
| car_R | 0.627 | 0.419 | 0.455 | **0.718** | **0.726** | 0.526 | **0.726** |
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | 0.081 | **0.090** |
| bg_FA | **0.222** | **0.199** | 0.331 | 0.311 | 0.407 | 0.278 | — |

### ORCH_024 vs ORCH_035 综合对比 (CEO 确认 offset 为核心)

| 指标 | ORCH_024 @8000 | ORCH_035 @12000 | 差距 |
|------|---------------|----------------|------|
| **off_cx** | **0.0446** | 0.082 | 024 优 84% |
| **off_cy** | **0.0736** | 0.107 | 024 优 45% |
| **off_w** | **0.0251** | 0.036 | 024 优 43% |
| **off_h** | **0.0064** | 0.011 | 024 优 72% |
| **off_th** | **0.1399** | 0.162 | 024 优 16% |
| car_R | **0.718** | 0.620 | 024 优 |
| car_P | 0.060 | **0.100** | 035 优 |
| bg_FA | 0.311 | **0.283** | 035 略优 |

**关键差异**: ORCH_024=center+单层L16, ORCH_035=overlap+多层[L9,L19,L29,L39]

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
| **ORCH_035** | **Label pipeline 大修 + resume 034@4000** | **TERMINATED** @14000 — car_R=0 BUG-17 崩溃 |
| ORCH_036 | score_thr 消融 @12k ckpt | ❌ FAILED — 模型无置信度, eval 无 thr 过滤 |
| ORCH_037 | BUG-17 Weight Cap (max_w=3.0) | DELIVERED (待 GPU 空闲) |
| ORCH_038 | 恢复训练 (resume iter_12000) | ✅ DONE (被 ORCH_039 合并) |
| ORCH_039 | 紧急恢复训练 | ✅ DONE (15:41 恢复) |
| ORCH_040 | score_thr 代码修复 | ✅ DONE (代码), 消融待执行 |
| **ORCH_041** | **score_thr 消融 (cls_probs, 4-GPU DDP)** | **DELIVERED** (等 @14000 val 后执行) |
| ORCH_030 | 多层特征代码实现 | ✅ DONE (commit `8a961de`) |
| ORCH_031 | BUG-54/55 修复 | ✅ DONE (commit `dba4760`) |

已完成归档: ORCH_001-033 (详见 `shared/logs/archive/verdict_history.md`)

---

## BUG 跟踪

### 活跃 BUG

| BUG | 严重性 | 摘要 | 计划修复阶段 |
|-----|--------|------|------------|
| **BUG-17** | **BLOCKER** | per-batch sqrt 类别竞争 — @14000 car_R=0.000, cone_R=0.830 完全接管。@12k bus 922K FP, 总FP 2.06M↑ | **必须修复才能继续训练** — ORCH_037 Weight Cap 代码完成 |
| **BUG-61** | MEDIUM | reg_loss=0 频率升高: ORCH_035 恢复后 13/173 iter=7.5% (ORCH_024 为 4.1%)。不致命但影响 offset 回归质量 | BUG-17 后调查 |
| **BUG-45** | MEDIUM | OCC head 推理 attn_mask=None, 训练/推理不一致 | Phase 2 |
| **BUG-48** | HIGH | unfreeze_last_n 目标与 extraction point 不匹配 | 仅 7B frozen 适用, ViT-L finetune 后关闭 |
| **BUG-49** | MEDIUM | DINOv3 遍历全 40 blocks, 只需部分, 浪费 58% | 仅 7B frozen 适用, ViT-L 仅 24 层 |
| **BUG-50** | MEDIUM | unfreeze 时全部 blocks 构建计算图, +10-15GB | 仅 7B frozen 适用, ViT-L finetune 无此问题 |

### 已修复 BUG (本轮)

| BUG | 修复 |
|-----|------|
| BUG-19v3 | z = box BOTTOM, corners z ∈ [z, z+h] (commit `80b1e23`) |
| BUG-51v2 | overlap + vis + convex hull |
| BUG-52v2 | IoF/IoB 对 hull polygon 计算 (Sutherland-Hodgman) (commit `80b1e23`) |
| BUG-54 | layer_indices [10,20,30,40]→[9,19,29,39] |
| BUG-57 | proj lr_mult=5.0 |
| BUG-58 | load_from=ORCH_029@2000 |
| BUG-59 | proj 4:1 compression |
| BUG-60 | clip_grad=30.0 |

### 已关闭 BUG (BUG-2~46, 详见 `shared/logs/archive/verdict_history.md`)
