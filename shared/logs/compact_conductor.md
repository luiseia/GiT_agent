# Conductor 上下文快照
> 时间: 2026-03-14 01:12
> 原因: CEO 请求上下文保存

## 当前状态

**GiT-Large + DINOv3 ViT-L 训练已启动** — PID 1169092, 4 GPU DDP

### 今日重大事件 (时间线)
1. **前一轮对话**: 诊断确认 mode collapse 根因 — 零数据增强 + teacher forcing
2. **本轮 00:30**: 修改 supervisor/critic/all_loops 加入训练质量健康检查
3. **本轮 00:45**: 创建 `plan_full_nuscenes_large_v1.py` (P0+P1)
4. **本轮 00:50**: DINOv3 ViT-L 权重下载 (1.2GB)
5. **本轮 01:05**: 杀掉 ORCH_035 训练 (mode collapse 确认, 无价值)
6. **本轮 01:08**: GiT-Large 训练启动成功
7. **01:10**: 首个 iter 输出: loss=144.6, memory=26.9GB/49GB, time=7.1s/iter

## ⭐ CEO 核心指示

1. **"解决frozen predictions优先级高于一切"** → P0+P1 已实施，训练已启动
2. **"在 ViT-L 上改 P0-P4"** → P0+P1 done, P2-P4 待实施
3. **"修改 critic/all_loops 更早发现问题"** → 已完成
4. **offset 指标优先** — 5个offset直接影响mIoU

## 训练详情

| 项目 | 值 |
|------|-----|
| Config | `configs/GiT/plan_full_nuscenes_large_v1.py` |
| Work dir | `/mnt/SSD/GiT_Yihao/Train/Train_20260314/full_nuscenes_large_v1` |
| 日志 | `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1.out` |
| 架构 | GiT-Large (1024-dim, 30 layers) + DINOv3 ViT-L frozen |
| 数据增强 | PhotoMetricDistortion (P0 fix) |
| train/test 分离 | ✅ (P0 fix) |
| batch | 2/GPU × 4 GPU × accumulative_counts=4 = effective 32 |
| iters | 40000 (≈11.4 epochs), val@2000 |
| 预计耗时 | ~3.3 天 |
| 显存 | 26.9GB/49GB per GPU |
| PID | 1169092 |

### 关键架构变化 (vs ORCH_024)
| 参数 | ORCH_024 (旧) | GiT-Large v1 (新) |
|------|--------------|-------------------|
| backbone | ViT-Base (768, 12+6层) | **ViT-Large (1024, 24+6层)** |
| DINOv3 | ViT-7B (4096) | **ViT-L (1024)** |
| 投影 | 4096→2048→GELU→768 | **1024→1024 Linear (无损)** |
| bert_embed | 768 | **1024** |
| 数据增强 | 无 | **PhotoMetricDistortion** |
| train=test | 是 (BUG) | **否 (修复)** |

## 待办

### 训练期间 (可并行)
- **P2**: 给 occ 任务加 position embedding
  - 位置: `git.py:334` — `if self.mode != 'occupancy_prediction': grid_pos_embed`
  - 改动: 去掉 occ 的排除条件
- **P3**: 每步注入 grid_interpolate_feats
  - 位置: `git_occ_head.py` decoder_inference 中 `if pos_id == 0` 限制
  - 改动: 去掉 pos_id==0 条件
- **P4**: Scheduled Sampling (较大改动)

### 训练到 iter_2000 时 (第一个 checkpoint)
- 运行 `diagnose_v3c_single_ckpt.py` 检查 diff/Margin 趋势
- 如果 diff/Margin > 之前的 7.9% → 数据增强生效
- 如果仍在下降 → 需要 P2+P3 代码改动

## Mode Collapse 诊断数据 (参考)
| Model | Checkpoint | diff/Margin | 预测相同率 |
|-------|-----------|------------|-----------|
| ORCH_024 | iter_4000 | 7.9% | 97.25% |
| ORCH_024 | iter_8000 | 8.7% | 98.00% |
| ORCH_024 | iter_12000 | 3.0% | 99.75% |
| ORCH_035 | iter_14000 | 2.3% | 99.75% |

## 监控系统升级 (已完成)
- `supervisor_cmd.md`: 预测多样性/loss-指标背离/config审查
- `all_loops.sh`: 自动健康检查 + RED告警自动签发紧急审计
- `critic CLAUDE.md`: 全链路特征流诊断清单
- `critic_cmd.md 模板`: 嵌入特征流诊断步骤 + 判定标准

## 关键文件索引
- Config: `GiT/configs/GiT/plan_full_nuscenes_large_v1.py`
- 训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1.out`
- DINOv3 ViT-L: `/mnt/SSD/yz0370/dinov3_weights/dinov3_vitl16_pretrain_lvd1689m.pth`
- 诊断脚本: `GiT/scripts/diagnose_v3_precise.py`, `diagnose_v3c_single_ckpt.py`
- 诊断报告: `GiT_agent/shared/logs/diagnosis_frozen_predictions.md`
- Memory: `diagnosis_mode_collapse.md`

## 恢复指令
1. 读取本文件恢复上下文
2. 检查训练进度: `tail -20 /mnt/SSD/GiT_Yihao/Train/Train_20260314/nohup_large_v1.out`
3. 检查 CEO_CMD.md
4. iter_2000 时运行特征流诊断验证数据增强效果
