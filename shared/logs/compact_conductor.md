# Conductor 上下文快照
> 时间: 2026-03-15 19:53
> 原因: ORCH_046_v2 @500 val 启动

---

## 当前状态: ORCH_046_v2 @500 val 运行中

### 修复内容 (全部生效)
- BUG-69: adapt lr_mult → 1.0 ✅
- BUG-62: clip_grad → 50.0 ✅
- BUG-64: bert-large + 预训练权重 ✅
- val_interval=500, checkpoint=500 ✅
- BEV RandomFlip: ❌ 未实现
- BUG-45 attn_mask: ❌ 未实现

### 训练观察 (iter 0-500)
- loss: 15→5-8 (vs ORCH_045 160-290 — 大幅改善)
- grad_norm: 50-340 (vs ORCH_045 3000-6700 — 一个数量级差异)
- reg_loss: 2.1-3.4 稳定, 无 reg_loss=0
- BERT-large 预训练 + BUG-69 修复效果显著

### @500 eval 预计 ~21:43
- 成功: bg_FA < 0.7, IoU < 0.9
- 失败: bg_FA ≥ 0.9, frozen

### VIS 已完成
- VIS/024_8k_old_inference ✅
- VIS/035_12k_old_inference ✅
- VIS/045_2k_new_inference ✅
- VIS/045_6k_new_inference ✅

### 恢复指令
1. 读本文件
2. `strings .../nohup_orch046_v2.out | grep "Iter(val) \[1505" | tail -1`
3. @500 eval 后判定 PROCEED 或 STOP
