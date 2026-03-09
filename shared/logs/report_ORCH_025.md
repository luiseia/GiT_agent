# ORCH_025 执行报告: 自动化测试框架

## 状态: COMPLETED
- 执行时间: 2026-03-09 ~00:30
- 耗时: ~25 分钟

## 修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `tests/test_config_sanity.py` | 新建 | Config 完整性验证 (24 config × 6 tests) |
| `tests/test_eval_integrity.py` | 新建 | Eval 指标正确性 (合成数据, 5 test classes) |
| `tests/test_label_generation.py` | 新建 | 标签生成验证 (BEV量化, 旋转多边形, 凸包) |
| `tests/test_training_smoke.py` | 新建 | 冒烟测试 (OccHead, 维度, 词表, loss) |

## 测试结果

```
177 passed, 12 skipped, 3 xfailed in 5.32s
```

### 按文件统计

| 文件 | Passed | Skipped | XFail |
|------|--------|---------|-------|
| test_config_sanity.py | 141 | 12 | 3 |
| test_eval_integrity.py | 8 | 0 | 0 |
| test_label_generation.py | 8 | 0 | 0 |
| test_training_smoke.py | 7 | 0 | 0 |

### XFail 说明 (已知旧 config BUG)

| Config | BUG | 详情 |
|--------|-----|------|
| plan_h_dinov3_layer16.py | BUG-42 | milestone 5500+begin 1000=6500 > max_iters 6000 |
| plan_p2_wide_gelu_fix.py | BUG-42 | milestone 2000+begin 500=2500 > max_iters 2000 |
| plan_o_online_wide_diag.py | BUG-41 | warmup end=500 >= max_iters=500 |

这些是已完成的旧实验 config, 测试正确检测到了问题并标记为 xfail。

### 测试覆盖的关键验证项

**Task 1 (config_sanity):**
- ✅ 所有 24 个 occ config 解析无错误
- ✅ load_from checkpoint 路径存在
- ✅ num_vocal = (num_bins+1) + num_classes + 1 + 4 + theta_groups + theta_fines + 1
- ✅ marker_end_id = (num_bins+1) + num_classes + 1 + 4 - 1
- ✅ len(classes) == num_classes
- ✅ milestones + begin <= max_iters (3 旧 config xfail)
- ✅ warmup end < max_iters (1 旧 config xfail)

**Task 2 (eval_integrity):**
- ✅ 完美预测 → recall=1.0, precision=1.0
- ✅ 无预测 → recall=0, bg_false_alarm=0
- ✅ 误报 → bg_false_alarm_rate > 0
- ✅ truck ≠ construction_vehicle 类别隔离
- ✅ BUG-12 cell-internal class-based matching
- ✅ 多帧汇总逻辑正确

**Task 3 (label_generation):**
- ✅ _boxes3d_to_bev7 输出 (N,8), 空输入 (0,8)
- ✅ gx/gy 在 [0,9] 范围
- ✅ 角度 coarse-to-fine 分解 (45°→group=4, fine=5)
- ✅ AABB 模式选中 cell
- ✅ 旋转多边形过滤 cell (|poly| <= |AABB|)
- ✅ 极小物体兜底选中心 cell
- ✅ _point_in_convex_hull 正确判定 inside/outside/degenerate

**Task 4 (training_smoke):**
- ✅ OccHead 正常创建 (num_vocal=230, num_classes=10)
- ✅ DINOv3 in_dim=4096, out_dim=768
- ✅ 投影层结构 (Linear+GELU)
- ✅ eval 输出 10 类 recall/precision + bg + offsets (共 35 字段)
- ✅ 合成 CE loss 无 NaN/Inf
- ✅ 词表 token 范围无重叠

## 运行命令

```bash
python -m pytest tests/test_config_sanity.py tests/test_eval_integrity.py \
    tests/test_label_generation.py tests/test_training_smoke.py \
    -v --tb=short -o "addopts="
```

注: 需要 `-o "addopts="` 覆盖 pytest.ini 中的 xdoctest 插件 (未安装)。

## 约束遵守

- ✅ 所有测试在 `GiT/tests/` 目录
- ✅ 用 pytest 运行
- ✅ 不影响 ORCH_024 训练 (4 GPU 全在运行, 测试无 GPU 依赖)
- ✅ 测试在无 GPU 环境可运行
- ✅ 每个测试有 docstring
