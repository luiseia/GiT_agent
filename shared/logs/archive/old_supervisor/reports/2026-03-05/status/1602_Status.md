# Status — 16:02

- **Iter**: Plan C 已启动，从 iter_2000.pth 开始，目标 8000 iter
- **Loss**: 尚无数据（训练刚启动 ~7min）
- **GPU**: 0=100%(21.5GB), 2=100%(22GB), 1,3=yl0826(31GB)
- **ML进程**: 3 主进程 + worker（plan_c_bg_fix.py, PID 2875356）
- **研究员操作**:
  - P0/P1/P3 修复已完成
  - P4 Plan C 已启动 @15:55
  - Config: plan_c_bg_fix.py, LR=5e-5, milestones=[4000,6000], max_iters=8000, val@500
  - Work dir: ssd_workspace/Train/Train_20260305/plan_c_bg_fix
  - 首次验证预计 ~16:20
