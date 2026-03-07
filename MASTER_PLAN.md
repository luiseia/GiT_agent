# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-07 18:00 (循环 #42)

## 当前阶段: P5 训练已启动! ORCH_008 验收通过, DINOv3 Layer 16 集成完成

### P5 训练状态 — RUNNING (warmup 初期)
- **PID**: 1572
- **GPU**: 0,2 (RTX A6000) | 显存 20.4 GB/GPU (低于 P4 的 22 GB)
- **Config**: `plan_h_dinov3_layer16.py`
- **起点**: P4@500
- **进度**: iter ~50 / 6000 (warmup 阶段, 极早期)
- **ETA 完成**: ~22:40 (3月7日)
- **首次 val**: P5@500
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/`

### ORCH_008 验收: PASS
| 任务 | 结果 | 判定 |
|------|------|------|
| PreextractedFeatureEmbed | .pt 加载 + Linear(4096,768) kaiming init + 缓存 | PASS |
| Dataset 适配 | sample_idx via PackOccInputs | PASS |
| P5 Config | 全参数匹配规格 | PASS |
| BUG-16 评估 | **NOT BLOCKING** — pipeline 无图像增强 | PASS |
| P5 训练启动 | PID 1572, GPU 0,2, 无 NaN/OOM | PASS |
| 特征验证 | (B, 4900, 768) shape 正确 | PASS |

### P5 早期信号 (iter 10-50) — 符合预期
- **Loss 极高**: 16-17 (P4 初期 ~0.5) — 随机投影初始化导致特征分布剧变
- **grad_norm 极高**: 140-257, **100% clipping** (max_norm=10.0)
- **iter 40 loss 降至 11.6** — 投影层开始适应
- 1000 步 warmup 提供充分适应时间
- 无 NaN/OOM

### P5 Config (vs P4)
| 参数 | P4 | **P5** | 变化原因 |
|------|----|----|---------|
| load_from | P3@3000 | **P4@500** | Critic: 最浅适应 |
| 特征输入 | Conv2d PatchEmbed | **预提取 Layer 16** | Phase 2 集成 |
| use_dinov3_patch_embed | True | **False** | 被预提取替代 |
| max_iters | 4000 | **6000** | 新特征需更多训练 |
| warmup | 500 | **1000** | 分布差异大 |
| milestones | [2500,3500] | **[4000,5500]** | 适配 6000 |
| bg_balance_weight | 2.0 | **2.5** | Critic: 防 bg_FA 偏高 |

### BUG-16: NOT BLOCKING
- train_pipeline 无图像增强 (无 flip/rotation/color jitter)
- 预提取特征直接兼容

---

### P4 最终成绩 (存档)
- 7/9 关键指标历史最佳
- car_R=0.667, truck_R=0.463, trailer_R=0.806, bus_R=0.773 (ATH)
- bg_FA=0.176 (ATL), offset_cx=0.047 (首破红线)
- avg_P=0.107 (Precision 瓶颈 → P5 解决)

---

## 架构审计待办 — 持久追踪

### 紧急修复 — 全部完成
- [x] BUG-2, BUG-8, BUG-10, BUG-11

### 架构/标签优化
- [x] AABB → 旋转多边形 → P4 验证
- [x] DINOv3 离线预提取 → ORCH_007 完成
- [x] **DINOv3 集成到模型** → **ORCH_008 COMPLETED, P5 RUNNING**
- [ ] Score 区分度改进 (Critic #2 优先级)
- [ ] BUG-14: Grid token 冗余
- [x] BUG-16: NOT BLOCKING (无增强)

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 |
| BUG-15 | HIGH | **P5 正在解决** (DINOv3 Layer 16 集成) |
| BUG-16 | MEDIUM | **NOT BLOCKING** (无增强) |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_005-007 | P4 + DINOv3 提取 | COMPLETED |
| **ORCH_008** | **P5: DINOv3 集成 + 训练** | **COMPLETED (验收通过, P5 RUNNING)** |

## 下一步计划
1. **P5@500 首次 val**: DINOv3 语义特征对 Precision 的首次验证!
   - 关键看: avg_P 是否开始上升? car_P 是否显著改善?
   - 注意: loss 从 16 起步, @500 时模型可能还在适应, 数据可能不佳
2. **P5 warmup 观察**: loss 和 grad_norm 是否在 1000 步内稳定
3. **P5 全程**: @500→@1000→...→@6000

## 红线
| 指标 | 红线 | P4 Best | 说明 |
|------|------|---------|------|
| truck_R | < 0.08 | 0.463 | — |
| bg_FA | > 0.25 | 0.176 | — |
| offset_th | ≤ 0.20 | 0.200 | — |
| offset_cy | ≤ 0.10 | 0.089 | — |
| avg_P | ≥ 0.20 | 0.107 | **P5 核心目标** |

## 历史决策
### [2026-03-07 18:00] 循环 #42 — ORCH_008 验收通过, P5 训练已启动
- ORCH_008 全部 6 项检查 PASS
- P5 PID 1572, GPU 0,2, 显存 20.4 GB/GPU
- 早期 loss 16-17 + grad_norm 140-257 (100% clipping) — 预期行为
- BUG-16 NOT BLOCKING
- 无需审计, 等待 P5@500 首次 val

### [2026-03-07 17:30] 循环 #41 — 审计归档
### [2026-03-07 17:05] 循环 #40 — VERDICT_P4_FINAL, ORCH_008 签发
### [2026-03-07 16:55] 循环 #39 — P4 COMPLETED
### [2026-03-07 16:05] 循环 #38 — P4@2000 + ORCH_007 完成
### [2026-03-07 05:10] 循环 #37 — CEO 指令 #7, ORCH_007 签发
### [2026-03-07 03:10] 循环 #33 — P4 启动
### [2026-03-07 01:50] 循环 #31 — P3 完成
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
