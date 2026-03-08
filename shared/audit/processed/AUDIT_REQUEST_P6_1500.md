# AUDIT REQUEST: P6 @1500 + BUG-33 确认 + Plan M/N 最终
- 签发: Conductor | Cycle #74
- 时间: 2026-03-08 11:00
- 优先级: HIGH

---

## 1. P6 @1500 — PASS per VERDICT_P6_1000 Criteria

**P6 完整 val 轨迹 (DDP 2-GPU, gt_cnt 有 BUG-33 inflation)**:

| Ckpt | car_R | car_P | truck_R | bus_R | constr_R | barrier_R | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|---------|-------|----------|-----------|-------|--------|--------|--------|
| @500 | 0.252 | 0.073 | 0.116 | 0.009 | 0.046 | 0.020 | **0.163** | 0.087 | 0.077 | 0.236 |
| @1000 | 0.197↓ | 0.054↓ | 0.043 | 0.112↑ | **0.306↑** | **0.141↑** | 0.323↑ | 0.127↓ | 0.092 | 0.250 |
| **@1500** | **0.681↑↑** | **0.117↑↑** | 0.000↓↓ | 0.126 | 0.064↓ | 0.000↓ | **0.278↓** | **0.034↑↑** | 0.069 | 0.259 |

### VERDICT_P6_1000 判定标准:
- **PASS**: car_P ≥ 0.07 + bg_FA ≤ 0.28
- **实际 @1500**: car_P=0.117 ✅ + bg_FA=0.278 ✅ (勉强)
- **→ PASS**

### @500→@1000→@1500 分析
1. **@1000 类振荡已确认为暂态**: constr/barrier @1000 爆发后 @1500 回落 (0.306→0.064, 0.141→0.000)
2. **car 重新主导**: car_R 从 0.197 暴涨到 0.681, car_P 从 0.054 到 0.117
3. **Critic 假说 B 完全验证**: 类振荡 + LR 过激 → 暂态, 非架构缺陷
4. **off_cx=0.034**: 历史最佳水平, 远优于所有之前实验

### 风险与担忧
1. **truck_R=0.000, barrier_R=0.000**: 类振荡反转, car 完全挤压其他类
2. **car_P=0.117 仍只有 DDP 值**: 单 GPU 下可能略有差异 (BUG-33)
3. **bg_FA=0.278 勉强 PASS**: 接近 0.28 阈值
4. **off_th=0.259**: 仍然偏高, 未改善
5. **@1500 可能是"反弹蜜月"**: 需 @2000 确认趋势可持续

### P6 @500 单 GPU vs DDP 对照 (BUG-33 修正参考)
| 指标 | DDP @500 | 单GPU @500 | 差值 |
|------|----------|-----------|------|
| car_R | 0.252 | 0.231 | -8% |
| car_P | 0.073 | 0.073 | 0% |
| bg_FA | 0.163 | 0.173 | +6% |
| off_th | 0.236 | 0.259 | +10% |

**Precision 在 DDP 和单 GPU 间基本不变**, recall 和 bg_FA 有 ~10% 差异。

---

## 2. BUG-33 根因确认 — DDP Val GT 计数错误

### 根因
Admin 在 GPU 0 上用单 GPU (`tools/test.py --launcher none`) 跑了 P6 @500 eval:
- 单 GPU gt_cnt: car=6719, truck=1640, bus=1522 — **与 Plan L 完全一致**
- DDP gt_cnt: car=7232 (+7.6%), truck=3206 (+95.5%), bus=2534 (+66.5%)

### 机制
DDP val 未使用 DistributedSampler, 每个 GPU 处理全量 323 样本。collect_results 将两个 rank 的结果 zip-interleave 后截断到 dataset size。导致前半数据被重复, 后半数据丢失, GT 统计被扭曲。

### 影响
1. **P6 所有 val 数据 (DDP) 的 gt_cnt 是错的** — recall 偏差 ~10%, precision 基本不变
2. **P6 vs Plan L 跨实验对比**: Precision 对比有效, recall 对比需修正
3. **P6 @1500 的 car_P=0.117 是可信的** (precision 不受 BUG-33 影响)

### 修复建议
1. **短期**: P6 @2000 后用单 GPU 重新 eval 关键 checkpoint (0.5h/ckpt)
2. **长期**: config 中加 `val_dataloader=dict(..., sampler=dict(type='DefaultSampler', shuffle=False))`
3. **或**: 所有 val 改用 `tools/test.py` 单 GPU 跑

---

## 3. Plan M/N @1500 — Frozen >> Unfreeze 最终确认

### 完整轨迹

**Plan M (在线 unfreeze)**:
| Ckpt | car_R | car_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.621 | 0.052 | 0.220 | 0.088 | 0.102 | 0.217 |
| @1000 | 0.699 | 0.049 | 0.249 | 0.079 | 0.090 | 0.232 |
| @1500 | **0.489↓↓** | 0.047 | 0.182 | 0.071 | 0.098 | 0.194 |

**Plan N (在线 frozen)**:
| Ckpt | car_R | car_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.618 | 0.050 | 0.219 | 0.088 | 0.104 | 0.206 |
| @1000 | 0.661 | 0.050 | 0.250 | 0.080 | 0.078 | 0.231 |
| @1500 | 0.630 | 0.045 | 0.236 | 0.080 | 0.081 | 0.229 |

### 结论
- **Unfreeze car_R 崩塌**: 0.699→0.489 (-21%), DINOv3 微调造成特征漂移
- **Frozen 稳定**: car_R 波动仅 ±3%, offsets 稳定
- **诊断最终结论: Frozen DINOv3 >> Unfreeze DINOv3**
- 在线路径 car_P ~0.05 < 0.077 (Plan K 基线阈值), **在线路径精度不达标**
- LR 已 decay (2.5e-06→2.5e-07), @2000 将是最终值

---

## 4. P6 训练异常 (已恢复)
- Iter 1450-1500: 5.3 s/iter (+77%), loss=8.61, GPU 0 内存 32.5 GB
- 原因: Admin 在 GPU 0 上跑 BUG-33 单 GPU eval (+8.3 GB)
- Iter 1510+: 恢复 ~3.0 s/iter, GPU 0 20.5 GB
- **影响有限**: 约 50 iter 训练减速, loss 飙升可能来自 val 切换

---

## 问题请 Critic 回答

### Q1: P6 @1500 PASS — 是否继续到 @3000?
car_P=0.117 远超 0.07 阈值, 且 Precision 不受 BUG-33 影响。但 truck_R=0.000 表明类振荡仍在。是否继续到 @2000/@3000 观察收敛?

### Q2: 类振荡是否会持续反转?
@500 car 主导 → @1000 小类爆发/car 被压 → @1500 car 反弹/小类归零。这个周期会继续还是在 LR decay 后稳定? @2000 是否是关键稳定点?

### Q3: BUG-33 修复方案
Admin 确认了 DDP val gt_cnt 错误。三种修复方案中推荐哪个? 是否需要用单 GPU 重新 eval P6 历史 checkpoint?

### Q4: Plan M/N 归档 — 在线 DINOv3 路线最终判决
Frozen >> Unfreeze 已确认。在线路径 car_P ~0.05 不达标。CEO 决策放弃预提取走在线路线, 但在线路径精度不达标。如何调和? 是否需要更长的训练 iter?

### Q5: P6 @2000 后 LR decay 的影响
Milestone=[2000, 4000], @2000 后 LR 将 decay。proj lr_mult=2.0 已知过激 (BUG-34)。Decay 后是否能稳定类振荡? 或者 P6 应在 @2000 后切换到 P6b (lr_mult=1.0)?

### Q6: off_th 为何始终 0.23-0.26, 无法改善?
P5b@3000 off_th=0.200, P6@1500 off_th=0.259。投影层变化没有帮助 theta 预测。根因是什么?

### Q7: P6 是否需要提 bg_balance_weight?
bg_FA=0.278 勉强 PASS。ORCH_017 建议 bg_FA>0.30 时提到 3.0。当前 2.5 是否已足够, 还是应在 P6b 中调整?
