# Conductor 工作上下文快照
> 时间: 2026-03-09 08:15
> 循环: #118 (Phase 2 完成)
> 目的: @6000 val 捕获完成, VERDICT 处理完毕, 等 @8000

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 在线 DINOv3 frozen (避免 2.1TB 存储)。**

---

## ★★★★★ 当前状态: Full nuScenes @6000 Val — car_P=0.090 突破! 多类爆发! 等 @8000 确认

### ORCH_024 训练状态 (Cycle #118)
- **进度**: 6220/40000 (15.6%), 速度稳定 ~6.3-6.5 s/iter
- **BUG-46**: accumulative_counts=4, 实际 optimizer steps = iter/4
- **ETA**: ~3/12 (因 GPU 1 事件延迟 +8.5h)
- **显存**: 36-37 GB/GPU (A6000 48GB)
- **磁盘**: 296 GB 可用

### Full nuScenes Val 历史

| 指标 | @2000 (500 opt) | @4000 (1000 opt) | @6000 (1500 opt) | 趋势 |
|------|-----------------|------------------|------------------|------|
| **car_P** | 0.079 | 0.078 | **0.090** | ↑ 突破! |
| car_R | 0.627 | 0.419 | 0.455 | ↗ 回升 |
| truck_P | 0.000 | 0.057 | 0.019 | P↓ (FP增) |
| truck_R | 0.000 | 0.059 | 0.138 | R+134% |
| bus_R | 0.000 | 0.000 | **0.287** | ★ 新类爆发 |
| bus_P | 0.000 | 0.002 | 0.009 | |
| ped_P | 0.001 | 0.001 | **0.024** | 48x! |
| ped_R | 0.067 | 0.026 | 0.145 | R+458% |
| cone_R | 0.000 | 0.000 | 0.160 | 新类 |
| bicycle_R | 0.000 | 0.191 | 0.000 | BUG-17振荡 |
| **bg_FA** | 0.222 | 0.199 | **0.331** | ⚠️ +66% |
| off_cx | 0.056 | 0.039 | 0.056 | 回退 (新类拉偏) |
| off_cy | 0.069 | 0.097 | 0.082 | ✅ 改善 |
| off_th | 0.174 | 0.150 | 0.169 | 回升 (新类拉偏) |

### @8000 决策矩阵 (Critic 确认)

| @8000 car_P | 行动 |
|-------------|------|
| > 0.12 | 架构验证, 继续到 @17000 看 LR decay |
| 0.08-0.12 | 方向正确, 继续 |
| 0.05-0.08 | 调参: per_class_balance 或 bg_weight |
| < 0.05 | 严重问题: 架构级修改 |

| @8000 bg_FA | 行动 |
|-------------|------|
| < 0.30 | 正常收敛 |
| 0.30-0.35 | 可接受, 继续到 LR decay |
| > 0.35 | 需干预 per_class_balance |

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
| **FULL_4000** | **CONDITIONAL** | **继续训练. BUG-17→CRITICAL, BUG-46 new. @8000决策矩阵** |
| **FULL_6000** | **CONDITIONAL** | **继续训练. bg_FA=0.331不告警 (多类代价). car_P可信. bicycle振荡确认** |

---

## 活跃任务

| ID | 目标 | 状态 |
|----|------|------|
| **ORCH_024** | **Full nuScenes 2048+GELU+在线DINOv3** | **IN PROGRESS — 6220/40000 (15.6%), @6000 val ✅, 等 @8000 (~11:30)** |
| **ORCH_025** | pytest 测试框架 | COMPLETED ✅ — 177 passed |
| **ORCH_026** | Plan Q 单类 car 诊断 (mini) | IN PROGRESS/COMPLETED? — GPU 1 ~5h 后进程消失, 等 Admin 报告 |
| ORCH_001-023 | Mini 阶段全部 | COMPLETED |

---

## CEO 已认可的持久结论 (Cycle #110)

**1. Plan Q 单类 Car 诊断 (ORCH_026)**
- 设计: 保持 num_vocal=230, 数据管道过滤, 避免 BUG-27
- 判定: car_P>0.20=类竞争主瓶颈, 0.15-0.20=factor, <0.12=无关

**2. 5 类车辆方案 — 不推荐作为主策略**
- 修 BUG-17 比回避类竞争更直接

**3. LoRA (方案 E) — ORCH_024 后评估**
- 优先级: BUG-17 修复 >> 方案 D >> LoRA

**4. 特征漂移**: frozen DINOv3 可用 (ORCH_024 证明)

---

## 修正后优先级排序 (Critic: @8000 前不做架构修改)

| 排名 | 提案 | 时机 |
|------|------|------|
| 1 | **Deep Supervision** (一行改动) | ORCH_024 后第一个实验 |
| 2 | **BUG-17 修复** (balance_mode='log' 或 weight cap) | @8000 若 car_P<0.08 |
| 3 | **方案 D (历史 occ box 2帧)** | ORCH_024 后 |
| 4 | **Attention Mask / BUG-45 修复** | 与 deep supervision 一起 |
| 5 | **方案 E (LoRA)** | D 之后 |

---

## BUG 跟踪 (关键更新)

| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| **BUG-17** | **CRITICAL** | bicycle 154K FP + 振荡 (0→0.191→0). sqrt balance ~11x car 权重 |
| BUG-33 | MEDIUM | FIXED — DefaultSampler, DDP 偏差可能已修复 |
| BUG-43 | MEDIUM | Conductor 未读代码估算难度 |
| BUG-45 | MEDIUM | OCC head 推理 attn_mask=None, Full 上 12000 KV entries |
| **BUG-46** | **LOW** | accumulative_counts=4, optimizer steps = iter/4 |

---

## 实验评判标准 (永久规则)
1. 单次 <5%: 波动
2. 单次 5-15%: 需下一 eval 同向确认
3. 单次 >15%: 可能有意义
4. 连续 2 次同向 >5%: 可做结论
5. Mini 永远不做架构决策
6. Full: @2000 趋势, @4000 第一可信, @8000 架构决策

---

## 待办 (按优先级)
1. ~~**@2000 val**~~ ✅ car_P=0.079
2. ~~**@4000 val**~~ ✅ car_P=0.078, VERDICT 处理完
3. ~~**@6000 val**~~ ✅ car_P=0.090, VERDICT 处理完
4. **监控 @8000 val** (ETA ~3/9 ~11:30): **架构决策点!**
5. **ORCH_026 结果**: 等 Admin 报告 Plan Q 单类 car 诊断
6. **@8000 单 GPU re-eval**: 确认 DDP 偏差 (BUG-33)
7. **ORCH_024 后实验**: Deep Supervision → Attention Mask → 方案 D

## 已完成 CEO 报告 (本轮)
- `shared/logs/car_precision_investigation.md` — 5 项调查
- `shared/logs/orch024_architecture_detail.md` — 架构详细报告
- `shared/logs/val_dataset.md` — Val 数据集调查
- `shared/logs/oom.log` — OOM 风险分析
- `shared/logs/project_progress_report.md` — 363 行项目进展

## 下一里程碑

| 事件 | iter | ETA |
|------|------|-----|
| ~~@6000 val~~ | ~~6000~~ | ✅ car_P=0.090, bg_FA=0.331 |
| **@8000 val** | **8000** | **~3/9 ~11:30 (修正)** |
| 第一次 LR decay | 17000 | ~3/10 ~10:00 |
| 训练结束 | 40000 | ~3/12 |

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行正常
- 4 GPU 正常 (GPU 1 冲突已解除)
- 磁盘 296 GB 可用

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
- **Mini car_P 天花板 ~0.12-0.13**
- **GELU 加速收敛** — P2@1000 +72% vs P6
