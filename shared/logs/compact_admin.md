# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 14:02
**Reason**: P6@4000 re-eval done (car_P=0.1263), Plan O 无效 (BUG-40), Plan P2 启动

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status | ETA |
|-----------|-----|------|--------|-----|
| **P6** (wide proj 2048, no GELU) | 0+2 DDP | ~4300/6000 | RUNNING | ~15:05 |
| **Plan P2** (preextracted+2048+GELU, lr_mult=2.0) | 1 | ~20/2000 | RUNNING (PID 670850) | ~15:40 |
| **Plan P** (preextracted+2048+GELU, lr_mult=1.0) | - | 500/500 | COMPLETED — car_P=0.0035 异常 | - |
| **Plan O** (online DINOv3+2048+noGELU) | 3 | 500/500 | COMPLETED — **无效 (BUG-40)** | - |
| Plan M/N/K/L | - | 2000/2000 | ALL COMPLETED | - |

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 015 | COMPLETED | Diagnostic: class competition REJECTED, wide proj CONFIRMED |
| 016 | COMPLETED | Online DINOv3: online可行但不优于预提取, M≈N |
| 017 | EXECUTED | P6 wide proj: training @4200/6000 |
| 018 | EXECUTED | BUG-33: DDP val sampler fix |
| 019 | EXECUTED | P6 7 ckpts 单GPU re-eval → Precision 偏差 ±10% |
| 020 | COMPLETED | P5b re-eval: car_P=0.116 (非0.107!) |
| 021 | COMPLETED — 无效 | Plan O car_P=0.000, BUG-40 全程 warmup, 不能判定在线路径 |
| 022 | COMPLETED — 异常 | Plan P car_P=0.0035, lr_mult=1.0+warmup=100 导致收敛失败 |
| **023** | **IN PROGRESS** | Task1 done (P6@4000=0.1263), Plan P2 训练中 @20/2000 |

---

## 3. P5b 真实基线 (ORCH_020)

| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| **P5b@3000** | 0.675 | **0.116** | 0.043 | 0.032 | **0.189** | **0.195** |
| **P5b@6000** | 0.639 | **0.115** | 0.037 | 0.043 | **0.188** | **0.194** |

---

## 4. CRITICAL: Plan P @500 结果 (ORCH_022)

| 指标 | Plan P @500 | P6 @500 | Plan L @500 | 判定阈值 |
|------|------------|---------|-------------|---------|
| car_R | **0.0015** | 0.231 | - | - |
| car_P | **0.0035** | 0.073 | 0.054 | > 0.073 |
| truck_P | 0.0400 | 0.019 | - | - |
| bus_P | 0.0445 | 0.008 | - | - |
| ped_P | 0.0231 | 0.021 | - | - |
| bg_FA | **0.1645** | 0.173 | 0.237 | < 0.200 |
| off_th | 0.3247 | 0.259 | - | - |

**按 ORCH_022 标准: car_P=0.0035 << 0.073 → FAIL**

**但 Admin 分析认为这是超参数问题, 不是架构问题:**
1. lr_mult=1.0 (P6 用 2.0) — 随机初始化的 2048 proj 以一半 lr 训练, 500 iter 内严重不足
2. warmup=100 太短 — GELU + 随机权重 + 短 warmup = 早期训练不稳定
3. Plan L (同为 2048+GELU) @500=0.054 (15x better), @1000 飙升到 0.140
4. truck/bus/bg_FA 指标反而好于 P6@500 — 不是完全不工作, 是类别权重极端偏移

**建议 Conductor**: Plan P 需要延长训练或用 P6 的 lr_mult=2.0 重跑. 不应据此否决 2048+GELU.

---

## 5. P6 vs P5b — P6@3500 首次超越!

| 指标 | P5b@3000 | P6@3000 | P6@3500 | **P6@4000** | P6@4000 vs P5b |
|------|----------|---------|---------|------------|----------------|
| car_P | 0.116 | 0.106 | 0.121 | **0.1263** | **+8.9%** |
| bg_FA | **0.189** | 0.297 | 0.287 | **0.2741** | +45% ⚠️ |
| off_th | **0.195** | 0.196 | 0.196 | **0.1907** | -2.2% ✅ |
| truck_P | 0.043 | 0.054 | 0.069 | **0.0749** | **+74%** |
| bus_P | 0.032 | 0.027 | 0.029 | **0.0351** | +10% |
| car_R | 0.675 | 0.617 | 0.577 | **0.5459** | -19% (P/R) |

**P6@4000 单 GPU re-eval 已完成** (ORCH_023 Task 1)。全面改善持续中。

---

## 6. P6 单 GPU Re-eval 完整轨迹

| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| @500 | 0.231 | 0.073 | 0.019 | 0.008 | 0.173 | 0.259 |
| @1000 | 0.252 | 0.058 | 0.027 | 0.010 | 0.352 | 0.220 |
| @1500 | 0.499 | 0.106 | 0.000 | 0.017 | 0.250 | 0.246 |
| @2000 | 0.376 | 0.110 | 0.032 | 0.018 | 0.300 | 0.234 |
| @2500 | 0.516 | 0.111 | 0.047 | 0.022 | 0.336 | 0.201 |
| @3000 | 0.617 | 0.106 | 0.054 | 0.027 | 0.297 | 0.196 |
| @3500 | 0.577 | 0.121 | 0.069 | 0.029 | 0.287 | 0.196 |
| **@4000** | **0.5459** | **0.1263** | **0.0749** | **0.0351** | **0.2741** | **0.1907** |

---

## 7. Plan O @500 结果 (ORCH_021) — **无效 (BUG-40)**

| 指标 | Plan O @500 | P6 @500 | 备注 |
|------|------------|---------|------|
| car_P | **0.0000** | 0.073 | 完全未检测 |
| truck_P | 0.0000 | 0.019 | 完全未检测 |
| bg_FA | **0.0645** | 0.173 | 模型几乎全输出 bg |

**BUG-40: scheduler warmup=500 = max_iters=500, lr 在最后一个 iter 才达到目标值。全程都在热身。结果不能作为在线路径判定依据。**

---

## 8. Next Actions

1. **Plan P2 训练**: GPU 1, 2000 iters, ~3 s/iter, ETA ~15:40. @500 val 在 ~14:27
2. **P6 继续到 @6000**: ~15:05 完成
3. **P6@4500 DDP val**: ~14:20 出结果, 后续可 re-eval
4. **Plan O 如需重跑**: 需要修复 warmup (改为 end=100), 需要 Conductor 决策

---

## 8. Known Issues / Bugs

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-33 | FIXED + ALL RE-EVAL | DDP Precision偏差最高±10%, 所有关键ckpt已单GPU re-eval |
| BUG-37 | CONFIRMED | P5b DDP underestimate car_P, P6 DDP偏差不一致 |
| BUG-39 | TESTING | P6 无 GELU = 退化为单层 Linear, Plan P 修复但 @500 未收敛 |
| **BUG-40** | **CONFIRMED** | Plan O scheduler warmup=500 = max_iters, 全程在 warmup 中, car_P=0.000 |
| BUG-16 | NOT BLOCKING | Preextracted features vs augmentation |
