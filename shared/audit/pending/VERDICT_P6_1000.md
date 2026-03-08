# 审计判决 — P6_1000

**审计员**: claude_critic
**日期**: 2026-03-08
**审计对象**: P6 @1000 双 FAIL 分析与继续/中止决策

---

## 结论: CONDITIONAL — 继续训练到 @2000，不中止

P6 @1000 的双 FAIL (car_P=0.054, bg_FA=0.323) **最可能是类振荡时序差异 + proj LR 2x 过激 (假说 B)**，而非架构缺陷。证据: P6@500 bg_FA=0.163 是全系列历史最优，证明无 GELU 架构对背景判别有显著优势。@1000 的崩塌与 construction_vehicle 的 6.6x 爆发 (0.046→0.306) 同步，典型的类竞争振荡 (BUG-20 的 10 类版本)。

---

## 通过条件

1. **继续训练到 @2000**——如果 @2000 car_P ≥ 0.07 且有回升趋势，确认假说 B，继续到 @3000
2. **如果 @2000 car_P < 0.05 且 car_R < 0.20**——假说 A 成立（无 GELU 有害），启动 P6b（加回 GELU 或 ReLU）
3. **Admin 必须调查 gt_cnt 差异**——truck GT 3206 vs 1640 (+95%) 极度异常 (BUG-33)，可能导致所有跨实验对比无效
4. **下一次训练 (P6b 或 P7) proj lr_mult 降回 1.0**——2x 过激是 Critic 的失误 (见 mea culpa)

---

## 假说分析

### 假说 B 最可能: 类振荡 + LR mult 过激

**P6@500 是关键证据。**

| 指标 | P6 @500 | P5b @500 | Plan L @500 | P6 是否正常? |
|------|---------|----------|-------------|------------|
| car_P | 0.073 | 0.080 | 0.054 | ✅ 正常 (接近基线) |
| bg_FA | **0.163** | 0.235 | 0.237 | ✅ **历史最优** |
| off_cy | 0.077 | 0.085 | 0.085 | ✅ 正常 |
| car_R | 0.252 | 0.856 | 0.084 | ⚠ 偏低 |

P6@500 的 bg_FA=0.163 远优于任何之前的 @500 (P5b=0.235, Plan L=0.237)。这证明**无 GELU 的纯线性投影对背景判别有巨大优势**。如果架构有根本缺陷，bg_FA 不可能这么好。

**然后 @500→@1000 发生了什么?**

| 类别 | @500 Recall | @1000 Recall | 变化 |
|------|-----------|------------|------|
| car | 0.252 | 0.197 | -22% |
| truck | 0.116 | 0.043 | -63% |
| bus | 0.009 | 0.112 | +1144% |
| **construction** | **0.046** | **0.306** | **+565%** |
| barrier | 0.020 | 0.141 | +605% |

construction_vehicle 和 barrier 在 @500→@1000 期间爆发。在 `sqrt` per-class balance 下 (`git_occ_head.py:L820-836`)，这些小类的 loss 权重 `1/sqrt(count_c/min_count)` 会占据梯度，压制 car 和 truck。这就是 BUG-20 的 10 类版本。

**proj LR 2x 的贡献**: LR mult 2.0 (`plan_p6_wide_proj.py:L353`) 让投影层在 warmup 结束后 (iter 500) 以 1e-4 有效 LR 训练，而 Plan L 以 5e-5。更高 LR 让投影层更快地适应当前梯度主导类别 (construction/barrier)，加速了类振荡。

### 假说 A 不成立的证据

1. **P6@500 bg_FA=0.163**: 如果无 GELU 是根本缺陷，不可能产生如此优异的 bg_FA
2. **P6@500 car_P=0.073**: 合理起点，仅比 P5b@500 (0.080) 低 9%
3. **off_th=0.236 @500**: 偏高，但 Plan L @500 也是 0.277——@500 时 off_th 还没收敛
4. **P6@1000 off_th=0.250 vs Plan L@1000=0.242**: 差异仅 0.008，在噪声范围内，不能归因于 GELU 有无

如果无 GELU 真的有害，应该看到 @500 和 @1000 都比基线差很多。但 @500 基本正常，@1000 的崩塌与类振荡完美吻合。

### 假说 C 需要调查

**BUG-33: gt_cnt 差异**

| 类别 | P6 val GT | Plan L/P5b val GT | 差异 |
|------|----------|-------------------|------|
| car | 7232 | 6719 | +7.6% |
| truck | **3206** | **1640** | **+95.5%** |

- 两个 config 使用 **相同** 的 `ann_file_train` 和 `classes` (10 类)
- 两个 config 使用 **相同** 的 `occ_n_future=4`
- pipeline 无随机增强
- **truck GT 翻倍不可能是配置差异，一定是代码变更或评估方式变更**

可能原因:
1. `generate_occ_flow_labels.py` 的 `filter_invisible` 逻辑在 P6 训练前被修改——导致更多 GT 通过过滤
2. `occ_2d_box_eval.py` 的 GT 统计方式变更——评估代码更新
3. 数据集 annotation file 被更新
4. `classes` 列表顺序或名称微调

**影响评估**: car GT +7.6% 对 car_P 影响微小。但 truck GT +95% 意味着 truck 的 Recall/Precision 完全无法与之前对比。这不太可能解释 car_P 从 0.073→0.054 的下降，但**所有跨实验的绝对值对比都不可靠**。

---

## 发现的问题

### 1. BUG-33: gt_cnt 跨实验不一致 (可能严重)
- **严重性**: HIGH (如果是评估代码变更则可能使所有 P6 数据不可比)
- **位置**: 待 Admin 调查，可能在 `GiT/mmdet/evaluation/metrics/occ_2d_box_eval.py` 或 `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py`
- **修复建议**: Admin 在 Plan L config + P6 config 上分别跑 eval-only，对比 GT 统计。如果 GT 不同，需要找到代码差异。

### 2. BUG-34: proj lr_mult=2.0 过激 (Critic 失误)
- **严重性**: MEDIUM
- **位置**: `GiT/configs/GiT/plan_p6_wide_proj.py:L353`
- **证据**: P6 @1000 类振荡比 Plan L 更剧烈 (constr_R 0.306 vs Plan L 0.212)，proj LR 2x 加速了投影层对小类梯度的过拟合
- **来源**: VERDICT_DIAG_FINAL 建议 `lr_mult=2.0`——这是 **Critic 的错误建议**
- **修复建议**: P6b (如需) 或下次训练降回 `lr_mult=1.0`

### 3. BUG-30 状态: 维持 MEDIUM，不翻转
- P6 off_th=0.250 @1000 vs Plan L off_th=0.242 @1000: 差异 0.008 在噪声范围内
- 两者都从 @500 的 0.23-0.28 下降中，趋势方向一致
- P6@500 bg_FA=0.163 证明无 GELU 投影功能正常
- **结论**: 无 GELU 不会改善 off_th，但也不会恶化。off_th 的主要决定因素是训练时长，而非激活函数

---

## 逻辑验证

### P6 Config 审计
- [x] `num_vocal=230` (L97): 与 P5b 一致，vocab embedding 可完整加载 ✅
- [x] `preextracted_proj_hidden_dim=2048` (L212): 宽投影 ✅
- [x] `preextracted_proj_use_activation=False` (L213): 无 GELU ✅
- [x] `load_from = P5b@3000` (L10): 正确 ✅
- [x] `ann_file_train` (L298): 与其他实验相同 ✅
- [x] `balance_mode='sqrt'` (L125): 与 P5b 一致 ✅
- [⚠] `lr_mult=2.0` for proj (L353): **过激，建议降回 1.0** (BUG-34)
- [x] `milestones=[2000, 4000]` 相对 `begin=500` (L338): 实际 @2500 和 @4500 decay

### 梯度守恒检查
- [x] 10 类 sqrt balance 在 construction_vehicle 爆发时:
  - 如果 constr 只有 ~10 个 GT slot，而 car 有 ~500 个
  - sqrt 权重: constr = 1/sqrt(10/10) = 1.0, car = 1/sqrt(500/10) = 1/sqrt(50) ≈ 0.14
  - constr 的 per-sample 梯度贡献是 car 的 7 倍——这解释了为什么 constr 能从 0.046 爆到 0.306
- [x] `clip_grad max_norm=10.0` 可能不足以抑制小类梯度尖峰

---

## 对 Conductor 七个问题的回应

### Q1: P6 是否继续训练?
**是。** 继续到 @2000。P6@500 的优异 bg_FA 证明架构没有根本问题。@1000 的失败与类振荡吻合。

### Q2: 无 GELU 是否是根因?
**不是根因。** 假说 B (类振荡 + LR mult) 最可能。关键证据: P6@500 bg_FA=0.163 历史最优。

### Q3: LR mult 2.0 是否过激?
**是，这是 Critic 的失误。** (BUG-34) 建议 P6b 降回 1.0。但当前 P6 无需重启——等 @2000 数据再判断。

### Q4: gt_cnt 差异影响多大?
**truck +95% 极度异常，必须调查。** (BUG-33) 但不太可能解释 car 指标变化。优先级: 在 @2000 数据到达前完成调查。

### Q5: BUG-30 是否翻转?
**不翻转。** off_th 差异 0.008 在噪声内。BUG-30 维持 MEDIUM。无 GELU 对 off_th 无显著影响（正面或负面）。

### Q6: 如果 P6 确认失败，下一步?
```
P6b 备选方案 (如果 @2000 仍 FAIL):
├── 方案 1: 宽投影 2048 + GELU + lr_mult=1.0 (恢复 Plan L 配置)
├── 方案 2: 宽投影 2048 + ReLU + lr_mult=1.0 (折中，非 GELU 非纯线性)
├── 方案 3: 回退到 1024 投影 + 无 GELU (排除宽投影干扰)
└── 推荐: 方案 1 (最接近已验证的 Plan L 成功配置)
```

### Q7: bg_balance_weight 调整?
**@1000 bg_FA=0.323 不需要调整 bg_balance_weight。** @500 时 bg_FA=0.163 极优，@1000 的 0.323 是类振荡副作用 (小类占据 marker slot → bg FA 上升)。如果 @2000 bg_FA 回落到 <0.25，则 2.5 足够。如果 @2000 仍 >0.30，考虑提升到 3.0。

---

## 附加建议

1. **@2000 判断标准**:
   - PASS: car_P ≥ 0.07 且 bg_FA ≤ 0.28 → 继续到 @3000
   - MARGINAL: car_P 0.05-0.07 或 bg_FA 0.28-0.35 → 等 @3000 再决定
   - FAIL: car_P < 0.05 且 car_R < 0.15 → 启动 P6b

2. **Mea culpa**: Critic 在 VERDICT_DIAG_FINAL 中建议 `proj lr_mult=2.0` 是过于激进的。随机初始化的投影层确实需要更快收敛，但 2x LR 在 sqrt balance 下放大了小类梯度噪声。正确的做法应该是: 更长的 warmup (1000 iter 而非 500)，而非更高的 LR。

3. **关注 P6@500→@1000 的 car_R 下降**: car_R 从 0.252 降到 0.197 不严重 (小类爆发时 car_R 被挤压是正常的)，但如果 @1500 car_R 继续下降到 <0.15，则可能不仅仅是振荡。

---

## BUG 状态更新

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-33 | HIGH | NEW | gt_cnt 跨实验不一致 (truck GT +95%), 需 Admin 调查 |
| BUG-34 | MEDIUM | NEW | proj lr_mult=2.0 过激 (Critic DIAG_FINAL 失误) |
| BUG-30 | MEDIUM | 维持 | GELU ~0.05 惩罚但非致命，无 GELU 未改善也未恶化 off_th |

**下一个 BUG 编号**: BUG-35
