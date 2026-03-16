# Supervisor 摘要报告
> 时间: 2026-03-16 18:30:00

## 训练状态
- 当前实验: **无训练运行** (ORCH_059 已于 16:17 CDT 终止)
- 进度: ORCH_059 在 iter 500/40000 被 kill (frozen check FAIL)
- GPU 使用: GPU 0,2 空闲 (我方); GPU 1,3 被 yl0826 占用 (100% util, petr_vggt)
- 训练是否正常运行: **否** — 三连 FAIL 后待 Conductor 决策

## 🚨 磁盘空间告警
| 挂载点 | 使用率 | 剩余 |
|--------|--------|------|
| /mnt/SSD | **100%** | **4.7 GB** |
| /home | **99%** | **46 GB** |

⚡ /mnt/SSD 已满！新训练将无法保存 checkpoint。**必须清理旧实验目录后才能启动新训练。**

## 最近三次实验结果 (连续 FAIL)

| ORCH | 变量 | 结果 | 失败模式 |
|------|------|------|----------|
| 057 | marker_no_grid_pos + frozen check | FAIL | saturation=1.0 @100, 早停 |
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

### ORCH_059 Loss 趋势（已终止）
| iter | loss | cls | reg | grad_norm | 备注 |
|------|------|-----|-----|-----------|------|
| 240 | 0.016 | 0.016 | 0.000 | 0.97 | reg=0 — 无正预测 |
| 300 | 0.013 | 0.013 | 0.000 | 0.75 | all-bg trivial |
| 380 | 8.83 | 6.93 | 1.90 | 37.8 | spike — 偶尔学到正 |
| 440 | 13.39 | 11.73 | 1.66 | 63.3 | spike |
| 500 | 12.06 | 9.82 | 2.25 | 113.9 | 最后 iter |

**分析**: 90%+ iter 中 loss<0.02 (trivial all-bg)，间歇性 spike 10-13 但立即回落。reg_loss 绝大部分时间=0。模型稳定在 all-negative trivial solution。

## 🚨 训练质量告警
- [RED] 预测多样性极低: ORCH_059 @400 仅 7/1200 pos_slots (0.6%), TP=4
- [RED] marker_same > 0.96 全程: 模型未学到位置相关的 marker 判断
- [RED] reg_loss ≈ 0: 无正预测导致无回归目标，offset 学习完全停滞
- [RED] 三连 FAIL (ORCH_057/058/059): init_bias、no_grid_pos 均无法打破 marker fixation
- [YELLOW] 根因疑似: marker 分类与位置条件解耦 — 需架构层面干预而非超参调整

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
| ORCH_057 | FAIL | marker_no_grid_pos frozen check @100 早停 |
| ORCH_058 | FAIL | marker_no_grid_pos=True, 同样饱和 |
| ORCH_059 | FAIL | marker_init_bias → all-negative collapse |
| **ORCH_060** | **DELIVERED** | 可视化 pred/target alignment 对齐诊断 (刚投递) |

## Agent 状态
| Agent | tmux | 状态 | 备注 |
|-------|------|------|------|
| conductor | ✅ UP | active | PCA 可视化 DINOv3 + 签发 ORCH_060 |
| conductor-auto | ✅ UP | — | 已重启 |
| critic | ✅ UP | idle | 无审计请求 |
| supervisor | ✅ UP | active | 本轮循环 |
| admin | ✅ UP | active | 接收到 ORCH_060 |
| ops | ✅ UP | now | 快照正常 |

## Admin 最新活动
Admin 已接收 ORCH_060 (可视化 pred/target alignment 诊断)，截止 20:15 CDT。

## 异常告警
- 🚨 **[CRITICAL] /mnt/SSD 磁盘 100%** — 仅剩 4.7GB，新训练无法运行
- 🚨 **[RED] 三连 FAIL** — marker fixation 问题需架构层面方案
- ⚠️ **[YELLOW] /home 磁盘 99%** — 仅剩 46GB
- ℹ️ Conductor 已切换到诊断模式，签发 ORCH_060 做 pred/target alignment 可视化
