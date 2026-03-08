# Supervisor 摘要报告
> 时间: 2026-03-08 10:55
> Cycle: #155

## ===== Plan M/N @1500 | M 召回崩塌 0.489 证实 unfreeze 不稳定 | ORCH_018 BUG-33 gt_cnt 调查 | P6 训练减速 =====

---

### 实验进度

| 实验 | GPU | 进度 | 状态 |
|------|-----|------|------|
| Plan K/L | — | done | ✅ COMPLETED |
| **Plan M (γ)** 在线 unfreeze | 1 | 1640/2000 | **@1500 done (NEW)**, LR decayed |
| **Plan N (δ)** 在线 frozen | 3 | 1610/2000 | **@1500 done (NEW)**, LR decayed |
| **P6 宽投影** | 0+2 | ~1500/6000 | @1500 val 进行中 |

---

### Plan M vs N @1500 — Unfreeze 不稳定确认

**Plan M 完整轨迹 (在线 unfreeze)**:

| Ckpt | car_R | car_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.621 | 0.052 | 0.220 | 0.088 | 0.102 | 0.217 |
| @1000 | **0.699** | 0.049 | 0.249 | 0.079 | 0.090 | 0.232 |
| @1500 | **0.489**↓↓ | 0.047 | **0.182** | **0.071** | 0.098 | **0.194** |

**Plan N 完整轨迹 (在线 frozen)**:

| Ckpt | car_R | car_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.618 | 0.050 | 0.219 | 0.088 | 0.104 | 0.206 |
| @1000 | 0.661 | 0.050 | 0.250 | 0.080 | 0.078 | 0.231 |
| @1500 | 0.630 | 0.045 | 0.236 | 0.080 | **0.081** | 0.229 |

**@1500 M vs N 对比**:

| 指标 | M (unfreeze) | N (frozen) | 胜者 |
|------|-------------|-----------|------|
| car_R | **0.489** ↓↓ | **0.630** | N 大胜 (+14%) |
| car_P | 0.047 | 0.045 | ≈ |
| bg_FA | **0.182** | 0.236 | M 胜 |
| off_cx | **0.071** | 0.080 | M 略优 |
| off_cy | 0.098 | **0.081** | N 优 |
| off_th | **0.194** | 0.229 | M 胜 |

**关键结论**:
1. **Unfreeze 导致 car_R 崩塌**: 0.699→0.489 (-21%), 而 N 稳定在 0.630 — **DINOv3 微调造成特征漂移, 不稳定**
2. **Unfreeze 的 bg_FA/off_th 更好**: 可能是因为 car_R 下降导致预测更保守
3. **Frozen 更稳定可靠**: 全程 car_R 波动仅 ±3%, offsets 稳定
4. **两者 LR 已 decay**: 2.5e-06 → 2.5e-07 (milestone @1500), @2000 最终值将在低 LR 下收敛

> **诊断最终结论: Frozen DINOv3 >> Unfreeze DINOv3。在线路径应使用 frozen 模式。**

---

### P6 训练异常

**⚠️ P6 训练减速 + loss 飙升**:
- 速度: ~3.0 s/iter (正常) → **~5.3 s/iter** (iter 1450 起, +77%)
- Loss 飙升: iter 1460 loss=8.61 (cls=6.40), grad_norm=39-71
- **GPU 0 内存**: 20.5 GB → **32.5 GB** (+12 GB), GPU 2 不变 (21 GB)
- 可能原因: BUG-33 调查进程占用 GPU 0 资源

P6 @1500 val 正在进行 (50/162), ~10:58 完成。

---

### 🆕 ORCH_018: BUG-33 gt_cnt 跨实验不一致调查

- **状态**: DELIVERED
- **优先级**: HIGH — P6 @2000 前必须完成 (~11:10)
- **问题**: P6 val 的 gt_cnt (car=7232, truck=3206) 与 Plan L/P5b (car=6719, truck=1640) 不一致, truck +95%
- **影响**: 所有 P6 跨实验对比可能无效
- **调查方向**: eval-only 对比, ann_file/pipeline 差异, `generate_occ_flow_labels.py` 变更
- **最可能原因**: P6 代码变更 (ORCH_017 commit) 可能修改了评估逻辑

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-015 | COMPLETED | 历史 |
| ORCH_016 | IN_PROGRESS | Plan M (1640/2000) + Plan N (1610/2000) |
| ORCH_017 | IN_PROGRESS | P6 (~1500/6000), @1000 双 FAIL |
| **🆕 ORCH_018** | **DELIVERED** | BUG-33 gt_cnt 调查, HIGH |

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | **32.5 GB** ⚠️ | 100% | P6 + ?(BUG-33 eval?) |
| 1 | 37.8 GB | 100% | Plan M (1640/2000) |
| 2 | 21.0 GB | 100% | P6 (1500/6000) |
| 3 | 37.6 GB | 100% | Plan N (1610/2000) |

## 告警
1. **[CRITICAL] Plan M car_R 崩塌**: 0.699→0.489, unfreeze 不稳定确认
2. **[CONCLUSION] Frozen >> Unfreeze**: 在线 DINOv3 应使用 frozen 模式
3. **[ANOMALY] P6 训练减速**: 3.0→5.3 s/iter, GPU 0 内存 +12 GB
4. **[ANOMALY] P6 loss 飙升**: iter 1460 loss=8.61, grad_norm 高位
5. **[NEW] ORCH_018 BUG-33**: gt_cnt 不一致调查, 截止 P6 @2000 (~11:10)
6. **[NEXT] P6 @1500 val (~10:58), Plan M/N @2000 final (~11:32-11:35)**
