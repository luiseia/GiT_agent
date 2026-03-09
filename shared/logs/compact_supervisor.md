# Supervisor Compact Context Snapshot
> Timestamp: 2026-03-09 15:58
> Supervisor cycles: #89 — #214 (本轮 session 覆盖 #199-#214)
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
- **当前进度**: iter **9960/40000** (24.9%), LR=2.5e-06, **@10000 val 即将触发!**
- **ETA**: ~3/12 02:30
- **训练日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/20260308_163535/20260308_163535.log`

### Val 结果汇总 (DDP) — 含 @8000 新数据

| 指标 | @2000 | @4000 | @6000 | @8000 | 趋势 |
|------|-------|-------|-------|-------|------|
| **car_P** | 0.079 | 0.078 | **0.090** | **0.060** | ⚠️ @8000 回落 (P/R tradeoff) |
| **car_R** | 0.627 | 0.419 | 0.455 | **0.718** | ✅ @8000 历史最高 |
| truck_R | 0.000 | 0.059 | 0.138 | 0.000 | ⚠️ 类间振荡 |
| bus_R | 0.000 | 0.000 | 0.287 | 0.002 | ⚠️ @6000 爆发→@8000 崩塌 |
| ped_R | 0.067 | 0.026 | 0.145 | **0.276** | ✅ 持续增长 |
| ped_P | 0.001 | 0.001 | 0.024 | 0.016 | 振荡 |
| cone_R | 0.000 | 0.000 | 0.160 | 0.000 | 振荡 |
| **bg_FA** | 0.222 | **0.199** | **0.331** | **0.311** | ✅ @8000 开始回落! |
| **off_th** | 0.174 | **0.150** | 0.169 | **0.140** | ✅✅ @8000 历史最低! |
| off_cx | 0.056 | 0.039 | 0.056 | **0.045** | ✅ 改善 |

> **@8000 结论**: 类间注意力振荡 — @6000 多类模式 (car+truck+bus+ped+cone) → @8000 双类模式 (car+ped). car_P 回落但 car_R 大增 (P/R tradeoff). **结构指标持续改善** (bg_FA↓, off_th 历史最低). 常数 LR 下振荡幅度大, 预期 LR decay @17000 后收窄.
> **注意**: DDP val 有 BUG-33 偏差 (±10%), 可能放大振荡. 建议 @10000 后做单 GPU re-eval.

### GPU 1 被占事件 (已解决, 历史记录)

- iter ~4840 — ~6000, 外部 PID 908307, ~5h, 累计损失 ~2-3h
- ETA 已完全恢复正常

---

## Mini 阶段总结 (ORCH_001-023 全部 COMPLETED)

### P5b 真实基线: car_P=**0.116**, bg_FA=0.189, off_th=0.195
### P6 FINAL (2048, 无 GELU): car_P=**0.129** @6000 DDP, 超 P5b +11%
### Plan P2 FINAL (2048+GELU): car_P=**0.112** @1500, GELU 加速收敛

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
| **Plan Q** | 预提取 | 2048 | ✅ | 0.083 | **类竞争无关** (ORCH_026) |

### 重大 BUG 记录
- **BUG-33**: DDP val 缺 sampler → GT+P 偏差. 修复: 加 DefaultSampler
- **BUG-39**: P6 无 GELU → 两层 Linear 退化为单层. 修复: Plan P2 加 GELU
- **BUG-40**: Plan O warmup=max_iters → LR 从未达标. 结果无效

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-023 | COMPLETED | Mini 阶段全部完成 |
| **ORCH_024** | **IN PROGRESS** | Full nuScenes (9960/40000), @2000/@4000/@6000/@8000 val ✅ |
| ORCH_025 | COMPLETED | 自动化测试框架 (pytest) |
| ORCH_026 | COMPLETED | Plan Q 单类诊断: car_P=0.083, 类竞争无关 |

---

## GPU 状态 (Cycle #214)

| GPU | Used | Task |
|-----|------|------|
| 0 | 36.8 GB | **Full nuScenes** (9960/40000) |
| 1 | 36.8 GB | **Full nuScenes** |
| 2 | 37.3 GB | **Full nuScenes** |
| 3 | 36.8 GB | **Full nuScenes** |

磁盘: /mnt/SSD 282 GB 可用 (93%) — checkpoint @2000/@4000/@6000/@8000 已保存

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
    - ~~**@2000 val** — ✅ car_P=0.079, 在线 DINOv3 确认有效~~
    - ~~**@4000 val** — ✅ car_P=0.078 停滞, truck_P=0.057 新类出现~~
    - ~~**@6000 val** — ✅ car_P=0.090 突破! 多类爆发! bg_FA=0.331 恶化~~
    - ~~**@8000 val** — ✅ car_P=0.060 (P/R tradeoff), bg_FA=0.311 回落, off_th=0.140 最低~~
    - **@10000 val ~3/9 16:01** — 即将触发! 类间振荡方向? 多类是否恢复?
    - **LR decay @17000 ~3/10 10:00** — milestone 15000 + begin 2000, gamma=0.1
    - **训练完成 @40000 ~3/12 03:00**
    - DDP val 注意 BUG-33: 建议 @10000 后做单 GPU re-eval 确认真实值
    - **关键发现**: @8000 显示类间注意力振荡, 但结构指标 (bg_FA, offset) 持续改善
