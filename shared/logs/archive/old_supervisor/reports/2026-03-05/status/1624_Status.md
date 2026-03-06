# Status — 16:24

- **Iter**: 500/8000 (6.25%), checkpoint saved, validation completed
- **Loss**: 波动 1.0–5.2, iter 500 loss=1.19 (cls=0.32, reg=0.87)
- **GPU**: 0=99%(22.4GB), 2=100%(23GB) [Plan C]; 1,3=yl0826(31.2GB)
- **ML进程**: Plan C validation 刚完成 (plan_c_bg_fix.py, PID 2875356)
- **首次验证结果 (iter 500)**:
  | 指标 | Plan C @500 | Plan B @500 参考 |
  |------|------------|-----------------|
  | car_recall | 0.6451 | ~0.65 |
  | truck_recall | 0.1763 | ~0.35 |
  | bus_recall | 0.3224 | ~0.40 |
  | trailer_recall | 0.9778 | ~0.85 |
  | car_precision | 0.1425 | N/A(score坏) |
  | truck_precision | 0.0578 | N/A |
  | bus_precision | 0.1126 | N/A |
  | trailer_precision | 0.0126 | N/A |
  | **bg_false_alarm_rate** | **0.1558** | **0.194** |
  | bg_recall | 0.8442 | ~0.80 |
- **关键发现**:
  - bg_false_alarm_rate=0.1558 显著优于 Plan B (0.194→0.317)，P0 BG梯度修复生效
  - Precision 值首次可用（Plan B 的 score 从未工作），score传播链 P3 修复生效
  - trailer precision 极低 (0.0126) 需关注 — 可能过度预测
  - truck_recall 偏低 (0.18 vs Plan B 的 0.35)，但仅 iter 500，后续可能改善
  - 下次验证 iter 1000 预计 ~16:49
- **研究员操作**: 空闲（等待在 prompt）
- **指令通道**: NO_CHANGE / NO_PENDING
