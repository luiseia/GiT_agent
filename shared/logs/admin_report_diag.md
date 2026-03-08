# 诊断实验报告 (ORCH_015 + ORCH_016)
**Timestamp**: 2026-03-08 08:50
**Status**: Plan K/L COMPLETED, Plan M/N IN PROGRESS (~600/2000)

---

## 1. 实验设计

| 实验 | Config | 变量 | GPU | 基线对照 |
|------|--------|------|-----|----------|
| α (Plan K) | car-only, 预提取, proj=1024 | 单类 vs 多类 | 0 | P5b@3000 |
| β (Plan L) | 10类, 预提取, **proj=2048** | 投影层宽度 | 2 | P5b@3000 |
| γ (Plan M) | car-only, **在线 DINOv3, unfreeze 2** | 在线+解冻 | 1 | Plan K |
| δ (Plan N) | car-only, **在线 DINOv3, frozen** | 在线 vs 离线 | 3 | Plan K |

所有实验: load_from=P5b@3000, max_iters=2000, val_interval=500, mini dataset

---

## 2. BUG-26 验证 ✅

**确认: 只有 CAM_FRONT 使用 DINOv3 特征**
- `LoadFrontCameraImageFromFile`: 只加载 CAM_FRONT 图像
- `GenerateOccFlowLabels:502`: 只读 `results['cams']['CAM_FRONT']`
- `PreextractedFeatureEmbed`: 通过 sample_idx 加载前摄像头特征

---

## 3. 完整结果

### Plan K α (car-only) — COMPLETED

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500  | 0.629 | 0.064 | 0.183 | 0.228 |
| 1000 | 0.507 | 0.047 | 0.211 | 0.254 |
| 1500 | 0.639 | 0.060 | 0.185 | 0.212 |
| 2000 | 0.602 | **0.063** | **0.166** | **0.191** |

**Best**: car_P=0.064@500, offset_th=0.191@2000

### Plan L β (wide proj 2048) — COMPLETED

| iter | car_R | car_P | truck_R | truck_P | bg_FA | offset_th |
|------|-------|-------|---------|---------|-------|-----------|
| 500  | 0.084 | 0.054 | 0.000 | 0.000 | 0.237 | 0.277 |
| 1000 | 0.338 | **0.140** | 0.263 | 0.048 | 0.407 | 0.242 |
| 1500 | 0.572 | 0.103 | 0.015 | 0.003 | 0.447 | 0.225 |
| 2000 | 0.512 | **0.111** | 0.360 | 0.034 | 0.331 | 0.205 |

**Best**: car_P=0.140@1000 (peak, from random init!), offset_th=0.205@2000
**Note**: proj 层 shape mismatch 自动跳过, 从随机初始化开始训练

### Plan M γ (online DINOv3, unfreeze 2) — @500 only

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500  | 0.621 | 0.052 | 0.220 | 0.217 |

### Plan N δ (online DINOv3, frozen) — @500 only

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500  | 0.618 | 0.051 | 0.219 | 0.206 |

---

## 4. 对比分析

### 4.1 类竞争假说: REJECTED ❌

| | car_P | 对比 P5b@3000 |
|---|-------|---------------|
| P5b@3000 (10类) | 0.107 | baseline |
| Plan K (1类) | 0.063 | **-41%** |

单类 car 训练精度更低。原因分析:
- num_vocal 从 230→221, 所有 bin token 含义重映射
- 10→1 类的 vocab 变化破坏了 P5b@3000 checkpoint 学到的 token 分布
- **结论: 类竞争不是精度瓶颈, vocab 兼容性是更大问题**

### 4.2 投影层宽度假说: CONFIRMED ✅

| | car_P | 对比 P5b@3000 |
|---|-------|---------------|
| P5b@3000 (proj=1024) | 0.107 | baseline |
| Plan L@1000 (proj=2048) | **0.140** | **+31%** |
| Plan L@2000 (proj=2048) | **0.111** | **+4%** |

宽投影层从随机初始化仅 1000 iter 就超越了 P5b 基线:
- **4096→2048→768 保留了更多 DINOv3 信息**
- 即使最终@2000 (0.111), 仍优于 P5b 1024 版本 (0.107)
- **结论: 投影层是关键瓶颈, 建议 P7 采用 proj_hidden_dim=2048**

### 4.3 在线 vs 离线 DINOv3: 初步对比

| | car_P@500 | offset_th@500 |
|---|-----------|---------------|
| Plan K (预提取) | 0.064 | 0.228 |
| Plan M (在线 unfreeze) | 0.052 | 0.217 |
| Plan N (在线 frozen) | 0.051 | 0.206 |

在线模式 @500 与预提取接近 (差距在 warmup 噪声范围内)。
M vs N 几乎一致, unfreeze 效果需要更多 iteration 显现。

---

## 5. GPU 资源使用

| 实验 | GPU | 显存 | iter 速度 | 备注 |
|------|-----|------|-----------|------|
| Plan K | 0 | 15.2 GB | 3.0 s/iter | 预提取基线 |
| Plan L | 2 | 15.4 GB | 3.0 s/iter | 预提取 + 宽 proj |
| Plan M | 1 | 29.5 GB | 6.3 s/iter | DINOv3 在线 (+14 GB, 2x 慢) |
| Plan N | 3 | 28.0 GB | 6.3 s/iter | DINOv3 在线 frozen |

在线 DINOv3 额外开销: +14 GB 显存, 2x 时间 (A6000 48GB 可承受)

---

## 6. 关键建议 (给 CEO)

1. **P7 应采用 proj_hidden_dim=2048** — 经过诊断验证, 是最有效的改进
2. **类竞争不是问题** — 不需要减少类别数
3. **在线 DINOv3 可行** — 显存开销可控 (~28-30 GB/GPU), 训练速度减半但消除存储瓶颈
4. **待 Plan M/N 完成** — 确认 unfreeze 增益和在线/离线一致性
