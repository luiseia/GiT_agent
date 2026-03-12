# Supervisor 摘要报告
> 时间: 2026-03-12 05:50:00
> Cycle #255

## ⭐ 重大变化: ORCH_032 → ORCH_033 → ORCH_034

### 事件链
1. **ORCH_033** (COMPLETED): Critic 判定 ORCH_032 STOP。Kill ORCH_032, 修复 4 个 BUG:
   - BUG-57: proj lr_mult 2→5
   - BUG-58: load_from=None → ORCH_029@2000 (warm start)
   - BUG-59: proj_hidden_dim 2048→4096 (压缩比 8:1→4:1)
   - BUG-60: clip_grad 10→30
2. **ORCH_034** (COMPLETED): CEO 要求部署 BUG-52 IoF/IoB 修复。Kill ORCH_033, 用修复后代码重启。
   - Config 不变 (ORCH_033 的 4 个修复 + BUG-52 live IoF/IoB 过滤)
   - Work dir: `full_nuscenes_multilayer_v3`

## 当前训练状态 — ORCH_034
- 进度: iter **200/40000** (0.5%) — 刚启动 ~25min
- LR: 2.5e-7 (warmup 极早期, base_lr=5e-5)
- ETA: ~2d 22h
- GPU: 0-3 各 ~35.5 GB, 100% ✅ (比 ORCH_032 +0.8GB from proj_hidden=4096)
- 磁盘: /mnt/SSD 94% (224GB free)
- 进程: 4 DDP workers alive ✅

## Loss 趋势 (iter 10-200)
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 10 | 3.88 | 2.02 | 1.86 | 31.2 |
| 50 | 3.46 | 1.77 | 1.68 | 24.5 |
| 100 | 5.06 | 2.97 | 2.09 | 25.9 |
| 150 | 3.60 | 1.85 | 1.75 | 52.1 |
| 200 | 4.33 | 2.47 | 1.85 | 20.1 |

### 与 ORCH_032 对比 (同期 iter 10-200)
| 指标 | ORCH_032 | **ORCH_034** | 判定 |
|------|----------|-------------|------|
| loss 范围 | 5-15 | **3.5-7.1** | ✅ 大幅改善 |
| reg=0 频率 | 频繁 | **0 次** | ✅ warm start 有效 |
| grad_norm 均值 | ~100+ | **~28** | ✅ 大幅改善 |
| VRAM | 29.8 GB | **30.6 GB** | ✅ 可控 (+0.8GB) |

### 初步分析
1. **Warm start 明显有效**: 初始 loss ~4 (vs ORCH_032 ~8-10), reg 从不为零
2. **grad_norm 稳定**: 18—52, 比 ORCH_032 (50-200 早期) 大幅改善
3. **cls/reg 平衡**: reg ≈ 1.6-2.5, 始终有前景 cell 贡献, 不再出现 mode collapse 迹象
4. **极早期, 不做结论** — 下次关注 @500, @1000 时的稳定性

## 异常告警
无当前告警。训练正常。

## ORCH 投递状态
- 0 个 PENDING ORCH
- ORCH_033, ORCH_034: 均 COMPLETED
