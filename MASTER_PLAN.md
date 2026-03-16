# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-16 16:20
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

## 当前阶段: ⏸️ 等待 CEO 方向性决策 — 11 轮实验穷尽超参/微架构空间 (2026-03-16 16:40 CDT)

> **无活跃训练。无 pending ORCH。所有 GPU 空闲。**
> ORCH_049-059 共 11 轮实验证明: marker_same 在任何超参/bias/微架构调整下都不可逆上升至 ~1.0。
> 需要 CEO 从"待 CEO 决策的方向"(5 个候选)中选择下一步。

### 🔴🔴 前阶段总结: 回到 ORCH_049 精确配置 + 多点 frozen-check 定位崩塌时间 (2026-03-16 05:17 CDT)

### 🔴 bg_balance_weight 二分搜索完成: 只有 bg=5.0 存活

| ORCH | marker_pos_punish | bg_balance_weight | FG/BG | @200 结果 |
|------|-------------------|-------------------|-------|-----------|
| 048 | 3.0 | 2.5 | 6x | @500 all-positive |
| **049** | **1.0** | **5.0** | **1x** | **TP=112 唯一存活** → @500 all-neg |
| 051 | 2.0 | 3.0 | 3.3x | all-positive |
| 052 | 1.0 | 3.0 | 1.67x | all-negative |
| 053 | 1.0 | 4.0 | 1.25x | all-negative |

- bg=3.0, 4.0 均死亡；只有 bg=5.0 存活
- FG/BG 比调参空间几乎用尽
- **策略转换**: 不再调 FG/BG 比，回到 ORCH_049 精确配置，用多点 frozen-check 定位 @200→@500 之间的崩塌时间点

### ⭐⭐ ORCH_055 完整崩塌轨迹 (2-GPU DDP, 精确复现 ORCH_049)

| iter | Pos slots | Saturation | marker_same | TP | 模式 |
|------|-----------|-----------|-------------|-----|------|
| **100** | **750 (62.5%)** | **0.703** | **0.887** | **109** | **🟢 HEALTHY** |
| 200 | 954 (79.5%) | 0.820 | 0.962 | 147 | 向 all-positive |
| 300 | 1010 (84.1%) | 0.873 | 0.973 | 150 | all-positive 峰值 |
| **400** | **71 (5.9%)** | **0.080** | **0.984** | **0** | **相变→near-all-negative** |
| 500 | 158 (13.2%) | 0.142 | 0.988 | 12 | 微回弹仍 frozen |

**崩塌机制**:
1. **健康期 (@100)**: LR 极低, 模型用图像特征+位置编码共同决策
2. **模板化加速 (@100→@300)**: LR 升高, grid_pos_embed shortcut 优化效率更高, 逐渐主导
3. **相变 (@300→@400)**: bg_weight 梯度在高 LR 下反噬, 模板从全正翻转为全负
4. **终态 (@400+)**: marker_same→0.988, 模板固化不可逆

**BUG-78 确认**: 单 GPU (effective batch=1) 在 @100 就全阴性; DDP (batch=16) 在 @100 健康。batch size 是 mode collapse 的关键因素。

### ORCH_055 iter_100 Full Eval (2026-03-16 11:13 CDT)

| 指标 | @100 | ORCH_024 @2000 |
|------|------|----------------|
| car_R | 0.000 | 0.627 |
| cone_R | 0.588 | — |
| 其余 8 类 R | 全 0 | — |
| bg_FA | 0.618 | 0.222 |
| off_cx | 0.311 | 0.056 |
| off_cy | 0.090 | 0.069 |
| off_w | 0.021 | 0.020 |
| off_h | 0.018 | 0.005 |
| off_th | 0.211 | 0.174 |

- **@100 只训练了 100 iter**，car_R=0 是预期的（分类器冷启动）
- frozen-check HEALTHY 但 full eval 性能极弱 — 证明 ORCH_057 架构变更是必要的：需要让模型在更长训练中保持健康，而非在 @100 就判定成功

### 🔴 ORCH_056 结论: 降低 LR 加速模板化

- @200: saturation=0.998, marker_same=0.999 — **比 ORCH_055 @200 更差**（ORCH_055 sat=0.82）
- 低 LR 让模型更快固化到 all-positive 模板，可能因为梯度太弱无法逃离 grid_pos_embed shortcut
- **超参数空间已用尽**: FG/BG 比、dropout、LR 均无法解决问题

### ⭐⭐⭐ 战略结论: 需要架构级干预

所有超参数实验都指向同一根因: **grid_pos_embed 为 marker step 提供了免费的空间先验**，模型不需要看图像就能决定"哪里有目标"。

唯一可行的干预方向: **让 marker step 的 input 不包含 grid_pos_embed**。

#### 方案: marker_step_no_pos — 分离 marker 和 box 的位置编码

- **marker step (pos_id=0)**: input = image_features + text_embed（**不加** grid_pos_embed）
- **class/box steps (pos_id=1-9)**: input = image_features + text_embed + grid_pos_embed（正常）
- **实现位置**: `git.py` 的 `forward_transformer` 或 `git_occ_head.py` 的 decoder 中，grid_pos_embed 被添加到 grid_start_embed 的地方
- **需要 Critic 审计**: 这是架构变更，需要确认不会破坏 box 回归的位置信息传递

### 🔴 ORCH_057 (marker_no_grid_pos) FAILED @100 — 全正饱和 (2026-03-16 14:00)

- @100: marker_same=0.992, saturation=1.000, EARLY STOP
- **比 ORCH_055 @100 更差**（ORCH_055 marker_same=0.887, HEALTHY）
- **原因**: 移除 grid_pos_embed 后 marker 失去空间差异 → 所有 cell 输入相同(task_embed) → 立即收敛到全正

### ⭐⭐ 问题重新定义

| 实验 | grid_pos_embed 状态 | @100 marker_same | 结论 |
|------|---------------------|-----------------|------|
| ORCH_055 | 正常 | 0.887 🟢 | grid_pos_embed 提供多样性 |
| ORCH_050 | cell-level dropout | @200 全阴性 | dropout 破坏定位 |
| ORCH_057 | marker 移除 | 0.992 🔴 | 移除导致多样性消失 |

**grid_pos_embed 在早期帮助维持预测多样性**。问题不是它的存在，而是训练过程中它逐渐取代图像特征成为主导。

### 🔴 ORCH_059 (BUG-82 marker_init_bias) 结论: 改变崩塌方向但不阻止模板化 (2026-03-16 16:20)

| iter | 055 sat | 059 sat | 055 marker_same | 059 marker_same |
|------|---------|---------|-----------------|-----------------|
| 100 | 0.703 | **0.253** | 0.887 | 0.963 |
| 300 | 0.873 | 0.035 | 0.973 | 0.996 |
| 500 | 0.142 | 0.025 | 0.988 | 0.995 |

- ✅ bias init 成功翻转 saturation（从偏正到偏负）
- ❌ marker_same 在两个实验中都不可逆升至 ~1.0
- **BUG-82 不是模板化的根因**；初始化偏置只影响崩塌方向

### ⭐⭐⭐ 核心问题重新聚焦: marker_same 不可逆上升

11 轮实验 (ORCH_049-059) 的共同现象: **marker_same 始终单调上升至 ~1.0**。
无论 FG/BG 比、dropout、LR、grid_pos_embed 移除、bias init — marker_same 都不可阻止。

**这意味着**: grid_pos_embed → marker 的映射是一个强 shortcut，模型在任何超参/bias/架构微调下都会找到这条路径。根因可能在于:
1. grid_pos_embed 与 marker 决策之间的因果路径太短/太强
2. 或者 marker 的 4-class 设计（3 FG + 1 BG）本身创造了不对称的梯度动态

### 待 CEO 决策的方向

1. **grid_pos_embed 噪声/shuffle**: 训练时对 grid_pos_embed 加随机扰动，保留空间信息但防止固定模式记忆
2. **二元 marker**: 将 4-class marker (near/mid/far/end) 改为 2-class (FG/BG)，消除 3:1 结构偏差
3. **marker 与 box 解耦**: marker 用独立的轻量 head（不共享 decoder），直接从图像特征分类
4. **接受现状，尝试长训练**: ORCH_055 @100 有 TP=109 和 diff/Margin=54.6%，也许在更长训练(>500 iter)中模板化会自然缓解
5. **回退到 ORCH_024 架构**: DINOv3 7B frozen + 单层 L16 从未出现 marker_same 问题，@8000 car_R=0.718

### 活跃 BUG 跟踪

| BUG | 状态 | 级别 | 当前结论 |
|-----|------|------|----------|
| **BUG-73** | **PARTIAL** | **CRITICAL** | FG/BG=1x 方向正确(TP=112)但 @500 崩塌; 需 1.5-2x |
| **BUG-74** | **FIXED** | HIGH | `GlobalRotScaleTransBEV` 已移除 |
| **BUG-75** | **OPEN** | HIGH | `grid_pos_embed` 空间模板 shortcut — cell-level dropout 不可行(BUG-77)，需 marker-only 方案 |
| **BUG-76** | **CONFIRMED** | HIGH | FG/BG=1x→all-neg @500, 3.3x→all-pos @200; 可行窗口 1-3.3x |
| **BUG-77** | **CONFIRMED** | **CRITICAL** | cell-level grid_pos_embed dropout 破坏定位; 已关闭 |
| **BUG-79** | **CONFIRMED** | MEDIUM | marker_no_pos 若只改一侧会放大训练/推理不对称 |
| **BUG-81** | **NEW** | HIGH | focal_alpha_marker=0.75 方向错误，FG 权重 3× BG |
| **BUG-82** | **NEW** | **CRITICAL** | marker 无 bias init，初始 P(FG)=75%，100% all-positive |
| **BUG-83** | **NEW** | MEDIUM | per_class_balance 下 BG per-sample 梯度稀释 39x |

### 活跃 BUG 跟踪

| BUG | 状态 | 级别 | 当前结论 |
|-----|------|------|----------|
| **BUG-73** | **PARTIAL** | **CRITICAL** | ORCH_049 修复到 FG/BG=1x，但矫枉过正导致全阴性崩塌 |
| **BUG-74** | **FIXED** | HIGH | `GlobalRotScaleTransBEV` 已在 ORCH_048 移除 |
| **BUG-75** | **OPEN** | HIGH | `grid_pos_embed` 空间模板 shortcut，ORCH_050 将用 marker dropout 处理 |
| **BUG-76** | **NEW** | HIGH | FG/BG=1x 完全平衡导致 all-negative collapse（ORCH_049 @500） |

### 🟠 ORCH_048 @500 最新结论

- `ORCH_048` 已完成并按指令在 `@500` 直接执行 frozen-check，未继续 full val
- **Frozen 指标**:
  - Avg positive slots: **482/1200 (40.2%)**
  - Positive IoU (cross-sample): **0.9459**
  - Marker same rate: **0.9767**
  - Coord diff (shared pos): **0.007028**
  - Saturation: **0.426**
- **进展**:
  - 成功打破 `1200/1200` 全正饱和
  - 首次出现真实 TP，说明 `center assignment + core/around supervision + prefix dropout + pos/neg rebalance` 方向有效
- **仍未通过**:
  - `marker_same=0.9767` 仍远高于 `<0.90` 阈值
  - 当前失败模式已从“全正模板”收缩为“稀疏模板”，说明 marker 决策路径仍存在强 shortcut
- 可视化: `shared/logs/VIS/048_iter500_frozen_check/`

### 当前主线判断

- **不是训练不足**
  - `ORCH_046_v2 @500`、`ORCH_047 @500`、`ORCH_048 @500` 已连续证明：错误模式在早期就成型
- **不是 marker teacher forcing 泄漏**
  - Critic 已确认 marker 作为第一个 token，不接收 GT prefix
- **当前阻断项就是 BUG-73**
  - 不先修 BUG-73，就不值得继续任何长训练

## 当前阶段: ORCH_047 @500 仍 Frozen，后续改用 frozen-check 代替 full val 作为首道闸门 (2026-03-15 23:15 CDT)

### 🔴 ORCH_047 @500 结论

- 已手动停止 `ORCH_047` 的 `@500 full val`，不再等待 `1505` 个 val iter 全跑完
- 已直接对 `iter_500.pth` 运行 `scripts/check_frozen_predictions.py`
- **Frozen 指标**:
  - Avg positive slots: **1200/1200 (100.0%)**
  - Positive IoU (cross-sample): **1.0000**
  - Marker same rate: **1.0000**
  - Coord diff (shared pos): **0.008062**
  - Saturation: **1.000**
- **结论**: 即使加入 `RandomFlipBEV + GlobalRotScaleTransBEV`，`ORCH_047 @500` 仍然与 `ORCH_046_v2` 一样完全 frozen
- 可视化已生成: `shared/logs/VIS/047_iter500_frozen_check/`

### 新流程决定

- **@500 不再先跑 full val**
- 今后所有新实验统一采用：
  1. `iter_500.pth` 一生成，立即运行 `scripts/check_frozen_predictions.py`
  2. 若 `Positive IoU > 0.95` 或 `Marker same rate > 0.90` 或 `Saturation > 0.90` → **立即停训**
  3. 只有 frozen-check 通过的实验，才继续 full val / 长训练
- 这样可以把 “1 小时以上的无效 val” 缩短为 “几分钟的 frozen 诊断”
- **CEO 当前明确不同意**把 `filter_invisible=True` 纳入下一轮修复；后续方案默认保持 `filter_invisible=False`
- 当前准备中的 `ORCH_048` 主线只考虑：
  - 去掉 `GlobalRotScaleTransBEV`，只保留 `RandomFlipBEV`
  - 显式设 `grid_assign_mode='center'`
  - 回收前景/背景权重失衡（`pos_cls_w_multiplier↓`, `neg_cls_w↑`）
  - 用更强的 scheduled sampling / prefix dropout 替代单纯 `token_drop_rate`

### 🔴 已吸收 Critic 判决: VERDICT_ORCH046_V2_AT500 = STOP

- `ORCH_046_v2` 的 `iter_500.pth` 已确认 **frozen predictions**
- **Frozen 指标**:
  - Avg positive slots: **1200/1200 (100.0%)**
  - Positive IoU (cross-sample): **1.0000**
  - Marker same rate: **1.0000**
  - Coord diff (shared pos): **0.008769**
  - Saturation: **1.000**
- Critic 结论已归档到 `shared/audit/processed/VERDICT_ORCH046_V2_AT500.md`
- **最终判断**: `BUG-69` / `BUG-62` / `BUG-64` 虽已修复，但仅修超参数不能解除 collapse；当前主问题是训练算法层面的 shortcut learning

### 当前主线判断

- **BUG-71 (Teacher Forcing shortcut + 无 BEV 空间增强)** 已上升为当前主问题
  - 100% teacher forcing 下，模型可沿固定空间先验学习模板输出
  - 无 `RandomFlipBEV/GlobalRotScaleTransBEV` 时，BEV 坐标系稳定，shortcut 成本极低
- **DINOv3“Layer 16 方差过小”不是当前主嫌疑**
  - `ORCH_046_v2` 实际用的是 `online_dinov3_layer_indices=[5,11,17,23]`
  - frozen 横跨单层与多层配置复现，更像 decoder/pipeline shortcut，而不是单层特征失效
- **BUG-45 从活跃问题中降级**
  - Critic 本轮判定：推理端 `attn_mask=None` 在 KV cache 自回归下与训练端 causal mask 数学等价
  - 结论：**暂不再把 BUG-45 当作当前阻断项**

### 当前执行状态

- **ORCH_047 已停止**
  - `iter_500.pth` 的 frozen-check 已确认失败
  - `full val` 已在 `Iter(val) [1060/1505]` 手动终止，不再继续浪费 GPU
- **ORCH_048 已签发**
  - CEO 明确同意直接进入 Admin 执行
  - 审计 `AUDIT_REQUEST_ORCH048_PLAN` 继续并行，用于校正实现细节
  - 本轮主线: `RandomFlipBEV only + center assignment + core/around supervision + stronger anti-TF shortcut`

## 当前阶段: 准备签发 ORCH_046 — 修复 BUG-69 + BUG-62

### ⭐⭐ Critic VERDICT_ORCH046_PLAN (2026-03-15 17:15) — 根因修正

**重大发现**: ORCH_045 崩塌首因不是"零数据增强"（PhotoMetricDistortion 一直在 config 中），而是：
1. **BUG-69 (NEW CRITICAL)**: adaptation layers 被 paramwise_cfg substring match 意外设为 lr_mult=0.05，25.2M 参数实际冻结
2. **BUG-62**: clip_grad=10 导致有效梯度 0.33%

### 修正后的优先级 (Critic 审计通过)

| 优先级 | 修复项 | 说明 |
|--------|--------|------|
| **P0** | **BUG-69**: adapt_layers/adapt_norm lr_mult → 1.0 | 让 25.2M 适应层真正参与训练 |
| **P0** | **BUG-62**: clip_grad → 50.0 | 释放梯度信号 |
| P1 | RandomFlip3D (BEV 水平翻转) | 空间增强, 打破 BEV 空间先验 |
| P1 | Scheduled Sampling | 防止 exposure bias |
| P2 | BUG-64: bert_embed → bert-large + pretrain | 分类器收敛加速 |
| 保留 | token_drop_rate=0.3 | 辅助 |

### 执行策略: 分步验证
1. **ORCH_046**: 只修 BUG-69 + BUG-62 (config 改动), 跑 2000 iter 验证
2. **ORCH_047**: 如不崩塌, 再加 RandomFlip3D + Scheduled Sampling

### 🚨🚨 Frozen Predictions 根因最终确认 (2026-03-15 03:05)

**P2+P3 @6000 (ORCH_043) 的 car_R=0.582 是假象** — BEV 可视化确认预测完全 frozen:
- 5 个样本的预测框在相同 BEV 位置，不随场景变化
- 1200/1200 slots 全正，跨样本 marker 相同率 93~98%，坐标完全一致
- **喂随机噪声/全零图像 → 输出完全一样** → 模型完全忽略视觉输入
- DINOv3 特征跨样本确实不同 ✅，但 decoder 输出跨样本完全相同 ❌

### 推理错误纠正 (重要教训)

| 错误推理 | 正确结论 |
|---------|---------|
| "TF≈AR → 位置信息缺失" | TF≈AR → **完全 mode collapse** |
| "car_R=0.582 → P2+P3 修复成功" | frozen 位置碰巧和 GT 重叠的假象 |
| "P2+P3 是正确修复方向" | P2+P3 是必要条件但**不充分**，根因是 TF mode collapse |
| "检测数 765-846 → 预测不 frozen" | 检测数不等于空间分布，BEV 位置才是判断标准 |

### ORCH_045 训练详情 (当前活跃实验)

| 项目 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_large_v1.py` (commit `26b6f92`) |
| 架构 | GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen |
| 特征提取 | **多层 [5,11,17,23]** → 4×1024=4096 → 投影 2048 → GELU → 1024 |
| 适应层 | **2 层 PreLN TransformerEncoderLayer** (25.2M 参数, trainable, nhead=16) |
| Anti-collapse | **token_drop_rate=0.3** — 30% GT 输入替换为随机 token |
| 权重 | 从零训练 (load_from=None, SAM pretrained via init_cfg) |
| PID | 1686317 (rank0), 1686318 (rank1), GPU 0,2 (2×A6000) |
| Batch | batch_size=1/GPU × 2 GPU × accumulative_counts=8 = effective 16 |
| 显存 | ~29 GB/GPU |
| 速度 | ~3.78 sec/iter |
| ETA | ~1 天 17 小时 (~03/16 21:30) |
| 进度 | **iter 2000+/40000** — @2000 eval 完成, 训练继续 |
| Loss | 极大波动 (0→984→447→113), 从零训练早期预期 |
| ⚠️ reg_loss=0 | 19/200 报告 = 9.5%, 均反弹, 非永久 collapse |
| work_dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt` |
| 日志 | `.../nohup_multilayer_adapt.out` (用 `strings` 过滤) |

### 关键代码修改

| Commit | 文件 | 改动 |
|--------|------|------|
| `05d5138` | `mmdet/models/detectors/git.py` | token corruption: forward_transformer 中 input_seq 随机替换 |
| `a69b64b` | `mmdet/models/backbones/vit_git.py` | 多层 DINOv3 [5,11,17,23] + 2 层 PreLN 适应层 |
| `a69b64b` | `scripts/check_frozen_predictions.py` | mode collapse 自动诊断脚本 |
| `26b6f92` | config | batch_size=1, accumulative_counts=8 (OOM fix) |
| `d9d7f7d` | `git.py` + `git_occ_head.py` | P2 (position embedding) + P3 (每步图像特征注入) |

### ⭐ @2000 Eval 结果 (2026-03-15 07:19)

| 指标 | ORCH_045 @2000 | GiT-Large v1 @2000 (单层) | ORCH_024 @2000 |
|------|---------------|--------------------------|----------------|
| **ped_R** | **0.7646** | 0.0000 | ~0 |
| car_R | 0.0000 | 0.0000 | 0.627 |
| 其他 8 类 R | 全 0 | 全 0 | — |
| bg_FA | **0.9208** | 0.002 | 0.222 |
| off_cx | 0.309 | 0.106 | 0.056 |
| off_cy | 0.146 | 0.029 | 0.069 |
| off_w | 0.087 | 0.070 | 0.020 |
| off_h | 0.038 | 0.009 | 0.005 |
| off_th | 0.192 | 0.078 | 0.174 |

**初步判断: 不是 frozen predictions, CONDITIONAL PROCEED to @4000**
- **ped_R=0.7646**: 从零训练 @2000 即激活 1 类，旧单层 @2000 全 0 — 积极信号
- **bg_FA=0.9208**: 模型大量预测正样本，行为与 frozen 完全不同（frozen=100% 正但位置一致）
- **offset 全面较差**: 从零训练 @2000 预期内
- **待 Critic 运行 check_frozen_predictions.py 确认预测多样性**

### ⚠️⚠️ @4000 Eval 结果 (2026-03-15 11:17) — Marker Saturation Warning

| 指标 | @2000 | **@4000** | 趋势 | ORCH_024 @4000 |
|------|-------|-----------|------|----------------|
| ped_R | 0.7646 | **1.0000** | ⬆️ | — |
| car_R | 0.000 | **0.000** | — | 0.419 |
| bg_FA | 0.921 | **1.0000** | 🔴🔴 | 0.199 |
| off_cx | 0.309 | **0.279** | ✅ | 0.039 |
| off_cy | 0.146 | **0.193** | 🔴 | 0.097 |
| off_w | 0.087 | **0.084** | ✅ | 0.016 |
| off_h | 0.038 | **0.038** | — | 0.005 |
| off_th | 0.192 | **0.280** | 🔴🔴 | 0.150 |

**问题**: bg_FA=1.0 = 所有 cell 预测为正样本 (marker saturation collapse)
**判断**: CONDITIONAL PROCEED to @6000 (ABSOLUTE FINAL)
- off_cx/off_w 有微弱改善 → 模型不是完全死掉
- 但 bg_FA 0.92→1.00 + off_th 0.19→0.28 恶化明确
- **@6000: bg_FA ≥0.95 且 offset 不改善 → STOP**

### 🔴 @6000 ABSOLUTE FINAL Eval (2026-03-15 15:16) — STOP

| 指标 | @2000 | @4000 | **@6000** | @4000→@6000 |
|------|-------|-------|-----------|-------------|
| ped_R | 0.7646 | 1.0000 | **1.0000** | — |
| car_R | 0.000 | 0.000 | **0.000** | — |
| bg_FA | 0.921 | 1.000 | **1.000** | 🔴 仍 1.0 |
| off_cx | 0.309 | 0.279 | **0.300** | 🔴 恶化 |
| off_cy | 0.146 | 0.193 | **0.198** | 🔴 恶化 |
| off_w | 0.087 | 0.084 | **0.087** | 🔴 恶化 |
| off_h | 0.038 | 0.038 | **0.038** | — |
| off_th | 0.192 | 0.280 | **0.252** | ✅ 唯一改善 |

**决策: STOP — 训练已终止 (03/15 15:25)**
- bg_FA=1.0 连续两个 checkpoint — marker saturation 确认
- offset 仅 1/5 改善 (off_th), 4/5 恶化或持平
- car_R=0 连续三个 checkpoint
- token_drop_rate=0.3 未能阻止 marker saturation collapse

### 检查点历史

| 检查点 | 时间 | 结果 |
|--------|------|------|
| ✅ @2000 | 03/15 07:19 | ped_R=0.76, bg_FA=0.92, 初步非 frozen |
| ⚠️ @4000 | 03/15 11:17 | bg_FA=1.0 marker saturation, CONDITIONAL PROCEED |
| 🔴 @6000 | 03/15 15:16 | bg_FA=1.0 持续, offset 恶化, **STOP** |

### 历史 Eval 数据 (GiT-Large v1 单层, 已终止)

> 以下数据来自 ORCH_043 之前的单层 ViT-L 训练，该训练已确认为 frozen predictions，数据仅供参考。

<details>
<summary>展开查看历史 eval 数据</summary>

#### @2000 Eval (2026-03-14 05:40)
- 9/10类 R=0, off_th=0.078 (优于 024), 分类器冷启动慢

#### @4000 Eval (2026-03-14 10:36)
- Critic: CONDITIONAL PROCEED, 发现 BUG-62

#### @6000 Eval (2026-03-14 16:59)
- off_th=0.094 (项目历史最佳), bicycle NEW, car_R=0
- Critic: CONDITIONAL PROCEED @8000 FINAL
- 但后续确认为 frozen predictions 假象

#### P2+P3 @6000 (ORCH_043, 2026-03-15 01:26)
- car_R=0.582 — 但 BEV 可视化确认仍为 frozen predictions
</details>

### 里程碑

| 里程碑 | 时间 | 行动 |
|--------|------|------|
| ✅ Frozen 根因确认 | 03/15 03:05 | P2+P3 不充分, TF mode collapse 是根因 |
| ✅ ORCH_044 停止 | 03/15 03:00 | 前提错误 (无 anti-collapse), iter_440 reg_loss=0 |
| ✅ ORCH_045 启动 | 03/15 03:20 | 多层+适应层+token corruption 从零训练 |
| ⭐ @2000 eval | 03/15 07:19 | **ped_R=0.7646, bg_FA=0.92, car_R=0** — 非 frozen, CONDITIONAL PROCEED |
| **@4000 eval** | **~03/15 15:00** | **car_R 是否激活? offset 改善? bg_FA 下降?** |
| @8000 eval | ~03/16 01:00 | 架构决策级评估 |

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
| ✅ | 03/13 20:27 | **score_thr 消融 (ORCH_041)** | thr=0.5: bg_FA -47% 但 truck_R -77% | car_R=0 全阈值=BUG-17/mode collapse |
| ⭐ | 03/13 22:17 | **CEO 可视化 (ORCH_024@8k)** | 5 样本 BEV pred vs GT | 387-393/400 cell 正样本 |
| 🚨 | 03/14 00:30 | **Mode Collapse 根因诊断** | 零增强+teacher forcing→模型记忆先验 | diff/Margin 7.9%→2.3% |
| ⭐⭐ | 03/14 01:08 | **GiT-Large v1 训练启动** | P0(增强)+P1(ViT-L 1024-dim) | 训练运行中 |
| ⚠️ | 03/14 05:40 | **GiT-Large v1 @2000 eval** | 9/10类 R=0, off_th=0.078 优于024 | 分类器冷启动慢, 继续到@4000 |
| 🚨 | 03/14 10:36 | **GiT-Large v1 @4000 eval** | 9/10类 R=0, ped_R=0.025, bg_FA=0.115 | Critic: CONDITIONAL PROCEED, BUG-62 clip_grad 是首因 |
| ✅ | 03/14 11:10 | **ORCH_042 修复 + resume** | BUG-62/63/17 修复, 2-GPU resume from iter_4000 | grad_norm 3x 提升验证, batch 32→16 |
| ⭐⭐ | 03/14 16:59 | **GiT-Large v1 @6000 eval** | off_th=0.094 (历史最佳!), bicycle_R=0.010 NEW, car_R=0, bg_FA=0.025 | Critic: CONDITIONAL PROCEED, @8000 ABSOLUTE FINAL |

| ⭐ | 03/14 19:22 | **TF vs AR 诊断** | TF≈AR (差异<1%), 1200/1200 slots 全正, 2/10类 | **不是 exposure bias，是位置信息缺失** |
| 🔄 | 03/14 19:35 | **ORCH_043 签发** | P2+P3 修复后从 iter_4000 重启 | Admin 执行中 |
| ⭐⭐⭐ | 03/15 01:26 | **@6000 eval (P2+P3)** | **car_R=0.582!** bg_FA=0.680, off_th=0.254 | **P2+P3 确认有效! frozen predictions 消除** |
| 🔄 | 03/15 01:30 | **ORCH_044 签发** | 多层 ViT-L [5,11,17,23] + LN + 投影 4096→2048→1024 | CEO 指令执行 |
| 🚨 | 03/15 02:37 | **BEV 可视化 → frozen 确认** | P2+P3 @6000 预测仍 frozen, car_R=0.582 是假象 | smoking gun: 噪声/全零→输出一样 |
| ❌ | 03/15 03:00 | **ORCH_044 停止** | reg_loss=0 @iter_440, 无 anti-collapse 前提错误 | PID 1626949 已 kill |
| 🔄 | 03/15 03:20 | **ORCH_045 启动** | 多层+适应层+token corruption 从零训练 | **当前活跃实验** |

---

## 长期战略路线图

> 综合所有 VERDICT 审计结论。按阶段排列，每阶段内按优先级排序。
> 各阶段之间有依赖关系，但同阶段内的项目可并行或独立决策。

### Phase 1: 基础修正 (已完成 — ORCH_035 终止)
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

### Phase 3: ★ DINOv3 ViT-L + GiT-Large (⭐ 当前 — GiT-Large v1 训练中)
> 目标: 从 7B frozen + 10M adapter 切换到 ViT-L + GiT-Large, 同时修复 mode collapse
> 状态: **P0+P1 已部署, 训练中 iter 100/40000**
> CEO 决策: 2026-03-12, 分析论文后确认优先路线 B; 2026-03-14 批准立即实施

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
| ORCH_041 | score_thr 消融 (cls_probs, 4-GPU DDP) | ✅ DONE — thr=0.5 bg_FA-47%, 确认 car_R=0 全阈值 |
| **ORCH_042** | **BUG-62/63/17 修复 + iter_4000 resume** | ✅ **COMPLETED** — commit `4ad3b0f`, 2-GPU resume 11:10, PID 1312401 |
| **ORCH_043** | **P2+P3 修复后从 iter_4000 重启训练** | ✅ **COMPLETED** — @6000 car_R=0.582, P2+P3 确认有效 |
| **ORCH_044** | **多层 ViT-L + LN + 投影 (无 anti-collapse)** | **STOPPED** @iter_440 — reg_loss=0 mode collapse, 前提错误, PID 1626949 已 kill |
| **ORCH_045** | **多层+适应层+token corruption 从零训练** | 🔴 **STOPPED** @6000 — bg_FA=1.0 marker saturation, 训练已终止 03/15 15:25 |
| **ORCH_049** | **BUG-73 修复 (FG/BG=1x)** | 🔴 **FAILED** @500 — all-negative collapse, 0/1200 positive, TP=0 |
| **ORCH_050** | **FG/BG=3.3x + cell-level grid_pos_embed dropout** | 🔴 **FAILED** @200 — EARLY STOP, 0/1200 positive, dropout 破坏定位 |
| **ORCH_051** | **纯 FG/BG=3.3x，无 dropout（隔离变量）** | 🔴 **FAILED** @200 — EARLY STOP, 1200/1200 all-positive |
| **ORCH_052** | **FG/BG=1.67x (marker_pos_punish=1.0, bg_balance_weight=3.0)** | 🔴 **FAILED** @200 — EARLY STOP, 0/1200 all-negative |
| **ORCH_053** | **bg_balance_weight=4.0 二分搜索** | 🔴 **FAILED** @200 — all-negative |
| **ORCH_054** | **复现 ORCH_049 + 多点 frozen-check** | ⚠️ **INVALID** — 单 GPU 执行，与 ORCH_049 的 DDP 不可比(BUG-78) |
| **ORCH_055** | **2-GPU DDP 复现 ORCH_049 + 多点 frozen-check** | ✅ **DONE** — 完整崩塌轨迹: @100 HEALTHY, @300→@400 相变 |
| **ORCH_056** | **低 LR resume 实验** | 🔴 **FAILED** @200 — saturation=0.998, 低 LR 加速模板化 |
| **ORCH_057** | **架构变更: marker_no_grid_pos** | 🔴 **FAILED** @100 — saturation=1.0, 移除位置编码反而加速全正崩塌 |
| **ORCH_058** | **marker_step_no_pos (Critic CONDITIONAL 实现)** | 🔴 **FAILED** @100 — EARLY STOP, IoU=1.0, sat=1.0, 全面崩塌 |
| **ORCH_059** | **BUG-82 marker_init_bias** | 🔴 **FAILED** — all-negative collapse, bias 翻转方向但不阻止模板化 |
| ORCH_030 | 多层特征代码实现 | ✅ DONE (commit `8a961de`) |
| ORCH_031 | BUG-54/55 修复 | ✅ DONE (commit `dba4760`) |

已完成归档: ORCH_001-033 (详见 `shared/logs/archive/verdict_history.md`)

---

## BUG 跟踪

### 活跃 BUG

| BUG | 严重性 | 摘要 | 计划修复阶段 |
|-----|--------|------|------------|
| **BUG-69** | **CRITICAL** | adaptation layers lr_mult=0.05 — paramwise_cfg substring match 导致 25.2M 适应层参数实际冻结 (lr=2.5e-6) | **ORCH_046 修复: adapt_layers lr_mult → 1.0** |
| **BUG-62** | **CRITICAL** | clip_grad=10.0, 有效梯度仅 0.33% | **ORCH_046 修复: → 50.0** |
| **BUG-70** | HIGH (纠正) | Critic VERDICT_ORCH045_AT2000 错误声明"零数据增强" — PhotoMetricDistortion 一直在 config 中 | 根因分析已修正 |
| **BUG-66** | HIGH | token_drop_rate=0.3 效果有限 | 降级为辅助措施 |
| **BUG-67** | HIGH | adaptation layers 初始化 + clip_grad 交互 | clip_grad → 50 后缓解 |
| **BUG-68** | CRITICAL (流程) | Conductor 签发前未检查 CRITICAL bugs | 流程改进 |
| **BUG-64** | **HIGH** | `bert_embed` 应用 BERT-large 预训练权重加速分类器收敛 | v2 训练必要改动 |
| **BUG-65** | **HIGH** | off_cx 持续恶化 | 需数据增强后重新评估 |
| **BUG-61** | **HIGH** | reg_loss=0 频率 9.5% (ORCH_045), ALL-zero 3 次 | 与单类崩塌一致 |
| **BUG-45** | MEDIUM | OCC head 推理 attn_mask=None, 训练/推理不一致 | Phase 2 |

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
| BUG-62 | clip_grad 10→30 (ORCH_042, commit `4ad3b0f`) |
| BUG-63 | filter_invisible True→False (ORCH_042, commit `4ad3b0f`) |
| BUG-17 | max_class_weight=3.0 激活 (ORCH_042, commit `4ad3b0f`) |

### 已关闭 BUG (BUG-2~46, 详见 `shared/logs/archive/verdict_history.md`)
