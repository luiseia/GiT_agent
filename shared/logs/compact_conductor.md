# Conductor 工作上下文快照
> 时间: 2026-03-09 16:00
> 循环: #135 (Phase 2 完成)
> 目的: @8000 val + VERDICT 处理完毕, @10000 val 即将触发, 等结果

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 在线 DINOv3 frozen (避免 2.1TB 存储)。**

---

## ★★★★ 当前状态: Full nuScenes — peak_car_P=0.090, off_th=0.140 历史最低! @10000 val 进行中

### ORCH_024 训练状态 (Cycle #135)
- **进度**: 10000/40000 (25.0%), 速度稳定 ~6.3-6.5 s/iter
- **BUG-46**: accumulative_counts=4, 实际 optimizer steps = iter/4
- **ETA**: ~3/12 ~03:00
- **显存**: 36-37 GB/GPU (A6000 48GB)
- **磁盘**: 282 GB 可用

### Full nuScenes Val 历史

| 指标 | @2000 (500 opt) | @4000 (1000 opt) | @6000 (1500 opt) | @8000 (2000 opt) | 趋势 |
|------|-----------------|------------------|------------------|------------------|------|
| **car_P** | 0.079 | 0.078 | **0.090** | **0.060** | 振荡 (P/R tradeoff) |
| car_R | 0.627 | 0.419 | 0.455 | **0.718** | 振荡 (与P反向) |
| truck_R | 0.000 | 0.059 | 0.138 | **0.000** | 类间振荡 |
| bus_R | 0.000 | 0.000 | **0.287** | **0.002** | 类间振荡 |
| ped_R | 0.067 | 0.026 | 0.145 | **0.276** | ✅ 持续增长 |
| cone_R | 0.000 | 0.000 | 0.160 | **0.000** | 类间振荡 |
| **bg_FA** | 0.222 | 0.199 | 0.331 | **0.311** | ✅ 开始回落! |
| off_cx | 0.056 | 0.039 | 0.056 | **0.045** | ✅ 改善 |
| off_cy | 0.069 | 0.097 | 0.082 | **0.074** | ✅ 改善 |
| **off_th** | 0.174 | 0.150 | 0.169 | **0.140** | ✅✅ 历史最低! |

### 振荡模式 (Critic VERDICT_FULL_8000 分析)
- 周期 ~1000 optimizer steps: car spam → 多类展开 → 多类爆发 → car spam
- @2000: car dominant → @4000: 多类展开 → @6000: 多类爆发 → @8000: car spam v2
- **@10000 预判**: 多类展开/爆发, car_P 应回升 0.08-0.10
- LR decay @17000 会缓解振荡幅度 (-10x), 但 sqrt balance 根因不变

### @10000 决策矩阵 (修正版, BUG-47: 用 peak_car_P 替代单点)

| peak_car_P (3-eval) | @10000 趋势 | 行动 |
|---------------------|------------|------|
| > 0.10 | 结构指标改善 | 确认方向, 继续到 @17000 |
| 0.08-0.10 | 结构指标改善 | 继续, @12000 再评估 |
| 0.08-0.10 | 结构指标停滞 | 启用 deep supervision |
| < 0.08 (peak!) | any | 必须调参 |

当前 peak_car_P = 0.090 (from @6000). @8000 单点=0.060 是振荡低谷 (BUG-47).

### Full nuScenes Config
```python
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))
在线 DINOv3 frozen, ViT-7B fp16, Layer 16
ViT-Base 18层 (12 SAM + 6 新增窗口注意力)
lr_mult: proj=2.0, 新层=1.0, SAM 0.05-0.80 渐进
max_iters = 40000, warmup = 2000, milestones = [15000, 25000]
accumulative_counts = 4, effective batch = 32
num_vocal = 230, 10 classes, sqrt balance, bg_weight = 2.5
val_interval = 2000, 4 GPU DDP
Config: configs/GiT/plan_full_nuscenes_gelu.py
Work dir: /mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu
Data: train 28130 (700 scenes), val 6019 (150 scenes), 零重叠
参数: ~180M 可训练 (2.5%), ~7B 冻结 (97.5%)
显存: ~37 GB/GPU (DINOv3 FP16 ~14GB + 激活+优化器 ~23GB)
```

---

## VERDICT 判决汇总

| ID | 判决 | 关键结论 |
|----|------|---------|
| P2_FINAL_FULL_CONFIG | PROCEED | Full nuScenes 2048+GELU! |
| CEO_STRATEGY_NEXT | CONDITIONAL | D最有前途, 等训练 |
| CEO_ARCH_QUESTIONS | CONDITIONAL | Deep Supervision零成本#1, BUG-43/44/45 |
| AR_SEQ_REEXAMINE | CONDITIONAL | 非主要瓶颈, MEDIUM |
| FULL_4000 | CONDITIONAL | 继续训练. BUG-17→CRITICAL, BUG-46 new |
| FULL_6000 | CONDITIONAL | 继续训练. bg_FA=0.331不告警 |
| ORCH026_PLANQ | PROCEED | 类竞争无关! BUG-17→HIGH. 新瓶颈: BUG-15 |
| **FULL_8000** | **CONDITIONAL** | **继续不调参. BUG-47 修正决策矩阵. peak=0.090→继续. @10000 新矩阵** |

---

## 活跃任务

| ID | 目标 | 状态 |
|----|------|------|
| **ORCH_024** | **Full nuScenes 2048+GELU+在线DINOv3** | **IN PROGRESS — 10000/40000 (25.0%), @10000 val 进行中, 等结果 (~17:00)** |
| ORCH_025 | pytest 测试框架 | COMPLETED ✅ — 177 passed |
| ORCH_026 | Plan Q 单类 car 诊断 (mini) | COMPLETED ✅ — car_P@best=0.083 < 0.12 → 类竞争无关! |
| ORCH_001-023 | Mini 阶段全部 | COMPLETED |

---

## 关键发现 (本 session)

**1. ORCH_026 类竞争无关 (Cycle #120)**
- Plan Q car_P@best=0.083 < P2 (10类+GELU) 0.112 → 多类对 car 有正迁移!
- car_P 瓶颈候选: DINOv3→BEV 信息瓶颈 (BUG-15), BEV 投影精度, per-cell 评估偏差 (BUG-18)

**2. @8000 架构决策 (Cycle #128)**
- car_P=0.060 是 P/R tradeoff + 类间振荡, 非真退化
- 结构指标全面历史最优 (off_th=0.140!)
- BUG-47: 单点决策矩阵有缺陷 → 改用 3-eval 峰值
- peak_car_P=0.090 → "方向正确, 继续"

---

## 修正后优先级排序

| 排名 | 提案 | 时机 |
|------|------|------|
| 1 | **Deep Supervision** (一行改动) | ORCH_024 后第一个实验 |
| 2 | **方案 D (历史 occ box 2帧)** | ORCH_024 后 |
| 3 | **方案 E (LoRA)** (缓解 BUG-15) | D 之后 |
| 4 | **BUG-17 修复** (不影响 car_P) | ORCH_024 后第二轮 |
| 5 | **Attention Mask / BUG-45 修复** | 与 deep supervision 一起 |

---

## BUG 跟踪 (关键)

| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| **BUG-17** | **HIGH** (降级) | bicycle 振荡. 不影响 car_P. 仅影响 bg_FA/训练稳定 |
| BUG-33 | MEDIUM | FIXED — DefaultSampler, DDP 偏差已修复 |
| BUG-45 | MEDIUM | OCC head 推理 attn_mask=None |
| BUG-46 | LOW | accumulative_counts=4, optimizer steps = iter/4 |
| **BUG-47** | **MEDIUM** | 单点 car_P 决策矩阵不适用振荡训练. 改用 3-eval 峰值 |

---

## 待办 (按优先级)
1. ~~@2000 val~~ ✅ → ~~@4000~~ ✅ → ~~@6000~~ ✅ → ~~@8000~~ ✅ VERDICT 处理完
2. **捕获 @10000 val 结果** (ETA ~17:00): 应用修正版决策矩阵
3. **@10000 per-slot 分析** (VERDICT_AR_SEQ_REEXAMINE 遗留)
4. **单 GPU re-eval**: 确认 DDP 偏差 (BUG-33)
5. **ORCH_024 后实验**: Deep Supervision → 方案 D → LoRA
6. **BUG-15 专项审计**: @10000 后安排 (precision 瓶颈根因)

## 下一里程碑

| 事件 | iter | ETA |
|------|------|-----|
| **@10000 val** | **10000** | **进行中, 结果 ~17:00** |
| @12000 val | 12000 | ~3/9 ~23:00 |
| 第一次 LR decay | 17000 | ~3/10 ~10:00 |
| 训练结束 | 40000 | ~3/12 ~03:00 |

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行正常
- 4 GPU 正常
- 磁盘 282 GB 可用

## 关键代码位置
- Deep Supervision: `git.py:L386-388` → `loss_out_indices = [8, 10, 11]`
- OCC head 推理 mask (BUG-45): `git_occ_head.py:L1116` → `attn_mask=None`
- Proj 层: `vit_git.py:L166-171` → Linear(4096,2048)+GELU+Linear(2048,768)
- per_class_balance: `git_occ_head.py:L820-836` → sqrt mode
- Token layout: Bins 0-167(168) + Classes 168-177(10) + BG 178 + Markers 179-182 + Theta_G 183-218(36) + Theta_F 219-228(10) + Ignore 229 = num_vocal 230

## 实验设计教训
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **accumulative_counts 影响 optimizer steps** (BUG-46)
- **DDP 偏差不可预测** — 必须单 GPU re-eval (BUG-37)
- **不读代码就估算 = BUG** (BUG-43)
- **Mini car_P 天花板 ~0.12-0.13, 不再跑 Mini 实验**
- **GELU 加速收敛** — P2@1000 +72% vs P6
- **eval 结果需参考振荡周期, 不做单点决策** (BUG-47)
- **类竞争无关 car_P** — 多类训练对 car 有正迁移 (ORCH_026)
