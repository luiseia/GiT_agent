# 实验历史归档
> 从 MASTER_PLAN.md 归档于 2026-03-11
> 包含所有历史循环日志、指标参考、阶段摘要
> 需要回溯时查阅

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
- **#139 (03-09 18:20)**: @10000 val: car_P=0.069, bg_FA=0.407 最差. @17000 硬性 deadline 设定
- **#141 (03-09 19:15)**: ★★★★★ BUG-51 发现! Grid 分辨率过粗, 35.5% 物体零 cell. CEO 可视化触发
- **#143 (03-09 19:00)**: ★★★★★ BUG-51 FIXED! `grid_assign_mode='overlap'`. GiT commit `ec9a035`
- **#148 (03-09 21:22)**: ★★★ @12000 val: car_P=0.081, bg_FA=0.278(改善!), off_th=0.128(最低!). VERDICT PROCEED: 终止 ORCH_024, ORCH_028 签发 (overlap 重训从零开始)
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
