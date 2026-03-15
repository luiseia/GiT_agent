# Conductor 上下文快照
> 时间: 2026-03-15 08:30
> 原因: Context 消耗较多，定期保存

---

## 当前状态: ORCH_045 训练巡航中，@2000 eval 完成，等 @4000

### 训练信息
- **Config**: `configs/GiT/plan_full_nuscenes_large_v1.py` (commit `26b6f92`)
- **架构**: GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen **多层 [5,11,17,23]**
- **投影**: 4×1024=4096 → 2048 → GELU → 1024
- **适应层**: 2 层 PreLN TransformerEncoderLayer (25.2M 参数, trainable, nhead=16)
- **Anti-collapse**: `token_drop_rate=0.3`
- **权重来源**: 从零训练 (load_from=None, SAM pretrained via init_cfg)
- **PID**: 1686317 (rank0), 1686318 (rank1), GPU 0,2 (2×A6000), ~29GB/GPU
- **work_dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt`
- **日志**: `.../nohup_multilayer_adapt.out` (用 `strings` 过滤)
- **当前进度**: ~iter 3110/40000
- **effective batch**: 1×2×8 = 16, val@2000
- **速度**: ~3.78 sec/iter
- **LR**: 2.5e-6 (warmup 完成, 稳态)
- **ETA @40000**: ~03/16 21:30

---

## ⭐ @2000 Eval 结果 (2026-03-15 07:19)

| 指标 | ORCH_045 @2000 | GiT-Large v1 @2000 (单层) | ORCH_024 @2000 |
|------|---------------|--------------------------|----------------|
| **ped_R** | **0.7646** | 0.0000 | ~0 |
| car_R | 0.0000 | 0.0000 | 0.627 |
| 其他 8 类 R | 全 0 | 全 0 | — |
| bg_FA | **0.9208** | 0.002 | 0.222 |
| off_cx | 0.309 | 0.106 | 0.056 |
| off_cy | 0.146 | 0.029 | 0.069 |
| off_w | 0.087 | 0.070 | 0.020 |
| off_h | 0.038 | 0.009 | 0.005 |
| off_th | 0.192 | 0.078 | 0.174 |

### 判断: 不是 frozen predictions, CONDITIONAL PROCEED to @4000
- **ped_R=0.7646**: 从零训练 @2000 即激活 1 类 — 积极
- **bg_FA=0.9208**: 大量预测正样本，行为与 frozen 完全不同
- **offset 差**: 从零训练 @2000 预期内
- Critic 未响应（上次活跃 03/09），conductor 自行决策

---

## reg_loss=0 趋势
- @iter_2000: 19/200 报告 = 9.5%
- 含 3 次 total loss=0 (iter 1530, 1550, 1600)
- 所有事件均反弹，非永久 collapse
- 训练恢复后 (iter 2000+) 暂无新 reg_loss=0 事件

---

## 检查点计划

| 检查点 | 预计时间 | 行动 |
|--------|---------|------|
| ✅ @2000 | 03/15 07:19 | ped_R=0.76, non-frozen, CONDITIONAL PROCEED |
| **@4000** | **~03/15 15:00** | car_R 是否激活? offset 改善? bg_FA 下降? |
| @8000 | ~03/16 01:00 | 架构决策级评估 |

---

## Agent 状态
| Agent | 状态 |
|-------|------|
| conductor | 活跃，Phase 1/2 循环中 |
| supervisor | 快照过期 (03/13)，仍在监控 ORCH_035 |
| critic | ⚠️ 无响应 (上次活跃 03/09)，AUDIT_REQUEST 未取走 |
| admin | 快照过期 (03/15 02:00)，不知道 ORCH_044 已停止 |
| ops | 正常运行 |

## 关键文件
- MASTER_PLAN: `MASTER_PLAN.md` (已更新 @2000 eval)
- AUDIT_REQUEST: `shared/audit/requests/AUDIT_REQUEST_ORCH045_AT2000.md`
- 状态归档: `shared/logs/conductor_state_archive_20260315.md`
- Checkpoint: `/mnt/SSD/.../full_nuscenes_large_v1_multilayer_adapt/iter_2000.pth`
- 诊断脚本: `scripts/check_frozen_predictions.py`

## 恢复指令
1. 读本文件 + `shared/logs/conductor_state_archive_20260315.md`
2. `ps aux | grep train.py | grep yz0370` — 确认训练存活
3. `strings .../nohup_multilayer_adapt.out | grep "Iter(train)" | tail -5`
4. 检查 `CEO_CMD.md`
5. @4000 后运行 eval 收集 + frozen prediction 诊断
6. 恢复 Phase 1/Phase 2 循环
