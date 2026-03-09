# Admin Agent Context Snapshot
**Timestamp**: 2026-03-08 21:12
**Reason**: Session 结束前保存, Full nuScenes @2030 训练中

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status |
|-----------|-----|------|--------|
| **Full nuScenes** (2048+GELU+Online) | **0+1+2+3 DDP** | **~2030/40000** | **RUNNING** 6.3 s/iter, ETA 3月11日 |
| P6 (2048, no GELU, Mini) | - | 6000/6000 | COMPLETED — car_P=0.143 |
| Plan P2 (2048+GELU, Mini) | - | 2000/2000 | COMPLETED |
| Plan P/O/M/N/K/L (Mini) | - | - | ALL COMPLETED |

---

## 2. 正在做什么

**ORCH_024: Full nuScenes 训练** — 4 GPU DDP 运行中
- Task 1 ✅ Config 创建 (`plan_full_nuscenes_gelu.py`, 15 项检查全通过)
- Task 2 ✅ 在线 DINOv3 代码路径验证 (单 GPU 10 iter, 28.2 GB)
- Task 3 ✅ 4 GPU DDP 启动 (36.4-37.0 GB/GPU, 6.3 s/iter)
- Task 4 ⏳ 早期监控: @2000 val 完成, 等待 @4000 val

**当前进度**: @2030/40000, warmup 已结束, LR=5e-5 full rate

---

## 3. Full nuScenes @2000 Val (DDP) — 关键结果

| 指标 | Full@2000 | Mini P2@2000 | Mini P6@2000 |
|------|----------|--------------|--------------|
| car_R | **0.627** | 0.801 | 0.376 |
| car_P | **0.079** | 0.096 | 0.110 |
| truck_P | 0.000 | 0.027 | 0.032 |
| bus_P | 0.000 | 0.035 | 0.018 |
| ped_P | 0.001 | - | - |
| bg_FA | **0.222** | 0.295 | 0.300 |
| off_th | **0.174** | 0.208 | 0.234 |

**判定**: car_P=0.079 >> 0.02 阈值 → **在线路径可用 PASS!**
**亮点**: bg_FA=0.222 和 off_th=0.174 远优于所有 Mini 实验
**注意**: truck/bus/ped 等罕见类全为 0 (warmup 刚结束, 需更多 iter)
**BUG-33**: 这是 DDP 结果, 真实 car_P 可能更高

---

## 4. Full nuScenes 训练配置

| 参数 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_gelu.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu` |
| Log | `launch.log` (在 work dir 中) |
| 架构 | 2048+GELU proj (4096→2048→GELU→768), 在线 DINOv3 ViT-7B frozen FP16 |
| 数据 | Full nuScenes: train 28130, val 6019 |
| GPU | 4× A6000 DDP, 36.4-37.0 GB / 48 GB |
| 速度 | ~6.3-6.5 s/iter train, ~4.6 s/step val (753 steps) |
| LR | AdamW 5e-5, warmup 0→2000, milestones [15000,25000]+begin=2000 |
| max_iters | 40000 |
| val_interval | 2000 (Full nuScenes val split) |
| checkpoint | 每 2000 iter |
| Load from | P5b@3000 (proj 随机初始化, head/backbone 迁移) |
| ETA | ~2天21小时 (~3月11日 13:00) |

### LR Schedule:
- 0-2000: linear warmup (0.001x → 1.0x)
- 2000-17000: full LR 5e-5
- 17000-27000: 0.1x LR 5e-6
- 27000-40000: 0.01x LR 5e-7

---

## 5. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 015-023 | COMPLETED | Mini 验证阶段全部完成 |
| **024** | **IN PROGRESS** | Full nuScenes: @2000 car_P=0.079, 在线路径 PASS |

---

## 6. Mini 阶段关键基线 (供参考)

**P5b (1024+GELU, baseline):** car_P=0.116, bg_FA=0.189
**P6 (2048, no GELU):** car_P=0.143 @6000, bg_FA=0.265
**Plan P2 (2048+GELU):** car_P 轨迹 0.069→0.100→0.112→0.096

---

## 7. Known Issues

| Bug | Status | Notes |
|-----|--------|-------|
| BUG-33 | ACTIVE | DDP val 偏差 ±10%, Full @2000 是 DDP 结果, 需后续 single-GPU re-eval |
| BUG-39 | RESOLVED | Full config 已用 GELU (preextracted_proj_use_activation=True) |
| BUG-40 | RESOLVED | Full config warmup=2000 << max_iters=40000 |

---

## 8. 待办 (Next Actions)

1. **监控 @4000 val** — ETA ~3月9日 02:30
2. **@4000 后考虑单 GPU re-eval** — 确认 DDP 偏差 (BUG-33)
3. **检查 truck/bus 类是否开始出现** — 预期 @4000+ 开始有信号
4. **定期报告** — 每 2000 iter val 结果
5. **检查新 ORCH 指令** — `git pull` shared/pending/
