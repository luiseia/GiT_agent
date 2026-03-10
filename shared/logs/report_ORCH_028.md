# Report: ORCH_028 — Full nuScenes Overlap-Based Grid Retraining

**状态**: IN PROGRESS
**启动时间**: 2026-03-09 21:34
**目标**: BUG-51 修复验证 — overlap grid assignment 替代 center-based

---

## 实验设置

| 参数 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_gelu.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260309/full_nuscenes_overlap` |
| GPU | 0,1,2,3 (4 GPU DDP), PID 1220551 |
| grid_assign_mode | **overlap** (唯一与 ORCH_024 的区别) |
| max_iters | 40000, val_interval=2000 |
| 显存 | 28849 MB/GPU |
| 速度 | ~6.2-6.5 s/iter |

---

## @100 iter 早期监控

### reg=0 频率统计

| 指标 | ORCH_028 (overlap) | ORCH_024 (center) |
|------|--------------------|--------------------|
| reg=0 频率 | **0/10 = 0.0%** | 28.6% |
| 判定 | ✅ < 10% | ❌ 过高 |

**结论: overlap grid assignment 完全消除了 reg=0 现象**, 每个 batch 都有足够回归训练信号。

### Loss 趋势 @10-100

| iter | loss | cls_loss | reg_loss | grad_norm |
|------|------|----------|----------|-----------|
| 10 | 5.870 | 3.481 | 2.389 | 39.40 |
| 20 | 7.665 | 4.828 | 2.837 | 54.68 |
| 30 | 5.616 | 2.762 | 2.854 | 69.29 |
| 40 | 4.547 | 2.012 | 2.535 | 28.81 |
| 50 | 5.593 | 2.907 | 2.686 | 54.35 |
| 60 | 3.856 | 1.423 | 2.433 | 24.37 |
| 70 | 4.948 | 2.173 | 2.774 | 32.53 |
| 80 | 8.977 | 6.183 | 2.793 | 36.20 |
| 90 | 7.793 | 5.099 | 2.694 | 51.87 |
| 100 | 7.308 | 4.654 | 2.654 | 39.45 |

- reg_loss 范围 2.39-2.85，波动正常，**从未为零**
- cls_loss 波动较大 (1.4-6.2)，warmup 阶段 LR 极低，正常

### 系统状态
- 显存: 28849 MB (稳定)
- ETA: ~2 days 22 hours (预计 3/12 ~20:00 完成)
- 速度: 6.2-6.5 s/iter (与 ORCH_024 一致)

---

## 下一检查点

- **@500 iter** (~21:46 + 400*6.4s ≈ 22:29 + 43min ≈ ~22:29 3/10 00:30): loss 趋势, reg=0 持续为零
- **@2000 val** (~21:46 + 1900*6.4s ≈ ~3/10 01:00): 首次 eval, 与 ORCH_024 @2000 对比

---

*Admin Agent 执行 | 2026-03-09 21:48*
