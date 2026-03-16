# Supervisor 摘要报告
> 时间: 2026-03-16 18:36:26

## 训练状态
- 当前实验: **无训练运行**
- 最后实验: ORCH_059 (FAIL @iter500, 16:17 CDT 终止)
- GPU: 0,2 空闲; 1,3 被 yl0826 占用 (100%)
- 训练是否正常运行: **否**

## 🚨 磁盘空间告警
| 挂载点 | 使用率 | 剩余 |
|--------|--------|------|
| /mnt/SSD | **100%** | **4.7 GB** |
| /home | **99%** | **46 GB** |

## 最近实验 (连续 FAIL)
| ORCH | 结果 | 失败模式 |
|------|------|----------|
| 057 | FAIL | sat=1.0 @100 早停 |
| 058 | FAIL | marker_same>0.95 全程 |
| 059 | FAIL | all-negative collapse |

## 🚨 训练质量告警
- [RED] marker 无位置相关判断能力 (marker_same>0.96 全程)
- [RED] reg_loss≈0, offset 学习停滞
- [RED] 三连 FAIL, 超参调整无效, 需架构干预

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_060 | DELIVERED | pred/target alignment 可视化, 截止 20:15, Admin 执行中 |

## Agent 状态
| Agent | tmux | 备注 |
|-------|------|------|
| conductor | ✅ UP (attached) | active |
| conductor-auto | ✅ UP | |
| critic | ✅ UP | idle |
| supervisor | ✅ UP | 本轮循环 |
| admin | ✅ UP (attached) | 执行 ORCH_060 |
| ops | ✅ UP | 正常 |

## 代码变更（GiT）
无新 commit (最新仍 f67998d, ORCH_059)

## 异常告警
- 🚨 [CRITICAL] /mnt/SSD 100% (4.7GB) — 新训练硬阻塞
- 🚨 [RED] 三连 FAIL — marker fixation 未解
- ⚠️ [YELLOW] /home 99% (46GB)
- ℹ️ ORCH_060 Admin 执行中, 尚无报告
