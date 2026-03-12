# BUG-52 分析报告: IoF/IoB 死代码为什么标为 ACCEPTED

> 时间: 2026-03-12
> 应 CEO 要求撰写

---

## BUG-52 是什么

在 `generate_occ_flow_labels.py` 的两阶段过滤中，Stage 2 的 IoF/IoB 过滤 (`min_iof=0.30, min_iob=0.20`) **从未被执行**。

代码结构：
```python
# L365: polygon_uv 路径 (convex hull center-check)
if polygon_uv is not None and len(polygon_uv) >= 3:
    # convex hull 过滤 — IoF/IoB 从未被计算
    ...

# L388: IoF/IoB 路径 (仅在无 polygon_uv 时执行)
elif use_iof_iob_filter:
    # IoF/IoB 过滤 — 仅在 polygon_uv 为 None 时到达
    ...
```

config 设置了 `use_rotated_polygon=True`，使得 **99.4% 的可见 GT** (3431/3453) 有非空 `polygon_uv`，全部走 convex hull 路径，**完全跳过 IoF/IoB**。

---

## 为什么标为 ACCEPTED（不修复）

### 原因 1: Convex hull 已提供等效保护

Critic 审计用调试脚本 (`debug_two_stage_filter_audit.py`) 在 200 帧 val 数据上做了三种方法对比：

| 方法 | 描述 | 每帧平均 FG cells |
|------|------|-----------------|
| **A (实际训练)** | convex hull center-check | **33.1** |
| B (explore_final) | AABB + IoF/IoB | 41.0 |
| **C (意图设计)** | convex hull + IoF/IoB 叠加 | **33.0** |

**方法 A ≈ 方法 C (差异仅 0.1%)**。convex hull 的隐式过滤效果已经和 IoF/IoB 等价甚至更严格。加上 IoF/IoB 几乎没有增量收益。

### 原因 2: 修复有成本，收益为零

如果要"修复"BUG-52，需要：
1. 在 convex hull 分支 (L386-387) 之后追加 IoF/IoB 检查
2. 重新测试确认无回归
3. 如果 ORCH_029 正在训练，要么等结束要么中断重启

所有这些工作换来的效果：FG cells 额外减少 **0.1%**。不值得。

### 原因 3: 当前行为没有危害

IoF/IoB 的目的是"过滤边缘噪声 cell"。Convex hull center-check 做了同样的事 — 它只保留几何中心落在 convex hull 内部的 cell，自然排除了边缘低重叠的 cell。

Critic 验证了 convex hull 路径的 IoF 分布：
- Mean IoF = 0.845（被保留的 cell 平均有 84.5% 的面积重叠）
- P01 IoF = 0.277（最差 1% 的 cell 也有 27.7% 重叠，接近 IoF≥30% 的阈值）

即使不显式检查 IoF/IoB，convex hull 隐式地实现了类似的阈值效果。

---

## 我们实际用了什么

ORCH_029 的实际过滤链是：
1. **Stage 1**: `vis ≥ 10%` — 移除大部分出画面的物体 ✅
2. **Stage 2**: `convex hull center-check` — 保留几何中心在投影区域内的 cell ✅
3. ~~IoF ≥ 30% OR IoB ≥ 20%~~ — **未执行（死代码）**

MASTER_PLAN 和 ORCH_029 配置清单中标注 `min_iof=0.30, min_iob=0.20` 为 "NEW" 是**误导性的**，这两个参数对 99.4% 的 GT 没有效果。

---

## 如果 CEO 认为必须修复

如果认为代码应该真正使用 IoF/IoB，修复方式很简单：

```python
# 在 convex hull 路径内追加 IoF 检查
if polygon_uv is not None and len(polygon_uv) >= 3:
    for idx, (r, c) in enumerate(rc_pairs):
        if inside[idx]:
            iof = compute_iof(cell_box, gt_box)  # 新增
            if iof >= min_iof or iob >= min_iob:  # 新增
                cell_ids.append(...)
```

但基于数据，这只会额外移除 ~0.1% 的 FG cells，对训练指标不会有可测量的影响。

---

## 结论

BUG-52 ACCEPTED 是因为：
- Convex hull 已经在做 IoF/IoB 该做的事（定量验证差异 0.1%）
- 修复成本 > 收益
- 当前行为没有危害

**需要修正的是认知和文档**，而不是代码：团队应知道实际生效的是 `overlap + vis + convex hull`，不包含 IoF/IoB。
