# Admin Agent 上下文快照
- **时间**: 2026-03-15 23:05
- **当前任务**: ORCH_046/047 执行中，@500 val 等待结果

---

## 当前训练状态

### ORCH_047 训练 (当前运行)
- **Config**: `plan_full_nuscenes_large_v1.py`
- **架构**: 多层 ViT-L [5,11,17,23] + 2层 adaptation + 投影 4096→2048→GELU→1024
- **新增**: RandomFlipBEV + GlobalRotScaleTransBEV 空间增强
- **关键修复**: BUG-69 (adapt_layers lr_mult=1.0) + BUG-62 (clip_grad=50) + bert-large embedding
- **训练**: 从零, load_from=None, batch_size=1, accum=8, effective=16
- **GPU**: 2×A6000 (GPU 0,2), ~29 GB/GPU
- **速度**: ~3.8 sec/iter (train), ~10 sec/iter (val)
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_orch047`
- **日志**: `.../nohup_orch047.out`
- **进度**: @500 val 进行中 (1020/1505)，预计 00:25 CDT 出结果
- **GiT commit**: `3fc2e3e`

### ORCH_047 训练初始指标 (极好)
```
Iter 10: loss=11.35  cls=7.95  reg=3.41  grad_norm=290
Iter 50: loss=15.15  cls=11.77  reg=3.39  grad_norm=352
```
对比 ORCH_045 (无 BUG-69 修复): loss=172, grad_norm=6122 → **loss 降 15 倍，grad_norm 降 20 倍**

---

## 本 Session 执行记录

### ORCH_044 (被 CEO 终止)
- 多层 ViT-L 训练，在 iter 450 被 SIGTERM 终止
- CEO 另起 ORCH_045 (token corruption + adaptation layers)

### ORCH_045 (另一个 Agent 执行)
- @2000 val: 除 pedestrian (R=0.76, P=0.004) 外全 0, bg_FA=0.92
- Loss 极高不收敛 (63-447 @ iter 6000+), grad_norm 400-6000
- **根因**: BUG-69 — adapt_layers 被 backbone lr_mult=0.05 覆盖，实际 lr 只有 2.5e-6

### ORCH_046 (本 Agent 执行)
- **修复**: BUG-69 adapt_layers lr_mult=1.0 + BUG-62 clip_grad=50
- v1 训练 (bert-base): 启动后被 CEO 终止于 iter 1140，改用 bert-large
- v2 训练 (bert-large): CEO 另起，val_interval=500
- 初始 loss 大幅改善: 15 (bert-large) vs 177 (bert-base)

### ORCH_047 (本 Agent 执行, 当前运行)
- **新增代码**: `mmdet/datasets/pipelines/bev_augmentation.py`
  - `RandomFlipBEV`: 水平翻转 + 相机参数调整，保持投影一致
  - `GlobalRotScaleTransBEV`: Z轴旋转 + 缩放，相机外参同步调整
- 验证脚本确认增强正确 (对象数不变，BEV 标签正确变换)
- 训练初始指标极好 (loss 11-15, grad_norm 243-352)

---

## ORCH 046/047 验收标准

### ORCH_046 (@2000):
1. bg_FA < 0.7 (vs ORCH_045 的 0.92)
2. 非 frozen predictions (IoU < 0.9)
3. adapt_layers lr = 5e-05 ✅ (已确认)

### ORCH_047 (@500):
1. Positive IoU < 0.95
2. Marker same rate < 0.90
3. 不得出现 1200/1200 全正饱和
4. 需运行 `check_frozen_predictions.py`

---

## 关键技术细节 (当前架构)

- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: 层 [5,11,17,23] → concat 4096 → 投影 2048 → GELU → 1024
- 2 层 PreLN Transformer 适应层 (25.2M params, trainable, lr=5e-05)
- bert-large embedding (1024-dim, pretrain_path=bert_embed_large.pt)
- token_drop_rate=0.3 (anti-mode-collapse)
- clip_grad=50, max_class_weight=3.0, filter_invisible=False
- RandomFlipBEV(flip_ratio=0.5) + GlobalRotScaleTransBEV(rot=±22.5°, scale=0.95-1.05)
- val_interval=500, checkpoint_interval=500

### GPU 共享
- GPU 0,2: 我们的训练 (~29 GB)
- GPU 1,3: yl0826 PETR 训练 (~31 GB)

---

## 历史 val 数据

| iter | config | car_R | bg_FA | 备注 |
|------|--------|-------|-------|------|
| @2000 | 原始 | 0.0000 | 0.0020 | 全 bg |
| @4000 | 原始 | 0.0000 | 0.1147 | 开始预测 occupied |
| @6000 | +BUG fixes | 0.0000 | 0.0247 | 修复后更保守 |
| @6000 | +P2+P3 | **0.5824** | 0.6804 | **car 突破** |
| ORCH_045 @2000 | +adapt+token_drop | 0.0000 | 0.9208 | BUG-69 致 adapt 层不学习 |
| ORCH_047 @500 | +BUG-69+bert-large+augment | ??? | ??? | **等待结果** |

---

*Admin Agent 上下文快照 | 2026-03-15 23:05*
