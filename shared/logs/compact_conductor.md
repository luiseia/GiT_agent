# Conductor 上下文快照
> 时间: 2026-03-15 02:20
> 原因: 上下文耗尽前保存

---

## 当前状态: 多层 ViT-L 训练运行中 (ORCH_044)

### 训练信息
- **Config**: `configs/GiT/plan_full_nuscenes_large_v1.py`
- **架构**: GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen **多层 [5,11,17,23]**
- **投影**: 4×1024=4096 → 2048 → GELU → 1024
- **权重来源**: iter_6000.pth (P2+P3 单层训练), `resume=False` (从 iter_0 重新计数)
- **GiT commit**: `14ff4a0`
- **PID**: 1626949, GPU 0,2 (2×A6000), ~34GB/GPU
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/20260315_015348/*.log`
- **当前进度**: ~iter_200, LR warmup 中
- **ETA**: ~3.4 天
- **effective batch**: 2×2×4 = 16

### 关键 Config 参数
- `online_dinov3_layer_indices=[5, 11, 17, 23]` (4层拼接, DINOv3 内部 LN)
- `online_dinov3_unfreeze_last_n=0` (冻结)
- `preextracted_proj_hidden_dim=2048` + `preextracted_proj_use_activation=True`
- `clip_grad=dict(max_norm=10.0, norm_type=2)`
- `max_class_weight=3.0`
- val@2000

### 初始 Loss (多层)
- iter 10-40: loss 12~18 (cls 10~16, reg 1.7~2.2)
- iter 200: loss 40 (spike, 正常波动)
- 比 P2+P3 单层初始 (24~52) 更低

---

## 本轮关键成果

### ⭐⭐⭐ P2+P3 修复确认有效 (@6000 eval, 2026-03-15 01:26)
| 指标 | @6000 P2+P3 | @6000 旧 (无P2+P3) | ORCH_024 @6000 |
|------|-------------|-------------------|---------------|
| **car_R** | **0.582** | 0.000 | 0.455 |
| bg_FA | 0.680 | 0.025 | 0.331 |
| off_cx | 0.249 | 0.273 | 0.056 |
| off_cy | 0.125 | 0.081 | 0.082 |
| off_w | 0.087 | 0.041 | 0.038 |
| off_h | 0.012 | 0.023 | 0.011 |
| off_th | 0.254 | 0.094 | 0.169 |

**结论**: car_R 从 0 → 0.582, frozen predictions 完全消除。bg_FA 高 (0.680) 但模型在学习。

### TF vs AR 诊断 (2026-03-14 19:22)
- Teacher Forcing ≈ Autoregressive (差异<1%, 1200/1200 slots 全正, 2/10 类)
- **不是 exposure bias, 是位置信息缺失 (P2) + 单步特征注入 (P3)**
- P4 (scheduled sampling) 在当前阶段无意义, 延后

### P2+P3 代码修复 (commit `d9d7f7d`)
- **P2**: `git.py:334` — occ 任务注入 position embedding (去掉 mode skip)
- **P3**: `git_occ_head.py` — 去掉 `pos_id == 0` 限制, 每步注入 grid_token + image_interp_feats
- **推理对称修复**: layer_id>0 重注入 grid_token (匹配训练路径 get_grid_feature)

---

## 待办

### 近期 (本轮训练)
1. **@2000 eval** (~05:00 03/15) — 多层 ViT-L 首个 eval
2. **@4000 eval** (~09:00 03/15) — 关键验证点, 多层 vs P2+P3 单层 @6000 对比
3. **签发 Critic 审计** — @4000 后, 使用更新后的 critic_cmd.md (含 6B 健康检查)

### 决策树 (@4000 多层)
```
多层 ViT-L @4000:
├─ car_R > 0.5 + offset 改善 → PROCEED (多层有效)
├─ car_R > 0 + offset 持平 → CONDITIONAL (继续到 @8000)
├─ car_R = 0 → 投影层未收敛, 继续到 @6000 再决策
└─ 前提: Critic 审计 (含新增预测健康检查)
```

### 未来改进 (按优先级)
- **P4** Scheduled Sampling — 延后, 当前不紧急
- **BUG-64** BERT-large 预训练权重 — 分类器收敛加速
- **Phase 5** BEV 坐标 Positional Encoding — CEO 计划中

---

## ORCH 状态 (活跃)
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_043 | P2+P3 修复后从 iter_4000 重启 | ✅ COMPLETED — @6000 car_R=0.582 |
| ORCH_044 | 多层 ViT-L + LN + 投影 | ✅ COMPLETED — PID 1626949, commit `14ff4a0` |

---

## Critic 命令已更新
- 新增 **6B 预测健康度量化检查** (commit `d93fe1f`):
  - Marker 饱和度 (1200 全正 = 🔴)
  - 过检比 (det/GT > 50x = 🔴)
  - 类别多样性 (≤2类 = 🔴)
  - 自回归有效性 TF vs AR (差异<1% = 🔴)
- `test_teacher_forcing_inference.py` 已修复 (commit `338ecfc`)
- critic_cmd.md 通用化 (去掉硬编码 ID)

---

## 关键文件路径
- Config: `configs/GiT/plan_full_nuscenes_large_v1.py`
- 多层训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/20260315_015348/`
- P2+P3 单层训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/20260314_193422/`
- Checkpoints: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/`
- CEO 指令记录: `shared/logs/ceo_directive_multilayer_vitl.md`
- MASTER_PLAN: `MASTER_PLAN.md`
- Critic 命令: `shared/commands/critic_cmd.md`
- TF 诊断脚本: `GiT/scripts/test_teacher_forcing_inference.py`
- 可视化脚本: `GiT/scripts/visualize_pred_vs_gt.py`

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整历史
3. 检查多层训练进度: `grep "Iter(train)" /mnt/SSD/.../20260315_015348/*.log | tail -5`
4. 检查 CEO_CMD.md
5. 按 Phase 1/Phase 2 循环继续监控
6. @2000 eval 后对比 P2+P3 单层 @6000 结果
