# Conductor 工作上下文快照
> 时间: 2026-03-07 22:30
> 循环: #51 (Phase 1 完成)
> 目的: Context compaction 备份

---

## 当前状态

### P5 训练 — RUNNING (84%, LR DECAYED!)
- **PID**: 1572 | GPU 0 (20.4GB) + 2 (20.9GB)
- **进度**: iter 5020 / 6000
- **LR**: 2.5e-07 (**×0.1 decay 已生效! @iter 5000**)
- **grad_norm**: 28.4→7.8 (decay 后立即下降)
- **ETA 完成**: ~23:07
- **下次 val**: @5500 (~22:47) — LR decay 后首次 val, 关键!

### P5 Val 轨迹 (关键 checkpoint)

| 指标 | P5@4000 (最优) | P5@4500 | **P5@5000** | P4@4000 | 红线 |
|------|---------------|---------|-------------|---------|------|
| car_R | 0.569 | 0.529 | **0.615** | 0.592 | — |
| car_P | 0.090 | 0.091 | **0.085** | 0.081 | — |
| truck_R | 0.421 | 0.317 | **0.199** | 0.410 | <0.08 |
| truck_P | 0.130 | 0.095 | **0.086** | 0.175 | — |
| bus_R | 0.315 | 0.058 | **0.002** | 0.752 | — |
| bus_P | 0.037 | 0.024 | **0.001** | 0.129 | — |
| trailer_R | 0.472 | 0.361 | **0.333** | 0.750 | — |
| trailer_P | 0.006 | 0.005 | **0.033** | 0.044 | — |
| bg_FA | 0.213 | 0.167 | **0.160** | 0.194 | ≤0.25 **持续新低** |
| offset_cx | 0.051 | 0.083 | **0.053** | 0.057 | ≤0.05 接近 |
| offset_cy | 0.091 | 0.111 | **0.105** | 0.103 | ≤0.10 接近 |
| offset_th | 0.142 | 0.226 | **0.163** | 0.207 | ≤0.20 **恢复达标** |

**P5@4000 仍是综合最优**: 四类 Recall>0.3, offset 三指标全面超 P4
**P5@5000 优势**: bg_FA=0.160 全程新低, trailer_P=0.033 跳升 6.6 倍
**P5@5000 劣势**: bus_R=0.002 完全坍塌, truck_R=0.199 持续下降

---

## 已完成的关键决策

### VERDICT_P5_MID (Critic 已返回, 已归档到 shared/audit/processed/)
- **判决**: CONDITIONAL — P5b 必要
- **振荡根因**: DINOv3 语义过强 + per_class_balance 等权 (car 8269 vs trailer 90 = 92:1) + Linear(4096,768) 5.3:1 压缩瓶颈
- **BUG-17 升级 HIGH**: milestone 相对值 + per_class_balance 振荡
- Critic 修正方案: milestones 用相对值 `[2000,3500]` (begin=500), sqrt 加权 balance, 可选双层投影
- Critic 建议: P6 BEV PE 推迟, 先解决 DINOv3 适配

### P5b 方案 (CEO 批准, 三项全修)
1. **milestones 修正** (必须): `milestones=[2000,3500]` 相对 begin=500, 实际 decay @2500, @4000
2. **per_class_balance → sqrt 加权** (必须): `weight_c = 1/sqrt(count_c/min_count)`
3. **双层投影** (必须, CEO 决策): `Linear(4096,1024)+GELU+Linear(1024,768)`
- 起点: P5@4000 checkpoint
- 时机: P5 完成后签发 ORCH_010

### P6 方向
- BEV 坐标 PE **推迟** — 先解决 DINOv3 适配 (P5b)
- 代码改动: git.py L329, 给 grid_start_embed 加 BEV 物理坐标 PE (MLP 2→768)
- 路线: P5b → P6 (BEV PE, 0.5天) → P6b (3D Anchor, 2-3天) → P7+ (V2X)
- 详见: shared/audit/processed/VERDICT_3D_ANCHOR.md

---

## 活跃任务

| ID | 目标 | 状态 |
|----|------|------|
| ORCH_008 | P5 DINOv3 集成 | COMPLETED (P5 RUNNING) |
| ORCH_009 | 旋转多边形 Grid 分配可视化 | PENDING (CEO 请求, Admin 待执行) |
| AUDIT_P5_MID | P5 中期审计 | COMPLETED (VERDICT 已处理并归档) |
| ORCH_010 | P5b 三项修复 | 未签发 (等 P5 完成) |

---

## 待办 (按优先级)

1. **等 P5 完成** (~23:07) — 收集 @5000 (LR decay 后), @5500, @6000 数据
2. **签发 ORCH_010** — P5b: milestones 修正 + sqrt 加权 + 双层投影, 从 P5@4000 出发
3. **跟踪 ORCH_009** — Admin 执行旋转多边形可视化
4. **P5 完成后做最终评估** — 对比 @4000 (最优) vs @6000 (最终), 决定 P5b 起点

---

## BUG 跟踪

| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 (Grid token 冗余) |
| BUG-15 | HIGH | Precision 瓶颈 — P5b 解决 |
| BUG-16 | MEDIUM | NOT BLOCKING (无数据增强) |
| BUG-17 | HIGH | milestone 相对值 + per_class_balance 振荡 — P5b 解决 |

---

## 基础设施

- 5 Agent 全部 UP (conductor, critic, supervisor, admin, ops)
- all_loops.sh PID 4189737 运行 4h+
- sync_loop PID 34389 运行 3h+
- watchdog crontab 正常
- GPU 0,2: P5 训练 | GPU 1,3: 空闲

---

## 循环协议

### Phase 1
git pull → CEO_CMD.md → supervisor_report_latest.md → STATUS.md → 检查 ORCH 状态 → 读 Admin 报告 → 审计决策 → git push

### Phase 2
git pull → shared/audit/pending/ VERDICTs → 归档到 processed/ → 更新 MASTER_PLAN.md → ORCH 决策 → Context 检查 → git push

---

## 关键文件位置

| 文件 | 用途 |
|------|------|
| MASTER_PLAN.md | 中央策略文档 (每循环更新) |
| CEO_CMD.md | CEO 指令通道 |
| STATUS.md | ops 自动生成的状态面板 |
| shared/logs/supervisor_report_latest.md | Supervisor 最新报告 |
| shared/pending/ORCH_*.md | 待执行/已完成的指令 |
| shared/audit/processed/ | 已归档的 VERDICT 和 AUDIT_REQUEST |
| shared/logs/report_ORCH_*.md | Admin 执行报告 |

---

## P5 Config (ORCH_008)

```
load_from: P4@500
backbone: PreextractedFeatureEmbed (DINOv3 Layer 16, Linear 4096→768)
max_iters: 6000, warmup: 1000 (begin=1000)
milestones: [4000, 5500] (实际: @5000, @6500 永不触发)
bg_balance_weight: 2.5
base_lr: 5e-05, max_norm: 10.0
use_rotated_polygon: True
GPU: 0, 2
work_dir: /mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/
```

## P5b 计划 Config (ORCH_010 待签发)

```
load_from: P5@4000
backbone: PreextractedFeatureEmbed (DINOv3 Layer 16, Linear(4096,1024)+GELU+Linear(1024,768))
max_iters: TBD (参考 P5 的 6000)
warmup: 500 (缩短, Critic 建议)
milestones: [2000, 3500] (相对 begin=500, 实际 decay @2500, @4000)
per_class_balance: sqrt 加权 (weight_c = 1/sqrt(count_c/min_count))
bg_balance_weight: 2.5 (保持)
base_lr: 5e-05 (保持)
其余参数: 保持 P5 配置
```

---

## 红线

| 指标 | 红线 |
|------|------|
| truck_R | < 0.08 |
| bg_FA | > 0.25 |
| offset_th | ≤ 0.20 |
| offset_cy | ≤ 0.10 |
| avg_P | ≥ 0.20 |

## CEO 指令归档 (shared/logs/ceo_cmd_archive.md)
- #1-#6: 历史指令 (见归档)
- #7 (03-07 05:10): 批准 GPU 1,3 用于 DINOv3 特征提取

## 关键历史洞察
1. P3@3000 基线: avg_P=0.147 (最优起点选择依据)
2. P4@4000: 7/9 指标历史最佳, avg_P=0.107 (Precision 瓶颈 → 触发 DINOv3 集成)
3. P5 学习动态: 高振幅探索模式 (不同于 P3/P4 的平稳收敛)
4. P5@1500: bg_FA=0.442 峰值 (自发回落, 未干预)
5. P5@2500: 全类别恢复里程碑 (bus 最晚恢复)
6. P5@3000: car_P=0.091 首超 P4
7. P5@3500: truck_R=0.679 超 P4 66%, offset_th=0.197 首破红线
8. P5@4000: 综合最优 (四类>0.3, offset 全面超 P4)
9. Critic: 振荡根因 = 语义过强 + 等权 balance + Linear 压缩
