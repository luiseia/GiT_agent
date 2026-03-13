# 报告: @8000 后未执行计划中的 Phase 1 消融 & Phase 2 优化

> 时间: 2026-03-13 05:00
> 签发者: claude_conductor
> 触发: CEO_CMD

---

## 1. 问题描述

MASTER_PLAN 中明确规定:
- **Phase 1 score_thr 消融**: 状态标注 "待 @8000 eval"，应在 @8000 checkpoint 完成后立即执行
- **Phase 2 训练优化**: 标题为 "ORCH_035 @8000 后"，包含:
  - Deep Supervision `loss_out_indices=[8,10,11]` (改一行，零成本)
  - BUG-45 fix: OCC head 推理加显式 attn_mask (2-4h)

@8000 val 在 03/13 02:52 完成后，Conductor **仅执行了**:
1. 记录 @8000 val 结果
2. 签发审计请求给 Critic
3. 收到 Critic PROCEED 判决
4. 更新 MASTER_PLAN 加入 @12000 决策树
5. 继续监控循环

**未执行**: score_thr 消融、Deep Supervision 部署、BUG-45 修复。

---

## 2. 根因分析

### 2.1 Conductor 决策链路中的遗漏

Conductor 在 @8000 后的决策路径:

```
@8000 val 结果 → 签发审计 → Critic VERDICT: PROCEED to @12000
                                         ↓
                              Conductor 仅理解为 "继续训练不变"
                                         ↓
                              忽略了 MASTER_PLAN Phase 1/Phase 2 中已到期的任务
```

**核心问题**: Conductor 将 Critic 的 "PROCEED" 理解为 "什么都不做继续训练"，而非 "训练继续 + 同时启动已到期的优化项"。

### 2.2 Critic 判决的影响

Critic 在 VERDICT_ORCH035_AT8000 中:
- 将 score_thr 消融建议推迟到 @12000 附加测试
- 未提及 Deep Supervision 或 BUG-45

Conductor 过度依赖 Critic 的判决来决定下一步行动，而忽略了 MASTER_PLAN 中已有的时间表。

### 2.3 Phase 2 协议缺陷

Phase 2 指令 (`phase2_cmd.md`) 的 PLAN 步骤仅要求 "更新 MASTER_PLAN"，没有要求 "检查 MASTER_PLAN 中已到期的行动项"。这导致 Conductor 在 Phase 2 执行中只做了状态更新，没有触发到期任务。

---

## 3. 各项任务的可行性评估

### 3.1 score_thr 消融 (0.1/0.2/0.3)

- **需要**: 在 @8000 checkpoint 上跑 3 次 val (score_thr=0.1, 0.2, 0.3)
- **耗时**: 每次 val ~50 min, 总计 ~2.5h
- **影响**: 零 — 只是 eval，不影响训练
- **现在可做**: ✅ @8000 checkpoint 仍在, 训练继续跑不受影响
- **但**: Critic 建议在 @12000 做更全面的消融 (0.1/0.2/0.3/0.5)，@12000 数据更成熟

### 3.2 Deep Supervision `loss_out_indices=[8,10,11]`

- **需要**: 修改 config 一行，重启训练
- **影响**: 需要 **停止当前训练** 并从 @8000 或当前 checkpoint resume
- **问题**: 当前训练已推进到 ~9180，如果从 @8000 加 Deep Supervision 重启，浪费 1180 iter (~2h) 的计算
- **替代方案**: 等到 @12000 eval 后，如果需要调整，在下一个 ORCH 中同时加入

### 3.3 BUG-45 fix (OCC head 推理 attn_mask)

- **需要**: 修改推理代码 (2-4h 开发)
- **影响**: 仅影响推理/eval，不影响训练
- **现在可做**: ✅ 可并行开发，下次 eval 时使用

---

## 4. 评估: 是否应该立即补救

| 任务 | 立即执行 | 等到 @12000 | 推荐 |
|------|---------|-----------|------|
| score_thr 消融 @8000 | 可做，~2.5h eval | @12000 做更全面版 | **@12000** — 数据更成熟，且 Critic 已规划 |
| Deep Supervision | 需停训重启 | @12000 后作为 ORCH_036 | **@12000 后** — 停训代价 > 收益 |
| BUG-45 fix | 可并行开发 | eval 时使用 | **立即开发** — 不影响训练 |

---

## 5. ViT-L 参数量澄清

MASTER_PLAN 中写 "ViT-L (300M)"。实际从 DINOv3 代码实例化:

| 配置 | 参数量 | 来源 |
|------|--------|------|
| ViT-L/14 (img=518) | **302.9M** | `dinov3.models.vision_transformer.vit_large(patch_size=14)` |
| ViT-L/16 (img=1120) | **303.1M** | `dinov3.models.vision_transformer.vit_large(patch_size=16)` |
| ViT-L/14 (DINOv2 论文) | **304M** | DINOv2 Table 1 |

实测 ~303M，与 300M 差异 ~1%。如果 CEO 有不同来源显示不同参数量，请提供以便核实和修正。

---

## 6. 纠正措施

### 立即执行
1. **BUG-45 开发**: 开始编写 OCC head 推理 attn_mask 修复 (不影响训练)

### @12000 eval 时执行
2. **score_thr 消融**: 在 @12000 checkpoint 上执行 0.1/0.2/0.3/0.5 消融
3. **per-class confusion matrix**: Critic 建议的附加测试

### @12000 eval 后部署
4. **Deep Supervision**: 在 ORCH_036 中加入 `loss_out_indices=[8,10,11]`
5. **BUG-45**: 在 ORCH_036 eval 中使用修复后的推理代码

### 流程改进
6. **Phase 2 协议补丁**: 在 `phase2_cmd.md` 的 PLAN 步骤中加入 "检查 MASTER_PLAN 中已到期但未执行的行动项"
7. **Conductor 决策规则**: Critic PROCEED ≠ "什么都不做"，PROCEED 仅表示训练继续，其他已计划的优化应按时启动

---

## 7. 结论

**主因**: Conductor 将 Critic 的 PROCEED 判决解读为 "维持现状"，忽略了 MASTER_PLAN 中已排期的任务。这是 Conductor 决策逻辑的缺陷，不是 Critic 的问题。

**影响评估**: 中等。score_thr 消融推迟到 @12000 实际上更合理 (数据更成熟)。Deep Supervision 如果从 @8000 重启会浪费已完成的训练。BUG-45 是唯一应该立即开始的工作。

**建议**: 接受当前状态，在 @12000 集中处理所有优化项。同时立即开始 BUG-45 修复的开发工作。
