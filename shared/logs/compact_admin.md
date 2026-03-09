# Admin Agent Context Snapshot
**Timestamp**: 2026-03-09 03:10
**Reason**: Session 保存, ORCH_024 @4060 + ORCH_026 Plan Q @10 并行训练中

---

## 1. Current Training Status

| Experiment | GPU | Iter | Status |
|-----------|-----|------|--------|
| **Full nuScenes** (ORCH_024) | **0+1+2+3 DDP** | **~4060/40000** | **RUNNING** 6.3 s/iter, ETA 3月11日 |
| **Plan Q car-only** (ORCH_026) | **1 (共存)** | **~10/3000** | **RUNNING** 3.4 s/iter, 9058 MB, ETA ~06:20 |
| P6 (2048, no GELU, Mini) | - | 6000/6000 | COMPLETED — car_P=0.143 |
| Plan P2 (2048+GELU, Mini) | - | 2000/2000 | COMPLETED |

---

## 2. 正在做什么

### ORCH_024: Full nuScenes 训练 — 4 GPU DDP 运行中
- Task 1-3 ✅ 全部完成
- Task 4 ⏳ 监控中: @2000 + @4000 val 已完成, 等待 @6000

### ORCH_025: 自动化测试框架 — COMPLETED
- 177 passed, 12 skipped, 3 xfailed
- 4 个测试文件: config_sanity, eval_integrity, label_generation, training_smoke

### ORCH_026: Plan Q 单类 Car 诊断 — IN PROGRESS
- Task 1 ✅ Config 创建 (`plan_q_single_car_diag.py`)
- Task 2 ✅ 验证通过 (10 iter, 9058 MB, class_filter 生效)
- Task 3 ⏳ 训练中 @10/3000, GPU 1 (与 ORCH_024 共存)
- Task 4 待完成 — 训练后提取 car_P 曲线

**代码改动**: `generate_occ_flow_labels.py` 新增 `class_filter` 参数，向后兼容

---

## 3. Full nuScenes Val 结果追踪

| 指标 | @2000 | @4000 | 趋势 |
|------|-------|-------|------|
| car_R | 0.627 | 0.419 | ↓ P/R tradeoff |
| car_P | 0.079 | 0.078 | 持平 |
| truck_P | 0.000 | **0.057** | ★ 从 0 出现! |
| bus_P | 0.000 | 0.002 | 微弱信号 |
| bicycle_R | 0.000 | **0.191** | 新出现 |
| bg_FA | 0.222 | **0.199** | ↓ 改善 |
| off_th | 0.174 | **0.150** | ↓ 改善 |
| off_cx | 0.056 | **0.039** | ↓ 改善 |

**判定**: 训练健康, truck 信号出现, bg/offset 持续改善, 继续训练
**下一 val**: @6000, ETA ~3月9日 05:00

---

## 4. 训练配置速查

### ORCH_024 Full nuScenes
| 参数 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_gelu.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu` |
| 架构 | 2048+GELU proj, 在线 DINOv3 ViT-7B frozen FP16 |
| 数据 | Full nuScenes: train 28130, val 6019 |
| GPU | 4× A6000 DDP, 36.4-37.0 GB / 48 GB |
| LR | AdamW 5e-5, warmup 0→2000, milestones [15000,25000]+begin=2000 |
| max_iters | 40000, val_interval=2000 |

### ORCH_026 Plan Q
| 参数 | 值 |
|------|-----|
| Config | `configs/GiT/plan_q_single_car_diag.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260309/plan_q_single_car` |
| 架构 | 2048+GELU proj, 预提取特征 (不加载 DINOv3) |
| 数据 | Mini nuScenes (323 samples), class_filter=['car'] |
| GPU | GPU 1 单卡, 9058 MB |
| LR | AdamW 5e-5, warmup 500, milestones [1000,2000]+begin=500 |
| max_iters | 3000, val_interval=500 |
| 判定标准 | car_P@best > 0.20 → 类竞争是瓶颈; < 0.12 → 类竞争无关 |

---

## 5. ORCH History

| ORCH | Status | Summary |
|------|--------|---------|
| 015-023 | COMPLETED | Mini 验证阶段全部完成 |
| **024** | **IN PROGRESS** | Full nuScenes: @4000 truck_P=0.057, bg_FA=0.199 |
| **025** | **COMPLETED** | 测试框架: 177 passed, 3 xfail (旧 config BUG) |
| **026** | **IN PROGRESS** | Plan Q car-only: 训练中 @10/3000 |

---

## 6. Known Issues

| Bug | Status | Notes |
|-----|--------|-------|
| BUG-33 | ACTIVE | DDP val 偏差 ±10%, @4000 是 DDP 值 |
| BUG-42 | DETECTED | 旧 config plan_h/plan_p2 milestones > max_iters (测试发现) |
| BUG-41 | DETECTED | 旧 config plan_o warmup_end >= max_iters (测试发现) |

---

## 7. Git Commits (本 Session)

| Hash | Message |
|------|---------|
| b00d1da | Add pytest test framework (ORCH_025) |
| 5e7af1e | Add Plan Q config + class_filter (ORCH_026) |

---

## 8. 待办 (Next Actions)

1. **监控 ORCH_024 @6000 val** — ETA ~3月9日 05:00
2. **等待 ORCH_026 Plan Q 完成** — ETA ~06:20, 提取 car_P 曲线, 写报告
3. **检查新 ORCH 指令** — `git pull` shared/pending/
4. **ORCH_024 @6000+ 后考虑单 GPU re-eval** — 确认 DDP 偏差 (BUG-33)
