# 审计判决 — TWO_STAGE_FILTER

## 结论: CONDITIONAL — ORCH_029 可继续训练，但必须了解 Stage 2 IoF/IoB 实际未生效

---

## 发现的问题

### 1. **BUG-52**: Stage 2 IoF/IoB 过滤是死代码 (`use_rotated_polygon=True` 时)
   - 严重性: **HIGH** (文档/实现不一致，团队认知与实际行为脱节)
   - 位置: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py:L365-L403`
   - 描述:

代码结构:
```python
# L365: polygon_uv 路径 (convex hull center-check, 无 IoF/IoB)
if polygon_uv is not None and len(polygon_uv) >= 3:
    # ... convex hull filter — IoF/IoB 从未被计算
    for idx, (r, c) in enumerate(rc_pairs):
        if inside[idx]:
            cell_ids.append(...)

# L388: IoF/IoB 路径 (仅在无 polygon_uv 时执行)
elif use_iof_iob_filter:
    # ... IoF/IoB filter — 仅在 polygon_uv 为 None 时到达
    if iof >= min_iof or iob >= min_iob:
        cell_ids.append(...)
```

`plan_full_nuscenes_gelu.py:L285` 设置 `use_rotated_polygon=True`。这使得 `polygon_uv` 对 **99.4% 的可见 GT** 非空 (3431/3453)。这些 GT 全部走 convex hull 路径 (L365)，**完全跳过 IoF/IoB 过滤** (L388)。

仅 **22 个 GT** (0.6%) 因投影角点 < 3 个而走 IoF/IoB 路径。

**后果**: MASTER_PLAN 声称 "Stage 2: IoF≥30% OR IoB≥20% 过滤边缘噪声 cell"，ORCH_029 配置清单标注 `min_iof=0.30, min_iob=0.20` 为 "NEW"。但这两个参数对训练 **几乎无影响**。团队以为有三个改动 (overlap + vis + IoF/IoB)，实际只有两个 (overlap + vis)。

   - 修复建议:
     - **Option A (推荐)**: 不改代码。Convex hull center-check 已是有效过滤 (Mean IoF = 0.845, P01 = 0.277, 见 VERDICT_OVERLAP_THRESHOLD)。在 convex hull 路径内再叠加 IoF/IoB 过滤几乎无增量效果 (方法 A vs C 差异仅 +0.1%)。**更新文档说明 IoF/IoB 被 convex hull 替代即可。**
     - **Option B**: 将 IoF/IoB 过滤应用到 convex hull 路径内部 (先 convex hull 再 IoF/IoB)。效果: FG cell 额外减少 ≈0.1%。不值得实现复杂度。

### 2. **BUG-53**: `explore_final.py` 验证与实际训练行为不一致
   - 严重性: **MEDIUM** (误导性验证数据)
   - 位置: `GiT_agent/scripts/explore_final.py:L59-L91` vs `GiT/...generate_occ_flow_labels.py:L365-L403`
   - 描述:

| | explore_final.py (验证) | 实际训练代码 |
|---|---|---|
| cell 过滤方式 | **AABB + IoF/IoB** (无 convex hull) | **Convex hull center-check** (无 IoF/IoB) |
| 每帧平均 FG cells | **41.0** | **33.1** |
| 相对差异 | — | **比验证结果少 19.3%** |

MASTER_PLAN 引用 "FG cell 减少 30.3%" 基于 explore_final.py 的数据 (baseline 58.6 → filtered 40.9)。但实际训练产出 FG = 33.1，比 explore_final 的 "filtered" 还少。

**好消息**: 实际训练行为**比验证更严格**，不存在"比预期更多噪声 cell"的风险。只是 Conductor 对 FG 数量的预期偏高。

   - 修复建议: 更新 MASTER_PLAN 中的 FG 统计数据。备注: explore_final.py 未使用 convex hull，仅作为近似参考。

### 3. **INFO-4**: vis filter 使用 AABB 面积作为分母，对极近物体可能过度拒绝
   - 严重性: **LOW**
   - 位置: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py:L326`
   - 描述: vis_ratio = clamp_area / full_bbox_area。`full_bbox_area` 基于投影 AABB (包括 `safe_Z=1e-3` 极端投影)。物体紧贴相机 (部分角点 z→0) 时，投影 AABB 可达数万像素，使 vis_ratio 极低。这些物体实际在画面内可见面积可能不小，但会被 vis < 10% 拒绝。
   - 缓解: nuScenes 前摄 FOV 有限，紧贴相机的物体罕见。10% 阈值足够宽松。不需要修复。

### 4. **INFO-5**: polygon_uv (convex包) 路径不受 Stage 2 过滤，属设计遗漏而非 intentional
   - 严重性: **INFO** (代码意图不清晰)
   - 位置: `GiT/mmdet/datasets/pipelines/generate_occ_flow_labels.py:L365-L387`
   - 描述: 审计请求 Q4 问 "polygon_uv 未应用 IoF/IoB 过滤, 是否有意为之?" 答案: **不是有意为之**。代码结构是新增 IoF/IoB 时加在了 `elif` 分支，没有注意到 polygon_uv 分支先于 IoF/IoB 分支。但这不是问题，因为 convex hull 过滤效果 ≥ IoF/IoB (方法 A ≈ C)。

---

## 逻辑验证

- [x] **vis 计算正确性**: clamp 边界用 `float(cur_w)` 而非旧版 `cur_w-1`。对连续坐标系更正确。边界安全 clamp (L349-352) 保护越界。无 bug。
- [x] **IoF/IoB 计算正确性 (死代码路径)**: intersection 计算 (L393-399) 数学正确。IoB 用 full_bbox_area 作分母 (L401) 符合 CEO 意图。只是此路径不被执行。
- [x] **vis 拒绝后的行为**: vis < 10% 返回空 cell_ids → 调用方 `keep_front[g] = False` → 物体从 GT 移除。正确: 大部分出画面的物体不应作为训练 target。
- [x] **兜底策略**: cell_ids 为空时强制选几何中心 (L411-415)。vis 拒绝在此之前返回 (L331)，不触发兜底。兜底仅用于通过 vis 但 convex hull 给零 cell 的小物体。正确。
- [x] **full_bbox_area 重复计算**: L326 (Stage 1) 和 L361 (Stage 2) 各算一次。微小低效，非 bug。

---

## 对审计请求的逐项回答

### Q1: 阈值合理性
- **vis >= 10%**: 合理且宽松。48% 可见 GT 被拒 (大多真的在画面外)。10% 足以保护部分出画面但仍可见的物体。
- **IoF >= 30%**: 合理但**死代码**。convex hull 隐式提供 P01=27.7% 的阈值，效果更优。
- **IoB >= 20%**: 保护小目标的设计正确但**死代码**。小目标本就通过 convex hull + fallback 获得 cell。
- **边缘冲突**: 不存在。三个阈值设计在理论上互补。但 Stage 2 未实际执行。

### Q2: IoB 分母选择
- CEO 判断正确: IoF 处理大车边缘, IoB 保护小目标, 用 full bbox 简洁合理。
- **CEO 未考虑到的边缘 case**: 中等物体部分出画面, vis 刚过 10%, IoF 不够, IoB 因 full 分母被稀释？
  - 理论上存在，但 vis >= 10% 已保证至少 10% 可见面积。对中等物体 (80-200px 投影)，10% 可见意味着 8-20px 可见宽度，仅 1-2 cell。这些 cell 的 IoF 可能低 (~15-30%)，IoB 也低 (cell 面积 / huge full bbox)。
  - **但此 case 的 IoF/IoB 过滤是死代码，所以不影响训练。** Convex hull 路径仍正常工作。

### Q3: 对训练的潜在影响
- **FG cell 减少**: 实际训练 FG = 33.1/frame (vs convex hull 无 vis 时 ~44-50/frame)。减少约 25-35%，主要来自 vis filter 移除出画面物体。
- **bg_weight=2.5**: 正样本变少 → FG:BG 比例变化。bg_weight 可能需要下调 (如 2.0-2.2)。**但建议先跑 ORCH_029 baseline，@4000 看数据再决定**。Premature 调参不如先观察。
- **sqrt balance**: 类别分布因 vis filter 变化 (远处小物体如 pedestrian/cone 更多被过滤)。sqrt balance 自适应，无需手动调。但如果特定类 (如 pedestrian) 大量被 vis 过滤，其训练比重会自动降低。
- **兜底策略**: vis < 10% 物体被完全移除 (不是降为 1 cell 而是彻底移除)。不会引入新的兜底问题。

### Q4: 代码实现审查
- **vis 计算**: `float(cur_w)` vs `cur_w-1` — 更正确，无 bug (见逻辑验证)。
- **Stage 1 拒绝 → 物体移除**: 正确。vis < 10% 的物体确实应从 GT 中完全移除。
- **polygon_uv 未应用 IoF/IoB**: 非有意为之，是代码结构遗漏 (见 INFO-5)。但效果等价。

### Q5: 与 CEO 后续方案的兼容性
- **soft loss 加权**: 当前 hard 过滤 (binary 留/弃) 与未来 soft 方案兼容。两者可叠加: hard 过滤先移除最差 cell, soft 权重再对剩余 cell 按 IoF 降权。但需要在 convex hull 路径中额外计算 IoF 并传递给 head。当前架构不传递 per-cell IoF。
- **置信度后处理**: 过滤后模型训练标签更干净 → 模型对真实前景 cell 置信度更高, 对背景 cell 置信度更低 → 更容易用 confidence threshold 区分 FP。理论上有利。

---

## 需要 Admin 协助验证（如有）

无。BUG-52 是文档/实现不一致问题，不需要跑实验验证。Convex hull 的等效性已由调试脚本定量证明 (方法 A vs C 差异 0.1%)。

---

## 对 Conductor 计划的评价

1. **ORCH_029 可继续**: 两阶段过滤的 Stage 1 (vis filter) 有效且正确。Stage 2 (IoF/IoB) 虽是死代码，但 convex hull 提供等效保护。实际训练行为健康。
2. **MASTER_PLAN "FG cell -30.3%" 统计需纠正**: 基于 explore_final.py 的 AABB 逻辑，非训练实际行为。实际 FG 更低 (33.1 vs 41.0)。
3. **ORCH_029 配置清单有误导**: 标注 `min_iof=0.30, min_iob=0.20` 为 "NEW"，暗示有效改动。实际这两个参数对 99.4% 的 GT 无效。应注明。
4. **bg_weight=2.5 未调**: 正确。先跑 baseline 看数据，不要 premature 调参。
5. **优先级排序正确**: overlap 重训 >> 其他。两阶段过滤是单一变量实验的合理延伸。
6. **遗漏风险**: Conductor 未注意到 vis filter 对类别分布的不对称影响。远处小物体 (pedestrian, traffic_cone) 更容易被 vis 过滤。如果 ORCH_029 这些类表现异常差 (比 ORCH_024 还差)，需考虑 vis filter 是否过度拒绝了它们。**建议 @4000 时分类对比 vis=0 和 vis=0.10 的 GT 分布差异**。

---

## 附加建议

1. **不修改代码, 不重启 ORCH_029**: 当前行为 (convex hull + vis) 是健康的。IoF/IoB 死代码不造成危害。改代码重启浪费 GPU 时间。
2. **更新认知**: Conductor 和 CEO 需了解实际生效的过滤是 `convex hull center-check + vis >= 10%`，而非 `IoF/IoB + vis`。这影响后续分析和调参决策。
3. **如果未来要真正启用 IoF/IoB**: 需在 convex hull 分支 (L386-387) 之后追加 IoF/IoB 检查。但从数据看不值得 (额外减少仅 0.1% cells)。
4. **监控点**: @4000 对比 ORCH_024 时，注意实际 FG/BG 比率变化。如果 bg_FA 大幅改善 (< 0.20) 说明 vis filter + overlap 标签有效。如果 bg_FA 反而更高，说明问题不在标签噪声。

---

## 调试数据留档

- `GiT/ssd_workspace/Debug/Debug_20260311/debug_two_stage_filter_audit.py`
  - 三种方法对比: A (实际训练) vs B (explore_final) vs C (意图)
  - 200 帧 val, 定量结论: A=33.1, B=41.0, C=33.0 FG/frame

---

*Critic: IoF/IoB 设计优美但从未上场。Convex hull 默默做了同样的事。ORCH_029 的真正改变是 overlap 标签 + vis 过滤 + clamp 边界修正，不含 IoF/IoB。认清现实后继续训练。*
