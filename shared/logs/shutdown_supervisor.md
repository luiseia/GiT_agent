# Supervisor 紧急关机状态快照
> 时间: 2026-03-09 ~21:35
> 最后 Cycle: #229 (实际有效数据 Cycle #227)
> 角色: claude_supervisor — 信息中枢
> 原因: 用户请求紧急关机

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
- **当前进度**: iter **~12100/40000** (30.3%), 日志缓冲延迟, 实际可能已到 ~12200+
- **ETA**: ~3/12 02:59
- **训练日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/20260308_163535/20260308_163535.log`

### Val 结果汇总 (DDP) — 含 @12000 最新数据

| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | @12000 | 趋势 |
|------|-------|-------|-------|-------|--------|--------|------|
| **car_P** | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | **0.081** | ✅ 恢复中 |
| **car_R** | 0.627 | 0.419 | 0.455 | 0.718 | **0.726** | 0.526 | 振荡 |
| truck_R | 0.000 | 0.059 | 0.138 | 0.000 | **0.239** | 0.000 | on/off |
| bus_R | 0.000 | 0.000 | **0.287** | 0.002 | 0.112 | **0.222** | 持续存在 |
| CV_R | 0.000 | 0.000 | 0.000 | 0.000 | **0.287** | 0.000 | 单次出现 |
| ped_R | 0.067 | 0.026 | 0.145 | **0.276** | 0.000 | 0.000 | ⚠️ 连续 2 次消失 |
| moto_R | 0.000 | 0.000 | 0.000 | 0.000 | **0.126** | 0.000 | 单次出现 |
| barrier_R | 0.003 | 0.000 | 0.000 | 0.000 | 0.025 | 0.000 | 微弱 |
| **bg_FA** | 0.222 | **0.199** | 0.331 | 0.311 | 0.407 | **0.278** | ✅ @12000 大幅恢复 |
| **off_th** | 0.174 | 0.150 | 0.169 | 0.140 | 0.160 | **0.128** | ✅✅✅ 历史最佳! |
| **off_cx** | 0.056 | **0.039** | 0.056 | 0.045 | 0.072 | **0.038** | ✅✅ 历史最佳! |

### 类间振荡 — 4 种模式已识别

| Val | 模式 | 活跃类 | bg_FA | off_th |
|-----|------|--------|-------|--------|
| @6000 | 广泛模式 | car+truck+bus+ped+cone (5) | 0.331 | 0.169 |
| @8000 | 窄模式 | car+ped (2) | 0.311 | 0.140 |
| @10000 | 车辆模式 | car+truck+bus+CV+moto+barrier (6) | 0.407 | 0.160 |
| @12000 | 精准双类 | car+bus (2) | 0.278 | **0.128** |

**关键洞察**: 活跃类数量 vs 结构指标反相关; 底层空间表征持续改善 (off_th 从未停止进步); LR decay @17000 是多类同时收敛的关键

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-023 | COMPLETED | Mini 阶段全部完成 |
| **ORCH_024** | **IN PROGRESS** | Full nuScenes (~12100/40000), @2000-@12000 val 全部捕获 |
| ORCH_025 | COMPLETED | 自动化测试框架 (pytest) |
| ORCH_026 | COMPLETED | Plan Q 单类诊断: car_P=0.083 < 0.12 → 类竞争无关 |

---

## GPU 状态 (最后检查)

| GPU | Used | Task |
|-----|------|------|
| 0 | 36.5 GB | **Full nuScenes** |
| 1 | 36.4 GB | **Full nuScenes** |
| 2 | 37.0 GB | **Full nuScenes** |
| 3 | 36.5 GB | **Full nuScenes** |

磁盘: /mnt/SSD 253 GB 可用 (93%) — checkpoint @2000-@12000 已保存

---

## Mini 阶段总结 (历史参考)

### P5b 真实基线: car_P=**0.116**, bg_FA=0.189, off_th=0.195
### P6 FINAL (2048, 无 GELU): car_P=**0.129** @6000 DDP
### Plan P2 FINAL (2048+GELU): car_P=**0.112** @1500

### 重大 BUG 记录
- **BUG-33**: DDP val 缺 sampler → GT+P 偏差 (±10%). 修复: 加 DefaultSampler
- **BUG-39**: P6 无 GELU → 两层 Linear 退化为单层
- **BUG-40**: Plan O warmup=max_iters → LR 从未达标

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
3. 读本文件 `shared/logs/shutdown_supervisor.md` 恢复上下文
4. `git pull` 两仓库
5. 读 Full nuScenes 日志尾部: `tail -30 .../20260308_163535.log`
6. 搜 val 结果: `grep "753/753" .../20260308_163535.log`
7. 检查新 ORCH 指令 (`ls -lt shared/pending/`)
8. 深度监控: `nvidia-smi`, `df -h /mnt/SSD`, `pgrep -c -f train.py`
9. 写 supervisor_report_latest.md + 追加 history
10. git push
11. 继续循环

### 关注事项
- ~~@2000 val~~ ✅ | ~~@4000 val~~ ✅ | ~~@6000 val~~ ✅ | ~~@8000 val~~ ✅ | ~~@10000 val~~ ✅ | ~~@12000 val~~ ✅
- **@14000 val ~3/10 00:50** — 下一个 val 点
- **LR decay @17000 ~3/10 10:00** — milestone 15000 + begin 2000, gamma=0.1 → **关键节点!**
- **@18000 val ~3/10 14:00** — LR decay 后首次 val, 观察类振荡是否收窄
- **训练完成 @40000 ~3/12 03:00**
- DDP val 有 BUG-33 偏差 (±10%), 建议后期做单 GPU re-eval
- **核心发现**: 底层表征持续改善 (off_th 趋势向好), 类注意力振荡是分类头在常数 LR 下的不稳定, 非架构缺陷

### 本轮 session 覆盖 Cycle #215-#229
