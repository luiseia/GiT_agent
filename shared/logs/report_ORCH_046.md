# ORCH_046 执行报告

- **状态**: COMPLETED (部分执行，后续被 ORCH_047 接管)
- **执行者**: Admin Agent
- **时间**: 2026-03-15 17:45 — 20:31

## 执行内容

### 已完成
1. **BUG-69 修复**: `paramwise_cfg.custom_keys` 中添加 `'backbone.patch_embed.adapt_layers': dict(lr_mult=1.0)` 和 `'backbone.patch_embed.adapt_norm': dict(lr_mult=1.0)`
   - 确认 adaptation layers 实际 lr = 5e-05 (之前被 backbone lr_mult=0.05 覆盖为 2.5e-06)
2. **BUG-62 修复**: `clip_grad=dict(max_norm=50.0, norm_type=2)` (之前 10.0)
3. **v1 训练启动** (bert-base): 正常运行，iter 1140 被 CEO SIGTERM 终止

### CEO 外部修改 (非本 Agent 执行)
4. **BUG-64**: bert-base → bert-large (hidden_size=1024, pretrain_path=bert_embed_large.pt)
5. **val_interval**: 2000 → 500
6. **v2 训练启动** (bert-large): CEO 另起，初始 loss 15 vs v1 的 177 (10x 改善)

### 未完成 (被 ORCH_047 接管)
- **BEV 空间增强** (RandomFlipBEV, GlobalRotScaleTransBEV): → ORCH_047
- **BUG-45** (推理 causal attention mask): 未实施

## GiT Commits
- `db4bd08` — config: fix BUG-69 adapt_layers lr_mult=1.0 + BUG-62 clip_grad=50 (ORCH_046)
- `92c79ca` — config: val_interval=500, checkpoint=500, bert-large with pretrain weights (CEO)

## 验证
- adapt_layers lr = 5e-05 ✅ (训练日志确认)
- 初始 loss 大幅下降 (15 vs 172 @ ORCH_045) ✅
- v1 和 v2 均被外部终止，未到 @500 val

## 备注
ORCH_046 原计划包含 6 项修改，实际完成了核心的 BUG-69/62 修复。BEV 增强和 BUG-45 被拆分到 ORCH_047。bert-large 切换由 CEO 直接修改 config 完成。
