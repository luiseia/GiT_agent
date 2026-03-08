# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 16:45
**Reason**: ORCH_024 Full nuScenes 训练已启动, 4 GPU DDP 运行中

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status |
|-----------|-----|------|--------|
| **Full nuScenes** (2048+GELU+Online) | **0+1+2+3 DDP** | **30/40000** | **RUNNING** ~6.3 s/iter, ETA 3月11日 |
| P6 (2048, no GELU) | - | 6000/6000 | COMPLETED — car_P=0.143 (新纪录) |
| Plan P2 (2048+GELU) | - | 2000/2000 | COMPLETED — car_P轨迹: 0.069→0.100→0.112→0.096 |
| Plan P/O/M/N/K/L | - | - | ALL COMPLETED |

---

## 2. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 015-020 | COMPLETED | Mini 诊断实验全部完成 |
| 021 | COMPLETED — 无效 | Plan O BUG-40, 全程 warmup |
| 022 | COMPLETED — 异常 | Plan P lr_mult=1.0 导致收敛失败 |
| 023 | COMPLETED | P6@6000=0.143, P2 GELU 确认有效 |
| **024** | **IN PROGRESS** | Full nuScenes: 2048+GELU+在线 DINOv3, 4 GPU DDP |

---

## 3. Full nuScenes 训练详情 (ORCH_024)

**Config**: `configs/GiT/plan_full_nuscenes_gelu.py`
**Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu`
**Log**: `launch.log`

| 参数 | 值 |
|------|-----|
| 架构 | 2048+GELU proj (4096→2048→GELU→768) |
| 特征源 | 在线 DINOv3 ViT-7B frozen FP16 |
| 数据 | Full nuScenes: train 28130, val 6019 |
| GPU | 4× A6000 DDP, 36.4-37.0 GB / 48 GB |
| 速度 | ~6.3 s/iter |
| Batch | 2/GPU × 4 GPU × accum 4 = effective 32 |
| LR | AdamW 5e-5, warmup 2000, milestones [15000,25000]+2000 |
| max_iters | 40000 |
| Val | 每 2000 iter, Full nuScenes val split |
| Load from | P5b@3000 |
| ETA | ~2天21小时 (~3月11日 13:00) |

**早期 Loss:**

| Iter | Loss | cls_loss | reg_loss | grad_norm |
|------|------|----------|----------|-----------|
| 10 | 6.28 | 3.85 | 2.43 | 37.9 |
| 20 | 8.34 | 5.40 | 2.95 | 57.2 |
| 30 | 5.55 | 2.74 | 2.81 | 65.9 |

**监控节点:**
- @500 val: ETA ~17:22 (确认方向正确)
- @1000 val: ETA ~18:15 (car_P > 0.02 判定)
- @2000 val: ETA ~20:00 (完整指标报告)

---

## 4. Mini 阶段关键基线

**P5b (1024+GELU, baseline):**
| Ckpt | car_P | bg_FA | off_th |
|------|-------|-------|--------|
| @3000 | 0.116 | 0.189 | 0.195 |

**P6 (2048, no GELU, 新纪录):**
| Ckpt | car_P | bg_FA | off_th | truck_P |
|------|-------|-------|--------|---------|
| @6000 | **0.143** | 0.265 | 0.190 | 0.075 |

---

## 5. Known Issues / Bugs

| Bug | Status | Description |
|-----|--------|-------------|
| BUG-33 | FIXED | DDP val sampler — Full config 已加 explicit sampler |
| BUG-39 | RESOLVED | Plan P2 验证 GELU 有效, Full config 已用 GELU |
| BUG-40 | CONFIRMED | Plan O warmup 问题, Full config warmup=2000 (远小于 40000) |

---

## 6. Next Actions

1. **监控 Full nuScenes @500 val** — ETA ~17:22
2. **@2000 后做单 GPU re-eval** — BUG-33 DDP 偏差教训
3. **定期报告** — 每 2000 iter 一次
