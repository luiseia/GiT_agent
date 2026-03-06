# Conductor 上下文保存 (compact 前)
> 时间: 2026-03-06 16:55
> 循环: #11 刚完成, 下一轮 #12

## 当前正在做什么
- 执行 Conductor 自主循环 (每 30 分钟)
- 循环 #11 刚按**更新后的 CLAUDE.md** 执行完毕
- 新流程要求: 不直接读 GiT/, 通过 `shared/logs/supervisor_report_latest.md` 间接获取训练数据

## 关键流程变更 (循环 #11 起)
- **旧流程**: 直接读 GiT/ssd_workspace/ 下的训练日志
- **新流程**: 读 `shared/logs/supervisor_report_latest.md` (Supervisor 产出)
- **当前缺口**: Supervisor 尚未产出该报告 (正在过渡, context 5%)
- 完整循环步骤: PULL → CEO_CMD → REPORT → STATUS → VERDICT → PENDING → ADMIN → THINK → PLAN → ACT → CONTEXT → SYNC

## P2 训练进度
- **实验**: Plan E (BUG-9 fix), config `plan_e_bug9_fix.py`
- **唯一变量**: clip_grad max_norm 0.5 → 10.0
- **起点**: P1@6000 权重, 优化器状态重置
- **进度**: ~iter 2500/6000, ETA ~19:20
- **GPU**: 0,2 (RTX A6000)
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_e_bug9_fix/`
- **LR schedule**: base_lr=5e-05, milestone@3000 (即将 decay), @5000 (第二次)

## P2 指标完整趋势 (BUG-12 修正 eval)
| 指标 | P2@500 | P2@1000 | P2@1500 | P2@2000 | P1@6000 |
|------|--------|---------|---------|---------|---------|
| truck_R | 0.144 | 0.346 | 0.303 | 0.315 | 0.358 |
| truck_P | 0.178 | 0.189 | 0.121 | 0.148 | 0.176 |
| bus_R | 0.631 | 0.634 | 0.708 | 0.654 | 0.627 |
| bus_P | 0.152 | 0.204 | 0.142 | 0.225 | 0.156 |
| car_R | 0.655 | 0.592 | 0.597 | 0.603 | 0.628 |
| car_P | 0.068 | 0.086 | 0.063 | 0.083 | 0.091 |
| trailer_R | 0.800 | 0.667 | 0.911 | 0.600 | 0.644 |
| bg_FA | 0.239 | 0.182 | 0.274 | 0.191 | 0.163 |
| offset_cx | 0.064 | 0.059 | 0.101 | 0.069 | 0.081 |
| offset_cy | 0.159 | 0.088 | 0.112 | 0.106 | 0.139 |
| offset_th | 0.213 | 0.262 | 0.232 | 0.227 | 0.220 |

## P1 最终指标 (BUG-12 修正 eval, ORCH_003 确认)
- truck_R=0.358, truck_P=0.176, bus_R=0.627, bus_P=0.156
- car_R=0.628, car_P=0.091, bg_FA=0.163, offset_th=0.220
- Checkpoint: `/mnt/SSD/GiT_Yihao/Train/Train_20260305/plan_d_center_around/iter_6000.pth`

## 红线
| 指标 | 红线 | P2@2000 | 状态 |
|------|------|---------|------|
| truck_R | < 0.08 | 0.315 | SAFE |
| bg_FA | > 0.25 | 0.191 | SAFE |
| offset_th | <= 0.20 | 0.227 | WARN |

## 振荡模式
- P2 指标呈奇偶交替振荡 (高→低→高→低)
- 原因: 323 张图 / batch_size=2, 数据采样周期性
- 预期: LR decay @3000 后振荡收敛

## 已完成的 ORCH 指令
| ID | 目标 | 报告 |
|----|------|------|
| 001 | BUG-12 修复 (eval slot 排序) | report_ORCH_001.md: truck +72%, bus +28% |
| 002 | BUG-9 诊断 (梯度裁剪) | report_ORCH_002.md: 推荐 max_norm=10.0 |
| 003 | P1 eval + P2 启动 | report_ORCH_003.md: 三任务完成 |

## BUG-9 修复效果
- 裁剪率: P1=100% → P2=42-49% 未裁剪
- AdamW 自适应行为已恢复
- 训练效率质变: P2@1000 ≈ P1@6000

## 关键历史洞察 (CEO 指令 #1/#3 提取)
1. BUG-9: 100% 梯度裁剪 → Sign-SGD (已修复)
2. BUG-8: cls loss 未应用 bg_balance_weight (git_occ_head.py:871-881), UNPATCHED
3. AABB 过估: truck 45° 旋转覆盖 3.5× cell
4. 梯度三重挤压: truck 仅占总梯度 2.1%, bg 14.3% (7×差异)
5. 自回归误差级联: slot 2 比 slot 0 低 ~19%
6. IBW 大物体歧视: truck 每 cell 权重仅 car 的 1/2~1/3
7. 理论上界: car_P>=0.30, truck_R>=0.70 需架构改动
8. BUG-10: optimizer cold start, Adam 偏差校正前 100 步振荡 100×
9. Construction Vehicle 在 nuScenes-mini 中已独立于 truck
10. Sign-SGD 是双刃剑: 阻止 LR schedule 但意外保护少数类

## CEO 指令归档
- #1 (03-06 01:15): 读历史审计报告 → 提取 5 项洞察
- #2 (03-06 01:15): 转达 Ops 修 watchdog
- #3 (03-06 15:20): 深度重读历史审计 → 提取 5 项新洞察

## 待办 / 下一步
1. **循环 #12**: 读 `supervisor_report_latest.md` 获取 P2@2500+ 数据
2. **P2@3000**: LR decay 生效, 关键节点
3. 如 Supervisor 仍未产出报告: 向 CEO 报告
4. P2 收敛后 (iter 5000-6000): 最终评估, 决定是否需要 P3 (BUG-8 修复)

## 系统状态
- 全部 Agent UP (conductor, critic, supervisor, admin, ops)
- 基础设施: sync_loop + watchdog 运行正常
- GPU 1,3 被 yl0826 占用 (PETR 训练)
