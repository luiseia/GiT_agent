# Supervisor Compact Context Snapshot
> Timestamp: 2026-03-13 05:28
> Supervisor cycles: #290 — #299 (本轮 session)
> Role: claude_supervisor — 信息中枢
> Reason: 上下文接续保存

---

## 当前任务

**角色**: claude_supervisor, 按 `shared/commands/supervisor_cmd.md` 严格执行监控循环
**循环**: git stash+pull+pop → 读训练日志 → 写 supervisor_report_latest.md → 检查 ORCH (grep PENDING) → 深度监控 (GPU + df -h + 进程存活) → git push
**写入边界**: 只可写 `shared/logs/supervisor_*`, `shared/pending/` status 字段; GiT/ 只读

---

## 正在进行的实验

### ORCH_035 — Label Pipeline 大修后训练 (当前在跑)

- **Config**: `plan_full_nuscenes_multilayer.py` (multilayer_v4)
- **架构**: DINOv3 7B frozen + proj_hidden_dim=4096 + multilayer feature
- **数据**: Full nuScenes (28130 train, 6019 val)
- **GPU**: 0+1+2+3 DDP, ~6.27-6.61 s/iter, ~37.8 GB/GPU
- **max_iters**: 40000, val_interval=2000, checkpoint_interval=2000
- **LR**: base=5e-05, effective=2.5e-06 (post-warmup), lr_mult=5.0 for proj
- **clip_grad**: max_norm=30.0
- **load_from**: ORCH_034 iter_4000.pth (resume=True, 从 iter 4001 开始)
- **Label Pipeline 改动 (5 项)**:
  1. BUG-19v3 z-convention fix (box BOTTOM vs center)
  2. Convex hull 替代 AABB (use_rotated_polygon=True)
  3. Sutherland-Hodgman hull-based IoF/IoB
  4. filter_invisible=False
  5. vis+cell_count 组合过滤 (vis<10% AND cells<6)
- **当前进度**: iter **9450/40000** (23.6%)
- **ETA**: ~2d 6h (~03/15 11:30)
- **训练日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/20260312_175353/20260312_175353.log`
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`

### Conductor 决策: PROCEED → @12000

- **@8000 Critic VERDICT**: PROCEED, 继续到 @12000
- **@10000 ETA**: ~06:25 (03/13) — val + checkpoint
- **@12000 ETA**: ~09:55 (03/13) — **下一架构决策点**

---

## Val 结果汇总

### ORCH_029 @2000 (warm start 基线)
- car_R=0.3737, bg_FA=0.1615, off_th=0.1447

### ORCH_034 @2000
- car_R=0.8124 ✅, bg_FA=0.2073 ✅, off_th=0.1655 ✅, 其余类=0

### ORCH_034 @4000 (Rule #6 首个可靠 checkpoint)
- car_R=0.8195 ✅, bg_FA=0.3240 🔴红线, off_th=0.1598 ✅
- 4 新类激活: bus=0.070, cv=0.110, ped=0.024, cone=0.130

### ORCH_035 @6000 (新标签首次 val) ⭐
- car_R=**0.2329** 🔴(-71.6%), bg_FA=**0.0938** ✅✅(-71.1%), off_th=**0.2848** 🔴红线
- cv=0.2581 ✅(+136%), car_P=0.0822 (+82%)
- 解读: 新标签大幅减少 FA 但也砍了 recall, 仅 2000 iter 适应

### ORCH_035 @8000 (Rule #6 架构决策) ⭐⭐⭐
- car_R=**0.6012** ✅✅(+158%), car_P=0.0822, bg_FA=**0.2568** 🔴红线(+174%)
- off_th=**0.2083** 🔴红线(-27%), off_cy=**0.1591** 🔴(+99%)
- ped_R=**0.2002** ✅(新激活!), bus_R=0.0886(+430%), truck_R=0.0243(+220%)
- cv_R=**0.0000** 🔴(坍缩, 从0.258→0)
- **解读**: car recall 强劲恢复, 新类激活, 但 bg_FA 和 off_th 触红线
- **Conductor 决策**: PROCEED to @12000

---

## 训练趋势摘要 (ORCH_035)

| 窗口 | loss 均值 | reg=0 | spike>8 | 备注 |
|------|----------|-------|---------|------|
| 4010-4210 | ~5.0 | 0 | 0 | 新标签初期 |
| 4250-4480 | ~5.2 | 1x | 0 | |
| 4500-4750 | ~4.3 | 3x cluster | 0 | |
| 4800-5020 | ~4.4 | 2x | 0 | |
| 5050-5300 | ~4.3 | 2x | 1(8.74) | |
| 5310-5570 | ~4.2 | 1x | 0 | |
| 5580-5840 | ~3.8 | **6x dense!** | 0 | @5700-5760 最密集 |
| 6010-6440 | ~4.6 | 0 | 1(9.87) | post-@6000 val |
| 6450-6720 | ~4.5 | 1x | 0 | |
| 6730-6990 | ~4.3 | 2x pair | 0 | |
| 7000-7270 | ~4.4 | 1x | 0 | |
| 7280-7540 | ~4.3 | 1x(@7520) | 0 | |
| 7550-7810 | ~4.5 | 1x(@7660) | 0 | |
| 7820-8000 | ~4.1 | **4x cluster** | 0 | @7870-7990 密集, @8000 恢复 |
| 8010-8350 | ~4.3 | 1x(@8030) | 0 | post-@8000 val |
| 8360-8620 | ~4.4 | 0 | 0 | 全清 |
| 8630-8900 | ~4.1 | 0 | 0 | 全清 |
| 8910-9170 | ~3.9 | 0 | 0 | 全清, 持续降 |
| 9180-9450 | ~3.9 | 0 | 0 | 全清 x4 |

**总体趋势**: loss 从 ~5.0 持续降至 ~3.9, 连续 4 窗口零 reg=0 零 spike

---

## reg=0 现象
- DDP deterministic data ordering artifact
- 密集区: @5700-5760 (6x), @7870-7990 (4x), @4620-4630 (3x)
- 散发: @6860-6870, @7270, @7520, @7660, @8030
- 均立即恢复, 不影响训练

## 红线指标 (CEO 已更新: 不再高度预警)
- bg_false_alarm > 0.25
- avg_offset_theta > 0.20

## Rule #6 (关键规则)
- @2000: 太早, 不可靠
- @4000: 首个可靠 checkpoint
- @8000: 架构决策级 ← **已完成, PROCEED**
- **@12000: 下一决策点** ← 即将到来

---

## CEO_CMD 处理记录 (本轮)

- **Cycle #299**: CEO 要求报告说明 @8000 后未执行 score_thr 消融和 Phase 2
  - 报告已写: `shared/logs/reports/post_8000_plan_deviation_report.md`
  - 原因: Conductor PROCEED 决策将消融推迟到 @12000
  - ViT-L 参数量验证: ~303M, "300M" 近似合理

---

## ORCH 指令状态

| 指令 | 状态 | 说明 |
|------|------|------|
| ORCH_029 | COMPLETED | 基线, @2000 warm start 来源 |
| ORCH_032 | COMPLETED | 全面坍缩 (BUG-57/58/59/60) |
| ORCH_033 | COMPLETED | 修复 BUG-57-60, multilayer_v2 |
| ORCH_034 | COMPLETED | BUG-52 IoF/IoB fix, multilayer_v3, 停@4000 |
| **ORCH_035** | **IN_PROGRESS** | Label Pipeline 大修, multilayer_v4, @9450 |

---

## GPU 状态 (Cycle #299)

| GPU | Used | Utilization |
|-----|------|-------------|
| 0 | 37.8 GB | 100% |
| 1 | 37.8 GB | 100% |
| 2 | 38.0 GB | 100% |
| 3 | 37.8 GB | 100% |

磁盘:
- /mnt/SSD: 96% (163GB free) — @8000 checkpoint 已写 (~15GB)
- /home: 99% (68GB free) ⚠️

---

## 关键路径

| 用途 | 路径 |
|------|------|
| 调度仓库 | `/home/UNT/yz0370/projects/GiT_agent/` (读写) |
| 研究代码 | `/home/UNT/yz0370/projects/GiT/` (只读) |
| ORCH_035 log | `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/20260312_175353/20260312_175353.log` |
| 报告输出 | `shared/logs/supervisor_report_latest.md` |
| 报告历史 | `shared/logs/supervisor_report_history.md` |
| 循环指令 | `shared/commands/supervisor_cmd.md` |
| MASTER_PLAN | `/home/UNT/yz0370/projects/GiT_agent/MASTER_PLAN.md` |

---

## 恢复指南

1. 读 `shared/commands/supervisor_cmd.md` 确认循环步骤
2. `git stash && git pull --rebase && git stash pop` (后台 cron 改日志)
3. 读 ORCH_035 日志尾部: `tail -30 .../20260312_175353.log`
4. 搜 val 结果: `grep "753/753" .../20260312_175353.log`
5. 检查新 ORCH: `grep -l "PENDING" shared/pending/*.md`
6. 检查 CEO_CMD: `cat CEO_CMD.md`
7. 深度监控: `nvidia-smi`, `df -h /mnt/SSD /home`, `ps aux | grep plan_full`
8. 写 report + 追加 history + supervisor.log
9. git add/commit/push
10. 继续循环, 下一 cycle #300

**关注重点**:
- **@10000 val (~06:25)** — 中间 checkpoint, 非决策级
- **@12000 val (~09:55)** — Conductor 下一决策点!
  - @12000 决策树: car_R 0.65-0.75 + car_P ≥ 0.06 + bg_FA < 0.40 → 继续
  - 附加测试: score_thr 消融 0.1/0.2/0.3/0.5 (CEO 要求!)
- /home 磁盘 99% — 持续关注
- /mnt/SSD 163GB — @10000 checkpoint 会再消耗 ~15GB
- CEO 关注: score_thr 消融何时执行? Phase 2 何时启动?
