# Supervisor 摘要报告
> 时间: 2026-03-12 21:41:00
> Cycle #283

## 训练状态 — ORCH_035 @6000 checkpoint + VAL 进行中
- 进度: iter **6000/40000** (15.0%) — ⭐ @6000 checkpoint 已保存
- **Val: 170/753 (22.6%)**, ETA ~40 min (预计 ~22:21 完成)
- Val 速度: ~4.09s/iter
- GPU: 0-3 各 ~39.5 GB, 86-97% (val 期间略低, 正常)
- 磁盘: /mnt/SSD **96% (178GB free)** — checkpoint 写入消耗 ~16GB ⚠️
- /home 99% (68GB free)

## Loss 趋势 (iter 5900-6000, pre-val)
| iter | loss | cls | reg | grad_norm |
|------|------|-----|-----|-----------|
| 5900 | 4.68 | 2.64 | 2.04 | 16.5 |
| 5930 | 6.49 | 4.34 | 2.15 | 22.4 |
| 5960 | 7.10 | 5.05 | 2.05 | 28.1 |
| 5990 | 4.25 | 2.00 | 2.24 | 23.6 |
| 6000 | 4.65 | 2.95 | 1.70 | 25.0 |

### 分析
1. **@6000 milestone** — checkpoint 保存成功, val 启动
2. **本窗口零 reg=0** — 密集 cluster 后完全恢复 ✅
3. Loss 均值 ~5.1 (正常波动, 上窗口低值受 reg=0 影响)
4. **ORCH_035 首次 val** — 新标签 pipeline 的第一个评估结果
5. 将与 ORCH_034 @4000 val 对比:
   - car_R=0.8195, bg_FA=0.3240 (红线), off_th=0.1598
   - 期望: 新标签修复 bg_FA

## 磁盘变化
- /mnt/SSD: 194GB → 178GB (-16GB, checkpoint 写入)

## 异常告警
- ⚠️ /mnt/SSD 96% (178GB free, 下降中)
- ⚠️ /home 99% (68GB free)

## ORCH 投递
- 0 个 PENDING
