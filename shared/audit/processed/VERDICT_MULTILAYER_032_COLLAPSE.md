# 审计判决 — MULTILAYER_032_COLLAPSE

## 结论: STOP

ORCH_032 @2000 的全面坍缩不是代码 bug，而是**训练设置根本性错误**。随机 16384→2048 投影的 8:1 压缩比在初始化时摧毁了太多信息，导致 ViT backbone 从未获得有意义的输入特征。继续训练不会恢复——模型已进入退化局部极小值。

---

## 发现的问题

### BUG-57 [CRITICAL] — proj.0 经过 2000 iter 仍停在 kaiming 初始化状态

**文件**: `vit_git.py:177-184`
```python
layers = [nn.Linear(effective_in_dim, proj_hidden_dim)]  # proj.0: 16384→2048
# ...
nn.init.kaiming_uniform_(m.weight, a=math.sqrt(5))
```

**实验验证**: 加载 iter_2000.pth checkpoint，对比 proj.0.weight 统计量：

| 模型 | shape | actual std | kaiming expected std | actual/expected |
|------|-------|-----------|---------------------|----------------|
| ORCH_024 (正常) | [2048, 4096] | 0.009060 | 0.009021 | **1.004** |
| ORCH_032 (坍缩) | [2048, 16384] | 0.004540 | 0.004511 | **1.007** |

**两个模型的 proj.0 权重都几乎没动** — actual/expected 比值 ≈1.00，说明 2000 iter warmup 中 proj.0 基本没有学习。

但 ORCH_024 依然能工作 (car_R=0.627)，因为随机 4096→2048 投影 (2:1 压缩) 保留了足够的特征结构；ORCH_032 的 16384→2048 (8:1 压缩) 则摧毁了 87.5% 的信息。

**根因链**:
1. `clip_grad max_norm=10.0` (`plan_full_nuscenes_multilayer.py:361`) — 训练全程梯度被截断
2. ORCH_024 grad_norm 中位数 ~35-40，ORCH_032 ~65-80 (**2× 高**)
3. 原因: proj.0 参数量 4× (33.6M vs 8.4M)，且输入维度高导致每个梯度分量 ~2× 大
4. 有效学习率: ORCH_024 ~10/35=28% 名义值，ORCH_032 ~10/80=12.5% 名义值
5. proj.0 收敛速度: ORCH_032 约需 ORCH_024 的 **8×** 迭代 (4× 更多参数 × 2× 更慢学习率)

**调试脚本**: `GiT/ssd_workspace/Debug/Debug_20260312/debug_032_collapse_analysis.py`

---

### BUG-58 [HIGH] — load_from=None 导致从零训练，backbone/head 无暖启动

**文件**: `plan_full_nuscenes_multilayer.py:12`
```python
load_from = None  # 从头训练, proj 层维度不同 (16384 vs 4096) 无法部分加载
```

**问题**: Conductor 为避免之前审计发现的 partial loading 问题 (BUG-55)，将 `load_from` 改为 None。但这过于保守 — ViT-GiT backbone (层 0-17) 和 OCC head 都完全随机初始化 (仅 SAM 预训练 backbone 加载)。

**对比**: 如果 `load_from=ORCH_024@2000`，mmdet 的 `load_checkpoint(strict=False)` 会:
- 跳过 `backbone.patch_embed.proj.0.weight` (shape 不匹配) ✓
- 加载 `backbone.patch_embed.proj.2.weight/bias` (shape 匹配) ✓
- 加载全部 backbone layers、OCC head ✓
- 此时 backbone 已知道如何处理 768-dim 输入，head 已知道如何解码预测
- 唯一随机的是 proj.0，但有暖启动的 backbone/head 作为稳定锚点

**建议**: 使用 `load_from=ORCH_029@2000` 或 `ORCH_024@any`，接受 partial load。

---

### BUG-59 [HIGH] — 16384→2048 压缩比 (8:1) 对随机初始化太激进

**文件**: `plan_full_nuscenes_multilayer.py:213`
```python
preextracted_proj_hidden_dim=2048,  # ★ 投影 16384->2048->GELU->768
```

**分析**: Johnson-Lindenstrauss 理论表明，随机投影从 d 维到 k 维时，距离失真比例 ∝ sqrt(d/k)：
- ORCH_024: 4096→2048, sqrt(4096/2048) = sqrt(2) ≈ **1.41×** 失真
- ORCH_032: 16384→2048, sqrt(16384/2048) = sqrt(8) ≈ **2.83×** 失真

2.83× 的距离失真意味着不同类别的特征在投影后几乎不可区分。下游网络无法从如此失真的特征中学习类别判别。

DINOv3 论文使用 **12 层 Transformer (100M 参数)** 作为适配层 (`shared/logs/reports/dinov3_paper_analysis.md`)。我们用 **2 层 MLP (33.6M 参数)**，容量严重不足。

**建议**: 将 `proj_hidden_dim` 从 2048 提升到 4096，将压缩比从 8:1 降至 4:1。

---

### BUG-60 [MEDIUM] — clip_grad max_norm=10.0 未针对多层架构调整

**文件**: `plan_full_nuscenes_multilayer.py:361`
```python
clip_grad=dict(max_norm=10.0, norm_type=2),
```

**训练日志证据**:

| 指标 | ORCH_024 (正常) | ORCH_032 (坍缩) | 比值 |
|------|----------------|----------------|------|
| iter 10 grad_norm | 37.91 | 81.51 | 2.15× |
| grad_norm 中位数 | ~35 | ~70 | 2.0× |
| grad_norm 峰值 | 70.48 | **164.0** (iter 790) | 2.33× |
| >100 的次数 (0-2000) | 0 | **16+** | — |
| 有效 lr (full lr 时) | ~28% | ~12.5% | 0.45× |

ORCH_032 的 grad_norm 系统性 2× 高于 ORCH_024，因为 proj.0 参数量 4× (33.6M vs 8.4M)。`clip_grad=10.0` 相对于 ORCH_032 的梯度尺度过于激进。

**建议**: 对多层 config 设置 `max_norm=30.0` 或更高。

---

## 逻辑验证

### 多层特征提取实现 — 正确

- [x] `get_intermediate_layers(n=[9,19,29,39])` 提取正确的 4 个 block 输出 (`vision_transformer.py:270-284`)
- [x] `torch.cat(features, dim=-1)` 沿最后维度拼接: (B, 4900, 4096×4) = (B, 4900, 16384) (`vit_git.py:234`)
- [x] 投影层 `Linear(16384, 2048)→GELU→Linear(2048, 768)` 正确构建 (`vit_git.py:176-181`)
- [x] DINOv3 norm 正确应用于每层输出 (`vision_transformer.py:297-306`)
- [x] `n_storage_tokens=0` for vit_7b，cls token 正确剥离 (`vision_transformer.py:309`)
- [x] 向后兼容性: `layer_indices=None` 时完全等价于单层模式 (`vit_git.py:215-236`)

### 梯度流通 — 通路正确但被截断

- [x] DINOv3 frozen (`torch.no_grad()`): 梯度不流入 DINOv3 — 正确 (`vit_git.py:226-229`)
- [x] proj 层 `requires_grad=True`: 梯度到达 proj — 正确
- [x] `lr_mult=2.0` for proj: 在 paramwise_cfg 中最长匹配规则生效 — 正确 (`plan_full_nuscenes_multilayer.py:365`)
- [⚠️] 梯度被 `clip_grad=10.0` 持续截断 >85%，有效更新极小

### 数值稳定性 — 无 NaN/Inf

- [x] 日志中未出现 NaN 或 Inf
- [x] Loss 值未发散 (最高 14.44 at iter 840)，仍在正常范围

### 零 reg_loss 事件 — 数据特征，非 bug

ORCH_032 在 2000 iter 内有 ~20 次 `loss_reg=0.0` 事件。ORCH_024 同期有 ~14 次，且发生在**相似迭代位置** (iter 240, 440, 580, 620, 630, 760, 800, 1050, 1130, 1520, 1600, 1700, 1710, 1720)。

原因: `_per_class_reg_loss()` (`git_occ_head.py:763-775`) 在 `(slot_class == c) & (weights > 0)` 全为 False 时返回 0。某些 batch 中前景 cell 数量极少或为零是 nuScenes 数据固有特征 (如空旷道路场景)。

**结论**: 零 reg_loss 不是坍缩原因，两个模型都有此现象。

---

## 模式坍缩机制分析

@2000 eval 结果:
```
car_recall=0.000, car_precision=0.000       (ORCH_024: R=0.627, P=0.079)
pedestrian_recall=0.8328, precision=0.0056  (ORCH_024: R=0.067, P=0.001)
bg_false_alarm_rate=0.3181                  (ORCH_024: 0.222)
所有其他类: R=0, P=0
```

**坍缩机制**:
1. 随机 proj.0 输出 ≈ 高斯噪声 (std 确认与 kaiming init 一致)
2. ViT backbone 处理噪声特征，OCC head 从噪声中无法区分类别
3. 模型找到 loss 最小路径: 所有前景 cell 预测为同一类 (pedestrian)
4. pedestrian 被选中可能因其几何特征 (小 bbox, 简单 offset) 使 reg_loss 最容易降低
5. 一旦进入此模式，loss landscape 锁定: head 专门学习 pedestrian 模式，其他类别权重萎缩

**不可恢复性论证**:
- 后续 iter 2010-2210: loss=4.5-8.5，仍在波动，但 cls_loss 占比持续偏高 (>60%)
- proj.0 权重仍然冻结在 kaiming init (2000 iter 没学到任何东西)
- 即使 proj 后续开始收敛 (需 >8000 iter)，head 已锁定在 pedestrian-only 模式
- 无外力干预 (reset head / 改训练策略)，极难跳出此局部极小值

---

## 对 Conductor 计划的评价

1. **ORCH_030/031 实现**: 代码正确，BUG-54/55 修复有效。实现不是问题。
2. **ORCH_032 训练决策有误**: `load_from=None` 从零训练是过度反应。BUG-55 审计建议 "接受 partial load 或排除 proj 参数"，Conductor 选择了最保守方案 (完全从零)，导致 backbone/head 失去暖启动优势。
3. **@4000 等待策略不可行**: 决策树假设 "从零训练可能慢一点但终会收敛"。checkpoint 分析表明 proj.0 在 2000 iter 后 **零学习**，且模型已坍缩。等到 @4000 只是浪费 ~6 小时 GPU 时间。
4. **clip_grad 未随架构调整**: 从 ORCH_024 复制训练超参到 ORCH_032，忽略了参数量 4× 增加对梯度范数的影响。

---

## 修复方案 (建议 Conductor 选择)

### 方案 A: 快速修复 (推荐，改动最小)
1. `load_from = ORCH_029@2000` 或 `ORCH_024@2000` — 给 backbone/head 暖启动
2. `clip_grad max_norm=30.0` — 匹配多层架构的梯度尺度
3. `lr_mult=5.0` for proj — 加速 proj 收敛
4. 其他不变，重新启动训练

### 方案 B: 架构优化
1. `preextracted_proj_hidden_dim=4096` — 降低压缩比到 4:1
2. 加入 per-layer LayerNorm: 每层特征独立归一化后再拼接
3. `load_from=ORCH_029@2000` + `clip_grad max_norm=30.0`

### 方案 C: 渐进训练
1. 从 ORCH_024@2000 加载，仅 proj.0 随机
2. 先冻结 backbone/head 500 iter，只训 proj
3. 解冻全部继续训练

**成本**: Kill 当前训练 + 重启，损失 ~4h GPU 时间。修复配置 <30 分钟。

---

## 需要 Admin 协助验证

- **假设**: `load_from=ORCH_029@2000` 的 partial load 会给出 backbone/head 暖启动，仅 proj.0.weight 跳过
- **验证方法**: 在 config 中设置 `load_from=ORCH_029@2000 iter_2000.pth`，启动训练，检查 mmengine 日志中的 "unexpected/missing keys" 输出
- **预期结果**: 仅 `backbone.patch_embed.proj.0.weight` 和 `backbone.patch_embed.proj.0.bias` 因 shape 不匹配被跳过，其余正常加载

---

## BUG 总结

| BUG | 严重性 | 阻断 | 摘要 |
|-----|--------|------|------|
| BUG-57 | CRITICAL | YES | proj.0 权重 2000 iter 后仍 = kaiming init，8:1 随机投影摧毁信息，模式坍缩不可恢复 |
| BUG-58 | HIGH | YES | load_from=None 导致全体从零训练，backbone/head 无暖启动 |
| BUG-59 | HIGH | — | 16384→2048 压缩比 (8:1) 对 2 层 MLP 太激进 |
| BUG-60 | MEDIUM | — | clip_grad=10.0 未随参数量调整，有效 lr 仅为名义值 12.5% |

**判决: STOP** — Kill ORCH_032 当前训练，按方案 A 或 B 修复后重启。
