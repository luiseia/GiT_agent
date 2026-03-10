# Admin Agent 紧急关机状态保存

**时间**: 2026-03-09 23:38
**原因**: 用户发出紧急关机指令

---

## 活跃任务

### ORCH_028: Full nuScenes Overlap Retraining — IN PROGRESS

| 项目 | 状态 |
|------|------|
| Task 1 | ✅ ORCH_024 已终止, @12000 checkpoint 保留 |
| Task 2 | ✅ overlap config 验证通过 |
| Task 3 | ✅ 训练已启动, 4 GPU DDP |
| Task 4 | ⏳ 早期监控中 (@100 ✅, @500 ✅, @2000 val 待做) |
| Task 5 | ❌ 未开始 (后续检查点) |
| Task 6 | ❌ 未开始 (最终报告) |

#### 训练进程状态
- **PID**: 1220551 (主进程), 共 22 个相关进程在运行
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260309/full_nuscenes_overlap`
- **Config**: `configs/GiT/plan_full_nuscenes_gelu.py`
- **当前 iter**: 1160/40000
- **显存**: 28849 MB/GPU (稳定)
- **速度**: ~6.2-6.5 s/iter
- **ETA**: ~2 days 20 hours (预计 3/12 ~20:00 完成)
- **训练仍在后台运行** — 进程未终止，会继续训练

#### reg=0 累计统计
- @100: 0/10 = 0.0%
- @500: 2/51 = 3.9%
- @1160 (当前): 9/116 = 7.8% — 注意略升高，但仍远低于 ORCH_024 的 28.6%

#### 已完成的检查点
1. **@100 iter**: reg=0=0.0%, 通过 ✅
2. **@500 iter**: reg=0=3.9%, 通过 ✅ (< 5% 阈值)

#### 下一步操作 (恢复后)
1. **@2000 val** (预计 ~01:10 3/10): 提取首次 eval 结果
   - 对比基线: ORCH_024 @2000 — car_P=0.079, bg_FA=0.222
   - 异常阈值: car_P < 0.03 → 报告异常但不终止
2. 更新 report_ORCH_028.md
3. 继续监控 @4000, @6000 等后续 val

---

## 已完成任务 (本 session)

| ORCH | 状态 | 摘要 |
|------|------|------|
| ORCH_024 | TERMINATED @12000 | 已由 ORCH_028 终止 |
| ORCH_026 | COMPLETED | Plan Q 单类 Car 诊断, car_P@best=0.083 → 类竞争无关 |
| ORCH_027 | COMPLETED | 10 样本 nuScenes 可视化 + polygon_viz 迁移 |

---

## 关键文件位置

- ORCH_028 pending: `shared/pending/ORCH_0309_2145_028.md`
- ORCH_028 report: `shared/logs/report_ORCH_028.md`
- ORCH_028 work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260309/full_nuscenes_overlap`
- ORCH_028 launch log: 同 work dir 下 `launch.log`
- ORCH_024 work dir (保留对照): `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu`

---

## 注意事项

1. **训练进程仍在运行** — 不需要重新启动，恢复后直接读 launch.log 检查进度即可
2. reg=0 从 3.9% 升至 7.8%，需在 @2000 后重新评估是否仍在可接受范围
3. 无未处理的 DELIVERED ORCH 指令

---

*Admin Agent 关机保存 | 2026-03-09 23:38*
