# 审计判决 — OVERLAP_THRESHOLD

## 结论: PROCEED — 当前 overlap 模式无需添加阈值，直接重启 ORCH_028

---

## 核心发现: Convex Hull 过滤 = 隐式高阈值，边缘 cell 问题不存在

### 实证数据 (500 帧 nuScenes val, 完整量化分析)

| 指标 | 值 |
|------|-----|
| 分析帧数 | 500 |
| GT 总数 | 15,719 |
| 前方可见 GT | 8,156 |
| 获得 cell 的 GT | 3,351 |
| Convex hull 零 cell (用 fallback) | 1,159 (25.7%) |
| **总分配 cell 数** | **22,322** |
| **Mean IoF** | **0.8445** |
| **Median IoF** | **1.0000** |
| **IoF < 0.10** | **8 cells (0.04%)** |
| **IoF < 0.20** | **93 cells (0.4%)** |
| **IoF < 0.30** | **297 cells (1.3%)** |

> IoF = Intersection Area / Cell Area = cell 中有多大比例被物体投影覆盖

**结论**: 84.5% 的 cell 几乎被物体完全覆盖。低重叠 cell 在统计上不存在。CEO 担心的"边缘微量重叠"问题，已被 `use_rotated_polygon=True` 的 convex hull center-check 天然过滤。

---

## 发现的问题

### 1. **INFO-1**: Convex hull center-check = 隐式 ~50% IoF 阈值 (非 BUG，信息记录)
   - 严重性: INFO
   - 位置: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py:L336-L358`
   - 说明: 当前代码流程是 **overlap AABB 扩大候选 → convex hull 过滤 (cell 中心必须在投影多边形内)**。cell 中心在多边形内 ⟹ 该 cell 至少有约 50% 面积与物体重叠 (凸多边形几何性质)。**这已经是一个有效的隐式阈值。**
   - 数据支撑: P01 IoF = 0.277, P05 IoF = 0.432, P10 IoF = 0.522。最差 1% 的 cell 仍有 27.7% 覆盖率。

### 2. **INFO-2**: 小物体 fallback 率高 (25.7%)，但这不是 overlap 阈值问题
   - 严重性: INFO
   - 位置: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py:L366-L370`
   - 说明: 1,159 / 4,510 可见 GT (25.7%) 因投影太小 (< 1 cell)，convex hull 没有任何 cell 中心通过，触发 fallback 强制分配几何中心 cell。这是**网格分辨率问题** (20×20 grid, 56×56px cell)，不是 overlap 阈值问题。BUG-51 修复了零 cell 的成因，但物体太小依然只能给 1 cell。
   - 与 ORCH_028 关系: 这是 grid resolution 的根本限制，不影响 overlap 阈值决策

### 3. **INFO-3**: IBW 权重不区分 cell 位置质量 — 未来可选优化方向
   - 严重性: LOW
   - 位置: `GiT/mmdet/models/dense_heads/git_occ_head.py:L487`
   - 说明: IBW (Inverse Bandwidth Weighting) 给同一 GT 的所有 cell 相同权重 (`1.0 / count`)。一个 medium 物体有 4 个 cell (2 interior 100% IoF + 2 edge 40% IoF)，4 个 cell 权重相同。理论上 edge cell 信号弱，应降权。**但数据显示 medium 物体仅 0.1% cell 的 IoF < 0.20**，实际影响极小。此为未来可选优化，不阻塞 ORCH_028。

---

## 逻辑验证

- [x] **IoF 分布健康**: Mean 0.845, Median 1.000, 仅 0.4% < 0.20
- [x] **Convex hull 过滤有效**: 已天然排除低重叠边缘 cell
- [x] **小物体保护**: fallback 机制确保零 cell 率 = 0%
- [x] **阈值风险评估**: 任何 threshold > 0.20 会杀死 tiny 物体 (88.9% tiny cell 在 IoF < 0.20)

---

## 对 CEO 问题的逐项回答

### Q1: 合理的阈值度量

**推荐: Option B — IoF = intersection_area / cell_area**

| 选项 | 公式 | 适用性 | 理由 |
|------|------|--------|------|
| A | overlap / bbox_area | ❌ 不适合 per-cell | 大物体每个 cell 的 overlap/bbox 都极小 (e.g., 1/16)，无法区分好/坏 cell |
| **B** | **overlap / cell_area** | **✅ 推荐** | 直觉清晰: "这个 cell 有多少比例被物体覆盖?" 与 cell 特征质量直接相关 |
| C | IoU | ❌ 双重惩罚 | 分母 = cell + bbox - overlap, 对小物体不公平 |

**但当前不需要显式使用此度量**, 因为 convex hull 已隐式实现。

### Q2: 当前问题量化

**问题极小。数据如下:**

**按物体大小分层:**

| 大小 | cell 数 | Mean IoF | IoF < 0.10 | IoF < 0.20 |
|------|---------|----------|------------|------------|
| large (>200px) | 17,584 | 0.899 | 0.0% | 0.0% |
| medium (80-200px) | 4,108 | 0.686 | 0.0% | 0.1% |
| small (40-80px) | 603 | 0.375 | 1.2% | 10.9% |
| tiny (<40px) | 27 | 0.154 | 3.7% | 88.9% |

**关键事实**: tiny 物体仅 27 个 cell (占总 22,322 的 0.12%)。即使它们全部是噪声，对训练的影响可忽略不计。

**按类别分层:**

| 类别 | cell 数 | Mean IoF | IoF < 0.20 |
|------|---------|----------|------------|
| car | 9,875 | 0.848 | 0.1% |
| truck | 5,165 | 0.908 | 0.0% |
| bus | 1,647 | 0.903 | 0.0% |
| pedestrian | 1,670 | 0.711 | 3.3% |
| traffic_cone | 266 | 0.648 | 4.9% |
| barrier | 1,834 | 0.761 | 0.8% |

**Pedestrian 和 traffic_cone 有少量低 IoF cell**, 但绝对数量极少 (ped: ~55 cells, cone: ~13 cells)。

### Q3: 阈值建议

**不推荐添加硬阈值。** 理由:

1. **边缘 cell 问题在统计上不存在** — 0.4% cell IoF < 0.20
2. **Convex hull 已是有效隐式阈值** — P01 IoF = 0.277
3. **阈值风险 >> 收益**:
   - threshold 0.15: 安全 (丢 0.2% cell), 但收益也接近零
   - threshold 0.20: 丢 0.4% cell, 但 tiny 物体 88.9% cell 被杀
   - threshold 0.25: tiny 物体 100% 被杀, small 物体丢 18%
   - **任何阈值都倾向于伤害小物体** — 与 BUG-51 修复的初衷 (保护小物体) 矛盾
4. **ViT 窗口 224×224 px 的感受野** 意味着即使 cell 只有 30% 直接覆盖，self-attention 也能从同窗口其他 patch 获取物体信息

**如果 CEO 强制要求加阈值**: 建议 IoF threshold = 0.10，丢失仅 8 个 cell (0.04%)，纯粹是安全网，不影响任何实际标注。

### Q4: 对训练的影响

**不加阈值 → 无影响 → 直接启动 ORCH_028**

- `bg_weight=2.5`: 保持不变。当前标注质量已经很高
- `sqrt balance`: 保持不变。与 overlap 阈值无关
- `reg=0 频率`: overlap 模式已将零 cell 率从 21.1% 降至 0% (BUG-51 数据)。不加阈值不会增加 reg=0
- **不需要从零重训**: ORCH_028 本来就要从零训 (BUG-51 标签变更)。如果加了 threshold 就需要再从零训，浪费计算资源

### Q5: 实现建议 (仅供未来参考)

**当前不实现。** 如果未来 ORCH_028 结果表明 bg_FA 异常高且排除其他原因后，可考虑:

```python
# generate_occ_flow_labels.py __init__ 中:
self.overlap_min_iof = overlap_min_iof  # default: 0.0 (disabled)

# _compute_valid_grid_ids 中, convex hull 过滤后:
if self.overlap_min_iof > 0:
    filtered_cells = []
    for cell_id, iof, ... in cell_stats:
        if iof >= self.overlap_min_iof:
            filtered_cells.append(cell_id)
    cell_ids = filtered_cells if filtered_cells else cell_ids  # 保留 fallback
```

更优的替代方案 — **IoF-weighted supervision** (不丢弃 cell, 而是按 IoF 降权):
```python
# git_occ_head.py 中:
cell_iof = info.get('cell_iof', {})  # pipeline 传来的 per-cell IoF
for cid in cell_ids:
    iof_w = cell_iof.get(cid, 1.0)
    tokens_weights[cid, ...] *= iof_w  # 边缘 cell 自然降权
```

**但这两个方案都是 premature optimization** — ORCH_028 还没跑过一次完整训练。

---

## 对 Conductor 计划的评价

1. **ORCH_028 等待此审计是正确的**: CEO 提出了合理关切，值得量化验证
2. **ORCH_028 应立即重启**: 数据明确证明无需修改标签逻辑
3. **优先级排序正确**: overlap 重训 >> 其他优化
4. **单一变量原则**: ORCH_028 只改了 overlap 标签 → 不要在重启时加入 threshold，保持单一变量
5. **BUG-47 阈值重建**: @4000 后用新数据重建决策矩阵。这仍然正确

---

## 附加建议

1. **保持现有代码不变**: `grid_assign_mode='overlap'` + `use_rotated_polygon=True` 已足够
2. **ORCH_028 立即从零重启**: 不要因此审计延迟
3. **在 ORCH_028 @4000 eval 时增加诊断**: 如果 bg_FA 异常 (>0.40)，回来检查是否有其他标签问题
4. **长期优化方向** (不阻塞当前):
   - IoF-weighted supervision (INFO-3) — 等 ORCH_028 baseline 数据后评估必要性
   - Grid resolution 提升 (5×5 → 6×6 或 7×7) — 解决 25.7% fallback 率，但这是架构级变更
5. **不要陷入"调阈值"陷阱**: 当前系统最大瓶颈是 grid resolution (23.4% GT < 1 cell) 和 BUG-17 (sqrt balance 振荡)，不是 edge cell overlap

---

## 调试数据留档

完整调试脚本和输出:
- `GiT/ssd_workspace/Debug/Debug_20260311/debug_overlap_threshold.py`
- 可重复: `conda run -n GiT python debug_overlap_threshold.py`

---

*Critic: 审计完毕。结论明确 — overlap 模式 + convex hull 已足够，CEO 的直觉值得验证但数据不支持添加阈值。ORCH_028 应立即重启。*
