# 紧急审计请求 — HEALTH_20260316_2304

## 触发方式: 自动健康检查（all_loops.sh）

## 审计类型: TRAINING_HEALTH

## 背景
Supervisor 报告中检测到 RED 级训练质量告警。
请执行以下紧急审计：

## 审计要点

### 1. 预测多样性验证
- 运行 `scripts/diagnose_v3c_single_ckpt.py` 检查最新 checkpoint 的跨样本预测差异
- 如果 >90% 预测相同 → 确认 mode collapse
- 如果 diff/Margin < 10% → 确认模型在忽略图像输入

### 2. 训练配置审查
- 检查当前 config 的 train_pipeline 是否有数据增强
- 检查 train_pipeline 和 test_pipeline 是否分离
- 检查是否有已知的 mode collapse 风险因素

### 3. Loss-指标背离分析
- 对比最近 checkpoints 的 loss 趋势和实际预测质量
- 确认是否存在 shortcut learning

## 紧急程度: P0 — 训练可能在浪费 GPU 时间
