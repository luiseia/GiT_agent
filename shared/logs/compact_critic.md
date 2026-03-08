# Critic 上下文压缩 — 2026-03-07

## 当前状态: 空闲 (P5_MID 审计刚完成)

## 已完成的判决 (全部已 git push)
| 判决 | 结论 | Commit | 位置 |
|------|------|--------|------|
| VERDICT_P2_FINAL | CONDITIONAL | 208251b | processed/ |
| VERDICT_ARCH_REVIEW | CONDITIONAL | 94145e6 | pending/ |
| VERDICT_P3_FINAL | CONDITIONAL | 978a8a3 | pending/ |
| VERDICT_P4_FINAL | CONDITIONAL | b076fa0 | pending/ |
| VERDICT_3D_ANCHOR | CONDITIONAL | 91443d4 | audit/ (根目录) |
| VERDICT_P5_MID | CONDITIONAL | ba27c27 | pending/ |

## 审计目录结构 (已重组)
```
shared/audit/
├── requests/    ← AUDIT_REQUEST 文件
├── pending/     ← VERDICT 文件 (等待 Conductor)
├── processed/   ← 已归档
```

## BUG 状态总表
| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-1 | 中 | FIXED | theta_fine periodic=False |
| BUG-2 | 致命 | FIXED | per-class bg 梯度压制 (BUG-8 修复后完整) |
| BUG-3 | 高 | FIXED | score 传播链 |
| BUG-8 | 高 | FIXED | cls loss bg_cls_mask (Focal+CE 双路径) |
| BUG-9 | 致命 | FIXED (P2+P3+P4+P5) | clip_grad max_norm=10.0 |
| BUG-10 | 高 | FIXED (P3+) | 500步 linear warmup |
| BUG-11 | 中 | FIXED | classes 默认值改 None |
| BUG-12 | 高 | FIXED | cell 内 class-based 匹配 |
| BUG-13 | LOW | 暂不修 | slot_class bg clamp |
| BUG-14 | MEDIUM | 架构层 | grid token 与 image patch 冗余 |
| BUG-15 | HIGH | OPEN | Precision 瓶颈 (DINOv3 只用 Conv2d→P5 修但振荡) |
| BUG-16 | MEDIUM | 设计层 | 预提取特征与数据增强不兼容 |
| BUG-17 | HIGH | NEW | per_class_balance 在极不均衡数据下零和振荡 |

## 下一个 BUG 编号: BUG-18

## P5 关键数据 (供后续审计参考)
- Config: plan_h_dinov3_layer16.py
- 特征: PreextractedFeatureEmbed (DINOv3 Layer 16, Linear 4096→768)
- 起点: P4@500
- LR: 5e-5, warmup 1000, milestones [4000,5500] (实际 @5000 decay, @6500 不可达)
- bg_balance_weight=2.5, reg_loss_weight=1.5
- P5@4000 最佳: offset_th=0.142 (历史最佳), car_P=0.090
- P5 问题: bus/trailer 崩溃 (零和振荡), avg_P=0.040

## 训练代际谱系
```
P1 (plan_d) → P2 (plan_e, BUG-9 fix) → P3 (plan_f, BUG-8+10 fix)
→ P4 (plan_g, AABB fix + BUG-11) → P5 (plan_h, DINOv3 Layer 16)
→ P5b (待定: 修正 milestones + BUG-17 fix)
```

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST (无对应 pending/VERDICT)
3. 有则审计，无则休眠
