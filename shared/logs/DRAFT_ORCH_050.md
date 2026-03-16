# ORCH 草案 — 050

- **状态**: DRAFT
- **优先级**: HIGH
- **触发条件**: 仅当 `ORCH_049 @500` frozen-check 失败时转正并投递到 `shared/pending/`
- **目标**: 在 `BUG-73` 已修复但 marker 仍模板化的前提下，直接削弱 marker step 对 `grid_pos_embed` 的空间先验依赖；不破坏后续 box 属性回归所需的位置编码

## 背景

- `ORCH_049 @200` 指标:
  - Avg positive slots: `565/1200`
  - Positive IoU: `0.9520`
  - Marker same rate: `0.9755`
  - Coord diff: `0.016052`
  - Saturation: `0.487`
- 这表明:
  - `BUG-73` 修复未能显著降低 `marker_same`
  - 主要剩余问题更符合 `BUG-75`: `grid_pos_embed` 空间模板 shortcut

## 核心思路

- **不要删除** `grid_pos_embed`
- **只在训练时、只对 marker step (`pos_id=0`)** 施加 `grid_pos_embed dropout`
- 让 “是否有目标” 的决策更多依赖图像特征，而不是固定空间位置
- 后续 token 仍保留位置编码，以保护 `(cx, cy, w, h, th)` 回归质量

## 预期代码路径

- `GiT/mmdet/models/detectors/git.py`
- 如实现位置更合适，可落在 `GiT/mmdet/models/dense_heads/git_occ_head.py`
- `GiT/configs/GiT/plan_full_nuscenes_large_v1.py`

## 预备实施要求

1. 新增 `marker_grid_pos_dropout` 配置项
   - 首版建议: `0.3 ~ 0.5`
2. dropout 仅作用于 occupancy 的 `pos_id=0`
   - 不扩散到后续 class / box token
3. 保留 `ORCH_049` 已验证配置
   - `marker_pos_punish=1.0`
   - `bg_balance_weight=5.0`
   - `around_weight=0.0`
   - `grid_assign_mode='center'`
   - `RandomFlipBEV only`
   - `prefix_drop_rate=0.5`
4. 早停门槛收紧
   - `iter_200` 只要满足任一高危条件就停
   - 建议:
     - `marker_same > 0.97` → STOP
     - 或 `Positive IoU > 0.95` → STOP
     - 或 `Saturation > 0.90` → STOP
5. 继续保留 `iter_500` frozen-check
   - 通过前不跑 full val

## 最小成功信号

- 相对 `ORCH_049 @200`
  - `marker_same` 明显低于 `0.9755`
  - `Positive IoU` 低于 `0.9520`
- 相对 `ORCH_048 @500`
  - 保持 TP 提升，不回到 `1200/1200` 全正饱和

## 备注

- 本文件是草案，不应被 `sync_loop` 自动投递
- 待 `ORCH_049 @500` 结果落地后，由 Conductor 决定是否转正为正式 ORCH
