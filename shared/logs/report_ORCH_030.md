## 执行报告 — ORCH_030: DINOv3 多层特征支持 + Layer 32 验证

### Task 1: OnlineDINOv3Embed 多层特征支持 ✅
- **修改文件**: `mmdet/models/backbones/vit_git.py`
- **新增参数**: `layer_indices` (list, 默认 None)
  - `layer_indices=[10,20,30,40]` → 4层拼接, effective_in_dim=16384
  - `layer_indices=None` → 走原来 `layer_idx` 单层路径 (向后兼容)
- **投影层**: 自动适配 `effective_in_dim` (16384 多层 / 4096 单层)
- **ViTGiT**: 新增 `online_dinov3_layer_indices` 参数透传
- **向后兼容验证**: 不带新参数时行为与修改前完全一致 ✅
- **测试**: `pytest tests/test_config_sanity.py` — 167 passed ✅

### Task 2: 多层特征 config ✅
- **新文件**: `configs/GiT/plan_full_nuscenes_multilayer.py`
- **关键变更**:
  - `online_dinov3_layer_indices=[10, 20, 30, 40]`
  - 投影: 16384→2048→GELU→768
  - 其余参数与 `plan_full_nuscenes_gelu.py` 完全一致
- **语法验证**: ast.parse 通过 ✅

### Task 3: Layer 32 mini 快速验证 ⏸️ BLOCKED
- **原因**: ORCH_029 训练正在运行，4 GPU 全部占用 (36.4GB/GPU)
- **ORCH_029 状态**: iter 730/40000, ETA ~2 days 21h
- **可执行时机**: ORCH_029 eval 间隙或完成后
- 预提取脚本 `scripts/extract_dinov3_features.py` 已验证支持 `--layers 32`

### GiT commit
- `8a961de` — `feat: multi-layer DINOv3 feature support [10,20,30,40] (ORCH_030)`

### 验收清单
1. [x] `OnlineDINOv3Embed` 支持 `online_dinov3_layer_indices=[10,20,30,40]`
2. [x] 向后兼容验证: 不带新参数时行为不变
3. [x] `plan_full_nuscenes_multilayer.py` config 创建
4. [x] 代码通过 import 和 pytest 验证
5. [ ] Layer 32 mini 预提取 — BLOCKED (GPU 占满)
6. [ ] Layer 32 vs Layer 16 mini 对比 — BLOCKED

### 耗时
~15 分钟 (代码修改 + 验证)
