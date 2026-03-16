# Supervisor 摘要报告
> 时间: 2026-03-16 18:30:40

## 训练状态
- 当前实验: **无训练运行**
- 最后实验: ORCH_059 (FAIL @iter500, 16:17 CDT 终止)
- GPU 使用: GPU 0,2 空闲; GPU 1,3 被 yl0826 占用 (100%, petr_vggt)
- 训练是否正常运行: **否** — 等待 ORCH_060 诊断结果

## 🚨 磁盘空间告警
| 挂载点 | 使用率 | 剩余 |
|--------|--------|------|
| /mnt/SSD | **100%** | **4.7 GB** |
| /home | **99%** | **46 GB** |

⚡ /mnt/SSD 已满，新训练无法运行。

## 最近实验结果 (连续 FAIL)

| ORCH | 变量 | 结果 | 失败模式 |
|------|------|------|----------|
| 057 | marker_no_grid_pos frozen check | FAIL | sat=1.0 @100 早停 |
| 058 | marker_no_grid_pos=True | FAIL | marker_same>0.95 全程 |
| 059 | marker_init_bias [-2,-2,-2,+0.5] | FAIL | all-negative collapse |

## Loss 趋势 (ORCH_059, 已终止)
- cls_loss: ~0.01 (trivial all-bg solution, 间歇 spike 10-13)
- reg_loss: ≈0 (无正预测)
- total_loss: ~0.01

## 🚨 训练质量告警
- [RED] marker_same>0.96 全程: marker 无位置相关判断能力
- [RED] reg_loss≈0: offset 学习停滞
- [RED] 三连 FAIL: init_bias/no_grid_pos 均无效，需架构层面干预
- [YELLOW] /mnt/SSD 100% — 阻塞新训练

## 代码变更（GiT 最近 5 条 commit）
```
f67998d feat: ORCH_059 BUG-82 marker_init_bias for P(bg)≈80% init
54aa79e scripts: ORCH_057/058 5-point frozen check with triple early-stop criteria
0566568 feat: ORCH_058 marker_no_grid_pos — marker step skips grid_pos_embed
6bb2089 config: ORCH_056 reduce lr 5e-5→1e-5 to slow template fixation
cb74b15 scripts: ORCH_055 5-point frozen check for 2-GPU DDP replication
```

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_057 | FAIL | |
| ORCH_058 | FAIL | |
| ORCH_059 | FAIL | |
| **ORCH_060** | **DELIVERED** | pred/target alignment 可视化诊断, 截止 20:15 |

## Agent 状态
| Agent | tmux | 状态 |
|-------|------|------|
| conductor | ✅ UP | active |
| conductor-auto | ✅ UP | active |
| critic | ✅ UP | idle |
| supervisor | ✅ UP | active |
| admin | ✅ UP | 执行 ORCH_060 中 |
| ops | ✅ UP | 快照正常 |

## 异常告警
- 🚨 [CRITICAL] /mnt/SSD 100% (4.7GB) — 新训练硬阻塞
- 🚨 [RED] 三连 FAIL — marker fixation 未解
- ⚠️ [YELLOW] /home 99% (46GB)
- ℹ️ ORCH_060 已投递 Admin, 诊断中
