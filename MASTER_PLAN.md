# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-11 ~22:30
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

## 当前阶段: ORCH_029 @2000 val 进行中 (29%, ETA ~23:14), 等结果后决策切换

## 实验路线图

| 阶段 | 时间 | 实验 | 内容 | 决策依据 |
|------|------|------|------|---------|
| **现在** | 03/11 ~22:30 | ORCH_029 @2000 val | val 进行中 29%, ckpt 已保存, reg=0 9.0% (vs 024 28.6%) | 等 val 完成 |
| **里程碑 1** | ~03/11 23:14 | ORCH_029 @2000 eval 完成 | 收集指标, 与 ORCH_024 @2000 对比 | 标签改进初步结论 |
| **切换** | ~03/12 01:30 | 停止 ORCH_029 | 保留 ckpt, 释放 4 GPU | — |
| **阶段 2** | ~03/12 01:30 | ORCH_032 启动 | **多层 [9,19,29,39]** + overlap+vis 标签, `plan_full_nuscenes_multilayer.py`, 从零训练, 4×A6000 | CEO 论文分析: 多层特征可能是 car_P 根因 |
| **里程碑 2** | ~03/12 05:00 | ORCH_032 @2000 eval | 多层 vs ORCH_029 @2000 vs ORCH_024 @2000 三方对比 | 特征改进是否有效 |
| **里程碑 3** | ~03/12 12:00 | ORCH_032 @4000 eval | 第一个可信评估点, 重建决策矩阵 | 继续 or 调参 |
| **条件分支** | @4000 后 | 视数据决定 | 见下方决策树 | — |

### @4000 决策树

```
ORCH_032 @4000 car_P vs ORCH_024 @4000 (baseline 0.078):
│
├─ car_P > 0.12 → ★ 多层特征有效, 继续训练到 LR decay
│   └─ @8000: 考虑加 deep supervision / LN+BN (P3)
│
├─ car_P 0.09-0.12 → 有改善但不够大
│   ├─ bg_FA < 0.20 → 标签+特征都有贡献, 继续训练
│   └─ bg_FA > 0.25 → 特征改善被标签噪声抵消, 考虑 P3 (LN+BN)
│
└─ car_P < 0.09 → 多层特征无效或有害
    ├─ 检查 loss 收敛是否正常
    ├─ 考虑 P4 (加重投影层) 或回退单层 Layer 32
    └─ 重新评估架构瓶颈
```

### 并行准备清单 (不占 GPU)

| 优先级 | 任务 | 状态 | 触发条件 |
|--------|------|------|---------|
| P3 | 投影层加 LN+BN | 待开发 | ORCH_032 @4000 后视需要 |
| P4 | 加重投影层 (2-4 层 Transformer) | 待设计 | ORCH_032 car_P < 0.09 |
| — | Soft loss 加权 (边缘 cell 降权) | 待设计 | ORCH_032 bg_FA > 0.25 |
| — | Deep supervision (`loss_out_indices=[8,10,11]`) | 待配置 | ORCH_032 @8000 car_P < 0.12 |
| — | 置信度阈值后处理 | 待评估 | 任何 eval 后可尝试 |

---

## 关键发现

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
- **Critic 发现 (BUG-52)**: IoF/IoB 是死代码，实际生效的是 convex hull + vis≥10%
- **ORCH_029 正在验证此修复**

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
| **ORCH_029** | **Full nuScenes overlap + vis + convex hull** | **IN_PROGRESS @2000, val 进行中, 4×A6000** |
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
| **BUG-52** | ACCEPTED | IoF/IoB 死代码, convex hull 等效, 不修复 |
| **BUG-53** | NOTED | explore_final.py FG 偏高 (41.0 vs 实际 33.1), 方向一致 |
| **BUG-54** | FIXED | layer_indices 0-indexed 修正 [9,19,29,39] (commit `dba4760`) |
| **BUG-55** | FIXED | 多层 config load_from=None (commit `dba4760`) |
| **BUG-56** | NOTED | layer_idx=16 实为 block 16 (0-indexed) = 论文 Layer 17, 不改 |

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
