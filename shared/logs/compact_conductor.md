# Conductor 工作上下文快照
> 时间: 2026-03-08 21:10
> 循环: #95 (Phase 2 完成)
> 目的: @2000 val 结果捕获完成, 继续训练到 @4000

---

## CEO 战略方向
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 仅用于 debug。**
> **CEO 决策: 在线 DINOv3 frozen (避免 2.1TB 存储)。**

---

## ★★★★ 当前状态: Full nuScenes @2000 Val 完成! 方向正确, 继续训练

### ORCH_024 训练状态 (Cycle #95)
- **进度**: 2000/40000 (5%), **warmup 完成!** LR=2.5e-06 达目标
- **@2000 val 完成** (21:06:10):
  - **car**: R=0.627, **P=0.0789** (决策矩阵边界值)
  - **pedestrian**: R=0.067, P=0.001 (微弱信号)
  - **barrier**: R=0.003, P=0.001 (微弱信号)
  - **其他 7 类**: 全部 0 (0.57 epochs 预期内)
  - **bg**: R=0.778, **FA=0.222** (< 0.25 ✓)
  - **回归**: cx=0.056, cy=0.069, w=0.020, h=0.006, **th=0.174**
- **决策**: 方向正确, 不中断, 继续训练到 @4000
- **Loss@2000**: 5.53 (cls=3.81, reg=1.72)
- **速度**: 6.3 s/iter, 显存 36-37 GB/GPU (A6000 48GB)
- **ETA**: ~3/11 14:45 完成
- **Checkpoint**: iter_2000.pth 已保存
- **磁盘**: 336 GB 可用, 充足

### Full nuScenes Config
```python
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))
在线 DINOv3 frozen, ViT-7B fp16
lr_mult = 2.0 for proj
max_iters = 40000, warmup = 2000, milestones = [15000, 25000]
num_vocal = 230, 10 classes, sqrt balance, bg_weight = 2.5
val_interval = 2000, 4 GPU DDP
Config: configs/GiT/plan_full_nuscenes_gelu.py
Work dir: /mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu
Data: train 28130, val 6019
```

### @2000 决策矩阵 (已执行)
| ORCH_024 @2000 结果 | 行动 | 实际 |
|---------------------|------|------|
| car_P > 0.15, bg_FA < 0.25 | 架构正确. 继续到 @40000. 方案 D 排队 | — |
| car_P 0.08-0.15, bg_FA < 0.30 | 方向正确但需更多训练. 继续 | — |
| **car_P 0.03-0.08** | **不中断, 继续训练** | **★ car_P=0.0789 (边界)** |
| car_P < 0.03 | 在线 DINOv3 可能有根本问题. 切预提取 175GB | — |

### @4000 决策矩阵 (待定, ETA 3/9 ~01:30)
| 结果 | 行动 |
|------|------|
| car_P > 0.15 | 架构确认, 方案 D 排队 |
| car_P 0.08-0.15, 比 @2000 提升 | 方向正确, 继续 |
| car_P < 0.08, 无明显提升 | 评估是否需调参或改架构 |

---

## CEO 架构审计结果 (3 轮审计, Cycles #87-94)

### VERDICT_CEO_STRATEGY_NEXT (Cycle #87)
- **方案 A (1024+GELU)**: ✅ 已被 ORCH_024 (2048+GELU) 涵盖
- **方案 B (DINOv3 unfreeze)**: ❌ 三重否决 (显存 50+>48GB, BUG-35 特征漂移, GPU 全占)
- **方案 C (单类 car)**: ⚠️ 不改 vocab, ORCH_024 car 指标已足够
- **方案 D (历史 occ box)**: ✅ **最有前途的下一步!** 2 帧 1.0s, 轻量条件信号编码, ORCH_024 后执行
- **方案 E (LoRA)**: ✅ 最佳 DINOv3 域适应方案, D 之后执行, rank=16, ~12M 参数

### VERDICT_CEO_ARCH_QUESTIONS (Cycle #92)
- **Q1 (30 token AR)**: 不是主要瓶颈, 但是 contributing factor (MEDIUM)
- **Q2 (Deep Supervision)**: ★★★ **代码已存在!** `git.py:L386-388` 改一行 `loss_out_indices=[8,10,11]`. **BUG-43: Conductor 误估 "1-2天"**
- **Q3 (Attention Mask)**: CEO 直觉正确, hard mask. **BUG-45: OCC head 推理 attn_mask=None, 训练/推理不一致!**
- **Q4 (评判标准)**: 已制定 6 条永久规则

### VERDICT_AR_SEQ_REEXAMINE (Cycle #94)
- **维持 "非主要瓶颈", 上调为 MEDIUM contributing factor**
- **瓶颈排序**: DINOv3→BEV 投影 (HIGH) > 类别不平衡 (HIGH) > 30 token AR+exposure bias (MEDIUM) > BUG-45 (MEDIUM)
- **关键发现: finished_mask 机制** — 大部分 cell 背景→Slot1=END→实际解码仅 1 token
- **验证**: per-slot 指标提取 (方案 A, 零成本), 从 ORCH_024 @2000 eval 提取

---

## 修正后优先级排序 (综合所有审计)

| 排名 | 提案 | 实现难度 | 时机 |
|------|------|---------|------|
| 1 | **Deep Supervision** (改一行配置) | **零** | ORCH_024 后第一个实验 |
| 2 | **评判标准 6 条规则** | 零 (流程) | 已写入 MASTER_PLAN |
| 3 | **方案 D (历史 occ box 2帧)** | 高 (1-2周) | ORCH_024 后 |
| 4 | **Attention Mask 结构化** | 低 (2-4h) | 与 deep supervision 一起测试 |
| 5 | **BUG-45 修复 (推理 mask)** | 低 | 与上同 |
| 6 | **方案 E (LoRA)** | 中 (2-3天) | D 之后 |
| 7 | **AR 解码长度** | 高 (架构级) | 仅在其他方案无效时 |

### ORCH_024 后实验计划
- **实验 A**: 仅启用 deep supervision `loss_out_indices=[8,10,11]`, 其他不变 → baseline
- **实验 B**: deep supervision + structured attention mask → ablation

---

## 实验评判标准 (永久规则, CEO+Critic 确认)
1. 单次 eval 相对变化 <5%: 不做决策, 标记"波动"
2. 单次 5-15%: 需下一个 eval (间隔 ≥500 iter) 同向确认
3. 单次 >15%: 可能有意义, 排除前 500 iter 数据
4. 连续 2 次同向 >5% (间隔 ≥500 iter): 可做结论
5. Mini 只做代码验证/BUG 发现/粗略趋势, **永远不做架构决策**
6. Full nuScenes: @2000 仅趋势参考, **@4000 第一个可信点**, @8000 架构决策

---

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | Grid token 冗余 |
| BUG-15~17 | HIGH | P5b 解决 |
| BUG-18 | MEDIUM | GT instance 未跨 cell 关联 |
| BUG-19 | HIGH | FIXED — z+=h/2 删除 |
| BUG-20 | HIGH | bus 振荡=mini 数据量天花板 |
| BUG-21 | MEDIUM | off_th 退化, 双层投影结构差异 |
| BUG-22~26 | HIGH/MEDIUM | ckpt/GPU/存储/在线路径 |
| BUG-27 | CRITICAL | Plan K vocab 不兼容 |
| BUG-28 | HIGH | Plan L 双变量混淆 |
| BUG-29 | LOW | Plan K sqrt 单类无意义 |
| BUG-30 | INVALID | GELU 不损害 off_th |
| BUG-31~32 | HIGH/MEDIUM | Plan M/N vocab / off_cy |
| BUG-33 | MEDIUM | FIXED — DDP val sampler |
| BUG-34 | LOW | proj lr_mult |
| BUG-35 | MEDIUM | DINOv3 unfreeze 特征漂移 — frozen only |
| BUG-36 | HIGH | Plan M/N vs P6 对比不公平 |
| BUG-37 | HIGH | P5b 基线修正: car_P=0.116 |
| BUG-38 | LOW | Critic 预测准确, 仅延迟 500 iter |
| BUG-39 | MEDIUM | 因式参数化有效, 退化≠无效 |
| BUG-40 | HIGH | Critic审计链失误 |
| BUG-41 | HIGH | Plan O warmup=max_iters, 完全无效 |
| BUG-42 | MEDIUM | Plan P2 全程 full LR 无 decay |
| **BUG-43** | **MEDIUM** | **Conductor 未读代码估算 Deep Supervision "1-2天", 实际一行** |
| **BUG-44** | **LOW** | **Deep supervision 各层共享 vocab embedding** |
| **BUG-45** | **MEDIUM** | **OCC head 推理 attn_mask=None, 训练/推理不一致** |

---

## VERDICT 判决汇总

| ID | 判决 | 关键结论 |
|----|------|---------|
| P2_FINAL_FULL_CONFIG | PROCEED | Full nuScenes 2048+GELU! Mini 阶段结束! |
| CEO_STRATEGY_NEXT | CONDITIONAL | 方案A已涵盖, B否决, D最有前途, 等@2000 |
| CEO_ARCH_QUESTIONS | CONDITIONAL | Deep Supervision零成本#1, BUG-43/44/45 |
| AR_SEQ_REEXAMINE | CONDITIONAL | 维持非主要瓶颈, 上调MEDIUM, finished_mask缓解 |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| **ORCH_024** | **Full nuScenes 2048+GELU+在线DINOv3** | **IN PROGRESS — 2000/40000, @2000 val 完成, 等 @4000** |
| ORCH_001-023 | Mini 阶段全部 | COMPLETED |

---

## 待办 (按优先级)
1. ~~**捕获 @2000 val 结果**~~ ✅ 完成: car_P=0.0789, 继续训练
2. **监控 @4000 val** (3/9 ~01:30): **第一个可信评估点** — 关键里程碑
3. **Per-slot 指标提取**: 需要修改 eval 代码提取 per-slot 数据 (方案 A, 零成本)
4. **ORCH_024 后实验准备**: Deep supervision 配置 (一行改动)
5. **方案 D 代码规划**: 修改 `LoadAnnotations3D_E2E` 和 `GenerateOccFlowLabels` 加载历史 2 帧

## Mini 阶段基线 (存档)
| 实验 | car_P@best | 结论 |
|------|-----------|------|
| P5b (1024+GELU) | 0.116 | 基线 |
| P6 (2048, noGELU) | 0.129 @6000 | BUG-39 但仍超 P5b +11% |
| Plan P2 (2048+GELU) | 0.112 @1500 | GELU 加速收敛 |

## 基础设施
- 5 Agent 全部 UP, all_loops.sh 运行正常
- 4 GPU 全部被 ORCH_024 占用 (36-37 GB/GPU)
- 磁盘 336 GB 可用

## 关键代码位置
- Deep Supervision 开关: `git.py:L386-388` → `loss_out_indices = [8, 10, 11]`
- OCC head 推理 mask (BUG-45): `git_occ_head.py:L1116` → `attn_mask=None`
- Det head 推理 mask (参考): `git_det_head.py:L417-427`
- Proj 层 GELU: `vit_git.py:L238-244`
- finished_mask: `git_occ_head.py:L1100, L1134, L1178`
- Teacher forcing: `git_occ_head.py:L514-519`
- Token layout: Bins 0-167(168) + Classes 168-177(10) + Background 178 + Markers 179-182 + Theta_G 183-218(36) + Theta_F 219-228(10) + Ignore 229 = num_vocal 230

## 实验设计教训
- **每次只改一个变量** (BUG-27/28)
- **vocab 大小变化 = 实验无效** (BUG-27/31)
- **DDP val 必须显式声明 sampler** (BUG-33)
- **DDP 偏差方向不可预测** — 必须单GPU re-eval (BUG-37)
- **warmup 不能等于 max_iters** (BUG-41)
- **max_iters 必须大于 first milestone** (BUG-42)
- **500 iter 不够验证** — 需 ≥2000 iter on mini, ≥4000 on full
- **GELU 加速收敛** — P2@1000 +72% vs P6
- **Mini car_P 天花板 ~0.12-0.13**
- **不读代码就估算实现难度 = BUG** (BUG-43)
