# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 11:05
**Reason**: ORCH_017/018 executed, P6 running, Plan M/N near completion

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status | ETA |
|-----------|-----|------|--------|-----|
| **P6** (wide proj 2048, no GELU) | 0+2 DDP | 1540/6000 | RUNNING | ~14:50 |
| **Plan M** (online DINOv3, unfreeze 2) | 1 | 1690/2000 | RUNNING | ~11:32 |
| **Plan N** (online DINOv3, frozen) | 3 | 1660/2000 | RUNNING | ~11:35 |
| Plan K (car-only diag) | - | 2000/2000 | COMPLETED | - |
| Plan L (wide proj diag) | - | 2000/2000 | COMPLETED | - |

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 005-014 | COMPLETED | (see previous snapshots) |
| **015** | COMPLETED | Diagnostic experiments α(K)/β(L): class competition REJECTED, wide proj CONFIRMED |
| **016** | IN PROGRESS | Online DINOv3 experiments γ(M)/δ(N): online≈preextracted, M/N near completion |
| **017** | IN PROGRESS | P6 wide proj mini validation: config+code done, training @1540/6000 |
| **018** | COMPLETED | BUG-33 investigation: DDP val GT mismatch → missing sampler fix |

---

## 3. Diagnostic Results (ORCH_015/016) — All Single GPU, GT Correct

### Plan K α (car-only, preextracted, proj=1024)

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500 | 0.629 | 0.064 | 0.183 | 0.228 |
| 1000 | 0.507 | 0.047 | 0.211 | 0.254 |
| 1500 | 0.639 | 0.060 | 0.185 | 0.212 |
| 2000 | 0.602 | 0.063 | 0.166 | 0.191 |

### Plan L β (10-class, preextracted, proj=2048) — FROM RANDOM INIT

| iter | car_R | car_P | truck_P | bg_FA | offset_th |
|------|-------|-------|---------|-------|-----------|
| 500 | 0.084 | 0.054 | 0.000 | 0.237 | 0.277 |
| 1000 | 0.338 | **0.140** | 0.048 | 0.407 | 0.242 |
| 1500 | 0.572 | 0.103 | 0.003 | 0.447 | 0.225 |
| 2000 | 0.512 | **0.111** | 0.034 | 0.331 | 0.205 |

### Plan M γ (car-only, online DINOv3, unfreeze 2)

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500 | 0.621 | 0.052 | 0.220 | 0.217 |
| 1000 | 0.699 | 0.049 | 0.249 | 0.232 |
| 1500 | 0.489 | 0.047 | 0.182 | 0.194 |

### Plan N δ (car-only, online DINOv3, frozen)

| iter | car_R | car_P | bg_FA | offset_th |
|------|-------|-------|-------|-----------|
| 500 | 0.618 | 0.051 | 0.219 | 0.206 |
| 1000 | 0.661 | 0.050 | 0.250 | 0.231 |
| 1500 | 0.630 | 0.045 | 0.236 | 0.229 |

### Key Diagnostic Conclusions
1. **类竞争假说 REJECTED**: 单类 car (K) car_P=0.063 < P5b 10类 car_P=0.107
2. **投影层宽度假说 CONFIRMED**: Plan L (2048) car_P=0.140@1000, +31% over P5b baseline
3. **在线 DINOv3 可行**: 与预提取性能一致, 显存+14 GB, 速度 2x 慢

---

## 4. P6 Validation Results (DDP 2-GPU, gt_cnt 有 BUG-33 偏差, Precision 可信)

| iter | car_P | bus_P | bg_FA | offset_th | 备注 |
|------|-------|-------|-------|-----------|------|
| 500 | 0.073 | 0.006 | 0.163 | 0.236 | warmup 刚结束, proj 从随机初始化 |
| 1000 | 0.054 | 0.015 | 0.323 | 0.250 | bg_FA 飙升, 过拟合? |
| **1500** | **0.117** | **0.031** | 0.278 | 0.259 | **car_P 突破 P5b baseline!** |

**单 GPU eval P6@500**: car_P=0.073, car_R=0.231, bg_FA=0.173 (GT 正确: car_gt=6719)

**P6@1500 重要**: car_P=0.117 > P5b@3000 的 0.107, 确认宽投影有效!

---

## 5. BUG-33: DDP Val GT 不一致

**根因**: `ConfigDict.pop('sampler')` 静默返回 None → PyTorch 用 SequentialSampler → 每 GPU 处理全量数据 → collect_results zip-interleave 截断 → 前半重复/后半丢失

**影响**: DDP 实验 (P5b, P6) 的 Recall/gt_cnt 偏差. **Precision 不受影响** (分母=pred_cnt).

**修复**: 已添加 `sampler=dict(type='DefaultSampler', shuffle=False)` 到 P6 和 P5b config. 当前 P6 训练仍用旧 config, 下次 eval 需用修复后 config 或单 GPU.

---

## 6. Code Changes This Session

| File | Change |
|------|--------|
| `vit_git.py` | `preextracted_proj_use_activation` param 添加到 ViTGiT/PreextractedFeatureEmbed/OnlineDINOv3Embed |
| `plan_p6_wide_proj.py` | 新建: proj=2048, no GELU, lr_mult=2.0, milestones=[2000,4000] |
| `plan_p6_wide_proj.py` | BUG-33 FIX: 添加 val sampler |
| `plan_i_p5b_3fixes.py` | BUG-33 FIX: 添加 val sampler |

Commits: `5d39c59` (P6 code+config), `41ca1c8` (BUG-33 fix)

---

## 7. Key Paths

| Resource | Path |
|----------|------|
| P6 work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/plan_p6_wide_proj/` |
| P5b work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/` |
| Plan K/L/M/N | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/plan_{k,l,m,n}_*_diag/` |
| DINOv3 features | `/mnt/SSD/GiT_Yihao/dinov3_features/` (mini, 323 files) |
| DINOv3 weights | `/mnt/SSD/yz0370/dinov3_weights/dinov3_vit7b16_pretrain_lvd1689m.pth` |
| P5b best ckpt | `iter_3000.pth` (car_P=0.107, used as P6 load_from) |
| BUG-33 report | `shared/logs/admin_report_bug33.md` |
| Diag report | `shared/logs/admin_report_diag.md` |

---

## 8. Next Actions

1. **P6 监控**: @2000 关键检查点 — 是否 car_P >= 0.10 且 bg_FA <= 0.30
2. **Plan M/N 完成**: ~11:35, 收集 @2000 最终结果, 更新 diag report
3. **P6 准确 eval**: 用修复后 config 单 GPU re-eval 关键 checkpoint (tools/test.py)
4. **等待 ORCH**: 后续可能需要 P6 full nuScenes 或进一步调参
5. **GPU 释放**: Plan M/N 完成后 GPU 1,3 空闲

---

## 9. Known Issues / Bugs

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

---

## 10. P5b Reference (10-class, DDP 2-GPU, gt_cnt has BUG-33 bias)

Best checkpoints: iter 3000 (car_P=0.107), iter 3500 (car_P=0.108), iter 1000 (multi-class peak)

car_P plateau @3000+ (0.104-0.108), bg_FA stabilized ~0.21. Precision values reliable despite BUG-33.
