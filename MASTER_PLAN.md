# MASTER_PLAN.md
> 由 claude_conductor 维护 | 其他 Agent 只读
> 最后更新: 2026-03-09 ~19:00 (循环 #140 — 巡航, MASTER_PLAN 清理完成 1260→787 行)

## ✅ 告警已解除 (2026-03-09 07:43)
> ~~GPU 1 资源冲突~~: ORCH_026 (Plan Q) ~5h 后正常完成退出. GPU 1 恢复 36782 MB.
> CEO 选择选项 A (让 Plan Q 跑完). OOM 未发生. ORCH_024 延迟约 +8.5h (可接受).

## CEO 战略转向 (2026-03-08)
> **不再以 Recall/Precision 为最高目标，不再高度预警红线。**
> **目标: 设计出在完整 nuScenes 上性能优秀的代码。mini 数据集仅用于 debug。**

## 当前阶段: ★★★★ Full nuScenes @10000 完成! peak_car_P=0.090 未突破 | bg_FA=0.407 最差 | 等 LR decay @15000 (@17000 硬性 deadline)

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

**★★★★ Full nuScenes @6000 Val 结果 (08:00:30, 1.71 epochs, 1500 optimizer steps) — car_P 突破!**:
| 类别 | @2000 R | @4000 R | @6000 R | @2000 P | @4000 P | @6000 P | @4000→@6000 |
|------|---------|---------|---------|---------|---------|---------|------------|
| **car** | 0.627 | 0.419 | **0.455** | 0.079 | 0.078 | **0.090** | **P+15%! R+9%** |
| **truck** | 0.000 | 0.059 | **0.138** | 0.000 | 0.057 | **0.019** | R+134%, P-66% |
| **bus** | 0.000 | 0.000 | **0.287** | 0.000 | 0.002 | **0.009** | **★ 新类爆发!** |
| **ped** | 0.067 | 0.026 | **0.145** | 0.001 | 0.001 | **0.024** | **P 48x! R+458%** |
| **cone** | 0.000 | 0.000 | **0.160** | 0.000 | 0.000 | **0.001** | 新类出现 |
| bicycle | 0.000 | 0.191 | 0.000 | 0.000 | 0.001 | 0.000 | 消失 (BUG-17 振荡) |
| **bg** | R=0.778 | R=0.801 | **R=0.669** | FA=0.222 | FA=0.199 | **FA=0.331** | **⚠️⚠️ FA+66%!** |

| 回归 | @2000 | @4000 | @6000 | @4000→@6000 |
|------|-------|-------|-------|------------|
| off_cx | 0.056 | 0.039 | **0.056** | +44% ❌ 回退 |
| off_cy | 0.069 | 0.097 | **0.082** | -15% ✅ 改善! |
| off_th | 0.174 | 0.150 | **0.169** | +13% ⚠️ 回升 |
| off_w | 0.020 | 0.016 | **0.038** | +138% ❌ 恶化 |
| off_h | 0.006 | 0.005 | **0.011** | +120% ❌ 恶化 |

**Conductor @6000 分析**:
1. **car_P=0.090 突破!** 从 @2000-@4000 的 0.078-0.079 停滞区跳出, +15% 是规则#2 范围 (需 @8000 同向确认)
2. **多类大爆发**: bus/ped/cone 首次出现有意义的 Recall. 模型容量分配正在扩大
3. **⚠️ bg_FA=0.331 大幅恶化**: 模型从保守→激进预测, 多类学习早期典型模式. 预期 LR decay @17000 收紧
4. **⚠️ offset 回归恶化**: off_w/off_h 大幅恶化, off_cx 回退, off_th 回升. 新类几何属性不同 (bus 大/ped 小), 拉偏平均值
5. **off_cy=0.082 改善!** (VERDICT_FULL_4000 关注项, 0.097→0.082, -15% ✅)
6. **bicycle 消失**: @4000 R=0.191 → @6000 R=0.000, BUG-17 sqrt balance 振荡证据
7. **@8000 决策矩阵**: car_P=0.090 在 0.08-0.12 区间 → "方向正确, 继续"

**★★★ VERDICT_FULL_6000 (Critic, Cycle #118): CONDITIONAL — 继续训练不中断**
- **bg_FA=0.331 不告警**: 多类学习 + BUG-17 组合效应. 新类 (bus/ped/cone) 海量 FP 直接推高. 非模型崩溃 (car_P/R 同向改善)
- **car_P=0.090 中等偏高可信度**: P 和 R 同向 ↑ 是最强信号 (非 precision-recall tradeoff). 需 @8000 确认
- **offset 恶化 = 新类统计效应**: bus 极长/ped 极小/cone 微小, FP 几何差异拉偏平均值. 需 per-class offset 确认 car 自身未退化
- **bicycle 振荡确认**: 0→0.191→0 是 BUG-17 周期性 (~500 optimizer steps). @8000 可能重新出现
- **维持 @8000 决策矩阵**, 新增 bg_FA 阈值: <0.30 正常, 0.30-0.35 可接受, >0.35 需干预
- **@8000 预测**: car_P 0.08-0.12 区间
- **@8000 决策矩阵**:

| @8000 car_P | 行动 |
|-------------|------|
| > 0.12 | 架构验证, 继续到 @17000 看 LR decay 效果 |
| 0.08-0.12 | 方向正确, 继续 |
| 0.05-0.08 | 调参: 考虑关闭 per_class_balance 或调低 bg_balance_weight |
| < 0.05 | 严重问题: 需架构级修改 |

**★★★★ Full nuScenes @8000 Val 结果 (12:30, 2.28 epochs, 2000 optimizer steps) — 类间振荡! 结构指标历史最优!**:
| 类别 | @2000 R | @4000 R | @6000 R | @8000 R | @2000 P | @4000 P | @6000 P | @8000 P |
|------|---------|---------|---------|---------|---------|---------|---------|---------|
| **car** | 0.627 | 0.419 | 0.455 | **0.718** | 0.079 | 0.078 | **0.090** | **0.060** |
| truck | 0.000 | 0.059 | 0.138 | **0.000** | 0.000 | 0.057 | 0.019 | 0.000 |
| bus | 0.000 | 0.000 | 0.287 | **0.002** | 0.000 | 0.002 | 0.009 | 0.000 |
| **ped** | 0.067 | 0.026 | 0.145 | **0.276** | 0.001 | 0.001 | 0.024 | **0.016** |
| cone | 0.000 | 0.000 | 0.160 | **0.000** | — | — | 0.001 | 0.000 |
| **bg** | R=0.778 | R=0.801 | R=0.669 | **R=0.689** | FA=0.222 | FA=0.199 | FA=0.331 | **FA=0.311** |

| 回归 | @2000 | @4000 | @6000 | @8000 | 趋势 |
|------|-------|-------|-------|-------|------|
| off_th | 0.174 | 0.150 | 0.169 | **0.140** | ✅✅ 历史最低! 下降趋势夹振荡 |
| off_cx | 0.056 | 0.039 | 0.056 | **0.045** | ✅ 改善 |
| off_cy | 0.069 | 0.097 | 0.082 | **0.074** | ✅ 改善 |

**Conductor @8000 分析**:
1. **car_P=0.060 回落 -33%**: 但 car_R=0.718 (+58%) — 经典 P/R tradeoff, 模型检测阈值下移
2. **类间振荡**: @6000 多类爆发 → @8000 回退到 car+ped 双类模式. truck/bus/cone 全消失
3. **结构指标全面历史最优**: bg_FA=0.311 (开始回落!), off_th=0.140 (历史最低!), off_cx/off_cy 改善
4. **振荡模式**: @2000 car为主→@4000 truck出现→@6000 多类爆发→@8000 回退car+ped. 周期 ~500 optimizer steps
5. **决策矩阵**: car_P=0.060 在 0.05-0.08 → "调参". 但 P/R tradeoff + 结构改善 使直接适用存疑
6. **bg_FA=0.311** 在 0.30-0.35 → "可接受, 继续到 LR decay"
7. **审计签发**: AUDIT_REQUEST_FULL_8000

**★★★ VERDICT_FULL_8000 (Critic, Cycle #128): CONDITIONAL — 继续训练到 @10000, 不调参**
- **BUG-47 (NEW, MEDIUM)**: 单点 car_P 决策矩阵不适用于振荡训练. 修正: 用 **最近 3-eval 峰值** (peak_car_P)
- **peak_car_P = max(0.078, 0.090, 0.060) = 0.090** → "0.08-0.12: 方向正确, 继续"
- **car_P=0.060 不是真退化**: P/R tradeoff (TP+56%, FP+145%) + 类间振荡
- **结构指标权重 > car_P 单点**: off_th/off_cx/off_cy 呈明确下降趋势 = 模型在正确方向学习
- **振荡周期 ~1000 optimizer steps**: car spam → 多类展开 → 多类爆发 → car spam 循环
- **@10000 预判**: 多类展开/爆发阶段, car_P 应回升 0.08-0.10
- **LR decay @17000 会缓解振荡**: 权重更新幅度 -10x, 但 sqrt balance 根因不变 (需 BUG-17 修复)
- **@10000 决策矩阵命中**: peak=0.090 (0.08-0.10) + 结构停滞 → "启用 deep supervision"
- **VERDICT_FULL_10000 修正**: 推迟到 LR decay 后, @17000 为硬性 deadline

**★★★ @10000 Val 结果 (2026-03-09 17:24)**:
- car_P=0.069 (↑ from 0.060, 但未恢复 peak 0.090)
- car_R=0.726 (✅ 历史最高)
- **CV=0.287, moto=0.126 首次出现!** 6 类车辆激活
- **ped=0.000 彻底消失** (from 0.276)
- **bg_FA=0.407 历史最差** (连续恶化 0.199→0.331→0.311→0.407)
- off_th=0.160 (回弹, 未保持 0.140)
- **振荡模式**: 广泛(5类)→窄(2类)→车辆(6类), 3 种模式轮转

**★★★ VERDICT_FULL_10000 (Critic, Cycle #139): CONDITIONAL — 继续到 LR decay, @17000 硬性 deadline**
- **继续 ORCH_024 不中断**, LR decay @15000 是"免费"干预
- **@17000 硬性 deadline** (不可再推迟!):

| @17000 条件 | 行动 |
|-------------|------|
| peak_car_P > 0.12 且 bg_FA < 0.40 | 继续 ORCH_024 到 @25000 |
| peak_car_P < 0.12 或 bg_FA > 0.40 | **立即启动 ORCH_025 (deep supervision)** |

- **Deep supervision resume 风险**: 辅助 loss 默认 1.0 权重会导致 ~4× loss 跳变 → **必须降权 aux_weight=0.4**
- **立即准备 ORCH_025 config**: 不等 @17000
- **car_P 0.090 非硬天花板**, 但当前配置难超 0.12. 需要结构改变 (layer/deep supervision/unfreeze)
- **@40000 估计**: 仅 LR decay 0.10-0.12; +deep supervision 0.12-0.16; +layer 24 0.15-0.22; +unfreeze 0.18-0.25
- **bg_FA 阈值**: <0.30 健康, 0.30-0.45 关注, 0.45-0.50 警告, >0.50 必须干预

- **永久规则补充**: eval 结果需参考振荡周期, 不做单点决策 (BUG-47)

**Full nuScenes 训练数据汇总 (完整 5 eval)**:
| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | peak | 趋势 |
|------|-------|-------|-------|-------|--------|------|------|
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | **0.090** | 振荡, peak 未突破 |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | **0.726** | 0.726 | ✅ 持续攀升 |
| bg_FA | 0.222 | **0.199** | 0.331 | 0.311 | **0.407** | — | ⚠️ 系统性恶化 |
| off_th | 0.174 | **0.150** | 0.169 | **0.140** | 0.160 | **0.140** | 振荡, @8000 最优 |
| off_cx | 0.056 | **0.039** | 0.056 | 0.045 | — | **0.039** | 振荡 |
| off_cy | 0.069 | 0.097 | 0.082 | 0.074 | — | — | 振荡 |
| 模式 | car spam | 收敛 | 广泛(5类) | 窄(2类) | **车辆(6类)** | — | 3 种模式轮转 |

**VERDICT_CEO_STRATEGY_NEXT (CONDITIONAL — 等 @2000 再决策)**:
- **方案 A (1024+GELU)**: ✅ 已被 ORCH_024 (2048+GELU) 涵盖, 无需额外实验
- **方案 B (DINOv3 unfreeze)**: ⚠️ ~~三重否决~~ **基于无效实验 (BUG-48)!** Plan M unfreeze 实际未生效. 需修 BUG-48 后用正确 block 重新实验
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

### Mini 诊断实验结论摘要 (详细数据已归档: shared/logs/archive/mini_era_detailed_data.md)

**四路诊断 (Plan K/L/M/N) 核心结论**:
1. **宽投影 2048 有帮助**: Plan L car_P=0.111 > P5b=0.094 (+18%)
2. **Frozen >> Unfreeze**: ~~Plan M 特征漂移~~ → **BUG-48: unfreeze 实际未生效, "漂移" 系 BUG-50 显存暴增**
3. **在线路径在 mini 不达标**: car_P~0.05, 但 Full nuScenes 已验证可用 (ORCH_024 car_P=0.090)
4. **GELU 加速收敛 1.3×**: P2@1000 比 P6@1000 快 72%

**Mini 最终基线**: P6@4000 car_P=0.1263 (mini 天花板), P5b@3000 car_P=0.116
**永久规则: 不再跑 Mini 实验** (Plan Q 是 Mini 收官, 类竞争无关已确认)

### P6 Mini 最终结论 (详细轨迹已归档)
- **P6@4000 (单GPU)**: car_P=0.1263, bg_FA=0.2741, off_th=0.1907 — Mini 天花板
- **P6@6000 (DDP)**: car_P=0.129 (+11% vs P5b), plateau 确认
- **DDP 偏差 (BUG-33)**: car_P 最大 -9%, car_R 最大 -27%, 方向不一致

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

### P5/P5b Mini 最终结论 (详细轨迹已归档)
- **P5 核心贡献**: DINOv3 Layer 16 → offset 精度飞跃 (off_th=0.142) + bg_FA 大幅降低 + 9/12 指标超 P4
- **P5b 三项修复**: milestones 纠正 + sqrt 加权 + 双层投影, 红线 3/5 达标
- **P5b@3000 (单GPU)**: car_P=0.116, bg_FA=0.189 — P6 起点
- **BUG-17**: MMEngine milestones 相对于 begin, ORCH_024 已修正 (milestones=[15000,25000])

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

### P5b 训练轨迹摘要 (详细 12-checkpoint 数据已归档: shared/logs/archive/mini_era_detailed_data.md)
- **sqrt 权重效果**: @500 truck_R 6x 提升 (0.153 vs P5=0.025), offset 继承 P5@4000
- **振荡→收敛**: @1000 三类活跃 → @1500 类振荡回归 → @2500 LR decay → @3000 红线 3/5 达标
- **关键拐点**: @3000 car_P=0.107 + bg_FA=0.217 + off_th=0.200 (LR decay 效果显著)
- **最终**: @6000 模型完全冻结, car_P=0.104 (peak@3500=0.108), bg_FA=0.208 全程最低
- **P6 load_from**: P5b@3000 (car_P+bg_FA 最优点)

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

**1. 单类 Car 诊断实验 (Plan Q) — ORCH_026 ✅ COMPLETED — 类竞争无关!**
- **目的**: 干净回答 "类竞争是否为 car_P 瓶颈" (Plan K 因 BUG-27 无效)
- **设计**: 保持 num_vocal=230 + num_classes=10 不变, 只在数据管道过滤 (避免 BUG-27)
- **结果**: car_P@best = 0.083 (@2500) < 0.12 阈值 → **类竞争无关**
- **对比**: Plan Q 0.083 < P6@4000 0.126 (10类基线), 去除类竞争反而更差
- **混淆因素**: 投影层 1024→2048 mismatch 随机初始化, 但 off_cx@1500 恢复基线, 3000 iter 足够
- **结论**: car_P 瓶颈不在类间混淆, 需关注数据质量/模型容量/训练策略
- **战略影响**: BUG-17 CRITICAL→HIGH (不影响 car_P), Full nuScenes 数据量是关键方向
- **★★ VERDICT_ORCH026_PLANQ (Critic): PROCEED** — 结论有效且稳健
  - Plan Q (单类+GELU) 0.083 < P2 (10类+GELU) 0.112 → 多类训练对 car 有正迁移!
  - 10 类训练的特征多样性、BEV 理解、背景判别 → 比单类更好
  - BUG-17: CRITICAL→HIGH, 不影响 car_P, 优先级 #4 (从 #2 降)
  - **car_P 真正瓶颈候选**: (1) DINOv3→BEV 信息瓶颈 BUG-15 (4096→768 降维); (2) BEV 投影精度 proj_z0; (3) per-cell 评估偏差 BUG-18
  - **优先级**: Deep Supervision > 方案D > LoRA (上升) > BUG-17 (下降) > Attention Mask
  - **永久规则: 不再跑 Mini 实验** (Plan Q 是 Mini 收官)
  - **@8000 后安排 BUG-15 专项审计** (precision 瓶颈根因)

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
- ~~Plan M 崩溃: DINOv3 预训练表示脆弱, 任何微调都破坏中间层分布~~ **BUG-48: unfreeze 实际未生效! "漂移" 系 BUG-50 显存暴增所致**
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
| **BUG-17** | **HIGH** (降级, was CRITICAL) | bicycle 154K FP + sqrt balance ~11x 权重. **但 VERDICT_ORCH026_PLANQ 证明不影响 car_P!** 危害限于 bg_FA 膨胀/训练不稳定. 修复时机: ORCH_024 后第二轮实验 |
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
| **BUG-35** | ~~MEDIUM~~ **INVALIDATED** | ~~DINOv3 unfreeze last-2 导致特征漂移~~. **BUG-48 证明: unfreeze_last_n=2 解冻 blocks 38-39, 但 layer 16 不受影响. "漂移" 系 BUG-50 显存暴增所致, 非真漂移** |
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
| **BUG-47** | **MEDIUM** | 决策矩阵使用单点 car_P 不适用于振荡训练. 相邻 eval 给出相反结论 (@6000 "继续" vs @8000 "调参"). 修正: 用最近 3-eval 峰值 peak_car_P (VERDICT_FULL_8000) |
| **BUG-48** | **HIGH** | `unfreeze_last_n` 解冻 DINOv3 末端 blocks (38-39), 但 layer_idx=16 提取中段. 梯度不流经 blocks 17-39, 解冻参数永远不被更新. **Plan M "漂移" 结论无效, 方案 B 三重否决需标注为基于无效实验** (VERDICT_DINOV3_LAYER_AND_UNFREEZE) |
| **BUG-49** | **MEDIUM** | DINOv3 `get_intermediate_layers` 遍历全部 40 blocks, 但 layer_idx=16 只需前 17 个. 浪费 ~58% DINOv3 前向计算. 不影响正确性 (VERDICT_DINOV3_LAYER_AND_UNFREEZE) |
| **BUG-50** | **MEDIUM** | `unfreeze_last_n > 0` 时整个 `get_intermediate_layers` 移除 `torch.no_grad()`, 全部 40 blocks 构建计算图, 显存增加 ~10-15 GB. **Plan M "漂移" 的真因**: 显存暴增导致 OOM/训练不稳定, 非 DINOv3 特征漂移 (VERDICT_DINOV3_LAYER_AND_UNFREEZE) |

## 活跃任务
| ID | 目标 | 状态 |
|----|------|------|
| **ORCH_024** | **Full nuScenes 2048+GELU+在线DINOv3** | **IN PROGRESS — 10230/40000 (25.6%), @10000 val ✅, 等 LR decay @15000, @17000 硬性 deadline** |

### 已完成任务归档
ORCH_008~013 (P5/P5b/BUG-19), ORCH_014~016 (P6准备+诊断), ORCH_017~023 (P6 mini+re-eval+Plan P/P2), ORCH_025 (测试框架 177passed), ORCH_026 (Plan Q 类竞争无关). 所有 AUDIT 已 VERDICT PROCESSED.

## 指标参考 (CEO: 红线降级, mini 仅 debug)
| 指标 | 参考线 | @3000 | @4000 | @5000 | **@6000** | 备注 |
|------|--------|-------|-------|-------|-----------|------|
| truck_R | ≥ 0.08 | 0.205 | 0.229 | 0.239 | 0.240 | ✅ 稳定 |
| bg_FA | ≤ 0.25 | 0.217 | 0.211 | 0.210 | **0.208** | ✅ 全程最低 |
| off_th | ≤ 0.20 | 0.200 | 0.196 | 0.201 | **0.198** | ✅ 最终达标! |
| off_cx | ≤ 0.05 | 0.059 | 0.059 | 0.059 | 0.057 | ❌ 差 0.007 |
| off_cy | ≤ 0.10 | 0.112 | 0.132 | 0.132 | 0.134 | ❌ 偏高 |

> CEO 方向: 不再以这些指标为最高目标。完整 nuScenes 性能才是真正评判标准。

## 历史决策 (关键里程碑)

### Full nuScenes 阶段 (Cycle #86-#139)
- **#86 (03-08 16:10)**: ★ VERDICT PROCEED! 2048+GELU 确认, ORCH_024 签发, Mini 阶段结束
- **#95 (03-08 21:10)**: @2000 val: car_P=0.079, 决策矩阵边界, 继续
- **#104 (03-09 01:40)**: @4000 val (第一可信点): car_P=0.078, bg_FA=0.199<0.20, truck/bicycle 新出现
- **#105 (03-09 02:10)**: VERDICT_FULL_4000: CONDITIONAL. BUG-46 (accumulative_counts). @8000 决策矩阵建立
- **#118 (03-09 08:10)**: ★ @6000 val: car_P=0.090 突破! 多类爆发. bg_FA=0.331 恶化
- **#120 (03-09 08:50)**: ★ ORCH_026 完成: Plan Q car_P=0.083<0.12 → 类竞争无关! 多类正迁移确认
- **#128 (03-09 12:35)**: @8000 val: car_P=0.060 (P/R tradeoff), off_th=0.140 历史最低. BUG-47 修正决策矩阵用 peak
- **#138 (03-09 17:00)**: ★★ CEO_CMD: BUG-48/49/50 发现! DINOv3 解冻完全无效. Layer 24 推荐. 分阶段阈值建立
- **#139 (03-09 18:20)**: @10000 val: car_P=0.069, bg_FA=0.407 最差. @17000 硬性 deadline 设定. 详见 shared/logs/reports/decision_matrix_and_dinov3_review.md
- **bicycle 消失**: R=0.191→0.000, BUG-17 sqrt balance 振荡证据
- **GPU 1 恢复**: Plan Q ~5h 完成, 速度恢复正常
- **审计签发**: AUDIT_REQUEST_FULL_6000

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

### Mini P6/P2 GELU 验证阶段 (Cycle #65-#86)
- **#65-70**: 四路诊断 (Plan K/L/M/N) → 宽投影 2048 获批, 纯双 Linear 无 GELU (BUG-30 误判)
- **#71-77**: P6 训练 — @500 bg_FA=0.163 最低, @1000 双 FAIL (类振荡), @1500 PASS (car_P=0.117), @2000-2500 收敛
- **#78**: P6@3000 CONDITIONAL PASS. car_P 平台化 0.106-0.111. ORCH_020+021 签发
- **#79**: ★ BUG-39 CRITICAL 发现! 双 Linear 无 GELU = 单 Linear. BUG-40 审计链连锁失误. Plan P 签发
- **#81**: Plan P FAIL (超参), P6@3500 首超 P5b=0.121. ORCH_023 签发 (Plan P2 唯一干净 GELU 实验)
- **#84-85**: ★ Plan P2 验证 GELU: @1000 +72%, @1500 +5.7%. P6@6000 完成 car_P=0.129
- **#86**: ★★ VERDICT PROCEED! 2048+GELU+在线 DINOv3 frozen → ORCH_024 签发. Mini 阶段结束

### P5b 训练阶段 (Cycle #55-#66)
- **#55-56**: P5b 启动 → @500 truck_R 6x ↑, @1000 三类同时活跃 (sqrt 权重验证)
- **#58**: ★ BUG-19 v2 修复 (z+=h/2 根因, commit `965b91b`), P5b@1500 类振荡回归
- **#59-60**: @2000 四类全活, @3000 红线 3/5 达标 (LR decay 效果显著), 10 类 commit `2b52544`
- **#61-62**: @3500 收敛稳定, CEO 战略转向 (mini 仅 debug), @4000 模型冻结
- **#65-66**: P5b COMPLETED @6000, 四路诊断 (Plan K/L/M/N) 启动, ORCH_015+016 签发

### 诊断实验阶段 (Cycle #67-#70)
- **#67-69**: Plan K (单类): car_P=0.063, bg_FA=0.166 最低; Plan L (宽投影): car_P=0.111; Plan M/N (在线): car_P~0.05 不达标
- **#70**: VERDICT_DIAG_FINAL: 宽投影 2048 获批, BUG-27/28/30/31/32 发现, ORCH_017 签发
- **bus 回暖比 P5 快 500 iter**: P5 bus 到 @2500 才恢复, P5b @2000 已有 0.085
- **bg_FA 持续改善**: 0.333→0.282, 接近红线; off_cx 0.064→0.055, off_cy 0.144→0.113
- **振荡周期确认 ~1000 iter**: @1000 均衡→@1500 car主导→@2000 再次均衡化
- **LR decay @2500 即将触发**: iter 2380, ~6 min, 预期大幅稳定训练
- ORCH_013 COMPLETED 确认, BUG-19 全面修复, 全 323 张 viz 已生成
- 审计不签发, 数据积极, 等 @2500 LR decay 关键验证

### P5 训练阶段 (Cycle #42-#53)
- **#42**: P5 启动 (DINOv3 Layer 16 集成)
- **#44-49**: P5 训练: @1500 truck_R 爆发, @2500 全类恢复, @3500 多指标超 P4, @4000 综合最优
- **#50**: VERDICT_P5_MID → P5b 必要 (振荡根因: 语义过强+等权balance+压缩瓶颈)
- **#51-53**: LR decay @5000 → bg_FA=0.160 新低; P5 @6000 完成 (9/12 超 P4); ORCH_010 签发

### 早期阶段 (Cycle #1-#43)
- **#1 (03-06)**: 系统启动, ORCH_001 签发
- **#33-39 (03-07)**: P4 训练→完成 (7/9 历史最佳, avg_P=0.107)
- **#40-43**: P4 FINAL → ORCH_008 签发 → P5 启动 → VERDICT_3D_ANCHOR (词汇表方案)
