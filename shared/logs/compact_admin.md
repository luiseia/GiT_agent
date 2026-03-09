# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 21:10
**Reason**: Full nuScenes @2000 val 完成, car_P=0.079, 在线路径 PASS

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status |
|-----------|-----|------|--------|
| **Full nuScenes** (2048+GELU+Online) | **0+1+2+3 DDP** | **2000+/40000** | **RUNNING** car_P=0.079@2000 |
| P6 (2048, no GELU, Mini) | - | 6000/6000 | COMPLETED — car_P=0.143 |
| Plan P2 (2048+GELU, Mini) | - | 2000/2000 | COMPLETED |
| Plan P/O/M/N/K/L (Mini) | - | - | ALL COMPLETED |

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 015-023 | COMPLETED | Mini 验证阶段全部完成 |
| **024** | **IN PROGRESS** | Full nuScenes: @2000 car_P=0.079 PASS |

---

## 3. Full nuScenes @2000 Val (DDP) — 关键结果

| 指标 | Full@2000 | Mini P2@2000 | Mini P6@2000 |
|------|----------|--------------|--------------|
| car_R | **0.627** | 0.801 | 0.376 |
| car_P | **0.079** | 0.096 | 0.110 |
| truck_P | 0.000 | 0.027 | 0.032 |
| bus_P | 0.000 | 0.035 | 0.018 |
| bg_FA | **0.222** | 0.295 | 0.300 |
| off_th | **0.174** | 0.208 | 0.234 |

**判定**: car_P=0.079 >> 0.02 阈值 → 在线路径可用!
**亮点**: bg_FA 和 off_th 远优于所有 Mini 实验

---

## 4. Full nuScenes 训练配置

| 参数 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_gelu.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu` |
| 架构 | 2048+GELU proj, 在线 DINOv3 ViT-7B frozen FP16 |
| 数据 | train 28130, val 6019 |
| GPU | 4× A6000 DDP, 36.4-37.0 GB/48 GB |
| 速度 | ~6.4 s/iter train, ~4.6 s/step val |
| LR | AdamW 5e-5, warmup 2000, milestones [15000,25000]+2000 |
| max_iters | 40000, ETA ~3月11日 |

---

## 5. Known Issues

| Bug | Status | Notes |
|-----|--------|-------|
| BUG-33 | ACTIVE | DDP val 偏差, Full @2000 是 DDP 结果, 需后续 single-GPU re-eval |
| BUG-39 | RESOLVED | Full config 已用 GELU |
| BUG-40 | RESOLVED | Full config warmup=2000 << 40000 |

---

## 6. Next Actions

1. **监控 @4000 val** — ETA ~3月9日 02:30
2. **@4000+ 单 GPU re-eval** — 确认 DDP 偏差
3. **定期报告** — 每 2000 iter
