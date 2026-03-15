# Conductor 上下文快照
> 时间: 2026-03-15 11:30
> 原因: @4000 eval 完成，context 消耗大

---

## 当前状态: ORCH_045 训练中，@6000 为 ABSOLUTE FINAL

### 训练信息
- **架构**: GiT-Large + DINOv3 ViT-L frozen 多层 [5,11,17,23] + 2 层适应层 + token_drop_rate=0.3
- **从零训练**, PID 1686317/1686318, GPU 0,2 (2×A6000), ~29GB/GPU
- **进度**: ~iter 4130/40000, LR=2.5e-6 稳态
- **work_dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt`
- **ETA @40000**: ~03/16 21:30

---

## Eval 结果

| 指标 | @2000 (07:19) | @4000 (11:17) | 趋势 | ORCH_024 @4000 |
|------|--------------|--------------|------|----------------|
| ped_R | 0.7646 | **1.0000** | ⬆️ | — |
| car_R | 0.000 | 0.000 | — | 0.419 |
| 其他 8 类 | 全 0 | 全 0 | — | — |
| bg_FA | 0.921 | **1.000** | 🔴🔴 | 0.199 |
| off_cx | 0.309 | **0.279** | ✅ | 0.039 |
| off_cy | 0.146 | **0.193** | 🔴 | 0.097 |
| off_w | 0.087 | **0.084** | ✅ | 0.016 |
| off_h | 0.038 | 0.038 | — | 0.005 |
| off_th | 0.192 | **0.280** | 🔴🔴 | 0.150 |

### ⚠️ Marker Saturation Collapse
- bg_FA=1.0: 模型将所有 cell 预测为正样本
- ped_R=1.0 + ped_P=0.0043: 全正导致碰巧覆盖所有 GT ped
- off_th 0.19→0.28, off_cy 0.15→0.19 恶化
- off_cx 0.31→0.28, off_w 0.09→0.08 有微弱改善

### 决策: CONDITIONAL PROCEED to @6000 (ABSOLUTE FINAL)
- @6000 条件: bg_FA<0.95 且 offset 至少 2/5 改善 → 否则 STOP

---

## @6000 ABSOLUTE FINAL (~03/15 17:00)

### 停止条件 (任一满足即 STOP):
1. bg_FA ≥ 0.95
2. offset 全面恶化 (5/5 都比 @4000 差)
3. car_R 仍为 0 且 offset 无改善

### 继续条件 (需全部满足):
1. bg_FA < 0.95 (模型开始区分正/负)
2. offset 至少 2/5 改善
3. 或 car_R > 0

---

## Agent 状态
- conductor: 活跃
- supervisor: 过期 (03/13)
- critic: ⚠️ 无响应 (03/09), AUDIT_REQUEST 未取走
- admin: 过期 (03/15 02:00)
- ops: 正常

## 恢复指令
1. 读本文件 + `conductor_state_archive_20260315.md`
2. `ps aux | grep train.py | grep yz0370` 确认训练存活
3. `strings .../nohup_multilayer_adapt.out | grep "Iter(train)" | tail -5`
4. 检查 `CEO_CMD.md`
5. @6000 后: 读 eval → 判定 STOP 或 PROCEED
