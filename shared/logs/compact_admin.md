# Admin Agent 上下文快照
- **时间**: 2026-03-16 07:11
- **当前任务**: ORCH_056 执行中 — 实验 B 训练运行中 (lr=1e-5, resume from 055 iter_100)

---

## 当前训练状态

### ORCH_056 实验 B (当前运行)
- **Config**: bg=5.0, marker_pos_punish=1.0, **lr=1e-5** (原 5e-5 的 1/5)
- **Resume from**: ORCH_055 iter_100.pth
- **训练**: 2-GPU DDP (GPU 2,3), memory=28884, master_port=29510
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch056`
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/nohup_orch056.out`
- **GiT commit**: `6bb2089`
- **启动时间**: 07:09 CDT, 从 iter 100 resume
- **Auto-check**: @200/@300/@400/@500, 只 sat>0.95 早停

### ORCH_056 实验 A (待完成)
- iter_100 full eval 被暂停（太慢 ~3.7h），训练完成后重启
- 部分日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/eval_055_iter100.log`

### GPU 共享状况
- **GPU 0,1**: xg0091 StreamPETR (~40/39 GB)
- **GPU 2,3**: 我们的 ORCH_056 训练 (~34/41 GB)
- **GPU 3**: + yl0826 PETR (~14 GB)

---

## ORCH_055 关键成果 (本 session 最重要发现)

**5 点崩塌轨迹 (bg=5.0, lr=5e-5, 2-GPU DDP):**

| iter | Pos slots | IoU | marker_same | sat | TP |
|------|-----------|-----|-------------|-----|-----|
| 100 | 750 (63%) | 0.853 | 0.887 | 0.703 | 109 |
| 200 | 954 (80%) | 0.954 | 0.963 | 0.820 | 147 |
| 300 | 1010 (84%) | 0.968 | 0.973 | 0.873 | 150 |
| **400** | **71 (6%)** | 0.780 | 0.984 | **0.080** | **0** |
| 500 | 158 (13%) | 0.910 | 0.988 | 0.142 | 12 |

- **崩塌点**: iter 300-400 之间 (突然相变)
- **BUG-78 确认**: 单 GPU vs 2-GPU DDP 结果完全不同
- marker_same 全程单调上升，是模板化的核心指标

---

## 本 Session 完整执行记录

### ORCH_049-051 (前 session, 上下文恢复)
- 049: bg=5.0 → @200 TP=112, @500 全背景
- 050: bg=3.0+dropout → @200 全背景
- 051: bg=3.0 → @200 全正

### ORCH_052 (FAIL, EARLY STOP @200)
- bg=3.0, punish=1.0 → @200 全背景 (TP=0)
- GiT commit: `07659cb`

### ORCH_053 (FAIL, EARLY STOP @200)
- bg=4.0, punish=1.0 → @200 全背景 (TP=0)
- 磁盘满修复: 清理 049-052 checkpoint 释放 67 GB
- GiT commit: `7961447`

### ORCH_054 (INVALIDATED — BUG-78 单 GPU)
- bg=5.0, 单 GPU → @100/@200 都全背景
- 结果无效, GiT commit: `fa06de2`

### ORCH_055 (COMPLETED — PASS, 5 点轨迹)
- bg=5.0, 2-GPU DDP → 完整崩塌轨迹 (见上表)
- GiT commit: `cb74b15`

### ORCH_056 (执行中)
- 实验 A: full eval (暂停)
- 实验 B: lr=1e-5 resume, 训练中
- GiT commit: `6bb2089`

---

## Frozen Check 完整历史

| ORCH | Iter | sat | TP | 状态 |
|------|------|-----|-----|------|
| 055 | @100 | 0.703 | 109 | 中间态 (唯一健康点) |
| 055 | @200 | 0.820 | 147 | 正向漂移 |
| 055 | @300 | 0.873 | 150 | 接近饱和 |
| 055 | @400 | 0.080 | 0 | 急剧坍塌 |
| 055 | @500 | 0.142 | 12 | 微弱恢复 |
| 056 | @200-500 | ? | ? | 等待 (lr=1e-5) |

---

*Admin Agent 上下文快照 | 2026-03-16 07:11*
