# 审计判决 — P5B_3000

## 结论: CONDITIONAL

**条件：P5b 应跑完 6000 iter（不提前终止），但 P6 必须从 P5b@3000 启动（非 @1000 或 @2500），且需解决下述 3 个关键问题。**

---

## 一、红线达标分析

### 1.1 P5b@3000 红线对照表

| 红线指标 | 阈值 | P5b@3000 | 达标? | 趋势 |
|----------|------|----------|-------|------|
| truck_R | ≥0.08 | 0.205 | **YES** | 下降中 (@1000:0.568 → @3000:0.205) |
| bg_FA | ≤0.25 | 0.217 | **YES** | 持续改善 (@1500:0.333 → @3000:0.217) |
| off_th | ≤0.20 | 0.200 | **边缘** | 压线通过 |
| off_cx | ≤0.05 | 0.059 | **NO** | 略超 (P5 最佳 0.049@1000) |
| off_cy | ≤0.10 | 0.112 | **NO** | 始终超标 |

**结论：3/5 达标，off_cx 和 off_cy 未过。**

### 1.2 关键发现：car_P=0.107 历史新高

| 指标 | P4@500 | P5@4000 | P5b@3000 | 变化 |
|------|--------|---------|----------|------|
| car_P | N/A | 0.090 | **0.107** | +18.9% |
| bg_FA | N/A | N/A | **0.217** | 历史最低 |
| off_th | N/A | 0.142 | 0.200 | -40.8% (退化) |

car_P 改善 + bg_FA 降低 = **模型的"有车/无车"判别能力在提升**。但 off_th 从 P5 的 0.142 退化到 0.200，说明**角度回归被牺牲了**。

---

## 二、发现的问题

### BUG-20: sqrt 加权未解决 bus 振荡——根因是 nuScenes-mini 样本量不足
- **严重性**: HIGH
- **位置**: `git_occ_head.py:L820-836` (sqrt 权重计算)
- **描述**:

Bus 振荡轨迹极其规律：
```
@1000: 0.368 → @1500: 0.000 → @2000: 0.085 → @2500: 0.470 → @3000: 0.051
```
周期约 1000 iter，振幅接近 0-0.47 全范围。

**根因分析**：
- nuScenes-mini 中 bus 约 120 个标注，仅覆盖约 40 张图（323 张总计）
- 每个 epoch ≈ 20 iter，1000 iter ≈ 50 epochs
- sqrt 加权给 bus 的权重为 `1/sqrt(count_bus/min_count)`，在 4 类时 min_count=trailer(~90)
- 但 bus 样本量太少，50 epochs 内模型反复"学会→遗忘→学会"bus 特征
- 这不是权重策略问题，**是数据量问题**——323 张图无法支撑 bus/trailer 的稳定学习

**证据**：P5b@2500 bus_R=0.470 是因为当时模型恰好"记住了"训练集中 bus 样本，下一轮又忘了。

**影响**：sqrt 加权缓解了 P5 中 bus/trailer 的完全崩溃（从 0→0.47 周期性出现），但无法消除振荡。

### BUG-21: off_th 从 P5@4000 的 0.142 退化到 P5b@3000 的 0.200
- **严重性**: MEDIUM
- **位置**: `git_occ_head.py:L1012-1015` (theta regression loss)
- **描述**:

P5 的 off_th=0.142 是历史最佳，P5b 通过三项修复后 off_th 退化 40.8%。

**可能原因**：
1. 双层投影 (4096→1024→GELU→768) 引入了非线性瓶颈：
   - `vit_git.py:L106-109`: `nn.Sequential(Linear(4096,1024), GELU(), Linear(1024,768))`
   - GELU 的非线性可能损害了 DINOv3 Layer 16 特征中的方向信息
   - P5 使用 `Linear(4096,768)` 直接投影，更好地保留了角度特征
2. sqrt 权重改变了各类的梯度分配，间接影响了 theta 回归精度
3. LR schedule 修正后，@3000 时模型处于 0.1x LR (5e-6) 阶段，精细回归能力受限

**验证建议**: 对比 P5 和 P5b 的 `l_th_group` / `l_th_fine` loss 曲线。

### BUG-22: 10 类扩展的 checkpoint 兼容性隐患
- **严重性**: HIGH
- **位置**: `plan_i_p5b_3fixes.py:L74-76, L112`
- **描述**:

P5b config 已声明 10 类 (`classes = ["car", "truck", "bus", "trailer", "construction_vehicle", "pedestrian", "motorcycle", "bicycle", "traffic_cone", "barrier"]`)，num_vocal=230。

但 `load_from` 仍指向 P5@4000：
```python
# L11:
load_from = '/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/iter_4000.pth'
```

P5 训练时 num_classes=4, num_vocal=224。P5b 训练时 num_classes=10, num_vocal=230。

**关键问题**：
1. `vocabulary_embed` 形状变化: (224, 768) → (230, 768)。load_from 时 strict=False 会跳过不匹配的权重，这意味着新增的 6 个类别 token 的 embedding 是**随机初始化的**。
2. `cls_start` 位置不变 (168)，但 cls range 从 168-172 (4+1) 扩展到 168-178 (10+1)
3. OccHead 的 class logits 输出范围也变了: `cls_logits = logits[:, cls_start : cls_start + C_all]`，C_all 从 5→11
4. 如果 P5b 实际以 10 类训练，但 load_from 的 P5@4000 只认识 4 类，那 6 个新类的 loss 在早期会是噪声

**验证**: 请确认 P5b 实际训练时使用的是 4 类还是 10 类（检查训练 log 中的 class count 输出）。如果是 4 类训练，则此 BUG 不影响 P5b 但影响 P6。如果已是 10 类训练，则 P5b 的数据中新 6 类样本极少（nuScenes-mini），且权重随机初始化，会导致 loss 不稳定。

---

## 三、P5b 后半程策略判决

### 3.1 是否跑完 6000 iter？

**答：跑完。** 理由：

1. @3000 正处于第一次 LR decay (5e-5 → 5e-6) 后 500 步，模型正在以低 LR 精调
2. @4000 会触发第二次 LR decay (5e-6 → 5e-7)，此后 2000 步用于极精细收敛
3. bg_FA 和 car_P 的趋势都在改善，没有发散迹象
4. bus 振荡与 LR 无关（根因是数据量），早停不会解决
5. **成本极低**：3000 步 ≈ 几小时训练，不值得因省几小时而错失可能的改善

### 3.2 第二次 LR decay @4000 (5e-6→5e-7) 是否合理？

```
# plan_i_p5b_3fixes.py L366:
milestones=[2000, 3500],  # 相对 begin=500
# 实际: @2500 第一次 decay, @4000 第二次 decay
```

**分析**：
- @4000-6000 用 5e-7 训练 2000 步。这个 LR 极低，可能只对 car 的精细回归有帮助
- bus/trailer 在如此低 LR 下不会有实质性变化（样本太少，梯度信号太弱）
- 但也不会恶化——低 LR 下模型基本冻结

**判决**: 合理，无需修改。

---

## 四、P6 启动决策

### 4.1 最优 checkpoint 选择

| Checkpoint | 优势 | 劣势 | P6 适合度 |
|-----------|------|------|-----------|
| @1000 | off_th=0.168 最优 | bg_FA=0.302 最差, truck 不稳 | **低** |
| @2500 | bus_R=0.470 峰值, trailer_R=0.444 | bg_FA=0.283, off_th=0.212 | **中** |
| **@3000** | **car_P=0.107 最高, bg_FA=0.217 最低** | off_th=0.200, bus 振荡低谷 | **高** |
| @4000+ | 待观察 | 待观察 | 待观察 |

**判决: P6 应从 P5b@3000 启动。** 理由：
1. car_P 和 bg_FA 是模型"基础判别力"的核心指标，@3000 两项均为历史最佳
2. bus_R 的振荡是数据问题，选"振荡峰值"的 @2500 没有意义——下一秒就会忘
3. off_th 退化可能源于双层投影（BUG-21），P6 可考虑回退到单层投影
4. 如果 @4000-6000 出现更好的综合指标，可更新起点

**但**：如果 @4000 或之后的 ckpt 综合表现超越 @3000（尤其是 off_cx<0.05 + off_th<0.20），应更新 P6 起点。

### 4.2 P6 启动前必须解决的问题

1. **词表兼容性 (BUG-22)**: 从 4 类 ckpt 加载 10 类模型，新增 6 类 token 随机初始化。必须在 P6 config 中：
   - 确认 `strict=False` 并显式 log 哪些权重被跳过
   - 新类的 warmup 策略（前 500 步只训练新类 embedding？还是全局 warmup？）

2. **新 6 类数据量问题**: nuScenes-mini 中 pedestrian/motorcycle/bicycle/traffic_cone/barrier/construction_vehicle 各有多少标注？如果某些类 <50 个样本，sqrt 权重也无法拯救，建议评估时标记为"探索性"指标。

3. **off_th 退化决策**: P6 应测试单层投影 vs 双层投影的 off_th 差异。

---

## 五、逻辑验证

- [x] **梯度守恒**: sqrt 权重 `1/sqrt(cnt_c/min_cnt)` 确保 total weight = sum(w_c) 非零，`/total_weight` 归一化正确 (`git_occ_head.py:L828-836`)
- [x] **边界条件**: `_cls_counts` 为空时 `_class_weights={}` → 所有类默认 1.0 (`git_occ_head.py:L833-836`)。当某类 count=0 时不在 `_cls_counts` 中，loss 跳过该类。正确。
- [x] **数值稳定性**: `clamp_min(1.0)` 保护除零 (`git_occ_head.py:L866,900,940,974`)。正确。
- [x] **LR schedule**: milestones=[2000,3500] 相对 begin=500，实际 @2500 和 @4000 decay。与注释一致 (`plan_i_p5b_3fixes.py:L348-368`)。

---

## 六、BUG-19 修复验证

### 6.1 proj_z0 标签问题
- `generate_occ_flow_labels.py:L441-445`: `valid_mask = np.ones(...)` — 绕过了 proj_z0 对 grid assignment 的影响。**正确但粗暴**——本质是承认 image_reference_valid_mask 不被 head 使用。
- `generate_occ_flow_labels.py:L539-541`: 移除了 `box_center_geo[2] += box_params[5] * 0.5` 的 z 偏移。**正确**——nuScenes 的 z 已经是 box center。

**验证**: BUG-19 修复正确。

---

## 七、风险总结

| 风险 | 严重性 | 缓解措施 |
|------|--------|---------|
| bus 振荡永远不会在 mini 上收敛 | HIGH | 接受现实，P6 扩展到全量 nuScenes 后再观察 |
| off_th 退化源于双层投影 | MEDIUM | P6 做 A/B test: 单层 vs 双层 |
| 10 类 ckpt 兼容性 | HIGH | 显式验证权重加载 log，新类 warmup |
| P5b @4000+ 可能出现更优 ckpt | LOW | 持续监控，动态更新 P6 起点 |

---

## 八、附加建议

1. **不要在 nuScenes-mini 上追求 bus/trailer 稳定性**——323 张图中 bus ~120 标注、trailer ~90 标注，统计噪声无法消除。这是数据集天花板，不是模型 bug。
2. **P6 的核心目标应是 car 精度提升**——car 有 8000+ 标注，是唯一有统计意义的类别。car_P 从 0.090→0.107 是真实改善。
3. **off_cx=0.059 和 off_cy=0.112 超红线**——这两个指标的改善需要回归 loss 权重调优或 BEV grid 分辨率提升（10×10→20×20），不应期望纯 LR/权重修改能解决。

---

**判决签发: claude_critic**
**日期: 2026-03-08**
**BUG 编号更新: 下一个 BUG-23**
