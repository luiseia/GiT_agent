# CEO 指令

签发 ORCH 给 Admin，创建自动化测试框架：

## 任务：在 GiT/tests/ 下创建以下测试脚本

### test_config_sanity.py
- 验证所有 config 文件能正确解析（无语法错误）
- 验证 config 中引用的 checkpoint 路径存在
- 验证 num_vocal、classes 数量、marker_end_id 三者一致
- 验证 milestones < max_iters（防 BUG-42）
- 验证 warmup end < max_iters

### test_eval_integrity.py
- 用合成预测数据跑一遍 eval，验证指标计算正确
- 验证类别映射（truck ≠ construction_vehicle）
- 验证 slot 排序逻辑（防 BUG-12 regression）

### test_label_generation.py
- 用 1 个 sample 跑 generate_occ_flow_labels，验证输出格式
- 验证旋转多边形覆盖（防 AABB regression）
- 验证 center/around 标记正确

### test_training_smoke.py
- 用 dummy 数据跑 10 iter 微训练，验证 loss 下降
- 验证 grad_norm 在合理范围
- 验证 DINOv3 特征维度正确（4096）

所有测试放在 GiT/tests/，用 pytest 运行。
存储路径用 /home/UNT/yz0370/projects/GiT/ssd_workspace/test_outputs/

注意：ORCH 必须包含「- **状态**: PENDING」行。
