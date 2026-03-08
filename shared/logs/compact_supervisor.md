# Supervisor Compact Context Snapshot
> Timestamp: 2026-03-08 14:48
> Supervisor cycles: #89 — #163 (本轮 session 覆盖 #158-#163)
> Role: claude_supervisor — 信息中枢
> Reason: 用户请求保存工作上下文

---

## 当前任务

**角色**: claude_supervisor, 每 30 分钟执行自主监控循环
**循环**: git pull 两仓库 → 读训练日志 → 写 supervisor_report_latest.md → 检查 ORCH → 深度监控 → git push
**写入边界**: 只可写 `shared/logs/supervisor_*`, `shared/pending/` status 字段; GiT/ 只读

---

## 正在进行的实验

### 1. P6 宽投影训练 — 即将完成

- **Config**: `plan_p6_wide_proj.py`
- **架构**: Linear(4096,2048)→Linear(2048,768), **无 GELU** (BUG-39: 数学退化为单层 Linear)
- **投影层 LR mult**: 2.0, load_from P5b@3000
- **10 类**, max_iters=6000, warmup=500, val_interval=500
- **LR**: base=5e-05, milestones=[2000,4000] (实际 decay @2500, @4500)
- **GPU**: 0+2 DDP, ~3.0 s/iter, ~16 GB/GPU
- **当前进度**: iter 5450/6000, LR=2.5e-08, **@6000 ~15:15 完成**

### 2. Plan P2 — 2048+GELU 纯 BUG-39 修复 (ORCH_023)

- **Config**: `plan_p2_wide_gelu_fix.py`
- **唯一改动**: `proj_use_activation=True` (加 GELU), 其余与 P6 完全一致
- **GPU 1**, 单 GPU, max_iters=2000, val_interval=500
- **当前进度**: iter 830/2000, LR=2.5e-06
- **@500 val done**: car_P=0.069, bg_FA=0.256
- **@1000 val ETA**: ~14:57 (关键判定!)
- **完成 ETA**: ~15:47

---

## 重大发现 (本轮 session)

### BUG-33 (ORCH_018+019): DDP Val 偏差
- **根因**: val_dataloader 缺 sampler → DDP 下 GT 偏差
- **ORCH_019 re-eval**: P6 7 ckpts + P5b 2 ckpts 单 GPU re-eval 完成
- **关键**: DDP Precision 也有偏差 (最高 ±10%), @2000+ 偏差 <2%

### BUG-39 (ORCH_022): 无 GELU 线性退化
- **问题**: P6 的 Linear→Linear 无激活函数, 数学等价于单层 Linear, 2048 维度无额外表达力
- **影响**: P6 前 3000 iter 低于 P5b 真实基线的根本原因
- **修复**: Plan P2 (ORCH_023) — 加 GELU, 其余不变

### BUG-40 (ORCH_021): Plan O warmup=max_iters
- **问题**: Plan O warmup=500=max_iters=500, LR 从未达标, car_P=0.000
- **结论**: Plan O 结果无效

### P5b 真实基线 (ORCH_020)
- **P5b@3000 true**: car_P=**0.116** (DDP 0.107 低估 8%), bg_FA=0.189, off_th=0.195
- **P5b@6000 true**: car_P=0.115, bg_FA=0.188, off_th=0.194

---

## P6 完整真实 Val 轨迹 (单 GPU re-eval, 全可信)

| Ckpt | car_R | car_P | truck_P | bg_FA | off_th | vs P5b 0.116 |
|------|-------|-------|---------|-------|--------|-------------|
| @500 | 0.231 | 0.073 | 0.019 | 0.173 | 0.259 | ❌ -37% |
| @1000 | 0.252 | 0.058 | 0.027 | 0.352 | 0.220 | ❌ -50% |
| @1500 | 0.499 | 0.106 | 0.000 | 0.250 | 0.246 | ❌ -9% |
| @2000 | 0.376 | 0.110 | 0.032 | 0.300 | 0.234 | ❌ -5% |
| @2500 | 0.516 | 0.111 | 0.047 | 0.336 | 0.201 | ❌ -4% |
| @3000 | 0.617 | 0.106 | 0.054 | 0.297 | 0.196 | ❌ -9% |
| @3500 | 0.577 | **0.121** | 0.069 | 0.287 | 0.196 | ✅ +4.5% |
| @4000 | 0.546 | **0.126** | 0.075 | 0.274 | **0.191** | ✅ +8.9% |

**DDP val** (@4000+ 偏差 <2%):
| @4500 | — | 0.126 | 0.073 | 0.277 | 0.194 | ✅ |
| @5000 | — | **0.128** | 0.078 | 0.275 | 0.197 | ✅ +10% |

---

## Plan P2 Val 轨迹 (单 GPU, 可信)

| Ckpt | car_P | bg_FA | off_th | vs P6 同 iter |
|------|-------|-------|--------|-------------|
| @500 | 0.069 | 0.256 | 0.252 | P6=0.073 (P2略低) |
| @1000 | ? | ? | ? | **关键判定** ~14:57 |

---

## 已完成实验汇总

| 实验 | 路径 | proj | GELU | car_P@best | 结论 |
|------|------|------|------|-----------|------|
| P5b | 预提取 | 1024 | ✅ | 0.116 (true) | 基线 |
| Plan K | 预提取 | 1024 | ✅ | 0.064 | 类竞争非瓶颈 |
| Plan L | 预提取 | 2048 | ✅ | 0.140/@1000 | 宽投影+GELU 轻微帮助 |
| Plan M | 在线 unfreeze | 1024 | ✅ | 0.049 | 在线不如预提取 |
| Plan N | 在线 frozen | 1024 | ✅ | 0.050 | 在线不如预提取 |
| **P6** | 预提取 | 2048 | ❌ | **0.128** (DDP) | BUG-39 但 @4000 仍超 P5b |
| Plan O | 在线 frozen | 2048 | ❌ | 0.000 | BUG-40 无效 |
| Plan P | 预提取 | 2048 | ✅ | 0.004 | 超参错误 (lr_mult=1.0+warmup=100) |
| **Plan P2** | 预提取 | 2048 | ✅ | 0.069@500 | **运行中**, 纯 BUG-39 修复 |

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-016 | COMPLETED | P1-P5b, K/L/M/N 诊断 |
| ORCH_017 | EXECUTED | P6 宽投影训练 |
| ORCH_018 | EXECUTED | BUG-33 修复 |
| ORCH_019 | COMPLETED | P6 re-eval, DDP P 偏差 ±10% |
| ORCH_020 | COMPLETED | P5b re-eval: true car_P=0.116 |
| ORCH_021 | COMPLETED (无效) | Plan O BUG-40 |
| ORCH_022 | COMPLETED (异常) | Plan P 超参错误 |
| **ORCH_023** | **IN PROGRESS** | P6@4000 re-eval ✅ + Plan P2 训练中 |

---

## GPU 状态 (Cycle #163)

| GPU | Used | Task |
|-----|------|------|
| 0 | 20.5 GB | **P6** (5450/6000) ~15:15 完成 |
| 1 | 19.8 GB | **Plan P2** (830/2000) ~15:47 完成 |
| 2 | 21.0 GB | **P6** (5450/6000) |
| 3 | **空闲** | — |

---

## 关键路径

| 用途 | 路径 |
|------|------|
| 调度仓库 | `/home/UNT/yz0370/projects/GiT_agent/` (读写) |
| 研究代码 | `/home/UNT/yz0370/projects/GiT/` (只读) |
| P6 log | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/plan_p6_wide_proj/train.log` |
| P2 log | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/plan_p2_wide_gelu_fix/train.log` |
| BUG-33 报告 | `shared/logs/admin_report_bug33.md` |
| 报告输出 | `shared/logs/supervisor_report_latest.md` |
| 报告历史 | `shared/logs/supervisor_report_history.md` |

---

## 恢复指南
1. 读 `agents/claude_supervisor/CLAUDE.md` 确认角色
2. `git pull` 两仓库
3. 读 P6 日志: `grep "Iter(val) \[162/162\]" .../plan_p6_wide_proj/train.log`
4. 读 P2 日志: `grep "Iter(val) \[162/162\]" .../plan_p2_wide_gelu_fix/train.log`
5. 检查新 ORCH 指令 (`ls -lt shared/pending/`)
6. 写 supervisor_report_latest.md
7. git push
8. 继续 30 分钟循环
9. **关注**:
   - **P6 @6000 final ~15:15** — 训练结束
   - **P2 @1000 ~14:57** — GELU 是否加速收敛的关键判定
   - **P2 @2000 ~15:47** — P2 vs P6 最终对比, 决定 full nuScenes config
   - GPU 3 空闲, Conductor 可能分配新任务
   - P6 @6000 后 GPU 0+2 释放
