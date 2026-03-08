# Critic 上下文压缩 — 2026-03-07

## 当前状态: DIAG_RESULTS 审计完成 (2026-03-08)

## 已完成的判决 (全部已 git push)
| 判决 | 结论 | Commit | 位置 |
|------|------|--------|------|
| VERDICT_P2_FINAL | CONDITIONAL | 208251b | processed/ |
| VERDICT_ARCH_REVIEW | CONDITIONAL | 94145e6 | pending/ |
| VERDICT_P3_FINAL | CONDITIONAL | 978a8a3 | pending/ |
| VERDICT_P4_FINAL | CONDITIONAL | b076fa0 | pending/ |
| VERDICT_3D_ANCHOR | CONDITIONAL | 91443d4 | audit/ (根目录) |
| VERDICT_P5_MID | CONDITIONAL | ba27c27 | pending/ |
| VERDICT_INSTANCE_GROUPING | CONDITIONAL | 81e231c | processed/ |
| VERDICT_P5B_3000 | CONDITIONAL | b6a9717 | processed/ |
| VERDICT_P6_ARCHITECTURE | CONDITIONAL | 4c5aa24 | pending/ |
| VERDICT_P5B_3000 (re-issue) | CONDITIONAL | 4cfc0d1 | pending/ |
| VERDICT_DIAG_RESULTS | CONDITIONAL | f457807 | pending/ |

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
| BUG-18 | MEDIUM | 设计层 | 评估未跨 cell 关联 GT instance (box_idx 存在但未用) |
| BUG-19 | HIGH | FIXED | proj_z0 标签问题 (z center 偏移 + valid_mask) |
| BUG-20 | HIGH | 数据层 | bus 振荡根因是 nuScenes-mini 样本不足 (~120 标注) |
| BUG-21 | HIGH | **升级→BUG-30** | off_th 退化, GELU 损害方向特征 (三组实验交叉印证) |
| BUG-22 | HIGH | 已修正 | P5b 已用 10 类 config, P6 无词表不匹配 |
| BUG-23 | HIGH | 事实纠正 | 审计请求 GPU 显存信息错误 (实际 4×A6000 48GB) |
| BUG-24 | MEDIUM | OPEN | 缺少单类 car 诊断 config |
| BUG-25 | HIGH | OPEN | 无在线 DINOv3 提取路径 (LoRA/unfreeze 前提) |
| BUG-26 | MEDIUM | OPEN | DINOv3 存储只需前摄 fp16 ~175GB (非 2.1TB) |
| BUG-27 | CRITICAL | NEW | Plan K vocab mismatch (230→221) 导致实验无效 |
| BUG-28 | HIGH | NEW | Plan L 双变量混淆 (投影宽度 + vocab 保留) |
| BUG-29 | LOW | 记录 | Plan K sqrt balance 对单类无意义 |
| BUG-30 | HIGH | OPEN | GELU 系统性损害 off_th (三组实验一致) |

## 下一个 BUG 编号: BUG-31

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
→ P5b (plan_i, 双层投影+sqrt+LR fix, P5@4000起点)
→ P6 诊断: Plan K(单类car,无效BUG-27) + Plan L(宽2048,car_P=0.140)
→ P6 Phase 0: 宽投影2048 + 10类 + 去GELU (待定)
→ P6 Phase 1: 根据诊断选择 全量nuScenes / LoRA
→ P7 (待定: 历史 occ box t-1)
```

## 恢复指引
1. git pull 两个仓库
2. 检查 shared/audit/requests/ 是否有新 AUDIT_REQUEST (无对应 pending/VERDICT)
3. 有则审计，无则休眠
