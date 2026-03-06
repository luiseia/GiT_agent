# critic 紧急休眠报告

- **时间**: 2026-03-06
- **触发方式**: CEO 手动指令

## 当前审计状态

无正在进行的审计。最近两轮循环检查 `shared/audit/` 均未发现 `AUDIT_REQUEST_*.md` 文件。

## 未写入的 BUG

无。本次会话未执行任何审计，无新发现。

## 已知未修复 BUG（来自 CLAUDE.md 历史记录，非本次发现）

| BUG | 严重性 | 状态 | 描述 |
|-----|--------|------|------|
| BUG-8 | 高 | UNPATCHED | cls loss 缺 bg_balance_weight (git_occ_head.py:871-881) |
| BUG-9 | 致命 | UNPATCHED | 100% 梯度裁剪 (clip_grad max_norm=0.5, 梯度实测 3.85-59.55) |
| BUG-10 | 高 | UNPATCHED | 优化器冷启动 (resume=False) |
| BUG-11 | 中 | UNPATCHED | 默认类别顺序地雷 (generate_occ_flow_labels.py:77) |
| BUG-12 | 高 | URGENT | 评估 slot 排序不一致 (occ_2d_box_eval.py) |

## 下次唤醒时的续接点

- 从第 3 轮循环开始
- BUG 编号从 BUG-13 起
- 无未完成判决需要补写
