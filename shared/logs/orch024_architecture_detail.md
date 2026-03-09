# ORCH_024 架构详细报告
> 撰写: Conductor | 时间: 2026-03-09 ~04:20 | Cycle #110
> 来源: 直接读取 config 和代码, 非记忆

---

## 1. DINOv3 冻结/可训练状态

**完全冻结。** 0 个可训练参数。

```python
# plan_full_nuscenes_gelu.py L217
online_dinov3_unfreeze_last_n=0   # 不解冻任何层

# vit_git.py L148-149 (OnlineDINOv3Embed.__init__)
for param in self.dinov3.parameters():
    param.requires_grad = False   # 所有参数冻结
```

- DINOv3 ViT-7B 总共 ~7B 参数, 全部 frozen
- FP16 推理模式 (`online_dinov3_dtype='fp16'`), 不参与反向传播
- 仅前向传播提取 Layer 16 特征, 输出维度 4096

---

## 2. 投影层具体结构

```python
# vit_git.py L166-171 (OnlineDINOv3Embed.__init__)
# proj_hidden_dim=2048, proj_use_activation=True

self.proj = nn.Sequential(
    nn.Linear(4096, 2048),   # 8,390,656 参数 (4096×2048 + 2048)
    nn.GELU(),                # 无参数, 非线性激活
    nn.Linear(2048, 768),    # 1,573,632 参数 (2048×768 + 768)
)
# 总投影层参数: ~9.96M
```

**没有 LayerNorm。** 投影层结构是 Linear → GELU → Linear, 无 BatchNorm/LayerNorm/Dropout。

**初始化**: `kaiming_uniform_` (权重), `zeros_` (偏置)。

**数据类型**: DINOv3 输出 FP16, 投影层运算在 FP32 (自动上转):
```python
# vit_git.py ~L190 (forward)
features = features.float()  # FP16 → FP32
projected = self.proj(features)  # FP32 运算
```

---

## 3. 学习率配置

```python
# plan_full_nuscenes_gelu.py L354-385
optimizer = AdamW(lr=5e-5, weight_decay=0.01)
accumulative_counts = 4  # 有效 lr = 5e-5 (梯度累积不影响 lr)

paramwise_cfg = dict(custom_keys={
    # 投影层 (proj)
    'backbone.patch_embed.proj': dict(lr_mult=2.0),    # → 实际 lr = 1.0e-4

    # SAM 预训练层 0-11 (渐进式 lr)
    'backbone': dict(lr_mult=0.05),                      # → 2.5e-6 (默认)
    'backbone.layers.6':  dict(lr_mult=0.15),            # → 7.5e-6
    'backbone.layers.7':  dict(lr_mult=0.25),            # → 1.25e-5
    'backbone.layers.8':  dict(lr_mult=0.35),            # → 1.75e-5
    'backbone.layers.9':  dict(lr_mult=0.50),            # → 2.5e-5
    'backbone.layers.10': dict(lr_mult=0.65),            # → 3.25e-5
    'backbone.layers.11': dict(lr_mult=0.80),            # → 4.0e-5

    # 新增层 12-17
    'backbone.layers.12': dict(lr_mult=1.0),             # → 5.0e-5
    'backbone.layers.13': dict(lr_mult=1.0),             # → 5.0e-5
    'backbone.layers.14': dict(lr_mult=1.0),             # → 5.0e-5
    'backbone.layers.15': dict(lr_mult=1.0),             # → 5.0e-5
    'backbone.layers.16': dict(lr_mult=1.0),             # → 5.0e-5
    'backbone.layers.17': dict(lr_mult=1.0),             # → 5.0e-5
})
```

**学习率层次结构**:
| 组件 | lr_mult | 实际 LR | 说明 |
|------|---------|---------|------|
| **投影层** | **2.0** | **1.0e-4** | 最快, 新初始化 |
| 新层 12-17 | 1.0 | 5.0e-5 | 随机初始化, 全速训练 |
| SAM 层 11 | 0.80 | 4.0e-5 | 渐进解冻 |
| SAM 层 10 | 0.65 | 3.25e-5 | |
| SAM 层 9 | 0.50 | 2.5e-5 | |
| SAM 层 8 | 0.35 | 1.75e-5 | |
| SAM 层 7 | 0.25 | 1.25e-5 | |
| SAM 层 6 | 0.15 | 7.5e-6 | |
| SAM 层 0-5 | 0.05 | 2.5e-6 | 最慢, 保留预训练特征 |
| OCC Head | 1.0 | 5.0e-5 | 默认 |
| DINOv3 | — | 0 (frozen) | 不训练 |

---

## 4. ViT 层结构

### ViT-Base 基础配置
```python
# vit_git.py L878-884
arch_zoo['base'] = {
    'embed_dims': 768,
    'num_layers': 12,           # 原始 SAM 层数
    'num_heads': 12,
    'feedforward_channels': 3072,
    'global_attn_indexes': [2, 5, 8, 11]  # 全局注意力层
}
```

### 新增层 12-17
```python
# plan_full_nuscenes_gelu.py L205
new_more_layers=['win', 'win', 'win', 'win', 'win', 'win']  # 6 个窗口注意力层
```

**总层数: 18** (12 SAM + 6 新增)

| 层 | 来源 | 注意力类型 | 权重来源 | lr_mult |
|----|------|-----------|---------|---------|
| 0-1 | SAM | 窗口 (window_size=14) | SAM 预训练 | 0.05 |
| 2 | SAM | **全局** | SAM 预训练 | 0.05 |
| 3-4 | SAM | 窗口 | SAM 预训练 | 0.05 |
| 5 | SAM | **全局** | SAM 预训练 | 0.05 |
| 6-7 | SAM | 窗口 | SAM 预训练 | 0.15/0.25 |
| 8 | SAM | **全局** | SAM 预训练 | 0.35 |
| 9-10 | SAM | 窗口 | SAM 预训练 | 0.50/0.65 |
| 11 | SAM | **全局** | SAM 预训练 | 0.80 |
| **12-17** | **新增** | **窗口** | **随机初始化** | **1.0** |

**每层结构 (TransformerEncoderLayer)**:
```
LayerNorm → Multi-Head Attention (12 heads, 768 dims) → 残差
LayerNorm → FFN (768→3072→768, GELU) → 残差
DropPath (rate 从 0 线性增到 0.4)
```

**新层 12-17 与原层 0-11 结构完全相同**, 仅:
- 窗口注意力 (window_size=14, 非全局)
- 随机初始化 (非 SAM 预训练权重)
- lr_mult=1.0 (全速训练)

---

## 5. 参数统计 (基于架构计算)

### 可训练参数

| 组件 | 参数量 | 说明 |
|------|--------|------|
| 投影层 (proj) | ~9.96M | Linear(4096,2048)+Linear(2048,768) |
| ViT 层 0-11 (SAM) | ~85M | 12 层 × ~7.1M/层, lr_mult 渐进 |
| ViT 层 12-17 (新增) | ~43M | 6 层 × ~7.1M/层, lr_mult=1.0 |
| OCC Head | ~30-50M | Embedding(230×768) + 解码器 + loss 层 |
| 位置编码 | 0 | frozen (requires_grad=False) |
| **可训练总计** | **~170-190M** | |

### 冻结参数

| 组件 | 参数量 | 说明 |
|------|--------|------|
| DINOv3 ViT-7B | ~7,000M | 全部 frozen, FP16 推理 |
| 位置编码 | ~3.8M | 70×70×768, frozen |
| **冻结总计** | **~7,004M** | |

### 比例
- **可训练**: ~180M (~2.5%)
- **冻结**: ~7,000M (~97.5%)

*注: 以上为架构推算值, 如需精确值可签发 ORCH 让 Admin 运行 `sum(p.numel() for p in model.parameters() if p.requires_grad)`*

---

## 6. 显存占用

**实测: 每卡 ~37 GB** (A6000 48 GB)

| 组件 | 估算 | 说明 |
|------|------|------|
| DINOv3 模型 (FP16) | ~14 GB | 7B × 2 bytes |
| 可训练参数 (FP32) | ~0.7 GB | 180M × 4 bytes |
| AdamW 优化器状态 | ~1.4 GB | 180M × 8 bytes (momentum + variance) |
| 梯度 (FP32) | ~0.7 GB | 180M × 4 bytes |
| 激活值 (batch=2) | ~15-18 GB | Transformer 中间激活, 注意力矩阵等 |
| 其他 (CUDA 开销) | ~2-3 GB | cuDNN workspace, 碎片等 |
| **每卡总计** | **~35-38 GB** | **实测 36.8-37.3 GB** |

**accumulative_counts=4**: 梯度累积不增加显存 (不保留中间计算图)。

---

## 7. 训练进度和最新结果

### 训练状态
| 指标 | 值 |
|------|-----|
| 进度 | 5230/40000 (13.1%) |
| 实际 optimizer steps | 1308 (post-warmup: 808) — 因 BUG-46 (accumulative_counts=4) |
| 速度 | ⚠️ 交替 6.2s/28s (GPU 1 被 ORCH_026 占用) |
| 显存 | 37 GB/GPU (正常) |
| GPU 1 | 47.9/49.1 GB (97.4%, ORCH_026 额外 11 GB) |
| ETA | ⚠️ 延迟中 (正常 ~3/11 14:00, 当前膨胀到 ~3/12) |

### Val 结果
| 指标 | @2000 (500 opt steps) | @4000 (1000 opt steps) |
|------|----------------------|----------------------|
| car_P | 0.079 | 0.078 (持平) |
| car_R | 0.627 | 0.419 (再平衡) |
| truck_P | 0.000 | 0.057 (新类!) |
| bicycle_R | 0.000 | 0.191 (P=0.001, 154K FP) |
| bg_FA | 0.222 | 0.199 (首次<0.20) |
| off_th | 0.174 | 0.150 (历史最优) |

### 下一里程碑
- @6000 val: ETA 延迟 (取决于 GPU 1 冲突何时解决)
- 第一次 LR decay @17000: ~3/9 22:00 (可能延迟)

---

## 完整数据流图

```
输入图像 (B=2, 3, 1120, 1120)
  │
  ▼
┌─────────────────────────────────────┐
│ OnlineDINOv3Embed (patch_embed)     │
│                                     │
│  DINOv3 ViT-7B [FROZEN, FP16]      │
│  ├── 40 transformer blocks          │
│  └── 提取 Layer 16 特征             │
│       输出: (B, 4900, 4096)         │ ← 70×70 patches
│                                     │
│  投影层 [TRAINABLE, FP32, lr=1e-4]  │
│  ├── Linear(4096 → 2048)           │
│  ├── GELU()                        │
│  └── Linear(2048 → 768)            │
│       输出: (B, 4900, 768)          │
└─────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────┐
│ ViT-Base 18 层 Transformer          │
│                                     │
│  层 0-5  [SAM, lr=2.5e-6]          │
│  层 6-11 [SAM, lr=7.5e-6→4e-5]    │
│  层 12-17 [NEW, lr=5e-5]           │
│                                     │
│  每层: LN→MHSA(12h)→LN→FFN→DropPath │
│  Window attn (14) or Global attn    │
│       输出: (B, 4900, 768)          │
└─────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────┐
│ OCC Head (git_occ_head)             │
│                                     │
│  Grid Sampling: 400 cells           │
│  AR 解码: 3 slots × 10 tokens/slot │
│  Vocab: 230 tokens                  │
│  Loss: CE (cls + reg + marker)      │
│  per_class_balance: sqrt mode       │
└─────────────────────────────────────┘
```

---

*Conductor 签发 | 2026-03-09 ~04:20*
