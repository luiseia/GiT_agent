# Conductor 上下文快照
> 时间: 2026-03-15 15:30
> 原因: ORCH_045 已终止，等待 CEO 指令

---

## 当前状态: 无活跃训练，GPU 0,2 空闲，等待 CEO 决策

### ORCH_045 结果: STOPPED @6000 — Marker Saturation Collapse

| 指标 | @2000 | @4000 | @6000 |
|------|-------|-------|-------|
| ped_R | 0.7646 | 1.0000 | 1.0000 |
| car_R | 0.000 | 0.000 | 0.000 |
| bg_FA | 0.921 | **1.000** | **1.000** |
| off_cx | 0.309 | 0.279 | 0.300 |
| off_cy | 0.146 | 0.193 | 0.198 |
| off_w | 0.087 | 0.084 | 0.087 |
| off_h | 0.038 | 0.038 | 0.038 |
| off_th | 0.192 | 0.280 | 0.252 |

**失败根因**: token_drop_rate=0.3 未能阻止 marker saturation。模型学会了将所有 cell 预测为正样本 (bg_FA=1.0)，9/10 类 R=0，offset 全面恶化。

### 下一步可选方向（需 CEO 决策）

1. **增大 token_drop_rate** (0.3→0.5+)
2. **Scheduled Sampling (P4)** — 渐进降低 teacher forcing
3. **数据增强** — RandomFlip for BEV
4. **Loss function** — focal loss / 正负样本平衡 / marker saturation 惩罚
5. **回退 ORCH_024 @8000 baseline** — 从已知好的权重出发

### 资源状态
- GPU 0: 空闲 (15MB), GPU 2: 空闲 (217MB)
- GPU 1,3: yl0826 PETR 占用 (~31GB)
- /mnt/SSD: checkpoints iter_2000/4000/6000.pth 已保存 (~18GB 总计)

### 关键 Checkpoints 保留
- ORCH_045: `/mnt/SSD/GiT_Yihao/Train/Train_20260315/full_nuscenes_large_v1_multilayer_adapt/iter_{2000,4000,6000}.pth`
- ORCH_024 @8000 (baseline): `/mnt/SSD/GiT_Yihao/Train/Train_20260308/full_nuscenes_gelu/iter_8000.pth`

### ORCH 状态
| ID | 状态 |
|----|------|
| ORCH_045 | 🔴 STOPPED @6000 — marker saturation |
| ORCH_044 | STOPPED @440 — mode collapse |
| ORCH_043 | COMPLETED — frozen predictions 假象 |
| ORCH_024 | TERMINATED @12000 — baseline @8000 最优 |

### Agent 状态
- conductor: 活跃，等待 CEO
- supervisor: 过期 (03/13)
- critic: 无响应 (03/09)
- admin: 过期 (03/15 02:00)
- ops: 正常

## 恢复指令
1. 读本文件
2. 检查 `CEO_CMD.md`
3. GPU 0,2 空闲可用
4. 如需新实验: 签发 ORCH → Admin 执行
