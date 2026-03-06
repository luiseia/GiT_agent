# Status — 16:14

- **Iter**: 360/8000 (~4.5%), ~3.0s/iter, ETA ~6h19m
- **Loss**: 波动 1.0–5.2, 最近 4.41 (cls=1.82, reg=2.60), 无NaN
- **LR**: base=5e-5, effective=2.5e-6 (backbone lr_mult=0.05)
- **GPU**: 0=97%(22.4GB), 2=98%(23GB) [Plan C]; 1,3=yl0826(31.2GB)
- **ML进程**: Plan C 运行中 (plan_c_bg_fix.py, PID 2875356)
- **研究员操作**:
  - 研究员已空闲（等待在 prompt），Plan C 作为后台进程运行
  - 首次验证 iter 500 预计 ~16:21 (约7分钟后)
  - Loss 波动较大但属正常范围（早期训练，从 iter_2000 checkpoint 继续）
  - grad_norm 偶有尖峰 (103, 93) 但未持续
- **指令通道**: NO_CHANGE / NO_PENDING
