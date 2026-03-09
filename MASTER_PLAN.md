# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-09 ~04:20 (循环 #110 Phase 1)

## 🚨 活跃告警 (2026-03-09 03:20)
> **GPU 1 资源冲突**: ORCH_026 (Plan Q, PID 908307, 11 GB) 与 ORCH_024 共享 GPU 1 → 显存 97.4% → ORCH_024 从 6.3s 减速到 17s/iter (2.7x)
> **选项 A**: 让 Plan Q 跑完 (~3-5h), ORCH_024 延迟 ~3h, OOM 风险持续
> **选项 B**: Kill Plan Q, 保护 ORCH_024, 之后再跑诊断
> **需 CEO 决策**

## CEO 战略转向 (2026-03-08)
> **不再以 Recall/Precision 为最高目标，不再高度预警红线。**
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 数据集仅用于 debug。**

## 当前阶段: ★★★★ Full nuScenes @4000 Val + VERDICT 完成! 继续到 @8000 | BUG-17 升级 CRITICAL | BUG-46 新发现

### ★★★★ VERDICT_P2_FINAL_FULL_CONFIG 核心判决 (Critic, Cycle #86)

**判决: PROCEED — Full nuScenes 使用 2048+GELU, 立即启动!**

**核心结论**:
1. **GELU for Full nuScenes**: 非线性容量必要, 收敛更快 (@1000 +72%), 所有反对意见已被驳回
2. **P2@2000 回调 = BUG-42 (LR 问题)**: max_iters=2000 < first milestone@2500, P2 全程 full LR 无 decay
3. **跳过 Plan O2**: 直接 Full nuScenes 测在线路径, mini 在线数据不可靠 (BUG-27/31/41)
4. **P6@6000 re-eval 不需要**: 不影响任何决策
5. **Critic 纠正**: off_th 收敛到 ~0.19-0.20 与 GELU 无关, Conductor off_th 对比有误导性

**Full nuScenes Config (Critic 推荐)**:
```python
proj: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))
在线 DINOv3 frozen (不 unfreeze, BUG-35)
lr_mult = 2.0 for proj
max_iters = 40000, warmup = 2000, milestones = [15000, 25000]
num_vocal = 230, 10 classes, sqrt balance, bg_weight = 2.5
BUG-33 fix: val DistributedSampler
```

**Mini 验证阶段总结 (Critic)**:
1. DINOv3 Layer 16 特征有效
2. 2048 宽投影优于 1024 (offset 精度 -30-38%)
3. GELU 必要 (去 GELU 是 BUG-39/40 错误)
4. sqrt balance 有效但 mini 振荡不可避免 (BUG-20)
5. DDP val 需 DistributedSampler (BUG-33)
6. DINOv3 frozen only (BUG-35)
7. Mini car_P 天花板 ~0.12-0.13

### VERDICT_PLAN_P_FAIL_P6_TREND 核心判决 (Critic, Cycle #81)

**判决: CONDITIONAL → SUPERSEDED by VERDICT_P2_FINAL_FULL_CONFIG**

**BUG-39 CRITICAL → MEDIUM (Critic 重评)**: P6 数学退化确实存在 (双 Linear 无 GELU = 单 Linear), 但 **P6@3500 car_P=0.121 > P5b 0.116** 证明因式参数化有独立优化优势: (1) 9.96M vs 3.15M 参数, 梯度更平滑; (2) 隐式核范数正则化; (3) lr_mult=2.0 仍足够。**退化 ≠ 无效**。

**BUG-38 MEDIUM → LOW**: Critic car_P 预测 0.12-0.13 实际准确, 只是延迟 500 iter (15 min). @3500 hit 0.121, @4000 hit 0.126。

**P6@4000 单 GPU re-eval (ORCH_023 Task 1)**:
| 指标 | P6@3500 | **P6@4000** | vs P5b@3000 |
|------|---------|------------|-------------|
| car_P | 0.121 | **0.1263** | **+8.9% ✅** |
| truck_P | 0.069 | **0.0749** | **+74% ✅** |
| bus_P | 0.029 | **0.0351** | +10% |
| bg_FA | 0.287 | **0.2741** | vs 0.189 |
| off_th | 0.196 | **0.1907** | vs 0.195 |

**Plan P @500 FAIL (100% 超参问题)**:
- car_P=0.004, 但 **bg_FA=0.165 历史最低!** — GELU 对 bg/fg 判别有独立强贡献
- lr_mult=1.0+warmup=100+LR_decay@300+500iter → 仅 200 有效训练 iter (vs P6 ~4000 等效)
- **结论: 不能基于此否定 2048+GELU 架构**

**Plan O car_P=0.000 INVALID (BUG-41)**: warmup=max_iters=500, 全程 warmup, 且用 noGELU (未遵循 COND-3). 在线路径验证被阻塞

**BUG-40**: Critic 审计链失误 (BUG-27→BUG-30→去GELU→P6退化). **补充**: Critic 在 @3000 过度反应 (振荡低谷), @3500 数据 500 iter 内反驳

**BUG-30 INVALID**: GELU 不损害 off_th (P5b=0.195≈P6=0.196). 原假设基于 BUG-27 污染数据

**P6 Config (因式参数化, 仍有效 — BUG-39 降级 MEDIUM)**:
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj 层: nn.Sequential(nn.Linear(4096, 2048), nn.Linear(2048, 768))  # 无 GELU, 因式参数化有优化优势
backbone.patch_embed.proj lr_mult = 2.0
balance_mode = 'sqrt', bg_balance_weight = 2.5
max_iters = 6000 (mini), warmup = 500, milestones = [2000, 4000] (相对 begin=500)
```

**Plan P2 Config (唯一干净 GELU 实验, ORCH_023 GPU 1 训练中)**:
```python
classes = 10 类 (num_vocal=230)
load_from = P5b@3000
proj 层: nn.Sequential(nn.Linear(4096, 2048), nn.GELU(), nn.Linear(2048, 768))  # 非线性!
backbone.patch_embed.proj lr_mult = 2.0  # 与 P6 一致!
warmup = 500, milestones = [2000, 4000], max_iters = 2000
balance_mode = 'sqrt', bg_balance_weight = 2.5
# ★ 与 P6 唯一区别: proj_use_activation=True
```

**BLOCKING 条件 (Critic COND-A/B/C)**:
- **COND-1**: ✅ **DONE** — P5b@3000 car_P=0.116, bg_FA=0.189
- **COND-A (BLOCKING)**: Plan P2 2000 iter — @1000 bg_FA<0.25+car_P>0.10 → GELU for full; @2000 vs P6@2000 (0.110) 做最终决定
- **COND-B (NON-BLOCKING)**: P6@4000 re-eval ✅ **DONE** — car_P=0.1263
- **COND-C (NON-BLOCKING)**: Plan O2 (在线+GELU) — Plan O BUG-41 阻塞, 后续需 GELU 版

**Full nuScenes Config 排名 (Critic)**:
1. **Plan P2** (predicted best, 2h 验证) — bg_FA 预计远优于 P6
2. **P6** (validated, car_P=0.121→0.126) — 已超 P5b, 可作 fallback
3. **P5b** (superseded) — car_P=0.116, 已被 P6 超越

**Critic: "2h 投入换取 24-48h 风险规避。ROI > 10x"**

**Plan P2 判定标准 (Critic) + 实际结果**:
| iter | P6 car_P | P2 car_P | P2 bg_FA | 判定 |
|------|----------|----------|----------|------|
| @500 | 0.073 | **0.069** | **0.256** | ❌ 略低于 P6, warmup 期 |
| @1000 | 0.058 | **0.100** | **0.328** | ★ car_P +72%! 类振荡期 bg_FA 高属正常 |
| @1500 | 0.106 | **0.112** | **0.279** | ★★ 超 P6@1500 +5.7%! 超 P6@2000(0.110)! |
| @2000 | **0.110** | **0.096** | **0.295** | ❌ P6 反超. car_R=0.801 极端, ped_P=0 全崩. LR 未 decay 导致 |

> **P2@2000 回调分析**: car_R 飙到 0.801 (P6@2000=0.376), 模型 spam car 预测. 全程 full LR 2.5e-06 无 decay, P6 也要 @2500 decay 后才从 0.111 升到 0.121. **LR 问题, 非架构问题**
> **P2 off_th@2000=0.208 显著优于 P6=0.234 (-11.2%)**: GELU 对方向精度有独立贡献
> **AUDIT_REQUEST_P2_FINAL_FULL_CONFIG 已签发**: 等 Critic 做 Full nuScenes config 最终决策

> Plan L @500=0.054→@1000=0.140, 证明 @500 不具判定意义. P2@500=0.069 > Plan L @500=0.054 (lr_mult=2.0 效果)
> **bg_FA 是最重要指标**: P2 bg_FA<0.20 + car_P≥0.10 → GELU 价值确认

**P6 历程 (BUG-39 降级, 因式参数化有效)**:
- @1000: ❌ 双 FAIL — 类振荡暂态
- @1500: ✅ PASS — 假说 B 完全验证
- @2500: ✅ LR decay 生效 — off_th=0.201
- @3000: CONDITIONAL PASS — BUG-39 争议
- **@3500: ★ car_P=0.121 首超 P5b!** 突破平台
- **@4000: car_P=0.1263, truck_P=0.0749, bg_FA=0.2741** 持续全面改善
- @4500 DDP: car_P=0.126, off_th=0.194, bicycle_P=0.103 ↑↑
- @5000 DDP: car_P=0.128, plateau
- **@6000 FINAL DDP: car_P=0.129, bg_FA=0.274** — **P6 训练完成! GPU 0+2 释放**

### VERDICT_P6_1500 核心判决 (Critic, Cycle #74)

**判决: PROCEED — P6 继续到 @3000, 不需要 P6b**

### VERDICT_P6_3000 核心判决 (Critic, Cycle #78)

**判决: CONDITIONAL — P6 mini 有条件通过, Full nuScenes 启动需满足前置条件**

**核心结论**:
1. **car_P 平台化 0.106-0.111** (@1500-3000): mini 数据天花板, 继续训练不会突破
2. **架构验证通过**: 宽投影 2048 + 无 GELU 的价值在 offset 精度 (off_cx=0.039, off_th=0.205)
3. **P6 未超越 P5b**: car_P=0.106 ≈ P5b@3000 (0.107), 但 P5b 也不可信 (BUG-37)
4. **BUG-36 (HIGH)**: Plan M/N 用 proj=1024, P6 用 2048 — 在线路径对比不公平, 需 Plan O 验证
5. **BUG-37 (HIGH)**: P5b 基线不可信 — 必须做单 GPU re-eval
6. **BUG-38 (MEDIUM)**: Critic 自我纠正 car_P 预测偏乐观 (0.12-0.13 vs 0.106)
7. **bg_FA 与 car_R 负相关**: 类振荡的另一表现, 非独立恶化
8. **Full nuScenes 预期**: car_P 0.20-0.35, 类振荡大幅缓解, 试错成本高 (~24-48h/实验)

**BLOCKING 条件 (修正后, full nuScenes 前必须满足)**:
- **COND-1**: ✅ **DONE** — P5b@3000 单GPU car_P=**0.116**, bg_FA=**0.189**; P5b@6000 car_P=0.115
- **COND-2 (修正)**: Plan P (2048+**GELU**+lr_mult=1.0) 500 iter → ORCH_022, GPU 1
- **COND-3 (修正)**: Plan O (在线+2048+**GELU**) 500 iter → Plan O 当前运行版本是 noGELU (BUG-39), 需后续 GELU 版本验证

**P6 @3500 预测 (Critic) → 被数据反驳**: Critic 预测 car_P ~0.11 不超 0.115, 实际 @3500=0.121, @4000=0.1263. BUG-38→LOW

**P6 mini 运行至 @6000**: @4000 已全面超 P5b, @6000 为最终保险 (ETA ~15:00)

**Full nuScenes 路线 (VERDICT_P2_FINAL_FULL_CONFIG 最终决定)**:
1. ✅ **Plan P2 COMPLETED**: GELU 确认 (@1000 +72%, @1500 +5.7%). BUG-42: @2000 回调 = LR 问题
2. ✅ **Config 选择**: **2048+GELU + 在线 DINOv3 frozen** (Critic PROCEED)
3. **ORCH_024 IN PROGRESS**: 2000/40000, **warmup 完成!** LR=2.5e-06 达目标. **@2000 val 完成!** iter_2000.pth 已保存. Loss@2000=5.53

**★★★ Full nuScenes @2000 Val 结果 (21:06:10)**:
| 类别 | Recall | Precision | GT Count |
|------|--------|-----------|----------|
| **car** | **0.627** | **0.0789** | 100454 |
| pedestrian | 0.067 | 0.001 | 16135 |
| barrier | 0.003 | 0.001 | 15569 |
| truck/bus/trailer/CV/moto/bicycle/cone | 0.0 | 0.0 | — |
| **bg** | **R=0.778** | **FA=0.222** | — |
| **回归** | cx=0.056 | cy=0.069 | w=0.020, h=0.006, th=0.174 |

**@2000 决策矩阵判定**: car_P=0.0789 落在 0.03-0.08 边界 → "不中断, 继续训练"

**★★★ Full nuScenes @4000 Val 结果 (01:35:32, 1.14 epochs) — 第一个可信评估点**:
| 类别 | @2000 R | @4000 R | @2000 P | @4000 P | 变化 |
|------|---------|---------|---------|---------|------|
| **car** | 0.627 | **0.419** | 0.079 | **0.078** | P持平, R-33% (停止spam) |
| **truck** | 0.000 | **0.059** | 0.000 | **0.057** | ✅ 新类出现! |
| **bicycle** | 0.000 | **0.191** | 0.000 | **0.001** | ✅ 新类出现! |
| bus | 0.000 | 0.0003 | 0.000 | 0.002 | 微弱信号 |
| ped | 0.067 | 0.026 | 0.001 | 0.001 | 资源转向 |
| **bg** | R=0.778 | **R=0.801** | FA=0.222 | **FA=0.199** | ✅ 首次<0.20! |

| 回归 | @2000 | @4000 | 变化 |
|------|-------|-------|------|
| off_cx | 0.056 | **0.039** | -30% ✅✅ |
| off_cy | 0.069 | **0.097** | +41% ❌ |
| off_th | 0.174 | **0.150** | -14% ✅✅ |
| off_w | 0.020 | **0.016** | -20% ✅ |

**Conductor 分析**: 典型类别再平衡 (类似 mini P6@1000 振荡). car_P 持平<1% = 波动 (规则#1). truck/bicycle 新出现 = 积极. bg_FA/off_th/off_cx 大幅改善. off_cy 恶化需关注.

**★★★ VERDICT_FULL_4000 (Critic, Cycle #105): CONDITIONAL — 继续训练不中断**
- **BUG-46 (NEW, LOW)**: `accumulative_counts=4` 使实际优化步数 = iter/4. @4000 = 500 post-warmup optimizer steps. **Full @4000 实际训练量 < Mini @1000!** 解释 car_P 低于 mini 参考值
- **BUG-17 升级 CRITICAL**: bicycle 154,845 FP (R=0.191, P=0.001). sqrt balance 给 bicycle ~11x car 的 per-sample loss 权重. Full nuScenes 实证确认有害
- **car_P 持平符合预期**: 500 post-warmup optimizer steps 远不够. LR decay @17000. Mini 突破在 LR decay 后
- **off_cy 恶化可解释**: 单目深度估计固有困难 + 多类引入新深度分布 + proj_z0=-0.5m 对不同类别精度不同. @6000 观察趋势
- **DDP BUG-33**: DefaultSampler 可能已修复, @8000 单 GPU re-eval 确认
- **BUG-45 补充**: Full 上 400 cells × 30 tokens = 12000 KV entries 累积, 远超 mini 信噪比
- **Critic 建议**: @8000 前不做任何架构修改 (包括 deep supervision/attention mask)
- **@8000 决策矩阵**:

| @8000 car_P | 行动 |
|-------------|------|
| > 0.12 | 架构验证, 继续到 @17000 看 LR decay 效果 |
| 0.08-0.12 | 方向正确, 继续 |
| 0.05-0.08 | 调参: 考虑关闭 per_class_balance 或调低 bg_balance_weight |
| < 0.05 | 严重问题: 需架构级修改 |

**Full nuScenes 训练数据汇总 (经 Critic 校正)**:
| 指标 | @2000 | @4000 | 趋势 | optimizer_steps |
|------|-------|-------|------|----------------|
| car_P | 0.079 | 0.078 | → (持平) | 500 → 1000 |
| car_R | 0.627 | 0.419 | ↓ (再平衡) | — |
| truck_P | 0 | 0.057 | ↑ (新类) | — |
| bg_FA | 0.222 | 0.199 | ↓ ✅ | — |
| off_cx | 0.056 | 0.039 | ↓ ✅ | — |
| off_cy | 0.069 | 0.097 | ↑ ❌ | — |
| off_th | 0.174 | 0.150 | ↓ ✅ | — |

**VERDICT_CEO_STRATEGY_NEXT (CONDITIONAL — 等 @2000 再决策)**:
- **方案 A (1024+GELU)**: ✅ 已被 ORCH_024 (2048+GELU) 涵盖, 无需额外实验
- **方案 B (DINOv3 unfreeze)**: ❌ 三重否决 (显存超限 50+GB>48GB, BUG-35 特征漂移, GPU 全占用)
- **方案 C (单类 car)**: ⚠️ 不改 vocab, ORCH_024 car 指标已足够替代
- **方案 D (历史 occ box)**: ✅ 最有前途的下一步! ORCH_024 后执行. **2 帧 1.0s** (CEO 建议 1 帧, Critic 推荐 2 帧). 编码用轻量条件信号 (方案 3)
- **方案 E (LoRA)**: ✅ 最佳 DINOv3 域适应方案. 在 D 之后执行. rank=16, ~12M 参数, 显存 +2 GB
- **方案 F (多尺度特征)**: ⚠️ 搁置, 复杂度高, 当前不紧急
- **方案 G (等 @2000)**: ✅ 最正确的当下行动
- **优先级**: ORCH_024 >> 方案 G >> 方案 D >> 方案 E >> F >> C >> B >> A
- **@2000 决策矩阵**: car_P>0.15 → 继续+排队 D; 0.08-0.15 → 继续; 0.03-0.08 → 调参; <0.03 → 切预提取

**VERDICT_CEO_ARCH_QUESTIONS (CONDITIONAL — BUG-43 修正优先级)**:
- **Q1 (30 token AR 解码)**: 不是主要瓶颈. OCC per-query 30 token 是 GiT 最长的 (det=5), 但 per-cell 并行, 错误不跨 cell 传播. 低优先级
- **Q2 (Deep Supervision)**: ★★★ **代码已存在!** `git.py:L386-388` 只需改一行 `loss_out_indices=[8,10,11]`. **BUG-43: Conductor 未读代码误估 "1-2 天"**. 零成本, 应为 #1 优先级
- **Q3 (Attention Mask)**: CEO 直觉正确, 用 hard mask. **BUG-45: OCC head 推理 attn_mask=None, 训练有 causal+跨 cell 隔离, 不一致!** 应在 Full nuScenes 上验证, 非 mini
- **Q4 (评判标准)**: 基本合理. 补充: @2000=0.57 epoch 仅趋势参考; @4000=1.14 epoch 第一个可信点; @8000 可做架构决策. Mini 上永远不做架构决策
- **修正后优先级**: Q2 (Deep Supervision, 零成本) >> Q4 >> 方案D >> Q3 (Mask) >> 方案E >> Q1 >> 方案F
- **ORCH_024 后第一个实验**: 实验A=仅启用 deep supervision; 实验B=deep supervision + structured mask. A/B ablation
- **BUG-43 (MEDIUM)**: Conductor 未读代码就给 deep supervision 实现估算. 已纠正
- **BUG-44 (LOW)**: Deep supervision 各层共享 vocab embedding, 理论风险, 暂不处理
- **BUG-45 (MEDIUM)**: OCC head 推理 `attn_mask=None` vs 训练有显式 mask. 参考 `git_det_head.py:L417-427` 修复

**实验评判标准 (永久规则, CEO+Critic 确认)**:
1. 单次 eval 相对变化 <5%: 不做决策, 标记"波动"
2. 单次 5-15%: 需下一个 eval (间隔 ≥500 iter) 同向确认才可做条件性结论
3. 单次 >15%: 可能有意义, 但排除前 500 iter 数据
4. 连续 2 次同向 >5% (间隔 ≥500 iter): 可做结论
5. Mini 实验只做代码验证/BUG 发现/粗略趋势, 永远不做架构决策
6. Full nuScenes: @2000 仅趋势参考, @4000 第一个可信点, @8000 架构决策

**VERDICT_AR_SEQ_REEXAMINE (CONDITIONAL — 维持"非主要"但上调为 contributing factor)**:
- **Critic 维持结论**: 30 token AR 不是主要瓶颈, 但从"可忽略"上调为 **MEDIUM contributing factor**
- **瓶颈排序**: DINOv3→BEV 投影 (HIGH) > 类别不平衡 (HIGH) > 30 token AR+exposure bias (MEDIUM) > BUG-45 mask 不一致 (MEDIUM)
- **关键发现: finished_mask 机制** (`git_occ_head.py:L1100-1134`): 大部分 cell 是背景→Slot1=END→实际解码仅 1 token. 平均解码长度远小于 30
- **Exposure bias**: 训练用 teacher forcing (GT input), 推理用自身预测. 30 token 的 train/inference gap 确实比 5 token 更大
- **验证方案**: 方案 A (per-slot 指标提取, 零成本) >> C (仅评估 Slot 1) >> B (1-slot 实验, 不推荐). ORCH_024 @2000 eval 时应提取 per-slot 数据
- **归因确认**: "GiT 序列更长" 的错误说法是 Conductor 的, 不是 Critic 的. CEO 的事实理解完全正确
- **CEO 补充 (Cycle #96)**: cell 内 Slot 1→2→3 是串行 AR, 错误从近层累积到远层. "不跨 cell" 掩盖了 within-cell exposure bias. per-slot 验证将确认 Slot 3 是否显著差于 Slot 1

**BUG-33 修复完成**:
- ✅ ORCH_019: 5 ckpt 单 GPU re-eval, @2500+ DDP 偏差 <2%
- ✅ config 已加 DistributedSampler
- ⚠️ car_P DDP 偏差最大 ±10%@1500, @2000+ <2%

**Plan L 宽投影净效果 (Critic 评估: 正面但信号弱)**:
| 指标 | Plan L @2000 | P5b @2000 | 差值 |
|------|-------------|-----------|------|
| car_P | 0.111 | 0.094 | +0.017 ✅ |
| car_R | 0.512 | 0.856 | -0.344 ❌ (proj 随机初始化暂态) |
| bg_FA | 0.331 | 0.282 | +0.049 ❌ (10类+容量增加) |
| off_cy | 0.074 | 0.113 | -0.039 ✅ |

**Plan M/N @1000 快速评判标准**: M_car_P > 0.077 → 在线路径有价值; 否则 mini 无优势

### 诊断实验完整轨迹 (截至 @1500)

**Plan K 完整最终轨迹 (单类 car, 预提取) — COMPLETED ✅**:
| Ckpt | car_R | car_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.629 | 0.064 | 0.183 | 0.073 | 0.082 | 0.228 |
| @1000 | 0.507 | 0.047 | 0.211 | 0.056 | 0.073 | 0.254 |
| @1500 | 0.639 | 0.060 | 0.185 | 0.059 | 0.206⚠️ | 0.212 |
| **@2000** | 0.602 | 0.063 | **0.166** | 0.054 | 0.171 | **0.191** |

**Plan L 完整最终轨迹 (10类+宽投影2048, 预提取) — COMPLETED ✅**:
| Ckpt | car_R | car_P | truck_R | bus_R | constr_R | ped_R | cone_R | barrier_R | bg_FA | off_cy | off_th |
|------|-------|-------|---------|-------|----------|-------|--------|-----------|-------|--------|--------|
| @500 | 0.084 | 0.054 | 0 | 0.017 | 0.088 | 0.451 | 0 | 0 | 0.237 | 0.085 | 0.277 |
| @1000 | 0.338 | **0.140** | 0.263 | 0.334 | 0.212 | 0.096 | 0.170 | 0.425 | 0.407 | 0.080 | 0.242 |
| @1500 | 0.572 | 0.103 | 0.015 | 0.024 | 0.637 | 0.105 | 0.556 | 0 | 0.447 | **0.069** | 0.225 |
| **@2000** | 0.512 | 0.111 | 0.360 | 0.101 | 0.212 | 0.425 | 0.182 | 0 | 0.331↓ | 0.074 | 0.205 |

**Plan M 完整轨迹 (在线 DINOv3, unfreeze) — COMPLETED ✅**:
| Ckpt | car_R | car_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.621 | 0.052 | 0.220 | 0.088 | 0.102 | 0.217 |
| @1000 | **0.699** | 0.049 | 0.249 | 0.079 | 0.090 | 0.232 |
| @1500 | **0.489↓↓** | 0.047 | 0.182 | 0.071 | 0.098 | 0.194 |
| **@2000** | 0.507 | 0.049 | **0.188** | **0.066** | 0.079 | 0.223 |

**Plan N 完整轨迹 (在线 DINOv3, frozen) — COMPLETED ✅**:
| Ckpt | car_R | car_P | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.618 | 0.050 | 0.219 | 0.088 | 0.104 | 0.206 |
| @1000 | 0.661 | 0.050 | 0.250 | 0.080 | 0.078 | 0.231 |
| @1500 | 0.630 | 0.045 | 0.236 | 0.080 | 0.081 | 0.229 |
| **@2000** | 0.513 | 0.045 | **0.198** | **0.071** | 0.084 | **0.217** |

> **最终结论: Frozen >> Unfreeze** — M@1500 car_R 崩塌 0.699→0.489, N 稳定到 @2000 才自然下降 (0.630→0.513). 特征漂移确认 (BUG-35)
> **预提取 > 在线** (car_P/car_R/bg_FA 全面领先); 在线唯一优势: off_cy
> 在线路径 car_P 始终 ~0.05, 不达标. 均有 BUG-31 (vocab mismatch)

**car_P 完整趋势对比 (P5b 单GPU可信值, P6 单GPU可信值, Plan P2 单GPU)**:
| Iter | Plan L (2048+GELU) | **P5b (1024+GELU)** | **P6 (2048+noGELU)** | **Plan P2 (2048+GELU)** |
|------|-------------------|---------------------|---------------------|------------------------|
| @500 | 0.054 | 0.080 (DDP) | 0.073 | **0.069** |
| @1000 | **0.140** | 0.089 (DDP) | 0.058 | **0.100 (+72%!)** |
| @1500 | 0.103 | 0.091 (DDP) | 0.106 | **0.112 (+5.7%)** |
| @2000 | **0.111** | 0.094 (DDP) | **0.110** | 0.096 (-12.8%, LR未decay) |
| @3000 | — | **0.116 ✅** | 0.106 | — |
| @3500 | — | — | **0.121 ✅** | — |
| @4000 | — | — | **0.1263 ✅✅** | — |
| @5000⚠️DDP | — | — | 0.128 (DDP) | — |
| **@6000 FINAL** | — | — | **0.129 (DDP) ✅+11%** | — |

> **★★★ GELU 优势确认**: P2@1000 +72%, P2@1500 +5.7% vs P6 同 iter
> **P2@1500=0.112 已超 P6@2000=0.110**: GELU 收敛速度约 P6 的 1.3x
> **P6 COMPLETED @6000**: car_P=0.129 (DDP, +11% vs P5b), plateau 确认
> **P2@2000 (~15:55) 是最终判定点**: 预期 car_P≥0.112, 确认 Full nuScenes 用 2048+GELU

**★★ P5b vs P6 可信对比 (均为单GPU)**:
| 指标 | P5b@3000 | P6@3000 | **P6@4000** | P6@4000 vs P5b |
|------|----------|---------|------------|----------------|
| **car_P** | **0.116** | 0.106 | **0.1263** | **+8.9% ✅✅** |
| **car_R** | 0.675 | 0.617 | 0.5459 | -19% (精度换召回) |
| **bg_FA** | **0.189** | 0.297 | 0.2741 | +45% ❌ (仍偏高) |
| off_th | 0.195 | 0.196 | **0.1907** | **-2.2% ✅** |
| **off_cx** | 0.063 | **0.039** | 0.043 | **-32% ✅✅** |
| **off_cy** | 0.105 | **0.073** | 0.076 | **-28% ✅✅** |
| **truck_P** | 0.043 | 0.054 | **0.0749** | **+74% ✅✅** |

> **P6@4000 已全面超越 P5b**: car_P+truck_P+off_cx+off_cy+off_th 五项胜出, 仅 bg_FA 偏高 (GELU 可能改善)

**四路诊断最终结论 (Plan K/L COMPLETED, Plan M/N @1500 done)**:
1. **宽投影有轻微帮助**: Plan L car_P=0.111 > P5b@2000=0.094 (+18% 同 iter)
2. **宽投影显著改善 off_cy**: Plan L 0.069-0.074 优于 P5b 全程最优 (0.085)
3. **类振荡是结构性问题**: Plan L 10 类振荡与 P5b 相同 (BUG-20)
4. **在线 DINOv3 精度未达标**: car_P ~0.05 < 0.077 阈值 → 在线路径在 mini 无优势
5. **Frozen >> Unfreeze**: M@1500 car_R 崩塌 0.699→0.489 (-21%), DINOv3 微调导致特征漂移 (BUG-35)
6. **在线路径暂判不达标**: mini 上 car_P ~0.05, 但 proj_hidden_dim=1024 (非 2048), full nuScenes 可能不同
7. **Critic 建议调和 CEO 决策**: mini 用预提取; full nuScenes 重测在线+宽投影 2048+frozen

### ★ P6 Val 轨迹 — 单 GPU 可信数据 (ORCH_019 re-eval 完成)

| Ckpt | car_R | car_P | truck_R | bus_R | constr_R | ped_R | cone_R | barrier_R | bg_FA | off_cx | off_cy | off_th |
|------|-------|-------|---------|-------|----------|-------|--------|-----------|-------|--------|--------|--------|
| @500 | 0.231 | 0.073 | 0.115 | 0.056 | 0.043 | 0.031 | 0.000 | 0.033 | **0.173** | 0.079 | **0.072** | 0.259 |
| @1000 | 0.252 | 0.058↓ | 0.043↓ | 0.168↑ | **0.285↑** | 0.012 | 0.002 | 0.166↑ | **0.352↑** | 0.105↓ | 0.077 | 0.220 |
| @1500 | **0.499↑** | **0.106↑** | 0.000↓ | 0.123 | 0.087↓ | 0.002 | 0.109 | 0.010↓ | **0.250↓** | **0.038↑** | 0.069 | 0.246 |
| @2000 | 0.376↓ | **0.110** | 0.179↑ | 0.302↑ | 0.181↑ | 0.005 | 0.222↑ | 0.000 | 0.300↑ | 0.085↓ | **0.067** | 0.234 |
| @2500 | 0.516↑ | **0.111** | 0.356↑ | 0.518↑ | 0.001↓ | 0.170↑ | 0.082 | 0.091↑ | 0.336↑ | 0.058 | 0.076 | **0.201↑** |
| **@3000** | **0.617↑** | **0.106** | 0.054 | 0.027 | — | — | — | — | **0.297↓** | **0.039** | 0.073 | **0.196↓** |
| **@3500** | 0.577 | **0.121↑** | **0.069↑** | 0.029 | — | — | — | — | **0.287↓** | 0.039 | 0.072 | **0.196** |
| **@4000** ✅单GPU | **0.5459** | **0.1263↑** | **0.0749↑** | **0.0351↑** | 0.060 | 0.095 | — | 0.013 | **0.2741↓** | 0.043 | 0.076 | **0.1907↓** |
| **@4500** ⚠️DDP | — | **0.126** | 0.073 | 0.044 | — | — | — | — | **0.277↓** | 0.042 | 0.076 | **0.194↓** |
| **@5000** ⚠️DDP | — | **0.128↑** | **0.078↑** | 0.045 | — | — | — | — | **0.275↓** | 0.043 | 0.076 | 0.197 |
| **@5500** ⚠️DDP | — | 0.128 | — | — | — | — | — | — | **0.273↓** | — | — | 0.199 |
| **@6000 FINAL** ⚠️DDP | 0.541 | **0.129** | 0.076 | 0.048 | — | 0.054 | — | — | 0.274 | 0.043 | 0.076 | 0.200 |

> @3000 已由 Admin 单 GPU re-eval (12:35). @3500 已由 Admin 单 GPU re-eval (13:06).
> **★★ @4000 单GPU car_P=0.1263 (+8.9% vs P5b!)** truck_P=0.0749 (+74%), bg_FA=0.2741, off_th=0.1907
> **@4500 DDP (第二次 LR decay 后)**: car_P=0.126 稳定, off_th=**0.194** (<0.20!), bicycle_P=0.103 ↑↑
> **bg_FA 持续改善**: 0.352(@1000)→0.297(@3000)→0.274(@4000)→**0.277(@4500 DDP)**
> **第二次 LR decay @4500**: base_lr 5e-06→5e-07, LR=2.5e-08. P6 @6000 ETA ~15:12

**@500**: bg_FA=0.173 全实验最低
**@1000 崩塌**: 类振荡爆发 → 双 FAIL (暂态)
**@1500 反弹**: car_P=0.106, off_cx=0.038 历史最佳
**@2000 回摆**: 小类反弹, car_P 稳定 0.110
**@2500 LR decay**: off_th=0.201 首破 0.21, car_P=0.111
**★ @3000 CONDITIONAL PASS (单GPU 可信数据)**: car_R=0.617, **bg_FA=0.297 首次<0.30!**, **off_th=0.196 首次<0.20!**, truck_P=0.054
**car_P 平台化**: @1500-3000 恒定 0.106-0.111 — mini 天花板 (BUG-38)
**@3000 是目前最均衡的 checkpoint** (Admin 评估)

**DDP vs 单 GPU 偏差 (BUG-33 ORCH_019 验证)**:
| Ckpt | car_P (DDP→单GPU) | car_R (DDP→单GPU) | bg_FA (DDP→单GPU) | off_th (DDP→单GPU) |
|------|-------------------|--------------------|--------------------|---------------------|
| @500 | 0.073→0.073 (=) | 0.252→0.231 (-8%) | 0.163→0.173 (+6%) | 0.236→0.259 (+10%) |
| @1000 | 0.054→0.058 (+7%) | 0.197→0.252 (+28%) | 0.323→0.352 (+9%) | 0.250→0.220 (-12%) |
| @1500 | **0.117→0.106 (-9%)** | **0.681→0.499 (-27%)** | 0.278→0.250 (-10%) | 0.259→0.246 (-5%) |
| @2000 | 0.111→0.110 (-1%) | 0.428→0.376 (-12%) | 0.327→0.300 (-8%) | 0.230→0.234 (+2%) |

> BUG-33 修正结论: car_P 有小幅偏差 (最大 @1500: -9%), **非完全不受影响**. car_R 偏差最大 (27%). 方向不一致 (非系统性偏高/偏低)

⚠️ Plan K: BUG-27 (vocab mismatch) + BUG-29 (sqrt 单类无意义)
⚠️ Plan L: BUG-28 (双变量混淆)
⚠️ Plan M/N: BUG-31 (继承 BUG-27)

### CEO 在线提取决策 (2026-03-08, Cycle #66)
> CEO: 放弃预提取路线, 走在线 DINOv3 提取以支持完整 nuScenes 训练。
> GPU 1,3 用于在线 DINOv3 + unfreeze 实验 (方案 B), 与 Plan K/L 并行。

### VERDICT_P6_ARCHITECTURE 核心判决 (Critic, Cycle #65)

**判决: CONDITIONAL — 必须先做诊断实验确认瓶颈来源**

**关键发现**:
1. **BUG-23 (HIGH)**: GPU 是 A6000 48GB (非 24GB), 显存约束大幅放松
2. **BUG-26 (MEDIUM)**: 代码只用 CAM_FRONT, 全量 DINOv3 仅需 ~175GB fp16 (非 2.1TB!) → **BLOCKER 降级**
3. **P5b 双层投影已触顶**: @3000-5500 car_P 标准差仅 0.0015
4. **优先级排序**: D (宽中间层 2048) > C (LoRA) > B (Full Unfreeze)
5. **单类 car 实验必须做**: 确认类别竞争是否为瓶颈
6. **历史 occ box 推迟到 P7**: P6 专注数据量+架构改进

**P6 路径 (Critic 推荐)**:
```
Phase 0 (诊断, ~1天):
  └→ 实验 α: 单类 car mini (plan_k_car_only_diag.py)
  └→ 实验 β: 宽中间层 2048 mini (plan_l_wide_proj_diag.py)

Phase 1 (结论驱动):
  ├→ IF α car_P >> β car_P: 类竞争是瓶颈 → per-class head 或解耦
  └→ IF α car_P ≈ β car_P: 特征/架构瓶颈 → 在线 DINOv3 + LoRA (方案 C)

Phase 2: P7 历史 occ box (t-1)
```

### P5 Val 轨迹 (最终 6 个 checkpoint + P4 参照)

| 指标 | P5@3500 | P5@4000 | P5@4500 | P5@5000 | P5@5500 | **P5@6000** | P4@4000 | 红线 |
|------|---------|---------|---------|---------|---------|-------------|---------|------|
| car_R | 0.779 | 0.569 | 0.529 | 0.615 | **0.721** | **0.682** | 0.592 | — |
| car_P | **0.093** | 0.090 | 0.091 | 0.085 | **0.092** | 0.089 | 0.081 | — |
| truck_R | **0.679** | 0.421 | 0.317 | 0.199 | 0.203 | 0.228 | 0.410 | <0.08 OK |
| truck_P | 0.072 | **0.130** | 0.095 | 0.086 | 0.065 | 0.065 | 0.175 | — |
| bus_R | 0.120 | **0.315** | 0.058 | 0.002 | 0.014 | 0.011 | 0.752 | — |
| bus_P | 0.024 | 0.037 | 0.024 | 0.001 | 0.006 | 0.005 | 0.129 | — |
| trailer_R | 0.000 | 0.472 | 0.361 | 0.333 | 0.417 | **0.500** | 0.750 | — |
| trailer_P | 0.000 | 0.006 | 0.005 | 0.033 | **0.046** | 0.043 | 0.044 | — |
| bg_FA | 0.290 | 0.213 | 0.167 | **0.160** | 0.186 | 0.190 | 0.194 | ≤0.25 ✓ |
| offset_cx | 0.066 | **0.051** | 0.083 | 0.053 | 0.064 | 0.066 | 0.057 | ≤0.05 |
| offset_cy | 0.151 | **0.091** | 0.111 | 0.105 | 0.107 | 0.111 | 0.103 | ≤0.10 |
| offset_th | 0.197 | **0.142** | 0.226 | 0.163 | 0.182 | 0.192 | 0.207 | ≤0.20 ✓ |

### P5@4000 — 目前综合最优 checkpoint

| 指标 | P5@4000 | P4@4000 | 对比 |
|------|---------|---------|------|
| car_R | 0.569 | 0.592 | -4% (接近) |
| car_P | **0.090** | 0.081 | **+11%** |
| truck_R | **0.421** | 0.410 | **+3%** |
| truck_P | 0.130 | 0.175 | -26% |
| bus_R | 0.315 | 0.752 | -58% |
| trailer_R | 0.472 | 0.750 | -37% |
| bg_FA | **0.213** | 0.194 | 接近 |
| offset_cx | **0.051** | 0.057 | **达标!** |
| offset_cy | **0.091** | 0.103 | **超越!** |
| offset_th | **0.142** | 0.207 | **大幅超越!** |

**P5@4000 特点**: 四类 Recall 全>0.3 (最均衡), offset 三指标全面超 P4, car_P 超 P4。弱点: bus_R/trailer_R 远低于 P4。

### LR Milestone 延迟问题 (BUG-17)

**已确认**: MMEngine MultiStepLR milestones 为**相对于 begin 参数**的值。

| Config 设置 | 预期触发 | 实际触发 | 状态 |
|------------|---------|---------|------|
| milestone=4000, begin=1000 | iter 4000 | **iter 5000** | 延迟 1000 iter |
| milestone=5500, begin=1000 | iter 5500 | **iter 6500** | **超出 max_iter, 永不触发!** |

**影响**: LR decay @5000 后仅剩 1000 iter 收敛。第二次 decay 不可达。

**当前决策**: 接受单次 decay, 让训练自然完成。理由:
1. P5@4000 已是优秀 checkpoint, 可作为回退点
2. @5000 decay 后 1000 iter 仍有望收敛 (P4 首次 decay 后也快速稳定)
3. 如果不满意, 可从 P5@4000 启动 P5b 并纠正 milestones
4. 已签发 AUDIT_REQUEST_P5_MID → Critic 评估是否需要 P5b

### ★ P5 训练完成 — 终极评估 ★

**P5 最优 Checkpoint 综合排名:**
1. **P5@4000** — 类别全平衡 (4 类>0.3), offset_th=0.142/cy=0.091/cx=0.051 全面最优 → **P5b 起点**
2. **P5@5500** — car_R=0.721 最高, car_P=0.092, trailer_P=0.046 首超 P4
3. **P5@6000** — trailer_R=0.500 恢复, truck_R=0.228 止跌, offset_th=0.192 仍达标

**P5 vs P4 (取各指标最优 checkpoint): 9/12 指标超 P4!**
- 超越: car_R(+22%), car_P(+15%), truck_R(+66%), trailer_P(+5%), bg_FA(+18%), offset_cx(+11%), offset_cy(+12%), offset_th(+31%), trailer_R(@3000: 0.556 vs 0.750 接近)
- P4 领先: bus_R/P (P5 最大遗憾), truck_P

**P5 核心贡献**: DINOv3 Layer 16 → offset 精度飞跃 + bg_FA 大幅降低 + car 全面超越
**P5 未解决**: 类别振荡 (bus 坍塌), LR milestone 配置错误, Linear 压缩瓶颈 → P5b 三项修复

**训练已结束**: 6000/6000, GPU 0,2 已释放, checkpoint 在 `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/`

### VERDICT_P5B_3000 核心发现 (Critic 已返回)

**判决: CONDITIONAL — P5b 跑完 6000; P6 从 P5b@3000 启动**

**核心判决**:
1. P5b 继续至 6000 iter（不提前终止），第二次 LR decay @4000 合理
2. **P6 从 P5b@3000 启动**: car_P+bg_FA 为"基础判别力"核心，@3000 两项均历史最佳
3. P6 启动前解决: 词表兼容性验证 (BUG-22)、新类 warmup 策略、off_th 退化 A/B test
4. bus 振荡是 nuScenes-mini 数据量天花板 (BUG-20)，非模型 bug
5. **关键建议**: 不要在 mini 上追求 bus/trailer 稳定; car 是唯一统计显著类别

### 10 类扩展 — COMMITTED (GiT commit `2b52544`)

- classes: 4→10 (car,truck,bus,trailer + construction_vehicle,pedestrian,motorcycle,bicycle,traffic_cone,barrier)
- num_vocal: 224→230, marker_end_id: 176→182, cls_start: 168 不变
- Checkpoint 兼容: vocab_embed 由 BERT tokenizer 动态生成，Head 无固定 vocab 参数
- **不影响当前 P5b** (config 在训练启动时加载), P6 生效

### VERDICT_P5_MID 核心发现 (已归档)

**判决: CONDITIONAL — P5b 是必要的**

**类别振荡根因 (三重冲突):**
1. **DINOv3 Layer 16 语义过强**: 不同于 Conv2d 的纯纹理, Layer 16 含清晰类别表征, 但类别间不均衡 (car 8269 vs trailer 90 = 92:1)
2. **per_class_balance 放大噪声**: 等权平衡让 trailer (90 GT) 的 loss 统计噪声主导部分 batch 梯度, 导致零和振荡
3. **Linear(4096,768) 压缩瓶颈**: 5.3:1 压缩迫使不同类别共享子空间, 改善一个类别时破坏另一个

**BUG-17 升级为 HIGH**: 不仅是 milestone 相对值问题, 还包括 per_class_balance 在极不均衡数据下的振荡问题

**P5b 方案 (从 P5@4000 出发, 三项全修):**
1. **milestones 修正** (必须): `milestones=[2000,3500]` (相对 begin=500, 实际 decay @2500, @4000)
2. **per_class_balance → sqrt 加权** (必须): `weight_c = 1/sqrt(count_c/min_count)`, 缓解 trailer 梯度噪声
3. **双层投影** (必须, CEO 决策): `Linear(4096,1024)+GELU+Linear(1024,768)`, 缓解类别子空间干扰。5.3:1 压缩是结构性瓶颈, sqrt 加权无法解决

**P6 方向**: DINOv3 适配问题解决前不进入 BEV PE。优先级: P5b > P6

### 干预策略

**当前策略: 让 P5 自然完成, 规划 P5b**

- P5 继续运行至 @6000, 收集 LR decay 后数据
- P5 结束后从 P5@4000 启动 P5b (纠正 milestones + sqrt 加权 balance)
- 等 P5 完成后签发 ORCH_010 (P5b)

---

### P5 训练状态 — COMPLETED ✓
- 完成时间: 2026-03-07 23:19, 9/12 指标超 P4

### P5b 训练状态 — COMPLETED ✅ (plan_i_p5b_3fixes)
- **完成时间**: 2026-03-08 06:36, 训练 ~6h40m
- **最终 iter**: 6000/6000, 12 个 checkpoint (iter_500~iter_6000)
- **GPU**: 0 + 2 (已释放 → 诊断实验)
- **P5b 结论**: 代码验证成功, 三项修复均按设计运行, mini 指标已收敛到平台
- **三项修复验证**:
  - [x] 双层投影: Sequential(4096→1024→768) 生效, grad_norm 稳定
  - [x] sqrt 权重: 四类全非零, 但 bus ~1000 iter 周期振荡未根治 (BUG-20: 数据量不足)
  - [x] LR milestones: @2500 decay 已触发, 效果显著 (bg_FA 0.283→0.217, car_P +14%)
- **第二次 LR decay**: @4000 (lr 2.5e-07→2.5e-08)

### ★ P5b@500 首次 Val — sqrt 权重效果显著! ★

| 指标 | P5b@500 | P5@500 | 变化 |
|------|---------|--------|------|
| car_R | 0.856 | 0.932 | ↓8% (类别均衡改善) |
| car_P | **0.080** | 0.055 | **+45%** |
| truck_R | **0.153** | 0.025 | **↑6x! sqrt 权重效果!** |
| truck_P | 0.039 | 0.027 | +44% |
| bus_R | 0.014 | 0.000 | 微弱 (P5 bus @2500 才出现) |
| trailer_R | 0.000 | 0.000 | 样本少 (72), 需更多 iter |
| bg_FA | **0.235** | 0.320 | **↓27%** (继承 P5@4000) |
| offset_cx | **0.068** | 0.189 | **↓64%** (继承 P5@4000) |
| offset_cy | **0.085** | 0.291 | **↓71%** (继承 P5@4000) |
| offset_th | 0.210 | 0.216 | 基本持平 |

**核心发现**:
1. sqrt 权重让 truck_R 提升 6 倍, car_R 相应下降 — 类别竞争向均衡方向移动
2. offset 精度完美继承自 P5@4000, 不受双层投影随机初始化影响
3. bg_FA 起点就在红线内 (0.235 < 0.25)

### ★★ P5b@3000 — 红线 3/5 达标! LR decay 效果显著!

| 指标 | @500 | @1000 | @1500 | @2000 | @2500 | @3000 | @3500 | @4000 | @4500 | @5000 | @5500 | **@6000** |
|------|------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-----------|
| car_R | 0.856 | 0.760 | 0.924 | 0.856 | 0.831 | 0.835 | 0.819 | 0.792 | 0.788 | 0.788 | 0.777 | 0.774 |
| car_P | 0.080 | 0.089 | 0.091 | 0.094 | 0.094 | 0.107 | **0.108** | 0.105 | 0.105 | 0.105 | 0.104 | 0.104 |
| truck_R | 0.153 | **0.568** | 0.390 | 0.340 | 0.287 | 0.205 | 0.234 | 0.229 | 0.238 | 0.239 | 0.243 | 0.240 |
| bus_R | 0.014 | 0.368 | 0.000 | 0.085 | **0.470** | 0.051 | 0.053 | 0.060 | 0.059 | 0.059 | 0.058 | 0.059 |
| trailer_R | 0.000 | 0.000 | 0.000 | 0.028 | **0.444** | 0.389 | 0.417 | 0.417 | 0.417 | 0.417 | 0.417 | 0.417 |
| trailer_P | 0.000 | 0.000 | 0.000 | 0.003 | 0.010 | 0.037 | 0.036 | 0.033 | 0.032 | 0.034 | 0.028 | 0.027 |
| bg_FA | 0.235 | 0.302 | 0.333 | 0.282 | 0.283 | 0.217 | 0.214 | 0.211 | 0.210 | 0.210 | 0.209 | **0.208** |
| off_cx | 0.068 | **0.049** | 0.064 | 0.055 | 0.073 | 0.059 | 0.060 | 0.059 | 0.059 | 0.059 | 0.058 | 0.057 |
| off_cy | **0.085** | 0.122 | 0.144 | 0.113 | 0.112 | 0.112 | 0.116 | 0.132 | 0.130 | 0.132 | 0.134 | 0.134 |
| off_th | 0.210 | **0.168** | 0.203 | 0.208 | 0.212 | 0.200 | 0.206 | **0.196** | 0.202 | 0.201 | 0.202 | **0.198** |

> LR decay: @2500 (2.5e-06→2.5e-07) | @4000 (2.5e-07→2.5e-08) ✅ 两次均已确认

**★ P5b 最终评估 (COMPLETED) ★**:
- **红线 3/5**: truck_R=0.240✅, bg_FA=0.208✅ (全程最低), off_th=0.198✅ (最终达标!)
- **双层投影已触顶**: @3000-6000 car_P 标准差 0.0015, 模型完全冻结
- **代码验证成功**: 三项修复均按设计运行, mini 指标已收敛到平台
- **P6 load_from**: P5b@3000 (Critic 确认, car_P+bg_FA 最优)
- **下一步重点**: 完整 nuScenes 数据集上的性能, 不再纠结 mini 上的红线指标

---

### P4 最终成绩 (存档)
- 7/9 指标历史最佳
- avg_P=0.107 (Precision 瓶颈)

### DINOv3 特征 — 已集成 + BLOCKER 降级
- Layer 16 预提取, 24.15 GB, 323 files (mini)
- PreextractedFeatureEmbed + Linear(4096,1024)+GELU+Linear(1024,768) 投影 (P5b 双层)
- **全量 nuScenes**: 仅 CAM_FRONT (BUG-26), fp16 ~175GB, SSD 可容纳 (528GB free)
- **在线提取路径**: 待实现 (BUG-25), A6000 48GB 显存充足 (BUG-23)
- **架构方案优先级**: D (宽中间层 2048) > C (LoRA) > B (Unfreeze)

---

## 架构审计待办 — 持久追踪

### 紧急修复 — 全部完成
- [x] BUG-2, BUG-8, BUG-10, BUG-11

### 架构/标签优化
- [x] AABB → 旋转多边形 → P4 验证
- [x] DINOv3 离线预提取 + 集成 → P5 RUNNING
- [ ] Score 区分度改进
- [ ] BUG-14: Grid token 冗余

### 3D 空间编码路线图 (VERDICT_3D_ANCHOR + CEO 词汇表方案)

**核心思路 (CEO 决策)**: 复用 GiT 的 vocab_embed 做语义先验注入, 输入输出共享同一语义空间。不需要额外编码器, 只扩展词汇表。

**词汇表扩展 (230→238, +8 先验 token)** (基于 10 类 num_vocal=230):
| Token ID | 名称 | 含义 |
|----------|------|------|
| 230 | PRIOR_CAR | V2X/历史: 此 cell 有 car |
| 231 | PRIOR_TRUCK | V2X/历史: 此 cell 有 truck |
| 232 | PRIOR_BUS | V2X/历史: 此 cell 有 bus |
| 233 | PRIOR_TRAILER | V2X/历史: 此 cell 有 trailer |
| 234 | PRIOR_OCCUPIED | 有东西但类别未知 |
| 235 | PRIOR_EMPTY | 确认空 |
| 236 | PRIOR_EGO_PATH | 自车轨迹经过 |
| 237 | NO_PRIOR | 无先验信息 |

**注入方式 (git.py L328, 3 行代码)**:
```python
prior_token_ids = batch_data['prior_tokens']  # [B, 100], 每个 cell 一个先验 token
prior_embed = self.vocab_embed(prior_token_ids)  # [B, 100, 768]
grid_start_embed = grid_start_embed + prior_embed
```
注: BEV Grid 为 10×10 = 100 cell, 非 20×20。

**V2X 2D box 工作流 (CEO 确认)**:
sender BEV occ box → 2D 刚体变换 (旋转+平移, 用两车相对 pose) → ego BEV 平面 → 检查覆盖的 grid cell → 标记 PRIOR_CLASS token。无需跨视角相机几何。

**训练策略**: 50% 概率清除所有先验 (prior_tokens 全设 NO_PRIOR), 防止模型过度依赖外部信息。

**P6 核心方向 (VERDICT_PLAN_P_FAIL_P6_TREND 修正)**:
- **架构**: 宽投影 2048, BUG-39 降级 MEDIUM — 因式参数化有效, P6@4000 已超 P5b
- **从 P5b@3000 启动**: backbone+head+vocab 完整, 仅 proj 随机初始化
- **投影层 LR**: 2.0 (P6 已验证有效)
- **P6 恢复有效**: car_P=0.1263, 可作 Full nuScenes fallback config
- **Plan P2 是最高优先级**: 2048+GELU+lr_mult=2.0, 2000 iter, GPU 1 (ORCH_023, 训练中)

**分阶段验证 (VERDICT_DIAG_FINAL 更新)**:
- [x] **Phase 0 (诊断)**: Plan K/L/M/N 全部 COMPLETED ✅
- [x] **P6 mini**: @3000 CONDITIONAL PASS — 但 BUG-39 退化架构, 作为负面参考
- [x] **COND-1**: ✅ P5b@3000 单GPU car_P=0.116 (ORCH_020 COMPLETED)
- [x] ~~**COND-2**: Plan P~~ → FAIL
- [x] **COND-A**: ✅ Plan P2 COMPLETED — GELU 确认 (@1000 +72%, @1500 +5.7%)
- [x] **COND-B**: ✅ P6@4000 re-eval DONE — car_P=0.1263
- [x] **COND-C**: ✅ **跳过 Plan O2** — Critic: 直接 Full nuScenes 测在线路径, mini 数据不可靠
- [x] **Full nuScenes**: ✅ **VERDICT PROCEED — 2048+GELU, ORCH_024 已签发!**
- [ ] **P6b**: BEV 坐标 PE + 先验词汇表
- [ ] **P7**: 历史 occ box (t-1) — CEO 批准单时刻 MVP
- [ ] **P7b**: 3D Anchor — 射线采样
- [ ] **P8**: V2X 融合

### 持久追踪: Car Precision 调查结论 (CEO 认可, Cycle #110)

**1. 单类 Car 诊断实验 (Plan Q) — ORCH_026 IN PROGRESS**
- **目的**: 干净回答 "类竞争是否为 car_P 瓶颈" (Plan K 因 BUG-27 无效)
- **设计**: 保持 num_vocal=230 + num_classes=10 不变, 只在数据管道过滤 (避免 BUG-27)
- **预提取特征 + 单 GPU**: 不加载 DINOv3, 可与 ORCH_024 共享 GPU
- **判定标准**: car_P>0.20=类竞争是主瓶颈, 0.15-0.20=contributing factor, 0.12-0.15=不是瓶颈, <0.12=无关
- **状态**: ORCH_026 已签发, Admin 执行中 (GPU 1, 导致 ORCH_024 减速 ⚠️)

**2. 5 类车辆方案 — 不推荐作为主策略**
- 技术可行: 同样用数据过滤保持 vocab 兼容, 无 BUG-27 风险
- 可从 ORCH_024 checkpoint 加载 (vocab 兼容)
- 显存/速度几乎无差异 (AR 长度由 grid 决定, 与类数无关)
- **不推荐原因**: (a) 最终仍需 10 类, 增加迁移成本; (b) 修复 BUG-17 (balance_mode) 比回避类竞争更直接; (c) ORCH_024 已在学习多类
- **结论**: 仅作为 mini 诊断备选, 不在 Full 上执行

**3. LoRA 方案 (方案 E) — ORCH_024 后评估**
- rank=16, ~12M 额外参数, ~2 GB 额外 VRAM
- 需应用到 Layer 14-18 (围绕提取层 16) 才有意义, 而非 Layer 38-39
- **风险**: 实现需 1-2 天, 效果不确定
- **优先级**: BUG-17 修复 >> 方案 D (历史 occ box) >> LoRA
- **执行条件**: ORCH_024 完成 + 方案 D 评估后, 且 car_P 仍不理想时

**4. 特征漂移结论**
- Plan M 崩溃: DINOv3 预训练表示脆弱, 任何微调都破坏中间层分布
- Plan N car_P=0.05 低: BUG-27/31/36 叠加, 不代表 DINOv3 特征有本质 gap
- ORCH_024 car_P=0.078 在更公平条件下证明 frozen DINOv3 可用

### Instance Grouping (VERDICT_INSTANCE_GROUPING — CONDITIONAL, 已归档)
- **提案**: SLOT_LEN 10→11, 加 instance_id token (g_idx, 32 bins)
- **Critic 判决**: 方向正确, 需解决 4 个问题 (编码方案/序列扩展/评估语义/Loss 权重)
- **决策**: 不纳入 P5b, 列入 P6+ 路线图。优先级低于 P5b 三项修复和 BEV PE
- **BUG-18**: 评估时 GT instance 未跨 cell 关联 (设计层, Critic 发现)

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 |
| BUG-15 | HIGH | P5b 解决 (双层投影) |
| BUG-16 | MEDIUM | NOT BLOCKING |
| **BUG-17** | **CRITICAL** | ~~P5b 解决~~ Full nuScenes 实证: bicycle 154K FP (P=0.001), sqrt balance 给稀有类 ~11x 权重. 建议: balance_mode='log' 或 weight cap=3.0 或关闭 (VERDICT_FULL_4000) |
| **BUG-18** | **MEDIUM** | 设计层 — 评估时 GT instance 未跨 cell 关联 (Critic VERDICT_INSTANCE_GROUPING) |
| **BUG-19** | **HIGH** | **FIXED** — z+=h/2 把 box 中心移到顶部, 导致投影只覆盖上半身。移除后多边形覆盖完整车辆。GiT commit `965b91b` |
| **BUG-20** | **HIGH** | bus 振荡根因: nuScenes-mini 数据量不足 (~120 bus 标注/40 张图), sqrt 加权无法根治。数据集天花板, 非模型 bug (Critic VERDICT_P5B_3000) |
| **BUG-21** | **MEDIUM** | off_th 退化: P5@4000=0.142 → P5b@3000=0.200 (+40.8%)。原假设 GELU 损害方向信息 → **BUG-30 INVALID, GELU 无影响** (P5b=0.195≈P6=0.196)。真因: 双层投影结构差异 |
| **BUG-22** | **HIGH** | 10 类 ckpt 兼容性: Admin 验证无障碍, vocab 动态索引无 shape mismatch ✅ |
| **BUG-23** | **HIGH** | GPU 显存信息错误: 实际 A6000 48GB (非 24GB), 所有显存约束大幅放松 (Critic VERDICT_P6_ARCHITECTURE) |
| **BUG-24** | **MEDIUM** | 缺少单类诊断 config: 需创建 `plan_k_car_only_diag.py` (Critic VERDICT_P6_ARCHITECTURE) |
| **BUG-25** | **HIGH** | 无在线 DINOv3 提取路径: `PreextractedFeatureEmbed` 只支持磁盘预提取, 方案 C/B 需在线模式 (Critic VERDICT_P6_ARCHITECTURE) |
| **BUG-26** | **MEDIUM** | DINOv3 存储过估: 代码只用 CAM_FRONT, 全量仅需 ~175GB fp16 (非 2.1TB). BLOCKER 降级 (Critic VERDICT_P6_ARCHITECTURE) |
| **BUG-27** | **CRITICAL** | Plan K vocab 不兼容 (230→221), vocab_embed 随机初始化, Plan K "类竞争否定"结论无效 (Critic VERDICT_DIAG_RESULTS) |
| **BUG-28** | **HIGH** | Plan L 双变量混淆: 投影宽度+vocab 保留同时变化, 无法干净归因 (Critic VERDICT_DIAG_RESULTS) |
| **BUG-29** | **LOW** | Plan K sqrt balance 对单类无意义, 不影响结果 (Critic VERDICT_DIAG_RESULTS) |
| **BUG-30** | ~~MEDIUM~~ **INVALID** | ~~GELU ~0.05 惩罚~~。**假设不成立**: P5b off_th=0.195 ≈ P6 off_th=0.196, GELU 对 off_th 无影响。原假设基于被 BUG-27 污染的 Plan K 数据 (Critic VERDICT_P6_VS_P5B) |
| **BUG-31** | **HIGH** | Plan M/N 继承 BUG-27 vocab mismatch (num_vocal=221). M vs N 对比仍有效, 绝对性能受拖累 (Critic VERDICT_DIAG_FINAL) |
| **BUG-32** | **MEDIUM** | Plan K @1500 off_cy 跳变 0.073→0.206, LR decay 后回归退化. P6 LR milestones 需关注 (Critic VERDICT_DIAG_FINAL) |
| **BUG-33** | **MEDIUM** (降级) | gt_cnt DDP inflation 根因确认: 缺 DistributedSampler. **ORCH_019 完成**: car_P 有小幅偏差 (最大 -9%@1500), car_R 偏差最大 (-27%@1500), 方向不一致. 修复已应用 (sampler config) |
| **BUG-34** | **LOW** (降级) | proj lr_mult=2.0, LR decay @2500 后 proj LR 1e-4→1e-5 自动缓解. 无需 P6b (Critic VERDICT_P6_1500) |
| **BUG-35** | **MEDIUM** | DINOv3 unfreeze last-2 导致特征漂移: Plan M car_R 0.699→0.489 (-21%). 在线路径必须 frozen (Critic VERDICT_P6_1500) |
| **BUG-36** | **HIGH** | Plan M/N vs P6 对比条件不一致: Plan M/N proj_dim=1024, P6 proj_dim=2048. CEO 基于不公平对比否决在线路径. 需 Plan O 验证 (Critic VERDICT_P6_3000) |
| **BUG-37** | **HIGH** | P5b 基线不可信 → **ORCH_020 完成**: P5b@3000 单GPU car_P=**0.116** (非 DDP 的 0.107), DDP 低估 8%. **P6 落后 P5b!** |
| **BUG-38** | ~~MEDIUM~~ **LOW** | Critic car_P 预测 0.12-0.13 实际准确, 仅延迟 500 iter. @3500 hit 0.121, @4000 hit 0.126 (Critic VERDICT_PLAN_P_FAIL_P6_TREND) |
| **BUG-39** | ~~CRITICAL~~ **MEDIUM** | 双层 Linear 无激活=单层 Linear 数学成立, 但 **因式参数化有优化优势** (9.96M vs 3.15M, 隐式核范数正则化). P6@4000 car_P=0.1263 超 P5b 8.9%. **退化≠无效** (Critic VERDICT_PLAN_P_FAIL_P6_TREND) |
| **BUG-40** | **HIGH** | **Critic 审计链连锁失误**: BUG-27(vocab mismatch)→BUG-30(GELU损害off_th错误假设)→VERDICT_DIAG_FINAL(推荐去GELU)→P6退化架构→3000iter低效. Critic 自我纠正 (VERDICT_P6_VS_P5B) |
| **BUG-41** | **HIGH** | **Plan O warmup=max_iters=500**: `LinearLR end=500` = 全程 warmup, LR 从未达正常值. **Plan O car_P=0.000, 完全未检测 car/truck**. 结果不可信, 在线路径验证被阻塞 (Critic 确认) |
| **BUG-42** | **MEDIUM** | **Plan P2 max_iters < first milestone**: `max_iters=2000`, `milestones=[2000,4000]` from `begin=500`. 第一次 decay@iter2500, 但训练@2000 结束. P2 全程 full LR 无 decay. P2@2000 car_P=0.096 回调不能归因 GELU (Critic VERDICT_P2_FINAL) |
| **BUG-43** | **MEDIUM** | Conductor 未读代码估算 Deep Supervision "1-2天", 实际一行 `loss_out_indices=[8,10,11]` |
| **BUG-44** | **LOW** | Deep supervision 各层共享 vocab embedding, 理论风险, 暂不处理 |
| **BUG-45** | **MEDIUM** | OCC head 推理 `attn_mask=None`, 训练有 causal+跨 cell 隔离 mask. Full 上 12000 KV entries 累积更严重 (VERDICT_FULL_4000 补充) |
| **BUG-46** | **LOW** | `accumulative_counts=4` 使 optimizer steps = iter/4. @4000=500 post-warmup steps < Mini @1000. 非代码 BUG, 分析需标注 optimizer steps (VERDICT_FULL_4000) |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_008 | P5 DINOv3 集成 | COMPLETED |
| ORCH_009 | 旋转多边形可视化 | **COMPLETED** — 10 张图, `/mnt/SSD/GiT_Yihao/polygon_viz/` |
| **ORCH_010** | **P5b 三项修复** | **COMPLETED — P5b 6000/6000, 红线 3/5** |
| ORCH_011 | SSD 迁移 | **COMPLETED** (标记) — 但 work_dirs 仍为普通目录, 未建软链接 |
| ORCH_012 | BUG-19 v1: valid_mask | COMPLETED — 影响小 |
| ORCH_013 | BUG-19 v2: z+=h/2 删除 | COMPLETED — 正样本覆盖修复, commit `965b91b` |
| AUDIT_P5_MID | P5 中期审计 | VERDICT PROCESSED |
| AUDIT_INSTANCE_GROUPING | Instance ID 提案 | VERDICT PROCESSED — 列入 P6+ |
| AUDIT_P5B_3000 | P5b 中期 + P6 决策 | VERDICT PROCESSED — P6 从 @3000 启动 |
| **ORCH_014** | **P6 完整 nuScenes 准备** | **COMPLETED — BUG-26: 仅 175GB fp16, BLOCKER 降级** |
| AUDIT_P6_ARCHITECTURE | P6 架构方案审计 | VERDICT PROCESSED — 诊断优先, D>C>B |
| AUDIT_DIAG_RESULTS | 诊断 @1000 结果审计 | VERDICT PROCESSED — 方向对但混淆, 去 GELU, 10 类 |
| **ORCH_015** | **诊断实验 (单类 car + 宽投影)** | **COMPLETED ✅ — Plan K/L @2000 最终结果到手** |
| **ORCH_016** | **DINOv3 在线提取 + unfreeze** | **COMPLETED ✅ — 预提取>在线, Frozen>>Unfreeze** |
| **ORCH_017** | **P6 宽投影 mini 验证** | **COMPLETED ✅ — @6000 FINAL car_P=0.129 (DDP, +11% vs P5b)** |
| **ORCH_018** | **BUG-33 gt_cnt 调查** | **COMPLETED ✅** |
| **ORCH_019** | **BUG-33 P6 单 GPU re-eval** | **COMPLETED ✅** |
| **ORCH_020** | **P5b@3000 单 GPU re-eval** | **COMPLETED ✅ — car_P=0.116! P5b >> P6!** |
| **ORCH_021** | **Plan O 在线+2048+noGELU** | **COMPLETED (INVALID) — car_P=0.000, BUG-41 全程warmup + BUG-39 退化** |
| **ORCH_022** | **Plan P 2048+GELU** | **COMPLETED (FAIL) — car_P=0.004, 超参问题 (lr_mult=1.0+warmup=100), bg_FA=0.165 历史最低** |
| **ORCH_023** | **P6@4000 re-eval + Plan P2** | **COMPLETED ✅ — P6@4000=0.1263, P2: @1000=0.100(+72%), @1500=0.112(+5.7%), @2000=0.096(BUG-42 LR回调)** |
| **ORCH_024** | **Full nuScenes 2048+GELU+在线DINOv3** | **IN PROGRESS — ~4200/40000 (10.5%), @4000 VERDICT CONDITIONAL, 等 @6000 (~05:30) → @8000 做决策** |
| **ORCH_025** | **pytest 测试框架** | **COMPLETED ✅ — 177 passed, 12 skipped, 3 xfailed** |
| **ORCH_026** | **Plan Q 单类 car 诊断 (mini)** | **IN PROGRESS — GPU 1, 导致 ORCH_024 减速 2.7x ⚠️** |

## 指标参考 (CEO: 红线降级, mini 仅 debug)
| 指标 | 参考线 | @3000 | @4000 | @5000 | **@6000** | 备注 |
|------|--------|-------|-------|-------|-----------|------|
| truck_R | ≥ 0.08 | 0.205 | 0.229 | 0.239 | 0.240 | ✅ 稳定 |
| bg_FA | ≤ 0.25 | 0.217 | 0.211 | 0.210 | **0.208** | ✅ 全程最低 |
| off_th | ≤ 0.20 | 0.200 | 0.196 | 0.201 | **0.198** | ✅ 最终达标! |
| off_cx | ≤ 0.05 | 0.059 | 0.059 | 0.059 | 0.057 | ❌ 差 0.007 |
| off_cy | ≤ 0.10 | 0.112 | 0.132 | 0.132 | 0.134 | ❌ 偏高 |

> CEO 方向: 不再以这些指标为最高目标。完整 nuScenes 性能才是真正评判标准。

## 历史决策
### [2026-03-09 ~02:10] 循环 #105 — VERDICT_FULL_4000 处理 | BUG-17→CRITICAL | BUG-46 new | @8000 决策矩阵
- **VERDICT_FULL_4000**: CONDITIONAL — 继续训练不中断
- **BUG-46**: accumulative_counts=4 → @4000=500 post-warmup optimizer steps (< Mini @1000). 解释 car_P 偏低
- **BUG-17 升级 CRITICAL**: bicycle 154K FP 实证. sqrt balance 给 bicycle ~11x car 权重. 建议 @8000 若 car_P<0.08 切 balance_mode='log'
- **@8000 决策矩阵**: >0.12 继续, 0.08-0.12 继续, 0.05-0.08 调 balance, <0.05 架构改
- **Critic 建议**: @8000 前不做架构修改 (deep supervision/mask 等)
- **off_cy 恶化**: 可解释 (深度估计+多类分布), @6000 观察趋势
- **项目进展报告**: 363 行, CEO 指令完成

### [2026-03-09 ~04:20] 循环 #110 — CEO 双任务: 调查结论持久化 + 架构详细报告
- **任务 1**: car_precision_investigation 结论写入 MASTER_PLAN 持久追踪区域 (Plan Q/5 类/LoRA/特征漂移)
- **任务 2**: orch024_architecture_detail.md 撰写 — 完整数据流、参数统计、LR 层次、显存分析
- **ORCH_026 IN PROGRESS**: Plan Q 在 GPU 1 执行, 导致 ORCH_024 减速 2.7x
- **GPU 冲突**: GPU 1 显存 97.4%, 等 CEO 决策或 Plan Q 自然完成

### [2026-03-09 ~01:40] 循环 #104 — ★★★ @4000 Val 完成! 第一个可信点 | car_P=0.078 持平 | truck/bicycle 新出现 | 审计签发
- **@4000 val**: car_P=0.078 (持平), car_R=0.419 (停止spam), truck_P=0.057, bicycle_R=0.191
- **bg_FA=0.199** 首次<0.20, off_th=0.150 大幅改善, off_cx=0.039 改善30%
- **off_cy=0.097 恶化** (vs @2000=0.069), 需关注
- **AUDIT_REQUEST_FULL_4000 签发**: 等 Critic 评估
- **ORCH_025 COMPLETED**: 测试框架 177 passed

### [2026-03-09 ~00:35] 循环 #102 — ORCH_025 COMPLETED (177 passed) | @4000 val ~00:38 开始
- **ORCH_025 完成**: pytest 测试框架 177 passed, 12 skipped, 3 xfailed (旧 config BUG-41/42)
- **测试覆盖**: config 验证 (24 configs), eval 完整性, 标签生成, 冒烟测试
- **@4000 val**: ~00:38 开始, ~01:35 完成 — 第一个可信评估点

### [2026-03-09 ~00:00] 循环 #101 — CEO 签发测试框架 ORCH_025 | 训练 3620/40000 巡航
- **CEO_CMD**: 创建 pytest 自动化测试框架 (config/eval/label/smoke 4 类测试)
- **ORCH_025 签发**: 测试框架覆盖 BUG-41/42/12 回归防护, Admin 执行
- **训练进度**: 3620/40000, @4000 val ETA 3/9 ~03:30

### [2026-03-08 ~21:40] 循环 #96 — CEO slot 错误传播观察 | 训练 2250/40000 正常 | 无需审计
- **CEO_CMD**: cell 内 Slot1→2→3 串行 AR 错误累积, per-slot 验证将确认. CEO 观察正确
- **训练进度**: 2250/40000, loss 下降中, @4000 ETA 3/9 ~02:30
- **Supervisor 新信息**: off_th=0.174 远优于 mini (0.25+), 数据多样性效应显著
- **建议**: @4000 后安排单 GPU re-eval (BUG-33 DDP 偏差)

### [2026-03-08 ~21:10] 循环 #95 — ★★★ @2000 Val 完成! car_P=0.079, car_R=0.627 | 继续训练 | 无需审计
- **@2000 val 结果**: car_P=0.0789, car_R=0.627, bg_FA=0.222, cx=0.056, cy=0.069, th=0.174
- **决策矩阵**: car_P=0.0789 (0.03-0.08 边界) → 不中断, 继续训练
- **规则 #6**: @2000 仅趋势参考 (0.57 epochs), @4000 第一可信点
- **积极信号**: car_R=0.627 (模型定位能力强), bg_FA=0.222 (前景/背景判别合格)
- **下一里程碑**: @4000 (ETA 3/9 ~01:30) — 第一个可做条件性结论的评估点
- **无审计签发**: 结果在预期范围内, 无需 Critic 介入

### [2026-03-08 ~20:40] 循环 #94 Phase 2 — VERDICT_AR_SEQ_REEXAMINE | iter 2000 warmup 完成 | @2000 val 进行中
- **VERDICT 处理**: AR 30 token 上调为 contributing factor (MEDIUM), finished_mask 缓解, per-slot 验证方案 A 零成本
- **ORCH_024 里程碑**: iter 2000, warmup 完成, LR 到达目标, @2000 val 进行中 (ETA ~21:07)
- **归因澄清**: CEO_CMD 处理, 确认是 Conductor 的错误不是 Critic 的

### [2026-03-08 ~19:00] 循环 #92 Phase 2 — VERDICT_CEO_ARCH_QUESTIONS CONDITIONAL | BUG-43/44/45 | 优先级重排
- **VERDICT 处理**: Deep Supervision 代码已存在 (零成本!), BUG-43 纠正 Conductor 误估
- **BUG-45 发现**: OCC head 推理 attn_mask=None, 训练/推理不一致
- **优先级重排**: Q2 (Deep Supervision) 升至 #1, Q3 (Mask) 降至 #4
- **ORCH_024 后计划**: 实验A (deep supervision only) → 实验B (+structured mask) A/B ablation
- **评判标准永久规则**: 写入 MASTER_PLAN, 6 条规则 (CEO+Critic 确认)
- **无新 ORCH**: 等 @2000 eval (~20:10)

### [2026-03-08 ~17:15] 循环 #87 Phase 2 — VERDICT_CEO_STRATEGY_NEXT CONDITIONAL | 等 @2000 决策 | 无新 ORCH
- **VERDICT 处理**: CEO 方案 A 已涵盖, B 三重否决, C 不改 vocab, D 最有前途 (2帧 1.0s), E LoRA 推荐, F 搁置, G 等数据
- **优先级排序**: ORCH_024 >> G >> D >> E >> F >> C >> B >> A
- **@2000 决策矩阵**: car_P>0.15→继续+D; 0.08-0.15→继续; 0.03-0.08→调参; <0.03→切预提取
- **无新 ORCH**: ORCH_024 运行正常, 等 @2000 eval (~20:00) 再决策
- **Critic 建议对 CEO**: 方案 A 直觉完全正确 (已被 2048 实现); 方案 B 用 LoRA 替代; 方案 D 最有前途

### [2026-03-08 ~17:00] 循环 #87 Phase 1 — ORCH_024 IN PROGRESS (60/40000) | CEO 新战略方案送审
- **ORCH_024 已启动**: 4 GPU DDP, 60/40000 iter, loss 4.00@60 持续下降, 速度 6.3 s/iter, 显存 36-37 GB/GPU
- **@500 val ETA ~17:29**: 第一次 eval, 确认在线路径正常
- **CEO 新指令**: DINOv3 适配层改进 (方案A/B) + 3D 空间编码路线图 + 单类 car 验证
- **GPU 冲突**: CEO 要用 GPU 1,3 做 mini 调试, 但全被 ORCH_024 占用
- **AUDIT_REQUEST_CEO_STRATEGY_NEXT 签发**: CEO 方案 A/B/C/D + Conductor 方案 E/F/G 统一送审
- **Conductor 方案 E**: LoRA/Adapter 替代全量 unfreeze (显存可控)
- **Conductor 方案 G**: 等 ORCH_024 @2000 结果再做 GPU 重分配决策

### [2026-03-08 16:10] 循环 #86 Phase 2 — ★★★★ VERDICT PROCEED! Full nuScenes 2048+GELU 启动! ORCH_024 签发!
- **VERDICT_P2_FINAL_FULL_CONFIG (PROCEED)**: Full nuScenes 使用 2048+GELU + 在线 DINOv3 frozen
- **BUG-42 NEW (MEDIUM)**: P2 max_iters < first milestone, 全程 full LR 无 decay. P2@2000 回调不能归因 GELU
- **Critic 纠正**: off_th 收敛到 ~0.19-0.20 与 GELU 无关 (Conductor 对比有误)
- **跳过 Plan O2**: Critic 推荐直接 Full nuScenes 测在线路径, mini 在线数据不可靠
- **P6@6000 re-eval 不需要**: 不改变任何决策
- **ORCH_024 签发+DELIVERED**: Full nuScenes Config 创建 + 在线代码验证 + 4 GPU DDP 训练
- **Mini 验证阶段正式结束!** 进入 Full nuScenes 训练阶段

### [2026-03-08 16:05] 循环 #86 Phase 1 — ★★★ ORCH_023 COMPLETED! P2@2000=0.096 回调 | 审计签发 | 4 GPU 空闲
- **P2@2000 FINAL**: car_P=**0.096** (从 @1500=0.112 回调), car_R=**0.801** (极端), P6@2000=0.110 反超
- **回调原因**: full LR 2.5e-06 无 decay, 模型 spam car 预测, 其他类崩. P6 也需 @2500 decay 才稳定
- **GELU 优势总结**: @1000 +72%, @1500 +5.7%, @2000 -12.8% (LR问题). off_th 始终优于 P6
- **P6@6000 FINAL DDP**: car_P=0.129, +11% vs P5b, 训练完成
- **ORCH_023 COMPLETED**: P6 re-eval + Plan P2 全部完成
- **4 GPU 全部空闲**: 等 Critic VERDICT 后签发 Full nuScenes ORCH
- **AUDIT_REQUEST_P2_FINAL_FULL_CONFIG 签发**: Full nuScenes config 决策, GELU 判定, 下一步规划

### [2026-03-08 15:46] 循环 #85 Phase 1 — ★★ P6 COMPLETED @6000! P2@1500=0.112 超 P6@2000! 等 P2@2000 最终决策
- **P6@6000 FINAL (DDP)**: car_P=0.129, plateau 确认. **P6 训练正式完成!** GPU 0+2 释放
- **P2@1500 (单GPU)**: car_P=**0.112** > P6@1500=0.106 (+5.7%), > P6@2000=0.110! bg_FA=0.279 (从 0.328 改善 -15%)
- **P2 收敛速度**: 1500 iter 超 P6 2000 iter 水平, 约 1.3x 加速
- **3 GPU 空闲**: GPU 0+2+3, 等 P2@2000 确认后规划
- **P2@2000 ETA ~15:55**: 约 10 分钟后, Full nuScenes config 最终决策点
- **无审计, 无 ORCH**: P2@2000 到手后综合签发

### [2026-03-08 15:18] 循环 #84 Phase 1 — ★★★ P2@1000 car_P=0.100 (+72% vs P6!) GELU 信号强烈
- **P2@1000 (单GPU)**: car_P=**0.100** vs P6@1000=0.058 → **+72%!** GELU 收敛加速效果巨大
- **P2@1000 bg_FA=0.328**: 未达 Critic 0.25 标准, 但 P6@1000=0.352 更差. @1000 是类振荡高峰, bg_FA 标准过严
- **P6@5500 DDP**: car_P=0.128, bg_FA=0.273, plateau 稳定. @6000 ~15:24 即将完成
- **P6@6000 倒计时**: ~15:24 val 完成, GPU 0+2 释放
- **Plan P2 at 1300/2000**: @1500 val ~15:26, @2000 final ~15:56
- **无审计**: 等 P2@2000 全部数据后综合审计
- **无 ORCH**: 等 GELU 确认后规划 GPU 0+2+3

### [2026-03-08 14:50] 循环 #83 Phase 1 — Plan P2@500=0.069 正常起步, P6@5000 plateau, 等 P2@1000
- **Plan P2@500 (单GPU)**: car_P=0.069 (略低于 P6@500=0.073), bg_FA=0.256 (高于 P6). 通过 Critic 最低阈值 (>0.05)
- **Plan L 参考**: @500=0.054→@1000=0.140 — @500 不具判定意义, @1000 才是关键
- **P6@5000 DDP**: car_P=0.128, truck_P=0.078, bg_FA=0.275 — plateau 中微增
- **P6 at 5450/6000**: ETA @6000 ~15:15
- **Plan P2 at 830/2000**: @1000 val ETA ~14:57 (关键!), @2000 final ~15:47
- **GPU 3 空闲**: 保留, 等 P2@1000 后决定
- **无审计, 无 ORCH**: 一切按计划

### [2026-03-08 14:22] 循环 #82 Phase 1 — 监控: P6@4500 DDP 稳定, Plan P2 训练中, 无审计
- **P6@4500 DDP**: car_P=0.126 (稳定), off_th=0.194 (<0.20!), bicycle_P=0.103 新类突破
- **第二次 LR decay @4500 已生效**: LR=2.5e-08, P6 进入最终收敛
- **P6 at 4950/6000**: ETA @6000 ~15:12
- **Plan P2 at 350/2000**: @500 val ETA ~14:32, 完成 ETA ~15:40
- **GPU 3 空闲**: 可用于 Plan O2 (在线+GELU), 但等 Plan P2@500 先
- **无审计**: 无新判决需求, 一切按计划运行

### [2026-03-08 14:05] 循环 #81 Phase 2 — ★ VERDICT 处理: BUG-39→MEDIUM, P6 恢复有效, Plan P2 训练中
- **VERDICT_PLAN_P_FAIL_P6_TREND (CONDITIONAL)**: Plan P2 BLOCKING, P6 fallback 有效
- **BUG-39 CRITICAL → MEDIUM**: 因式参数化有优化优势, P6@4000 car_P=0.1263 超 P5b 8.9%
- **BUG-38 MEDIUM → LOW**: Critic 预测准确, 仅延迟 500 iter
- **BUG-41 确认**: Plan O car_P=0.000, 完全无效
- **P6@4000 单GPU re-eval**: car_P=0.1263, truck_P=0.0749, bg_FA=0.2741, off_th=0.1907 — 全面改善
- **Plan P2 训练中**: ORCH_023 GPU 1, ETA ~16:00. 判定: @2000 car_P vs P6@2000(0.110)
- **Full nuScenes Config 排名**: Plan P2 > P6 > P5b. 2h 投入 ROI>10x
- **无新 ORCH**: ORCH_023 已覆盖, Plan P2 按计划运行

### [2026-03-08 13:52] 循环 #81 Phase 1 — Plan P FAIL (超参), P6 突破平台, Plan P2+ORCH_023 签发
- **Plan P @500 car_P=0.004**: lr_mult=1.0+warmup=100+500iter 严重不足. Admin 诊断: 超参问题, 非架构
- **P6@3500 car_P=0.121**: 首超 P5b 0.116 (+4.5%), 尽管 BUG-39 退化架构!
- **P6@4000 DDP car_P=0.123**: 趋势继续上升. bg_FA=0.285, truck_P=0.077 均为新高
- **BUG-41**: Plan O warmup=max_iters=500, 全程 warmup, 结果不可信. 在线路径验证阻塞
- **ORCH_023 签发**: P6@4000 re-eval (10 min) + Plan P2 (2048+GELU+lr_mult=2.0, 2000 iter, ~2h)
- **Plan P2 设计**: 从 P6 config 仅改 proj_use_activation=True. 唯一干净分离 GELU 变量的实验
- **AUDIT_REQUEST 签发**: Plan P 失败归因 + BUG-39 重评 + Full nuScenes 路线决策
- **Plan P bg_FA=0.165 历史最低!**: 暗示 GELU 对 bg/fg 判别有巨大帮助

### [2026-03-08 13:06] 循环 #79 Phase 2 — ★★★ BUG-39 CRITICAL! P6 架构退化! Plan P 签发!
- **VERDICT_P6_VS_P5B (CONDITIONAL)**: P6 架构方向需修正, BUG-39 致命
- **BUG-39 CRITICAL**: `Sequential(Linear(4096,2048), Linear(2048,768))` 无 GELU = `Linear(4096,768)`. 2048 维度无效
- **BUG-40 HIGH**: Critic 审计链连锁失误 → BUG-27→BUG-30→去GELU推荐→P6退化
- **BUG-30 INVALID**: GELU 不损害 off_th (P5b=0.195≈P6=0.196), 原假设基于 BUG-27 污染数据
- **ORCH_020 COMPLETED**: P5b@3000 car_P=**0.116**, bg_FA=**0.189** — P5b >> P6
- **ORCH_021 IN PROGRESS**: Plan O (online+noGELU) GPU 3, ETA ~13:45. ⚠️ 退化架构, 仅作 online vs preextract 参考
- **ORCH_022 签发**: Plan P (2048+GELU+lr_mult=1.0) GPU 1, 500 iter — **最高优先级实验**
- **Plan P 判定**: car_P@500>0.073(P6@500) + bg_FA<0.200 → 2048+GELU 是 full config
- **P6 继续到 @6000**: 作为负面参考, 不投入决策权重
- **三步策略**: Plan P → Plan O (GELU版) → Full nuScenes config 选择

### [2026-03-08 12:38] 循环 #78 Phase 2 — ★★ P6 @3000 CONDITIONAL PASS! ORCH_020+021 签发
- **P6 @3000 DDP val**: car_P=0.106, off_th=0.205, bg_FA=0.309, truck_P=0.061 历史最高
- **VERDICT_P6_3000 (CONDITIONAL)**: 架构验证通过, 精度验证不充分 (car_P 平台化 0.106-0.111)
- **car_P 平台化**: @1500-3000 恒定 ~0.11 — mini 数据天花板, Critic: 继续训练不会突破
- **BUG-36 (HIGH)**: Plan M/N vs P6 对比不公平 (proj 1024 vs 2048), 需 Plan O 验证
- **BUG-37 (HIGH)**: P5b 基线不可信 (DDP, 无 sampler), 必须 re-eval
- **BUG-38 (MEDIUM)**: Critic 自我纠正预测偏乐观
- **ORCH_020 签发**: P5b@3000 单 GPU re-eval (COND-1, GPU 1, ~10 min)
- **ORCH_021 签发**: Plan O 在线+2048+无GELU (COND-2, GPU 3, 500 iter ~1h)
- **两个 BLOCKING 条件满足后**: 决定 full nuScenes 路线 (在线 vs 预提取 175GB)
- Critic: P6 mini @6000 不投入决策权重, mini 价值 @3000 已耗尽
- **★ Admin 已完成 P6@3000 单 GPU re-eval**: bg_FA=**0.297** (<0.30✅), off_th=**0.196** (<0.20✅), car_R=0.617
- **@3000 是目前最均衡的 checkpoint**: bg_FA+off_th 双达标, car_P=0.106

### [2026-03-08 12:18] 循环 #77 Phase 2 — ★ ORCH_019 完成! P6 全可信数据, @2500 off_th=0.201 首破 0.21
- **ORCH_019 re-eval 完成**: 5 个 ckpt 单 GPU re-eval (@500~@2500), 全部可信数据到手
- **car_P 修正**: @1500 DDP=0.117 实际=0.106 (偏差 -9%), @2000-2500 差异 ≤1%, 仍 ≈ P5b@3000 (0.107)
- **P6 @2500 新数据 (LR decay 后首个 ckpt)**: car_P=0.111 稳定, off_th=**0.201** (Critic 预测 ~0.20 兑现!), car_R=0.516 回弹
- **bg_FA @2500=0.336 偏高**: 多类大幅激活 (bus=0.518, truck=0.356, ped=0.170), 但 CEO 方向不以此为最高目标
- **BUG-33 新发现**: car_P 也有小幅 DDP 偏差, 非完全不受影响; 偏差方向不一致 (非系统性)
- **ORCH_016/018/019 全部 COMPLETED**
- **VERDICT_P6_1500.md 第三次重现**: 与 processed/ 一致, 已删除 (sync_loop 重建)
- **P6 @3000 ~12:24**: mini 最终评估点 — 10 分钟后, 不签发 ORCH, 等数据
- 不签发审计 — 等 @3000 最终数据后做综合审计决策

### [2026-03-08 11:45] 循环 #75 Phase 2 — P6 @2000 类振荡回摆 (Critic 预测准确), Plan M COMPLETED
- **P6 @2000**: car_P=0.111 (仍>P5b 0.107), bg_FA=0.327 (类振荡), off_th=0.230 (改善趋势)
- **Critic @2000 预测完全验证**: 小类反弹, car_P 小幅回落, 属正常振荡周期
- **LR decay @2500 即将到来** — proj LR 1e-4→1e-5, 振荡将被压制
- **Plan M COMPLETED @2000**: car_R 部分恢复 0.489→0.507, car_P 始终 ~0.05, 在线 unfreeze 路径判定失败
- **Plan N @2000**: val 进行中, 下 cycle 收集
- **BUG-33 Admin 报告**: 根因+修复完整记录在 admin_report_bug33.md
- 无新 VERDICT, 不签发 ORCH — P6 按计划继续到 @3000

### [2026-03-08 11:05] 循环 #74 Phase 2 — ★ P6 @1500 PASS! VERDICT_P6_1500: PROCEED 到 @3000
- **P6 @1500 PASS**: car_P=0.117 ≥ 0.07 ✅ + bg_FA=0.278 ≤ 0.28 ✅
- **car_P=0.117 超越 P5b 全系列最优 (0.107)**, 投影层仅训练 1500 iter (vs P5b 3000)
- **off_cx=0.034 历史最佳**, off_cy=0.069 远优于 P5b
- **假说 B 完全验证**: @1000 崩塌是类振荡暂态, @1500 car 强势反弹
- **BUG-33 根因确认**: DDP val 缺 DistributedSampler → gt_cnt inflation, Precision 不受影响, 降级 MEDIUM
- **BUG-34 降级 LOW**: LR decay @2500 自动缓解
- **BUG-35 NEW (MEDIUM)**: DINOv3 unfreeze 特征漂移 (car_R -21%)
- **Plan M/N @1500**: Frozen >> Unfreeze 确认, 在线路径 car_P ~0.05 不达标
- **Critic: 不需要 P6b**, P6 继续到 @3000 (mini 最终评估点)
- **BUG-33 修复**: P6 @2000 后单 GPU re-eval + 长期加 DistributedSampler
- 不签发 ORCH — P6 按计划继续, @2000 (~11:31) 和 @3000 数据待收

### [2026-03-08 10:35] 循环 #73 Phase 2 — ⚠️ P6 @1000 双 FAIL; VERDICT_P6_1000: 继续, 假说 B
- **P6 @1000 双 FAIL**: car_P=0.054 < 0.10, bg_FA=0.323 > 0.30
- **VERDICT_P6_1000 (CONDITIONAL)**: 继续到 @2000, 不中止. 假说 B (类振荡+LR过激) 最可能
- **核心证据**: P6@500 bg_FA=0.163 历史最优 → 架构无根本缺陷, @1000 崩塌 = constr/barrier 爆发
- **BUG-33 (HIGH)**: gt_cnt 跨实验不一致 (truck +95%), 需 Admin 紧急调查
- **BUG-34 (MEDIUM)**: proj lr_mult=2.0 过激, Critic 自认失误
- **@2000 新判定**: car_P≥0.07+bg_FA≤0.28 → PASS; car_P<0.05+car_R<0.15 → P6b
- **ORCH_018 签发**: BUG-33 gt_cnt 调查 (Admin)

### [2026-03-08 10:00] 循环 #72 Phase 2 — ★ P6 @500 bg_FA=0.163 历史最低! Plan M/N 在线不达标
- **P6 @500**: bg_FA=0.163 全实验最低, car_P=0.073 同期最优, off_cy=0.077 优于 P5b
- **Plan M/N @1000 判决**: M_car_P=0.049 < 0.077 阈值 → 在线路径精度不达标
- **Unfreeze vs Frozen**: 差异极小, DINOv3 微调不值得投入
- **P6 gt_cnt 差异**: val car=7232 vs 其他 6720 (+7.6%), 需确认 val set 配置
- **下一关键**: P6 @1000 (~10:18) — car_P≥0.10 + bg_FA≤0.30 → PASS
- 不签发 ORCH — P6 训练正常, 等 @1000 关键判定

### [2026-03-08 09:30] 循环 #71 Phase 2 — P6 训练已启动, Plan M/N @1000 val 进行中
- **P6 已启动**: ORCH_017 DELIVERED, iter 90/6000, GPU 0+2 DDP
- **P6 config 验证**: 纯双 Linear 无 GELU ✅, P5b@3000 加载 ✅, proj 随机初始化 ✅, LR 2x ✅
- **P6 早期**: Loss 11.4→3.8 快速下降, grad_norm 39-63 偏高 (proj 层初期波动, 可接受)
- **Plan M/N @1000 val**: ~09:34-09:37 完成, unfreeze vs frozen 关键分化
- **4 GPU 全满**: P6(0+2) + M/N(1+3)
- 不签发 ORCH — 一切按计划, 等 @500 (~09:48) 和 M/N @1000 数据

### [2026-03-08 09:10] 循环 #70 Phase 2 — ★★ VERDICT_DIAG_FINAL: P6 Config 定稿! 纯双 Linear 无 GELU 无 LN
- **VERDICT_DIAG_FINAL (CONDITIONAL)**: 宽投影 2048 获批, 但去掉 LayerNorm!
- **P6 投影层定稿**: `nn.Sequential(nn.Linear(4096,2048), nn.Linear(2048,768))` — 纯线性, 无任何激活/归一化
- **投影层 LR 2x**: `backbone.patch_embed.proj lr_mult=2.0` 加速 proj 收敛
- **P6 先 mini 3000 iter**: 监控红线 @1000 car_P≥0.10 + bg_FA≤0.30
- **Plan K COMPLETED @2000**: car_P=0.063, bg_FA=0.166 (全实验最低), off_th=0.191
- **Plan L COMPLETED @2000**: car_P=0.111 (> P5b@3000=0.107), bg_FA=0.331 (条件 #5 失败但趋势收敛)
- **Plan N @500**: 与 M 几乎一致, 需 @1000 区分
- **BUG-30 降级 HIGH→MEDIUM**: GELU 是 ~0.05 一致性惩罚非致命
- **BUG-31 (HIGH)**: Plan M/N 继承 BUG-27 vocab mismatch
- **BUG-32 (MEDIUM)**: Plan K off_cy LR decay 后退化
- **ORCH_017 签发**: P6 config 创建 + mini 训练启动 (GPU 0+2)

### [2026-03-08 08:35] 循环 #69 Phase 2 — Plan L car_P 回落 0.103, 类振荡重现; Plan M @500 首数据
- **Plan L @1500**: car_P 从 @1000 的 0.140 回落至 0.103, @1000 峰值系类别未展开时的虚高
- **类振荡重现**: Plan L truck(0.263→0.015), bus(0.334→0.024), 与 P5b 相同模式 — 系统性问题非投影宽度能解
- **bg_FA=0.447 持续恶化**: Critic 条件 #5 (bg_FA<0.30) 几乎无法达成
- **Plan K @1500**: car_P=0.060 仍远低于 P5b; off_cy=0.206 异常暴涨
- **Plan M @500 首数据**: 整体略逊于 Plan K @500, off_th=0.217 略优 (M) vs 0.228 (K)
- **Plan L off_cy=0.069**: 优于 P5b 全程最优 (0.085), 宽投影对 offset 有益
- **Plan K/L 即将完成** (~08:40-08:45), 下一 Cycle 获取 @2000 最终数据
- 不签发 ORCH — 等 @2000 最终数据做综合审计

### [2026-03-08 08:10] 循环 #68 Phase 2 — ★ VERDICT_DIAG_RESULTS: 方向对但混淆, 去 GELU, 10 类
- **VERDICT_DIAG_RESULTS (CONDITIONAL)**: 投影宽度方向正确但实验设计有致命混淆
- **BUG-27 (CRITICAL)**: Plan K vocab 不兼容 → Plan K 结论无效, 类竞争仍未回答
- **BUG-28 (HIGH)**: Plan L 双变量混淆, car_P=0.140 无法干净归因投影宽度
- **BUG-30 (HIGH)**: GELU 损害 off_th 升级为三组交叉印证. P6 必须去 GELU
- **P6 方向**: 10 类 + 宽投影 2048 + LayerNorm (无 GELU) + P5b@3000
- **待**: Plan L @2000 (bg_FA<0.30?) + Plan M/N @1000 (在线 DINOv3 效果?)
- 不签发 ORCH — 等数据满足 Critic 通过条件后再定稿 P6

### [2026-03-08 07:35] 循环 #67 Phase 2 — 四路诊断首批 @500 数据, 等待 @1000
- **4 GPU 满载**: Plan K/L (GPU 0,2) ~780 iter + Plan M/N (GPU 1,3) ~70 iter
- **Plan K @500 (单类 car)**: bg_FA=0.183 大幅领先 P5b, car_P=0.064 暂低 (重建中)
- **Plan L @500 (10 类偏差)**: Admin 用 10 类非 4 类, car_R=0.084 (投影层随机), pedestrian_R=0.451 (意外)
- **Plan M/N**: 在线 DINOv3 刚启动, 显存 28-29.5 GB, 速度 ~2x 慢, 首 val @500 ~08:00
- 不签发 ORCH/审计 — 数据太早, 等 @1000 (~07:50) 做关键判断

### [2026-03-08 07:10] 循环 #66 Phase 2 — P5b 完成! 四路诊断运行中, ORCH_016 签发
- **P5b COMPLETED**: @6000 最终: bg_FA=0.208 全程最低, off_th=0.198 达标红线! 红线 3/5
- **诊断实验 (ORCH_015)**: Plan K (单类 car) + Plan L (宽投影) iter ~280/2000, GPU 0,2
- **CEO 决策**: 放弃预提取, 走在线 DINOv3 路线; GPU 1,3 用于方案 B (unfreeze)
- **ORCH_016 签发**: DINOv3 在线提取 + unfreeze 实验 (Plan M/N, GPU 1,3)
- **VERDICT_P5B_3000 v2 归档**: Critic 更详细版本, 核心结论不变

### [2026-03-08 06:45] 循环 #65 Phase 2 — VERDICT_P6_ARCHITECTURE 处理, ORCH_015 诊断实验签发
- **VERDICT_P6_ARCHITECTURE (CONDITIONAL)**: 必须先诊断再选路径
- **BUG-23**: GPU 是 A6000 48GB, 非 24GB — 显存约束大幅放松
- **BUG-26**: 代码只用 CAM_FRONT, 全量 DINOv3 仅 ~175GB fp16, BLOCKER 降级
- **P5b 双层投影已触顶**: car_P@3000-5500 标准差 0.0015
- **优先级**: D (宽中间层 2048) > C (LoRA) > B (Full Unfreeze)
- **ORCH_015 签发**: 诊断实验 — 单类 car (plan_k) + 宽中间层 (plan_l)
- **历史 occ box 推迟到 P7**: P6 专注数据量+架构诊断

### [2026-03-08 06:10] 循环 #64 Phase 2 — P5b@5000 完全冻结, ORCH_014 签发 P6 准备
- **P5b@5000**: 10/14 指标零变化, 模型完全冻结; bg_FA=0.210, off_th=0.201
- **ETA ~06:33**: ~20min 后完成, GPU 0+2 即将释放
- **ORCH_014 签发**: P6 完整 nuScenes 准备 — 调查数据/特征/磁盘/config
- **P6 方向**: 完整 nuScenes + 10 类 + BUG-19 修复 + 双层投影 (CEO 批准)

### [2026-03-08 05:40] 循环 #63 Phase 2 — P5b@4500 模型冻结确认, 等待自然完成
- **P5b@4500**: 所有指标变化≤3.6%, lr=2.5e-08 下模型已冻结; bg_FA=0.210 再创新低
- **ETA ~06:29**: 剩余 @5000/@5500/@6000, 预期无实质变化
- ORCH: 不签发, P5b 自然完成后规划 P6

### [2026-03-08 05:15] 循环 #62 Phase 2 — ★ CEO 战略转向! + P5b@4000 第二次 LR decay 确认
- **CEO 战略转向 (最高优先级)**: 不再以 Recall/Precision 为最高目标, 不再高度预警红线
- **新目标**: 设计出在完整 nuScenes 上性能优秀的代码, mini 仅用于 debug
- **影响**: 红线降级为参考指标; bus/trailer 振荡确认为 mini 数据量天花板 (BUG-20); P6 重点转向完整 nuScenes
- **P5b@4000**: 第二次 LR decay 确认 (lr=2.5e-08), off_th=0.196, bg_FA=0.211 新低
- **off_cy=0.132 恶化**: mini 噪声, 新方向下不紧急
- **P5b 收尾**: 剩余 ~1600 iter, lr 极低, 预期极微变化, 自然跑完
- ORCH: 不签发

### [2026-03-08 04:45] 循环 #61 Phase 2 — P5b@3500 收敛稳定, CEO 批准双层投影
- **P5b@3500**: 变化幅度大幅缩小, 模型收敛中; bg_FA=0.214 持续新低, car_P=0.108 维持新高
- **truck_R 触底回升**: 0.205→0.234 (+14%), bus 低谷持平 0.053
- **off_th 微失守**: 0.200→0.206, 边缘振荡; 红线 2/5 (truck_R+bg_FA)
- **CEO 指令**: 批准双层投影 Linear(4096,1024)+GELU+Linear(1024,768), 覆盖 Critic BUG-21 A/B test 建议
- **第二次 LR decay @4000**: ~140 iter, lr 2.5e-07→2.5e-08, 预期模型基本冻结
- **重复 VERDICT_P5B_3000 清除**: sync loop 重建, 内容与已归档版本相同
- ORCH: 不签发, P5b 自然收敛

### [2026-03-08 04:15] 循环 #60 Phase 2 — ★★ P5b@3000 红线 3/5! VERDICT_P5B_3000 处理, 10 类 commit
- **P5b@3000 里程碑**: bg_FA=0.217 首破红线, off_th=0.200 精确达标, car_P=0.107 历史新高
- **红线 3/5 达标**: truck_R+bg_FA+off_th, 从 @2500 的 1/5 大幅回升, LR decay 效果显著
- **VERDICT_P5B_3000 (CONDITIONAL)**: P5b 跑完 6000; P6 从 @3000 启动 (car_P+bg_FA 最优)
- **BUG-20 (HIGH)**: bus 振荡=nuScenes-mini 数据量天花板, 非模型 bug
- **BUG-21 (MEDIUM)**: off_th 退化 0.142→0.200, 双层投影 GELU 可能损害方向信息
- **BUG-22 (HIGH)**: 10 类 ckpt 兼容性, 新 6 类 token 随机初始化需验证
- **10 类扩展已 commit**: GiT commit `2b52544`, P6 启用
- **Critic 建议**: 不追求 mini 上 bus/trailer 稳定; car 是唯一统计显著类别; P6 做投影 A/B test
- ORCH: 不签发 — P5b 继续自然运行至 6000, @3500 val 即将到来

### [2026-03-08 03:12] 循环 #59 Phase 1 — ★ P5b@2000 四类全活! LR decay @2500 即将触发
- **P5b@2000 亮点**: 四类全非零 (car 0.856, truck 0.340, bus 0.085, trailer 0.028)
- **bus 回暖比 P5 快 500 iter**: P5 bus 到 @2500 才恢复, P5b @2000 已有 0.085
- **bg_FA 持续改善**: 0.333→0.282, 接近红线; off_cx 0.064→0.055, off_cy 0.144→0.113
- **振荡周期确认 ~1000 iter**: @1000 均衡→@1500 car主导→@2000 再次均衡化
- **LR decay @2500 即将触发**: iter 2380, ~6 min, 预期大幅稳定训练
- ORCH_013 COMPLETED 确认, BUG-19 全面修复, 全 323 张 viz 已生成
- 审计不签发, 数据积极, 等 @2500 LR decay 关键验证

### [2026-03-08 01:55] 循环 #58 Phase 2 — BUG-19 v2 FIXED! z+=h/2 是高度截断根因
- **BUG-19 根因确认**: z 在 pkl 中是 box 中心 (nuScenes 约定), `z += h/2` 把它移到顶部
- **结果**: `_get_corners_lidar` 角点范围 [center, center+h] 而非 [center-h/2, center+h/2], 底部一半被截断
- **验证**: 近距离 truck z=center 时 bottom≈-1.84m=地面高度 ✓
- **修复**: 移除两处 `z += h/2` (训练 + 可视化), GiT commit `965b91b`
- **可视化确认**: 10 张图重新生成, 多边形完整覆盖车辆全身 (包括车轮), 覆盖面积显著增大
- **影响**: P5b 不受影响 (代码已在内存), P6+ 生效。这将显著增加正样本数量
- ORCH_013 COMPLETED, 无 pending VERDICT

### [2026-03-08 01:48] 循环 #58 Phase 1 — P5b@1500 类别振荡回归, BUG-19 v2 ORCH_013 签发
- **P5b@1500**: bus 坍塌 0.368→0, car 回到 0.924 主导, truck_R 下降 31%, sqrt 权重优势消退
- **P5b@1500 ≈ P5@1500**: 两者指标趋同, 暗示 sqrt 权重在 full LR 下无法维持类别均衡
- **Offset 全面恶化**: cx 0.049→0.064, th 0.168→0.203, 均失守红线
- **红线达标 1/5**: 仅 truck_R 达标, 从 @1000 的 3/5 大幅退步
- **ORCH_012 COMPLETED 但不充分**: Admin 修复 valid_mask→全True, 但 CEO 反馈可视化仍有高度截断
- **ORCH_013 DELIVERED**: BUG-19 v2, 调查 z+=h/2 在 box 投影中的影响
- **@2000 val 即将触发**: iter 1970, 预计 ~01:50
- 审计不签发, 等 @2000 和 BUG-19 v2 修复结果

### [2026-03-08 01:15] 循环 #57 Phase 1 — ★★ P5b@1000 突破! 三类同时活跃, bus 超 P5 全程最优
- **P5b@1000 三大突破**: 三类同时活跃 (car/truck/bus), bus_R=0.368 超 P5 全程最优, offset_cx=0.049 首破红线
- **sqrt 权重强力验证**: car 让出配额→truck 0.568 + bus 0.368, 设计意图完美实现
- **bg_FA=0.302 暂超红线**: 优于 P5 同期 (0.354), 预期 LR decay 后下降
- **ORCH_012 (BUG-19) DELIVERED**: Admin 尚未拾取, 等待下一轮 loop
- 审计不签发, 数据极其积极

### [2026-03-08 00:50] 循环 #56 Phase 1 — ★ P5b@500 首次 val! truck_R 6x 提升! BUG-19 记录
- **P5b@500 核心**: truck_R=0.153 (6x P5@500!), car_P=0.080 (+45%), bg_FA=0.235 (红线内)
- **sqrt 权重初步验证**: 类别竞争向均衡方向移动 (car↓ truck↑)
- **offset 继承**: cx=0.068, cy=0.085 完美继承 P5@4000 精度
- **bus_R=0.014**: 仍接近 0, P5 bus 到 @2500 才恢复, 需耐心
- **BUG-19 (CEO 发现)**: `proj_z0=-0.5` 高度截断导致部分有车 grid 未分配正样本, HIGH 严重性
- **ORCH_011**: 文件标记 COMPLETED 但实际未建软链接
- 审计不签发, 继续监控 @1000 和后续

### [2026-03-08 00:15] 循环 #55 Phase 1 — P5b 训练已启动! 双层投影验证生效
- **P5b RUNNING**: plan_i_p5b_3fixes, iter 330/6000, 从 P5@4000 加载
- **双层投影验证**: Sequential(4096→1024→768) 生效, 旧权重丢弃, grad_norm 峰值 70 (P5: 247)
- **ORCH_009 完成**: 旋转多边形可视化, 10 张图
- **ORCH_011 待确认**: Supervisor 报告 work_dirs 仍非软链接
- 审计不签发, 等 @500 首次 val (~00:22)

### [2026-03-07 23:30] 循环 #53 Phase 2 — ORCH_010 签发! VERDICT_INSTANCE_GROUPING 处理
- **ORCH_010 签发**: P5b 三项修复 (milestones+sqrt+双层投影), 从 P5@4000, HIGH 优先级
- **VERDICT_INSTANCE_GROUPING 处理**: CONDITIONAL — 接受但不纳入 P5b, 列入 P6+ 路线图
- **BUG-18 记录**: 评估时 GT instance 未跨 cell 关联
- **路线图修正 (CEO)**: 3D Anchor (P7b) 早于 V2X (P8); P7 历史 occ box 目的是预测未来 box (时序建模), 帮助 planning 的是历史 ego 轨迹 (非历史 occ box)

### [2026-03-07 23:25] 循环 #53 Phase 1 — ★ P5 完成! @6000 最终数据, VERDICT_INSTANCE_GROUPING
- **P5 训练完成**: 6000/6000, GPU 0,2 释放
- **P5@6000**: trailer_R=0.500 恢复, truck_R=0.228 止跌, offset_th=0.192 仍达标, bus_R=0.011 未恢复
- **P5 总结**: 9/12 指标超 P4, DINOv3 集成验证成功
- **P5@4000 确认为 P5b 起点**: 类别全平衡 + offset 最优
- **VERDICT_INSTANCE_GROUPING (CONDITIONAL)**: Critic 审计 instance_id token 提案, 4 个问题待解决, Phase 2 处理
- 审计: 不签发, P5b 已审计通过, Phase 2 签发 ORCH_010

### [2026-03-07 22:55] 循环 #52 Phase 1 — P5@5500: LR decay 收敛! trailer_P 首超 P4!
- **LR decay 收敛效果明确**: car_R +17%, trailer_R +25%, trailer_P +39%
- **trailer_P=0.046 首超 P4@4000 (0.044)**: P5 超 P4 指标增至 5 个
- **offset_th=0.182 仍达标**: LR decay 稳定了 offset 精度
- **bg_FA=0.186 小幅回升但仍优于 P4**: 更多前景预测的正常代价
- **bus_R=0.014, truck_R=0.203 未恢复**: 确认 P5b sqrt 加权必要性
- 审计: 不签发, 等 @6000 最终 val (~23:17)
- ORCH_009: 仍 PENDING

### [2026-03-07 22:30] 循环 #51 Phase 1 — P5@5000: LR decay 确认! bg_FA=0.160 新低!
- **LR decay 确认**: iter 5000 触发, lr 2.5e-06→2.5e-07, grad_norm 28.4→7.8
- **bg_FA=0.160 全程新低**: 从峰值 0.442 累计下降 64%, 远超 P4@4000 (0.194)
- **offset_th=0.163 恢复达标**: 从 0.226 回到红线内
- **bus_R=0.002 完全坍塌**: 类别振荡最严重点, 验证 P5b 三项修复的必要性
- **truck_R=0.199 持续下降**: 连续 4 轮 (0.679→0.199), 但仍远高于红线
- **P5@4000 仍是综合最优**: 四类均>0.3, 类别平衡最佳
- 审计: 不签发, 等 @5500 (LR decay 后首次 val, ~22:47) 数据
- ORCH_009: PENDING, Admin 尚未开始

### [2026-03-07 22:05] 循环 #50 Phase 2 — VERDICT_P5_MID 处理, P5b 规划
- Critic VERDICT: CONDITIONAL — P5b 必要
- 振荡根因: DINOv3 语义过强 + per_class_balance 等权 + Linear 压缩瓶颈
- BUG-17 升级 HIGH: 含 per_class_balance 极不均衡振荡
- P5b 方案: P5@4000 出发, 修正 milestones, sqrt 加权 balance, 可选双层投影
- P6 推迟: 先解决 DINOv3 适配问题
- ORCH: 不签发, 等 P5 完成后签发 ORCH_010 (P5b)
- ORCH_009 (多边形可视化) 仍 PENDING

### [2026-03-07 21:55] 循环 #50 — P5@4000+@4500 双 checkpoint, milestone 问题, 审计签发
- P5@4000 综合最优: 四类 Recall>0.3, offset 三指标全面超 P4, bg_FA=0.213
- P5@4500 bg_FA=0.167 创跨代新低, 但 Recall/offset 全线回调 — full LR 振荡
- BUG-17 确认: milestone 相对值, 实际 decay @5000 (延迟 1000), 二次 decay 不可达
- 决策: 接受单次 decay, 让训练完成; P5@4000 作为回退点
- **签发 AUDIT_REQUEST_P5_MID** → Critic 评估全局 + milestone 问题 + P6 方向

### [2026-03-07 21:20] 循环 #49 — P5@3500 LR decay 前基线, 多指标超 P4
- truck_R=0.679 超 P4 66%, offset_th=0.197 首破红线
- car_P=0.093 持续超 P4, P5 已有 4/11 指标优于 P4
- 类别轮换振荡确认: truck 强时 trailer 坍塌 (0.000), 零和竞争
- bg_FA 小幅反弹 0.260→0.290, 与 truck 跳升关联
- LR decay @4000 (~21:25) 即将发生, 预期收敛振荡 + 提升精度
- 审计: 不签发, 等 @4500 LR decay 效果后签发

### [2026-03-07 20:30] 循环 #47 — P5@3000 car_P 首超 P4, bg_FA 逼近红线
- car_P=0.091 首超 P4@4000 (0.081) — DINOv3 语义优势首次兑现
- bg_FA=0.260, 连续 3 轮下降, 峰值累计↓41%, 距红线仅 0.01
- truck_R 从红线恢复至 0.230, bus_R 振荡至 0.118, trailer_R 持续增长至 0.556
- 训练 50%, 不干预, 静待 @4000 LR decay
- 审计: 不签发, 计划 @4500 后做 P5 中期审计

### [2026-03-07 20:00] 循环 #46 — P5@2500 全类别恢复里程碑
- bus_R: 0→0.409 首次恢复 (2500 iter 沉默后爆发), trailer_R: 0.056→0.528 最强恢复
- bg_FA 连续第二轮下降: 0.383→0.321 (峰值累计↓27%)
- truck_R 触及红线 0.080 — 被 bus/trailer 恢复挤压, 暂不干预
- car_R 下降至 0.793 — 类别再平衡的正常代价
- 决策: 不干预, 等 LR decay @4000 自然修正
- 审计: 不签发, 计划 @4500 后做 P5 中期审计

### [2026-03-07 19:35] 循环 #45 — P5@2000 分析, bg_FA 自发回落, 干预取消
- bg_FA: 0.442→0.383 (↓13%) — 未干预下自发修正
- car_P=0.073 P5 历史最高, offset_cy=0.103 追平 P4@4000
- truck_R 从 0.418 回落至 0.216 — 与 bg_FA 回落关联, 预测更保守
- bus_R 仍 0.000 — 最顽固类别
- 决策: 取消干预, 继续观察至 @2500
- 新阈值: @2500 bg_FA>0.45 或 truck_R<0.08 → 重新考虑
- P5 学习动态确认: 高振幅探索模式, 不同于 P3/P4 的平稳收敛

### [2026-03-07 19:05] 循环 #44 — P5@1500 分析, bg_FA 危机应对
- truck_R 从 0 爆发至 0.418 — 类别学习突破
- bg_FA=0.442 历史最高 — DINOv3 特征让前景预测过于激进
- 决策: 等 @2000, 设干预阈值 bg_FA>0.50
- 干预方案: bg_balance_weight 2.5→5.0 + milestones 提前
- offset 全面优秀: cx=0.053, th=0.201 均接近红线

### [2026-03-07 18:30] 循环 #43 — VERDICT_3D_ANCHOR, 路线图更新
### [2026-03-07 18:00] 循环 #42 — ORCH_008 验收, P5 启动
### [2026-03-07 17:05] 循环 #40 — VERDICT_P4_FINAL, ORCH_008 签发
### [2026-03-07 16:55] 循环 #39 — P4 COMPLETED
### [2026-03-07 05:10] 循环 #37 — CEO 指令 #7, ORCH_007 签发
### [2026-03-07 03:10] 循环 #33 — P4 启动
### [2026-03-06 00:57] 循环 #1 — 签发 ORCH_001
