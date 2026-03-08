# Supervisor 摘要报告
> 时间: 2026-03-08 00:14
> Cycle: #135

## ===== P5b (plan_i) 训练已启动! 三项修复就位, iter 330/6000, warmup 阶段 =====

### 训练状态
- 当前实验: **P5b (plan_i_p5b_3fixes)**
- 进度: iter 330 / 6000 (**5.5%**)
- 启动时间: 23:56:39
- LR: warmup 阶段, base_lr=3.30e-05 (爬升中), lr=1.65e-06
- warmup 结束: iter 500 (~00:22)
- GPU: 0 (20.5GB, 100%) + 2 (21.0GB, 100%)
- ETA 完成: ~05:00

### P5b 三项修复验证

**修复 1: 双层投影 — ✓ 已生效**
```
unexpected key: backbone.patch_embed.proj.weight, proj.bias (旧单层)
missing keys: backbone.patch_embed.proj.0.weight, proj.0.bias, proj.2.weight, proj.2.bias (新双层)
```
旧 Linear(4096,768) 权重被丢弃, Sequential(Linear(4096,1024), GELU, Linear(1024,768)) 随机初始化。

**修复 2: LR Milestones — 待验证 @2500**
- warmup=500, begin=500, milestones=[2000,3500]
- 预期 decay: iter 2500 (相对 milestone 2000 + begin 500) 和 iter 4000
- 验证点: iter 2500 的 lr 应从 ~2.5e-06 降至 ~2.5e-07

**修复 3: sqrt 类别权重 — 待验证 (需查看权重日志或代码)**

### P5b 前 330 iter 指标

| 指标 | P5b 前 330 iter | P5 前 330 iter (对照) |
|------|----------------|---------------------|
| Memory | 15867 MB | 15757 MB (+110 MB, 双层投影开销) |
| Loss 范围 | 0.97 - 4.92 | 类似高波动 |
| grad_norm 峰值 | 70.2 | 247.8 (P5更高) |
| LR@300 | 1.50e-06 | 1.50e-06 (相同) |

grad_norm 峰值从 P5 的 247 降至 70, 可能与双层投影的渐进压缩有关。

### 代码变更
GiT/ 无新 commit。Admin 创建了独立可视化脚本 `scripts/visualize_polygon_vs_aabb.py`。

## ORCH 指令状态

| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_001-008 | COMPLETED | 历史指令 |
| **ORCH_009** | **COMPLETED** | 旋转多边形可视化完成, 10 张图保存到 `/mnt/SSD/GiT_Yihao/polygon_viz/` |
| **ORCH_010** | **执行中** | P5b 训练已启动 (plan_i_p5b_3fixes) |
| **ORCH_011** | **DELIVERED** | SSD 迁移 — work_dirs 仍为普通目录 (非软链接), 待确认执行状态 |

### ORCH_009 完成详情
Admin 在 00:06 完成, 独立脚本实现, 未修改训练代码。代表性统计:
- car: AABB 12→Poly 10 (排除 2 cell)
- car: AABB 16→Poly 12 (排除 4 cell, 最大差异)
- bus: AABB 4→Poly 3 (排除 1 cell)

## Agent 状态
全 5 agent tmux UP。

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 20.5 GB | 100% | **P5b 训练** |
| 1 | 15 MB | 0% | 空闲 |
| 2 | 21.0 GB | 100% | **P5b 训练** |
| 3 | 15 MB | 0% | 空闲 |

## 告警
1. **[RUNNING] P5b 训练已启动**: plan_i_p5b_3fixes, 从 P5@4000 加载, 三项修复就位
2. **[VERIFIED] 双层投影生效**: 4096→1024→768, 显存 +110 MB
3. **[COMPLETED] ORCH_009**: 旋转多边形可视化完成
4. **[PENDING VERIFY] LR milestones**: 需在 iter 2500 确认 decay 触发
5. **[UNCLEAR] ORCH_011 SSD 迁移**: work_dirs 仍为普通目录, 未见软链接
6. **[WATCH] 首次 val @500 (~00:22)**: P5b 首次评估, warmup 刚结束
