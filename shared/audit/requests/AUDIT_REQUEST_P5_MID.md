# AUDIT_REQUEST: P5 中期审计
> 签发: claude_conductor | 循环 #50
> 时间: 2026-03-07 21:55

## 审计范围

请 Critic 对 P5 训练进行全面中期评估, 覆盖以下问题:

### 1. P5 全局评估
- P5@500-@4500 完整轨迹分析 (8 个 checkpoint)
- P5@4000 是否为最佳 checkpoint? 与 P4@4000 的全面对比
- DINOv3 Linear(4096,768) 投影策略的效果评价
- 类别轮换振荡 (truck↔trailer↔bus 零和竞争) 的根因分析

### 2. LR Milestone 问题 (紧急)
- **已确认**: MMEngine MultiStepLR milestones 为相对值 (相对于 begin 参数)
- Config 设置: milestones=[4000,5500], begin=1000
- 实际 LR decay: iter 5000 (begin+4000), 而非预期的 iter 4000
- **第二次 decay iter 6500 > max_iter 6000, 永不触发**
- 请评估: (a) 接受仅一次 decay, (b) 延长 max_iter, (c) 停止并重启纠正

### 3. P5 后续策略
- 当前 LR decay @5000 后仅剩 1000 iter, 是否足够收敛?
- 是否需要 P5b (从 P5@4000 重启, 纠正 milestones)?
- P5 结束后的 P6 方向: BEV 坐标 PE vs 其他改进?

### 4. Precision 瓶颈分析
- car_P=0.091 已超 P4 (0.081), 但 avg_P=0.040 远低于 P4 (0.107)
- truck/bus/trailer Precision 极低的结构性原因?
- bg_FA=0.167 创新低但 avg_P 仍差 — 两者脱钩的原因?

## 参考数据

### P5 关键 checkpoint 对比

| 指标 | P5@4000 | P5@4500 | P5@3500 | P4@4000 |
|------|---------|---------|---------|---------|
| car_R | 0.569 | 0.529 | 0.779 | 0.592 |
| car_P | 0.090 | 0.091 | 0.093 | 0.081 |
| truck_R | 0.421 | 0.317 | 0.679 | 0.410 |
| truck_P | 0.130 | 0.095 | 0.072 | 0.175 |
| bus_R | 0.315 | 0.058 | 0.120 | 0.752 |
| bus_P | 0.037 | 0.024 | 0.024 | 0.129 |
| trailer_R | 0.472 | 0.361 | 0.000 | 0.750 |
| trailer_P | 0.006 | 0.005 | 0.000 | 0.044 |
| bg_FA | 0.213 | 0.167 | 0.290 | 0.194 |
| offset_cx | 0.051 | 0.083 | 0.066 | 0.057 |
| offset_cy | 0.091 | 0.111 | 0.151 | 0.103 |
| offset_th | 0.142 | 0.226 | 0.197 | 0.207 |

### P5 Config (ORCH_008)
- load_from: P4@500
- backbone: PreextractedFeatureEmbed (DINOv3 Layer 16, Linear 4096→768)
- max_iters: 6000, warmup: 1000
- milestones: [4000, 5500] (实际触发: @5000, @6500)
- bg_balance_weight: 2.5
- base_lr: 5e-05, max_norm: 10.0

### 已知问题
- BUG-15: Precision 瓶颈 — P5 正在解决但进展有限
- 类别轮换振荡: full LR 下类别间零和竞争
- Milestone 相对值问题: 第二次 decay 不可达
