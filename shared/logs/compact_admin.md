# Admin Agent 上下文快照
- **时间**: 2026-03-15 23:15
- **当前任务**: ORCH_046/047 已完成，等待 CEO 新指令

---

## 最新结果: ORCH_047 @500 Frozen Check

```
Checkpoint: iter_500.pth
Avg positive slots: 1200/1200 (100.0%)
Positive IoU: 1.0000
Marker same rate: 1.0000
Coord diff: 0.008062
VERDICT: 🔴 FROZEN PREDICTIONS DETECTED
```

**所有验收标准 FAIL** — 尽管 loss 降 15x (11→15 vs ORCH_045 的 172)，模型仍 100% mode collapse。

### 可能根因
1. BUG-45: 推理缺少 causal attention mask (训练/推理不一致)
2. 架构问题: 解码器过度依赖位置编码
3. @500 太早: 模型可能需要更多迭代来学习 input-dependent 预测

---

## 已完成任务

### ORCH_046 (COMPLETED)
- BUG-69 fix: adapt_layers lr_mult=1.0 ✅
- BUG-62 fix: clip_grad=50 ✅
- bert-large: CEO 外部完成 ✅
- BEV augmentation: 转 ORCH_047
- BUG-45 (causal mask): 未执行
- GiT commits: `db4bd08`, `92c79ca`

### ORCH_047 (COMPLETED)
- RandomFlipBEV + GlobalRotScaleTransBEV: 实现 ✅
- 验证脚本: 几何正确性确认 ✅
- 训练启动: 初始指标极好 ✅
- @500 frozen check: **FAIL** (IoU=1.0, saturation=100%)
- 训练在 val 1060/1505 被 SIGTERM 终止
- GiT commit: `3fc2e3e`
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch047`

---

## 关键技术状态

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: 层 [5,11,17,23] → 4096 → 2048 → GELU → 1024
- 2 层 PreLN Transformer adaptation (25.2M, lr=5e-05)
- bert-large embedding (1024-dim, pretrained)
- token_drop_rate=0.3, clip_grad=50
- RandomFlipBEV(0.5) + GlobalRotScaleTransBEV(±22.5°, 0.95-1.05)

### GPU 共享
- GPU 0,2: 当前空闲 (训练已终止)
- GPU 1,3: yl0826 PETR 训练 (~31 GB)

---

## 历史 val 数据

| iter | config | car_R | bg_FA | frozen? | 备注 |
|------|--------|-------|-------|---------|------|
| @2000 | 原始 | 0.000 | 0.002 | N/A | 全 bg |
| @4000 | 原始 | 0.000 | 0.115 | N/A | 开始预测 occupied |
| @6000 | +BUG fixes | 0.000 | 0.025 | N/A | 修复后更保守 |
| @6000 | +P2+P3 | **0.582** | 0.680 | N/A | car 突破 |
| ORCH_045 @2000 | +adapt+token_drop | 0.000 | 0.921 | yes | BUG-69 致 adapt 不学习 |
| **ORCH_047 @500** | +all fixes+augment | N/A | N/A | **YES** | IoU=1.0, 1200/1200 饱和 |

---

*Admin Agent 上下文快照 | 2026-03-15 23:15*
