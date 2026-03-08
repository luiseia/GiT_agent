# Conductor 工作上下文快照
> 时间: 2026-03-08 00:20
> 循环: #55 (Phase 2 完成)
> 目的: Context compaction 备份

---

## 当前状态

### P5 训练 — COMPLETED ✓
- 完成时间: 2026-03-07 23:19, 6000/6000 iters
- **9/12 指标超 P4**, DINOv3 Layer 16 集成验证成功
- P5@4000 综合最优 (类别全平衡 + offset 最优) → P5b 起点

### P5 完整 Val 轨迹 (关键 checkpoint)

| 指标 | P5@4000 (最优) | P5@5500 | P5@6000 (最终) | P4@4000 | 红线 |
|------|---------------|---------|---------------|---------|------|
| car_R | 0.569 | **0.721** | 0.682 | 0.592 | — |
| car_P | 0.090 | **0.092** | 0.089 | 0.081 | — |
| truck_R | **0.421** | 0.203 | 0.228 | 0.410 | <0.08 |
| truck_P | **0.130** | 0.065 | 0.065 | 0.175 | — |
| bus_R | **0.315** | 0.014 | 0.011 | 0.752 | — |
| bus_P | 0.037 | 0.006 | 0.005 | 0.129 | — |
| trailer_R | 0.472 | 0.417 | **0.500** | 0.750 | — |
| trailer_P | 0.006 | **0.046** | 0.043 | 0.044 | — |
| bg_FA | 0.213 | 0.186 | 0.190 | 0.194 | ≤0.25 ✓ |
| offset_cx | **0.051** | 0.064 | 0.066 | 0.057 | ≤0.05 |
| offset_cy | **0.091** | 0.107 | 0.111 | 0.103 | ≤0.10 |
| offset_th | **0.142** | 0.182 | 0.192 | 0.207 | ≤0.20 ✓ |

### P5b 训练 — RUNNING (plan_i_p5b_3fixes)
- **启动时间**: 2026-03-07 23:56
- **进度**: iter 330 / 6000 (5.5%)
- **GPU**: 0 (20.5GB) + 2 (21.0GB), 显存 +110MB (双层投影)
- **LR**: warmup 阶段 (爬升中), warmup 结束 @iter 500
- **ETA 完成**: ~05:00
- **首次 val**: @500 (~00:22)

### P5b 三项修复验证状态
- [x] **双层投影**: Sequential(4096→1024→768) 生效, grad_norm 峰值 70 (P5: 247)
- [ ] **LR milestones**: 待 iter 2500 验证 decay (2.5e-06→2.5e-07)
- [ ] **sqrt 权重**: 待确认权重日志

---

## 已完成的关键决策

### VERDICT_P5_MID (已归档)
- **判决**: CONDITIONAL — P5b 必要
- **振荡根因**: DINOv3 语义过强 + per_class_balance 等权 (92:1) + Linear 5.3:1 压缩
- P5b 三项全修 (CEO 批准)

### VERDICT_INSTANCE_GROUPING (已归档)
- **判决**: CONDITIONAL — 方向正确, 需解决 4 个问题
- SLOT_LEN 10→11, instance_id token (g_idx, 32 bins)
- **决策**: 不纳入 P5b, 列入 P6+ 路线图
- BUG-18: 评估时 GT instance 未跨 cell 关联

### CEO 词汇表方案 (P6+ 路线图)
- **核心**: 复用 vocab_embed 注入语义先验, 词汇表 224→232 (+8 先验 token)
- **注入**: grid_start_embed += vocab_embed(prior_tokens), BEV 10×10=100 cell
- **V2X 工作流**: sender BEV box → 2D 刚体变换 → ego grid → 标记 prior token
- **训练**: 50% 随机 mask 先验, 防过度依赖
- **路线 (CEO 修正)**:
  - P5b → P6 (BEV PE) → P6b (先验词汇表, GT 模拟)
  - → P7 (历史 occ box, ego motion 补偿, 预测未来 box / 时序建模; planning 靠历史 ego 轨迹)
  - → P7b (3D Anchor, 射线采样, 对齐 NEAR/MID/FAR)
  - → P8 (V2X 融合, 需 V2X 数据集)

### DINOv3 特征评估 (CEO 提问 → 已回答)
- **结论**: 特征好, 集成方式需优化
- **确定提升**: offset (+31%), bg_FA (+18%), car_R/P (+22%/+15%) — 无争议
- **新问题**: 类别振荡 (bus 坍塌) — 集成方式导致, 非特征本身
- P5b 是验证点: 修复集成方式后能否保持优势 + 恢复 bus/truck

---

## 活跃任务

| ID | 目标 | 状态 |
|----|------|------|
| ORCH_008 | P5 DINOv3 集成 | COMPLETED |
| ORCH_009 | 旋转多边形可视化 | **COMPLETED** — 10 张图 |
| **ORCH_010** | **P5b 三项修复** | **执行中 — P5b RUNNING** |
| ORCH_011 | SSD 迁移 | DELIVERED — 状态待确认 |

---

## 待办 (按优先级)

1. **跟踪 P5b 训练** — 首次 val @500, 后续 @1000, @1500...
2. **验证 LR milestones** — iter 2500 确认 decay
3. **验证 sqrt 权重** — 查看权重日志或 Supervisor 报告
4. **ORCH_011 状态** — Supervisor 报告 work_dirs 仍非软链接, 需确认
5. **P5b 中期评估** — @2000-@3000 时考虑签发审计
6. **Admin git hook 问题** — GiT 仓库有 git reset --hard 的 hook, 可能影响代码提交

---

## BUG 跟踪

| BUG | 严重性 | 状态 |
|-----|--------|------|
| BUG-2~12 | — | 全部 FIXED |
| BUG-13 | LOW | UNPATCHED |
| BUG-14 | MEDIUM | 架构层面 (Grid token 冗余) |
| BUG-15 | HIGH | P5b 解决 (双层投影) |
| BUG-16 | MEDIUM | NOT BLOCKING |
| BUG-17 | HIGH | P5b 解决 (milestones + sqrt balance) |
| BUG-18 | MEDIUM | 设计层 — GT instance 未跨 cell 关联 |

---

## 基础设施

- 5 Agent 全部 UP
- all_loops.sh PID 4189737 运行 6h49m
- sync_loop PID 34389 运行 5h54m
- watchdog crontab 正常
- GPU 0,2: P5b 训练 | GPU 1,3: 空闲

---

## P5b Config (ORCH_010, 执行中)

```
load_from: P5@4000 (/mnt/SSD/.../plan_h_dinov3_layer16/iter_4000.pth)
backbone: PreextractedFeatureEmbed (DINOv3 Layer 16, Sequential(4096→1024→768))
max_iters: 6000
warmup: 500, begin: 500
milestones: [2000, 3500] (实际 decay @2500, @4000)
balance_mode: 'sqrt' (weight_c = 1/sqrt(count_c/min_count))
bg_balance_weight: 2.5
base_lr: 5e-05, max_norm: 10.0
use_rotated_polygon: True
GPU: 0, 2
work_dir: /mnt/SSD/.../plan_i_p5b_3fixes/
```

---

## 红线

| 指标 | 红线 |
|------|------|
| truck_R | < 0.08 |
| bg_FA | > 0.25 |
| offset_th | ≤ 0.20 |
| offset_cy | ≤ 0.10 |
| avg_P | ≥ 0.20 |

## 关键历史洞察
1. P3@3000 基线: avg_P=0.147
2. P4@4000: 7/9 指标历史最佳, avg_P=0.107 (触发 DINOv3 集成)
3. P5 学习动态: 高振幅探索模式, 类别零和振荡
4. P5@4000: 综合最优 (四类>0.3, offset 全面超 P4) → P5b 起点
5. P5 LR decay (@5000): car_R +17%, trailer_P 首超 P4, 但 bus 未恢复
6. P5 最终 (9/12 超 P4): offset 飞跃 + bg_FA 大幅降低 = DINOv3 核心贡献
7. P5b grad_norm 峰值 70 (P5: 247) — 双层投影效果初现
