# Conductor 上下文保存 (compact 前)
> 时间: 2026-03-07 03:15
> 循环: #33 完成, 下一轮 #34
> 协议: 不直接读 GiT/, 通过 shared/logs/supervisor_report_latest.md 获取数据

## 当前正在做什么
- P3 训练已完成 (4000/4000), P4 训练已启动
- P4 包含 AABB→旋转多边形标签修复 + BUG-11 修复 + config 调优
- ORCH_006 (DINOv3 离线预提取) Admin 并行执行中
- 等待 P4@500 首次 val 验证 AABB 修复效果

## CEO 未处理指令
- CEO_CMD.md: 空, 无待处理指令

## P4 训练状态 — RUNNING
- **实验**: Plan G (AABB fix + BUG-11 fix + config 调优), config `plan_g_aabb_fix.py`
- **起点**: P3@3000 checkpoint
- **进度**: 前 50+ iter (warmup 阶段)
- **PID**: 3929983
- **GPU**: 0,2 (RTX A6000) | CEO 限制只用 0,2
- **工作目录**: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_g_aabb_fix/`
- **ETA 完成**: ~06:20 (3月7日)
- **首次 val**: P4@500
- **Config 变化 vs P3**: bg_balance_weight 3.0→2.0, reg_loss_weight 1.0→1.5, use_rotated_polygon=True

## P4 早期信号
- Warmup 正常, LR 从 ~1e-6 爬升
- 梯度裁剪率 60% (高于 P3 的 0%) — 原因: reg_loss_weight 提升 + 标签分布变化
- loss_reg 偏高 (预期, reg_loss_weight 1.5x)
- 无 NaN/OOM, 显存 21.5GB/49.1GB per GPU

## P3@3000 基线 (P4 起点)
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
| offset_cx | 0.059 | 0.068 | -13.2% |
| offset_cy | 0.123 | 0.095 | +29.5% |
| offset_th | 0.214 | 0.217 | -1.4% |
| avg_P | **0.147** | 0.121 | +21.5% |

## P3@4000 最终结果 (参考)
| 指标 | P3@4000 | P2@6000 | vs P2 |
|------|---------|---------|-------|
| car_R | 0.570 | 0.596 | -4.4% |
| car_P | 0.084 | 0.079 | +6.3% |
| truck_R | 0.302 | 0.290 | +4.1% |
| truck_P | 0.211 | 0.190 | +11.1% |
| bus_R | 0.712 | 0.623 | +14.3% |
| bus_P | 0.153 | 0.150 | +2.0% |
| trailer_R | 0.622 | 0.689 | -9.7% |
| trailer_P | 0.041 | 0.066 | -37.9% |
| bg_FA | **0.185** | 0.198 | -6.6% |
| offset_cx | 0.052 | 0.068 | -23.5% |
| offset_cy | **0.087** | 0.095 | -8.4% |
| offset_th | 0.214 | 0.217 | -1.4% |
| avg_P | 0.122 | 0.121 | +0.8% |

## P3 历史性成就
- bg_FA=0.185 全项目历史最低
- offset_cy=0.087 首破红线 (≤0.10)
- offset_th=0.191 @2000 首触红线 (≤0.20, 未保持)
- truck_P=0.306 @3000 历史最高
- 9/12 指标超 P2@6000

## Phase 2 触发条件 (CEO 指令 #6)
- P4 首批 val 后 avg_P > 0.15 → Phase 2 低优先级
- P4 首批 val 后 avg_P < 0.12 → 立即集成 DINOv3 特征

## ORCH 状态
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_001 | BUG-12 修复 | COMPLETED |
| ORCH_002 | BUG-9 诊断 | COMPLETED |
| ORCH_003 | P1 eval + P2 启动 | COMPLETED |
| ORCH_004 | BUG-8/10 修复 + P3 启动 | COMPLETED |
| **ORCH_005** | **AABB+BUG-11+P4 训练** | **COMPLETED (验收通过)** |
| **ORCH_006** | **DINOv3 离线预提取** | **DELIVERED (Admin 执行中)** |

## Critic 审计
- VERDICT_P2_FINAL: CONDITIONAL (条件已满足)
- VERDICT_ARCH_REVIEW: CONDITIONAL (已处理, 持久追踪区域建立)
- VERDICT_P3_FINAL: CONDITIONAL — avg_P 系统性瓶颈, loss 调参达天花板, 须转向标签/架构

## BUG 跟踪
| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2 | CRITICAL | **FIXED** |
| BUG-8 | CRITICAL | **FIXED & VALIDATED** — cls loss bg weight |
| BUG-9 | 致命 | **FIXED** — max_norm=10.0 |
| BUG-10 | HIGH | **FIXED & VALIDATED** — warmup 500步 |
| BUG-11 | LOW | **FIXED (ORCH_005)** — 默认类别顺序 |
| BUG-12 | HIGH | **FIXED** — eval slot 排序 |
| BUG-13 | LOW | UNPATCHED — slot_class 溢出 |
| BUG-14 | MEDIUM | 新发现 — Grid token 冗余 (架构) |
| BUG-15 | HIGH | 新发现 — DINOv3 利用率极低 (架构) |

## 架构审计待办 (持久追踪)
### 紧急修复 — 全部完成
- [x] BUG-2, BUG-8, BUG-10, BUG-11

### 架构/标签优化
- [x] AABB → 旋转多边形 (ORCH_005)
- [ ] DINOv3 离线预提取 (ORCH_006 进行中)
- [ ] Score 区分度改进
- [ ] BUG-14: Grid token 冗余
- [ ] BUG-15: DINOv3 利用率
- [ ] 新增层 12-17 加 global attention

### 未实现历史分析
- [x] 分析 1: AABB (ORCH_005)
- [x] 分析 3: Center/Around
- [ ] 分析 2: 2D-3D 视觉对齐
- [ ] 分析 4: Token 合并

## CEO 指令归档
- #1 (03-06 01:15): 读历史审计报告
- #2 (03-06 01:15): 转达 Ops 修 watchdog
- #3 (03-06 15:20): 深度重读历史审计
- #4 (03-06 ~21:30): GPU 限制 (0,2 only)
- #5 (03-06 ~23:30): 架构审计待办追踪
- #6 (03-07 02:50): 批准 P4, Phase 1+2 并行, 评估标准

## 关键历史洞察
1. BUG-9: 100% 梯度裁剪 → Sign-SGD (P2 修复)
2. BUG-8: cls loss 丢弃背景 → precision 崩塌 (P3 修复, truck_R +34%)
3. AABB 过估: truck 45° 旋转覆盖 ~2x cell → P4 用旋转多边形修复
4. P2 LR decay @3000 over-prediction: bg_FA 0.284→0.198
5. P3 LR decay @2500 同样验证: truck_R 0.152→0.336 (+121%)
6. P3@2000 offset_th 首破红线 (0.191), LR decay 后回升至 0.214 (分类挤压回归)
7. Critic: avg_P 瓶颈是系统性的 — AABB 污染 + score 无区分度 + DINOv3 只用 Conv2d
8. Critic: P3@3000 是更好的 P4 起点 (avg_P=0.147 vs @4000 的 0.122)
9. Critic: bg_balance_weight=3.0 偏高压制 car_R, 建议降至 2.0

## 红线
| 指标 | 红线 |
|------|------|
| truck_R | < 0.08 |
| bg_FA | > 0.25 |
| offset_th | <= 0.20 |
| offset_cy | <= 0.10 |
| avg_P | >= 0.20 |

## 系统状态
- 全部 Agent UP
- 基础设施: sync_loop + watchdog + all_loops.sh 正常
- GPU 0,2: P4 训练 | GPU 1,3: 空闲

## 待办 / 下一步
1. **循环 #34**: 等待 P4@500 首次 val (AABB 修复效果验证!)
2. **ORCH_006 进度**: DINOv3 预提取完成状态
3. **Phase 2 触发**: 根据 avg_P 决定是否集成 DINOv3 特征
4. **P4 全程监控**: @500→@1000→...→@4000
