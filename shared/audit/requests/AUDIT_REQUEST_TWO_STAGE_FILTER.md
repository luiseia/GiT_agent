# 审计请求 — TWO_STAGE_FILTER
- **审计对象**: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py` (commit `a64a226`)
- **关注点**: 两阶段过滤设计的正确性和潜在风险
- **上下文**: CEO 指导下完成的标签过滤方案, 已合入 master, ORCH_029 即将从零训练

## 已实施的方案

### 两阶段过滤: `vis>=10% + (IoF>=30% OR IoB>=20%)`

**Stage 1 (object-level)**: 可见性过滤
- `vis = clamped_bbox_area / full_bbox_area`
- `vis < 10%` → 整个物体被拒 (返回空 cell_ids)
- 目的: 过滤大部分在画面外的物体 (如 99% 出画面的卡车)

**Stage 2 (cell-level)**: IoF/IoB OR 过滤
- `IoF = intersection(cell, bbox) / cell_area` → 过滤大物体边缘噪声 cell
- `IoB = intersection(cell, bbox) / full_bbox_area` → 保护小目标 (bbox < cell)
- `keep cell if IoF >= 30% OR IoB >= 20%`
- IoB 分母用 **full bbox 面积 (未裁剪)**, 理由: vis 已处理出画面, IoF 已处理大车, IoB 仅需保护小目标 (通常全在画面内, full=clamped)

**验证结果** (20 样本):
- Baseline avg FG: 58.6 → Filtered avg FG: 40.9 (**-30.3%**)
- 对象保留率: 96.9% (185/191), 6 个被 vis<10% 拒
- IoF 丢失: 0% (0 个对象因 cell 过滤而完全丢失)

## 需要 Critic 审查的问题

### 1. 阈值合理性
- `vis>=10%` 是否合理? 是否太宽松 (放过太多出画面物体) 或太激进 (误杀)?
- `IoF>=30%` 是否合理? 含义: cell 至少 30% 被 bbox 覆盖 (约 940/3136 px)
- `IoB>=20%` 是否合理? 含义: bbox 至少 20% 落在这个 cell 内
- 这三个阈值之间是否存在边缘冲突或覆盖缺口?

### 2. IoB 分母选择
- 用 full bbox 面积 vs clamped bbox 面积作为 IoB 分母
- CEO 判断: IoF 已保护大车, IoB 只需保护小目标, 所以用 full bbox 更干净
- 是否存在 CEO 未考虑到的边缘 case? (中等物体部分出画面, vis 刚好过 10%, IoF 不够, IoB 因 full 分母被稀释?)

### 3. 对训练的潜在影响
- FG cell 减少 30% 后, `bg_weight=2.5` 是否需要调整? (正样本变少, 背景比例增大)
- sqrt balance 权重在新标签分布下是否仍合理?
- 兜底策略 (空 cell 时强制选几何中心) 是否会引入新问题? (vis<10% 物体被拒但中心可能在画面内)

### 4. 代码实现审查
- 检查 `_compute_valid_grid_ids()` 方法的实现是否正确
- 特别关注: vis 计算的 clamp 边界 (用 `float(cur_w)` vs 旧版 `cur_w - 1`)
- Stage 1 vis 拒绝后直接返回空 → 调用方 `keep_front[g] = False` → 物体从 GT 中移除. 这是否正确? (vis<10% 的物体是否应该从 GT 中完全移除, 而非仅移除其 cell?)
- polygon_uv (凸包模式) 未应用 IoF/IoB 过滤, 是否是有意为之?

### 5. 与 CEO 后续方案的兼容性
- CEO 提出过 soft loss 加权方案 (边缘 cell 给更小的 loss), 当前 hard 过滤与未来 soft 方案是否兼容?
- 置信度后处理: 过滤后的模型是否更容易通过置信度阈值做 FP 清理?

## 代码位置
- 主文件: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py`
  - `__init__`: line 90-92 (新参数)
  - `_compute_valid_grid_ids`: line 292-405 (核心过滤逻辑)
- Config: `configs/GiT/plan_full_nuscenes_gelu.py` (无需改动, 走默认值)
- 可视化脚本: `GiT_agent/scripts/explore_final.py`
- 可视化结果: `GiT/ssd_workspace/VIS/final_v10_IoF30_IoB20_fullbbox/`

## 截止时间
ORCH_029 已签发, 不 block 训练启动. 但审计结论可能影响是否需要调参或中途修改.
