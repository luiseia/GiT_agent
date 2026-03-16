# Admin Agent 上下文快照
- **时间**: 2026-03-16 13:46
- **当前任务**: ORCH_058 执行中 — marker_no_grid_pos 训练运行中 (2-GPU DDP)

---

## 当前训练状态

### ORCH_058 / ORCH_057 (当前运行)
- **核心改动**: `marker_no_grid_pos=True` — marker step (pos_id%10==0) 不加 grid_pos_embed
- **Config**: bg=5.0, marker_pos_punish=1.0, lr=5e-5 (ORCH_055 基线), marker_no_grid_pos=True
- **训练**: 2-GPU DDP (GPU 2,3), memory=28881-28882, master_port=29511
- **Work dir**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/full_nuscenes_large_v1_orch057`
- **日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/nohup_orch057.out`
- **GiT commit**: `54aa79e` (代码 `0566568`, 脚本 `54aa79e`)
- **启动时间**: 13:41 CDT, 从 scratch 开始
- **当前进度**: iter 30 at 13:45, loss 10.5→4.9 (下降中, reg_loss=1.93 说明有正预测)
- **Auto-check**: @100/@200/@300/@400/@500, 三重早停 (IoU>0.95 OR marker_same>0.95 OR sat>0.95)
- **Auto-check 日志**: `/mnt/SSD/GiT_Yihao/Train/Train_20260316/auto_frozen_check_057.log`
- **ETA**: @100 ~13:55, @200 ~14:09, @500 ~14:50

### 初步信号 (积极)
- iter 10: loss=10.57 (cls=8.61, reg=1.95) — 比 ORCH_055 iter 10 高, 预期中 (marker 失去空间先验)
- reg_loss 从一开始就非零 (1.95→3.45→1.93) — 比 ORCH_056 (reg=0.0 from iter 140) 好很多
- 模型在积极学习, 不是静默崩塌

### GPU 共享状况
- **GPU 0,1**: xg0091 StreamPETR
- **GPU 2,3**: 我们的 ORCH_057 训练 (~28881 MiB each)
- **GPU 3**: + yl0826 PETR (~14 GB)

---

## ORCH_058 代码修改摘要

### 训练路径 (`git.py`)
- L50,88: 新增 `marker_no_grid_pos` 参数
- L354: 保存 `grid_pos_embed_raw`
- L385: 传递到 `transformer_inputs_dict`
- L393: `forward_transformer` 新增 `grid_pos_embed_raw` 参数
- L514-518: gather `select_grid_pos_embed_raw`
- L559: 传递给 `get_grid_feature`
- L639-652: `get_grid_feature` — layer_id==0 减去 grid_pos_embed_raw, layer_id>0 用 (grid_start_embed - grid_pos_embed_raw)

### 推理路径 (`git_occ_head.py`)
- L1068: `decoder_inference` 新增 `grid_pos_embed_raw` 参数
- L1119-1131: pos_id%10==0 时用 `(grid_token - grid_pos_embed_raw)` 替代 `grid_token`

### Config (`plan_full_nuscenes_large_v1.py`)
- L192: `marker_no_grid_pos=True`
- L377: lr 恢复为 5e-5 (从 ORCH_056 的 1e-5)

---

## ORCH_056 关键结果 (本 session)

### 实验 B: lr=1e-5 Resume (FAIL)
- @200: sat=0.998, marker_same=0.999, TP=177 → EARLY STOP (全正饱和)
- 降低 LR 加速全正饱和, 假设被推翻

### 实验 A: iter_100 Full Eval (COMPLETED)
- 所有主要类别 recall=0 (car/truck/bus/ped 全零)
- traffic_cone: recall=0.59, precision=0.0007 (每个正确预测对应 ~1400 误报)
- bg_FA=0.6181
- **结论**: "健康点" @100 在 full eval 下也是严重模板化状态

---

## ORCH_055 崩塌轨迹 (参考)

| iter | Pos slots | IoU | marker_same | sat | TP |
|------|-----------|-----|-------------|-----|-----|
| 100 | 750 (63%) | 0.853 | 0.887 | 0.703 | 109 |
| 200 | 954 (80%) | 0.954 | 0.963 | 0.820 | 147 |
| 300 | 1010 (84%) | 0.968 | 0.973 | 0.873 | 150 |
| 400 | 71 (6%) | 0.780 | 0.984 | 0.080 | 0 |
| 500 | 158 (13%) | 0.910 | 0.988 | 0.142 | 12 |

---

## Critic 审计关键结论 (VERDICT_ORCH057_MARKER_NO_POS)

- grid_pos_embed 是 marker 模板化的唯一根因, 已被 ORCH_049-056 反复确认
- BUG-79: 训练/推理路径 grid_token 注入方式不对称 (attention vs 直接加法)
- 实现时训练和推理都必须对称处理 marker_no_pos
- diff/Margin @100=54.6% → @500=4.2%, 13x 下降证明 mode collapse

---

## ORCH_057 待完成事项

1. ✅ 代码修改 + commit + push
2. ✅ 训练启动 (2-GPU DDP 确认)
3. ✅ Auto-check 脚本运行中
4. ⏳ @100 frozen check (ETA ~13:55) — 关键: marker_same 是否 < 0.887
5. ⏳ @200 frozen check (ETA ~14:09) — 如 marker_same < 0.95 → "首次 @200 HEALTHY"
6. ⏳ @300/@400/@500 frozen check
7. ⏳ 写完成报告 report_ORCH_058.md
8. ⏳ 更新 ORCH_057/058 状态为 COMPLETED

---

## 磁盘状态
- /mnt/SSD: 39 GB 可用 (清理了 055 iter_200-500 + 056 iter_200, 保留 055 iter_100)
- 5 个 checkpoint × 5.7GB = 28.5GB, 空间足够

---

*Admin Agent 上下文快照 | 2026-03-16 13:46*
