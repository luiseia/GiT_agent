# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 12:54
**Reason**: ORCH_020/021 executing, P5b re-eval DONE → P6 未超越 P5b!

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status | ETA |
|-----------|-----|------|--------|-----|
| **P6** (wide proj 2048, no GELU) | 0+2 DDP | ~3200/6000 | RUNNING | ~14:50 |
| **Plan O** (online DINOv3+2048+noGELU) | 3 | ~0/500 | JUST STARTED | ~13:40 |
| Plan M/N/K/L | - | 2000/2000 | ALL COMPLETED | - |

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 015 | COMPLETED | Diagnostic: class competition REJECTED, wide proj CONFIRMED |
| 016 | COMPLETED | Online DINOv3: online可行但不优于预提取, M≈N |
| 017 | EXECUTED | P6 wide proj: training @3200/6000 |
| 018 | EXECUTED | BUG-33: DDP val sampler fix |
| 019 | EXECUTED | P6 5 ckpts 单GPU re-eval → Precision 偏差 ±10% |
| **020** | **IN PROGRESS** | P5b re-eval DONE → car_P=0.116 (非0.107!) |
| **021** | **IN PROGRESS** | Plan O 在线宽投影诊断, 已启动 GPU 3 |

---

## 3. P5b 真实基线 (ORCH_020 — 颠覆性!)

| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| **P5b@3000** | 0.675 | **0.116** | 0.043 | 0.032 | **0.189** | **0.195** |
| **P5b@6000** | 0.639 | **0.115** | 0.037 | 0.043 | **0.188** | **0.194** |

**DDP 偏差**: car_P 0.107→0.116 (低估 8%), bg_FA 0.217→0.189 (高估 15%)

---

## 4. P6 vs P5b 真实对比 (颠覆性修正!)

| 指标 | P5b@3000 | P6@3000 | P6 vs P5b |
|------|----------|---------|-----------|
| car_P | **0.116** | 0.106 | **-8.6% ⚠️** |
| bg_FA | **0.189** | 0.297 | **+57% ⚠️** |
| off_th | **0.195** | 0.196 | 持平 |
| truck_P | 0.043 | **0.054** | **+26% ✅** |
| car_R | 0.675 | 0.617 | -8.6% |

**结论: P6 (2048投影) 尚未超越 P5b (1024投影)!**
- car_P 低 8.6%, bg_FA 高 57%
- 唯一优势: truck_P 更好, 但代价太大
- 原因: P6 的 2048 投影层从随机初始化, 需要更多训练 converge
- P5b 的 1024 投影已充分训练

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

car_P plateau ~0.106-0.111, 可能还需更多训练。bg_FA 远高于 P5b (0.297 vs 0.189)。

---

## 6. Plan O 状态 (ORCH_021)

- Config: online DINOv3 frozen + 2048 + 无GELU + 10类 + num_vocal=230
- GPU 3, 单 GPU, 500 iters (~50 min)
- 判定: car_P@500 > 0.05 → 在线路径可行
- 对比: P6@500 car_P=0.073 (预提取)

---

## 7. Next Actions

1. **Plan O @500 结果**: ~13:40 完成, 判定在线 vs 预提取
2. **P6 继续**: @3500 (~13:00), 观察 car_P 是否向 P5b 0.116 收敛
3. **CEO 决策**: P6 未超 P5b → 是否继续 P6 到 @6000? 还是调整策略?
4. **关键问题**: bg_FA=0.297 vs P5b 0.189 — bg_balance_weight 需要调整?

---

## 8. Known Issues / Bugs

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-33 | FIXED + ALL RE-EVAL | DDP Precision偏差最高±10%, P5b+P6 所有关键ckpt已单GPU re-eval |
| **BUG-37** | NEW | P5b DDP underestimate car_P (0.107→0.116), P6 DDP overestimate @1500 (0.117→0.106) |
| BUG-16 | NOT BLOCKING | Preextracted features vs augmentation |
