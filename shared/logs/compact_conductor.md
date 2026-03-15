# Conductor 上下文快照
> 时间: 2026-03-15 18:17
> 原因: ORCH_046 训练中, context 消耗大

---

## 当前状态: ORCH_046 训练中, 等待 @2000 eval

### ORCH_046 修复内容 (部分执行)
| 修改 | 状态 |
|------|------|
| BUG-69: adapt lr_mult → 1.0 | ✅ 已修复 |
| BUG-62: clip_grad → 50.0 | ✅ 已修复 |
| BUG-64: bert-large 预训练 | ❌ Admin 未执行 |
| val_interval → 500 | ❌ Admin 未执行 (仍 2000) |
| RandomFlipBEV | ❌ Admin 未执行 |
| BUG-45: attn_mask | ❌ Admin 未执行 |

### 训练信息
- **PID**: 1897372 (rank0), GPU 0,2
- **work_dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch046`
- **日志**: `.../nohup_orch046.out`
- **进度**: ~iter 830/40000, val@2000
- **reg_loss**: 2.8-3.8 稳定, reg_loss=0 仅 1 次 (vs ORCH_045 同期 5 次)
- **grad_norm**: 1400-5300, clip=50 有效梯度 ~1-2%

### @2000 eval 预计 ~19:00
- 成功条件: bg_FA < 0.7, IoU < 0.9
- 失败条件: bg_FA ≥ 0.9, frozen predictions

### 待补充修复 (ORCH_046 未执行部分)
1. BUG-64: bert_embed → bert-large + `/home/UNT/yz0370/projects/GiT/bert_embed_large.pt`
2. RandomFlipBEV (BEV 空间增强) — CEO 要求必须做
3. BUG-45: decoder_inference attn_mask
4. val_interval → 500

### 恢复指令
1. 读本文件
2. `ps aux | grep train.py | grep yz0370` 确认训练存活
3. `strings .../nohup_orch046.out | grep "Iter(train)" | tail -5`
4. 检查 CEO_CMD.md
5. @2000 后读 eval → 判定 PROCEED 或 STOP
