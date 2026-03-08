# 审计判决 — P5B_3000

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: P5b@3000 中期评估与 P6 启动决策

---

## 结论: CONDITIONAL

P5b 在@3000 达成 3/5 红线（bg_FA=0.217, off_th=0.200, car_P=0.107），但 bus/trailer 振荡 (BUG-20) 和 off_th 退化 (BUG-21) 暴露了根本性的数据和架构问题。不建议继续 P5b 后半程；建议以 P5b@3000 为起点启动 P6，但须满足以下条件。

---

## 通过条件（必须全部满足方可启动 P6）

1. **P6 必须基于 P5b@3000 checkpoint**——bg_FA 和 car_P 均为历史最优，不可用其他 ckpt
2. **P6 Phase 0 必须先做单类 car 诊断实验**——隔离 Precision 瓶颈根因（数据不足 vs 架构缺陷）
3. **bus/trailer 振荡 (BUG-20) 在 mini 数据集上不可修复**——P6 须使用 full nuScenes 或放弃这两类
4. **off_th 退化 (BUG-21) 须在 P6 中排查**——双层投影 GELU 是否损害方向特征需要对比实验

---

## 发现的问题

### 1. BUG-20: bus/trailer 零和振荡 — nuScenes-mini 样本不足 (致命)
- **严重性**: HIGH
- **位置**: 数据层（非代码 BUG）
- **证据**:
  - bus_R 轨迹: @1000:0.368 → @1500:0.000 → @2000:0.085 → @2500:0.470 → @3000:0.051
  - 振荡周期 ~1000 iter，sqrt 权重 (L821-836 `git_occ_head.py`) 和 LR decay 均无效
  - nuScenes-mini 仅 ~120 bus 标注横跨 ~40 张图，有效梯度信号极弱
  - `balance_mode='sqrt'` (config L146) 降低极少类权重噪声，但无法创造新样本
- **结论**: mini 数据集上 bus/trailer 不可能稳定收敛。sqrt 权重设计正确但治标不治本。
- **修复建议**: P6 必须扩展到 full nuScenes（28130 train images），或在 mini 阶段仅训练 car/truck 两类

### 2. BUG-21: off_th 退化 0.142→0.200 — 双层投影 GELU 疑似损害方向特征
- **严重性**: MEDIUM
- **位置**: `GiT/mmdet/models/backbones/vit_git.py:L106-109`
- **证据**:
  - P5 单层 Linear(4096→768): off_th=0.142 (历史最佳 @4000)
  - P5b 双层 Linear(4096→1024→GELU→768): off_th=0.200 (@3000)
  - GELU 的非线性可能破坏 theta 编码中的方向信息
  - `theta_group` 和 `theta_fine` 依赖精确的特征方向保持
- **对比**: car_P 改善 0.090→0.107 (双层投影在分类上有效)，但几何回归退化
- **修复建议**: P6 Phase 0 对比实验——方案 A (单层 Linear 4096→768) vs 方案 D (双层 4096→2048→768 无 GELU) vs 当前 (双层 + GELU)

### 3. BUG-22: P5b 后半程无价值 — LR 衰减至 5e-7 后模型冻结
- **严重性**: MEDIUM
- **位置**: `configs/GiT/plan_i_p5b_3fixes.py:L351-352`
- **证据**:
  - @3000 后 LR = 5e-6 (第一次 decay 后), @4000 将降至 5e-7
  - P5 的教训: @4000-@6000 期间 car_P 标准差仅 0.0015，完全停滞
  - config 注释 `milestones=[2000, 3500]` 相对 `begin=500`，实际 @2500 和 @4000 decay
  - @4000-@6000 的 5e-7 LR 不可能产生任何有意义更新
- **结论**: P5b 后半程可安全终止。继续跑到 6000 iter 浪费 GPU 时间。

---

## 逻辑验证

### 梯度守恒检查
- [x] `clip_grad max_norm=10.0` (config L385): BUG-9 修复生效，梯度不被截断
- [x] `accumulative_counts=4` (config L383): effective batch=16 (2×2GPU×4acc)，梯度累积正确
- [x] per_class balanced loss (L820-836): sqrt 权重计算 `1/sqrt(cnt/min_count)` 数学正确
- [x] IBW 能量守恒 (L486-492): `energy_scale = total_slots_filled / weighted_sum`，确保总梯度量级不变

### 边界条件检查
- [x] `slot_class clamp(0, num_classes-1)` (L818): 背景 slot 的 class index 被钳制到有效范围
- [x] 空 cell 处理 (L433-438): `neg_cls_w=0.3` 权重正确赋予 END marker
- [x] `marker_end_id` 判断 (L814-815): `is_real_car_gt` 和 `is_bg_gt` 互斥，无重叠
- [⚠] BUG-13 仍存在: `slot_class` 对背景 clamp 到 0 导致背景被计入 car 类的 sqrt 权重分母，但影响小 (LOW)

### 数值稳定性检查
- [x] `clamp_min(1.0)` 保护除法 (L866, L870, L900, L905 等多处)
- [x] Focal Loss 路径中 `_focal_cross_entropy` 使用 `F.cross_entropy` + power，数值稳定
- [x] theta 回归权重 `l_th_group * 1.2 + l_th_fine` (L1026): 固定系数，无 NaN 风险

---

## 红线达标分析

| 红线指标 | 阈值 | P5b@3000 | 状态 |
|----------|------|----------|------|
| truck_R | ≥0.08 | 0.205 | **达标** |
| bg_FA | ≤0.25 | 0.217 | **达标** (历史最优) |
| off_th | ≤0.20 | 0.200 | **边界达标** (精确等于阈值) |
| off_cx | ≤0.05 | 0.059 | **未达标** |
| off_cy | ≤0.10 | 0.112 | **未达标** |

3/5 红线达标。off_cx (0.059 vs 0.05) 和 off_cy (0.112 vs 0.10) 仍超标，但差距在缩小。

---

## Checkpoint 选择分析

| 候选 | 优势 | 劣势 | 推荐度 |
|------|------|------|--------|
| @1000 | off_th=0.168 最优 | bg_FA=0.302 超标, trailer=0 | 不推荐 |
| @2500 | bus=0.470, trailer=0.444 | bg_FA=0.283, off_th=0.212 | 不推荐 (不稳定) |
| **@3000** | **bg_FA=0.217, car_P=0.107** | off_th=0.200 边界 | **推荐** |

**结论: P6 必须从 P5b@3000 启动。** 理由：
1. bg_FA=0.217 是 P5 谱系中唯一突破 0.25 红线的 checkpoint
2. car_P=0.107 历史新高，说明分类能力在增长
3. @2500 的 bus/trailer 高值是振荡峰值而非稳定收敛，不可信赖

---

## P6 路线图建议

### Phase 0: 单类 car 诊断 (3000-5000 iter)
- 目的: 隔离 Precision 瓶颈根因（数据不足 vs 架构缺陷 vs off_th 退化）
- Config: 仅训练 car 类，去掉 per_class_balance
- 对比投影方案: 单层 Linear vs 双层 GELU vs 双层 宽中间层 2048 无 GELU
- 预期: 如果单类 car_P 显著上升 (>0.15)，说明 multi-class 干扰是主因

### Phase 1: 数据扩展或架构改进 (根据 Phase 0 结果)
- 路径 A: Full nuScenes (28130 images) — 解决 BUG-20，但需要 DINOv3 特征提取
- 路径 B: DINOv3 在线提取 + LoRA — 需确认 GPU 显存（4×A6000 48GB 理论可行）
- 路径 C: 保持 mini + 只训练 car/truck — 快速验证上限

### P5b 后半程: 建议终止
- @3000 后的 LR (5e-6) 在 P5 中已证明不足以推动改进
- @4000 后 LR 降至 5e-7，完全停滞
- 继续跑 3000 iter 的 GPU 成本 > 用同样时间启动 P6 Phase 0

---

## 附加建议

1. **DINOv3 特征存储策略 (BUG-26)**: 仅提取 CAM_FRONT，fp16 格式约 175GB (非全 6 相机 2.1TB)
2. **评估指标缺陷 (BUG-18)**: 当前评估无跨 cell instance 关联，`g_idx` 已存在于 `gt_projection_info_list` 但未用于评估。P6 阶段可考虑加入 instance-level mAP
3. **Focal Loss 未启用**: config 中 `use_focal_loss=False` (L139)。P6 可考虑在 Phase 1 开启 Focal Loss 替代 CE+punish 模式
4. **center_weight/around_weight**: 2.0/0.5 的几何加权对大物体不利（大物体大部分 cell 是 around），但在 mini 数据集上影响有限

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-20 | HIGH | OPEN | nuScenes-mini bus/trailer 样本不足 (~120 标注) 导致零和振荡 |
| BUG-21 | MEDIUM | OPEN | 双层投影 GELU 疑似损害方向特征 (off_th 0.142→0.200) |
| BUG-22 | MEDIUM | 确认 | P5b 后半程无价值, LR 5e-7 导致模型冻结 |

**下一个 BUG 编号**: BUG-23
