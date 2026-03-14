# Conductor 上下文快照
> 时间: 2026-03-13 20:35
> 原因: CEO 请求上下文保存

## 当前状态

**训练已终止** — ORCH_035 @14000 car_R=0.000 (BUG-17 灾难性崩溃)
**score_thr 消融正在运行** — ORCH_024 @8000 + ORCH_035 @12000, 8 组实验

### 今日重大事件 (时间线)
1. **12:04** 训练 OOM 崩溃 — ORCH_036 的 4 个并行 eval 占满 GPU
2. **12:05-15:36** ORCH_036 score_thr 消融失败 — scores=1.0, evaluator score_thr 是死代码
3. **15:41** 训练恢复 (ORCH_039), 从 iter_12000 resume
4. **18:15** score_thr 代码修复 — CEO 修正: cls_probs 替代 marker_probs (commit `9974e3a`)
5. **18:30** CEO 指示 offset 优先 + ORCH_024 @8000 确认为综合最优
6. **19:00** CEO 指出未考虑 DINOv3 LN tuning 和 ViT-L — 不能过早否定 overlap+多层方向
7. **19:15** @14000 val 开始 (自动触发), checkpoint 已保存
8. **20:09** 🔴🔴 **@14000 val 结果: car_R=0.000, cone_R=0.830** — BUG-17 完全接管
9. **20:10** CEO 指示暂停训练, 先跑消融对比两个模型
10. **20:27** score_thr 消融启动 (torchrun 串行执行)

## ⭐ CEO 核心指示

### 1. offset 指标优先
5 个 offset (cx,cy,w,h,th) 直接影响 occ 图 mIoU, 是最重要的评估标准。
优先级: offset > car_R > car_P/bg_FA

### 2. 不要过早否定 overlap+多层方向
CEO 指出 ORCH_035 offset 差不能归罪于 overlap+多层, 还有两个关键变量没试:
- **LN Tuning**: 当前 ViT-7B 完全冻结, 连 normalization 层都没解冻 (~1M 参数, 零成本)
- **ViT-L finetune**: 多层投影 16384→768 信息损失 95%, 用 ViT-L 全量微调可大幅缓解

## score_thr 消融 — 进行中

**脚本**: `/home/UNT/yz0370/projects/GiT/scripts/score_thr_ablation.sh`
**日志**: `shared/logs/score_thr_ablation.log` (进度), `shared/logs/ablation_*.log` (详细)
**nohup 日志**: `shared/logs/ablation_nohup.log`

| # | 模型 | Checkpoint | score_thr | 状态 | 预计完成 |
|---|------|-----------|-----------|------|---------|
| 1 | ORCH_024 @8000 | iter_8000.pth (center, L16) | 0.1 | 🔄 进行中 | ~22:30 |
| 2 | ORCH_024 @8000 | 同上 | 0.2 | 等待 | ~00:30 |
| 3 | ORCH_024 @8000 | 同上 | 0.3 | 等待 | ~02:30 |
| 4 | ORCH_024 @8000 | 同上 | 0.5 | 等待 | ~04:30 |
| 5 | ORCH_035 @12000 | iter_12000.pth (overlap, 多层) | 0.1 | 等待 | ~06:30 |
| 6 | ORCH_035 @12000 | 同上 | 0.2 | 等待 | ~08:30 |
| 7 | ORCH_035 @12000 | 同上 | 0.3 | 等待 | ~10:30 |
| 8 | ORCH_035 @12000 | 同上 | 0.5 | 等待 | ~12:30 |

**每次 ~2h (4-GPU DDP torchrun), 总 ~16h, 预计 03/14 ~12:30 完成**

### Baseline 数据 (score_thr=0, 已有)

| 指标 | ORCH_024 @8000 | ORCH_035 @12000 |
|------|---------------|----------------|
| off_cx | **0.0446** | 0.082 |
| off_cy | **0.0736** | 0.107 |
| off_w | **0.0251** | 0.036 |
| off_h | **0.0064** | 0.011 |
| off_th | **0.1399** | 0.162 |
| car_R | **0.718** | 0.620 |
| car_P | 0.060 | **0.100** |
| bg_FA | 0.311 | **0.283** |

### 技术规格对比

| 参数 | ORCH_024 | ORCH_035 |
|------|----------|----------|
| DINOv3 | ViT-7B frozen | ViT-7B frozen |
| 特征层 | **单层 L16** | **多层 [L9,L19,L29,L39]** |
| 投影 | 4096→2048→768 | 16384→4096→768 |
| Target 分配 | **center-based** | **overlap (min_iof=0.3)** |
| LN/BN | 完全冻结 | 完全冻结 |

## 🔴🔴 ORCH_035 @14000 — 灾难性结果

| 指标 | @12000 | **@14000** |
|------|--------|----------|
| car_R | 0.620 | **0.000** |
| car_P | 0.100 | 0.000 |
| cone_R | — | **0.830** |
| truck_R | 0.048 | 0.192 |
| off_cx | 0.082 | 0.059 ✅ |
| off_cy | 0.107 | 0.075 ✅ |
| off_w | 0.036 | 0.019 ✅ |
| off_h | 0.011 | 0.015 🔴 |
| off_th | 0.162 | 0.200 🔴 |

**BUG-17 类别权重跷跷板到极限 — cone 完全霸占预测空间**
注: offset 某些指标改善, 但 car 完全没有预测, 这些 offset 来自 cone/truck, 无参考价值

## BUG-17: BLOCKER — @14000 证明必须修复

修复方案: Weight Cap max_w=3.0 (一行改动):
```python
_class_weights[c] = min(1.0 / _math.sqrt(cnt / _min_count), 3.0)
```
- ORCH_037 代码已提交
- **消融完成后, 下一步必须部署 BUG-17 fix**

### 跷跷板演变
| Iter | 主要预测类 | car_R | 最大 FP 源 |
|------|----------|-------|-----------|
| @8k | car 主导 | 0.718 | car 1.01M |
| @10k | car+cone | 0.420 | car 1.14M + cone 449K |
| @12k | car+bus | 0.620 | bus 922K |
| **@14k** | **cone 独占** | **0.000** | cone 完全接管 |

## BUG-61: MEDIUM

恢复后 13/173 iter (7.5%) reg_loss=0, 高于 ORCH_024 的 4.1%。
不致命但影响 offset 回归质量。BUG-17 修复后调查。

## ORCH_024 Val 完整历史 (5-offset)

| 指标 | @2000 | @4000 | @6000 | **@8000** | @10000 | @12000 |
|------|-------|-------|-------|----------|--------|--------|
| off_cx | 0.0558 | **0.0392** | 0.0556 | 0.0446 | 0.0723 | 0.0383 |
| off_cy | **0.0693** | 0.0971 | 0.0818 | 0.0736 | 0.0916 | 0.0812 |
| off_w | 0.0201 | **0.0156** | 0.0378 | 0.0251 | 0.0389 | 0.0230 |
| off_h | **0.0049** | **0.0049** | 0.0107 | 0.0064 | 0.0171 | 0.0142 |
| off_th | 0.1739 | 0.1499 | 0.1685 | 0.1399 | 0.1597 | **0.1275** |
| car_R | 0.627 | 0.419 | 0.455 | **0.718** | **0.726** | 0.526 |
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | 0.081 |
| bg_FA | **0.222** | **0.199** | 0.331 | 0.311 | 0.407 | 0.278 |

权重路径: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/iter_8000.pth`

## 活跃 ORCH 指令

| ORCH | 任务 | 状态 | 说明 |
|------|------|------|------|
| **037** | BUG-17 Weight Cap (max_w=3.0) | COMPLETED (代码) | **BLOCKER** — 消融后立即部署 |
| 039 | 紧急恢复训练 | ✅ DONE | 15:41 恢复 |
| 040 | score_thr 代码修复 | ✅ DONE | cls_probs (9974e3a) |
| **041** | score_thr 消融 | 🔄 执行中 | 8 组实验, ~16h, ETA 03/14 ~12:30 |

## 下一步计划 (消融完成后)

1. **分析消融结果** — 对比 ORCH_024 vs ORCH_035 在不同 score_thr 下的 5-offset + R/P
2. **部署 BUG-17 fix** — Weight Cap max_w=3.0 (BLOCKER, 必须修复)
3. **CEO 提出的关键实验**:
   - LN Tuning: 解冻 DINOv3 norm 层 (~1M 参数, 零显存成本)
   - ViT-L finetune: 切换到 300M 参数全量微调
4. 决定是否继续 overlap+多层方向 (需 LN/ViT-L 实验数据支持)

## 基础设施
- 全 agent UP (conductor/critic/supervisor/admin/ops)
- all_loops.sh PID 443179, sync_loop PID 443180
- watchdog crontab ✅
- /mnt/SSD 96%, /home 99% ⚠️
- **训练已终止, GPU 被消融占用**

## 关键文件索引
- MASTER_PLAN: `/home/UNT/yz0370/projects/GiT_agent/MASTER_PLAN.md`
- 消融脚本: `/home/UNT/yz0370/projects/GiT/scripts/score_thr_ablation.sh`
- 消融日志: `shared/logs/score_thr_ablation.log`, `shared/logs/ablation_*.log`
- ORCH_024 训练日志: `/mnt/SSD/.../full_nuscenes_gelu/20260308_163535/20260308_163535.log`
- ORCH_035 训练日志: `/mnt/SSD/.../full_nuscenes_multilayer_v4/20260313_154113/20260313_154113.log`
- ORCH_024 权重: `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/iter_8000.pth`
- ORCH_035 权重: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/iter_12000.pth`
- score_thr 修复: GiT commit `9974e3a`

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整路线图
3. 检查 CEO_CMD.md
4. 检查消融进度: `cat shared/logs/score_thr_ablation.log`
5. **重点关注**:
   - 消融是否完成 → 提取结果, 生成对比报告
   - 消融完成后部署 BUG-17 fix (BLOCKER)
   - CEO 指示: LN tuning + ViT-L finetune 方向
   - **offset 指标是核心评判标准** (CEO 指示)
