# Supervisor 摘要报告
> 时间: 2026-03-08 16:44
> Cycle: #168

## ===== 🚀 ORCH_024: Full nuScenes 训练已启动! 4 GPU DDP, 在线 DINOv3+2048+GELU =====

---

### ⭐ ORCH_024: Full nuScenes 训练 — 新阶段开始!

**核心配置:**
| 参数 | 值 |
|------|-----|
| 数据 | **Full nuScenes** (28130 train, 6019 val) |
| 架构 | 在线 DINOv3 frozen + 2048+GELU 投影 |
| GPU | 4 GPU DDP (0+1+2+3) |
| max_iters | 40000 |
| warmup | 2000 iter |
| milestones | [15000, 25000] (相对 begin) |
| val_interval | 2000 |
| base_lr | ~5e-05, lr_mult=2.0 for proj |
| load_from | P5b@3000 |
| ETA | ~3 月 11 日 (约 2 天 22 小时) |

**当前状态 (iter 60/40000, 16:43:12):**
| 指标 | 值 |
|------|-----|
| 速度 | ~6.3-6.5 s/iter |
| 显存 | 28.8 GB/GPU (A6000 48 GB, 余量充足) |
| LR | 7.6e-08 (warmup 初期, 极低) |
| Loss @10 | 6.28 (cls=3.85, reg=2.43) |
| Loss @30 | 5.55 (cls=2.74, reg=2.81) |
| Loss @60 | **4.00** (cls=1.44, reg=2.56) — 持续下降 ✅ |

> Loss 正常下降, 在线 DINOv3 运行稳定, 无报错.

---

### 关键里程碑 ETA

| 事件 | iter | ETA | 关注点 |
|------|------|-----|--------|
| @500 early val | 500 | ~17:29 | 确认 val 正常运行, car_P>0 |
| @1000 val | 1000 | ~18:22 | car_P>0.02 → 在线路径正常 |
| warmup 结束 | 2000 | ~20:08 | LR 达到目标值, 训练正式开始 |
| @2000 val | 2000 | ~20:13 | 第一个有意义的 eval |
| 第一次 LR decay | 17000 | 3/9 ~22:00 | milestone @15000 + begin=2000 |
| 第二次 LR decay | 27000 | 3/10 ~15:30 | milestone @25000 + begin=2000 |
| **训练结束** | **40000** | **~3/11 14:30** | **最终评估** |

---

### Mini 阶段总结 (存档)

| 实验 | car_P@best | 结论 |
|------|-----------|------|
| P5b (1024+GELU) | 0.116 | 基线 |
| P6 (2048, noGELU) | **0.129** @6000 | BUG-39 但仍超 P5b +11% |
| Plan P2 (2048+GELU) | **0.112** @1500 | GELU 加速收敛, @2000 回调 (无 LR decay) |
| 结论 | — | **Full nuScenes 用 2048+GELU**, milestones @17000/27000 应避免回调 |

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-023 | COMPLETED | Mini 阶段全部完成 |
| **ORCH_024** | **IN PROGRESS** | Full nuScenes 训练 (60/40000), 4 GPU DDP |

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 36.5 GB | 100% | **Full nuScenes** (60/40000) |
| 1 | 36.4 GB | 100% | **Full nuScenes** |
| 2 | 37.0 GB | 100% | **Full nuScenes** |
| 3 | 36.5 GB | 100% | **Full nuScenes** |

## 告警
1. **[STARTED] Full nuScenes 训练**: 4 GPU DDP, 在线 DINOv3, loss 正常下降
2. **[WATCH] @500 val ~17:29**: 第一次 eval, 确认在线路径正常
3. **[NOTE] DDP val 注意**: BUG-33 教训, @2000 后需单 GPU re-eval 确认真实值
4. **[INFO] 训练日志路径**: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/20260308_163535/20260308_163535.log`
