# Admin Agent 上下文快照
- **时间**: 2026-03-15 02:00
- **当前任务**: 无待执行 ORCH，多层训练运行中

---

## 训练状态
- **Config**: `plan_full_nuscenes_large_v1.py` — 多层 ViT-L [5,11,17,23] + 投影 4096→2048→GELU→1024
- **训练运行中**: 从 iter 0 开始（load_from iter_6000 权重，resume=False 因架构变化）
- **PID**: 1626949
- **GPU**: 2×A6000 (GPU 0,2), ~34 GB/GPU。GPU 1,3 被 yl0826 PETR 训练占用 (~31 GB)
- **当前进度**: iter ~40/40000, warmup 阶段
- **速度**: ~7.2 sec/iter, ETA ~3.4 天
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1_multilayer.out`（有二进制字符，需用 `strings` 过滤）
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1`

---

## 关键里程碑

### P2+P3 修复验证 (@6000 val, ORCH_043)
```
car_R=0.5824  car_P=0.0170  (从 0 突破!)
bg_FA=0.6804  (过度预测 occupied, 学习中正常)
其他类: 全 0 (预期后续出现)
```
**结论**: P2+P3 (位置嵌入注入 + 每步图像特征) 是解决 frozen predictions 的关键

### ORCH_044 多层训练初始状态
```
Iter 10: loss=12.42  cls=10.73  reg=1.70  grad_norm=579
Iter 40: loss=12.44  cls=10.61  reg=1.83  grad_norm=304
```
投影层随机初始化，loss 比同位置单层低（多层特征信息更丰富）

---

## 近期 ORCH 完成记录
- ORCH_041: COMPLETED — score_thr 消融 @14000 (multilayer v4 训练)
- ORCH_042: COMPLETED — BUG-62/63/17 修复 (clip_grad/filter_invisible/max_class_weight)
- ORCH_043: COMPLETED — P2+P3 修复后从 iter_4000 重启 (car_R=0.58 突破)
- ORCH_044: COMPLETED — 多层 ViT-L 训练从 iter_6000 加载 (当前运行中)

---

## 关键技术细节

### 当前架构 (large_v1 + 多层)
- GiT-Large: 1024-dim, 30 layers (24 SAM + 6 new)
- DINOv3 ViT-L frozen: 层 [5,11,17,23] → concat 4096-dim → 投影 2048 → GELU → 1024
- P2: occ 任务接收 position embedding (git.py:334)
- P3: 每个解码步注入 grid_token + image_interp_feats (git_occ_head.py)
- clip_grad=10, max_class_weight=3.0, filter_invisible=False

### Eval 命令模板
```bash
source ~/anaconda3/etc/profile.d/conda.sh && conda activate GiT && cd ~/projects/GiT
CUDA_VISIBLE_DEVICES=0,2 python -m torch.distributed.launch --nproc_per_node=2 --master_port=29510 \
  tools/test.py configs/GiT/plan_full_nuscenes_large_v1.py \
  /mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1/iter_XXXX.pth \
  --launcher pytorch \
  --cfg-options test_evaluator.score_thr=0.0 resume=False test_dataloader.batch_size=1
```

### GPU 共享情况
- GPU 0,2: 我们的训练 (~34 GB)
- GPU 1,3: yl0826 PETR 训练 (~31 GB)，无法使用

---

## large_v1 历史 val 数据

| iter | config | car_R | bg_FA | 备注 |
|------|--------|-------|-------|------|
| @2000 | 原始 | 0.0000 | 0.0020 | 全 bg |
| @4000 | 原始 | 0.0000 | 0.1147 | 开始预测 occupied |
| @6000 | +BUG fixes | 0.0000 | 0.0247 | 修复后更保守 |
| @6000 | +P2+P3 | **0.5824** | 0.6804 | **car 突破!** |

---

*Admin Agent 上下文快照 | 2026-03-15 02:00*
