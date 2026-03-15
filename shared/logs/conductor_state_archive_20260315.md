# Conductor 完整状态归档
> 时间: 2026-03-15 04:05
> 归档原因: Session 结束前完整状态保存

---

## 1. 当前研究进度

### 项目概述
- **目标**: 基于 GiT (Generative Image-to-Text) 架构在 nuScenes 数据集上进行 BEV (Bird's Eye View) occupancy prediction
- **视觉特征**: DINOv3 ViT-L (frozen) 提取，多层拼接后投影为 GiT backbone 输入
- **训练数据**: Full nuScenes (28130 train, 6019 val)
- **硬件**: 2×A6000 (GPU 0,2), ~29 GB/GPU (GPU 1,3 被 yl0826 PETR 训练占用)

### 实验演进时间线

| 阶段 | 实验 | 时间 | 结果 | 关键发现 |
|------|------|------|------|---------|
| 1 | ORCH_024: 单层L16 + center-based 标签 | 03/06~03/09 | @8000 最优: car_R=0.718, off_th=0.140 | baseline, 但 mode collapse 逐步恶化 |
| 2 | ORCH_029: overlap 标签修复 | 03/11 | @2000: bg_FA -27%, off_th -17% | 标签改进确认有效 |
| 3 | ORCH_034: 多层特征 [L9,19,29,39] | 03/12 | @2000: car_R=0.8124 | 多层方向正确 |
| 4 | ORCH_035: Label Pipeline 大修 | 03/12~03/13 | @12000 peak: car_R=0.62, car_P=0.100 | @14000 car_R=0 mode collapse 崩溃 |
| 5 | GiT-Large v1 训练 | 03/14 | @6000: off_th=0.094 历史最佳 | 但 frozen predictions 仍存在 |
| 6 | ORCH_043: P2+P3 修复 | 03/14~03/15 | @6000: car_R=0.582 | P2+P3 确认有效但不充分 |
| 7 | ORCH_044: 多层 ViT-L + 投影 | 03/15 01:53 | ❌ 已停止 @iter_440 | 前提错误, reg_loss=0.0 mode collapse |
| **8** | **ORCH_045: 多层+适应层+token corruption** | **03/15 03:20** | **🔄 运行中 iter_640/40000** | **从零训练, anti-mode-collapse** |

### ORCH_045 当前训练详情 (最新实验)

| 项目 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_large_v1.py` (commit `26b6f92`) |
| 架构 | GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen |
| 特征提取 | **多层 [5,11,17,23]** → 4×1024=4096 → 投影 2048 → GELU → 1024 |
| 适应层 | **2 层 PreLN TransformerEncoderLayer** (25.2M 参数, trainable, nhead=16) |
| Anti-collapse | **token_drop_rate=0.3** — 30% GT 输入替换为随机 token |
| 权重 | 从零训练 (load_from=None, SAM pretrained via init_cfg) |
| PID | 1686388 (实际为多进程: 1686317 rank0, 1686318 rank1) |
| GPU | 0,2 (2×A6000), ~29 GB/GPU |
| Batch | batch_size=1/GPU × 2 GPU × accumulative_counts=8 = effective 16 |
| 速度 | ~3.79 sec/iter |
| ETA | ~1 天 17 小时 (~03/16 21:30) |
| 进度 | iter_640/40000 |
| Loss 趋势 | 初始 172 → 当前 ~90 (正常下降) |
| reg_loss | **3.3~3.9 波动, 未归零** — 好征兆, 没有早期 mode collapse |
| work_dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt` |
| 日志 | `/mnt/SSD/GiT_Yihao/Train/Train_20260315/nohup_multilayer_adapt.out` (二进制字符, 用 `strings` 过滤) |

### 关键代码修改 (GiT repo)

| Commit | 文件 | 改动 |
|--------|------|------|
| `05d5138` | `mmdet/models/detectors/git.py` | token corruption 实现: forward_transformer 中 input_seq 随机替换 |
| `a69b64b` | `mmdet/models/backbones/vit_git.py` | 多层 DINOv3 [5,11,17,23] + 2 层 PreLN 适应层 |
| `a69b64b` | `scripts/check_frozen_predictions.py` | mode collapse 自动诊断脚本 |
| `26b6f92` | config | batch_size=1, accumulative_counts=8 (OOM fix) |
| `d9d7f7d` | `git.py` + `git_occ_head.py` | P2 (occ position embedding) + P3 (每步图像特征注入) |
| `c416818` | config | clip_grad 回退到 10.0 |
| `4ad3b0f` | config | BUG-62/63/17 修复 |

### 检查点计划

| 检查点 | 预计时间 | 行动 |
|--------|---------|------|
| **@2000** | ~03/15 11:00 | 首次 frozen prediction 检查 (关键!) |
| @4000 | ~03/15 19:00 | 第二次检查 + 指标评估 |
| @8000 | ~03/16 05:00 | 架构决策级评估 |

### @2000 决策树

```
├─ FROZEN (IoU>0.95, saturation>0.9) → token_drop_rate 不够, 增大或换策略
├─ PARTIAL (IoU 0.5~0.95) → 有改善但不够, 考虑增大 drop_rate
├─ HEALTHY (IoU<0.5, predictions vary) → PROCEED, 等 @4000 看指标
```

### 已完成/终止的实验

| ORCH | 目标 | 状态 | 关键结果 |
|------|------|------|---------|
| ORCH_024 | 单层L16 center-based baseline | TERMINATED @12000 | @8000 最优: car_R=0.718, 5 offset 全面优于 ORCH_035 |
| ORCH_029 | overlap 标签修复 | STOPPED @2000 | bg_FA -27%, off_th -17% |
| ORCH_034 | 多层 + BUG修复 | STOPPED @4000 | car_R=0.8124, 4 新类激活 |
| ORCH_035 | Label Pipeline 大修 | TERMINATED @14000 | car_R=0 mode collapse 崩溃 |
| ORCH_041 | score_thr 消融 | DONE | thr=0.5: bg_FA-47%, car_R=0 全阈值 |
| ORCH_042 | BUG修复 + resume | COMPLETED | grad_norm 3x 提升 |
| ORCH_043 | P2+P3 修复 | COMPLETED | @6000 car_R=0.582 突破 |
| ORCH_044 | 多层投影 (无 anti-collapse) | STOPPED | reg_loss=0 mode collapse |

---

## 2. 两阶段 Conductor 设计

### 指挥架构

```
CEO (用户)
  │
  ├── CEO_CMD.md ────────────────── 直接指令 (最高优先级)
  │
  └── claude_conductor (决策中枢)
        │
        ├── Phase 1: 信息收集 + 审计决策
        │     ├── git pull
        │     ├── 读 CEO_CMD.md → 执行 → 归档到 ceo_cmd_archive.md → 清空
        │     ├── 读 supervisor_report_latest.md
        │     ├── 读 STATUS.md
        │     ├── 检查 ORCH 回执 (shared/pending/ 状态变化)
        │     ├── 读 Admin 报告 (shared/logs/report_ORCH_*.md)
        │     ├── 评估是否需要 Critic 审计
        │     └── 签发 AUDIT_REQUEST → shared/audit/requests/
        │
        ├── Phase 2: 读取判决 + 决策 + 行动
        │     ├── git pull (获取 Critic VERDICT)
        │     ├── 读 shared/audit/pending/VERDICT_*.md
        │     ├── ⚠️ 紧急停止规则 (frozen/mode collapse → 立即 kill)
        │     ├── 归档 VERDICT → shared/audit/processed/
        │     ├── 更新 MASTER_PLAN.md
        │     ├── 签发 ORCH 指令 → shared/pending/ (必须含 `- **状态**: PENDING`)
        │     └── 检查 context 剩余
        │
        └── 循环: Phase 1 → Phase 2 → Phase 1 → ...
```

### Agent 职责分工

| Agent | tmux session | 职责 | 写入权限 |
|-------|-------------|------|---------|
| **conductor** | agent-conductor | 决策中枢: 综合所有信息, 签发 ORCH, 更新 MASTER_PLAN | MASTER_PLAN.md, CEO_CMD.md, shared/audit/requests/, shared/pending/, shared/logs/compact_conductor.md |
| **supervisor** | agent-supervisor | 信息中枢: 监控训练日志, GPU/磁盘, 写 report | shared/logs/supervisor_*, shared/pending/ (仅状态字段) |
| **critic** | agent-critic | 审计: 读 AUDIT_REQUEST, 运行诊断, 写 VERDICT | shared/audit/pending/VERDICT_*.md, GiT/ssd_workspace/Debug/ |
| **admin** | agent-admin | 执行: 读 ORCH (DELIVERED), 改代码/启训练, 写 report | GiT/ 仓库 (代码修改), shared/logs/report_ORCH_*.md, shared/pending/ (状态字段) |
| **ops** | agent-ops | 基础设施: tmux 快照, STATUS.md, watchdog, cron | STATUS.md, shared/snapshots/, shared/logs/ops.log |

### 关键协议

1. **指令投递机制**: Conductor 签发 ORCH 到 `shared/pending/` → Supervisor 发现 PENDING → 修改为 DELIVERED → Admin 发现 DELIVERED → 执行 → 修改为 COMPLETED
2. **审计流程**: Conductor 签发 AUDIT_REQUEST 到 `shared/audit/requests/` → Critic 读取 → 运行诊断 → 写 VERDICT 到 `shared/audit/pending/` → Conductor Phase 2 读取 → 归档到 `shared/audit/processed/`
3. **紧急停止**: Phase 2 读 VERDICT 时, 如发现 frozen predictions / mode collapse / diff/Margin<10% → 立即 kill 训练进程

---

## 3. 待办事项

### P0: 紧急 (下一 session 必做)

1. **@2000 frozen prediction 检查** (~03/15 11:00)
   ```bash
   # 确认训练存活
   ps aux | grep train.py | grep yz0370 | grep -v grep
   # 查看进度
   strings /mnt/SSD/GiT_Yihao/Train/Train_20260315/nohup_multilayer_adapt.out | grep "Iter(train)" | tail -5
   # @2000 checkpoint 出现后运行诊断
   cd /home/UNT/yz0370/projects/GiT
   source ~/anaconda3/etc/profile.d/conda.sh && conda activate GiT
   CUDA_VISIBLE_DEVICES=0 python scripts/check_frozen_predictions.py \
     --config configs/GiT/plan_full_nuscenes_large_v1.py \
     --checkpoint /mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt/iter_2000.pth \
     --out-dir /home/UNT/yz0370/projects/GiT_agent/shared/logs/viz_orch045_2000
   ```

2. **@2000 BEV 可视化**: 使用 `scripts/visualize_pred_vs_gt.py` 对 5 个样本可视化, 确认预测模式随场景变化

### P1: 高优先级

3. **@4000 eval + 指标评估** (~03/15 19:00): 如果 @2000 健康, 继续观察
4. **ORCH_035 MASTER_PLAN 更新**: MASTER_PLAN.md 仍引用 ORCH_044 为当前活跃实验, 需更新为 ORCH_045
5. **BUG-64**: BERT-large 预训练权重初始化 (`bert_embed hidden_size=1024` 完美匹配 BERT-large) — 可大幅加速分类器收敛
6. **BUG-65**: off_cx 持续恶化 (0.106→0.193→0.273), 需在 ORCH_045 @4000 后检查

### P2: 中优先级

7. **数据增强**: 当前 train_pipeline 仍无 RandomFlip/RandomCrop (只有 PhotoMetricDistortion). BEV 任务的 RandomFlip 需同时翻转 BEV 标注
8. **Scheduled Sampling (P4)**: 渐进式降低 teacher forcing 比例, 当前 token_drop_rate=0.3 是简化版替代方案
9. **score_thr 消融**: 代码已就绪 (commit `9974e3a`), GPU 被训练占满无法执行

### P3: 长期

10. **Deep Supervision** `loss_out_indices=[8,10,11]`
11. **BEV 坐标 Positional Encoding**
12. **历史帧时序信息** (CEO 最看好方向)
13. **Instance Grouping**

---

## 4. Audit 目录结构

```
shared/audit/
├── requests/          # 空 — 所有审计请求已处理
├── pending/           # Critic 写入判决, Conductor Phase 2 读取
│   └── (当前为空或含已处理 VERDICT)
└── processed/         # 已归档的 AUDIT_REQUEST + VERDICT 对
    ├── AUDIT_REQUEST_*.md    # ~37 个审计请求
    └── VERDICT_*.md          # ~37 个对应判决
```

### 审计请求/判决清单 (共 37 对, 全部已处理)

关键判决:
| VERDICT | 结论 | 影响 |
|---------|------|------|
| VERDICT_FULL_4000 | CONDITIONAL | @4000 首次可靠数据 |
| VERDICT_FULL_8000 | CONDITIONAL | 架构决策级 |
| VERDICT_12000_TERMINATE | PROCEED | 终止 ORCH_024 |
| VERDICT_OVERLAP_THRESHOLD | PROCEED (无需阈值) | 简化了 overlap 实现 |
| VERDICT_TWO_STAGE_FILTER | hull-based IoF/IoB | 标签质量提升 |
| VERDICT_MULTILAYER_FEATURE | 四层拼接 | 确认多层方向 |
| VERDICT_LARGE_V1_AT4000 | CONDITIONAL PROCEED | BUG-62 发现 |
| VERDICT_LARGE_V1_AT6000 | CONDITIONAL PROCEED @8000 FINAL | off_th=0.094 历史最佳, BUG-64/65 |
| VERDICT_CEO_ARCH_QUESTIONS | Deep Supervision P1 | 架构改进建议 |
| VERDICT_CEO_STRATEGY_NEXT | 时序信息最有前途 | 长期方向 |

---

## 5. 文件命令投递机制

### CEO → Conductor

```
CEO_CMD.md (项目根目录)
├── CEO 写入指令 → Conductor Phase 1 读取
├── 执行后归档到 shared/logs/ceo_cmd_archive.md (附时间戳)
├── 必须清空 CEO_CMD.md 并 git push
└── 当前状态: 空 (无待执行指令)
```

### Conductor → Admin (ORCH 投递)

```
shared/pending/ORCH_MMDD_HHMM_NNN.md
├── 状态流转: PENDING → DELIVERED → COMPLETED
│   ├── PENDING: Conductor 签发 (必须含 `- **状态**: PENDING` 行)
│   ├── DELIVERED: Supervisor 检测到 PENDING 后修改
│   └── COMPLETED: Admin 执行完毕后修改
├── 当前有 45 个 ORCH 文件 (ORCH_001 ~ ORCH_045)
└── ORCH_045 状态: RUNNING
```

### Conductor → Critic (审计请求)

```
shared/audit/requests/AUDIT_REQUEST_*.md → Critic 读取
shared/audit/pending/VERDICT_*.md ← Critic 写入判决
shared/audit/processed/ ← Conductor Phase 2 归档
当前状态: requests/ 空, pending/ 空, processed/ 含 37 对已处理文件
```

### Phase 1/Phase 2 循环指令

```
shared/commands/
├── phase1_cmd.md      # Conductor Phase 1 步骤
├── phase2_cmd.md      # Conductor Phase 2 步骤
├── supervisor_cmd.md  # Supervisor 循环步骤
├── admin_cmd.md       # Admin 循环步骤
└── critic_cmd.md      # Critic 审计步骤 (含特征流诊断 + frozen prediction 检查 + TF vs AR)
```

### 基础设施自动化

```
all_loops.sh (PID 1442531, 运行 7h+)
├── sync_loop (PID 443180, 运行 56h+): 定期 git sync
├── watchdog (crontab): 进程存活检查
└── save_tmux.sh: 各 agent tmux 快照 → shared/snapshots/
```

---

## 6. 已知问题和踩过的坑

### 根因级问题

1. **Teacher Forcing Mode Collapse** (最致命)
   - **现象**: 模型对所有输入产生完全相同的预测 (IoU=1.0, 坐标一致)
   - **根因**: 零数据增强 + 100% teacher forcing → 模型记忆空间先验, 忽略视觉输入
   - **证据**: 喂噪声/全零图像 → 输出完全一样; diff/Margin 从 7.9% 跌至 2.3%
   - **修复**: token corruption (token_drop_rate=0.3) + 2 层适应层 + 从零训练 (ORCH_045)
   - **陷阱**: 之前错误地认为 "TF≈AR → 位置信息缺失", 实际是 "TF≈AR → 完全 mode collapse"
   - **陷阱**: car_R=0.582 被错误地认为 "P2+P3 修复成功", 实际是 frozen 位置碰巧和 GT 重叠的假象

2. **ORCH_035 @14000 崩溃**
   - car_R 从 0.62 (@12000) 暴跌至 0.000 (@14000)
   - 根因重新定性为 mode collapse (非 BUG-17 类别竞争)

### 工程级坑

3. **clip_grad=10 过度节流 (BUG-62)**
   - 实际 grad_norm 300-600, clip=10 导致 30-60x 缩减
   - 修复: clip_grad=30 → 但后来发现 30 摧毁了分类器 margin (19.73→0.16)
   - 最终: 回退到 clip_grad=10

4. **CUDA OOM**
   - 多层 [5,11,17,23] + 2 适应层 → 39.24GB (>A6000 47GB with overhead)
   - 修复: batch_size 2→1, accumulative_counts 4→8

5. **nohup 日志二进制字符**
   - tqdm 输出导致 nohup.out 被识别为 binary
   - 解决: `strings nohup.out | grep "Iter(train)"` 替代 `grep`

6. **DINOv3 Hook 目标错误**
   - `backbone.online_dinov3_embed` 不存在
   - 正确路径: `backbone.patch_embed` (= OnlineDINOv3Embed)

7. **模型属性错误**
   - `model.bbox_head` 不存在
   - occ head 在 `model.task_specific_heads.occupancy_prediction_head`

8. **GPU 共享冲突**
   - GPU 1,3 被 yl0826 PETR 训练占用 (~31GB), 只能用 GPU 0,2
   - effective batch 从 32 降至 16

9. **磁盘空间**
   - /home: 99% (68GB free) — 持续关注
   - /mnt/SSD: 96% (163GB free) — 每个 checkpoint ~15GB

10. **rate limit**
    - 所有 agent 曾同时触发限流, 导致全系统停摆
    - ops 实现了 hibernate 机制: 保存状态 → sleep → 恢复

### 推理错误记录 (反面教材)

| 错误推理 | 正确结论 |
|---------|---------|
| "TF≈AR → 位置信息缺失" | TF≈AR → 完全 mode collapse |
| "car_R=0.582 → P2+P3 修复成功" | frozen 位置碰巧和 GT 重叠的假象 |
| "P2+P3 是正确修复方向" | P2+P3 是必要条件但不充分, 根因是 TF mode collapse |
| "检测数 765-846 → 预测不 frozen" | 检测数不等于空间分布, BEV 位置才是判断标准 |
| "BUG-17 → @14000 car_R=0" | mode collapse 才是根因, BUG-17 最多是加速因素 |

---

## 7. 各 Agent 最近的任务状态

### Conductor (本 session — CEO 直接操作)

- **最后动作**: 保存 compact_conductor.md + git push
- **ORCH_045 签发完成**: 多层+适应层+token corruption 从零训练
- **Phase 1/2 循环**: 暂停 (CEO 直接控制中)
- **下一步**: @2000 checkpoint 后恢复自主循环, 运行 frozen prediction 检查

### Supervisor

- **最后记录**: Cycle #299 (compact_supervisor.md, 2026-03-13 05:28)
- **正在监控**: ORCH_035 @iter_9450 (已终止, 需更新)
- **问题**: 快照已过期 — 不知道 ORCH_043/044/045 的情况
- **下一步**: 需要新 session 更新到 ORCH_045 的监控

### Critic

- **最后记录**: compact_critic.md (2026-03-09)
- **已完成判决**: ~37 个 VERDICT (全部已处理)
- **最新判决**: VERDICT_LARGE_V1_AT6000 — CONDITIONAL PROCEED @8000 FINAL
- **问题**: 休眠中, 不知道 ORCH_045 已启动
- **下一步**: @2000 后需要签发新 AUDIT_REQUEST 给 Critic

### Admin

- **最后记录**: compact_admin.md (2026-03-15 02:00)
- **最后执行**: ORCH_044 (多层 ViT-L 训练, PID 1626949 — 已被 kill)
- **已完成**: ORCH_041, 042, 043, 044
- **问题**: 不知道 ORCH_044 已被停止, ORCH_045 由 CEO 直接启动 (绕过了 Admin)
- **下一步**: 需要更新 ORCH_044 状态为 STOPPED, 知悉 ORCH_045

### Ops

- **最后动作**: save_tmux.sh 快照 (持续运行)
- **基础设施**: all_loops.sh PID 1442531 运行 7h+, sync_loop PID 443180 运行 56h+, watchdog crontab 活跃
- **STATUS.md**: 最后更新 03/15 02:46, 所有 agent tmux UP
- **下一步**: 正常运行, 无需干预

---

## 附录: 快速恢复指南

### 新 session 启动步骤

1. **读取本文件**: `cat shared/logs/conductor_state_archive_20260315.md`
2. **检查训练存活**:
   ```bash
   ps aux | grep train.py | grep yz0370 | grep -v grep
   ```
3. **查看训练进度**:
   ```bash
   strings /mnt/SSD/GiT_Yihao/Train/Train_20260315/nohup_multilayer_adapt.out | grep "Iter(train)" | tail -10
   ```
4. **检查 checkpoint**:
   ```bash
   ls -la /mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt/iter_*.pth
   ```
5. **如果 @2000 checkpoint 已出现, 运行诊断**:
   ```bash
   cd /home/UNT/yz0370/projects/GiT
   source ~/anaconda3/etc/profile.d/conda.sh && conda activate GiT
   CUDA_VISIBLE_DEVICES=0 python scripts/check_frozen_predictions.py \
     --config configs/GiT/plan_full_nuscenes_large_v1.py \
     --checkpoint /mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt/iter_2000.pth \
     --out-dir /home/UNT/yz0370/projects/GiT_agent/shared/logs/viz_orch045_2000
   ```
6. **读取 CEO 指令**: `cat CEO_CMD.md`
7. **恢复 Phase 1/Phase 2 循环**: `cat shared/commands/phase1_cmd.md`

### 关键文件索引

| 用途 | 路径 |
|------|------|
| 本归档 | `shared/logs/conductor_state_archive_20260315.md` |
| Conductor 快照 | `shared/logs/compact_conductor.md` |
| Supervisor 快照 | `shared/logs/compact_supervisor.md` |
| Admin 快照 | `shared/logs/compact_admin.md` |
| Critic 快照 | `shared/logs/compact_critic.md` |
| MASTER_PLAN | `MASTER_PLAN.md` |
| CEO 指令 | `CEO_CMD.md` |
| 全局状态 | `STATUS.md` |
| ORCH 指令 | `shared/pending/ORCH_*.md` |
| ORCH 报告 | `shared/logs/report_ORCH_*.md` |
| 审计已处理 | `shared/audit/processed/` |
| Frozen 诊断报告 | `shared/logs/diagnosis_frozen_predictions.md` |
| Frozen 可视化 | `shared/logs/viz_p2p3_iter6000/` |
| CEO 指令归档 | `shared/logs/ceo_cmd_archive.md` |
| 训练 Config | `/home/UNT/yz0370/projects/GiT/configs/GiT/plan_full_nuscenes_large_v1.py` |
| Token corruption | `/home/UNT/yz0370/projects/GiT/mmdet/models/detectors/git.py` |
| 多层+适应层 | `/home/UNT/yz0370/projects/GiT/mmdet/models/backbones/vit_git.py` |
| 诊断脚本 | `/home/UNT/yz0370/projects/GiT/scripts/check_frozen_predictions.py` |
| 可视化脚本 | `/home/UNT/yz0370/projects/GiT/scripts/visualize_pred_vs_gt.py` |
| ORCH_045 work_dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt` |
| ORCH_045 日志 | `/mnt/SSD/GiT_Yihao/Train/Train_20260315/nohup_multilayer_adapt.out` |

---

*归档完成 | 2026-03-15 04:05 | claude_conductor*
