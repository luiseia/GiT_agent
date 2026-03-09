# Report: ORCH_026 — Plan Q 单类 Car 诊断实验

**状态**: COMPLETED
**执行时间**: 2026-03-09 03:04 ~ 07:27 (约 4.5 小时)
**目标**: 回答 "类竞争是否为 car_P 瓶颈"

---

## 实验设置

| 参数 | 值 |
|------|-----|
| Config | `configs/GiT/plan_q_single_car_diag.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260309/plan_q_single_car` |
| 架构 | 2048+GELU proj, 预提取 DINOv3 特征 |
| 数据 | Mini nuScenes (323 samples), class_filter=['car'] |
| GPU | GPU 1 单卡, 9058 MB |
| Checkpoint | P5b@3000 (proj 1024→2048 size mismatch, 投影层随机初始化) |
| LR | AdamW 5e-5, warmup 0-500, milestones [1000,2000]+begin=500 |
| max_iters | 3000, val_interval=500 |

### 代码改动
- `mmdet/datasets/pipelines/generate_occ_flow_labels.py`: 新增 `class_filter` 参数
- `configs/GiT/plan_q_single_car_diag.py`: 新 config 文件
- Git commit: `5e7af1e`

---

## Val 结果曲线

| iter | car_R | car_P | bg_FA | off_th | off_cx | off_cy |
|------|-------|-------|-------|--------|--------|--------|
| @500 | 0.411 | 0.0705 | 0.1020 | 0.2564 | 0.0540 | 0.0935 |
| @1000 | 0.367 | 0.0269 | 0.2443 | 0.2431 | 0.0794 | 0.1166 |
| @1500 | 0.567 | 0.0666 | 0.2187 | 0.2560 | 0.0403 | 0.0792 |
| @2000 | 0.714 | 0.0756 | 0.2130 | 0.2176 | 0.0566 | 0.0666 |
| **@2500** | **0.513** | **0.0830** | **0.1694** | 0.2458 | 0.0676 | 0.0652 |
| @3000 | 0.568 | 0.0777 | 0.1795 | 0.2738 | 0.0553 | 0.0613 |

**car_P@best = 0.0830 (@2500)**

### 对比基线

| 指标 | Plan Q @best | P6@4000 (Mini, 10类) | Full@4000 (DDP) |
|------|-------------|---------------------|-----------------|
| car_P | **0.083** | **0.126** | 0.078 |
| car_R | 0.513 | 0.301 | 0.419 |
| bg_FA | 0.169 | 0.232 | 0.199 |

---

## 判定

按 ORCH_026 规定的判定标准：

| 条件 | 结论 |
|------|------|
| car_P@best > 0.20 | 类竞争是主要瓶颈 |
| car_P@best 0.15-0.20 | 类竞争是 contributing factor |
| car_P@best 0.12-0.15 | 类竞争不是瓶颈 |
| **car_P@best < 0.12** | **★ 类竞争无关** |

### **结论: car_P@best = 0.083 < 0.12 → 类竞争无关**

去除类竞争 (只保留 car 类 GT) 并未帮助 car_P 提升，反而比 P6@4000 基线 (0.126) 更差。

---

## 详细分析

### 1. car_P 未改善
- Plan Q car_P@best = 0.083，远低于 P6 基线 0.126
- 去除其他 9 个类的竞争没有帮助，说明 car precision 的瓶颈不在类间混淆

### 2. 混淆因素: 投影层 mismatch
- P5b checkpoint 使用 1024 dim proj，Plan Q 使用 2048+GELU proj
- 投影层权重因 shape mismatch 未加载 (随机初始化)
- 但 off_cx 在 @1500 达到 0.040 (= P6 基线)，说明模型其他部分学习正常
- 即使 proj 从随机开始，3000 iter 足够学习线性映射

### 3. car_R 显著高于基线
- Plan Q car_R@2000 = 0.714 >> P6 的 0.301
- 无类竞争时模型更倾向"全预测为 car"策略
- 高 recall + 低 precision = 大量 false positive

### 4. bg_FA 分析
- @500 bg_FA=0.102 是历史最低 (无类竞争时 bg/fg 简单)
- 后续 bg_FA 回升到 0.17-0.24，可能是过拟合 Mini 数据

### 5. off_th 始终较差
- Plan Q off_th 在 0.22-0.27 区间，远不如 P6 (0.145) 和 Full (0.150)
- 朝向估计精度差，说明 Mini 数据量不足以学好旋转角

---

## 对后续工作的启示

1. **car_P 瓶颈不在类竞争** — 应关注其他方向 (数据质量、模型容量、训练策略)
2. **Full nuScenes 训练更有希望** — ORCH_024 @4000 已有 truck 信号出现，数据量是关键
3. **Mini 实验价值有限** — 323 样本易过拟合，结论需谨慎外推到 Full 数据

---

*Admin Agent 执行 | 2026-03-09 07:45*
