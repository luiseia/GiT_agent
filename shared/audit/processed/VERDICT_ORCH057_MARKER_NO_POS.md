# 审计判决 — ORCH057_MARKER_NO_POS

## 结论: CONDITIONAL

方案方向正确——grid_pos_embed 是 marker 模板化的根因已被 ORCH_049-056 实验反复确认。但实现存在 **训练/推理路径不对称** 的隐患 (BUG-79)，必须在实现时处理。判决附带具体修改位置和实现方案。

---

## 特征流诊断结果

### ORCH_055 崩塌轨迹 — diff/Margin 趋势分析

| Checkpoint | diff/Margin | marker identical | NEAR/END | 判定 |
|------------|-----------|-----------------|----------|------|
| **ORCH_055 @100** | **54.6%** | 91.50% | 183/207 | ✅ 健康 |
| **ORCH_055 @500** | **4.2%** | 99.50% | 25/375 | 🔴 崩塌 |
| ORCH_048 @500 (参考) | 9.7% | 97.75% | 226/155 | 🔴 模板化 |

- **趋势**: diff/Margin 从 54.6% 暴跌至 4.2% — 🔴 CRITICAL — mode collapse 在 @100→@500 之间加剧
- **机制**: @100 模型尚在利用图像特征 (diff/Margin>50%); @300→@400 grid_pos_embed shortcut 优化效率更高, 在 LR 上升期抢占梯度; @500 模板完全固化
- **诊断结论**: grid_pos_embed 为 marker 提供的免费空间先验是唯一幸存的 shortcut 通道，所有超参干预均已失败

### ORCH_048 @500 完整特征流 (最新可用 checkpoint)

| 检查点                          | cross-sample 相对差异 | 判定  |
|--------------------------------|----------------------|-------|
| patch_embed_input (DINOv3投影后) | 4.96%                | ✅ 正常 |
| grid_interp_feat_layer0        | 4.92%                | ✅ 正常 |
| image_patch_encoded (backbone) | 1.68%                | ✅ 正常 |
| pre_kv_layer0_k                | 1.80%                | ✅ 正常 |
| pre_kv_last_k                  | 1.41%                | ✅ 正常 |
| decoder_out_pos0               | 2.23%                | ✅ 正常 |
| logits_pos0                    | 1.06%                | ✅ 正常 |
| pred_token_pos0 (argmax)       | 97.75% 相同          | 🔴 危险 |

- **图像信号幅值**: grid_interp=0.9983, grid_token=0.5609, 比率 178% — 图像信号 > 位置先验
- **结论**: 图像信号到达 logits 层 (全程 >1% rel_diff) 但在 argmax 决策中被 grid_pos_embed 模板碾压

---

## 配置审查结果

- [x] 数据增强: 有 (PhotoMetricDistortion + RandomFlipBEV) → ✅
- [x] Pipeline 分离: 是 (train_pipeline ≠ test_pipeline) → ✅
- [x] Position embedding: 有 (`git.py:L339-353`, grid_pos_embed 注入) → ✅ (但这正是问题根源)
- [x] 特征注入频率: 每步每层注入 (`decoder_inference:L1120,L1125-1129`) → ✅
- [x] Scheduled sampling: 无 (prefix_drop_rate=0.5 替代) → ✅ 等效

---

## 审计请求逐项回复

### Q1: grid_pos_embed 在代码中何时/如何被加到 input 中？精确修改位置

**grid_pos_embed 注入路径完整追踪:**

#### 创建与融合 (`git.py:L339-353`)
```
grid_pos_embed = resize_pos_embed(backbone.pos_embed, ...)  # 从 backbone 位置编码插值
grid_start_embed += grid_pos_embed                           # L353: 融入 grid_start_embed
```
此后 `grid_start_embed` = `task_embedding` + `grid_pos_embed`，两者不可分离。

#### 训练路径 (`git.py:L466→L553`)
```
grid_token = grid_start_embed          # L466: grid_token 包含 grid_pos_embed
...
select_grid_start_embed = select_grid_token.clone()  # L505
...
# L553: 每层 grid_feature 通过 get_grid_feature 重新注入 grid_start_embed
grid_feature = get_grid_feature(patch_embed, ref, select_grid_start_embed, grid_token[:,:,0,:], layer_id)
```
- `get_grid_feature` (`git.py:L627-641`):
  - layer_id=0: `grid_feature = grid_forward` (已含 grid_pos_embed)
  - layer_id>0: `grid_feature = grid_forward + grid_start_embed` (重新注入)
  - 然后: `grid_feature += grid_interp_feat` (加图像特征)
- `seq = [grid_feature, seq_embed]` (L554) — grid_feature 作为位置 0 被所有 token 通过 causal attention 看到

#### 推理路径 (`git_occ_head.py:L1049-1137`)
```
grid_token = grid_pos_embed.clone()    # L1096: 参数名误导, 实际是 grid_start_embed
...
x = x + grid_token.view(B*Q, 1, -1)   # L1120: 每个 pos_id 都直接加
...
if layer_id > 0:
    curr_x = curr_x + grid_token.unsqueeze(2)  # L1125-1126: 每层重新注入
```

**需要修改的精确位置:**

| 路径 | 文件 | 行号 | 当前逻辑 | 修改 |
|------|------|------|----------|------|
| 创建 | `git.py` | L345-353 | `grid_start_embed += grid_pos_embed` | 保留, 但同时保存 `grid_pos_embed_raw` |
| 训练 | `git.py` | L553 | `get_grid_feature(..., select_grid_start_embed, ...)` | 传入 `no_pos` 版本 |
| 训练 | `git.py` | L627-641 | `get_grid_feature` 定义 | 新增 `marker_no_pos` 参数 |
| 推理 | `git_occ_head.py` | L1096 | `grid_token = grid_pos_embed.clone()` | 额外保存 `grid_pos_embed_raw` |
| 推理 | `git_occ_head.py` | L1120 | `x = x + grid_token` | pos_id=0 时减去 grid_pos_embed_raw |
| 推理 | `git_occ_head.py` | L1125-1126 | `curr_x += grid_token` | pos_id=0 时减去 grid_pos_embed_raw |

### Q2: 是否可以仅对 marker step (pos_id=0) 移除而不影响 class/box steps？

**推理路径: 可以，简单直接。**

```python
# decoder_inference 修改 (git_occ_head.py:L1116-1120)
for pos_id in range(30):
    x = input_embed
    if pos_id == 0 and self.marker_no_grid_pos:
        # Marker step: 只加 task_embedding, 不加 grid_pos_embed
        x = x + (grid_token - grid_pos_embed_raw).view(B * Q, 1, -1)
    else:
        x = x + grid_token.view(B * Q, 1, -1)  # 原逻辑不变
```

同样在 L1125-1126:
```python
if layer_id > 0:
    if pos_id == 0 and self.marker_no_grid_pos:
        curr_x = curr_x + (grid_token - grid_pos_embed_raw).unsqueeze(2)
    else:
        curr_x = curr_x + grid_token.unsqueeze(2)
```

**训练路径: 需要更多工作，但可行。**

训练中，grid_feature 是 concatenated sequence 的位置 0，被所有 token 通过 causal self-attention 看到。无法选择性地对某些 token "隐藏" 位置 0 的内容。

**推荐的训练实现方案:**

1. 将 `grid_pos_embed` 从 `grid_feature` (位置 0) 中移除:
   - 在 `get_grid_feature` 中使用 `grid_start_embed_no_pos` (= task_embedding only)
   - 这样位置 0 = task_embedding + grid_interp_feats（图像特征），无空间先验

2. 将 `grid_pos_embed` 直接加到 seq_embed 的 class/box token 位置:
   ```python
   # git.py L548 之后, seq_embed shape: [B, Q, 31, C]
   # 位置 0=task_emb, 位置 1=embed(start_token)→预测marker, 位置 2+=class/box tokens
   if self.marker_no_grid_pos and self.mode == 'occupancy_prediction':
       # grid_pos_embed_selected shape: [B, Q, C]
       seq_embed[:, :, 2:, :] += grid_pos_embed_selected.unsqueeze(2)
   ```

3. 这样:
   - Marker 预测 (来自位置 1 的输出): 看到 grid_feature (无 pos) + task_emb → **无空间先验**
   - Class/box 预测 (来自位置 2+ 的输出): 自身 embedding 含 grid_pos_embed + 看到 grid_feature (无 pos) → **有空间先验**

### Q3: marker 的 KV cache 对后续 steps 的影响

**影响最小，不构成阻断。**

分析:
1. Marker 在 pos_id=0 完成后，其 KV 被存入 `pre_kv_list[layer_id]` (L1136)
2. 后续 steps (pos_id=1-29) 通过 `token_forward(..., pre_kv=pre_kv_list[layer_id])` 用 cross-attention 关注 marker 的 KV
3. 如果 marker 没有 grid_pos_embed:
   - 其 KV 编码的是 "基于图像特征的有无判断"
   - 后续 steps 仍通过 **直接加法** (L1120) 获得 grid_pos_embed
   - Marker 的 KV 只是 KV cache 中的一小部分 (1 个 token vs 整个 patch_embed 的 70×70=4900 个 token)

**数学保证**: 后续 steps 的 grid_pos_embed 来源是 L1120 的直接加法，不依赖 marker 的 KV cache 传递。即使 marker KV 不含位置信息，class/box 的位置信息完整无损。

### Q4: 更简单的实现方式

**推荐方案: 减法替代 (最小改动)**

不修改 forward 逻辑的主要结构，而是在关键位置做减法:

**步骤 1**: 在 `git.py:L353` 之后保存原始 grid_pos_embed:
```python
grid_start_embed += grid_pos_embed
self._grid_pos_embed_raw = grid_pos_embed  # 新增: 保存供后续使用
```

**步骤 2**: 通过 `transformer_inputs_dict` 传递:
```python
transformer_inputs_dict = dict(
    ...
    grid_pos_embed_raw=grid_pos_embed,  # 新增
)
```

**步骤 3** (推理): `decoder_inference` 新增 `grid_pos_embed_raw` 参数:
```python
def decoder_inference(self, ..., grid_pos_embed_raw=None, ...):
    ...
    for pos_id in range(30):
        x = input_embed
        if pos_id == 0 and grid_pos_embed_raw is not None:
            x = x + (grid_token - grid_pos_embed_raw).view(B * Q, 1, -1)
        else:
            x = x + grid_token.view(B * Q, 1, -1)
```

**步骤 4** (训练): `get_grid_feature` 新增条件:
```python
def get_grid_feature(self, ..., grid_pos_embed_raw=None):
    grid_feature = grid_forward
    if layer_id != 0:
        if grid_pos_embed_raw is not None:
            grid_feature = grid_feature + (grid_start_embed - grid_pos_embed_raw)
        else:
            grid_feature = grid_feature + grid_start_embed
    ...
```

**改动量**: ~20 行代码修改，不改变函数签名以外的接口。

---

## 发现的问题

### 1. **BUG-79: 训练/推理路径中 grid_token 注入方式不对称** (MEDIUM, NEW)

- 严重性: **MEDIUM**
- 位置:
  - 训练: `git.py:L553-554` — grid_feature 作为 concatenated sequence 位置 0，通过 **self-attention** 传递
  - 推理: `git_occ_head.py:L1120,L1125-1126` — grid_token 通过 **直接加法** 注入
- 描述: 训练时 grid_pos_embed 通过 attention (位置 0 → 所有 token) 传递；推理时通过直接相加传递。数学上 layer_id=0 时等价（因为 grid_feature 是唯一的 attention source 且 attention 权重为 1），但 layer_id>0 时不完全等价
- 影响: 这是一个已存在的设计差异，不是本次修改引入的。但 `marker_no_pos` 修改会放大该差异:
  - 训练: marker 位置的 self-attention 可以部分捕获位置 0 的残余信号
  - 推理: 直接减法完全消除 grid_pos_embed
- 修复建议: 实现时确保训练和推理的 marker_no_pos 逻辑对称。推理用减法消除，训练也必须消除位置 0 中的 grid_pos_embed

### 2. **BUG-80: decoder_inference 的 grid_pos_embed 参数命名误导** (LOW, PRE-EXISTING)

- 严重性: LOW
- 位置: `git_occ_head.py:L1055` — `grid_pos_embed: torch.Tensor`
- 描述: 参数名为 `grid_pos_embed`，实际接收的是 `grid_start_embed` (= task_embedding + grid_pos_embed)。在实现 marker_no_pos 时需要传入 **真正的** grid_pos_embed_raw，容易混淆
- 修复建议: 在 ORCH_057 实现时顺便重命名为 `grid_start_embed`，避免后续维护混乱

---

## 健康检查结果

### A. Mode Collapse 检测

- [x] **数据增强检查**: PhotoMetricDistortion + RandomFlipBEV ✅
- [x] **Pipeline 分离检查**: train ≠ test ✅
- [x] **预测多样性**: ORCH_055 @100 marker_identical=91.5%, @500 marker_identical=99.5% 🔴 — 趋势恶化
- [x] **Marker 分布**: @100 NEAR=183/END=207 (近平衡) → @500 NEAR=25/END=375 (near-all-negative) 🔴 — 相变确认
- [x] **训练趋势**: diff/Margin 54.6%→4.2% 🔴 — 13x 下降, mode collapse 在 @100→@500 加剧

### B. Shortcut Learning 检测

- [x] **Loss-指标背离**: 无 eval 数据可用 (ORCH_055 仅有 frozen-check)
- [x] **Teacher Forcing 风险**: prefix_drop_rate=0.5 ✅ — 但 marker 的 shortcut 不是 TF 泄漏，是 grid_pos_embed

### C. 架构风险检测

- [x] **位置编码完整性**: grid_pos_embed 注入正确 — 但这正是需要修改的目标
- [x] **特征注入频率**: 每步每层 ✅
- [x] **维度匹配**: DINOv3 ViT-L 1024 → GiT-Large 1024 ✅

### D. 资源浪费检测

- [x] **无效训练**: 无训练在运行 ✅
- [x] **Checkpoint 价值**: ORCH_055 @100 是唯一 diff/Margin>50% 的 checkpoint，有参考价值

---

## 对 Conductor 计划的评价

### MASTER_PLAN.md 决策审查

1. **"超参数空间已用尽，需要架构级干预"** — ✅ **完全正确**
   - ORCH_049-056 的实验矩阵 (FG/BG 比、dropout、LR) 全部失败
   - ORCH_055 的完整崩塌轨迹 (@100 健康 → @400 相变) 证明 grid_pos_embed shortcut 是唯一阻断因素
   - diff/Margin 从 54.6% 暴跌至 4.2% 是决定性证据

2. **方案选择 "marker step 不加 grid_pos_embed"** — ✅ **最小可行干预**
   - 不改变 class/box 的位置信息 → 回归性能不受影响
   - 只修改 marker 的决策依据 → 强制 marker 依赖图像特征
   - 改动量小 (~20 行) → 实现风险低

3. **ORCH_055 @100 HEALTHY (marker_same=0.887, diff/Margin=54.6%)** — ⚠️ **Conductor 对这个数据点的利用不够**
   - @100 证明: 在 LR warmup 初期 (LR 极低)，模型 **确实在用图像特征做 marker 决策**
   - 这意味着: 模型有能力用图像做 marker，只是在 LR 升高后 grid_pos_embed shortcut 更高效
   - 架构干预 (移除 grid_pos_embed) 应该能让模型保持 @100 的健康状态进入高 LR 阶段

### 优先级排序

- **ORCH_057 (marker_no_pos) 应为当前唯一主线** — 正确
- 不应同时调其他超参数 — 隔离变量

### 遗漏的风险

1. **BUG-79 (训练/推理路径不对称)**: Conductor 的描述没有提到训练路径的复杂性。训练中不能简单"跳过" grid_pos_embed——需要从 grid_feature (位置 0) 中移除它，同时保持 class/box token 的位置信息。如果只改推理不改训练，模型训练时仍然学到模板，推理时的修改无效。
2. **BUG-73 状态不清**: MASTER_PLAN 标记 BUG-73 为 PARTIAL，但 marker_pos_punish 和 bg_balance_weight 在当前 config 中的值没有记录。ORCH_057 应确认使用哪组 FG/BG 参数 (建议用 ORCH_055 的 marker_pos_punish=1.0, bg_balance_weight=5.0)。
3. **BUG-78 (batch size 效应)**: ORCH_054 单 GPU 失败但 ORCH_055 DDP 健康。ORCH_057 必须用 DDP (≥2 GPU) 训练。

---

## 需要 Admin 协助验证

### 验证 1: marker_no_pos 实现正确性

- **假设**: 移除 grid_pos_embed 后 marker 将依赖图像特征决策
- **验证方法**: 实现 marker_no_pos，用 ORCH_055 配置 (2-GPU DDP, FG/BG=1x) 训练到 iter_500，运行 frozen-check + diff/Margin 诊断
- **预期结果**:
  - diff/Margin 在 @500 仍 >30% (不再暴跌到 4.2%)
  - marker_same < 0.90 (不再模板化)
  - saturation 在 0.3-0.7 范围 (不全正也不全负)

### 验证 2: class/box 回归不受影响

- **假设**: 移除 marker 的 grid_pos_embed 不影响 class/box 的位置回归
- **验证方法**: 如果 @500 frozen-check 通过，继续训练到 @2000 跑 full eval
- **预期结果**: offset 指标 (cx, cy, w, h, th) 不应比 ORCH_024 @2000 差

---

## 附加建议

1. **实现时先改推理路径，用 ORCH_055 @100 的 checkpoint 验证**: 改推理路径 (decoder_inference) 的 marker step 逻辑，用 @100 checkpoint 运行 frozen-check。如果 marker 的预测分布发生改变 (更依赖图像)，证明方向正确，再实现训练路径
2. **Config 新增参数**: `marker_no_grid_pos=True`，默认 False 向后兼容
3. **不要同时改 FG/BG 比**: ORCH_057 应隔离 marker_no_pos 这一个变量，FG/BG 保持 ORCH_055 的设置

---

*诊断脚本: `GiT/ssd_workspace/Debug/Debug_20260316/debug_feature_flow_orch048.py`, `GiT/scripts/diagnose_v3c_single_ckpt.py`*
*数据来源: ORCH_055 iter_100/500 + ORCH_048 iter_500*
*审计时间: 2026-03-16 07:45 CDT*
