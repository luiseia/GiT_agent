# Conductor 上下文快照
> 时间: 2026-03-15 02:30
> 原因: 上下文耗尽前保存

---

## 当前状态: 多层 ViT-L 训练运行中 (ORCH_044)

### 训练信息
- **Config**: `configs/GiT/plan_full_nuscenes_large_v1.py` (commit `14ff4a0`)
- **架构**: GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen **多层 [5,11,17,23]**
- **投影**: 4×1024=4096 → 2048 → GELU → 1024
- **权重来源**: iter_6000.pth (P2+P3 单层训练), `resume=False` (从 iter_0 重新计数)
- **PID**: 1626949, GPU 0,2 (2×A6000), ~34GB/GPU
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/20260315_015348/*.log`
- **当前进度**: ~iter_290, LR warmup 中 (lr 3.6e-7, 目标 2.5e-6)
- **effective batch**: 2×2×4 = 16, val@2000
- **ETA**: ~3.4 天

### 关键 Config 参数
- `online_dinov3_layer_indices=[5, 11, 17, 23]` (4层拼接, DINOv3 内部 LN norm=True)
- `online_dinov3_unfreeze_last_n=0` (冻结)
- `preextracted_proj_hidden_dim=2048` + `preextracted_proj_use_activation=True`
- `clip_grad=dict(max_norm=10.0, norm_type=2)`
- `max_class_weight=3.0`, `filter_invisible=False`

### 初始 Loss (多层)
- iter 10-40: loss 12~18
- iter 200-290: loss 8~40 波动, cls 主导, reg 稳定 1.9~2.9
- 比 P2+P3 单层初始 (24~52) 更低

---

## 本轮关键成果 (时间线)

### 1. TF vs AR 诊断 (03/14 19:22)
- Large v1 @4k: TF ≈ AR (1200/1200 全正, car+barrier 两类, std=0.0)
- **结论: 不是 exposure bias, 是位置信息缺失 → P2+P3 是正确修复方向**
- P4 scheduled sampling 延后

### 2. P2+P3 代码修复 (commit `d9d7f7d`)
- **P2**: `git.py:334` — 去掉 `if self.mode != 'occupancy_prediction'`, occ 任务注入 position embedding
- **P3**: `git_occ_head.py` — 去掉 `pos_id == 0` 限制, 每步注入 grid_token + image_interp_feats
- **推理对称修复**: inference loop 中 layer_id>0 时重注入 grid_token (匹配训练路径)

### 3. ORCH_043: P2+P3 单层训练 (03/14 19:34 ~ 03/15 01:53)
- 从 iter_4000 resume, 2 GPU, clip_grad=10
- Loss 波动极大 (6~200), cls_loss 主导, 架构适应期

### 4. ⭐⭐⭐ @6000 eval — P2+P3 确认有效 (03/15 01:26)
| 指标 | @6000 P2+P3 | @6000 旧 (无P2+P3) | ORCH_024 @6000 |
|------|-------------|-------------------|---------------|
| **car_R** | **0.582** | 0.000 | 0.455 |
| bg_FA | 0.680 | 0.025 | 0.331 |
| off_cx | 0.249 | 0.273 | 0.056 |
| off_cy | 0.125 | 0.081 | 0.082 |
| off_w | 0.087 | 0.041 | 0.038 |
| off_h | 0.012 | 0.023 | 0.011 |
| off_th | 0.254 | 0.094 | 0.169 |

**car_R 从 0 → 0.582, frozen predictions 消除。bg_FA=0.680 偏高, offset 还需改善。**

### 5. ORCH_044: 多层 ViT-L 启动 (03/15 01:53)
- CEO 指令: frozen predictions 消失后实施多层 LN ViT-L
- 停单层训练 → 改 config (4层拼接+投影) → 从 iter_6000 权重加载 (resume=False)
- 训练正常运行中

---

## Critic 命令更新 (commit `d93fe1f`)
新增 **6B 预测健康度量化检查**:
- Marker 饱和度 (1200 全正 = 🔴)
- 过检比 (det/GT > 50x = 🔴)
- 类别多样性 (≤2类 = 🔴)
- 自回归有效性 TF vs AR (差异<1% = 🔴)
- 诊断脚本: `GiT/scripts/test_teacher_forcing_inference.py` (commit `338ecfc`)
- critic_cmd.md 已通用化 (去掉硬编码审计 ID)

---

## 待办

1. **@2000 eval** (~05:00 03/15) — 多层首个 eval
2. **@4000 eval** (~09:00 03/15) — 关键验证, 对比单层 @6000
3. **Critic 审计** — @4000 后签发
4. CEO 提问: 要不要跑可视化确认 @6000 没有 frozen predictions → 待 CEO 回复

### 决策树 (@4000 多层)
```
├─ car_R > 0.5 + offset 改善 → PROCEED
├─ car_R > 0 + offset 持平 → CONDITIONAL → @8000
├─ car_R = 0 → 投影层未收敛, 继续到 @6000
```

---

## ORCH 状态
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_043 | P2+P3 单层从 iter_4000 | ✅ @6000 car_R=0.582 |
| ORCH_044 | 多层 ViT-L + 投影 | ✅ PID 1626949, iter_290 运行中 |

## 关键文件
- Config: `configs/GiT/plan_full_nuscenes_large_v1.py`
- 多层日志: `.../20260315_015348/*.log`
- 单层日志: `.../20260314_193422/*.log`
- Checkpoints: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/`
- MASTER_PLAN: `MASTER_PLAN.md`

## 恢复指令
1. 读本文件 + MASTER_PLAN.md
2. `grep "Iter(train)" /mnt/SSD/.../20260315_015348/*.log | tail -5`
3. 检查 CEO_CMD.md → Phase 1/Phase 2 循环
4. @2000 后对比 P2+P3 单层 @6000 结果
