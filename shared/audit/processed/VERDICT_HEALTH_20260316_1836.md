# 审计判决 — HEALTH_20260316_1836

## 结论: CONDITIONAL

**无活跃训练需要停止。** 所有 11 轮实验 (ORCH_049-059) 已终止。GPU 空闲。
但存在 2 个 CRITICAL 问题需要立即处理。

---

## 特征流诊断结果

### ORCH_055 iter_100 (唯一"HEALTHY"checkpoint, 2-GPU DDP)

| 检查点 | cross-sample 相对差异 | 判定 |
|--------|----------------------|------|
| patch_embed_input (DINOv3特征) | 10.60% | ✅ |
| grid_interp_feat_layer0 | 10.55% | ✅ |
| image_patch_encoded (backbone) | 5.61% | ✅ |
| pre_kv_layer0_k | 3.73% | ✅ |
| pre_kv_last_k | 4.59% | ✅ |
| decoder_out_pos0 | 6.63% | ✅ |
| logits_pos0 | 2.20% | ✅ |
| pred_token_pos0 (argmax) | **91.0% 相同** | **🔴** |

- **diff/Margin**: 54.6% ✅
- **Marker 分布**: NEAR=183/400, END(BG)=207/400 (接近均衡)
- **Marker prediction identical**: 91.50%

### ORCH_059 iter_500 (最新 checkpoint, all-negative collapse)

| 检查点 | cross-sample 相对差异 | 判定 |
|--------|----------------------|------|
| patch_embed_input (DINOv3特征) | 6.23% | ✅ |
| grid_interp_feat_layer0 | 6.19% | ✅ |
| image_patch_encoded (backbone) | 2.43% | ✅ |
| pre_kv_layer0_k | 2.47% | ✅ |
| pre_kv_last_k | 1.96% | ✅ |
| decoder_out_pos0 | 3.05% | ✅ |
| logits_pos0 | **0.88%** | **⚠️** |
| pred_token_pos0 (argmax) | **100.0% 相同** | **🔴** |

- **diff/Margin**: 7.7% 🔴 CRITICAL
- **Marker 分布**: NEAR=0/400, END(BG)=399/400 (**全阴性**)
- **Marker prediction identical**: 99.75%

### 趋势分析 (ORCH_055 @100 → ORCH_059 @500)

| 指标 | ORCH_055 @100 | ORCH_059 @500 | 趋势 |
|------|---------------|---------------|------|
| diff/Margin | 54.6% | 7.7% | 🔴 暴跌 |
| logits 相对差异 | 2.20% | 0.88% | 🔴 衰减 |
| pred_identical | 91.0% | 100.0% | 🔴 固化 |
| patch_embed差异 | 10.6% | 6.2% | ⚠️ 下降但仍可用 |

**诊断结论**: DINOv3 特征在 patch_embed 层面始终携带跨样本差异 (6-10%)，证明图像信号本身没有问题。但信号在通过 backbone → decoder → logits 的传播过程中被系统性压缩。grid_pos_embed 提供了一条"免费"的空间先验路径，模型逐渐学会只依赖这条路径做 marker 决策。

**关键洞察 (BUG-85)**: 即使在"HEALTHY"的 ORCH_055 @100，pred_token 已经 91% 相同。这意味着即使是项目历史最佳状态，模型也已经处于 mode collapse 的边缘。所谓"HEALTHY"只是差异从"极小"变成"微小"——marker 决策从未真正依赖图像内容。

---

## 配置审查结果

基于 `configs/GiT/plan_full_nuscenes_large_v1.py` 审查：

- [x] **数据增强**: `PhotoMetricDistortion` + `RandomFlipBEV(flip_ratio=0.5)` → ✅ 存在
- [x] **Pipeline 分离**: `train_pipeline` ≠ `test_pipeline` → ✅ 已分离
- [x] **Position embedding**: `grid_pos_embed` 在 `git.py:357-359` 注入 → ✅ 存在
- [x] **特征注入频率**: `grid_interpolate_feats[layer_id]` 在每个 decoder layer、每个 pos_id 都注入 (`git_occ_head.py:1140-1141`) → ✅ 每步注入
- [x] **Scheduled sampling**: `prefix_drop_rate=0.5` (50% cell prefix dropout) → ✅ 存在
- [x] **paramwise_cfg BUG-69 修复**: `backbone.patch_embed.adapt_layers` lr_mult=1.0 → ✅ mmengine longest-prefix-match 确认有效
- [x] **marker_no_grid_pos**: 设为 `False` (ORCH_058 FAIL 后回退) → ✅ 合理

**配置层面无新问题。** 已知的修复 (BUG-69/62/74) 均已正确部署。

---

## 健康检查结果

### A. Mode Collapse 检测

- [x] **数据增强检查**: `PhotoMetricDistortion` + `RandomFlipBEV` 存在 → ✅
- [x] **Pipeline 分离检查**: train ≠ test → ✅
- [x] **预测多样性**: ORCH_059 @500: 100% 预测相同 → **🔴 CRITICAL — mode collapse 确认**
- [x] **Marker 分布**: ORCH_059 @500: 399/400 = END(BG)，0/400 = NEAR → **🔴 CRITICAL — all-negative collapse**
- [x] **训练趋势**: ORCH_055 marker_same: 0.887→0.963→0.973→0.984→0.988 (单调上升) → **🔴 CRITICAL**

### B. Shortcut Learning 检测

- [x] **Loss-指标背离**: 无活跃训练，无法检查 loss 趋势。但历史数据 (ORCH_045 @2000-6000) 显示 loss 下降而 bg_FA 从 0.92 → 1.0 → **🔴 HIGH — shortcut learning 确认**
- [x] **Teacher Forcing 风险**: `prefix_drop_rate=0.5` (50% dropout) 但仍为 teacher forcing 框架 → ⚠️ MEDIUM (已有缓解措施但不充分)

### C. 架构风险检测

- [x] **位置编码完整性**: `grid_pos_embed` 正确注入，`marker_no_grid_pos=False` → ✅ (但这正是 shortcut 的根源)
- [x] **特征注入频率**: 每步每层注入 `grid_interpolate_feats` → ✅
- [x] **维度匹配**: DINOv3 ViT-L 4层×1024=4096 → proj 2048 → GELU → 1024 → GiT-Large 1024 → ✅ 匹配

### D. 资源浪费检测

- [x] **无效训练**: 无活跃训练 → ✅ 不适用
- [x] **Checkpoint 价值**: 最新 checkpoint (ORCH_059 @500) 比早期 (ORCH_055 @100) 更差 → 🔴 所有 @500 都退化

---

## 发现的问题

### 1. **BUG-84**: SSD 磁盘空间 CRITICAL — 4.7GB 剩余
   - 严重性: **CRITICAL**
   - 位置: `/mnt/SSD/GiT_Yihao/Train/` (442 个 >1GB checkpoint 文件 = **1.185 TB**)
   - 根因: 11 轮失败实验 (ORCH_049-059) 的 checkpoint 未清理。历史实验 (Train_20260308-20260314) 也有大量无用 checkpoint
   - 影响: **SSD 满后任何新训练/eval 都将失败**。当前 4.7GB 不足以保存一个新 checkpoint (每个 ~6GB)
   - 修复建议:
     1. **立即清理**: ORCH_049-054 的 checkpoint (均为短实验，iter_100-500，每个 ~6GB)
     2. **保留**: ORCH_055 iter_100 (唯一 HEALTHY)、ORCH_024 @8000 (baseline)
     3. **清理历史**: Train_20260308 中的 plan_m/plan_n/plan_o 诊断实验 (每个 ~60GB)
     4. **清理历史**: Train_20260312 中的 multilayer_v3/v4 (每个 ~80GB)
     5. 预估可回收: **200-400 GB**

### 2. **BUG-85**: "HEALTHY" checkpoint 的 pred_token 已 91% 相同
   - 严重性: **HIGH**
   - 位置: 系统性问题，非特定代码位置
   - 根因: 即使在 ORCH_055 @100 (项目历史最佳状态)，marker 预测也已 91% 跨样本相同。diff/Margin=54.6% 看似健康，但 argmax 后 91% 相同意味着 margin 虽然存在但方向一致——大多数 cell 的 top-1 预测已经被 grid_pos_embed 空间先验主导
   - 影响: 意味着目前的 "HEALTHY @100" 并不是真正健康，只是崩塌尚未完全固化的过渡态
   - 修复方向: 需要从根本上改变 marker 决策的信息流，不能只靠超参数调整

### 3. **BUG-75 升级**: grid_pos_embed shortcut 确认为架构级问题
   - 严重性: **CRITICAL** (从 HIGH 升级)
   - 位置: `git.py:640-654` (get_grid_feature)、`git_occ_head.py:1125-1141` (decoder loop)
   - 根因: 11 轮实验穷尽超参/bias/微架构空间后，marker_same 在任何配置下都单调上升至 ~1.0。这不是超参问题，是信息流架构问题
   - 11 轮实验证据汇总:
     - ORCH_049: FG/BG=1x → @500 all-negative
     - ORCH_050: grid_pos dropout → 破坏定位
     - ORCH_051: FG/BG=3.3x → all-positive
     - ORCH_052-053: 二分搜索 FG/BG → 均失败
     - ORCH_055: 精确复现 → @100 HEALTHY @400 相变
     - ORCH_056: 低 LR → 加速模板化
     - ORCH_057: 移除 grid_pos → 丧失多样性
     - ORCH_058: marker_step_no_pos → 全面崩塌
     - ORCH_059: bias init → 翻转方向但不阻止模板化

---

## 对 Conductor 计划的评价

### 正确的部分
1. **根因识别准确**: "grid_pos_embed 为 marker step 提供免费空间先验" — 本轮特征流诊断完全证实。image signal 从 10.6% 衰减到 2.2% (logits)，而 grid_pos_embed 提供确定性空间编码，优化器自然选择后者
2. **实验策略系统**: 11 轮实验覆盖了 FG/BG 比、dropout、LR、位置编码移除、bias init 等维度，每个方向都有明确的失败证据
3. **崩塌轨迹分析精确**: ORCH_055 的 5-point frozen check 准确刻画了 @100→@400 的相变过程
4. **正确决策暂停**: 在用尽超参空间后暂停等待 CEO 方向，而非继续盲目实验

### 需要修正的部分
1. **"HEALTHY @100" 标签误导 (BUG-85)**: MASTER_PLAN 多次引用 ORCH_055 @100 为 "🟢 HEALTHY"，但本次审计证明 pred_token 已 91% 相同。建议修改为 "🟡 BORDERLINE" 或 "PARTIAL HEALTHY"
2. **磁盘危机未被识别 (BUG-84)**: MASTER_PLAN 和 ORCH 状态中均未提及磁盘空间问题。SSD 仅剩 4.7GB，**下一次训练将无法保存任何 checkpoint**
3. **BUG 表重复**: MASTER_PLAN 中有两个 "活跃 BUG 跟踪" 表（一个在 ORCH_059 结论下方，一个更早），应合并

### 5 个候选方向的评价

| 方向 | 评价 | 风险 |
|------|------|------|
| 1. grid_pos_embed 噪声/shuffle | ⚠️ 可能重蹈 ORCH_050 覆辙 (dropout 破坏定位)，但噪声幅度可控 | MEDIUM |
| 2. 二元 marker (FG/BG) | ✅ 简化问题空间，消除 3:1 结构偏差，实现成本低 | LOW |
| 3. marker 独立 head | ✅ 从根本切断 grid_pos_embed → marker 路径 | MEDIUM (需验证 head 分离后 box 回归不退化) |
| 4. 长训练 | 🔴 不建议 — BUG-85 证明 @100 就已 91% 相同，更长训练只会加剧 | HIGH (浪费 GPU) |
| 5. 回退 ORCH_024 | ⚠️ 最安全的选择，但放弃 ViT-L 和多层特征的进展 | LOW |

**Critic 推荐**: 方向 3 (marker 独立 head) 或方向 2 (二元 marker) 优先。理由:
- 方向 3 彻底切断 shortcut 路径，是唯一从信息流层面解决问题的方案
- 方向 2 成本最低，可以快速验证 marker 简化是否缓解梯度不对称
- 方向 4 明确不可行 (BUG-85 证据)
- 方向 1 需要精细调参，在当前信号如此微弱 (2.2% 相对差异) 的情况下，噪声很容易完全淹没信号

---

## 附加建议

### URGENT: 磁盘清理必须在下一轮实验前完成
```
# 建议清理顺序 (按安全性排序):
# 1. ORCH_053/054 的 checkpoint (各 12GB) — 短实验，已有更好的 ORCH_055 数据
# 2. Train_20260308 诊断实验 (plan_m/n/o) — 旧架构，无参考价值
# 3. Train_20260312 multilayer_v3/v4 — 旧多层实验，已被 ORCH_055 取代
# 4. ORCH_059 中间 checkpoint (iter_100-400) — 只保留 iter_500 或全删

# 保留:
# - ORCH_055 iter_100 (唯一 HEALTHY)
# - ORCH_024 iter_8000 (baseline)
# - ORCH_059 iter_500 (最新参考)
```

### 下一步建议

如果 CEO 选择方向 3 (marker 独立 head):
1. 先清理磁盘释放 >100GB
2. 实现一个轻量分类 head (Linear → ReLU → Linear)，直接从 grid_interpolate_feats 预测 FG/BG
3. 保留现有 decoder 只做 class + box 回归
4. 在 ORCH_055 @100 checkpoint 基础上 resume，对比 marker_same 趋势
5. 如果 @200 marker_same < 0.95 → 方向 3 有效，继续长训练

---

## 审计元信息

- **审计员**: claude_critic
- **审计时间**: 2026-03-16 18:38-18:48 CDT
- **诊断脚本**: `ssd_workspace/Debug/Debug_20260316/debug_feature_flow_diagnosis.py`
- **审计范围**: 配置审查、特征流诊断 (2 个 checkpoint)、frozen check 趋势分析、磁盘状态、MASTER_PLAN 评价
- **GPU 使用**: GPU 0 + GPU 2 (诊断推理)
