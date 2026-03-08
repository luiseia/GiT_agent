# BUG-33 调查报告: GT 统计 DDP 不一致
**Timestamp**: 2026-03-08 11:00
**Status**: ROOT CAUSE CONFIRMED, FIX APPLIED

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

## 3. 验证

**单 GPU eval (tools/test.py)** 使用相同 P6@500 checkpoint:

| 类别 | 单GPU eval | DDP val | 匹配 Plan L? |
|------|-----------|---------|-------------|
| car_gt | **6719** | 7232 | YES (6719) |
| truck_gt | **1640** | 3206 | YES (1640) |
| car_R | **0.231** | 0.252 | - |
| car_P | **0.073** | 0.073 | YES |
| bg_FA | **0.173** | 0.163 | - |

**结论**: 单 GPU eval GT 与 Plan L 完全一致。DDP val 的 GT 和 Recall 不可信，Precision 基本可信（因为分母是 pred_cnt 不受影响）。

## 4. 影响范围

| 实验 | 启动模式 | GT 受影响? | Precision 可信? |
|------|---------|-----------|----------------|
| Plan K | 单 GPU | NO | YES |
| Plan L | 单 GPU | NO | YES |
| Plan M | 单 GPU | NO | YES |
| Plan N | 单 GPU | NO | YES |
| **P5b** | **DDP 2 GPU** | **YES** | YES |
| **P6** | **DDP 2 GPU** | **YES** | YES |

**关键**: 所有实验的 **Precision (car_P)** 不受影响（分母 = pred_cnt，不依赖 GT），因此跨实验 car_P 对比仍然有效。**Recall** 和 **gt_cnt** 在 DDP 实验中偏差较大。

## 5. 修复

已在以下 config 中添加 `sampler=dict(type='DefaultSampler', shuffle=False)`:
- `plan_p6_wide_proj.py`
- `plan_i_p5b_3fixes.py`

**注意**: 当前 P6 训练进程使用的是修复前的 config（已在内存中加载），val 结果仍有 GT 偏差。需要在下一次 checkpoint eval 时使用修复后的 config 重新评估。

## 6. 建议

1. **P6 跨实验对比用 car_P** — 不受 BUG-33 影响
2. **如需准确 Recall/GT**: 用 `tools/test.py` 单 GPU 重新 eval 关键 checkpoint
3. **后续所有 DDP config 必须显式声明 val sampler**
4. **P5b 历史数据**: car_P=0.107 可信，Recall 需重新评估
