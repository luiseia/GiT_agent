# Conductor 完整工作上下文 — Shutdown 存档
> 时间: 2026-03-15 19:55
> 原因: Session 结束前完整状态保存

---

## 1. MASTER_PLAN 当前状态

### 当前阶段: ORCH_046_v2 训练中 (@500 val 运行中)

**最新决策 (2026-03-15 17:15~19:55):**
- Critic VERDICT_ORCH046_PLAN 发现 **BUG-69 (CRITICAL)**: adaptation layers lr_mult=0.05, 25.2M 参数实际冻结
- Critic 自我纠正: VERDICT_ORCH045_AT2000 中"零数据增强"结论错误 — PhotoMetricDistortion 一直在 config 中
- 根因修正: ORCH_045 崩塌首因是 BUG-69 (adapt 冻结) + BUG-62 (clip_grad=10), 不是"零数据增强"
- CEO 指令: BEV 空间增强必须做 (ORCH_024 证明没 BUG-69 也会 frozen)
- CEO 指令: val@500 快速反馈, 用 bert_embed_large.pt 预训练权重
- CEO 决策: 从零训练 (不从 045_6k resume, Conductor 建议被采纳)

### 修正后优先级 (Critic 审计通过)

| 优先级 | 修复项 | 状态 |
|--------|--------|------|
| **P0** | BUG-69: adapt lr_mult → 1.0 | ✅ ORCH_046 已修复 |
| **P0** | BUG-62: clip_grad → 50.0 | ✅ ORCH_046 已修复 |
| **P0** | BUG-64: bert-large + 预训练 | ✅ ORCH_046 已修复 |
| **P0** | BEV RandomFlipBEV (空间增强) | ❌ 未实现 — CEO 要求必须做 |
| P1 | BUG-45: 推理 causal attn_mask | ❌ 未实现 |
| P1 | Scheduled Sampling | ❌ 未实现 |
| P2 | GlobalRotScaleTrans (BEV 旋转缩放) | 推迟 |

---

## 2. CEO 指令

CEO_CMD.md 当前为空, 无待执行指令。

### CEO 本 session 中的关键指令/反馈:
1. "希望修改批评家的职责扩大它的权限" → 已完成: Critic 获得紧急停止权
2. "你只能做自动驾驶常用的数据增强" → RandomFlip3D + GlobalRotScaleTrans 是标准做法
3. "我要求立刻就做BEV空间增强" → 已加入 ORCH_046 但 Admin 未执行
4. "500iter太慢了" → val_interval 改为 500
5. "你为什么不用bert_embed_large.pt权重" → 已修复, 权重在 `/home/UNT/yz0370/projects/GiT/bert_embed_large.pt`
6. "为什么不是500就可视化评价" → 发现 Admin 未改 val_interval, 停训重启
7. "把旧可视化都删了重新做" → 已完成, 新可视化在 shared/logs/VIS/
8. "save_tmux 移到循环最后" → 已修改 all_loops.sh
9. CEO 观察到早期 (iter 2000/4000) 只预测大 box → loss 贡献不平衡问题

---

## 3. 所有任务进度

### ORCH_046_v2 (当前活跃)
- **状态**: 🔄 RUNNING — @500 val 运行中 (20/1505, ~21:43 完成)
- **PID**: 1965006 (launcher), GPU 0,2
- **work_dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch046_v2`
- **日志**: `.../nohup_orch046_v2.out`
- **Config**: `configs/GiT/plan_full_nuscenes_large_v1.py`
- **修复内容**: BUG-69 (adapt lr_mult=1.0) + BUG-62 (clip_grad=50) + BUG-64 (bert-large pretrain) + val@500
- **未实现**: RandomFlipBEV, BUG-45 attn_mask, Scheduled Sampling
- **训练观察 (iter 0-500)**:
  - loss: 15→5-8 (vs ORCH_045 160-290 — 大幅改善)
  - grad_norm: 50-340 (vs ORCH_045 3000-6700 — 一个数量级差异)
  - reg_loss: 2.1-3.4 稳定, 无 reg_loss=0 事件
  - BERT-large 预训练 + BUG-69 修复效果显著

### ORCH_046_v1 (已停止)
- 只修了 BUG-69 + BUG-62, 没改 bert-large 和 val@500
- 跑到 iter ~330 被 kill (为了做可视化 + 改 config 重启)

### ORCH_045 (已终止)
- @6000 STOP — bg_FA=1.0 marker saturation + frozen predictions
- 根因: BUG-69 (adapt 冻结) + BUG-62 (clip_grad=10)
- Checkpoints 保留: iter_2000/4000/6000.pth

### ORCH_044 (已停止)
- iter 440 collapse, 无 anti-collapse 前提错误

### ORCH_043 (已完成)
- P2+P3 @6000 car_R=0.582 — 后确认为 frozen predictions 假象

### ORCH_024 (基线, 已终止)
- @8000 最优: car_R=0.718, 5 offset 全面领先
- 权重: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/iter_8000.pth`
- 唯一成功的实验

### ORCH_035 (已终止)
- @12000 peak: car_R=0.62, car_P=0.100
- @14000 崩溃: car_R=0 mode collapse

---

## 4. 待签发的 ORCH 和 AUDIT

### 待签发 ORCH
- **ORCH_047** (待 @500 eval 后决定): 如果 ORCH_046_v2 非 frozen → 加入 RandomFlipBEV + BUG-45 + Scheduled Sampling
- 如果 ORCH_046_v2 仍 frozen → 需要重新评估整体方向

### 待签发 AUDIT
- 当前无待签发审计请求
- @500 eval 后如需诊断 → 签发 AUDIT_REQUEST 给 Critic

### 已签发未处理
- `shared/audit/requests/` 当前应为空 (上一轮已归档)

---

## 5. 所有未完成待办

### P0 (必须做)
1. **@500 eval 读取** (~21:43) — 判定 PROCEED 或 STOP
2. **RandomFlipBEV 实现** — CEO 已要求立刻做, 但 Admin 未执行. 需要在下次 ORCH 中强制执行
3. **BUG-45 修复** — 推理 attn_mask 不一致

### P1 (高优先级)
4. **@500 后 check_frozen_predictions.py 诊断** — 确认预测多样性
5. **@500 后 BEV 可视化** → VIS/ 目录
6. **Scheduled Sampling 实现** — 替代 token_drop_rate

### P2 (中优先级)
7. **GlobalRotScaleTrans** — BEV 旋转+缩放增强
8. **loss 贡献不平衡** — 大 box 占据更多 cell, 小目标 loss 信号弱 (CEO 观察到的问题)
9. **score_thr 消融** — 代码已就绪 (`9974e3a`), 需要 GPU 空闲时执行

### P3 (长期)
10. Deep Supervision `loss_out_indices=[8,10,11]`
11. BEV 坐标 Positional Encoding
12. 历史帧时序信息 (CEO 最看好方向)
13. Instance Grouping

---

## 6. Critic VERDICT 摘要

### VERDICT_ORCH046_PLAN (2026-03-15 17:15) — 最新
- **结论**: CONDITIONAL — 方案有重大遗漏, 修正后可执行
- **关键发现**:
  1. **BUG-69 (CRITICAL NEW)**: adaptation layers lr_mult=0.05, mmengine substring match 导致 25.2M 参数冻结
  2. **BUG-70 (自我纠正)**: 之前 VERDICT 错误声明"零数据增强", 实际 PhotoMetricDistortion 一直在
  3. clip_grad 建议 50.0 (比 Conductor 提的 35 更高)
  4. bert_embed 可行, 代码已支持 bert-large + pretrain_path
  5. 初始化不是问题, lr_mult 才是首因
- **修正后根因排序**: BUG-69 > BUG-62 > 缺乏空间增强 > teacher forcing
- **建议**: 分步验证 — 先修 config, 验证后再加增强 (但 CEO 要求全部一起做)

### VERDICT_ORCH045_AT2000 (2026-03-15 16:55) — 上一份
- **结论**: STOP
- **关键发现**: 确认 frozen predictions (IoU=0.99, identical=99.5%)
- **BUG-62 回归**: clip_grad=10 在 ORCH_045 未修复
- **BUG-66**: token_drop_rate=0.3 无效
- **BUG-67**: adapt layers 初始化 + clip_grad 交互
- **BUG-68**: 流程失误, 签发前未检查 CRITICAL bugs

---

## 7. CEO DINOv3 论文分析发现

### 多层特征拼接
- 论文 4/4 下游任务都用 **[10,20,30,40] 四层拼接** (16384维)
- Layer 16 在几何任务上远未达峰 (Layer 30-35 最优)
- ORCH_034 验证: car_R 0→0.81, 4 个新类别激活
- 当前使用: ViT-L [5,11,17,23] 四层均匀采样 (4×1024=4096)

### VGGT 论文要点 (D.12)
1. 图像分辨率 518→592 (适配 patch_size=16)
2. 学习率 0.0002→0.0001 (更保守, 防漂移)
3. **4 层中间层拼接** (DINOv3 有收益, DINOv2 无收益)
4. 即使不调参, 仅替换 backbone 也超越原 VGGT

### 3D Detection 标准做法 (本 session 发现)
- **clip_grad=35.0** 是 PointPillars/SECOND 标准
- **RandomFlip3D (prob=0.5)** + **GlobalRotScaleTrans (±22.5°, scale 0.95-1.05)** 是 BEV 标准增强
- Detection 2D 对 backbone 用 lr_mult=0.1 逐层递增 — 启发了 adapt layers 的 lr 控制

---

## 8. 可视化状态

### shared/logs/VIS/ 目录 (新做的, 推理方式正确)
| 目录 | 权重 | 推理方式 | 结果摘要 |
|------|------|---------|---------|
| 024_8k_old_inference | ORCH_024 @8000 | 旧 (无 P2+P3) ✅ | 387 dets/sample, 有 TP |
| 035_12k_old_inference | ORCH_035 @12000 | 旧 (无 P2+P3) ✅ | 357-370 dets/sample |
| 045_2k_new_inference | ORCH_045 @2000 | 新 (P2+P3) ✅ | 1095-1107 dets, saturation 开始 |
| 045_6k_new_inference | ORCH_045 @6000 | 新 (P2+P3) ✅ | 1200/1200 全正, 完全 saturation |

---

## 9. Agent 状态

| Agent | 状态 |
|-------|------|
| conductor | 当前 session, 即将关闭 |
| supervisor | 快照过期 (03/13), 仍在监控 ORCH_035 |
| critic | 已恢复 (usage_watchdog 修复后), 最近活跃 17:15 |
| admin | 执行了 ORCH_046 部分修改 (lr_mult+clip_grad), 未执行 RandomFlip/bert-large/val@500 |
| ops | 正常运行, save_tmux 已移到循环末尾 |

---

## 10. 关键文件索引

| 用途 | 路径 |
|------|------|
| MASTER_PLAN | `MASTER_PLAN.md` |
| 本存档 | `shared/logs/shutdown_conductor.md` |
| Conductor 快照 | `shared/logs/compact_conductor.md` |
| 状态归档 | `shared/logs/conductor_state_archive_20260315.md` |
| VIS 可视化 | `shared/logs/VIS/` |
| ORCH_046 指令 | `shared/pending/ORCH_0315_1745_046.md` |
| 最新 VERDICT | `shared/audit/processed/VERDICT_ORCH046_PLAN.md` |
| 训练 Config | `GiT/configs/GiT/plan_full_nuscenes_large_v1.py` |
| ORCH_046_v2 work_dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch046_v2` |
| ORCH_046_v2 日志 | `.../nohup_orch046_v2.out` |
| BERT-large 权重 | `/home/UNT/yz0370/projects/GiT/bert_embed_large.pt` |
| ORCH_024 @8k 权重 | `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/iter_8000.pth` |

---

## 11. 本 session 修改的基础设施

1. `scripts/usage_watchdog.sh`: USAGE_TARGET 从 agent-critic 改为 agent-ops (修复 Critic 卡死)
2. `agents/claude_critic/CLAUDE.md`: 新增紧急停止权 (CEO 授权)
3. `scripts/all_loops.sh`: save_tmux 从步骤 4 移到步骤 9 (循环最后)

---

## 12. 恢复指令

1. 读取本文件 + `shared/logs/compact_conductor.md`
2. `ps aux | grep train.py | grep yz0370` — 确认 ORCH_046_v2 训练存活
3. `strings .../nohup_orch046_v2.out | grep "Iter(val) \[1505" | tail -1` — 检查 @500 eval 是否完成
4. 如果 @500 eval 已完成 → 读取结果, 判定 PROCEED 或 STOP
5. 检查 `CEO_CMD.md`
6. **下一步关键行动**: 读 @500 eval → 如果非 frozen → 签发 ORCH_047 (加 RandomFlipBEV + BUG-45)
7. 恢复 Phase 1/Phase 2 循环

---

*存档完成 | 2026-03-15 19:55 | claude_conductor*
