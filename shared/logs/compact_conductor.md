# Conductor 上下文快照
> 时间: 2026-03-13 07:30
> 原因: CEO 请求上下文保存

## 当前状态

**ORCH_035** — IN_PROGRESS, iter ~10010/40000 (25.0%)
- Label pipeline 大修 (5 项改动) + resume from ORCH_034@4000
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- Config: `configs/GiT/plan_full_nuscenes_multilayer.py`
- 4 GPU DDP, A6000 ~37.8GB/GPU
- ETA: ~2d 5h
- **下一关键节点: @12000 eval (~10:50)**

## 关键数据 — Val 历史

| 指标 | @6000 | @8000 | @10000 | 趋势 |
|------|-------|-------|--------|------|
| car_R | 0.2329 | **0.6012** | 0.4202 | 🔴 @10k 回退 |
| car_P | 0.0822 | 0.0822 | 0.0531 | 🔴 @10k 下降 |
| bg_FA | 0.0938 | 0.2568 | 0.2534 | → 稳定 |
| off_th | 0.2848 | 0.2083 | **0.1862** | ✅ 持续改善 |
| ped_R | — | 0.2002 | 0.0000 | 🔴 消失 |
| truck_R | — | 0.0243 | 0.0000 | 🔴 消失 |
| bus_R | — | 0.0886 | 0.1404 | ✅ 改善 |
| cone_R | — | 0.0000 | 0.3823 | 🆕 新激活 |

### Critic 判决历史
- **@8000**: PROCEED — car_R 0.60 达到决策树最优分支
- **@10000**: CONDITIONAL PROCEED — car_R/P 同时暴跌是新模式 (非 ORCH_024 振荡), cone 449K FP 挤压 car
  - **@12000 STOP 条件: car_P < 0.04 或 car_R < 0.35**

### Loss 趋势
- iter 4200-6000: ~5.0→3.8 (新标签适应)
- iter 6000-8000: ~4.4 (稳定)
- iter 8000-9500: ~4.1→3.9 (缓降)
- 零持续异常, 散发 reg=0 DDP artifact

## ⚠️ BUG-17 升级: CRITICAL

@10000 证明 per-batch sqrt balance 导致类别竞争:
- cone 激活 (R=0.38, P=0.008) 产生 449K FP
- 挤压 car_R (-30%), car_P (-35%), ped/truck 消失
- **必须在 @12000 后作为 ORCH_036 第一优先项修复**
- 候选方案: dataset-level sqrt / 权重上限 / EMA / 关闭 sqrt

## @12000 决策树

```
ORCH_035 @12000:
├─ car_R ≥ 0.55 + car_P ≥ 0.06 + bg_FA < 0.40 → ★ 继续 + 部署 BUG-17 修复
├─ car_R 0.35-0.55 + car_P ≥ 0.04 → ⚠️ 继续但必须部署 BUG-17
├─ car_R < 0.35 → 🔴 STOP — 部署 BUG-17 后重启
├─ car_P < 0.04 → 🔴 STOP — FP 工厂失控
└─ 注: 类别振荡是 BUG-17 症状, 非架构问题
```

## @12000 附加测试
1. score_thr 消融: @10000 + @12000 checkpoint 上跑 0.1/0.2/0.3/0.5 (零成本, 两次 VERDICT 强调)
2. per-class confusion matrix
3. per-class FP 目标分析

## CEO 指令记录 (本 session)
- CEO 要求报告为何 @8000 后未执行 score_thr 消融和 Phase 2
  - 报告: `shared/logs/reports/report_post8000_missed_actions.md`
  - 根因: Conductor 将 PROCEED 误解为 "维持现状"
- CEO 指出 ViT-L 可能不是 300M → 实测 303M (代码确认)

## Phase 2 待办 (ORCH_035 @12000 eval 后部署)
1. **🔴 BUG-17 修复** (CRITICAL, 第一优先)
2. Deep Supervision `loss_out_indices=[8,10,11]` (零成本)
3. BUG-45 fix: OCC head 推理 attn_mask (可立即开发)
4. Per-slot 性能分析

## Phase 3: ViT-L Finetune (CEO 优先)
- 代码已就绪: `model_variant='large'` in `vit_git.py`
- Config 已就绪: `plan_full_nuscenes_vitl_finetune.py` (303M, 24层, 1024维)
- **权重未下载**: 链接 403 过期, 需 CEO 重新申请

## 基础设施
- 全 agent UP (conductor/critic/supervisor/admin/ops)
- all_loops.sh PID 443179, sync_loop PID 443180
- watchdog crontab ✅
- /mnt/SSD 96% (163GB), /home 99% (68GB) ⚠️

## 关键文件索引
- MASTER_PLAN: `/home/UNT/yz0370/projects/GiT_agent/MASTER_PLAN.md`
- ORCH_035: `shared/pending/ORCH_0312_1750_035.md` (COMPLETED)
- @8000 verdict: `shared/audit/processed/VERDICT_ORCH035_AT8000.md`
- @10000 verdict: `shared/audit/processed/VERDICT_ORCH035_AT10000.md`
- CEO 报告: `shared/logs/reports/report_post8000_missed_actions.md`
- ViT-L config: `/home/UNT/yz0370/projects/GiT/configs/GiT/plan_full_nuscenes_vitl_finetune.py`
- 训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/20260312_175353/20260312_175353.log`

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整路线图和决策树
3. 检查 CEO_CMD.md
4. 继续 Phase 1/Phase 2 循环
5. **重点关注**: @12000 eval 结果 + BUG-17 部署决策
