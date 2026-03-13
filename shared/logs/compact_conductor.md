# Conductor 上下文快照
> 时间: 2026-03-13 15:10
> 原因: CEO 请求上下文保存

## 当前状态

**ORCH_035** — IN_PROGRESS, 训练暂停 (iter 12160), 等待恢复
- Label pipeline 大修 (5 项改动) + resume from ORCH_034@4000
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- Config: `configs/GiT/plan_full_nuscenes_multilayer.py`
- 4 GPU DDP, A6000 ~37.8GB/GPU

### 🔴 训练暂停事件
- **原因**: ORCH_036 score_thr 消融同时启动 4 个 eval 进程, 占满 4 GPU, 训练 OOM 崩溃
- **停止时间**: 12:04 (iter 12160)
- **eval 进度**: 4 个 eval 均 ~87% (2620/3010), ETA ~15:35
- **恢复**: ORCH_038 已签发 (DELIVERED), eval 完成后 Admin 自动 resume from iter_12000
- **教训**: 并行 eval 必须用 CUDA_VISIBLE_DEVICES 隔离; 1-GPU eval 数据量 = 4x (3010 iter vs 753)

## 关键数据 — Val 历史

| 指标 | @6000 | @8000 | @10000 | **@12000** | 趋势 |
|------|-------|-------|--------|----------|------|
| car_R | 0.2329 | 0.6012 | 0.4202 | **0.6203** | ✅✅ V 形反弹, 历史最优 |
| car_P | 0.0822 | 0.0822 | 0.0531 | **0.0995** | ✅✅ 历史最优! 超越 ORCH_024 峰值 0.090 |
| bg_FA | 0.0938 | 0.2568 | 0.2534 | **0.2831** | 🔴 缓升, <0.40 安全 |
| off_th | 0.2848 | 0.2083 | 0.1862 | **0.1622** | ✅✅ 持续改善, 历史最优 |
| ped_R | — | 0.2002 | 0.0000 | 0.0003 | 🔴 BUG-17 压制 |
| truck_R | — | 0.0243 | 0.0000 | 0.0477 | ✅ 恢复 |
| bus_R | — | 0.0886 | 0.1404 | 0.1491 | ✅ 但 bus FP 922K 成最大 FP 源 |
| cone_R | — | 0.0000 | 0.3823 | 0.0000 | ⚡ BUG-17 跷跷板 |

### ORCH_024 对比 (@12000)
| 指标 | ORCH_024 | ORCH_035 |
|------|----------|----------|
| car_R | 0.526 | **0.620** ✅ +18% |
| car_P | 0.081 | **0.100** ✅ +23% |
| bg_FA | **0.278** | 0.283 ≈ |
| off_th | **0.128** | 0.162 🔴 |

### Critic 判决历史
- **@8000**: PROCEED — car_R 0.60, 4 类激活
- **@10000**: CONDITIONAL PROCEED — car_R/P 暴跌, cone 449K FP (BUG-17)
- **@12000**: ⭐ **PROCEED** — car_P=0.100 历史最优, 决策树最优分支命中
  - car 改善真实: FP -25% + TP +48%, FP/TP 比 9.1 (最低)
  - BUG-17 跷跷板确认: @10k cone↑car↓ → @12k car↑cone↓bus↑
  - 总 FP 1.88M→2.06M (+9.5%), bg_FA 线性外推 @20k ≈ 0.40
  - peak_car_P = 0.100, 超越 ORCH_024 全程峰值 0.090

### Loss 趋势
- iter 10000-12000: 均值 ~4.0, 缓降
- 零 spike, 零 reg=0 (除 BUG-61 偶发), grad_norm 8-52 (clip=30)

## 活跃 ORCH 指令

| ORCH | 任务 | 状态 | 说明 |
|------|------|------|------|
| **036** | score_thr 消融 @12k ckpt (0.1/0.2/0.3/0.5) | DELIVERED — eval ~87% | 4 个 eval 并行, ETA ~15:35 |
| **037** | BUG-17 Weight Cap (max_w=3.0) + mini 验证 | DELIVERED | 待 eval 完成后执行 |
| **038** | 恢复训练 (resume from iter_12000) | DELIVERED | 待 eval 完成后执行 |

## ⚠️ BUG-17: CRITICAL — 修复方案确定

Critic @12000 推荐 **方案 A: Weight Cap max_w=3.0** (一行改动):
```python
# 文件: GiT/mmdet/models/dense_heads/git_occ_head.py ~L832
# 当前: _class_weights[c] = 1.0 / _math.sqrt(cnt / _min_count)
# 修改: _class_weights[c] = min(1.0 / _math.sqrt(cnt / _min_count), 3.0)
```
- 直接防止极端权重 (当前小类可达 10x+)
- 向后兼容, mini 验证后 @16k 部署
- 备选: B=Dataset-level sqrt, C=关闭 sqrt (核选项)

### BUG-17 跷跷板证据
| Iter | FP 主要来源 | 总 FP |
|------|-----------|-------|
| @8k | car 1.01M (54%) | 1.88M |
| @10k | car 1.14M + cone 449K | 1.90M |
| @12k | **bus 922K (45%)** + car 849K | **2.06M** |

## BUG-61 (NEW, LOW)
- 偶发 reg_loss=0 (iter 8030, 12030), 间隔 4000 iter
- 0.025% 频率, 不影响训练, BUG-17 后调查

## @16000 决策树

```
ORCH_035 @16000:
├─ car_P ≥ 0.08 + car_R ≥ 0.50 + bg_FA < 0.40
│   → ★ PROCEED + 部署 BUG-17 fix
├─ car_P ≥ 0.06 + car_R ≥ 0.45
│   → PROCEED, BUG-17 fix 必要前提
├─ car_R < 0.40 → STOP, 回退 @12k
├─ car_P < 0.04 → STOP, 审查 loss 权重
├─ bg_FA > 0.40 → CONDITIONAL
└─ peak_car_P(@12k) = 0.100 (Rule #6)
```

### @14000 快速检查 (非决策级)
- car_R < 0.35 → 提前预警
- car_P < 0.03 → 考虑提前 STOP

## Phase 2 待办 (@16000 eval 后部署)
1. **🔴 BUG-17 Weight Cap** — ORCH_037 开发中
2. Deep Supervision `loss_out_indices=[8,10,11]` (零成本)
3. BUG-45 fix: OCC head 推理 attn_mask
4. Per-slot 性能分析

## Phase 3: ViT-L Finetune (CEO 优先)
- car_P=0.100 超越 ORCH_024, 当前架构仍有潜力, 不急切换
- Critic 建议: 先完成 BUG-17, 若 ORCH_036 @12k car_P>0.10 且 bg_FA<0.25 则当前架构足够
- 代码/Config 已就绪, **权重未下载** (403 过期)

## 基础设施
- 全 agent UP (conductor/critic/supervisor/admin/ops)
- all_loops.sh PID 443179, sync_loop PID 443180
- watchdog crontab ✅
- /mnt/SSD 96%, /home 99% ⚠️

## 关键文件索引
- MASTER_PLAN: `/home/UNT/yz0370/projects/GiT_agent/MASTER_PLAN.md`
- ORCH_035: `shared/pending/ORCH_0312_1750_035.md` (COMPLETED)
- ORCH_036: `shared/pending/ORCH_0313_1150_036.md` (score_thr 消融)
- ORCH_037: `shared/pending/ORCH_0313_1150_037.md` (BUG-17 fix)
- ORCH_038: `shared/pending/ORCH_0313_1250_038.md` (恢复训练)
- @8000 verdict: `shared/audit/processed/VERDICT_ORCH035_AT8000.md`
- @10000 verdict: `shared/audit/processed/VERDICT_ORCH035_AT10000.md`
- @12000 verdict: `shared/audit/processed/VERDICT_ORCH035_AT12000.md`
- Eval 日志: `/home/UNT/yz0370/projects/GiT/work_dirs/plan_full_nuscenes_multilayer/20260313_*/`
- 训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/20260312_175353/20260312_175353.log`

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整路线图
3. 检查 CEO_CMD.md
4. 继续 Phase 1/Phase 2 循环
5. **重点关注**:
   - eval 是否完成 → 读取 score_thr 消融结果
   - 训练是否已恢复 (ORCH_038)
   - ORCH_037 BUG-17 weight cap 验证结果
   - @14000 快速检查 → @16000 决策级 eval
