# ORCH_058 执行报告 — marker_no_grid_pos

- **状态**: FAIL (EARLY STOP @100)
- **执行时间**: 2026-03-16 13:41 ~ 13:58 CDT (~17 min)
- **GiT commit**: `54aa79e` (code `0566568`)

---

## 实验配置

| 参数 | 值 |
|------|-----|
| marker_no_grid_pos | **True** (新增) |
| bg_balance_weight | 5.0 |
| marker_pos_punish | 1.0 |
| lr | 5e-5 |
| GPU | 2,3 (2-GPU DDP) |
| master_port | 29511 |
| work_dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch057` |

---

## 代码修改摘要

### 训练路径 (`git.py`)
- L50,88: 新增 `marker_no_grid_pos` 参数及 `self.marker_no_grid_pos` 属性
- L354: `grid_pos_embed_raw = grid_pos_embed if self.marker_no_grid_pos else None` — 保存原始 grid_pos_embed
- L385: 传入 `transformer_inputs_dict`
- L393: `forward_transformer` 新增 `grid_pos_embed_raw` 参数
- L514-518: gather `select_grid_pos_embed_raw`
- L559: 传递给 `get_grid_feature`
- L639-652: `get_grid_feature` — layer_id==0 时减去 grid_pos_embed_raw，layer_id>0 时用 `(grid_start_embed - grid_pos_embed_raw)`

### 推理路径 (`git_occ_head.py`)
- L1068: `decoder_inference` 新增 `grid_pos_embed_raw` 参数
- L1119-1131: pos_id%10==0 (marker step) 时用 `(grid_token - grid_pos_embed_raw)` 替代 `grid_token`；其他 step 正常使用 grid_token

### Config (`plan_full_nuscenes_large_v1.py`)
- L192: `marker_no_grid_pos=True`
- L377: lr 恢复为 5e-5

---

## 训练 loss 轨迹

| iter | loss | cls_loss | reg_loss | base_lr |
|------|------|----------|----------|---------|
| 10 | 10.57 | 8.61 | 1.95 | 2.75e-7 |
| 20 | 11.23 | 7.78 | 3.45 | 5.25e-7 |
| 30 | 4.92 | 2.98 | 1.93 | 7.75e-7 |
| 40 | 1.07 | 1.07 | **0.00** | 1.02e-6 |
| 50 | 0.85 | 0.85 | 0.00 | 1.27e-6 |
| 60 | 0.84 | 0.84 | 0.00 | 1.52e-6 |
| 70 | 0.79 | 0.79 | 0.00 | 1.77e-6 |
| 80 | 0.66 | 0.66 | 0.00 | 2.02e-6 |
| 90 | 0.48 | 0.48 | 0.00 | 2.27e-6 |
| 100 | 0.38 | 0.38 | 0.00 | 2.52e-6 |

**reg_loss 从 iter 40 开始持续为零** — 模型已不产出有意义的正预测回归。

---

## Frozen Check @100 结果

| 指标 | ORCH_055 @100 (基线) | ORCH_058 @100 |
|------|---------------------|---------------|
| Pos slots | 750/1200 (63%) | **1200/1200 (100%)** |
| Positive IoU | 0.853 | **1.000** |
| marker_same | 0.887 | **0.992** |
| Saturation | 0.703 | **1.000** |
| Coord diff | — | 0.014 |
| TP | 109 | 177 |

**三重 early-stop 全部触发**: IoU=1.0>0.95, marker_same=0.992>0.95, sat=1.0>0.95

---

## 结论

### ORCH_058 FAIL — marker_no_grid_pos 加速了崩塌

1. **假设被推翻**: grid_pos_embed 不是 marker 模板化的唯一根因
   - 移除 grid_pos_embed 后，marker 在 @100 已 100% 全正饱和 (vs 基线的 63%)
   - 模板化速度**加快**而非减缓

2. **机制分析**:
   - 移除 grid_pos_embed 后，marker 失去了区分空间位置的能力
   - 模型更快地退化到 "所有位置都预测正" 的 trivial solution
   - grid_pos_embed 实际上可能在**抑制**部分位置的 false positive（至少在早期训练）
   - 真正的问题可能不在位置编码，而在 cls/reg loss 结构或 AR decoding 机制本身

3. **下一步方向建议**:
   - 重新审视 loss 设计：cls loss 对 false positive 的惩罚力度不足
   - 考虑 focal loss 或 quality-aware loss 替代当前 cross-entropy
   - 审查 bg_balance_weight 在 warmup 阶段的有效性（LR 极低时梯度可能太弱）
   - 可能需要从 marker 的 sigmoid 初始化偏置入手（负偏置让模型默认预测 bg）

---

*报告生成: 2026-03-16 14:00 CDT*
