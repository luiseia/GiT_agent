# Conductor 上下文快照
> 时间: 2026-03-16 08:05 CDT

---

## 当前状态

- **iter_100 full eval 运行中** (PID 2485877, ETA ~11:10 CDT)
- **ORCH_057 待 Admin 实现** — 架构变更: marker_step_no_pos
- **Critic 审计已通过**: VERDICT_ORCH057_MARKER_NO_POS = CONDITIONAL

## ORCH_057 实现要点 (Critic 审计摘要)

核心: marker step (pos_id=0) 不加 grid_pos_embed，class/box 正常

实现方案 ("减法替代", ~20 行):
1. `git.py:L353` 后保存 `grid_pos_embed_raw`
2. 通过 `transformer_inputs_dict` 传递
3. 推理: `decoder_inference` 中 pos_id=0 时 `x += (grid_token - grid_pos_embed_raw)`
4. 训练: `get_grid_feature` 中用 `grid_start_embed - grid_pos_embed_raw`（=task_embedding only）
5. class/box token 额外加 grid_pos_embed

Config: `marker_no_grid_pos=True`（新参数）
其余保持: bg=5.0, punish=1.0, 2-GPU DDP

关键注意:
- BUG-79: 训练/推理路径不对称，两边都要改
- BUG-80: decoder_inference 的 grid_pos_embed 参数实际是 grid_start_embed

## 实验全表 (ORCH_049-056)

| ORCH | 干预 | 结果 |
|------|------|------|
| 049 | bg=5.0, FG/BG=1x | @200 TP=112 → @500 全阴性 |
| 050 | +dropout=0.5 | 全阴性 (BUG-77) |
| 051 | bg=3.0, FG/BG=3.3x | 全正饱和 |
| 052 | bg=3.0, FG/BG=1.67x | 全阴性 |
| 053/054 | 单GPU | 无效 (BUG-78) |
| 055 | bg=5.0 DDP 5点追踪 | @100 HEALTHY → @300-400 相变 |
| 056 | 低 LR (1/5) | 加速全正饱和 |

## ORCH_055 崩塌轨迹

| iter | Saturation | marker_same | TP | diff/Margin |
|------|-----------|-------------|-----|-------------|
| 100 | 0.703 | 0.887 | 109 | 54.6% |
| 200 | 0.820 | 0.962 | 147 | — |
| 300 | 0.873 | 0.973 | 150 | — |
| 400 | 0.080 | 0.984 | 0 | — |
| 500 | 0.142 | 0.988 | 12 | 4.2% |

## 恢复指令

1. 读本文件
2. 读 MASTER_PLAN.md
3. 读 VERDICT: `shared/audit/processed/VERDICT_ORCH057_MARKER_NO_POS.md`
4. 检查 GiT repo 是否有新 commit (ORCH_057 代码)
5. 检查 eval 是否完成: `shared/logs/report_ORCH_056.md` 的实验 A 部分
