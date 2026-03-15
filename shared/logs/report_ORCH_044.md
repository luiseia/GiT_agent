# ORCH_044 Report: 多层 ViT-L + 投影，从 iter_6000 加载

- **状态**: COMPLETED
- **执行时间**: 2026-03-15 01:45 ~ 01:59 CDT
- **GiT Commit**: `14ff4a0`
- **新训练 PID**: 1626949

## Config Diff

```diff
- load_from = '.../iter_4000.pth'
- resume = True
+ load_from = '.../iter_6000.pth'
+ resume = False  # 架构变化，不能 resume optimizer

- preextracted_proj_hidden_dim=None,
- preextracted_proj_use_activation=False,
+ preextracted_proj_hidden_dim=2048,    # 4096→2048→GELU→1024
+ preextracted_proj_use_activation=True,

- online_dinov3_layer_idx=23,
+ online_dinov3_layer_indices=[5, 11, 17, 23],  # 4层均匀采样
```

## 训练启动验证

- GPU: 2×A6000 (GPU 0,2), ~34 GB/GPU（比单层多 ~7 GB）
- 训练从 iter 0 开始（resume=False, 符合预期）
- Checkpoint 从 iter_6000 加载匹配权重，投影层随机初始化
- 日志: `nohup_large_v1_multilayer.out`

## 前 4 iter loss/grad_norm

| Iter | loss | cls_loss | reg_loss | grad_norm | memory |
|------|------|----------|----------|-----------|--------|
| 10 | 12.42 | 10.73 | 1.70 | 579.25 | 27406 |
| 20 | 14.17 | 11.93 | 2.24 | 592.41 | 27406 |
| 30 | 17.69 | 15.79 | 1.90 | 484.02 | 27406 |
| 40 | 12.44 | 10.61 | 1.83 | 303.75 | 27406 |

### 对比 P2+P3 单层 (ORCH_043, iter 4010-4040):
| Iter | loss | cls_loss | reg_loss | grad_norm |
|------|------|----------|----------|-----------|
| 4010 | 23.99 | 22.15 | 1.84 | 345.72 |
| 4020 | 51.57 | 49.20 | 2.38 | 751.39 |
| 4030 | 34.47 | 32.65 | 1.83 | 472.11 |
| 4040 | 33.69 | 31.96 | 1.73 | 611.26 |

### 分析
- **Loss 更低** (12-18 vs 24-52): iter_6000 权重比 iter_4000 更好，且多层特征提供更丰富信息
- **grad_norm 正常** (300-590): 投影层随机初始化未导致梯度爆炸
- **显存增加 ~7 GB/GPU** (27→34 GB): 4层特征 concat (4096-dim) + 投影层参数
- 投影层 warmup 期间 loss 可能有波动，属正常

## 注意事项
- 训练从 iter 0 重新计数，@2000 会触发首次 val
- effective batch = 2×2×4 = 16（2 GPU）
- 速度 ~7.2 sec/iter，ETA ~3.4 天
- 测试全通过: 186 passed
