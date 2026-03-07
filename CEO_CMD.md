# CEO 指令

ORCH_006 Phase 2 DINOv3 预提取：

1. 批准使用 GPU 1,3 完成 DINOv3 中间层特征预提取
2. conda 环境：新建 conda env（Python 3.10）
3. **存储预估**：先用 1 张图测试，计算单张图单层特征大小，然后推算总存储需求（323 张 × N 层）。如果总量超过 200 GB，只提取最关键的 1 层（推荐 Layer 16 或 Layer 20）
4. 存储路径：/mnt/SSD/GiT_Yihao/dinov3_features/（不要存主目录）
5. GPU 约束：GPU 1,3 仅用于本次提取，完成后立即释放，后续训练继续只用 GPU 0,2

请立即签发 ORCH 给 Admin 执行。
