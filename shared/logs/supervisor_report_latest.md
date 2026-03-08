# Supervisor 摘要报告
> 时间: 2026-03-08 07:32
> Cycle: #148

## ===== 四个诊断实验全 GPU 满载! Plan K/L @500 val + Plan M/N 启动 (ORCH_016) =====

---

### 实验总览 — 4 GPU 满载

| 实验 | Config | 目的 | GPU | 进度 | 速度 | 显存 |
|------|--------|------|-----|------|------|------|
| **Plan K (α)** | 单类 car, 预提取 | 类竞争诊断 | 0 | 780/2000 | 2.97s | 15.2 GB |
| **Plan L (β)** | 10类(!), 宽投影 2048 | 投影容量诊断 | 2 | 750/2000 | 2.98s | 15.4 GB |
| **Plan M (γ)** | 单类 car, 在线 unfreeze | DINOv3 微调效果 | 1 | 70/2000 | 6.26s | 29.5 GB |
| **Plan N (δ)** | 单类 car, 在线 frozen | 在线 vs 离线基线 | 3 | 70/2000 | 6.26s | 28.0 GB |

> Plan M/N 速度 ~2x 慢于 K/L (在线 DINOv3 提取), 显存 ~2x 高

### Plan K @500 Val (单类 car)

| 指标 | Plan K @500 | P5b @500 | 对比 |
|------|------------|----------|------|
| car_R | 0.629 | 0.856 | K 更低 (单类重建中) |
| car_P | 0.064 | 0.080 | K 更低 |
| bg_FA | **0.183** | 0.235 | **K 大幅领先!** |
| off_cx | 0.073 | 0.068 | 相近 |
| off_cy | **0.082** | **0.085** | K 微优 |
| off_th | 0.228 | 0.210 | K 更差 |

> Plan K @500 仅 500 iter 从 P5b@3000 重建, 类别指标暂时下降可理解。bg_FA=0.183 显著低于 P5b 同期, 单类确实减少了误检。**关键判断需等 @1000**。

### Plan L @500 Val (10 类, 宽投影)

⚠️ **注意**: Plan L 实际使用了 **10 类** (非 ORCH_015 指定的 4 类), 包含 pedestrian, bicycle 等新类。

| 指标 | Plan L @500 | P5b @500 | 备注 |
|------|------------|----------|------|
| car_R | 0.084 | 0.856 | 极低 (投影层随机初始化) |
| pedestrian_R | **0.451** | — | 新类, 高 recall |
| construction_vehicle_R | 0.088 | — | 新类 |
| bg_FA | 0.237 | 0.235 | 相近 |
| off_th | 0.277 | 0.210 | 差 |

> Plan L 投影层从随机初始化 (shape 不匹配), 500 iter 远不够恢复。car_R=0.084 说明投影层需要更多训练时间。pedestrian_R=0.451 是意外发现 — 行人检测出奇地好。

### Plan M/N (在线 DINOv3) — 刚启动

- iter ~70/2000, warmup 阶段
- **Plan M** (unfreeze): memory 29.5 GB, loss ~2.0
- **Plan N** (frozen): memory 28.0 GB, loss ~2.0
- **速度**: 6.26s/iter (~2x 于 K/L 的 2.97s)
- **首次 val**: @500, 预计 ~08:00

### 在线 DINOv3 显存对比

| 模式 | 显存 | 差异 |
|------|------|------|
| 预提取 (Plan K) | 15.2 GB | 基线 |
| 在线 frozen (Plan N) | 28.0 GB | +12.8 GB |
| 在线 unfreeze (Plan M) | 29.5 GB | +14.3 GB |

在线模式显存增加 ~13-14 GB, 单卡 A6000 (49 GB) 仍充足。但 DDP 双卡训练可能受限。

---

### P5b 训练 — 已完成 ✅ (上轮确认)

最终指标: bg_FA=**0.208**, off_th=**0.198**, 红线 3/5。

---

## ORCH 指令状态

| 指令 | 状态 | 内容 |
|------|------|------|
| ORCH_001-013 | COMPLETED | P1-P5b + BUG-19 |
| ORCH_014 | COMPLETED | P6 准备 + DINOv3 BLOCKER 报告 |
| **ORCH_015** | **IN_PROGRESS** | Plan K (α) + Plan L (β), GPU 0+2 |
| **ORCH_016** | **IN_PROGRESS** | Plan M (γ) + Plan N (δ), GPU 1+3 |

## GPU 状态
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 22.0 GB | 100% | **Plan K** (780/2000) |
| 1 | 37.1 GB | 94% | **Plan M** (70/2000) |
| 2 | 20.4 GB | 100% | **Plan L** (750/2000) |
| 3 | 33.5 GB | 100% | **Plan N** (70/2000) |

## 告警
1. **[ACTIVE] 4 GPU 满载**: 全部诊断实验并行运行
2. **[DEVIATION] Plan L 用 10 类**: ORCH_015 指定 4 类, 实际用了 10 类 (Admin 决策?)
3. **[WATCH] Plan L car_R=0.084**: 投影层随机初始化, 需更多 iter 恢复
4. **[INTERESTING] Plan K bg_FA=0.183 @500**: 单类确实减少误检
5. **[INTERESTING] Plan L pedestrian_R=0.451 @500**: 行人检测出奇地好
6. **[NEW] ORCH_016 在线 DINOv3**: CEO 选择在线路线, 绕过 2.1TB 存储问题
7. **[NEXT VAL] Plan K/L @1000 (~07:50), Plan M/N @500 (~08:00)**
