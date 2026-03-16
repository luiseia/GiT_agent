# Conductor 上下文快照
> 时间: 2026-03-16 07:30 CDT

---

## 当前状态

- **ORCH_056 DONE**: 低 LR 假设失败 (saturation=0.998 @200)
- **ORCH_057 PENDING**: 等待 Critic 审计 `AUDIT_REQUEST_ORCH057_MARKER_NO_POS`
- **所有超参数实验已用尽** → 需要架构级干预

## 关键实验结果

### ORCH_055 崩塌轨迹 (唯一完整 5 点数据)

| iter | Pos slots | Saturation | marker_same | TP |
|------|-----------|-----------|-------------|-----|
| **100** | **750 (62.5%)** | **0.703** | **0.887** | **109** |
| 200 | 954 (79.5%) | 0.820 | 0.962 | 147 |
| 300 | 1010 (84.1%) | 0.873 | 0.973 | 150 |
| 400 | 71 (5.9%) | 0.080 | 0.984 | 0 |
| 500 | 158 (13.2%) | 0.142 | 0.988 | 12 |

### 超参数扫描全表

| ORCH | 干预 | @200 结果 |
|------|------|-----------|
| 049 | bg=5.0, FG/BG=1x | TP=112 (唯一存活) → @500 全阴性 |
| 050 | +dropout=0.5 | 全阴性 (BUG-77 dropout 致死) |
| 051 | bg=3.0, FG/BG=3.3x | 全正饱和 |
| 052 | bg=3.0, FG/BG=1.67x | 全阴性 |
| 053/054 | bg=4.0/5.0 单GPU | 无效 (BUG-78) |
| 055 | bg=5.0 DDP 多点追踪 | @100 HEALTHY → @300-400 相变 |
| 056 | 低 LR (1/5) | 加速模板化, @200 sat=0.998 |

## 下一步: 架构级干预

### ORCH_057: marker_step_no_pos

- marker step (pos_id=0) 不加 grid_pos_embed
- class/box steps 正常使用
- 强制 marker 依赖图像特征决定物体存在性
- 等待 Critic 审计

## 活跃 BUG

| BUG | 结论 |
|-----|------|
| BUG-73 | FG/BG=1x 最优但仍崩塌 |
| BUG-75 | grid_pos_embed shortcut 是根因 → 需架构修改 |
| BUG-77 | cell-level dropout 不可行 |
| BUG-78 | DDP batch=16 是必要条件 |
