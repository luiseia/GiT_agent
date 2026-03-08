# 审计判决 — INSTANCE_GROUPING

## 结论: CONDITIONAL

**条件：必须解决下述 4 个关键设计问题后方可实施。当前提案方向正确但实施细节不足。**

---

## 一、提案核心逻辑分析

### 1.1 当前问题确认

当前 slot 结构 `[marker, class, gx, gy, dx, dy, w, h, theta_group, theta_fine]` 中，**每个 cell 是信息孤岛**。同一辆 bus 跨越 6 个 cell 时，这 6 个 cell 的预测互不知情。

- 位置: `git_occ_head.py:L406-425` — `cell_to_gts` 构建时 `g_idx` 已标记实例，但此信息从未传递给模型
- 位置: `git_occ_head.py:L462-467` — slot_tokens 只包含 10 个值，无 instance_id

**影响**：模型无法学习跨 cell 的实例一致性。NMS (`occ_2d_box_eval.py:L335-395`) 可以事后去重，但依赖 bbox 精度——如果 bbox 本身不准（P5 avg_offset_cx=0.142），NMS 效果受限。

### 1.2 Instance ID 的信息论价值

| 信息源 | 是否已存在 | Instance ID 新增信息 |
|--------|-----------|---------------------|
| 物体类别 | class token 已有 | 无新增 |
| 物体位置 | gx,gy,dx,dy 已有 | 无新增 |
| 物体尺寸 | w,h 已有 | 无新增 |
| **跨 cell 关联** | **完全缺失** | **唯一来源** |

结论：**Instance ID 提供的是一种 _不可从现有 token 推断的_ 结构化信息**——哪些 cell 属于同一物体。这不是冗余信号。

---

## 二、发现的问题

### ISSUE-1: Instance ID 编码方案未定义
- **严重性**: HIGH
- **位置**: 提案设计层
- **问题**: g_idx 的取值范围每帧不同（nuScenes-mini 中，前视单帧可见 GT 0~20+ 不等）。如何映射到固定词表？

**方案对比**:

| 方案 | 词表大小 | 优点 | 缺点 |
|------|---------|------|------|
| A. 直接使用 g_idx | 需要 max_objects 个 bin（~30） | 简单 | 序号跨帧无意义，模型需学习"任意排列" |
| B. 深度排序 g_idx | 同上 | 隐含空间关系 | 与 slot 内深度排序冗余 |
| C. 按类别分组编号 | num_classes * max_per_class（~4*8=32） | 类内关联更清晰 | 词表更大 |
| D. 哈希桶 | 固定 K 个桶（~16） | 词表小 | 碰撞风险 |

**建议**: 采用方案 A（直接 g_idx），词表大小设为 32。理由：
- `g_idx` 已按深度排序（`generate_occ_flow_labels.py:L442` 排序逻辑），自然带有空间语义
- 单帧前视可见物体通常 < 20，32 bins 足够
- 模型不需要学习 g_idx 的绝对含义，只需学习"同一 ID = 同一物体"的相对关系

### ISSUE-2: 序列长度扩展的架构影响
- **严重性**: MEDIUM
- **位置**: `git_occ_head.py:L392, L1088-1094`
- **问题**: SLOT_LEN 从 10→11，总序列从 30→33。影响范围：

| 文件 | 位置 | 修改内容 |
|------|------|---------|
| `git_occ_head.py` | L392 | `SLOT_LEN = 10` → `11` |
| `git_occ_head.py` | L428-429 | `targets_tokens` shape 30→33, `tokens_weights` 同 |
| `git_occ_head.py` | L462-467 | `slot_tokens` 列表从 10 元素→11 元素 |
| `git_occ_head.py` | L810-823 | loss reshape 用 SLOT_LEN |
| `git_occ_head.py` | L1088-1094 | 推理循环 30→33 步 |
| `git_occ_head.py` | L1114 | `inner_id = pos_id % 10` → `% 11` |
| `git_occ_head.py` | L1117-1166 | 新增 inner_id==2 分支 (instance_id)，后续编号+1 |
| `git_occ_head.py` | L1176 | reshape `(B, Q, 3, 10)` → `(B, Q, 3, 11)` |
| `occ_2d_box_eval.py` | L53-184 | 推理结果解析需适配 11 位 |
| config files | value_bin_cfg | 新增 `instance_id_range`, `instance_id_bin_count` |

**效率影响**: 33/30 = 10% 推理步数增加。单步推理代价是 O(seq_len * hidden_dim²) 的 attention，33 步的总体增量约 10%。在 nuScenes-mini (323 images) 上这不是瓶颈。

### ISSUE-3: 评估逻辑的语义歧义
- **严重性**: HIGH
- **位置**: 评估设计层
- **问题**: 提案说"同一辆车预测出最多的序号做主体，其他算错"。这存在多重歧义：

**歧义 1**: "算错"如何量化？是直接扣 Precision？还是单独的 consistency 指标？
- 如果扣 Precision：一辆 bus 跨 6 个 cell，其中 4 个预测 instance_id=3，2 个预测 instance_id=5。按提案，4 个正确，2 个错误。但按现有 class+bbox 标准，这 6 个可能全是 TP。两个标准冲突。
- **建议**: Instance consistency 应作为**独立指标**（如 `instance_consistency_rate`），不影响现有 Precision/Recall 计算。

**歧义 2**: 评估时 instance_id 怎么匹配？
- 模型预测的 instance_id 是词表索引，GT 的 g_idx 是帧内排序。评估时不能直接比较，因为模型可能学到不同的编号方案。
- **建议**: 评估时不比较绝对值，只比较**一致性**——同一 GT 物体的所有 cell 是否预测了相同的 instance_id，无论具体数值。

### ISSUE-4: Instance ID Loss 权重策略
- **严重性**: MEDIUM
- **位置**: `git_occ_head.py:L514-524` 权重分配区域
- **问题**: Instance ID 的 loss 权重如何设定？

**分析**:
- 如果权重太高：模型过度关注实例编号一致性，牺牲 bbox 精度
- 如果权重太低：模型忽略 instance_id，token 退化为噪声
- Instance ID 与 class token 性质不同——class 只有 4 个可能值，instance_id 有 0-31 共 32 个

**建议**:
- Instance ID loss 权重设为 class loss 权重的 0.3-0.5 倍
- 使用 Label Smoothing (0.1) 缓解 ID 编号的任意性
- 前 1000 步 warmup 期间 instance_id loss 权重为 0，让模型先学会基本检测

---

## 三、逻辑验证

- [x] **梯度守恒**: Instance ID 是独立的分类 head（softmax over 32 bins），梯度路径与其他 token 并行，不影响 bbox 回归梯度
- [x] **边界条件**:
  - 空 cell：instance_id token 与 marker=END 一起设为 ignore，不参与 loss ✓
  - 单物体跨 1 cell：instance_id 退化为无用信号，但 loss 权重被 IBW 归一化，不会放大 ✓
  - 多物体同 cell：每个 slot 有独立 instance_id，深度排序保证一致性 ✓
- [x] **数值稳定性**: Softmax over 32 bins，数值安全。需确保 instance_id bins 在词表中不与其他 token 重叠

---

## 四、代码修改清单

### 4.1 `generate_occ_flow_labels.py` — 标签生成

修改量: **极小**。`g_idx` 已存在于 `gt_projection_info`，无需改动 pipeline。

```python
# 当前 L502-506:
info = {
    'g': int(g),
    'label': int(gt_labels_3d[g]),
    'bev_bbox_norm': bev_boxes_all[g].tolist(),
    'depth': 0.0,
    'img_fine_cell_ids': [],
    'center_cell_id': -1,
    'best_cam': None
}
# g_idx 已隐式存在 (enumerate index)，无需额外字段
```

### 4.2 `git_occ_head.py` — 核心修改

**4.2.1 `__init__`**: 新增 instance_id 词表参数
```python
# 新增 value_bin_cfg 字段:
# 'instance_id_range': [X, X+32],  # 32 bins
# 'instance_id_bin_count': 32
```

**4.2.2 `_get_targets_single_based_on_bev`**: SLOT_LEN 10→11
```python
# L392:
NUM_SLOTS, SLOT_LEN = 3, 11  # 原 10

# L462-467: slot_tokens 新增 instance_id
slot_tokens = [
    marker_ids[i],
    self.cls_start + gt['label'],
    self.instance_id_start + gt['g_idx'],  # NEW: instance_id
    t_gx, t_gy, t_dx, t_dy, t_w, t_h,
    t_th_g, t_th_f
]
```

**4.2.3 `decoder_inference`**: 30→33 步，新增 inner_id==2 分支
```python
# L1094: for pos_id in range(33):
# L1114: inner_id = pos_id % 11
# 新增 elif inner_id == 2: # instance_id
#     inst_logits = logits[:, inst_start : inst_start + 32]
#     score_abs, absmax = torch.max(F.softmax(inst_logits, dim=-1), dim=-1)
#     pred_abs = absmax + inst_start
```

### 4.3 `occ_2d_box_eval.py` — 评估修改

新增 instance consistency metric:
```python
# 在 compute_metrics 中新增:
# 对每个 GT 物体 (g_idx)，收集所有覆盖 cell 的 predicted instance_id
# 计算众数与总数的比值 = consistency_rate
# eval_results['instance_consistency'] = mean(consistency_rates)
```

### 4.4 Config 文件修改

```python
value_bin_cfg = dict(
    # ... 现有字段 ...
    instance_id_range=[NEW_START, NEW_START + 32],
    instance_id_bin_count=32,
)
```

**词表总量影响**: +32 bins。当前词表 ~224 个 token，扩展到 ~256。对 embedding 层影响可忽略。

---

## 五、风险评估

| 风险 | 严重性 | 缓解措施 |
|------|--------|---------|
| 模型学习到 g_idx 的绝对编号而非相对关系 | MEDIUM | 训练时随机打乱 g_idx 分配（data augmentation） |
| Instance ID loss 干扰 bbox 回归 | MEDIUM | Loss 权重独立控制，前期 warmup=0 |
| 序列长度增加导致 KV cache 膨胀 | LOW | 33 vs 30，增量 10%，可忽略 |
| 评估指标与现有 P/R 冲突 | HIGH | Instance consistency 必须作为独立指标 |

---

## 六、替代方案

### 方案 B: 对比学习（不改 slot 结构）
在 encoder 输出层添加对比 loss：同一 GT 覆盖的 cell 的 grid_token 应相似，不同 GT 的应不同。
- 优点：不改 slot 结构，不增加推理步数
- 缺点：需要额外的 loss head，训练不稳定

### 方案 C: Instance-aware attention mask
在 window attention 中，为属于同一 GT 的 cell 之间添加 attention bias。
- 优点：直接在特征提取层注入实例信息
- 缺点：需要在 attention 层注入 GT 信息，train/test 不一致

### 方案 D: Post-hoc grouping（不改训练）
纯后处理：在评估时，将 class 和 bbox 相近的 cell 预测合并为同一实例。
- 优点：零训练代价
- 缺点：依赖 bbox 精度（当前 avg_offset_cx=0.142，不够精确）

**结论：提案方案（在 slot 中加 instance_id）是最直接、实施最清晰的方案。方案 B 可作为补充。**

---

## 七、实施优先级建议

1. **Phase 1** (P5b 修复后): 先修复 BUG-17 (per_class_balance 零和振荡) 和 LR milestone 问题
2. **Phase 2** (P6): 加入 instance_id token，SLOT_LEN 10→11
3. **Phase 3**: 加入 instance consistency 评估指标
4. **Phase 4** (可选): 探索方案 B 对比学习作为补充

---

## 八、附加发现

### BUG-18: 评估时 GT instance 信息未跨 cell 关联
- **严重性**: MEDIUM (设计层)
- **位置**: `occ_2d_box_eval.py:L99-112`
- **描述**: 当前评估代码 `cell_to_gt_eval` 将 GT 打散到各 cell，但丢失了跨 cell 的实例关联（`box_idx` 存在但未用于实例级统计）。这不是 bug，但是实现 instance consistency 指标的前提条件。

---

**判决签发: claude_critic**
**日期: 2026-03-07**
**BUG 编号更新: 下一个 BUG-19**
