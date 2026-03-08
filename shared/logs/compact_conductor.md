# Conductor 工作上下文快照
> 时间: 2026-03-08 08:15
> 循环: #68 (Phase 2 完成)
> 目的: Context compaction

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 放弃预提取路线, 走在线 DINOv3 提取 (避免 2.1TB 存储)。**

---

## 当前状态

### P5b 训练 — COMPLETED ✅
- 完成时间: 2026-03-08 06:36, 6000/6000, 12 个 checkpoint
- **@6000 最终**: bg_FA=**0.208** (全程最低), off_th=**0.198** (达标红线!), 红线 3/5
- P6 load_from: P5b@3000 (Critic 确认, car_P=0.107+bg_FA=0.217 最优)

### 四路诊断实验 — 运行中

| 实验 | GPU | 进度 | 目的 | 速度 | 显存 |
|------|-----|------|------|------|------|
| Plan K (α) | 0 | 1270/2000 | 单类 car, 预提取 | 2.97s | 15.2 GB |
| Plan L (β) | 2 | 1220/2000 | 10类, 宽投影 2048 | 2.98s | 15.4 GB |
| Plan M (γ) | 1 | 340/2000 | 单类 car, 在线 unfreeze | 6.26s | 29.5 GB |
| Plan N (δ) | 3 | 340/2000 | 单类 car, 在线 frozen | 6.26s | 28.0 GB |

ETA: Plan K/L ~08:36-08:39 | Plan M/N ~10:53-10:54

### 诊断 @1000 关键数据

| 指标 | Plan K (1类) | Plan L (10类+宽) | P5b @1000 | P5b 最优 |
|------|-------------|------------------|-----------|----------|
| car_P | 0.047 ⚠️ | **0.140** | 0.089 | 0.108 |
| car_R | 0.507 | 0.338 | 0.760 | 0.924 |
| bg_FA | 0.211 | 0.407 | 0.302 | 0.208 |
| off_th | 0.254 | 0.242 | 0.168 | 0.168 |

---

## VERDICT_DIAG_RESULTS 核心判决 (Critic, Cycle #68)

**判决: CONDITIONAL — 方向对但论证有致命混淆**

### 关键 BUG
- **BUG-27 (CRITICAL)**: Plan K vocab 不兼容 (num_vocal 230→221), vocab_embed 随机初始化 → **Plan K "类竞争否定" 结论无效**。类竞争假说仍未被正确测试。
  - 正确测试方法: 保持 num_vocal=230, 只在 pipeline 中过滤非 car GT
- **BUG-28 (HIGH)**: Plan L 同时改变投影宽度+保留 vocab (vs Plan K 丢失 vocab), 双变量混淆, car_P=0.140 无法干净归因投影宽度
- **BUG-30 (HIGH)**: GELU 系统性损害 off_th — 三组实验交叉印证 (BUG-21 升级):
  - P5 单层 Linear: off_th=0.142 (最优)
  - P5b 双层+GELU: off_th=0.200
  - Plan K/L 双层+GELU: off_th=0.254/0.242
  - **P6 必须去掉 GELU, 用 LayerNorm 或无激活函数**

### 弱推理仍支持宽投影
- 随机初始化的 2048 @1000 (car_P=0.140) > 训练好的 1024 @3000 (car_P=0.107)
- 暗示 2048 信息容量确实更优, 但非严格证明

### P6 定稿前通过条件 (全部必须满足)
1. ✅ 认识 Plan L 结论是混淆的
2. ✅ P6 用 10 类 (保持 vocab 兼容)
3. ✅ P6 宽投影去掉 GELU
4. ⏳ 等 Plan M/N @1000 数据 (~09:00+)
5. ⏳ Plan L @2000: bg_FA 需回落到 <0.30 (~08:39)

### P6 Config 方向 (Critic 建议, 待通过条件后定稿)
```
类别:    10 类 (num_vocal=230)
投影层:  Linear(4096, 2048) + LayerNorm + Linear(2048, 768) — 无 GELU!
load_from: P5b@3000 (backbone+head+vocab 完整加载, 仅 proj 随机初始化)
```

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
| BUG-21 | HIGH | → 升级为 BUG-30 |
| BUG-22 | HIGH | 10 类 ckpt 兼容 — Admin 验证无障碍 ✅ |
| BUG-23 | HIGH | GPU 是 A6000 48GB 非 24GB |
| BUG-24 | MEDIUM | 缺单类诊断 config → ORCH_015 已执行 |
| BUG-25 | HIGH | 无在线 DINOv3 路径 → ORCH_016 已实现 |
| BUG-26 | MEDIUM | 只用 CAM_FRONT, 175GB fp16 非 2.1TB |
| BUG-27 | CRITICAL | Plan K vocab 不兼容 → 实验结论无效 |
| BUG-28 | HIGH | Plan L 双变量混淆 → 无法干净归因 |
| BUG-29 | LOW | Plan K sqrt balance 对单类无意义 |
| BUG-30 | HIGH | GELU 系统性损害 off_th, 三组交叉印证 |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_010 | P5b 三项修复 | **COMPLETED** — 红线 3/5 |
| ORCH_014 | P6 完整 nuScenes 准备 | COMPLETED — BUG-26 降级 BLOCKER |
| ORCH_015 | 诊断 Plan K + Plan L | **执行中** — K 1270/2000, L 1220/2000 |
| ORCH_016 | 在线 DINOv3 Plan M + Plan N | **执行中** — M/N 340/2000 |

## 审计历史
| ID | 判决 | 关键结论 |
|----|------|---------|
| AUDIT_P5_MID | CONDITIONAL | P5b 必要, 三项修复 |
| AUDIT_INSTANCE_GROUPING | CONDITIONAL | 列入 P6+, BUG-18 |
| AUDIT_P5B_3000 | CONDITIONAL | P6 从 @3000, bus=数据量 |
| AUDIT_P6_ARCHITECTURE | CONDITIONAL | 诊断优先, D>C>B, BUG-23/26 |
| AUDIT_DIAG_RESULTS | CONDITIONAL | 方向对但混淆, 去 GELU, 10 类, BUG-27/28/30 |

---

## 待办 (按优先级)
1. **等 Plan L @2000** (~08:39): bg_FA < 0.30? car_P 继续上升?
2. **等 Plan M/N @1000** (~09:00+): 在线 DINOv3 unfreeze vs frozen 效果
3. **定稿 P6 config**: 通过条件满足后签发 ORCH
4. **P6 投影层**: Linear(4096,2048) + LayerNorm + Linear(2048,768) — 去 GELU (BUG-30)
5. **DINOv3 全量提取**: 仅 CAM_FRONT fp16, ~175GB (或走在线路线)

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行 13h+
- GPU 0: Plan K | GPU 1: Plan M | GPU 2: Plan L | GPU 3: Plan N — **4 GPU 满载**

## 路线图
- **当前**: 诊断实验 (Plan K/L/M/N) → 确认投影/在线/GELU 效果
- **P6**: 10 类 + 宽投影 2048 + LayerNorm + P5b@3000 (待定稿)
- **P6b**: BEV PE + 先验词汇表
- **P7**: 历史 occ box (t-1), CEO 批准单时刻 MVP
- **P7b**: 3D Anchor, 射线采样
- **P8**: V2X 融合

## 实验设计教训 (BUG-27/28)
- **每次只改一个变量**
- **vocab 大小变化 = 实验无效** (vocab_embed shape mismatch → 随机初始化)
- **正确的单类测试**: 保持 num_vocal=230, 只在 pipeline 过滤 GT
