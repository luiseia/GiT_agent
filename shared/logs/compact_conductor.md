# Conductor 上下文快照
> 时间: 2026-03-13 18:35
> 原因: CEO 请求上下文保存

## 当前状态

**ORCH_035** — IN_PROGRESS, 训练正常 iter ~13570, @14000 ETA ~19:15
- Label pipeline 大修 (5 项改动) + resume from ORCH_034@4000
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- Config: `configs/GiT/plan_full_nuscenes_multilayer.py`
- 4 GPU DDP, A6000 ~39.5GB/GPU
- **新训练日志** (resume 后): `20260313_154113/20260313_154113.log`

### 今日重大事件
1. **12:04 训练 OOM 崩溃** — ORCH_036 的 4 个并行 eval 占满 GPU
2. **ORCH_036 score_thr 消融彻底失败** — 模型 scores=1.0, evaluator score_thr 是死代码
3. **15:41 训练恢复** (ORCH_039), 从 iter_12000 resume
4. **score_thr 代码修复** — CEO 修正: 用 cls_probs 而非 marker_probs (commit `9974e3a`)
5. **CEO 认知修正**: offset 指标 (cx,cy,w,h,th) 才是最重要的, 直接决定 occ 图 mIoU

## ⭐ CEO 核心指示: offset 指标优先

**5 个 offset 指标直接影响 occ 图 mIoU, 是最重要的评估标准。**

评估优先级: offset (cx,cy,w,h,th) > car_R > car_P/bg_FA

### 综合最优权重评估: ORCH_024 @8000

| 指标 | ORCH_024 @8000 | ORCH_035 @12000 | 胜者 |
|------|---------------|----------------|------|
| **off_cx** | **0.045** | 0.082 | 024 (+82%) |
| **off_cy** | **0.074** | 0.107 | 024 (+45%) |
| off_w | 无数据 | 0.036 | — |
| off_h | 无数据 | 0.011 | — |
| **off_th** | **0.140** | 0.162 | 024 (+16%) |
| car_R | **0.718** | 0.620 | 024 |
| car_P | 0.060 | **0.100** | 035 |
| bg_FA | 0.311 | **0.283** | 035 |

**结论: ORCH_024 @8000 当前综合最优** (offset 全面碾压 + car_R 更高)

## 关键数据 — ORCH_035 Val 历史 (含完整 offset)

| 指标 | @6000 | @8000 | @10000 | **@12000** | 趋势 |
|------|-------|-------|--------|----------|------|
| **off_cx** | — | 0.061 | **0.046** | 0.082 🔴 | V 形 (采样偏差) |
| **off_cy** | — | 0.159 | 0.113 | **0.107** | ✅ 持续改善 |
| **off_w** | — | 0.033 | **0.026** | 0.036 🔴 | V 形 |
| **off_h** | — | **0.010** | 0.016 | 0.011 | ✅ 恢复 |
| **off_th** | 0.285 | 0.208 | 0.186 | **0.162** | ✅✅ 持续改善 |
| car_R | 0.233 | 0.601 | 0.420 | **0.620** | ✅ V 形反弹 |
| car_P | 0.082 | 0.082 | 0.053 | **0.100** | ✅ 历史最优 |
| bg_FA | 0.094 | 0.257 | 0.253 | **0.283** | 🔴 缓升 |
| ped_R | — | 0.200 | 0.000 | 0.000 | 🔴 BUG-17 |
| truck_R | — | 0.024 | 0.000 | 0.048 | ⚠️ |
| bus_R | — | 0.089 | 0.140 | 0.149 | ✅ 但 FP 922K |

### ORCH_024 Val 历史 (offset)

| 指标 | @2000 | @4000 | @6000 | @8000 | @10000 | @12000 |
|------|-------|-------|-------|-------|--------|--------|
| off_cx | 0.056 | **0.039** | 0.056 | 0.045 | — | — |
| off_cy | **0.069** | 0.097 | 0.082 | 0.074 | — | — |
| off_th | 0.174 | 0.150 | 0.169 | 0.140 | 0.160 | **0.128** |
| car_R | 0.627 | 0.419 | 0.455 | 0.718 | 0.726 | 0.526 |
| car_P | 0.079 | 0.078 | **0.090** | 0.060 | 0.069 | 0.081 |

## 活跃 ORCH 指令

| ORCH | 任务 | 状态 | 说明 |
|------|------|------|------|
| **037** | BUG-17 Weight Cap (max_w=3.0) 代码 | COMPLETED (代码) | mini 验证待 GPU |
| **039** | 紧急恢复训练 | ✅ DONE | 15:41 恢复 |
| **040** | score_thr 代码修复 | ✅ DONE (代码) | CEO 修正: cls_probs (9974e3a) |
| **041** | @14000 val 后 score_thr 消融 | DELIVERED | 4-GPU DDP 串行, ~4h |

## score_thr 消融 — 代码已就绪

- **ORCH_036 失败原因**: `_predict_single` 输出 scores=1.0, evaluator score_thr 从未使用
- **ORCH_040 修复**: marker_probs 传递 (错误)
- **CEO 修正 (commit 9974e3a)**: 用 `cls_probs = F.softmax(cls_logits)` 的 max 作为置信度
- **代码变更**: `pred_scores[..., 0]` → `pred_scores[..., 1]`, 变量名 grid_marker_scores → grid_cls_scores
- **消融执行**: ORCH_041, @14000 val 后暂停训练, 4-GPU DDP 串行跑 score_thr={0.1,0.2,0.3,0.5}
- **config 路径**: `--cfg-options val_evaluator.score_thr=X`

## BUG-17: CRITICAL — 代码已完成, 待 mini 验证

修复方案 A: Weight Cap max_w=3.0 (一行改动):
```python
_class_weights[c] = min(1.0 / _math.sqrt(cnt / _min_count), 3.0)
```
- ORCH_037 代码已提交, mini 验证待 GPU 空闲
- 计划 @16k eval 后部署

### BUG-17 跷跷板证据
| Iter | FP 主要来源 | 总 FP |
|------|-----------|-------|
| @8k | car 1.01M (54%) | 1.88M |
| @10k | car 1.14M + cone 449K | 1.90M |
| @12k | **bus 922K (45%)** + car 849K | **2.06M** |

## BUG-61 (LOW, 频率加速)
- iter 8030, 12030, 12440, **13520** — reg_loss=0
- 间隔: 4000 → 410 → 1080
- 仍 <0.1% 频率, 不影响收敛, BUG-17 后调查

## Loss 趋势
- iter 12000-13570: 均值 ~3.9, 缓降
- grad_norm 6-38, 正常
- 零 spike (除 BUG-61 偶发 reg=0)

## @14000 快速检查 (非决策级) — ETA ~19:15
- car_R < 0.35 → 提前预警
- car_P < 0.03 → 考虑提前 STOP
- **重点关注 offset 指标变化** (cx,cy,w,h,th)

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
**注**: 需增加 offset 指标判断条件

## Phase 2 待办
1. **🔴 BUG-17 Weight Cap** — 代码完成, 待 mini 验证
2. **score_thr 消融** — 代码完成 (cls_probs), ORCH_041 待执行
3. Deep Supervision `loss_out_indices=[8,10,11]` (零成本)
4. BUG-45 fix: OCC head 推理 attn_mask
5. Per-slot 性能分析

## 基础设施
- 全 agent UP (conductor/critic/supervisor/admin/ops)
- all_loops.sh PID 443179, sync_loop PID 443180
- watchdog crontab ✅
- /mnt/SSD 96%, /home 99% ⚠️

## 关键文件索引
- MASTER_PLAN: `/home/UNT/yz0370/projects/GiT_agent/MASTER_PLAN.md`
- 训练日志 (新): `/mnt/SSD/.../full_nuscenes_multilayer_v4/20260313_154113/20260313_154113.log`
- 训练日志 (旧): `/mnt/SSD/.../full_nuscenes_multilayer_v4/20260312_175353/20260312_175353.log`
- ORCH_041: `shared/pending/ORCH_0313_1830_041.md` (score_thr 消融)
- @12000 verdict: `shared/audit/processed/VERDICT_ORCH035_AT12000.md`
- score_thr 修复: GiT commit `9974e3a`

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整路线图
3. 检查 CEO_CMD.md
4. 继续 Phase 1/Phase 2 循环
5. **重点关注**:
   - @14000 val 是否触发 → 读取结果 (重点看 5 个 offset)
   - ORCH_041 score_thr 消融是否执行
   - ORCH_037 BUG-17 mini 验证
   - **offset 指标是核心评判标准** (CEO 指示)
   - 综合最优仍是 ORCH_024 @8000, ORCH_035 需要证明 offset 能追上
