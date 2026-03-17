# 审计判决 — HEALTH_20260316_1836 (重启后补发)

## 结论: STOP

**无活跃训练。所有 47 个 HEALTH 审计请求 (1836-0151) 均为 supervisor 自动循环产生的重复请求。**

本 VERDICT 覆盖以下所有请求:
- HEALTH_20260316_1836 ~ HEALTH_20260317_0151 (共 47 个)

---

## 特征流诊断结果 (来自前一轮完整审计)

| 检查点 | ORCH_055 @100 跨样本差异 | ORCH_059 @500 跨样本差异 |
|--------|------------------------|------------------------|
| DINOv3 patch_embed | 10.60% ✅ | 6.23% ✅ |
| backbone 输出 | 5.61% ✅ | 2.43% ✅ |
| logits | 2.20% ✅ | 0.88% ⚠️ |
| pred_token (argmax) | **91% 相同 🔴** | **100% 相同 🔴** |

- diff/Margin 比率: 54.6% (@100) → 7.7% (@500)
- 趋势: 持续减小 🔴
- 诊断结论: 图像信号在 backbone→decoder→logits 传播中被系统性压缩。即使 "BORDERLINE" @100 的 pred_token 已 91% 相同。marker 决策从未真正依赖图像内容。

## 配置审查结果

- [x] 数据增强: 有 (RandomFlip, PhotoMetricDistortion, RandomResize) → ✅
- [x] Pipeline 分离: 是 (train_pipeline ≠ test_pipeline) → ✅
- [x] Position embedding: 有 (grid_pos_embed 注入) → ✅ 但同时是 shortcut 源头 (BUG-75)
- [x] 特征注入频率: 仅首步 (pos_id==0) → ⚠️ MEDIUM
- [x] Scheduled sampling: 无 → ⚠️ MEDIUM

## 健康检查结果

### A. Mode Collapse 检测
- [x] **数据增强**: 有 → ✅
- [x] **Pipeline 分离**: 是 → ✅
- [x] **预测多样性**: pred_token 91-100% 相同 → 🔴 CRITICAL
- [x] **Marker 分布**: 所有 cell marker_same 单调上升至 ~1.0 → 🔴 CRITICAL
- [x] **训练趋势**: marker_same @100=0.887 → @500=0.988，不可逆上升 → 🔴 CONFIRMED

### B. Shortcut Learning 检测
- [x] **Loss-指标背离**: loss 下降但 marker_same 上升 → 🔴 HIGH (shortcut learning 确认)
- [x] **Teacher Forcing 风险**: 100% TF, 无 scheduled sampling → ⚠️ MEDIUM

### C. 架构风险检测
- [x] **位置编码完整性**: grid_pos_embed 正确注入但构成 shortcut → 🔴 CRITICAL (BUG-75)
- [x] **特征注入频率**: 仅 pos_id==0 → ⚠️ MEDIUM
- [x] **维度匹配**: DINOv3 ViT-L 多层 concat → 无问题

### D. 资源浪费检测
- [x] **无效训练**: 无训练在运行 → N/A
- [x] **Checkpoint 价值**: @500 全部退化 → 无价值

## 发现的问题

1. **BUG-75**: grid_pos_embed 空间模板 shortcut — 11 轮实验 (ORCH_049-059) 穷尽超参/微架构空间均无法解决
   - 严重性: **CRITICAL**
   - 位置: `GiT/git.py` (grid_pos_embed 注入点) + `GiT/git_occ_head.py` (decoder_inference)
   - 修复建议: 需要架构级干预 — 推荐方向 3 (marker 独立 head) 或方向 2 (二元 marker)

2. **BUG-84**: SSD 磁盘接近满 — 仅 4.7GB 剩余, 442 个 checkpoint 占 1.185TB
   - 严重性: HIGH
   - 位置: `/mnt/SSD/GiT_Yihao/Train/`
   - 修复建议: 清理早期失败实验 (ORCH_048-054, 056-059) 的 checkpoint, 仅保留 ORCH_055

3. **BUG-85**: 同一 cell 3 slot 输出完全相同, AR decoder 丧失 slot 间区分能力
   - 严重性: MEDIUM
   - 位置: decoder 的 AR sequence generation
   - 修复建议: 诊断 slot-level diversity, 可能需要不同的 slot positional encoding

## 对 Conductor 计划的评价

MASTER_PLAN.md 当前状态:
- ✅ **正确**: 暂停训练等待 CEO 决策是合理的
- ✅ **正确**: 5 个候选方向覆盖了合理的解决空间
- ⚠️ **建议**: 方向 4 (长训练) 明确不可行 — marker_same 单调上升, 不会自然缓解
- ⚠️ **建议**: 方向 5 (回退 ORCH_024) 是安全保底, 但 DINOv3 7B + 单层 L16 性能上限有限
- ✅ **推荐**: 方向 3 > 方向 2 > 方向 1 > 方向 5 > 方向 4

## ⚠️ SUPERVISOR 循环问题

**CRITICAL**: Supervisor `all_loops.sh` 在无活跃训练时持续每 ~10 分钟发送 HEALTH 审计请求。
- 前一轮 critic 因此消耗全部 context (14+ 次重复审计 → CONTEXT_LOW)
- 本轮重启后又收到 47 个重复请求
- **强烈建议**: Conductor 在无活跃训练时暂停 supervisor 的自动健康检查, 或在 all_loops.sh 中添加训练进程存在性检查

## 附加建议

1. **立即清理 SSD** — 1.185TB checkpoint 中绝大部分来自已失败实验
2. **修复 supervisor 循环** — 添加 `ps aux | grep train.py` 前置检查, 无训练时不发审计请求
3. **等待 CEO 决策后再启动新实验** — 当前所有方向都需要架构变更
