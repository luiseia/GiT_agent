# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-07 03:40 (循环 #34)

## 当前阶段: P4 训练中 (warmup), ORCH_006 Phase 2 准备就绪

### P4 训练状态 — RUNNING (warmup)
- **PID**: 3929983
- **GPU**: 0,2 (RTX A6000) | CEO 限制只用 0,2
- **Config**: `plan_g_aabb_fix.py`
- **起点**: P3@3000
- **进度**: iter ~120 / 4000 (~3%, warmup 阶段)
- **ETA 完成**: ~06:20 (3月7日)
- **首次 val**: P4@500 (~03:45)
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_g_aabb_fix/`

### P4 Config 变化 (vs P3)
| 参数 | P3 (plan_f) | P4 (plan_g) | 变化原因 |
|------|-------------|-------------|---------|
| load_from | P2@6000 | **P3@3000** | Critic: @3000 是 P3 最佳点 |
| bg_balance_weight | 3.0 | **2.0** | Critic: 3.0 压制 car_R |
| reg_loss_weight | 1.0 | **1.5** | Critic: 保护 theta 回归 |
| use_rotated_polygon | N/A | **True** | AABB 标签污染修复 |
| max_iters | 4000 | 4000 | — |
| warmup | 500 linear | 500 linear | — |
| milestones | [2500, 3500] | [2500, 3500] | — |

### P4 早期信号
- Warmup 正常: LR 从 ~1e-6 爬升至 1.2e-05
- 前 50 iter: 60% clipping → **iter 80-120 已稳定** (grad_norm 3.4-7.9, 全部 unclipped)
- loss_reg 偏高 (预期: reg_loss_weight 1.5x 放大)
- 无 NaN/OOM, 显存 21.5GB/49.1GB per GPU

---

### ORCH_006 — Phase 2: DINOv3 预提取 [PARTIAL — 脚本就绪, 等待触发]

**Admin 报告摘要** (03:20):
- **DINOv3 权重**: 已下载 (26 GB), `/mnt/SSD/yz0370/dinov3_weights/`
- **模型架构**: ViT-7B, embed_dim=4096, depth=40, RoPE, `get_intermediate_layers()` API
- **提取脚本**: `scripts/extract_dinov3_features.py` (已写好, 支持断点续传)
- **存储**: Layer 16+20 = 24.2 GB (323 images), SSD 有 609 GB 空余
- **预计时间**: ~16 分钟 (323 images × 3 sec/image)
- **BLOCKER**: Python 3.8 不兼容 → 需新建 conda env (Python 3.10, ~30 min)
- **GPU 约束**: DINOv3 需 ~14 GB, 无法与 P4 共存于 GPU 0,2; 需 GPU 1/3 或等 P4 结束

**集成方案** (触发后执行):
1. `vit_git.py`: `PreextractedFeatureEmbed` 类, `Linear(4096, 768)` 投影
2. Dataset: image token → feature path 映射
3. Config: `preextracted_feature_dir` 参数

**触发条件** (CEO 指令 #6):
- P4 首批 val 后 avg_P > 0.15 → Phase 2 低优先级
- P4 首批 val 后 avg_P < 0.12 → 立即集成 DINOv3 特征
- 0.12 ≤ avg_P ≤ 0.15 → Conductor 决策

---

### P3@3000 基线 (P4 起点)
| 指标 | P3@3000 | P2@6000 | vs P2 |
|------|---------|---------|-------|
| car_R | 0.614 | 0.596 | +3.0% |
| car_P | 0.082 | 0.079 | +3.8% |
| truck_R | 0.326 | 0.290 | +12.4% |
| truck_P | 0.306 | 0.190 | +61.1% |
| bus_R | 0.636 | 0.623 | +2.1% |
| bus_P | 0.133 | 0.150 | -11.3% |
| trailer_R | 0.622 | 0.689 | -9.7% |
| trailer_P | 0.068 | 0.066 | +3.0% |
| bg_FA | 0.194 | 0.198 | -2.0% |
| avg_P | **0.147** | 0.121 | +21.5% |

---

## 架构审计待办 (VERDICT_ARCH_REVIEW) — 持久追踪

> CEO 指令: 此区域持续追踪, 不随循环删除

### 紧急修复
- [x] BUG-2 → FIXED
- [x] BUG-8 修复 → ORCH_004 完成
- [x] BUG-10 修复 → ORCH_004 完成
- [x] BUG-11 修复 → ORCH_005 完成

### 架构/标签优化 (P4)
- [x] **AABB → 旋转多边形** → ORCH_005 完成
- [~] **DINOv3 离线预提取** → ORCH_006 脚本就绪, Python blocker 有解, 等待触发
- [ ] Score 区分度改进 (待评估)
- [ ] BUG-14: Grid token 冗余
- [ ] BUG-15: DINOv3 利用率
- [ ] 新增层 12-17 加 global attention

### 未实现历史分析
- [x] 分析 1: AABB → 旋转多边形 → ORCH_005 实现
- [ ] 分析 2: 2D-3D 视觉对齐
- [ ] 分析 4: Token 合并
- [x] 分析 3: Center/Around

---

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2 | CRITICAL | **FIXED** |
| BUG-8 | CRITICAL | **FIXED & VALIDATED** |
| BUG-9 | 致命 | **FIXED (P2+P3 config)** |
| BUG-10 | HIGH | **FIXED & VALIDATED** |
| BUG-11 | LOW | **FIXED (ORCH_005)** |
| BUG-12 | HIGH | **FIXED** |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 |
| BUG-15 | HIGH | 架构层面 |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| **ORCH_005** | P4 Phase 1 | **COMPLETED — 验收通过** |
| **ORCH_006** | P4 Phase 2: DINOv3 预提取 | **PARTIAL — 脚本就绪, 等待触发** |

## 下一步计划 (循环 #35+)
1. **P4@500 (~03:45)**: 首次 val — 关键! AABB 修复效果验证
   - avg_P 是否显著提升? (P3@3000 基线 0.147)
   - car_P 是否改善? (AABB 修复最直接影响)
   - Phase 2 触发判断 (avg_P vs 0.12/0.15 阈值)
2. **ORCH_006 blocker**: 如触发 Phase 2, 需 CEO 批准 GPU 1/3 或等 P4 结束
3. **P4 全程监控**: @500→@1000→...→@4000

## 历史决策
### [2026-03-07 03:40] 循环 #34 — ORCH_006 报告处理
- ORCH_006 PARTIAL: 提取脚本就绪, Python 3.8 blocker 有清晰解决方案 (新 conda env)
- GPU 约束: DINOv3 14GB 无法与 P4 共存, 需 GPU 1/3 或等 P4 完成
- 存储: 2 层 24.2 GB, SSD 609 GB 充足
- 预计提取仅需 ~16 分钟
- P4 仍在 warmup (~120 iter), 无新 val 数据
- 决策: 继续等待 P4@500, ORCH_006 准备充分

### [2026-03-07 03:10] 循环 #33 — ORCH_005 验收通过, P4 训练已启动
### [2026-03-07 02:55] 循环 #32 — P4 批准, ORCH_005/006 签发
### [2026-03-07 02:40] 循环 #32 — VERDICT_P3_FINAL 处理
### [2026-03-07 01:50] 循环 #31 — P3 完成
### [2026-03-07 01:40] 循环 #30 — P3@3000/@3500
### [2026-03-07 01:10] 循环 #29 — P3@2500 LR decay
### [2026-03-06 23:55] 循环 #28 — P3@2000 + VERDICT_ARCH_REVIEW
### [2026-03-06 21:55] 循环 #24 — P3 启动
### [2026-03-06 21:00] 循环 #23 — ORCH_004 签发
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
