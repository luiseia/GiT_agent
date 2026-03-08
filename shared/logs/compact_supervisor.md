# Supervisor Compact Context Snapshot
> Timestamp: 2026-03-08 00:15
> Supervisor cycles: #89 — #135 (本轮 session 覆盖 #129-#135)
> Role: claude_supervisor — 信息中枢
> Reason: 用户请求保存工作上下文

---

## 当前任务

**角色**: claude_supervisor, 每 30 分钟执行自主监控循环
**循环**: git pull 两仓库 → 读训练日志 → 写 supervisor_report_latest.md → 检查 ORCH → 深度监控 → git push
**写入边界**: 只可写 `shared/logs/supervisor_*`, `shared/pending/` status 字段; GiT/ 只读

---

## 正在进行: P5b 训练 (plan_i_p5b_3fixes)

### 基本信息
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/`
- **Train log**: 同目录 `train.log`
- **Load from**: P5@4000 (`/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_h_dinov3_layer16/iter_4000.pth`)
- **GPU**: 0 + 2 (~20.5+21.0 GB, 100%)
- **启动**: 2026-03-07 23:56, **max_iters**: 6000, **val_interval**: 500
- **进度 (Cycle #135)**: iter 330/6000 (5.5%), warmup 阶段
- **ETA**: ~05:00

### P5b 三项修复 (ORCH_010)
1. **LR milestones 修正**: warmup=500, begin=500, milestones=[2000,3500] → decay @2500 和 @4000
2. **sqrt 类别权重**: balance_mode='sqrt', 压缩 car:trailer 权重比从 92:1 → 9.6:1
3. **双层投影**: Linear(4096,768) → Sequential(Linear(4096,1024), GELU, Linear(1024,768))

### LR 调度
- base_lr=5e-05, warmup_ratio=0.05 → 实际 lr≈2.5e-06 (warmup 结束后)
- 第一次 decay: iter **2500** (begin500 + milestone2000) → lr=2.5e-07
- 第二次 decay: iter **4000** (begin500 + milestone3500) → lr=2.5e-08

### P5b 关键验证点
- [ ] @500 首次 val: warmup 结束, 初始状态
- [ ] @2500 LR decay: 确认 lr 变化
- [ ] @4000 第二次 decay: 确认 lr 再降
- [ ] 类别振荡是否缓解 (sqrt 权重)
- [ ] bus_R 是否恢复

---

## P5 已完成 — 参考基线

### P5 最优 Checkpoint
1. **P5@4000**: 类别全平衡(4类>0.3), offset_th=0.142, cy=0.091, cx=0.051, bg_FA=0.213
2. **P5@5500**: car_R=0.721, car_P=0.092, trailer_P=0.046(超P4), bg_FA=0.186
3. **P5@6000**: trailer_R=0.500, truck_R=0.228(止跌), offset_th=0.192

### P5 Val 轨迹 (关键指标)
| Ckpt | car_R | car_P | truck_R | truck_P | bus_R | trailer_R | trailer_P | bg_FA | off_th |
|------|-------|-------|---------|---------|-------|-----------|-----------|-------|--------|
| @1500 | 0.955 | 0.057 | 0.418 | 0.037 | 0 | 0 | 0 | 0.442 | 0.201 |
| @2500 | 0.793 | 0.073 | 0.080 | 0.030 | 0.409 | 0.528 | 0.004 | 0.321 | 0.215 |
| @3500 | 0.779 | 0.093 | 0.679 | 0.072 | 0.120 | 0 | 0 | 0.290 | 0.197 |
| **@4000** | 0.569 | 0.090 | 0.421 | 0.130 | 0.315 | 0.472 | 0.006 | 0.213 | **0.142** |
| @5000 | 0.615 | 0.085 | 0.199 | 0.086 | 0.002 | 0.333 | 0.033 | 0.160 | 0.163 |
| @5500 | 0.721 | 0.092 | 0.203 | 0.065 | 0.014 | 0.417 | 0.046 | 0.186 | 0.182 |
| @6000 | 0.682 | 0.089 | 0.228 | 0.065 | 0.011 | 0.500 | 0.043 | 0.190 | 0.192 |

### P5 关键发现
- **LR milestone 配置错误 (BUG-17)**: milestones 相对于 begin, 实际 decay 延迟 1000 iter (@5000而非@4000)
- **类别零和振荡**: full LR 下类别间竞争严重, 一类强则另一类塌
- **DINOv3 Layer16 优势**: offset 精度飞跃 (th: P4的0.207→P5的0.142), bg_FA 大幅下降
- **P5 在 9/12 指标上取得超 P4 的最优值**

### P4@4000 基线
| car_R | car_P | truck_R | truck_P | bus_R | bus_P | trailer_R | trailer_P | bg_FA | off_cx | off_cy | off_th |
|-------|-------|---------|---------|-------|-------|-----------|-----------|-------|--------|--------|--------|
| 0.592 | 0.081 | 0.410 | 0.175 | 0.752 | 0.129 | 0.750 | 0.044 | 0.194 | 0.057 | 0.103 | 0.207 |

---

## 红线指标
| 指标 | 红线 | P5 最优 | 说明 |
|------|------|---------|------|
| truck_R | ≥0.08 | 0.679 (@3500) | DINOv3 语义特征效果 |
| bg_FA | ≤0.25 | 0.160 (@5000) | 累计下降 64% |
| offset_th | ≤0.20 | 0.142 (@4000) | P5 最大优势 |
| offset_cx | ≤0.05 | 0.051 (@4000) | 接近达标 |
| offset_cy | ≤0.10 | 0.091 (@4000) | 达标 |

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-008 | COMPLETED | P1-P5 历史 |
| ORCH_009 | **COMPLETED** | 旋转多边形可视化, 10 张图 `/mnt/SSD/GiT_Yihao/polygon_viz/` |
| ORCH_010 | **执行中** | P5b 三修复, 训练已启动 |
| ORCH_011 | DELIVERED | SSD 迁移 work_dirs — 未见软链接, 状态不明 |

---

## 关键路径
| 用途 | 路径 |
|------|------|
| 调度仓库 | `/home/UNT/yz0370/projects/GiT_agent/` (读写) |
| 研究代码 | `/home/UNT/yz0370/projects/GiT/` (只读) |
| P5b train log | `/mnt/SSD/GiT_Yihao/Train/Train_20260307/plan_i_p5b_3fixes/train.log` |
| DINOv3 特征 | `/mnt/SSD/GiT_Yihao/dinov3_features/` |
| 报告输出 | `shared/logs/supervisor_report_latest.md` |
| 报告历史 | `shared/logs/supervisor_report_history.md` (~3000行) |

---

## 恢复指南
1. 读 `agents/claude_supervisor/CLAUDE.md` 确认角色
2. `git pull` 两仓库
3. 读 P5b train log 尾部 — 检查当前 iter 和最新 val
4. 检查 ORCH_010/011 状态变化
5. 写 supervisor_report_latest.md
6. git push
7. 继续 30 分钟循环
