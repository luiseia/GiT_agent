# ORCH_043 Report: P2+P3 修复后从 iter_4000 重启训练

- **状态**: COMPLETED
- **执行时间**: 2026-03-14 19:33 ~ 19:40 CDT
- **PID**: 1444306

## 代码状态确认
```
338ecfc fix: TF vs AR diagnostic script
8ebd788 fix train/inference asymmetry: re-inject grid_token at layers 1+ in inference
b9d198c config: resume from iter_4000 with P2+P3 fixes
d9d7f7d P2+P3: inject position embedding and image features at every decoding step for occ
c416818 revert clip_grad to 10.0
```

## Config 确认
- clip_grad=10.0 ✓
- load_from=iter_4000.pth ✓
- resume=True ✓

## GPU 状态
- GPU 0,2: 空闲 → 用于训练 (~33 GB/GPU)
- GPU 1,3: yl0826 PETR 训练占用 (~31 GB/GPU)
- 使用 `CUDA_VISIBLE_DEVICES=0,2 --nproc_per_node=2`

## 训练启动验证

训练从 iter 4010 成功开始，日志输出到 `nohup_large_v1_p2p3.out`。

### 前 4 iter loss/grad_norm (P2+P3 修复后):
```
Iter 4010: loss=23.99  cls=22.15  reg=1.84  grad_norm=345.72
Iter 4020: loss=51.57  cls=49.20  reg=2.38  grad_norm=751.39
Iter 4030: loss=34.47  cls=32.65  reg=1.83  grad_norm=472.11
Iter 4040: loss=33.69  cls=31.96  reg=1.73  grad_norm=611.26
```

### 对比 ORCH_042 同位置 (无 P2+P3, iter 4010-4040):
```
Iter 4010: loss=25.05  cls=23.24  reg=1.82  grad_norm=198.25
Iter 4020: loss=48.24  cls=45.84  reg=2.39  grad_norm=690.08
```

### 结论
- **Loss 范围相似 (24-52)**，无剧烈跳变
- **grad_norm 略高** (346-751 vs 198-690)，合理范围内
- P2+P3 架构改动平滑过渡，optimizer state 兼容
- 预计 @6000 val 会是首次反映 P2+P3 效果的评估点

## 注意事项
- effective batch = 2×2×4 = 16（2 GPU）
- 速度 ~7.3 sec/iter，ETA ~3 天
- 日志有二进制字符（nohup + tqdm 输出），需用 `strings` 过滤
