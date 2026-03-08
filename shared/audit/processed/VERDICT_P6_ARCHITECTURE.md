# 审计判决 — P6_ARCHITECTURE

## 结论: CONDITIONAL

**条件：必须先做诊断实验（单类 car）确认瓶颈来源，再选择架构方案。P6 优先级排序见第六节。**

---

## 一、关键事实纠正

### BUG-23: 审计请求中 GPU 显存信息错误
- **严重性**: HIGH（影响所有架构决策）
- **位置**: `AUDIT_REQUEST_P6_ARCHITECTURE.md:L96`
- **描述**: 请求称"20.5 GB 已接近 24 GB 上限"。**实际为 4× RTX A6000 (48 GB each)**，GPU 1 和 GPU 3 完全空闲 (48.5 GB free)。

```
GPU 0: A6000 49GB, used 20.5GB, free 28.1GB
GPU 1: A6000 49GB, used 0GB, free 48.5GB  ← 完全空闲
GPU 2: A6000 49GB, used 21GB, free 27.5GB
GPU 3: A6000 49GB, used 0GB, free 48.5GB  ← 完全空闲
```

**影响**: DINOv3 ViT-G (~1.1B 参数) fp16 约需 2.2GB 权重 + ~10GB 激活。48GB GPU 完全可以容纳 DINOv3 在线提取。方案 B/C 的显存约束大幅放松。

---

## 二、P5b 是否触顶

### 2.1 数据证据

P5b @3000-5500 数据表明**完全冻结**：

| 指标 | @3000 | @3500 | @4000 | @4500 | @5000 | @5500 | 标准差 |
|------|-------|-------|-------|-------|-------|-------|--------|
| car_P | 0.107 | 0.108 | 0.105 | 0.105 | 0.105 | 0.104 | 0.0015 |
| bg_FA | 0.217 | 0.214 | 0.211 | 0.210 | 0.210 | 0.209 | 0.003 |
| off_th | 0.200 | 0.206 | 0.196 | 0.202 | 0.201 | 0.202 | 0.003 |

**结论：P5b 双层投影 (4096→1024→GELU→768) 在 nuScenes-mini 上已触顶。** 第二次 LR decay @4000 (5e-6→5e-7) 后模型几乎不再更新。car_P≈0.105 是此架构+数据的上限。

### 2.2 瓶颈定位

| 假设 | 证据 | 可能性 |
|------|------|--------|
| 特征压缩损失 (4096→768 丢信息) | off_th 从 P5 的 0.142 退化到 0.200 (BUG-21) | **高** |
| 数据量不足 | mini 仅 323 图, bus/trailer 振荡 (BUG-20) | **高** |
| 类间竞争 | 10 类 loss 相互干扰 | **未验证** |
| 模型容量不足 | ViT-Base (86M) 可能不够 | **低** (car 的 R=0.8+ 说明容量够) |

---

## 三、方案逐项审计

### 3.1 方案 A (已完成): 双层投影
- **状态**: P5b 已实现并触顶
- **判决**: 不再追加层数。**更深不等于更好**——4096→1024→768 的信息瓶颈在 1024 维，而非层数。

### 3.2 方案 D (宽中间层): 4096→2048→768
- **优先级**: **最高**（最小改动，最快验证）
- **位置**: `vit_git.py:L104-109`
- **改动**: `preextracted_proj_hidden_dim=2048` (config 一行改动)
- **参数增量**: ~4096×2048 + 2048×768 ≈ 10M (vs 当前 ~5M)，可忽略
- **理论收益**: 中间层从 1024→2048 减少信息压缩比从 4:1→2:1，off_th 退化可能缓解
- **风险**: 极低

### 3.3 方案 C (LoRA): DINOv3 最后 2-4 层 LoRA
- **优先级**: 第二
- **实施**: 需要修改 `PreextractedFeatureEmbed` 为在线提取模式 + 引入 peft 库
- **位置**: `vit_git.py:L91-150` 需要重构
- **显存估算**: DINOv3 ViT-G fp16 权重 ~2.2GB + LoRA 参数 ~5-20MB + 激活 ~8GB ≈ 10-12GB。48GB GPU 完全够
- **关键问题**: LoRA 要求 DINOv3 前向传播，**不能使用预提取特征**。这意味着需要先实现在线提取
- **副作用**: 自动解决 2.1TB 存储 BLOCKER

### 3.4 方案 B (Full Unfreeze): DINOv3 部分层解冻
- **优先级**: 最低（但在 48GB GPU 上可行）
- **显存估算**: DINOv3 fp16 + 6 层 gradient ≈ 2.2GB + 12-15GB ≈ 15-17GB。加上 GiT 本身 21GB = 36-38GB < 48GB。**可行但紧张**
- **风险**:
  - 灾难性遗忘（需 LR 1e-6 量级）
  - 调参维度爆炸
  - 训练速度大幅下降
- **建议**: 仅在方案 D 和 C 都失败后尝试

### 3.5 方案评估总结

| 方案 | 改动量 | 显存增加 | 解决存储 BLOCKER | 预期收益 | 实施风险 |
|------|--------|---------|-----------------|----------|---------|
| D (宽中间层) | 1 行 config | ~5MB | 否 | 中 | 极低 |
| C (LoRA) | 新增在线提取 | ~10-12GB | **是** | 高 | 中 |
| B (Full Unfreeze) | 大改 | ~15-17GB | **是** | 最高理论上限 | 高 |

---

## 四、关键问题逐一回答

### Q1: P5b 双层投影是否触顶？
**是。** @3000-5500 六个 checkpoint 的 car_P 标准差仅 0.0015，模型完全冻结。

### Q2: B vs C vs D 性价比？
**D > C > B。** 理由：
- D 成本近零，一行 config 改动。如果 2048 宽中间层能改善 off_th，说明瓶颈确实在压缩比
- C (LoRA) 需要实现在线 DINOv3 提取（~2 天工作量），但自动解决存储 BLOCKER
- B 调参维度太高，在 mini 上验证不充分，应留到全量 nuScenes

### Q3: 单类 car 实验是否值得做？
**必须做。** 这是整个 P6 决策链的根基。

分析：
- 如果单类 car_P >> 0.105（比如 >0.15）→ 类间竞争是瓶颈 → 需要 per-class head 或类别解耦
- 如果单类 car_P ≈ 0.105 → 特征质量/架构是瓶颈 → 需要方案 D/C/B
- 成本极低：mini 上 1000-2000 iter 即可观察趋势，训练 ~1 小时

**BUG-24**: 当前无单类训练 config。需要创建 `plan_k_car_only_diag.py`，设置 `classes=["car"]`, `num_classes=1`。

### Q4: 历史 occ box 单时刻 MVP 是否足够？
**足够，但 P6 不应包含历史 occ box。** 理由：
- 历史 occ box 是全新功能，引入了多个未知变量（编码方式、时间对齐、增益量化）
- P6 的核心目标应该是**验证全量 nuScenes 的训练效果**——这本身就是巨大变量
- 混合太多变量无法定位问题
- **建议**: 历史 occ box 放到 P7，P6 专注于数据量+架构改进

### Q5: 在线 DINOv3 提取可行性？
**完全可行。** 理由：
- GPU 1 或 GPU 3 完全空闲 (48.5GB free)
- DINOv3 ViT-G fp16 仅需 ~2.2GB 权重 + ~8GB 激活 = ~10GB
- 训练时 DINOv3 forward + GiT forward 可流水线化
- **存储 BLOCKER 彻底消失**
- 速度下降 ~30-50% 可接受（全量 nuScenes 训练时间从 ~20 小时变为 ~30 小时）

**BUG-25**: `PreextractedFeatureEmbed` (`vit_git.py:L91-150`) 目前硬绑定预提取模式，没有在线提取路径。需要新增 `OnlineDINOv3FeatureEmbed` 类或重构为双模式。

### Q6: P6 整体优先级排序？

```
Phase 0 (诊断, 1天):
  └→ 实验 α: 单类 car mini 训练 (plan_k_car_only_diag.py)
  └→ 实验 β: 方案 D 宽中间层 mini 训练 (proj_hidden_dim=2048)

Phase 1 (结论驱动分支):
  ├→ IF α car_P >> β car_P: 类竞争是瓶颈
  │   └→ P6a: 全量 nuScenes + 单类 car 训练 (验证数据量收益)
  │
  └→ IF α car_P ≈ β car_P: 特征/架构是瓶颈
      └→ P6b: 实现在线 DINOv3 + LoRA (方案 C)
      └→ P6b-mini: mini 上验证 LoRA 效果
      └→ P6b-full: 全量 nuScenes + LoRA

Phase 2 (增量):
  └→ P7: 历史 occ box (t-1) 编码
```

---

## 五、P6 Config (plan_j) 审计

### 5.1 词表兼容性
- **位置**: `plan_j_full_nuscenes.py:L6-7, L19`
- P5b 已用 10 类 config (`num_vocal=230`)，所以 P5b@3000 checkpoint 的 vocab embedding 已是 230 维
- **BUG-22 (已修正)**: P5b→P6 不存在词表不匹配问题。但新 6 类在 mini 上训练不充分。
- **建议**: P6 前 2000 iter 的 val 应重点观察新 6 类 (ped/moto/bicycle/cone/barrier/construction) 的 Recall 是否从零起步

### 5.2 LR Schedule
```python
# L346: milestones=[20000, 30000]  # relative to begin=1000
# 实际: @21000 第一次 decay (5e-5→5e-6), @31000 第二次 decay (5e-6→5e-7)
```
- 28130 samples / 16 effective batch = 1758 iter/epoch
- @21000 ≈ 12 epochs，@31000 ≈ 17.6 epochs，max_iters=36000 ≈ 20.5 epochs
- **合理**。12 epochs full LR + 5.6 epochs 0.1x + 2.8 epochs 0.01x 是标准三段式

### 5.3 Val Interval
- `val_interval=2000`，36000 iter 共 18 次验证
- 全量 nuScenes val set 6019 samples，每次验证 ~10 分钟
- **合理**

### 5.4 存储 BLOCKER
```python
# L220: preextracted_feature_dir='/mnt/SSD/GiT_Yihao/dinov3_features_full/'  # TODO: 待提取
```
- 28130 samples × ~76.6MB/sample (fp32) = ~2.1TB
- 仅前摄 (CAM_FRONT): 28130 × ~12.8MB ≈ 350GB (fp32) 或 ~175GB (fp16)
- SSD 剩余 528GB，fp16 前摄特征可以放下
- **但**: 如果走方案 C (LoRA) 或 B (unfreeze)，在线提取更优，无需存储

---

## 六、发现的问题

### BUG-23: GPU 显存信息错误 (已在 §一 描述)
- **严重性**: HIGH
- **位置**: `AUDIT_REQUEST_P6_ARCHITECTURE.md:L96`
- **影响**: 所有基于 24GB 上限的显存估算需要重新计算

### BUG-24: 缺少单类诊断 config
- **严重性**: MEDIUM
- **位置**: 缺失文件 `configs/GiT/plan_k_car_only_diag.py`
- **描述**: 单类 car 实验是决策关键，但当前无对应配置
- **修复**: 从 plan_i 复制，改 `classes=["car"]`, `num_classes=1`, `num_vocal=224`

### BUG-25: 无在线 DINOv3 提取路径
- **严重性**: HIGH
- **位置**: `vit_git.py:L91-150` (`PreextractedFeatureEmbed`)
- **描述**: 当前 PatchEmbed 只支持磁盘预提取模式。方案 C (LoRA) 和方案 B (unfreeze) 都需要在线前向传播
- **修复**: 需新增 `OnlineDINOv3Embed` 类，加载 DINOv3 权重，forward 时实时提取 layer_16 特征

### BUG-26: DINOv3 存储计算遗漏——仅需前摄特征
- **严重性**: MEDIUM
- **位置**: `plan_j_full_nuscenes.py:L12-17`
- **描述**: BLOCKER 描述称需 2.1TB，但代码中只用 CAM_FRONT（`generate_occ_flow_labels.py:L476`：`cam_front = results['cams']['CAM_FRONT']`）。仅前摄 fp16 ≈ 175GB，完全可以放入 SSD

---

## 七、逻辑验证

- [x] **梯度守恒**: 方案 D (宽中间层) 不改变梯度路径，仅增加中间维度。安全。
- [x] **边界条件**: P6 config 的 val_dataloader 使用独立 `ann_file_val`，不再用 train 集自评。**正确**。
- [x] **数值稳定性**: LoRA rank=16-64 的梯度范数远小于主模型，不会导致梯度爆炸。
- [x] **LR 相对性**: `milestones=[20000,30000]` 相对 `begin=1000`，实际 @21000/@31000 decay。与注释一致。

---

## 八、风险总结

| 风险 | 严重性 | 缓解 |
|------|--------|------|
| 单类 car 实验结果不明确 | MEDIUM | 设明确阈值: car_P>0.15 = 类竞争瓶颈 |
| 在线 DINOv3 训练速度下降 | MEDIUM | 用 fp16 + 异步 prefetch 优化 |
| P6 全量训练时间过长 | LOW | 36000 iter ≈ 20h (预提取) 或 30h (在线) |
| 10 类新类冷启动 | MEDIUM | 前 2000 iter 密切监控新类 Recall |

---

**判决签发: claude_critic**
**日期: 2026-03-08**
**BUG 编号更新: 下一个 BUG-27**
