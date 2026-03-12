# VERDICT — MULTILAYER_FEATURE

- **结论**: **STOP**
- **审计对象**: `GiT/mmdet/models/backbones/vit_git.py` (OnlineDINOv3Embed multi-layer), `GiT/configs/GiT/plan_full_nuscenes_multilayer.py`
- **审计 Commit**: `8a961de`
- **日期**: 2026-03-11
- **审计员**: claude_critic

---

## 发现的 BUG

### BUG-54 [CRITICAL] — layer_indices=[10,20,30,40] 致命错误：索引越界 + 全部偏移一位

**文件**: `GiT/configs/GiT/plan_full_nuscenes_multilayer.py:218`
```python
online_dinov3_layer_indices=[10, 20, 30, 40],   # ★ 多层拼接 4×4096=16384维 (论文标准)
```

**文件**: `GiT/dinov3/dinov3/models/vision_transformer.py:270-284`
```python
def _get_intermediate_layers_not_chunked(self, x, n=1):
    x, (H, W) = self.prepare_tokens_with_masks(x)
    output, total_block_len = [], len(self.blocks)
    blocks_to_take = range(total_block_len - n, total_block_len) if isinstance(n, int) else n
    for i, blk in enumerate(self.blocks):
        # ...
        x = blk(x, rope_sincos)
        if i in blocks_to_take:
            output.append(x)
    assert len(output) == len(blocks_to_take), f"only {len(output)} / {len(blocks_to_take)} blocks found"
    return output
```

**问题**: ViT-7B 有 `depth=40`（`vision_transformer.py:408-417`），block 编号 0-39。`blocks_to_take=[10, 20, 30, 40]` 中 `40` 不在 `range(0, 40)` 内。`enumerate(self.blocks)` 只产出 i=0..39，index 40 永远不会被匹配。结果只收集 3 个输出（block 10, 20, 30），assertion 失败：`"only 3 / 4 blocks found"`。

**更深层问题**: 即使把 40 改成 39，其余索引也全部偏移一位。DINOv3 论文中 Layer [10, 20, 30, 40] 是 **1-indexed**（第10/20/30/40个 Transformer block）。代码中 `blocks_to_take` 用的是 **0-indexed**（`enumerate` 从 0 开始）。正确映射：

| 论文 Layer (1-indexed) | 代码 Block Index (0-indexed) |
|---|---|
| Layer 10 | block 9 |
| Layer 20 | block 19 |
| Layer 30 | block 29 |
| Layer 40 | block 39 |

**验证**: 实测 `n=[10,20,30,40]` → assertion crash；`n=[9,19,29,39]` → 成功返回 4 个输出。

**修复**: `online_dinov3_layer_indices=[9, 19, 29, 39]`

**影响**: 不修复此 BUG 训练直接崩溃，无法启动。

**波及范围**: 需同步修正以下位置的索引引用：
- `plan_full_nuscenes_multilayer.py:218` — config 中的索引值
- `vit_git.py:101` — docstring 注释 `(e.g. [10,20,30,40])`
- `vit_git.py:118` — 行内注释 `# e.g. [10, 20, 30, 40]`
- `vit_git.py:216` — forward 注释 `# e.g. [10, 20, 30, 40]`
- `MASTER_PLAN.md` — ORCH_030 描述中的索引

---

### BUG-55 [MEDIUM] — load_from P5b@3000 导致 proj 层部分加载

**文件**: `plan_full_nuscenes_multilayer.py:12`
```python
load_from = '/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/iter_3000.pth'
```

**文件**: `vit_git.py:176-181`
```python
if proj_hidden_dim is not None and proj_hidden_dim > 0:
    layers = [nn.Linear(effective_in_dim, proj_hidden_dim)]  # proj.0
    if proj_use_activation:
        layers.append(nn.GELU())                              # proj.1
    layers.append(nn.Linear(proj_hidden_dim, out_dim))         # proj.2
    self.proj = nn.Sequential(*layers)
```

**问题**: P5b@3000 的 checkpoint 中 proj 层结构：
- `backbone.patch_embed.proj.0.weight` shape = `[2048, 4096]` （单层 in_dim=4096）
- `backbone.patch_embed.proj.2.weight` shape = `[768, 2048]`

新多层 config 的 proj 层结构：
- `backbone.patch_embed.proj.0.weight` shape = `[2048, 16384]` （多层 effective_in_dim=16384）
- `backbone.patch_embed.proj.2.weight` shape = `[768, 2048]`

mmdet 的 `load_checkpoint(strict=False)` 行为：
- `proj.0.weight`：shape 不匹配 `[2048, 4096]` vs `[2048, 16384]` → **跳过**，保持随机初始化
- `proj.0.bias`：shape 匹配 `[2048]` → **加载**
- `proj.2.weight`：shape 匹配 `[768, 2048]` → **加载**
- `proj.2.bias`：shape 匹配 `[768]` → **加载**

**风险**: proj.0 权重随机但 bias 来自 P5b；proj.2 权重和 bias 都来自 P5b。proj.2 训练时期望的输入分布来自训练好的 proj.0，现在得到的是 kaiming_uniform 随机 proj.0 的输出。初始几百步可能有梯度不稳定。

**Config 注释声称 "proj 随机初始化"** — 这只是半对：proj.0.weight 随机，但 proj.0.bias、proj.2.weight、proj.2.bias 都从 P5b 加载。

**建议**: 两个选择：
1. 接受现状——几百步后 proj 会自适应，不是致命问题
2. 在 config 中对 proj 层做显式排除（不加载任何 proj 参数），确保 proj 整体从头训练，更干净

**严重程度**: MEDIUM — 不会崩溃，但可能导致初期训练波动。如果 Conductor 接受风险可以不修。

---

### BUG-56 [LOW] — 单层默认 layer_idx=16 的 off-by-one 一致性问题

**文件**: `vit_git.py:112`
```python
def __init__(self, weight_path, layer_idx=16, layer_indices=None, ...):
```

**问题**: 默认 `layer_idx=16` 提取的是 block 16（0-indexed），即论文的 Layer 17（1-indexed）。如果 CEO 原意是论文的 "Layer 16"，应为 `layer_idx=15`。

**不建议修改**: 所有历史实验（ORCH_024 至 ORCH_029）都使用了 block 16，改动会导致结果不可比。仅作为文档记录，提醒未来引用论文层号时注意 0-indexed 偏移。

---

## 代码正确性审查

### 1. OnlineDINOv3Embed 多层拼接实现 — 逻辑正确（索引问题除外）

**文件**: `vit_git.py:198-244`

代码逻辑审查通过的部分：
- L122-125: `effective_in_dim = len(layer_indices) * in_dim` — 正确，4×4096=16384
- L215-218: `layer_spec` 分支选择 — 正确
- L231-236: `torch.cat(features, dim=-1)` 沿最后维度拼接 — 正确，(B, N, 4096×4) = (B, N, 16384)
- L238-241: dtype 转换逻辑 — 正确，从 FP16 转到 proj 层的 FP32
- L176-181: proj 层构建 `Linear(16384, 2048) → GELU → Linear(2048, 768)` — 正确

### 2. get_intermediate_layers 返回值处理

**文件**: `vision_transformer.py:286-323`

- L296: 调用 `_get_intermediate_layers_not_chunked` 获取原始输出
- L297-306: norm 处理 — `n_storage_tokens=0` for vit_7b，所以 `cls_norm` 分支处理 `out[:, :1]`（cls token），`norm` 处理 `out[:, 1:]`（patch tokens）
- L309: `outputs = [out[:, self.n_storage_tokens + 1 :] for out in outputs]` → `out[:, 1:]` — 正确去除 cls token
- L317: `return tuple(outputs)` — 返回纯 patch token tensors

每个输出 shape: `(B, 4900, 4096)`，4900 = (1120/16)² = 70×70。正确。

### 3. 向后兼容性 — PASS

当 `layer_indices=None` 时：
- `effective_in_dim = in_dim` (4096) → proj = Linear(4096, 2048)→GELU→Linear(2048, 768) ✓
- `layer_spec = [self.layer_idx]` → 单元素 list → `blocks_to_take=[16]` → 提取 1 个输出 ✓
- `feat = features[0]` → shape (B, 4900, 4096) ✓
- 完全等价于修改前的行为 ✓

### 4. 显存影响评估

单层 vs 多层（batch_size=1, frozen DINOv3 FP16）：

| 项目 | 单层 | 多层 (4层) | 差值 |
|---|---|---|---|
| 中间层输出 (FP16) | 1×(1,4900,4096)×2B = 40MB | 4×40MB = 160MB | +120MB |
| cat 后张量 (FP16) | (1,4900,4096) = 40MB | (1,4900,16384) = 160MB | +120MB |
| cast 到 FP32 | 80MB | 320MB | +240MB |
| proj.0 weight (FP32) | (2048,4096)×4B = 33MB | (2048,16384)×4B = 134MB | +101MB |
| proj.0 grad (FP32) | 33MB | 134MB | +101MB |
| **总额外** | — | — | **~580MB** |

在 A100 80GB 上完全可忽略。4 GPU DDP 下每卡额外 <600MB，不构成问题。

### 5. Config 与代码一致性

**文件**: `plan_full_nuscenes_multilayer.py`

- L213: `preextracted_proj_hidden_dim=2048` → 传递给 `OnlineDINOv3Embed` 的 `proj_hidden_dim` → `Linear(16384, 2048)→GELU→Linear(2048, 768)` ✓
- L214: `preextracted_proj_use_activation=True` → GELU 激活 ✓
- L215: `use_online_dinov3=True` → 走 OnlineDINOv3Embed 路径 ✓
- L218: `online_dinov3_layer_indices=[10, 20, 30, 40]` → **BUG-54**
- L219: `online_dinov3_unfreeze_last_n=0` → 全 frozen ✓
- L220: `online_dinov3_dtype='fp16'` ✓

---

## 对 Conductor 计划的评价

ORCH_030 的设计方向正确——DINOv3 论文确实用多层特征 [10,20,30,40] 做所有下游任务，单层 Layer 16 在几何任务上不够。代码架构（multi-layer concat → 2-layer proj → ViT backbone）设计合理，向后兼容性处理干净。

但 **BUG-54 是致命阻断**：直接启动训练会立即 assertion crash。必须先修正 `[10,20,30,40]` → `[9,19,29,39]`。

BUG-55（partial checkpoint loading）不阻断但需要 Conductor 明确决策：是接受部分加载的 proj.2 权重，还是排除所有 proj 参数从头训练。建议后者更干净。

---

## 最终判决

| BUG | 严重程度 | 阻断 | 修复要求 |
|---|---|---|---|
| BUG-54 | CRITICAL | YES | 改 `[10,20,30,40]` → `[9,19,29,39]`，更新所有注释 |
| BUG-55 | MEDIUM | NO | Conductor 决策：接受 partial load 或排除 proj 参数 |
| BUG-56 | LOW | NO | 仅文档记录，不改动 |

**STOP** — 在 BUG-54 修复前不得启动 ORCH_030 训练。修复后需要 Critic 复审确认。
