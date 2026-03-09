# Supervisor Compact Context Snapshot
> Timestamp: 2026-03-08 23:00
> Supervisor cycles: #89 — #179 (本轮 session 覆盖 #171-#179)
> Role: claude_supervisor — 信息中枢
> Reason: 用户请求保存工作上下文

---

## 当前任务

**角色**: claude_supervisor, 按 `shared/commands/supervisor_cmd.md` 严格执行监控循环
**循环**: git pull 两仓库 → 读训练日志 → 写 supervisor_report_latest.md → 检查 ORCH (grep PENDING) → 深度监控 (GPU + df -h + 进程存活) → git push
**写入边界**: 只可写 `shared/logs/supervisor_*`, `shared/pending/` status 字段; GiT/ 只读

---

## 正在进行的实验

### Full nuScenes 训练 (ORCH_024) — 核心任务

- **Config**: `plan_full_nuscenes_gelu.py`
- **架构**: 在线 DINOv3 frozen + Linear(4096,2048)→GELU→Linear(2048,768)
- **数据**: Full nuScenes (28130 train, 6019 val)
- **GPU**: 0+1+2+3 DDP, ~6.28-6.52 s/iter, ~28.8 GB/GPU (A6000 48GB)
- **max_iters**: 40000, warmup=2000, milestones=[15000,25000]
- **val_interval**: 2000, checkpoint_interval=2000
- **LR**: base=5.0e-05, lr=2.5e-06, lr_mult=2.0 for proj, gamma=0.1
- **load_from**: P5b@3000
- **当前进度**: iter **3070/40000** (7.7%), LR=2.5e-06 (warmup 已完成 @2000)
- **ETA**: ~3/11 15:50
- **训练日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/20260308_163535/20260308_163535.log`

### @2000 Val 结果 (DDP) — ✅ 已完成

| 指标 | @2000 DDP | Mini P6@500 | Mini P2@500 | 评价 |
|------|-----------|-------------|-------------|------|
| car_R | 0.627 | 0.231 | 0.202 | 早期过度预测 |
| **car_P** | **0.079** | 0.073 | 0.069 | ✅ 在预期 0.05-0.10 内 |
| truck_P | 0.000 | 0.019 | 0.004 | warmup 刚结束, 预期 |
| bus_P | 0.000 | 0.008 | 0.021 | warmup 刚结束, 预期 |
| ped_P | 0.001 | 0.021 | 0.018 | — |
| **bg_FA** | **0.222** | 0.173 | 0.256 | ✅ 合理 |
| **off_th** | **0.174** | 0.259 | 0.252 | ✅ **大幅改善 33%!** |

> **结论**: 在线 DINOv3 路径确认有效. car_P=0.079 在预期范围. off_th=0.174 远优于 mini, Full nuScenes 数据多样性效果初显.
> **注意**: DDP val 有 BUG-33 偏差 (±10%), 建议 @4000 后单 GPU re-eval.

---

## Mini 阶段总结 (ORCH_001-023 全部 COMPLETED)

### P6 FINAL (2048, 无 GELU, 预提取)
- **@6000 DDP FINAL**: car_P=**0.129**, bg_FA=0.274, off_th=0.200
- 超 P5b 基线 (0.116) +11%, 但需 3500+ iter 和 LR decay 才达到

### Plan P2 FINAL (2048+GELU, 预提取, 纯 BUG-39 修复)

| Ckpt | car_P | bg_FA | off_th | vs P6 同 iter |
|------|-------|-------|--------|-------------|
| @500 | 0.069 | 0.256 | 0.252 | P6=0.073 (-5.6%) |
| @1000 | **0.100** | 0.328 | 0.227 | **P6=0.058 (+72%!)** |
| @1500 | **0.112** | 0.279 | 0.251 | **P6=0.106 (+5.7%)** |
| @2000 | 0.096 | 0.295 | 0.208 | P6=0.110 (-12.8%, 回调) |

**结论**: GELU 在 @1000-1500 显著加速收敛, @2000 回调因无 LR decay.

### P5b 真实基线
- car_P=**0.116**, bg_FA=0.189, off_th=0.195

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
| **ORCH_024** | **IN PROGRESS** | Full nuScenes 训练 (3070/40000), @2000 val ✅ |

---

## GPU 状态 (Cycle #179)

| GPU | Used | Task |
|-----|------|------|
| 0 | 36.8 GB | **Full nuScenes** (3070/40000) |
| 1 | 36.8 GB | **Full nuScenes** |
| 2 | 37.3 GB | **Full nuScenes** |
| 3 | 36.8 GB | **Full nuScenes** |

磁盘: /mnt/SSD 336 GB 可用 (91%)

---

## 关键路径

| 用途 | 路径 |
|------|------|
| 调度仓库 | `/home/UNT/yz0370/projects/GiT_agent/` (读写) |
| 研究代码 | `/home/UNT/yz0370/projects/GiT/` (只读) |
| Full nuScenes log | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/20260308_163535/20260308_163535.log` |
| 报告输出 | `shared/logs/supervisor_report_latest.md` |
| 报告历史 | `shared/logs/supervisor_report_history.md` |
| 循环指令 | `shared/commands/supervisor_cmd.md` |

---

## 恢复指南
1. 读 `agents/claude_supervisor/CLAUDE.md` 确认角色
2. 读 `shared/commands/supervisor_cmd.md` 确认循环步骤
3. `git pull` 两仓库
4. 读 Full nuScenes 日志尾部: `tail -30 .../20260308_163535.log`
5. 搜 val 结果: `grep "753/753" .../20260308_163535.log`
6. 检查新 ORCH 指令 (`ls -lt shared/pending/`)
7. 深度监控: `nvidia-smi`, `df -h /mnt/SSD`, `pgrep -c -f train.py`
8. 写 supervisor_report_latest.md + 追加 history
9. git push
10. 继续循环
11. **关注**:
    - ~~**@2000 val** — ✅ 已完成, car_P=0.079, 在线 DINOv3 确认有效~~
    - **@4000 val ~3/9 02:30** — 第一个有意义的 post-warmup eval
    - **LR decay @17000 ~3/9 22:00** — milestone 15000 + begin 2000
    - **训练完成 @40000 ~3/11 15:50**
    - DDP val 注意 BUG-33: 建议 @4000 后单 GPU re-eval 确认真实值
