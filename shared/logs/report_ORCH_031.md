## 执行报告 — ORCH_031: BUG-54 + BUG-55 修复

### Task 1: BUG-54 — 索引改为 0-indexed ✅
- DINOv3 7B `depth=40`, blocks 索引 0-39
- `[10,20,30,40]` 中 40 越界 → 修正为 `[9,19,29,39]`
- 修改位置:
  - `configs/GiT/plan_full_nuscenes_multilayer.py`: config 值
  - `mmdet/models/backbones/vit_git.py`: 3 处注释引用

### Task 2: BUG-55 — load_from=None ✅
- `plan_full_nuscenes_multilayer.py`: `load_from = None`
- 原因: proj 层输入维度 16384 vs 旧 checkpoint 的 4096, 无法部分加载

### 验证
- 索引范围验证: `[9,19,29,39]` 全部在 `[0, 39]` 内 ✅
- 旧索引 `40` 确认越界 ✅
- pytest test_config_sanity: 166 passed ✅
- 语法: ast.parse 通过 ✅

### GiT commit
- `dba4760` — `fix: BUG-54 layer indices 0-indexed [9,19,29,39] + BUG-55 load_from=None (ORCH_031)`

### 耗时
~5 分钟
