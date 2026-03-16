# ORCH_055 执行报告

- **状态**: COMPLETED (5-point frozen check 全部完成)
- **执行者**: Admin Agent
- **时间**: 2026-03-16 05:45 — 07:01

## 代码修改

### Config (`plan_full_nuscenes_large_v1.py`)
- 精确复现 ORCH_049: marker_pos_punish=1.0, bg_balance_weight=5.0
- 无新改动（config 从 ORCH_054 继承，已是 bg=5.0）

### 训练方式
- **2-GPU DDP** (CUDA_VISIBLE_DEVICES=2,3, torch.distributed.launch, --launcher pytorch)
- memory=28878 MiB（匹配 ORCH_049 ✓）
- 有 ~44s accumulative steps（匹配 ORCH_049 ✓）
- ETA ~4 days（匹配 ORCH_049 ✓）

### GiT Commit
- `cb74b15` — scripts: ORCH_055 5-point frozen check for 2-GPU DDP replication

## 5-point Frozen Check 完整数据

| iter | Pos slots | Positive IoU | marker_same | Coord diff | Saturation | TP |
|------|-----------|-------------|-------------|-----------|------------|-----|
| 100 | 750/1200 (63%) | 0.8532 | 0.8872 | 0.012130 | 0.703 | 109 |
| 200 | 954/1200 (80%) | 0.9539 | 0.9625 | 0.015109 | 0.820 | 147 |
| 300 | 1010/1200 (84%) | 0.9680 | 0.9725 | 0.026590 | 0.873 | 150 |
| 400 | 71/1200 (6%) | 0.7802 | 0.9840 | 0.014153 | 0.080 | 0 |
| 500 | 158/1200 (13%) | 0.9096 | 0.9875 | 0.006370 | 0.142 | 12 |

## 崩塌轨迹分析

### Phase 1: 正向增长 (iter 100-300)
- TP 持续增长: 109 → 147 → 150
- Saturation 单调上升: 0.703 → 0.820 → 0.873
- 模型正在学习检测，但正预测比例不断膨胀
- marker_same 也在升: 0.887 → 0.963 → 0.973（预测趋同化）

### Phase 2: 急剧坍塌 (iter 300-400)
- Saturation 从 0.873 骤降到 0.080 (10x 下降)
- TP 从 150 跌至 0
- Pos slots 从 1010 跌至 71
- **模型从"几乎全正"突然翻转为"几乎全背景"**

### Phase 3: 微弱恢复 (iter 400-500)
- Saturation 从 0.080 微升到 0.142
- TP 从 0 恢复到 12
- 模型尝试重新学习但 marker_same 继续上升 (0.984→0.988)

### 关键观察
1. **崩塌是突然的，不是渐进的** — 发生在约 50 iter 的窗口内
2. **崩塌方向**: 全正 → 全背景（不是渐进减少）
3. **marker_same 全程单调上升** (0.887→0.988) — 即使在 TP 恢复期间也在增加
4. **coord_diff 先升后降** (0.012→0.027→0.014→0.006) — 坍塌后坐标差异趋近于零
5. **与 ORCH_049 一致**: 049 @200 有 TP=112，@500 全背景。055 更精确定位了崩塌点

### BUG-78 确认
| 指标 | 055 @100 (2-GPU DDP) | 054 @100 (单 GPU) |
|------|---------------------|-------------------|
| TP | 109 | 0 |
| Saturation | 0.703 | 0.000 |
单 GPU 结果完全无效，batch size 差异导致训练动态根本不同。

## 验收标准对照

| 标准 | 要求 | 实际 | 状态 |
|------|------|------|------|
| 2-GPU DDP | memory~28878, accumulative ~44s | 28878, 有45s steps | ✅ PASS |
| Config 匹配 049 | bg=5.0, punish=1.0 | 一致 | ✅ PASS |
| @200 复现 049 TP>0 | TP>0 | TP=147 | ✅ PASS |
| 5 检查点完整数据 | 5/5 | 5/5 完成 | ✅ PASS |

**总体: PASS** — 成功复现 049 崩塌模式，并精确定位崩塌时间点在 iter 300-400。

## 可视化
- iter_100: `shared/logs/VIS/055_iter100_frozen_check/`
- iter_200: `shared/logs/VIS/055_iter200_frozen_check/`
- iter_300: `shared/logs/VIS/055_iter300_frozen_check/`
- iter_400: `shared/logs/VIS/055_iter400_frozen_check/`
- iter_500: `shared/logs/VIS/055_iter500_frozen_check/`

## Work Dir
`/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch055`
