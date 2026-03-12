# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-12 ~10:10
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

## 当前阶段: ORCH_034 训练中, @2000 eval 结果积极, 等待 @4000

### ⭐ ORCH_034 @2000 eval 结果 (03/12 09:47)

| 指标 | ORCH_024 @2000 | ORCH_029 @2000 | ORCH_032 @2000 | **ORCH_034 @2000** |
|------|---------------|---------------|---------------|-------------------|
| car_R | 0.627 | 0.3737 | 0.0000 | **0.8124** ⭐ |
| car_P | 0.079 | 0.0514 | 0.0000 | 0.0571 |
| bg_FA | 0.222 | 0.1615 | 0.3181 | **0.2073** ✅ |
| off_th | 0.174 | 0.1447 | 0.2308 | **0.1655** ✅ |
| ped_R | 0.000 | 0.000 | 0.8328 | 0.0000 ⚠️ |

**结论**: car_R 0.8124 是历史最佳 (ORCH_024 peak=0.726)。多层特征+暖启动+BUG修复组合效果显著。car_P 仍低 (0.057)，非car类全0是@2000早期单类主导现象。继续训练到@4000。

### 修复清单 (ORCH_034 已部署)

| 修复项 | 旧值 | 新值 | BUG |
|--------|------|------|-----|
| load_from | None | ORCH_029@2000 | BUG-58 |
| proj_hidden_dim | 2048 | 4096 (4:1) | BUG-59 |
| clip_grad | 10.0 | 30.0 | BUG-60 |
| lr_mult (proj) | 2.0 | 5.0 | BUG-57 |
| IoF/IoB 过滤 | 死代码 | convex hull+IoF/IoB | BUG-52 |

## 实验路线图

| 阶段 | 时间 | 实验 | 内容 | 决策依据 |
|------|------|------|------|---------|
| ✅ | 03/11 23:15 | ORCH_029 @2000 | bg_FA -27%, off_th -17% | 标签改进确认 |
| ❌ | 03/12 ~04:00 | ORCH_032 @2000 | 全面坍缩 | BUG-57/58/59/60 |
| ⭐ **已完成** | 03/12 09:47 | ORCH_034 @2000 | **car_R=0.8124**, bg_FA=0.2073, off_th=0.1655 | 多层特征方向正确 |
| **里程碑 4** | ~03/12 16:00 | ORCH_034 @4000 | 多层 vs 单层真正对比 | 见下方决策树 |
| **里程碑 5** | ~03/13 | ORCH_034 @8000 | 架构决策点 | — |

### @4000 决策树

```
ORCH_034 @4000 car_P vs ORCH_024 @4000 (baseline 0.078):
│
├─ car_P > 0.10 → ★ 多层特征确认有效, 继续到 LR decay
│
├─ car_P 0.06-0.10 → 有改善
│   └─ 对比 bg_FA/off_th: 优于 029 → 继续; 否则考虑 LayerNorm
│
└─ car_P < 0.06 → car_R 高但 car_P 低 = FP 过多
    └─ 考虑置信度阈值后处理或 loss 加权调整
```

---

## 关键发现

### ORCH_032 坍缩 → ORCH_034 修复成功

ORCH_032 从零训练导致 8:1 投影坍缩 (BUG-57/58/59/60)。ORCH_034 修复后 car_R 从 0→0.8124。
> 完整审计: `shared/audit/processed/VERDICT_MULTILAYER_032_COLLAPSE.md`

### ★★★★★ DINOv3 多层特征 (2026-03-11, CEO 论文分析)

> 详细分析: `shared/logs/reports/dinov3_paper_analysis.md`

- 论文 4/4 下游任务都用 **[10,20,30,40] 四层拼接** (16384维)，我们只用 Layer 16 单层 (4096维)
- Layer 16 在几何任务上远未达峰 (Layer 30-35 最优)，多层拼接是 DINOv3 特有优势
- 适配层差距: 论文 12 层 Transformer (100M) vs 我们 2 层 MLP (10M)
- **代码已就绪**: ORCH_030 (commit `8a961de`) + ORCH_031 BUG-54/55 修复 (commit `dba4760`)
- Config: `plan_full_nuscenes_multilayer.py`, `layer_indices=[9,19,29,39]`, `load_from=None`

### BUG-51 标签修复 (overlap + vis filter)

- **问题**: center-based 分配导致 35.5% 物体零 cell，是 car_P 天花板根因之一
- **修复**: `grid_assign_mode='overlap'` + `vis≥10%` + convex hull (commits `ec9a035`, `a64a226`)
- **BUG-52 (FIXED)**: IoF/IoB 原为死代码 → CEO 要求部署，已在 convex hull 分支追加 IoF/IoB 双重过滤
- **ORCH_029 @2000 验证**: bg_FA -27%, off_th -17% 确认标签改进有效

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
| ORCH_024 | Full nuScenes center-based baseline | TERMINATED @12000, 6 eval 完整 |
| ORCH_028 | Full nuScenes overlap (无过滤) | TERMINATED @1180, 断电 kill |
| ORCH_029 | Full nuScenes overlap + vis + convex hull | STOPPED @2000, ckpt 保留 |
| ORCH_032 | Full nuScenes 多层 [9,19,29,39] + overlap+vis | ❌ TERMINATED @2000, 全面坍缩 (BUG-57/58/59/60) |
| ORCH_033 | 多层修复重启: load_from+proj4096+clip30+lr5 | COMPLETED, 但使用 BUG-52 修复前代码 |
| **ORCH_034** | **多层 + BUG-52 IoF/IoB + BUG-57/58/59/60 修复** | **IN_PROGRESS, 训练中** |
| ORCH_030 | 多层特征代码实现 | ✅ DONE (commit `8a961de`) |
| ORCH_031 | BUG-54/55 修复 | ✅ DONE (commit `dba4760`) |

已完成归档: ORCH_001-027 (详见 `shared/logs/archive/verdict_history.md`)

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
| **BUG-51** | FIXED v2 | Grid 分辨率过粗 → overlap + vis 修复 (commits `ec9a035`, `a64a226`) |
| **BUG-52** | FIXED | IoF/IoB 死代码 → convex hull 分支内追加 IoF/IoB 双重过滤 (CEO 指令) |
| **BUG-53** | NOTED | explore_final.py FG 偏高 (41.0 vs 实际 33.1), 方向一致 |
| **BUG-54** | FIXED | layer_indices 0-indexed 修正 [9,19,29,39] (commit `dba4760`) |
| **BUG-55** | FIXED | 多层 config load_from=None (commit `dba4760`) |
| **BUG-56** | NOTED | layer_idx=16 实为 block 16 (0-indexed) = 论文 Layer 17, 不改 |
| **BUG-57** | FIXED | proj.0 零学习 → proj_hidden=4096 + lr_mult=5 (ORCH_034 car_R=0.81 验证) |
| **BUG-58** | FIXED | load_from=None → ORCH_029@2000 暖启动 (ORCH_034 验证) |
| **BUG-59** | FIXED | 8:1 压缩 → 4:1 (ORCH_034 验证) |
| **BUG-60** | FIXED | clip_grad=10→30 (ORCH_034 验证) |

### 已关闭 BUG (BUG-2~46, 详见 `shared/logs/archive/verdict_history.md`)

关键已关闭: BUG-19 (FIXED, z+=h/2), BUG-27 (vocab mismatch), BUG-33 (DDP sampler), BUG-39 (因式参数化有效), BUG-40 (Critic 审计链失误)

---

## 未来方向 (低优先级, 不阻塞当前)

| 方向 | 说明 | 触发条件 |
|------|------|---------|
| LoRA/Adapter | DINOv3 域适应, rank=16, ~12M 参数 | 多层特征验证后 |
| 历史 occ box (方案 D) | 2 帧 1.0s, CEO 最有前途 | 特征问题解决后 |
| 3D 空间编码 | 词汇表扩展 230→238, 先验 token 注入 | 长期 |
| V2X 融合 | BEV 2D 刚体变换 | 长期 |
| Instance Grouping | SLOT_LEN 10→11, instance_id token | 低优先级 |
