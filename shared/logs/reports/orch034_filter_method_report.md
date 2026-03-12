# ORCH_034 当前过滤方式报告

> 应 CEO 要求 | 2026-03-12

---

## 当前 ORCH_034 使用的过滤链

训练日志确认的 config 参数：
```
grid_assign_mode = 'overlap'
use_rotated_polygon = True
min_iof = 0.30    (代码默认值，config 未显式覆盖)
min_iob = 0.20    (代码默认值，config 未显式覆盖)
min_vis_ratio = 0.10  (代码默认值)
```

### 实际执行的三级过滤流程

```
3D GT Box
  │
  ▼
[投影到 2D 图像] → 8个角点 → (u_img, v_img)
  │
  ▼
Stage 0: AABB 候选范围
  overlap 模式: 任何与投影 bounding box 有重叠的 cell 都是候选
  │
  ▼
Stage 1: 可见性过滤 (object-level)
  vis_ratio = 裁剪后面积 / 原始 bbox 面积
  vis_ratio < 0.10 → 整个物体被拒绝 (出画面太多)
  │
  ▼
Stage 2a: Convex Hull 中心点检测 ← ★ 你问的
  use_rotated_polygon=True → 用投影角点构造 convex hull
  只有 cell 中心落在 convex hull 内部的 cell 才进入下一步
  │
  ▼
Stage 2b: IoF/IoB 过滤 (BUG-52 修复后新增)
  对通过 convex hull 的 cell，再计算:
  - IoF = (cell 与 clamped bbox 交集面积) / cell 面积
  - IoB = (cell 与 clamped bbox 交集面积) / 完整 bbox 面积
  - IoF ≥ 0.30 OR IoB ≥ 0.20 → 保留为正样本
  - 否则 → 拒绝
  │
  ▼
最终 cell_ids (正样本)
```

---

## Convex Hull 是什么

### 直观解释

Convex Hull（凸包）就是**用一根橡皮筋套住一组点，橡皮筋收紧后形成的形状**。

在我们的场景里：
1. 一个 3D GT box 有 8 个角点
2. 这 8 个角点投影到 2D 图像上，得到 8 个 (u, v) 坐标
3. 其中部分在相机前方（`valid_z`），比如 5-8 个有效点
4. 对这些有效 2D 点做 Convex Hull → 得到一个**凸多边形**（通常是 4-8 边形）

### 为什么不用 AABB (axis-aligned bounding box)

```
AABB (矩形包围框):          Convex Hull (凸包):
┌─────────────────┐         ╔══════════╗
│  ████████        │         ║ ████████ ║
│ ██████████       │         ║██████████║
│████████████      │         ╠══════════╣
│  ██████████      │          ╚════════╝
│    ████████      │
└─────────────────┘

█ = 物体实际投影区域
AABB 包含大量空白区域     Convex Hull 更贴合实际形状
→ 更多无关 cell 被标为正样本  → 只保留真正覆盖的 cell
```

3D 物体投影到 2D 后通常**不是矩形**——它是一个旋转的、透视变形的多边形。用 AABB 会包含很多实际不属于该物体的 cell（尤其是斜着的车辆），导致错误的正样本标签。Convex Hull 更贴合投影的真实形状。

### 代码实现

```python
# 1. 构造 convex hull
from scipy.spatial import ConvexHull
hull = ConvexHull(polygon_uv)           # polygon_uv = 投影后的有效2D角点
hull_pts = polygon_uv[hull.vertices]    # 取凸包顶点，逆时针排列

# 2. 判断 cell 中心是否在凸包内 (cross product test)
for i in range(N):  # 遍历凸包的每条边
    edge = p2 - p1                      # 边向量
    to_query = query_pts - p1           # 点到边起点的向量
    cross = edge[0] * to_query[:,1] - edge[1] * to_query[:,0]
    inside &= (cross >= 0)             # 叉积 ≥ 0 → 点在边的左侧（内侧）
```

原理：如果一个点在凸多边形**每条边的左侧**（逆时针方向），那它就在多边形内部。这就是 cross product test。

### 实际效果

根据之前 Critic 审计 (BUG-52 分析，200 帧 val 数据)：

| 方法 | 描述 | 每帧平均 FG cells |
|------|------|----|
| AABB only | 矩形包围框 | 41.0 |
| **Convex Hull** | 凸包中心检测 | **33.1** |
| Convex Hull + IoF/IoB | 凸包 + 面积重叠度 | **33.0** |

Convex Hull 比 AABB 减少了约 **19%** 的正样本 cell——这些被移除的 cell 是 AABB 矩形的角落区域，虽然在包围框内但实际不覆盖物体。

---

## 总结

ORCH_034 使用的是**三级过滤**：
1. **vis ≥ 10%** — 排除大部分出画面的物体
2. **Convex Hull center-check** — 只保留 cell 中心在物体投影凸包内的 cell
3. **IoF ≥ 0.30 OR IoB ≥ 0.20** — 进一步验证 cell 与物体的面积重叠度

其中 Convex Hull 是核心过滤步骤，IoF/IoB 是 BUG-52 修复后新增的补充验证（实测额外减少 ~0.1% cell）。
