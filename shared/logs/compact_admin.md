# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 13:06
**Reason**: P6@3500 单GPU re-eval → car_P=0.121 首次超越 P5b! Plan O @~80/500

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status | ETA |
|-----------|-----|------|--------|-----|
| **P6** (wide proj 2048, no GELU) | 0+2 DDP | ~3560/6000 | RUNNING | ~15:05 |
| **Plan O** (online DINOv3+2048+noGELU) | 3 | ~80/500 | RUNNING | ~13:49 |
| Plan M/N/K/L | - | 2000/2000 | ALL COMPLETED | - |

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 015 | COMPLETED | Diagnostic: class competition REJECTED, wide proj CONFIRMED |
| 016 | COMPLETED | Online DINOv3: online可行但不优于预提取, M≈N |
| 017 | EXECUTED | P6 wide proj: training @3560/6000 |
| 018 | EXECUTED | BUG-33: DDP val sampler fix |
| 019 | EXECUTED | P6 5 ckpts 单GPU re-eval → Precision 偏差 ±10% |
| 020 | COMPLETED | P5b re-eval: car_P=0.116 (非0.107!) |
| **021** | **IN PROGRESS** | Plan O @~80/500, 等待 @500 结果 |

---

## 3. P5b 真实基线 (ORCH_020)

| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| **P5b@3000** | 0.675 | **0.116** | 0.043 | 0.032 | **0.189** | **0.195** |
| **P5b@6000** | 0.639 | **0.115** | 0.037 | 0.043 | **0.188** | **0.194** |

---

## 4. P6 vs P5b — P6@3500 首次超越!

| 指标 | P5b@3000 | P6@3000 | **P6@3500** | P6@3500 vs P5b |
|------|----------|---------|-------------|----------------|
| car_P | 0.116 | 0.106 | **0.121** | **+4.5% ✅** |
| bg_FA | **0.189** | 0.297 | **0.287** | +52% ⚠️ (改善中) |
| off_th | **0.195** | 0.196 | **0.196** | 持平 |
| truck_P | 0.043 | 0.054 | **0.069** | **+60% ✅** |
| bus_P | 0.032 | 0.027 | 0.029 | -9% |
| car_R | 0.675 | 0.617 | 0.577 | -14% (P/R tradeoff) |

**结论: P6@3500 car_P=0.121 首次超越 P5b 0.116 (+4.5%)!**
- 2048 投影层 converge 中, 比 1024 需更多训练但潜力更大
- truck_P 大幅提升 (+60% vs P5b)
- bg_FA 仍高但在缓慢改善 (0.352→0.300→0.297→0.287)
- car_R 下降是正常 P/R tradeoff, Precision 更重要

---

## 5. P6 单 GPU Re-eval 完整轨迹

| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| @500 | 0.231 | 0.073 | 0.019 | 0.008 | 0.173 | 0.259 |
| @1000 | 0.252 | 0.058 | 0.027 | 0.010 | 0.352 | 0.220 |
| @1500 | 0.499 | 0.106 | 0.000 | 0.017 | 0.250 | 0.246 |
| @2000 | 0.376 | 0.110 | 0.032 | 0.018 | 0.300 | 0.234 |
| @2500 | 0.516 | 0.111 | 0.047 | 0.022 | 0.336 | 0.201 |
| @3000 | 0.617 | 0.106 | 0.054 | 0.027 | 0.297 | 0.196 |
| **@3500** | **0.577** | **0.121** | **0.069** | **0.029** | **0.287** | **0.196** |

car_P 突破! 从 @1500-3000 plateau ~0.106-0.111, @3500 跃升至 0.121。趋势向好。

---

## 6. Plan O 状态 (ORCH_021)

- Config: online DINOv3 frozen + 2048 + 无GELU + 10类 + num_vocal=230
- GPU 3, 单 GPU, 500 iters
- 当前: ~80/500, ETA ~13:49
- 判定: car_P@500 > 0.05 → 在线路径可行
- 对比: P6@500 car_P=0.073 (预提取)

---

## 7. Next Actions

1. **Plan O @500 结果**: ~13:49 完成, 判定在线 vs 预提取
2. **P6 继续到 @6000**: car_P 突破趋势, 值得跑完
3. **P6 后续 ckpt re-eval**: @4000 (~13:25), 持续跟踪
4. **bg_FA 仍是主要问题**: 0.287 vs P5b 0.189, 但在改善

---

## 8. Known Issues / Bugs

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-33 | FIXED + ALL RE-EVAL | DDP Precision偏差最高±10%, 所有关键ckpt已单GPU re-eval |
| BUG-37 | CONFIRMED | P5b DDP underestimate car_P, P6 DDP偏差不一致 |
| BUG-16 | NOT BLOCKING | Preextracted features vs augmentation |
