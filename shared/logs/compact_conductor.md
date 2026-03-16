# Conductor 上下文快照
> 时间: 2026-03-16 12:00 CDT
> 原因: 长时间等待 ORCH_057 实现，保存上下文

---

## 当前状态

- **等待 Admin 实现 ORCH_057** — 架构变更: marker_step_no_pos
- **Critic 审计已通过**: VERDICT_ORCH057_MARKER_NO_POS = CONDITIONAL
- **iter_100 full eval 完成**: car_R=0, cone_R=0.588, bg_FA=0.618（@100 训练太少）
- **无训练运行中**

## ORCH_057 实现要点

核心: marker step (pos_id=0) 不加 grid_pos_embed，class/box 正常

Critic 推荐 "减法替代" 方案 (~20 行):
1. `git.py:L353` 后保存 `grid_pos_embed_raw`
2. 通过 `transformer_inputs_dict` 传递
3. 推理: `decoder_inference` 中 pos_id=0 时用 `grid_token - grid_pos_embed_raw`
4. 训练: `get_grid_feature` 中 grid_feature 位置 0 不含 grid_pos_embed
5. class/box token 额外加 grid_pos_embed
6. Config: `marker_no_grid_pos=True`

关键注意:
- BUG-79: 训练/推理路径不对称，两边都要改
- 必须 2-GPU DDP (BUG-78)
- 保持 bg=5.0, punish=1.0 (ORCH_049/055 配置)

## 实验全表

| ORCH | 干预 | 结果 |
|------|------|------|
| 049 | bg=5.0, FG/BG=1x | @200 TP=112 → @500 全阴性 |
| 050 | +dropout=0.5 | 全阴性 (BUG-77) |
| 051 | FG/BG=3.3x | 全正饱和 |
| 052 | FG/BG=1.67x | 全阴性 |
| 053/054 | 单GPU | 无效 (BUG-78) |
| 055 | 5点追踪 | @100 🟢HEALTHY(TP=109) → @300-400 相变 |
| 056 | 低 LR | 加速全正饱和 |
| **057** | **marker_no_grid_pos** | **待实现** |

## ORCH_055 崩塌轨迹

| iter | Sat | marker_same | TP | diff/Margin |
|------|-----|-------------|-----|-------------|
| 100 | 0.70 | 0.887 | 109 | 54.6% |
| 300 | 0.87 | 0.973 | 150 | — |
| 400 | 0.08 | 0.984 | 0 | — |
| 500 | 0.14 | 0.988 | 12 | 4.2% |

## 恢复指令

1. 读本文件
2. 读 MASTER_PLAN.md
3. 读 VERDICT: `shared/audit/processed/VERDICT_ORCH057_MARKER_NO_POS.md`
4. 检查 GiT repo 新 commit: `cd /home/UNT/yz0370/projects/GiT && git log --oneline -3`
5. 检查 ORCH_057 pending 状态: `shared/pending/ORCH_0316_0730_057.md`
