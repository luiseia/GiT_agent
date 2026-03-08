# Conductor 工作上下文快照
> 时间: 2026-03-08 04:00
> 循环: #59 完成 (Phase 2)
> 目的: Context compaction + 10-class 扩展

---

## 当前状态

### P5b 训练 — RUNNING (plan_i_p5b_3fixes)
- **进度**: ~iter 2500+ / 6000
- **GPU**: 0 + 2
- **LR decay**: @2500 应已触发 (2.5e-06→2.5e-07)
- **P5b@2000 关键数据**: 四类全活! bus=0.085 回暖, trailer=0.028 首现
- **红线达标**: 1/5 (truck_R only), bg_FA 0.282 改善中

### P5b@2000 数据
| 指标 | P5b@2000 | P5b@1500 | P5@4000 | 红线 |
|------|----------|----------|---------|------|
| car_R | 0.924 | 0.924 | 0.569 | — |
| truck_R | 0.106 | 0.104 | 0.421 | ≥0.08 ✓ |
| bus_R | 0.085 | 0.000 | 0.315 | — |
| trailer_R | 0.028 | 0.000 | 0.472 | — |
| bg_FA | 0.282 | 0.333 | 0.213 | ≤0.25 ✗ |

### 10-class 扩展 — IN PROGRESS
- **CEO 指令**: "把nuScenes的所有类都加上吧" (训练 target 类别)
- **Checkpoint 兼容性**: ✅ 已确认
  - vocabulary_embed 通过 BERT tokenizer 动态生成 (transforms.py L4402-4433)
  - Head 无 nn.Linear/Embedding 依赖 num_vocal
  - 从 4 类(224 vocab) → 10 类(230 vocab) 完全兼容
- **待修改** (之前改动未提交已丢失):
  1. `generate_occ_flow_labels.py` L76: num_classes default 4→10
  2. `plan_i_p5b_3fixes.py` L74: classes 扩展到 10 类

### nuScenes 10 类频率
| 类别 | 数量 | 比例 |
|------|------|------|
| car | 5051 | 41.7% |
| pedestrian | 3682 | 30.4% |
| barrier | 2399 | 19.8% |
| traffic_cone | 1339 | 11.1% |
| truck | 525 | 4.3% |
| bus | 369 | 3.0% |
| motorcycle | 212 | 1.8% |
| construction_vehicle | 196 | 1.6% |
| bicycle | 191 | 1.6% |
| trailer | 60 | 0.5% |

---

## 已完成的关键事项

### BUG-19 — FIXED (ORCH_013)
- **根因**: `z += h/2` 把 z 从 box CENTER 移到 TOP
- **修复**: 删除 z+=h/2，generate_occ_flow_labels.py L538 + viz script L259
- **可视化**: 全 323 张图含 training fallback (277/3247=8.5% GT 用兜底)

### P5 训练 — COMPLETED
- P5@4000 综合最优 → P5b 起点
- 9/12 指标超 P4, DINOv3 集成验证成功

### P5b 三项修复
- [x] 双层投影 4096→1024→768 (grad_norm 70 vs P5: 247)
- [ ] LR milestones @2500 — 应已触发
- [x] sqrt 权重 — 动态计算, 无需手动配

---

## 活跃 ORCH
| ID | 目标 | 状态 |
|----|------|------|
| ORCH_010 | P5b 三项修复 | RUNNING |
| ORCH_012 | BUG-19 valid_mask | COMPLETED |
| ORCH_013 | BUG-19 v2 z+=h/2 | COMPLETED |

---

## 待办 (按优先级)
1. **完成 10-class 扩展** — 修改 config + pipeline, commit
2. **跟踪 P5b** — LR decay @2500 验证, @3000 数据
3. **P6 规划** — 首个 10-class + BUG-19 修复实验

---

## 红线
| 指标 | 红线 | P5b@2000 |
|------|------|----------|
| truck_R | ≥ 0.08 | 0.106 ✓ |
| bg_FA | ≤ 0.25 | 0.282 ✗ |
| offset_th | ≤ 0.20 | TBD |
| offset_cx | ≤ 0.05 | TBD |
| offset_cy | ≤ 0.10 | TBD |

## Token 布局 (10 类)
```
Bins: 0-167 (168)
Classes: 168-177 (10 类)
Background: 178
Markers: 179-182 (NEAR/MID/FAR/END)
Theta_G: 183-218 (36)
Theta_F: 219-228 (10)
Ignore: 229
Total num_vocal: 230
cls_start: 168, marker_end_id: 182
```

## 基础设施
- 5 Agent 全部 UP
- all_loops.sh PID 4189737
- GPU 0,2: P5b 训练 | GPU 1,3: 空闲
