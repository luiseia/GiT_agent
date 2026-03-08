# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 11:52
**Reason**: Plan M/N COMPLETED, P6@2000 collected, all diagnostics done

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status | ETA |
|-----------|-----|------|--------|-----|
| **P6** (wide proj 2048, no GELU) | 0+2 DDP | 2460/6000 | RUNNING | ~14:50 |
| Plan M (online DINOv3, unfreeze 2) | - | 2000/2000 | **COMPLETED** | - |
| Plan N (online DINOv3, frozen) | - | 2000/2000 | **COMPLETED** | - |
| Plan K (car-only diag) | - | 2000/2000 | COMPLETED | - |
| Plan L (wide proj diag) | - | 2000/2000 | COMPLETED | - |

**GPU 1, 3 已释放** — 可用于新实验

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 005-014 | COMPLETED | (see previous snapshots) |
| **015** | COMPLETED | Diagnostic α(K)/β(L): class competition REJECTED, wide proj CONFIRMED |
| **016** | **COMPLETED** | Online DINOv3 γ(M)/δ(N): online可行但不优于预提取, M≈N |
| **017** | EXECUTED | P6 wide proj: config+code done, training @2460/6000 |
| **018** | EXECUTED | BUG-33: DDP val GT mismatch → missing sampler fix |

---

## 3. Diagnostic Results (ORCH_015/016) — All Single GPU, GT Correct

### Plan M γ (car-only, online DINOv3, unfreeze 2) — COMPLETED

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500 | 0.621 | 0.052 | 0.220 | 0.217 |
| 1000 | 0.699 | 0.049 | 0.249 | 0.232 |
| 1500 | 0.489 | 0.047 | 0.182 | 0.194 |
| **2000** | 0.507 | **0.049** | **0.188** | **0.223** |

### Plan N δ (car-only, online DINOv3, frozen) — COMPLETED

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500 | 0.618 | 0.051 | 0.219 | 0.206 |
| 1000 | 0.661 | 0.050 | 0.250 | 0.231 |
| 1500 | 0.630 | 0.045 | 0.236 | 0.229 |
| **2000** | 0.513 | **0.045** | **0.198** | **0.217** |

### Key Diagnostic Conclusions (FINAL)
1. **类竞争假说 REJECTED**: 单类 car (K) car_P=0.063 < P5b 10类 car_P=0.107
2. **投影层宽度假说 CONFIRMED**: Plan L (2048) car_P=0.140@1000, +31% over P5b baseline
3. **在线 DINOv3 可行但不优于预提取**: K(0.063) > M(0.049) > N(0.045)
4. **M vs N 无显著差异**: unfreeze 增益极微 (+0.004), 不值得额外开销
5. **建议继续预提取路线**: 效率更高 (省 14GB, 2x 快), 性能不差

---

## 4. P6 Validation Results (DDP 2-GPU, Precision 可信, Recall/gt 有 BUG-33 偏差)

| iter | car_P | bus_P | truck_P | bg_FA | offset_th | 备注 |
|------|-------|-------|---------|-------|-----------|------|
| 500 | 0.073 | 0.006 | 0.037 | 0.163 | 0.236 | warmup 刚结束 |
| 1000 | 0.054 | 0.015 | 0.033 | 0.323 | 0.250 | V 型低谷 |
| 1500 | **0.117** | 0.031 | 0.000 | 0.278 | 0.259 | car_P 突破! |
| **2000** | **0.111** | **0.036** | **0.036** | **0.327** | **0.230** | bg_FA > 0.30 ⚠️ |

**P6@2000 评估**:
- ✅ car_P=0.111 > P5b baseline 0.107
- ⚠️ bg_FA=0.327 > 0.30 RED LINE
- ✅ offset_th=0.230 从 @1500 的 0.259 改善
- ✅ 多类出现: bus_P=0.036, truck_P=0.036, traffic_cone_P=0.034

---

## 5. BUG-33: DDP Val GT 不一致

**根因**: `ConfigDict.pop('sampler')` 静默返回 None → PyTorch 用 SequentialSampler → 每 GPU 处理全量数据 → collect_results zip-interleave 截断 → 前半重复/后半丢失

**影响**: DDP 实验 (P5b, P6) 的 Recall/gt_cnt 偏差. **Precision 不受影响** (分母=pred_cnt).

**修复**: 已添加 `sampler=dict(type='DefaultSampler', shuffle=False)` 到 P6 和 P5b config. 当前 P6 训练仍用旧 config.

---

## 6. Key Paths

| Resource | Path |
|----------|------|
| P6 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/plan_p6_wide_proj/` |
| P5b work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/` |
| Plan K/L/M/N | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/plan_{k,l,m,n}_*_diag/` |
| Diag report | `shared/logs/admin_report_diag.md` |
| BUG-33 report | `shared/logs/admin_report_bug33.md` |

---

## 7. Next Actions

1. **P6 继续监控**: @2500 下一个 val — 关注 bg_FA 趋势, 是否需要调 bg_balance_weight
2. **P6 准确 eval**: 用修复后 config 单 GPU re-eval 关键 checkpoint (tools/test.py)
3. **等待 ORCH**: P6@2000 数据已就绪, 需 CEO 决策:
   - bg_FA=0.327 > 0.30 → 是否调 bg_balance_weight 2.5→3.0?
   - 是否需要新实验利用 GPU 1,3?
4. **GPU 状态**: 0+2 → P6, **1+3 空闲**

---

## 8. Known Issues / Bugs

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-8 | FIXED | cls loss missing bg class |
| BUG-9 | FIXED | 100% grad clipping (0.5→10.0) |
| BUG-10 | FIXED | No warmup |
| BUG-11 | FIXED | Default class order mismatch |
| BUG-12 | FIXED | Eval cell-internal class matching |
| BUG-16 | NOT BLOCKING | Preextracted features vs augmentation |
| BUG-17 | FIXED (P5b) | LR milestones relative to begin |
| BUG-19 | FIXED (P5b) | z center offset |
| BUG-26 | VERIFIED | Only CAM_FRONT uses DINOv3 (by design) |
| **BUG-33** | **FIXED** | DDP val missing sampler → GT count bias |
