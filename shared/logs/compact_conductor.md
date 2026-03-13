# Conductor 上下文快照
> 时间: 2026-03-13 00:15
> 原因: 上下文保存

## 当前状态

**ORCH_035** — IN_PROGRESS, iter ~6990/40000
- Label pipeline 大修 (5 项改动) + resume from ORCH_034@4000
- 工作目录: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4`
- Config: `configs/GiT/plan_full_nuscenes_multilayer.py`
- 4 GPU DDP, A6000 ~37.8GB/GPU

## 关键数据

### @6000 Val 结果 (新标签首次评估)

| 指标 | ORCH_034@4000 (旧标签) | ORCH_035@6000 (新标签) | 变化 |
|------|----------------------|----------------------|------|
| car_R | 0.8195 | 0.2329 | 🔴 -71.6% |
| car_P | 0.0451 | **0.0822** | ✅ +82.3% |
| bg_FA | 0.3240 | **0.0938** | ✅✅ -71.1% |
| off_th | 0.1598 | 0.2848 | 🔴 +78.2% |
| cv_R | 0.1095 | 0.2581 | ✅ +136% |

解读: bg_FA 和 car_P 大幅改善 (标签修复目标达成), car_R 下降是适应期 + 新标签更严格。

### Loss 趋势
- iter 4200-5000: ~5.0 (新标签适应中)
- iter 5000-5800: ~4.2 (改善)
- iter 5800-6000: ~3.8 (继续改善)
- iter 6000-6700: ~4.5 (post-val 正常波动)
- iter 6700-7000: ~4.0 (再次改善)

## 下一步

### 即将到来: @8000 eval (~1.8h, 预计 ~02:00)

@8000 决策树:
```
├─ car_R > 0.50 + car_P ≥ 0.08 → ★ 新标签适应成功, 继续训练
├─ car_R 0.30-0.50 + car_P ≥ 0.08 → 进步中但慢, 继续到 @12000
├─ car_R < 0.30 (未回升) → 标签可能过于激进, 审查过滤参数
└─ off_th > 0.25 → z-fix 角度适应缓慢
```

### @8000 后 Phase 2: Deep Supervision + BUG-45
- Deep Supervision: `loss_out_indices=[8,10,11]` (改一行, 零成本)
- BUG-45: OCC head 推理加显式 attn_mask (2-4h)

### Phase 3 准备状态: ViT-L Finetune (CEO 优先)
- 代码已就绪: `model_variant='large'` 参数已加入 `vit_git.py`
- Config 已就绪: `plan_full_nuscenes_vitl_finetune.py`
  - ViT-L (300M, 24层, 1024维) finetune 全部
  - 4 层拼接 [5,11,17,23] → 4096维 → 直接投影 768
  - DINOv3 LR=1e-5 (base 1e-4 × 0.1), VGGT recipe
- **权重未下载**: `dinov3_vitl16_pretrain_lvd1689m.pth` 链接 403 过期, 需 CEO 重新申请
- 符号链接已创建: `/home/UNT/yz0370/projects/GiT/dinov3/weights/dinov3_vitl16_pretrain_lvd1689m.pth`

## 基础设施
- 全 agent UP (conductor/critic/supervisor/admin/ops)
- all_loops.sh PID 443179, sync_loop PID 443180
- watchdog crontab ✅
- /mnt/SSD 96% (178GB), /home 99% (68GB) ⚠️

## 关键文件索引
- MASTER_PLAN: `/home/UNT/yz0370/projects/GiT_agent/MASTER_PLAN.md`
- ORCH_035: `shared/pending/ORCH_0312_1750_035.md` (COMPLETED)
- @6000 report: `shared/logs/report_ORCH_035.md`
- ViT-L config: `/home/UNT/yz0370/projects/GiT/configs/GiT/plan_full_nuscenes_vitl_finetune.py`
- ViT-L 权重链接: `/home/UNT/yz0370/projects/GiT/dinov3/ckpts.md`
- 训练日志: `/mnt/SSD/GiT_Yihao/Train/Train_20260312/full_nuscenes_multilayer_v4/20260312_175353/20260312_175353.log`

## ORCH 队列
- 0 个 PENDING
- ORCH_035: COMPLETED (Admin 已执行, 训练运行中)

## 长期路线图 (MASTER_PLAN Phase 1-8)
1. ✅ Label pipeline 修复 (当前 ORCH_035)
2. Deep Supervision + BUG-45 (待 @8000)
3. ★ **ViT-L Finetune** (CEO 优先, 代码已就绪, 待权重)
4. Attention 机制 (Slot Mask)
5. 3D 空间编码 (BEV PE)
6. 时序信息 (Historical Occ Box)
7. 架构扩展 (Instance Grouping)
8. V2X 多车协作

## 恢复指令
1. 读取本文件恢复上下文
2. 读取 MASTER_PLAN.md 获取完整路线图和决策树
3. 检查 CEO_CMD.md
4. 继续 Phase 1/Phase 2 循环
