# Conductor 工作上下文快照
> 时间: 2026-03-08 06:35
> 循环: #64 (Phase 2 完成)
> 目的: Context compaction

---

## CEO 战略转向 (2026-03-08)
> **不再以 Recall/Precision 为最高目标，不再高度预警红线。**
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**

---

## 当前状态

### P5b 训练 — 即将完成
- 进度: iter 5390/6000 (89.8%), ETA ~06:33
- LR: 2.5e-08, 模型完全冻结 (@5000: 10/14 指标零变化)
- GPU: 0 + 2
- 三项修复全部验证成功: 双层投影 + sqrt 权重 + LR milestones

### P5b 最终冻结指标 (@5000, 不再变化)
| 指标 | 值 | 参考线 |
|------|------|--------|
| car_R | 0.788 | — |
| car_P | 0.105 | — |
| truck_R | 0.239 | ≥0.08 |
| bus_R | 0.059 | — |
| trailer_R | 0.417 | — |
| bg_FA | 0.210 | ≤0.25 |
| off_cx | 0.059 | ≤0.05 |
| off_cy | 0.132 | ≤0.10 |
| off_th | 0.201 | ≤0.20 |

### P5b 最优 checkpoint 候选 (Critic 推荐 P6 从 @3000)
1. **@3000**: car_P=0.107 最高, bg_FA=0.217, **P6 起点** (Critic+Conductor 确认)
2. @1000: offset 最优 (cx=0.049, th=0.168), 三类最均衡
3. @2500: 四类全活 (bus=0.470, trailer=0.444)

---

## ORCH_014 — COMPLETED (Admin 已执行)

### 关键发现

**1. 完整 nuScenes 数据 ✅**
- Train: 28,130 samples, 974,146 GT boxes
- Val: 6,019 samples
- pkl: `data/infos/nuscenes_infos_temporal_train.pkl`
- 图像: `data/nuscenes/` (6 相机完整, 与 mini 硬链接共享)

**2. DINOv3 特征 — BLOCKER**
- Mini: 323 files, 25 GB (~76.6 MB/file)
- Full train: 28,130 files ≈ **2.1 TB** — SSD 仅剩 528 GB, 远不够
- 提取脚本: `scripts/extract_dinov3_features.py` 可用
- **需要 CEO 决策**: 清理SSD / 外部存储 / 在线提取 / 延后

**3. 磁盘空间**
- `/mnt/SSD/`: 3.7 TB 总, 528 GB 可用 (86%)
- `/home/`: 3.7 TB 总, 70 GB 可用 (99%)
- 可回收: Debug/ 167 GB + old work_dirs ~300 GB → 仍不够 2.1 TB

**4. P6 Config ✅**
- `plan_j_full_nuscenes.py` 已创建 (GiT commit `b3cca77`)
- load_from: P5b@3000, 10 classes, num_vocal=230
- max_iters=36000 (~20 epochs), val_interval=2000
- DINOv3 features dir: **TODO** (待解决 BLOCKER)

**5. Checkpoint 兼容性 ✅**
- 267 个权重 key, 无 num_vocal 维度权重
- vocab tokens 由 BERT embedding (30524×768) 动态索引
- 4→10 类扩展完全兼容, 无 shape mismatch

---

## 10 类扩展 — COMMITTED (GiT `2b52544`)
- classes: 4→10 (全 nuScenes 检测类)
- num_vocal: 224→230, marker_end_id: 176→182, cls_start: 168
- 修改文件: plan_i_p5b_3fixes.py, generate_occ_flow_labels.py
- Checkpoint 兼容: 已验证

## CEO 批准项
- 双层投影 Linear(4096,1024)+GELU+Linear(1024,768) — 覆盖 Critic BUG-21 A/B test 建议

---

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层 (Grid token 冗余) |
| BUG-15 | HIGH | P5b 解决 (双层投影) |
| BUG-17 | HIGH | P5b 解决 (milestones + sqrt) |
| BUG-18 | MEDIUM | 设计层 (GT instance 未跨 cell 关联) |
| BUG-19 | HIGH | FIXED — z+=h/2 删除, commit `965b91b` |
| BUG-20 | HIGH | bus 振荡=mini 数据量天花板, 非模型 bug |
| BUG-21 | MEDIUM | off_th 退化 0.142→0.200, CEO 批准双层投影不回退 |
| BUG-22 | HIGH | 10 类 ckpt 兼容 — Admin 验证无障碍 ✅ |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_010 | P5b 三项修复 | COMPLETING (~06:33) |
| ORCH_014 | P6 完整 nuScenes 准备 | **COMPLETED — BLOCKER: DINOv3 2.1TB** |

## 审计历史
| ID | 判决 | 关键结论 |
|----|------|---------|
| AUDIT_P5_MID | CONDITIONAL | P5b 必要, 三项修复 |
| AUDIT_INSTANCE_GROUPING | CONDITIONAL | 列入 P6+, BUG-18 |
| AUDIT_P5B_3000 | CONDITIONAL | P6 从 @3000, bus 振荡=数据量 |

---

## 待办 (按优先级)
1. **解决 DINOv3 存储 BLOCKER** — 需要 CEO 决策 (清理/外部存储/在线提取/延后)
2. **P5b 完成后** — 确认最终 checkpoint, 更新 MASTER_PLAN
3. **P6 启动** — 待 BLOCKER 解决后, 用 plan_j_full_nuscenes.py 启动

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 11h+
- GPU 0,2: P5b (即将释放) | GPU 1,3: 空闲

## 路线图
- **P6**: 完整 nuScenes + 10 类 (BLOCKER 待解决)
- **P6b**: BEV PE + 先验词汇表
- **P7**: 历史 occ box, 时序建模
- **P7b**: 3D Anchor, 射线采样
- **P8**: V2X 融合
