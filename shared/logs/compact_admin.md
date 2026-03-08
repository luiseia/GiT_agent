# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 12:35
**Reason**: P6@3000 re-eval done, best balanced checkpoint

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status | ETA |
|-----------|-----|------|--------|-----|
| **P6** (wide proj 2048, no GELU) | 0+2 DDP | ~3010/6000 | RUNNING | ~14:50 |
| Plan M/N/K/L | - | 2000/2000 | ALL COMPLETED | - |

**GPU 1, 3 空闲** — 可用于新实验

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 005-014 | COMPLETED | (see previous snapshots) |
| 015 | COMPLETED | Diagnostic α(K)/β(L): class competition REJECTED, wide proj CONFIRMED |
| 016 | COMPLETED | Online DINOv3 γ(M)/δ(N): online可行但不优于预提取, M≈N |
| 017 | EXECUTED | P6 wide proj: config+code done, training running |
| 018 | EXECUTED | BUG-33: DDP val GT mismatch → missing sampler fix |
| **019** | **EXECUTED** | P6 单GPU re-eval 5 ckpts → **Precision 也有偏差 (±10%)** |

---

## 3. P6 单 GPU Re-eval 真实值 (ORCH_019 核心输出)

| Ckpt | car_R | car_P | truck_P | bus_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|--------|
| @500 | 0.231 | 0.073 | 0.019 | 0.008 | 0.173 | 0.259 |
| @1000 | 0.252 | 0.058 | 0.027 | 0.010 | 0.352 | 0.220 |
| @1500 | 0.499 | **0.106** | 0.000 | 0.017 | 0.250 | 0.246 |
| @2000 | 0.376 | **0.110** | 0.032 | 0.018 | **0.300** | 0.234 |
| @2500 | 0.516 | **0.111** | **0.047** | 0.022 | 0.336 | **0.201** |
| **@3000** | **0.617** | **0.106** | **0.054** | **0.027** | **0.297** | **0.196** |

### P6 趋势 (基于真实值, 6 checkpoints)
- car_P: 0.073→0.058→0.106→0.110→0.111→**0.106** (plateau ~0.106-0.111)
- bg_FA: 0.173→0.352→0.250→0.300→0.336→**0.297** (LR 衰减后回落 ✅)
- off_th: 0.259→0.220→0.246→0.234→0.201→**0.196** (持续改善, 首次 <0.20 ✅)
- car_R: 0.231→0.252→0.499→0.376→0.516→**0.617** (持续上升 ✅)
- 多类: truck_P 0.019→0.054 持续上升, bus/ped 也在改善

### @3000 关键评估
- ✅ **bg_FA=0.297 回到红线以下** (LR 衰减生效)
- ✅ **off_th=0.196 新低** (首次低于 0.20)
- ⚠️ car_P=0.106 略降 (从 @2500 的 0.111), 与 P5b baseline 持平
- ✅ truck_P=0.054 持续提升 (P5b 水平 ~0.043)
- **@3000 是目前最均衡的 checkpoint**

---

## 4. BUG-33 影响 (修正)

**重要修正**: DDP Precision 也有偏差 (最高 ±10%), 不像之前以为的完全可信!

原因: zip-interleave 截断只评估前半数据集, 前后半数据预测分布不一致。偏差随训练收敛减小 (@2000+ 偏差 <2%)。

**所有跨实验对比应使用单 GPU re-eval 值。**

---

## 5. Key Diagnostic Conclusions (FINAL)
1. **类竞争假说 REJECTED**: 单类 car (K) car_P=0.063 < P5b 10类 car_P=0.107
2. **投影层宽度假说 CONFIRMED**: Plan L (2048) car_P=0.140@1000, +31%
3. **在线 DINOv3 可行但不优于预提取**: K(0.063) > M(0.049) > N(0.045)
4. **建议继续预提取路线**: 效率更高 (省 14GB, 2x 快)

---

## 6. Next Actions

1. **P6 继续训练**: 当前 @3010/6000, 下次 val @3500
2. **等待 ORCH 决策**:
   - @3000 bg_FA 回到 0.297 ✅, 但 car_P=0.106 开始 plateau
   - 是否继续到 @6000? 还是在 @3000 切 full nuScenes?
   - GPU 1,3 空闲 → 新实验?
   - P5b car_P=0.107 需要单 GPU re-eval (可能有 ±10% 偏差)
3. **P6 第二个 LR 衰减**: milestone @4500 (实际 iter 4500), 观察效果

---

## 7. Known Issues / Bugs

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-33 | **FIXED + RE-EVAL DONE** | DDP val sampler → GT+Precision 偏差, P6 5 ckpts 已单GPU re-eval |
| BUG-16 | NOT BLOCKING | Preextracted features vs augmentation |
| Others | FIXED | BUG-8,9,10,11,12,17,19,26 all resolved |
