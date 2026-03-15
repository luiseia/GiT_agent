# Conductor 上下文快照
> 时间: 2026-03-15 03:25
> 原因: CEO 请求保存

---

## 当前状态: ORCH_045 多层 DINOv3 + 适应层 + Token Corruption 从零训练

### 训练信息
- **Config**: `configs/GiT/plan_full_nuscenes_large_v1.py` (commit `26b6f92`)
- **架构**: GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen **多层 [5,11,17,23]**
- **投影**: 4×1024=4096 → 2048 → GELU → 1024
- **适应层**: 2 层 PreLN TransformerEncoderLayer (25.2M 参数, trainable, nhead=16)
- **Anti-collapse**: `token_drop_rate=0.3` — 30% GT 输入被替换为随机 token
- **权重来源**: 从零训练 (load_from=None, SAM pretrained via init_cfg)
- **PID**: 1686388, GPU 0,2 (2×A6000), ~29GB/GPU
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/nohup_multilayer_adapt.out`
- **work_dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt`
- **当前进度**: ~iter_20, LR warmup 中
- **effective batch**: 1×2×8 = 16, val@2000
- **速度**: ~3.75 sec/iter
- **ETA**: ~1.8 天

### 关键 Config 参数
- `online_dinov3_layer_indices=[5, 11, 17, 23]` (4层拼接)
- `online_dinov3_num_adapt_layers=2` (适应层)
- `preextracted_proj_hidden_dim=2048` + `preextracted_proj_use_activation=True`
- `token_drop_rate=0.3` (anti-mode-collapse)
- `batch_size=1` + `accumulative_counts=8` (OOM 限制)
- `clip_grad=dict(max_norm=10.0, norm_type=2)`

### 初始 Loss
- iter 10: loss 172, cls 169, reg 3.4, grad_norm 6122
- iter 20: loss 162, cls 159, reg 3.3, grad_norm 6715
- 从零训练 loss 远高于之前 (预期行为 — 没有 collapsed 权重)

---

## 本轮关键突破: Frozen Predictions 根因确认 (03/15 02:37~03:05)

### 1. CEO 要求可视化 P2+P3 @6000 → 发现预测仍然 frozen
- BEV 可视化: 5 个样本的预测框在相同 BEV 位置, 不随场景变化
- 图片保存: `shared/logs/viz_p2p3_iter6000/`

### 2. 定量确认 frozen (smoking gun)
| 指标 | 值 | 含义 |
|------|-----|------|
| 每样本正样本数 | 1200/1200 | 所有 slot 全正 |
| 样本间 marker 相同率 | 93~98% | 几乎完全一样 |
| 正样本重叠 IoU | 1.0000 | 完全相同 slot 为正 |
| 坐标值 | `[0.29, 0.69, 0.116, 0.03, 0.0]` | **跨样本完全一致** |

### 3. 数据流追踪
- DINOv3 特征跨样本确实不同 (cos_sim≈0.995) ✅
- 但 decoder 输出 (bert_embed, synt_att) 跨样本完全相同 (diff=0.0) ❌
- **喂随机噪声 vs 全零图像 → 输出完全一样** (markers identical=True)
- **结论: 模型完全忽略视觉输入**

### 4. 之前推理错误纠正
- ❌ "TF≈AR → 位置信息缺失" → ✅ "TF≈AR → 完全 mode collapse"
- ❌ "car_R=0.582 → P2+P3 修复成功" → ✅ "frozen 位置碰巧和 GT 重叠的假象"
- ❌ "P2+P3 是正确修复方向" → ✅ "P2+P3 是必要条件但不充分, 根因是 TF mode collapse"

### 5. 修复方案
- **Token corruption** (`token_drop_rate=0.3`): 迫使模型依赖视觉特征
- **2 层 Transformer 适应层**: 让多层拼接特征有更好的融合
- **从零训练**: collapsed 权重不可修复
- 实现: `git.py` forward_transformer 中 input_seq 随机替换

---

## ORCH_044 已停止 (03/15 03:00)
- 原因: 基于错误前提 (P2+P3 修复了 frozen predictions)
- iter_440 已出现 reg_loss=0.0 (mode collapse 症状)
- 已 kill PID 1626949

---

## 待办

1. **@2000 eval** (~03/15 ~11:00) — 首次检查 mode collapse
   - 使用 `scripts/check_frozen_predictions.py` 自动诊断
   - 同时用 `scripts/visualize_pred_vs_gt.py` 可视化
2. **@4000 eval** — 如果 @2000 健康, 继续观察
3. **决策树 (@2000)**:
   ```
   ├─ FROZEN (IoU>0.95, saturation>0.9) → token_drop_rate 不够, 增大或换策略
   ├─ PARTIAL (IoU 0.5~0.95) → 有改善但不够, 考虑增大 drop_rate
   ├─ HEALTHY (IoU<0.5, predictions vary) → PROCEED, 等 @4000 看指标
   ```

---

## ORCH 状态
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_043 | P2+P3 单层从 iter_4000 | ✅ @6000 但仍 frozen (假象) |
| ORCH_044 | 多层 ViT-L + 投影 (无 anti-collapse) | ❌ 已停止, 前提错误 |
| ORCH_045 | 多层+适应层+token corruption 从零 | 🔄 PID 1686388, iter_20 运行中 |

## 关键 Commits (GiT repo)
- `05d5138` — token corruption 实现 (git.py)
- `a69b64b` — 多层 DINOv3 + 2 适应层 (vit_git.py) + check_frozen_predictions.py
- `26b6f92` — batch_size=1 OOM fix

## 关键文件
- Config: `configs/GiT/plan_full_nuscenes_large_v1.py`
- 诊断脚本: `scripts/check_frozen_predictions.py`
- 可视化脚本: `scripts/visualize_pred_vs_gt.py`
- frozen 可视化结果: `shared/logs/viz_p2p3_iter6000/`
- work_dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt`

## 恢复指令
1. 读本文件
2. `ps aux | grep train.py | grep yz0370` — 确认 PID 1686388 存活
3. `grep "Iter(train)" /mnt/SSD/GiT_Yihao/Train/Train_20260315/nohup_multilayer_adapt.out | tail -5`
4. @2000 后运行: `CUDA_VISIBLE_DEVICES=0 python scripts/check_frozen_predictions.py --config configs/GiT/plan_full_nuscenes_large_v1.py --checkpoint <ckpt> --out-dir shared/logs/viz_orch045_2000`
5. 检查 CEO_CMD.md → Phase 1/Phase 2 循环
