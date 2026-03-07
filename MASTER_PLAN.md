# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-07 17:05 (循环 #40)

## 当前阶段: P5 DINOv3 集成! ORCH_008 已签发

### Critic VERDICT_P4_FINAL: CONDITIONAL — 处理完成

**核心判断**: P4 AABB 修复正确有效 (Recall 全面提升), 但 avg_P=0.107 不升反降。Precision 瓶颈已从"标签污染"转移为"模型分辨力不足"。P5 必须集成 DINOv3 中间层特征。

**Critic 关键分析**:
1. AABB 修复因果性: ~50% AABB + ~30% bg_weight + ~20% 更优起点
2. Precision 根因: Conv2d (Layer 0) 只编码纹理/边缘, 缺乏类别语义。模型无法区分"有 truck 的 cell"和"truck 附近的 cell"
3. offset_th 回退是结构性的 (共享 decoder 参数), reg_loss_weight=2.0 不推荐
4. BUG-16 NEW: 预提取特征与数据增强不兼容

**Critic P5 建议** (已采纳):
- 起点: **P4@500** (对旧分布适应最浅)
- 特征层: **Layer 16 单层** (平衡细节和语义)
- 投影: **Linear(4096, 768)** 随机初始化
- Warmup: **1000 步**
- bg_balance_weight: **2.5** (防止 bg_FA 偏高)

---

### ORCH_008 — P5: DINOv3 集成 [PENDING → Admin]

| 参数 | P4 | **P5** | 原因 |
|------|----|----|------|
| load_from | P3@3000 | **P4@500** | Critic: 最浅适应 |
| 特征输入 | Conv2d PatchEmbed | **预提取 Layer 16** | Phase 2 |
| max_iters | 4000 | **6000** | 新特征需更多训练 |
| warmup | 500 | **1000** | 分布差异大 |
| milestones | [2500,3500] | **[4000,5500]** | 适配 6000 |
| bg_balance_weight | 2.0 | **2.5** | Critic 建议 |
| reg_loss_weight | 1.5 | 1.5 | 保持 |
| GPU | 0,2 | 0,2 | CEO 限制 |

**预期**: avg_P 从 0.107 提升至 0.15-0.20 (语义特征直接提供类别信息)

---

### P4 最终成绩 (存档)

**7/9 关键指标全项目历史最佳**:
- car_R=0.667, car_P=0.097, truck_R=0.463, bus_R=0.773, trailer_R=0.806 (ATH)
- bg_FA=0.176 (ATL), offset_cx=0.047 (首破红线)

**P4@4000 最终**: truck_R=0.410 (+36% vs P3), bus_R=0.752 (+6%), trailer_R=0.750 (+21%), avg_P=0.107

---

### DINOv3 特征 — 已就绪
- 路径: `/mnt/SSD/GiT_Yihao/dinov3_features/`
- 323/323 文件, Layer 16 + Layer 20, (4900, 4096) FP16
- 24.15 GB

---

## 架构审计待办 — 持久追踪

### 紧急修复 — 全部完成
- [x] BUG-2, BUG-8, BUG-10, BUG-11

### 架构/标签优化
- [x] AABB → 旋转多边形 → P4 验证
- [x] DINOv3 离线预提取 → ORCH_007 完成
- [~] **DINOv3 集成到模型** → **ORCH_008 签发, P5 规划中**
- [ ] Score 区分度改进 (Critic #2 优先级, 可并行)
- [ ] BUG-14: Grid token 冗余
- [ ] BUG-16: 预提取特征与数据增强不兼容 (NEW)

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 |
| BUG-15 | HIGH | P5 将解决 (DINOv3 集成) |
| **BUG-16** | **MEDIUM** | **NEW — 预提取特征与增强不兼容** |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_005-007 | P4 + DINOv3 提取 | COMPLETED |
| **ORCH_008** | **P5: DINOv3 集成 + 训练** | **PENDING → Admin** |

## 下一步计划
1. **ORCH_008 执行**: Admin 实现 PreextractedFeatureEmbed + 启动 P5
2. **P5@500 首次 val**: DINOv3 语义特征对 Precision 的影响
3. **P5 目标**: avg_P ≥ 0.15 (中期), ≥ 0.20 (终极)

## 历史决策
### [2026-03-07 17:05] 循环 #40 — VERDICT_P4_FINAL 处理, ORCH_008 签发
- Critic 审计 CONDITIONAL: AABB 修复有效但 Precision 需 DINOv3 突破
- Critic 因果分析: AABB ~50%, bg_weight ~30%, 起点 ~20%
- Precision 根因: Conv2d 缺乏语义 → 需 Layer 16 深层特征
- 采纳 Critic 全部建议: P4@500 起点, Layer 16 单层, warmup 1000
- 签发 ORCH_008 给 Admin
- BUG-16 NEW: 预提取特征与增强不兼容

### [2026-03-07 16:55] 循环 #39 — P4 COMPLETED, Critic 审计请求
### [2026-03-07 16:05] 循环 #38 — P4@2000 + ORCH_007 完成
### [2026-03-07 05:10] 循环 #37 — CEO 指令 #7, ORCH_007 签发
### [2026-03-07 04:40] 循环 #36 — P4@1000 offset_th 达标
### [2026-03-07 04:10] 循环 #35 — P4@500 bg_FA 历史最低
### [2026-03-07 03:10] 循环 #33 — P4 启动
### [2026-03-07 01:50] 循环 #31 — P3 完成
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
