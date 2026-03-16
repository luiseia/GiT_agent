# Conductor 上下文快照
> 时间: 2026-03-16 16:20 CDT

---

## 当前状态

- **ORCH_059 完成**: bias init 改变崩塌方向(全正→全负)但不阻止模板化
- **11 轮实验 (049-059) 全部未能阻止 marker_same 上升至 ~1.0**
- **等待 CEO 决策下一方向**

## 核心问题

**marker_same 不可逆上升** — 所有实验共同现象:
- 超参数调整 (FG/BG, LR): 改变崩塌方向，不改模板化
- 架构干预 (dropout, 移除 grid_pos_embed): 破坏多样性/定位
- 初始化修复 (bias init): 改变方向，不改模板化

grid_pos_embed → marker 的映射是强 shortcut，当前框架下无法阻止。

## 实验全表

| ORCH | 干预 | @100 sat | @500 sat | marker_same趋势 |
|------|------|----------|----------|----------------|
| 055 | baseline (bg=5.0) | 0.703 | 0.142 | 0.887→0.988 |
| 059 | +bias init | 0.253 | 0.025 | 0.963→0.995 |
| 051 | FG/BG=3.3x | @200 全正 | — | — |
| 052 | FG/BG=1.67x | @200 全阴 | — | — |
| 050 | +dropout | @200 全阴 | — | — |
| 057 | marker_no_pos | @100 全正 | — | — |
| 056 | 低LR | @200 全正 | — | — |

## 待 CEO 决策

1. grid_pos_embed 噪声/shuffle
2. 二元 marker (4-class→2-class)
3. marker 独立 head
4. 接受现状长训练
5. 回退到 ORCH_024 架构

## 恢复指令

1. 读本文件
2. 读 MASTER_PLAN.md
3. 检查 CEO_CMD.md
