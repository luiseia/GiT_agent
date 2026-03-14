# Critic 审计指令 — LARGE_V1_AT4000

严格按以下步骤执行，不可跳过任何步骤：

## 1. PULL
cd /home/UNT/yz0370/projects/GiT_agent && git pull
cd /home/UNT/yz0370/projects/GiT && git pull

## 2. 阅读角色定义
读取 agents/claude_critic/CLAUDE.md，理解你的职责、性格规则和写入边界

## 3. 读取审计请求
读取 shared/audit/requests/AUDIT_REQUEST_LARGE_V1_AT4000.md

## 4. 读取 MASTER_PLAN
读取 MASTER_PLAN.md，审视 Conductor 的计划和决策是否合理

## 5. 全链路特征流诊断（CRITICAL — 必须执行）

这是训练质量的核心检查。每次审计必须运行此诊断，产出下面这张表：

### 5.1 找到最新的训练 checkpoint 和 config
```bash
# 找到最新训练目录
ls -t /mnt/SSD/GiT_Yihao/Train/ | head -3
# 找到最新 checkpoint
ls -t /mnt/SSD/GiT_Yihao/Train/<最新目录>/*.pth | head -3
# 找到对应 config
ls /home/UNT/yz0370/projects/GiT/configs/GiT/plan_*.py
```

### 5.2 运行特征流诊断脚本
```bash
cd /home/UNT/yz0370/projects/GiT
conda activate GiT  # 确认环境
python scripts/diagnose_v3_precise.py  # 修改脚本中的 checkpoint 路径和 config 路径
```
如果脚本路径有变化或不存在，按照以下原理自己写诊断脚本（写入 ssd_workspace/Debug/ 目录）：
- monkey-patch `decoder_inference`，在推理过程中捕获每一层的中间特征
- 用 2-3 个不同的 val 样本分别推理
- 计算每个检查点的 cross-sample 相对差异

### 5.3 产出特征流诊断表（VERDICT 中必须包含）

在 VERDICT 中必须包含以下格式的表格：

```
| 检查点                          | cross-sample 相对差异 | 判定                       |
|--------------------------------|----------------------|---------------------------|
| patch_embed_input (特征提取器)  | X.XX%                | ✅/⚠️/🔴                  |
| grid_interp_feat_layer0        | X.XX%                | ✅/⚠️/🔴                  |
| image_patch_encoded (backbone) | X.XX%                | ✅/⚠️/🔴                  |
| pre_kv_layer0_k                | X.XX%                | ✅/⚠️/🔴                  |
| pre_kv_last_k                  | X.XX%                | ✅/⚠️/🔴                  |
| decoder_out_pos0               | X.XX%                | ✅/⚠️/🔴                  |
| logits_pos0                    | X.XX%                | ✅/⚠️/🔴                  |
| pred_token_pos0 (argmax)       | XX% 相同             | ✅/⚠️/🔴                  |
```

### 5.4 判定标准

**阈值定义**：
- ✅ 正常: cross-sample 相对差异 > 1%
- ⚠️ 偏弱: 0.1% < 差异 ≤ 1%（信号在衰减）
- 🔴 危险: 差异 ≤ 0.1% 或 argmax >80% 相同（模型忽略图像）

**关键比率 — diff/Margin**：
```bash
python scripts/diagnose_v3c_single_ckpt.py <ckpt_name> <ckpt_dir> <config_path>
```
- diff/Margin > 50%: ✅ 模型在利用图像特征
- 10% < diff/Margin ≤ 50%: ⚠️ 图像信号偏弱
- diff/Margin ≤ 10%: 🔴 CRITICAL — 图像信号无法改变决策，确认 mode collapse

**趋势分析（如果有多个 checkpoint）**：
```bash
# 对多个 checkpoint 分别运行
python scripts/diagnose_v3c_single_ckpt.py iter_4000 <dir> <config>
python scripts/diagnose_v3c_single_ckpt.py iter_8000 <dir> <config>
```
- diff/Margin 随训练增大 → ✅ 模型在学习使用图像
- diff/Margin 随训练减小 → 🔴 CRITICAL — mode collapse 正在加剧，立即停止训练
- prediction identical 随训练增大 → 🔴 CRITICAL — 同上

### 5.5 配置审查（不需要 GPU）
直接读取当前训练 config 文件，检查：
- [ ] `train_pipeline` 是否包含数据增强（RandomFlip / PhotoMetricDistortion / RandomResize）→ 没有则 🔴 CRITICAL
- [ ] `train_pipeline` 是否等于 `test_pipeline` → 相同则 🔴 HIGH RISK
- [ ] occ 任务的 `grid_start_embed` 是否注入了 position embedding（检查 git.py 中 `if self.mode != 'occupancy_prediction'`）
- [ ] `grid_interpolate_feats` 是否只在 pos_id==0 注入（检查 occ_head 的 decoder_inference）
- [ ] 是否使用 scheduled sampling → 没有则 ⚠️ MEDIUM

## 6. 审计请求专项审查
按 AUDIT_REQUEST 中的具体要求，深度审查 GiT/ 代码，追踪完整调用链

## 7. 调试验证（如需）
调试脚本写入：/home/UNT/yz0370/projects/GiT/ssd_workspace/Debug/Debug_20260314/
文件名必须以 debug_ 前缀

## 8. 写入判决
写入 shared/audit/pending/VERDICT_LARGE_V1_AT4000.md
判决必须包含以下所有部分：

```markdown
# 审计判决 — LARGE_V1_AT4000

## 结论: PROCEED / STOP / CONDITIONAL

## 特征流诊断结果
<步骤 5.3 的表格>
- diff/Margin 比率: X.X%
- 趋势: 增大/减小/持平
- 诊断结论: <模型是否在利用图像特征>

## 配置审查结果
- [ ] 数据增强: 有/无 → <判定>
- [ ] Pipeline 分离: 是/否 → <判定>
- [ ] Position embedding: 有/无 → <判定>
- [ ] 特征注入频率: 每步/仅首步 → <判定>
- [ ] Scheduled sampling: 有/无 → <判定>

## 发现的问题
1. **BUG-XX**: <描述>
   - 严重性: CRITICAL / HIGH / MEDIUM / LOW
   - 位置: `GiT/<path/to/file.py>:L<行号>`
   - 修复建议: <具体方案>

## 对 Conductor 计划的评价
- MASTER_PLAN.md 中的决策是否合理
- 优先级排序是否正确
- 有无遗漏的风险
```

## 9. 提交
cd /home/UNT/yz0370/projects/GiT_agent
git add shared/audit/pending/ && git commit -m "critic: verdict LARGE_V1_AT4000" && git push
