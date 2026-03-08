# Supervisor 摘要报告
> 时间: 2026-03-08 09:28
> Cycle: #152

## ===== ORCH_017 P6 启动! iter 90/6000 | Plan M/N @1000 val 进行中 | GPU 全满 =====

---

### 实验进度

| 实验 | GPU | 进度 | 状态 |
|------|-----|------|------|
| **Plan K (α)** 单类 car | — | 2000/2000 | ✅ COMPLETED |
| **Plan L (β)** 10类 宽投影 | — | 2000/2000 | ✅ COMPLETED |
| **Plan M (γ)** 在线 unfreeze | 1 | @1000 val 60/162 | val ~09:34 完成 |
| **Plan N (δ)** 在线 frozen | 3 | @1000 val 50/162 | val ~09:37 完成 |
| **🆕 P6 宽投影** | 0+2 | **90/6000** | 训练中, @500 ~09:48 |

---

### 🆕 ORCH_017: P6 宽投影 mini 验证 — 已启动

**Config**: `plan_p6_wide_proj.py`
- 投影层: `Linear(4096,2048) → Linear(2048,768)` — **无 GELU!** (BUG-30 测试)
- 投影层 LR 倍率: 2.0
- load_from: P5b@3000, 投影层 shape mismatch → **自动随机初始化** ✅
- 10 类, max_iters=6000, warmup=500, milestones=[2000,4000]
- DDP: GPU 0+2, 内存 ~16 GB/GPU, 速度 ~3.1 s/iter

**P6 Checkpoint 加载确认**:
- P5b@3000 权重加载成功
- `proj.0`: 1024→2048 shape mismatch → 随机初始化 ✅
- `proj.1`: missing (新 Linear) → 随机初始化 ✅
- `proj.2` (旧 GELU 位置): unexpected → 跳过 ✅
- layers.12-17: missing (原始 ViT 额外层) → 随机初始化

**P6 早期训练**:
| Iter | Loss | cls_loss | reg_loss | grad_norm | LR |
|------|------|----------|----------|-----------|-----|
| 10 | 11.42 | 9.10 | 2.32 | 39.5 | 4.8e-08 |
| 50 | 5.42 | 3.24 | 2.18 | 42.0 | 2.5e-07 |
| 90 | 3.80 | 2.08 | 1.72 | 63.3 | 4.5e-07 |

> Loss 快速下降 (11.4→3.8), warmup 正常, grad_norm 偏高但可接受 (随机 proj 层初期波动)

**P6 关键里程碑**:
| 里程碑 | 预计时间 | 检查项 |
|--------|---------|--------|
| @500 | ~09:48 | loss/grad 正常? |
| @1000 | ~10:14 | car_P≥0.10 且 bg_FA≤0.30 → PASS |
| @2000 | ~11:06 | off_th 无 GELU 是否 ≤0.18 |
| @3000 | ~11:58 | 决定是否切 full nuScenes |

---

### Plan M/N @1000 Val — 进行中

Plan M: val 60/162, ~09:34 完成
Plan N: val 50/162, ~09:37 完成

**@500 对比 (回顾)**:

| 指标 | M (unfreeze) | N (frozen) | K (预提取) |
|------|-------------|-----------|-----------|
| car_R | 0.621 | 0.618 | 0.629 |
| car_P | 0.052 | 0.050 | 0.064 |
| bg_FA | 0.220 | 0.219 | 0.183 |
| off_th | 0.217 | **0.206** | 0.228 |

> @500 几乎一致, **@1000 是 unfreeze vs frozen 关键分化点**
> ORCH_017 判定条件: M_car_P > 0.077 → 在线路径有价值

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-014 | COMPLETED | 历史 |
| ORCH_015 | COMPLETED | Plan K + Plan L 诊断完成 |
| ORCH_016 | IN_PROGRESS | Plan M (val @1000) + Plan N (val @1000) |
| **🆕 ORCH_017** | **DELIVERED → 执行中** | P6 宽投影 mini 验证, GPU 0+2, iter 90/6000 |

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 20.5 GB | 100% | **🆕 P6** (90/6000) |
| 1 | 37.8 GB | 98% | **Plan M** (@1000 val) |
| 2 | 21.0 GB | 100% | **🆕 P6** (90/6000) |
| 3 | 37.6 GB | 100% | **Plan N** (@1000 val) |

> **4 GPU 全满!** P6 (GPU 0+2) + M/N (GPU 1+3)

## 告警
1. **[NEW] P6 已启动**: 宽投影 2048, 无 GELU, GPU 0+2 DDP, iter 90/6000
2. **[NEW] P6 投影层随机初始化**: shape mismatch 自动处理, 符合预期
3. **[WATCH] P6 grad_norm 偏高** (39-63): 随机 proj 层 + warmup, 需观察下降趋势
4. **[PENDING] Plan M/N @1000 val**: ~09:34-09:37 完成, 关键分化数据
5. **[NEXT] P6 @500 val (~09:48)**: 首次验证
6. **[CRITERIA] ORCH_017 判定**: M_car_P > 0.077 → 在线路径有价值
