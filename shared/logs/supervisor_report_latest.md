# Supervisor 摘要报告
> 时间: 2026-03-16 18:19:05

## 训练状态
- 当前实验: **无训练运行** (ORCH_059 已于 16:17 CDT 终止)
- 进度: ORCH_059 在 iter 500/40000 被 kill (frozen check FAIL)
- GPU 使用: GPU 0,2 空闲 (我方); GPU 1,3 被 yl0826 占用 (100% util, petr_vggt)
- 训练是否正常运行: **否** — 三连 FAIL 后待 Conductor 决策下一步

## 🚨 磁盘空间告警
| 挂载点 | 使用率 | 剩余 |
|--------|--------|------|
| /mnt/SSD | **100%** | **4.7 GB** |
| /home | **99%** | **46 GB** |

⚡ /mnt/SSD 已满！新训练将无法保存 checkpoint。**必须清理旧实验目录后才能启动新训练。**

## 最近三次实验结果 (连续 FAIL)

| ORCH | 变量 | 结果 | 失败模式 |
|------|------|------|----------|
| 057 | marker_no_grid_pos + frozen check | FAIL | marker_same > 0.95 全程 |
| 058 | marker_no_grid_pos=True | FAIL | marker_same > 0.95 全程 |
| 059 | marker_init_bias [-2,-2,-2,+0.5] | FAIL | all-negative collapse: pos_slots 259→7→23 |

### ORCH_059 Frozen Check 数据
| iter | Pos slots | marker_same | Coord diff | TP |
|------|-----------|-------------|------------|-----|
| 100 | 259/1200 (21.6%) | 0.963 | 0.019 | 106 |
| 200 | 54/1200 (4.5%) | 0.994 | 0.020 | 34 |
| 300 | 32/1200 (2.7%) | 0.996 | 0.003 | 23 |
| 400 | 7/1200 (0.6%) | 0.998 | 0.004 | 4 |
| 500 | 23/1200 (1.9%) | 0.995 | 0.000 | 16 |

**结论**: init_bias 只是将 all-positive 翻转为 all-negative，marker_same 从 @100 就 >0.96，根本问题是 marker 无法学会位置相关判断。

## Loss 趋势 (ORCH_059, 已终止)
- cls_loss: 0.01 (极低 — trivial all-bg solution)
- reg_loss: 0.00 (无正预测 → 无回归目标)
- total_loss: 0.01

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
| ORCH_057 | FAIL | marker_no_grid_pos frozen check 全饱和 |
| ORCH_058 | FAIL | marker_no_grid_pos=True, 同样饱和 |
| ORCH_059 | FAIL | marker_init_bias → all-negative collapse |
| 新 ORCH | — | 待 Conductor 决策 |

## Agent 状态
| Agent | tmux | 状态 | 备注 |
|-------|------|------|------|
| conductor | ✅ UP | active | PCA 可视化 DINOv3 特征 (38% ctx) |
| conductor-auto | ❌ DOWN | — | 需要重启 |
| critic | ✅ UP | idle | 无审计请求 |
| supervisor | ✅ UP | active | 本轮循环 |
| admin | ✅ UP | active | 自主循环中 |
| ops | ✅ UP | now | 快照正常 |

## Admin 最新活动
最后有效日志条目来自 ORCH_035 时期 (03-12)。最近 ORCH_057-059 由 frozen check 自动脚本管理执行和终止。

## 异常告警
- 🚨 **[CRITICAL] /mnt/SSD 磁盘 100%** — 仅剩 4.7GB，新训练无法正常运行
- 🚨 **[RED] 三连 FAIL** — ORCH_057/058/059 全部失败，marker fixation 问题未解决
- ⚠️ **[YELLOW] conductor-auto DOWN** — 自动循环会话不可用
- ⚠️ **[YELLOW] /home 磁盘 99%** — 仅剩 46GB
- ℹ️ Conductor 正在做 PCA 可视化分析，可能在诊断 marker fixation 根因
