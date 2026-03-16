# ORCH_059 执行报告 — marker_init_bias (BUG-82)

- **状态**: FAIL (all-negative collapse, 未触发 sat>0.95 早停但模型无效)
- **执行时间**: 2026-03-16 15:01 ~ 16:17 CDT (~76 min)
- **GiT commit**: `f67998d`

---

## 实验配置

| 参数 | 值 |
|------|-----|
| marker_init_bias | `[-2.0, -2.0, -2.0, +0.5]` (新增，P(bg)≈80%) |
| marker_no_grid_pos | False (ORCH_058 reverted) |
| bg_balance_weight | 5.0 |
| marker_pos_punish | 1.0 |
| lr | 5e-5 |
| GPU | 2,3 (2-GPU DDP) |
| work_dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch059` |

---

## 代码修改摘要 (~5 行)

### `git_occ_head.py`
1. **__init__ (L215-216)**: 新增 `self.marker_init_bias = nn.Parameter(torch.tensor([-2.0, -2.0, -2.0, +0.5]))`
2. **训练路径 focal (L858)**: `marker_logits = ... + self.marker_init_bias`
3. **训练路径 CE (L932)**: `marker_logits = ... + self.marker_init_bias`
4. **推理路径 (L1156)**: `marker_logits = ... + self.marker_init_bias`

### `plan_full_nuscenes_large_v1.py`
- `marker_no_grid_pos=False` (从 ORCH_058 的 True 恢复)

---

## 训练 loss 轨迹

| iter | loss | cls | reg | 备注 |
|------|------|-----|-----|------|
| 10 | 8.05 | 5.90 | 2.15 | cls 比基线低 (8.61→5.90), bias 起效 |
| 20 | 13.85 | 9.75 | 4.10 | reg 活跃 |
| 30 | 9.39 | 7.47 | 1.91 | reg 活跃 |
| 40 | 0.10 | 0.10 | 0.00 | reg 归零 — 同 ORCH_055/058 模式 |
| 100 | 0.05 | 0.05 | 0.00 | cls 极低 — 模型"满意"于 all-bg |

---

## Frozen Check 完整数据

| iter | Pos slots | IoU | marker_same | Coord diff | Saturation | TP |
|------|-----------|-----|-------------|------------|------------|-----|
| 100 | 259/1200 (21.6%) | 0.851 | 0.963 | 0.019 | 0.253 | 106 |
| 200 | 54/1200 (4.5%) | 0.876 | 0.994 | 0.020 | 0.050 | 34 |
| 300 | 32/1200 (2.7%) | 0.886 | 0.996 | 0.003 | 0.035 | 23 |
| 400 | 7/1200 (0.6%) | 0.633 | 0.998 | 0.004 | 0.007 | 4 |
| 500 | 23/1200 (1.9%) | 0.760 | 0.995 | 0.000 | 0.025 | 16 |

### 与 ORCH_055 基线对比

| iter | ORCH_055 pos_slots | ORCH_059 pos_slots | ORCH_055 TP | ORCH_059 TP |
|------|--------------------|--------------------|-------------|-------------|
| 100 | 750 (63%) | 259 (21.6%) | 109 | 106 |
| 200 | 954 (80%) | 54 (4.5%) | 147 | 34 |
| 300 | 1010 (84%) | 32 (2.7%) | 150 | 23 |
| 400 | 71 (6%) | 7 (0.6%) | 0 | 4 |
| 500 | 158 (13%) | 23 (1.9%) | 12 | 16 |

---

## 结论

### ORCH_059 FAIL — init_bias 将 all-positive 翻转为 all-negative

1. **假设部分成立但效果适得其反**:
   - init_bias 确实打破了 all-positive 初始化 (pos_slots @100: 63% → 21.6%)
   - 但模型持续向 all-negative 方向漂移 (pos_slots: 21.6% → 4.5% → 2.7% → 0.6%)
   - 最终结果: 几乎不产出正预测 (TP @400=4)

2. **marker_same 自始至终都 > 0.95**:
   - @100 就已经 0.963, 远高于 ORCH_055 @100 的 0.887
   - 说明 init_bias 没有解决模板化问题，只是改变了模板的极性（从 all-positive 模板变成了 all-negative 模板）

3. **根因分析**:
   - init_bias 的 `+0.5` 对 END token 太强，使模型初始就倾向预测 bg
   - 结合 `bg_balance_weight=5.0`，bg 梯度被进一步放大
   - 模型发现"全部预测 bg"是 cls_loss 极低的 trivial solution (loss@100=0.05)
   - reg_loss 从 iter 40 就归零 — 没有正预测就没有回归目标

4. **ORCH_055 vs ORCH_059 镜像崩塌**:
   - ORCH_055: all-positive → 逐渐饱和 (pos_slots ↑)
   - ORCH_059: all-negative → 逐渐消失 (pos_slots ↓)
   - 两者 marker_same 都趋近 1.0 — 根本问题是 marker 无法学会位置相关的判断

---

*报告生成: 2026-03-16 16:20 CDT*
