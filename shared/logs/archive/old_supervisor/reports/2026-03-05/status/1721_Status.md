# Status — 17:21 [ALERT]

- **Iter**: 1500/8000 (18.75%), validation 完成
- **Loss**: iter 1500 loss=0.845 (本轮最低)
- **GPU**: 0=98%(22.4GB), 2=98%(23GB) [Plan C]; 1,3=yl0826(31.2GB)

## [ALERT] iter 1500 验证指标全面下降

| 指标 | @500 | @1000 | @1500 | 趋势 |
|------|------|-------|-------|------|
| car_recall | 0.645 | 0.697 | **0.598** | ↓ |
| car_precision | 0.143 | 0.104 | **0.074** | ↓↓ |
| truck_recall | 0.176 | 0.114 | **0.050** | ↓↓ [CRITICAL] |
| truck_precision | 0.058 | 0.057 | 0.060 | → |
| bus_recall | 0.322 | 0.609 | 0.476 | ↓ from peak |
| bus_precision | 0.113 | 0.229 | 0.115 | ↓ |
| trailer_recall | 0.978 | 0.733 | 0.822 | ↑ slight |
| trailer_precision | 0.013 | 0.061 | 0.020 | ↓ |
| bg_recall | 0.844 | 0.829 | **0.794** | ↓ |
| **bg_false_alarm** | 0.156 | 0.171 | **0.206** | ↑↑ [ALERT] |

## 关键问题
1. **truck_recall=0.050 近乎崩溃** — CEO 特别要求关注 truck 稳定性
2. **bg_false_alarm=0.206 已超过 Plan B 最佳 (0.194)** — P0 BG 修复优势正在消失
3. **所有 recall 和 precision 全面下降** — 模型可能在过拟合或特征漂移
4. **研究员尚未响应 CEO 指令** — tmux 可见但未行动

- **研究员操作**: 仍空闲在 prompt
- **指令通道**: CEO 指令已中继 / NO_ORCH_FILES
