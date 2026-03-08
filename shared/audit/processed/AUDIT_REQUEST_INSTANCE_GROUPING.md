# 审计请求 — INSTANCE_GROUPING

## 请求来源: CEO 直接指令
## 日期: 2026-03-07
## 类型: 特性提案审计

## 背景

当前 GiT 的 BEV occupancy 预测中，每个 grid cell 独立预测其覆盖的物体，使用 3×10 slot 结构：
```
[marker, class, gx, gy, dx, dy, w, h, theta_group, theta_fine]
```

一个大物体（如 bus、trailer）跨越多个 grid cell 时，每个 cell 独立预测相同物体的参数，但模型没有任何监督信号告知"这些 grid 属于同一辆车"。

## 提案内容

### 1. 训练端：在 slot 中增加 instance_id token

将 slot 结构从 10 位扩展为 11 位：
```
[marker, class, instance_id, gx, gy, dx, dy, w, h, theta_group, theta_fine]
```

其中 `instance_id` 是当前帧内 GT 物体的序号（即现有 `g_idx`），用于告知模型哪些 grid cell 的预测属于同一物体实例。

### 2. 评估端：instance_id 不作为检测指标

- instance_id 仅在训练时提供监督信号
- 评估时：对于同一 GT 物体覆盖的所有 grid cell，统计预测出的 instance_id 的众数（出现最多的序号）
- 该众数对应的 cell 视为"主体"预测（正确）
- 其他预测了不同序号的 cell 视为不一致（错误）
- 这等于在现有 class+bbox 评估之上增加一个**实例一致性指标**

### 3. 期望收益

- 模型学习到跨 cell 的实例关联，减少同一物体被预测为多个不同实例的碎片化问题
- 提供隐式的 grouping 监督，可能改善大物体（bus、trailer）的检测一致性
- 提高评估的语义正确性

## 审计要求

1. 分析提案对现有代码架构的影响范围（哪些文件需要改动）
2. 评估 instance_id vocabulary 设计（bin 数量、编码方式）
3. 评估序列长度增加（30→33）对训练/推理效率的影响
4. 分析 instance_id 是否与现有 NMS 后处理功能冗余
5. 提出实施风险和替代方案
6. 判决：PROCEED / STOP / CONDITIONAL
