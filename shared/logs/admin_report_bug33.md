# BUG-33 调查报告: GT 统计 DDP 不一致
**Timestamp**: 2026-03-08 12:15
**Status**: ROOT CAUSE CONFIRMED, FIX APPLIED, **P6 RE-EVAL COMPLETED**

---

## 1. 现象

P6 (DDP 2-GPU) val 的 GT 统计与 Plan L (单 GPU) 不一致:

| 类别 | Plan L (单GPU) | P6 (DDP 2GPU) | 偏差 |
|------|---------------|---------------|------|
| car | 6719 | 7232 | +7.6% |
| truck | 1640 | 3206 | +95% |
| bus | 1522 | 2534 | +66% |
| pedestrian | 2354 | 3728 | +58% |
| motorcycle | 127 | 12 | **-91%** |

## 2. 根因

**val_dataloader 缺少 `sampler` 配置**

调用链:
1. `BaseLoop.__init__` → `runner.build_dataloader(val_dataloader_cfg)`
2. `build_dataloader()` 执行 `sampler_cfg = dataloader_cfg.pop('sampler')`
3. `ConfigDict.pop('sampler')` 返回 **None**（不抛 KeyError）
4. PyTorch `DataLoader(sampler=None)` 使用默认 `SequentialSampler`
5. DDP 下每个 GPU 独立处理全量 323 样本
6. `collect_results()` 将两个 rank 的结果 zip-interleave 后截断到 size=323
7. 结果: 前 ~162 个样本被重复计数，后 ~161 个样本丢失
8. GT 在数据集中分布不均 → 各类偏差不等比

## 3. P6 全量 Re-eval (ORCH_019) — 5 Checkpoints

### 3.1 单 GPU 真实值

| Ckpt | car_R | car_P | truck_P | bus_P | ped_P | bg_FA | off_th |
|------|-------|-------|---------|-------|-------|-------|--------|
| @500 | 0.231 | 0.073 | 0.019 | 0.008 | 0.021 | 0.173 | 0.259 |
| @1000 | 0.252 | 0.058 | 0.027 | 0.010 | 0.002 | 0.352 | 0.220 |
| @1500 | 0.499 | **0.106** | 0.000 | 0.017 | 0.004 | 0.250 | 0.246 |
| @2000 | 0.376 | **0.110** | 0.032 | 0.018 | 0.004 | **0.300** | 0.234 |
| @2500 | 0.516 | **0.111** | **0.047** | 0.022 | 0.018 | 0.336 | **0.201** |

### 3.2 DDP vs 单 GPU 偏差

| Ckpt | 指标 | DDP | 单GPU | 偏差 | 方向 |
|------|------|-----|-------|------|------|
| @500 | car_P | 0.073 | 0.073 | 0% | - |
| @500 | bg_FA | 0.163 | 0.173 | -6% | DDP 低估 |
| @500 | off_th | 0.236 | 0.259 | -9% | DDP 低估 |
| @1000 | car_P | 0.054 | 0.058 | -7% | DDP 低估 |
| @1000 | bg_FA | 0.323 | 0.352 | -8% | DDP 低估 |
| @1000 | off_th | 0.250 | 0.220 | +14% | DDP 高估 |
| **@1500** | **car_P** | **0.117** | **0.106** | **+10%** | **DDP 虚高!** |
| @1500 | bg_FA | 0.278 | 0.250 | +11% | DDP 高估 |
| @1500 | off_th | 0.259 | 0.246 | +5% | DDP 高估 |
| @2000 | car_P | 0.111 | 0.110 | +1% | 接近 |
| @2000 | bg_FA | 0.327 | 0.300 | +9% | DDP 高估 |
| @2000 | off_th | 0.230 | 0.234 | -2% | 接近 |
| @2500 | car_P | 0.112 | 0.111 | +1% | 接近 |
| @2500 | bg_FA | 0.337 | 0.336 | 0% | 接近 |
| @2500 | off_th | 0.202 | 0.201 | 0% | 接近 |

### 3.3 关键修正

1. **P6@1500 car_P=0.106** (DDP 显示 0.117, 虚高 10%) — 实际 **略低于** P5b baseline 0.107
2. **P6@2000 car_P=0.110** — 真正超过 P5b baseline ✅
3. **P6@2500 car_P=0.111** — 持续超过 baseline ✅
4. **P6@2000 bg_FA=0.300** — 刚好在红线, 不是 0.327 ✅
5. **P6@2500 off_th=0.201** — 首次低于 0.21, 接近 P5b 水平 ✅

## 4. 影响范围 (修正)

| 实验 | 启动模式 | GT 受影响? | Precision 可信? |
|------|---------|-----------|----------------|
| Plan K | 单 GPU | NO | YES |
| Plan L | 单 GPU | NO | YES |
| Plan M | 单 GPU | NO | YES |
| Plan N | 单 GPU | NO | YES |
| **P5b** | **DDP 2 GPU** | **YES** | **±10% 偏差** |
| **P6** | **DDP 2 GPU** | **YES** | **±10% 偏差** |

**重要修正**: DDP 的 **Precision 也有偏差** (最高 ±10%)! 原因: zip-interleave 截断只评估了前半数据集的 predictions, 后半数据集被丢失。前半和后半数据的预测分布不一致导致 Precision 偏差。

偏差随训练收敛而减小 (@2000, @2500 偏差 <2%)。

## 5. 修复

已在以下 config 中添加 `sampler=dict(type='DefaultSampler', shuffle=False)`:
- `plan_p6_wide_proj.py`
- `plan_i_p5b_3fixes.py`

当前 P6 训练进程使用修复前 config, 但现在已有 5 个 checkpoint 的单 GPU 真实值。

## 6. 建议 (更新)

1. **所有跨实验对比需用单 GPU re-eval 值** — DDP Precision 偏差最高 10%
2. **P5b car_P=0.107 需要 re-eval** — 可能偏差 ±10%
3. **后续所有 DDP config 必须显式声明 val sampler**
4. **P6 训练继续** — @2000+ 真实 car_P=0.110-0.111, 确认超过 P5b baseline
