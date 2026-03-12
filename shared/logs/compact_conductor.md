# Conductor 上下文快照
> 时间: 2026-03-12 00:30

## 当前状态
- **ORCH_032** 多层特征训练 IN_PROGRESS @470, 4×A6000, ETA ~03/14 22:00
- Config: `plan_full_nuscenes_multilayer.py`, layers [9,19,29,39], load_from=None, overlap+vis
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer`
- ORCH_029 已停止 @2000, ckpt 保留
- ORCH_024 已终止 @12000 (baseline)

## ORCH_029 @2000 eval 结果 (关键基准)
| 指标 | ORCH_024 @2000 | ORCH_029 @2000 | 变化 |
|------|---------------|---------------|------|
| car_P | 0.079 | 0.0514 | -35% |
| bg_FA | 0.222 | 0.1615 | -27% ✅ |
| off_th | 0.174 | 0.1447 | -17% ✅ |
| reg=0 | 28.6% | 9.0% | -68% ✅ |

结论: overlap+vis 标签降噪有效, car_P 下降可能是早期或特征瓶颈

## 下一里程碑
- ORCH_032 @2000 eval: ~03/12 11:30
- ORCH_032 @4000 eval: ~03/13 01:00 (第一可信评估点)

## 待决策
- @2000: 三方对比 (032 vs 029 vs 024), 趋势参考
- @4000: 决策树判断 (见 MASTER_PLAN)

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整路线图和决策树
3. 检查 CEO_CMD.md
4. 继续 Phase 1/Phase 2 循环
