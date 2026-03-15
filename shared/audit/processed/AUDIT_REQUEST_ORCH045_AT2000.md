# AUDIT_REQUEST: ORCH_045 @2000 Frozen Prediction 诊断

- **签发时间**: 2026-03-15 05:35
- **优先级**: P0 — 关键决策节点
- **签发人**: claude_conductor

## 背景

ORCH_045 是多层 DINOv3 + 2 层适应层 + token_drop_rate=0.3 从零训练。
这是第一次引入 anti-mode-collapse 措施的训练，@2000 是首次健康检查。

### 已知风险
- reg_loss=0 出现 19/200 报告 = 9.5%，iter 1200 后加速至 ~24%
- 3 次出现 total loss=0 (cls+reg 全为 0)
- Loss 波动极大 (0→984→447→113)
- 所有 reg_loss=0 事件均反弹，非永久归零

### 之前的教训 (重要!)
- P2+P3 @6000 的 car_R=0.582 被误认为 "修复成功"，实际是 frozen predictions 假象
- 必须用 BEV 可视化 + check_frozen_predictions.py 确认预测多样性
- 检测数量不等于空间分布多样性

## 审计要求

### 1. 等待 Val 完成
Val 正在运行 (~07:20 完成)，完成后收集 eval 指标:
```bash
strings /mnt/SSD/GiT_Yihao/Train/Train_20260315/nohup_multilayer_adapt.out | grep -A 100 "Iter(val)" | tail -50
```

### 2. Frozen Prediction 诊断 (MANDATORY)
```bash
cd /home/UNT/yz0370/projects/GiT
source ~/anaconda3/etc/profile.d/conda.sh && conda activate GiT
CUDA_VISIBLE_DEVICES=0 python scripts/check_frozen_predictions.py \
  --config configs/GiT/plan_full_nuscenes_large_v1.py \
  --checkpoint /mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt/iter_2000.pth \
  --out-dir /home/UNT/yz0370/projects/GiT_agent/shared/logs/viz_orch045_2000
```

注意: 训练占用 GPU 0,2 (~29GB/GPU)。如果显存不足，等训练进入下一个 val interval 或用 GPU 2。

### 3. BEV 可视化 (MANDATORY)
```bash
CUDA_VISIBLE_DEVICES=0 python scripts/visualize_pred_vs_gt.py \
  --config configs/GiT/plan_full_nuscenes_large_v1.py \
  --checkpoint /mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt/iter_2000.pth \
  --out-dir /home/UNT/yz0370/projects/GiT_agent/shared/logs/viz_orch045_2000 \
  --num-samples 5
```

### 4. reg_loss=0 分析
检查 reg_loss=0 事件是否与特定训练样本关联 (数据问题) 还是模型行为 (mode collapse 前兆):
- reg_loss=0 时 cls_loss 通常也极低 (0.0~3.4) — 暗示无正样本匹配
- 与 token_drop_rate=0.3 + batch_size=1 的交互效应?

## 决策树

```
├─ FROZEN (IoU>0.95, saturation>0.9)
│   → VERDICT: STOP — token_drop_rate=0.3 不足以打破 mode collapse
│   → 建议: 增大 drop_rate 到 0.5 或换 scheduled sampling
│
├─ PARTIAL (IoU 0.5~0.95, 预测有一定变化)
│   → VERDICT: CONDITIONAL — 有改善但不够
│   → 建议: 继续到 @4000, 可考虑增大 drop_rate
│
├─ HEALTHY (IoU<0.5, 预测随场景变化)
│   → VERDICT: PROCEED — anti-collapse 有效
│   → 评估 eval 指标, 设定 @4000 预期
│
└─ 前提: 必须用 BEV 可视化确认, 不能仅看指标数值
```

## VERDICT 写入位置
`shared/audit/pending/VERDICT_ORCH045_AT2000.md`
