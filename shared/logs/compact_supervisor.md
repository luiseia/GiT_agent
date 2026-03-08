# Supervisor Compact Context Snapshot
> Timestamp: 2026-03-08 17:42
> Supervisor cycles: #89 — #170 (本轮 session 覆盖 #164-#170)
> Role: claude_supervisor — 信息中枢
> Reason: 用户请求保存工作上下文

---

## 当前任务

**角色**: claude_supervisor, 每 30 分钟执行自主监控循环
**循环**: git pull 两仓库 → 读训练日志 → 写 supervisor_report_latest.md → 检查 ORCH → 深度监控 → git push
**写入边界**: 只可写 `shared/logs/supervisor_*`, `shared/pending/` status 字段; GiT/ 只读

---

## 正在进行的实验

### Full nuScenes 训练 (ORCH_024) — 核心任务

- **Config**: `plan_full_nuscenes_gelu.py`
- **架构**: 在线 DINOv3 frozen + Linear(4096,2048)→GELU→Linear(2048,768)
- **数据**: Full nuScenes (28130 train, 6019 val)
- **GPU**: 0+1+2+3 DDP, ~6.3-6.5 s/iter, ~28.8 GB/GPU (A6000 48GB)
- **max_iters**: 40000, warmup=2000, milestones=[15000,25000]
- **val_interval**: 2000, checkpoint_interval=2000
- **LR**: base=~5e-05, lr_mult=2.0 for proj, gamma=0.1
- **load_from**: P5b@3000
- **当前进度**: iter 610/40000, LR=7.6e-07 (warmup 中)
- **ETA**: ~3/11 14:30 (约 2 天 22 小时)
- **训练日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/20260308_163535/20260308_163535.log`

---

## Mini 阶段总结 (ORCH_001-023 全部 COMPLETED)

### P6 FINAL (2048, 无 GELU, 预提取)
- **@6000 DDP FINAL**: car_P=**0.129**, bg_FA=0.274, off_th=0.200
- 超 P5b 基线 (0.116) +11%, 但需 3500+ iter 和 LR decay 才达到
- DDP val @4000+ 偏差 <2%

### Plan P2 FINAL (2048+GELU, 预提取, 纯 BUG-39 修复)

| Ckpt | car_P | bg_FA | off_th | vs P6 同 iter |
|------|-------|-------|--------|-------------|
| @500 | 0.069 | 0.256 | 0.252 | P6=0.073 (-5.6%) |
| @1000 | **0.100** | 0.328 | 0.227 | **P6=0.058 (+72%!)** |
| @1500 | **0.112** | 0.279 | 0.251 | **P6=0.106 (+5.7%)** |
| @2000 | 0.096 | 0.295 | 0.208 | P6=0.110 (-12.8%, 回调) |

**结论**: GELU 在 @1000-1500 显著加速收敛, @2000 回调因无 LR decay. Full nuScenes 用 2048+GELU + milestones decay 应避免回调.

### P5b 真实基线
- car_P=**0.116**, bg_FA=0.189, off_th=0.195

### P6 完整真实 Val 轨迹 (单 GPU re-eval)

| Ckpt | car_P | truck_P | bg_FA | off_th | vs P5b |
|------|-------|---------|-------|--------|--------|
| @500 | 0.073 | 0.019 | 0.173 | 0.259 | ❌ |
| @1000 | 0.058 | 0.027 | 0.352 | 0.220 | ❌ |
| @1500 | 0.106 | 0.000 | 0.250 | 0.246 | ❌ |
| @2000 | 0.110 | 0.032 | 0.300 | 0.234 | ❌ |
| @2500 | 0.111 | 0.047 | 0.336 | 0.201 | ❌ |
| @3000 | 0.106 | 0.054 | 0.297 | 0.196 | ❌ |
| @3500 | 0.121 | 0.069 | 0.287 | 0.196 | ✅ +4.5% |
| @4000 | 0.126 | 0.075 | 0.274 | 0.191 | ✅ +8.9% |
| @4500 | ~0.126 | 0.073 | 0.277 | 0.194 | ✅ (DDP) |
| @5000 | ~0.128 | 0.078 | 0.275 | 0.197 | ✅ +10% (DDP) |
| @5500 | ~0.128 | 0.075 | 0.273 | 0.199 | ✅ (DDP) |
| @6000 | **~0.129** | 0.076 | 0.274 | 0.200 | **✅ +11% (DDP FINAL)** |

### 已完成实验汇总

| 实验 | 路径 | proj | GELU | car_P@best | 结论 |
|------|------|------|------|-----------|------|
| P5b | 预提取 | 1024 | ✅ | 0.116 (true) | 基线 |
| Plan K | 预提取 | 1024 | ✅ | 0.064 | 类竞争非瓶颈 |
| Plan L | 预提取 | 2048 | ✅ | 0.140/@1000 | 宽投影+GELU 帮助 (有 BUG-28) |
| Plan M | 在线 unfreeze | 1024 | ✅ | 0.049 | 在线不如预提取 |
| Plan N | 在线 frozen | 1024 | ✅ | 0.050 | 在线不如预提取 |
| P6 | 预提取 | 2048 | ❌ | **0.129** @6000 | BUG-39 但仍超 P5b +11% |
| Plan O | 在线 frozen | 2048 | ❌ | 0.000 | BUG-40 无效 |
| Plan P | 预提取 | 2048 | ✅ | 0.004 | 超参错误 |
| Plan P2 | 预提取 | 2048 | ✅ | 0.112 @1500 | GELU 加速收敛 |

### 重大 BUG 记录
- **BUG-33**: DDP val 缺 sampler → GT+P 偏差. 修复: 加 DefaultSampler
- **BUG-39**: P6 无 GELU → 两层 Linear 退化为单层. 修复: Plan P2 加 GELU
- **BUG-40**: Plan O warmup=max_iters → LR 从未达标. 结果无效

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-023 | COMPLETED | Mini 阶段全部完成 |
| **ORCH_024** | **IN PROGRESS** | Full nuScenes 训练 (610/40000) |

---

## GPU 状态 (Cycle #170)

| GPU | Used | Task |
|-----|------|------|
| 0 | 36.5 GB | **Full nuScenes** (610/40000) |
| 1 | 36.4 GB | **Full nuScenes** |
| 2 | 37.0 GB | **Full nuScenes** |
| 3 | 36.5 GB | **Full nuScenes** |

---

## 关键路径

| 用途 | 路径 |
|------|------|
| 调度仓库 | `/home/UNT/yz0370/projects/GiT_agent/` (读写) |
| 研究代码 | `/home/UNT/yz0370/projects/GiT/` (只读) |
| Full nuScenes log | `.../full_nuscenes_gelu/20260308_163535/20260308_163535.log` |
| P6 log (完成) | `.../plan_p6_wide_proj/train.log` |
| P2 log (完成) | `.../plan_p2_wide_gelu_fix/train.log` |
| 报告输出 | `shared/logs/supervisor_report_latest.md` |
| 报告历史 | `shared/logs/supervisor_report_history.md` |

---

## 恢复指南
1. 读 `agents/claude_supervisor/CLAUDE.md` 确认角色
2. `git pull` 两仓库
3. 读 Full nuScenes 日志尾部: `tail -30 .../full_nuscenes_gelu/20260308_163535/20260308_163535.log`
4. 搜 val 结果: `grep "Iter(val)" .../20260308_163535.log | tail -5`
5. 检查新 ORCH 指令 (`ls -lt shared/pending/`)
6. 检查 GPU: `nvidia-smi --query-gpu=...`
7. 写 supervisor_report_latest.md
8. git push
9. 继续 30 分钟循环
10. **关注**:
    - **首次 val @2000 ~20:13** — warmup 刚结束, 确认在线 DINOv3 路径正常
    - **@4000 val ~3/9 00:50** — 第一个有意义的 post-warmup eval
    - **LR decay @17000 ~3/9 22:00** — milestone 15000 + begin 2000
    - **训练完成 @40000 ~3/11 14:30**
    - DDP val 注意 BUG-33: @2000 后建议单 GPU re-eval 确认真实值
