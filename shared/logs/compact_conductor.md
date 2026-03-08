# Conductor 工作上下文快照
> 时间: 2026-03-08 06:50
> 循环: #65 (Phase 2 完成)
> 目的: Context compaction

---

## CEO 战略转向 (2026-03-08)
> **不再以 Recall/Precision 为最高目标，不再高度预警红线。**
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**

## CEO 架构指令 (2026-03-08, Cycle #65)
> CEO 提出 DINOv3 适配层改进 (方案 A/B) + 3D 空间编码路线图
> Conductor 补充方案 C (LoRA) + D (宽中间层)
> Critic 审计: CONDITIONAL — 先做诊断实验

---

## 当前状态

### P5b 训练 — 即将完成
- 进度: iter 5910/6000 (98.5%), ETA ~06:36
- LR: 2.5e-08, 模型完全冻结
- GPU: 0 + 2 (即将释放)
- 三项修复全部验证成功: 双层投影 + sqrt 权重 + LR milestones

### P5b@5500 最新指标
| 指标 | @5500 | 参考线 |
|------|-------|--------|
| car_R | 0.777 | — |
| car_P | 0.104 | — |
| truck_R | 0.243 | ≥0.08 |
| bus_R | 0.058 | — |
| trailer_R | 0.417 | — |
| bg_FA | 0.209 | ≤0.25 (P5b 新低) |
| off_cx | 0.058 | ≤0.05 |
| off_cy | 0.134 | ≤0.10 |
| off_th | 0.202 | ≤0.20 |

### VERDICT_P6_ARCHITECTURE 关键发现
1. **BUG-23**: GPU 是 A6000 48GB (非 24GB) — 显存约束大幅放松
2. **BUG-24**: 需创建单类 car 诊断 config
3. **BUG-25**: 无在线 DINOv3 提取路径 (PreextractedFeatureEmbed 只支持磁盘)
4. **BUG-26**: 代码只用 CAM_FRONT! 全量 DINOv3 仅 ~175GB fp16 (非 2.1TB) → BLOCKER 降级
5. **P5b 双层投影已触顶**: car_P@3000-5500 标准差 0.0015
6. **方案优先级**: D (宽中间层 2048) > C (LoRA) > B (Full Unfreeze)
7. **必须做**: 单类 car 诊断实验 (确认类竞争是否为瓶颈)
8. **历史 occ box 推迟到 P7**

---

## ORCH_015 — PENDING (刚签发)

### 任务
1. 创建 plan_k_car_only_diag.py (单类 car, 实验 α)
2. 创建 plan_l_wide_proj_diag.py (宽中间层 2048, 实验 β)
3. 验证 BUG-26 (只用 CAM_FRONT)
4. P5b 完成后启动两个诊断实验 (GPU 0 + GPU 2)
5. 结果汇总报告

### 判断标准
- α car_P > 0.15 → 类竞争是瓶颈 → per-class head
- α car_P ≈ 0.105 → 特征/架构瓶颈 → LoRA/在线 DINOv3

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
| BUG-19 | HIGH | FIXED — z+=h/2 删除 |
| BUG-20 | HIGH | bus 振荡=mini 数据量天花板 |
| BUG-21 | MEDIUM | off_th 退化, CEO 批准双层投影不回退 |
| BUG-22 | HIGH | 10 类 ckpt 兼容 — Admin 验证无障碍 ✅ |
| BUG-23 | HIGH | GPU 是 A6000 48GB 非 24GB |
| BUG-24 | MEDIUM | 缺单类诊断 config → ORCH_015 |
| BUG-25 | HIGH | 无在线 DINOv3 路径 → 未来需实现 |
| BUG-26 | MEDIUM | 只用 CAM_FRONT, 175GB fp16 非 2.1TB |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_010 | P5b 三项修复 | COMPLETING (~06:36) |
| ORCH_014 | P6 完整 nuScenes 准备 | COMPLETED — BUG-26 降级 BLOCKER |
| ORCH_015 | 诊断实验 (car only + wide proj) | **PENDING** |

## 审计历史
| ID | 判决 | 关键结论 |
|----|------|---------|
| AUDIT_P5_MID | CONDITIONAL | P5b 必要, 三项修复 |
| AUDIT_INSTANCE_GROUPING | CONDITIONAL | 列入 P6+, BUG-18 |
| AUDIT_P5B_3000 | CONDITIONAL | P6 从 @3000, bus=数据量 |
| AUDIT_P6_ARCHITECTURE | CONDITIONAL | 诊断优先, D>C>B, BUG-23/26 |

---

## 待办 (按优先级)
1. **ORCH_015 执行**: Admin 创建 plan_k + plan_l, 启动诊断实验
2. **P5b 完成后**: 确认 @6000 最终 checkpoint
3. **诊断结果分析**: 根据 α vs β 选择 P6 路径
4. **DINOv3 全量提取**: 仅 CAM_FRONT fp16, ~175GB (BUG-26 验证后)

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 12h+
- GPU 0,2: P5b (即将释放) | GPU 1,3: 空闲

## 路线图
- **Phase 0**: 诊断实验 α (car only) + β (wide proj) — ORCH_015
- **P6**: 根据诊断选路径 — 全量 nuScenes + 改进
- **P6b**: BEV PE + 先验词汇表
- **P7**: 历史 occ box (t-1), CEO 批准单时刻 MVP
- **P7b**: 3D Anchor, 射线采样
- **P8**: V2X 融合
