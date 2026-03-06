# Status — 18:03 [Plan D ACTIVE]

- **Iter**: 60/8000 (0.75%), ~3.0s/iter, ETA ~6h34m
- **Loss**: 0.66–2.40, 最近 0.660 (cls=0.355, reg=0.306)
- **GPU**: 0=100%(21.5GB), 2=100%(22GB) [Plan D]; 1,3=yl0826(31.2GB)
- **ML进程**: Plan D 训练中 (plan_d_reg_rebalance.py, PID 2973822)

## Plan D 启动确认
- 从 Plan C iter_1000.pth checkpoint 恢复
- reg_loss_weight = **1.0** (Plan C 为 2.0)
- cls/reg 比例 ~1:1 (Plan C ~1:2) — **梯度平衡显著改善**
- bg_balance_weight=3.0 保持
- per_class_balance 保持
- 工作目录: `GiT/ssd_workspace/Train/Train_20260305/plan_d_reg_rebalance/`

## Loss 趋势 (前60 iter)
| iter | loss | cls | reg | 备注 |
|------|------|-----|-----|------|
| 10 | 2.046 | 1.049 | 0.997 | 初始 |
| 30 | 1.887 | 0.848 | 1.040 | |
| 50 | 2.397 | 1.210 | 1.186 | |
| 60 | 0.660 | 0.355 | 0.306 | cls/reg 均衡 |

## 研究员状态
- 空闲在 prompt, Plan D 已自动启动
- 等待指挥家后续指令

## Context 系统脉搏
- Supervisor: 运行正常, 三循环活跃
- Researcher #1: 空闲, Plan D 训练后台运行

## 指令通道
- CEO: NO_CHANGE
- ORCH: NO_PENDING

## 下次验证
- iter 500 预计 ~18:22 (约 22 分钟内)
