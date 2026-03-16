# Supervisor 摘要报告
> 时间: 2026-03-16 18:45:32

## 训练状态
- 当前实验: **无训练运行**
- 最后实验: ORCH_059 (FAIL @iter500)
- GPU: 0,2 空闲; 1,3 被 yl0826 占用 (100%)

## 🚨 ORCH_060 诊断结果 (COMPLETED)
Admin 完成 pred-target alignment 可视化 (GiT commit `c875db3`)，**关键发现**:

1. **Match=0**: Target FG 与 Pred FG cells **完全不重叠** (3个样本均 0 match)
2. **Pred 完全模板化**: 所有 pred FG slot 输出相同坐标 `cx≈0.155,cy≈0.255`，相同类 `construction_vehicle`
3. **BUG-84 (around_weight=0.0)**: 只有 center cell 有非零权重，大量 FG target weight=0 → effective positive 极少
4. **BUG-85 (slot collapse)**: 同一 cell 3 个 slot 预测完全相同，decoder 丧失 slot 区分能力
5. **Pred marker=ignore_id(229)**: target FG 区域的 pred 甚至没产出有效 marker

**Conductor 已处理**: 识别 BUG-84 + BUG-85, 等待 CEO 决策下一步

## 🚨 磁盘空间告警
| 挂载点 | 使用率 | 剩余 |
|--------|--------|------|
| /mnt/SSD | **100%** | **4.7 GB** |
| /home | **99%** | **46 GB** |

## 🚨 训练质量告警
- [RED] pred-target 0% match — 模型预测与 target 完全无关联
- [RED] around_weight=0.0 导致 effective positive 极少 (BUG-84)
- [RED] slot collapse: 3 slot 预测完全一样 (BUG-85)
- [RED] marker 输出 ignore_id 而非有效 token — decoder 崩塌
- [RED] 三连 FAIL (ORCH_057/058/059)
- [YELLOW] /mnt/SSD 100% — 新训练硬阻塞

## ORCH 指令状态
| 指令 | 状态 | 备注 |
|------|------|------|
| ORCH_060 | **COMPLETED** | pred-target viz, 发现 BUG-84/85 |
| 新 ORCH | 待签发 | Conductor 等待 CEO 决策 |

## GiT 代码变更 (新)
```
c875db3 fix: ORCH_060 replace BEV overlay with front camera overlay panel
78f818f feat: ORCH_060 pred-target alignment visualization with real target hook
f67998d feat: ORCH_059 BUG-82 marker_init_bias for P(bg)≈80% init
```

## Agent 状态
| Agent | tmux | 备注 |
|-------|------|------|
| conductor | ✅ UP | phase2 完成, 发现 BUG-84/85, 等待 CEO |
| conductor-auto | ✅ UP | |
| critic | ✅ UP | idle |
| supervisor | ✅ UP | 本轮循环 |
| admin | ✅ UP | ORCH_060 已完成 |
| ops | ✅ UP | 正常 |

## 异常告警
- 🚨 [CRITICAL] /mnt/SSD 100% (4.7GB)
- 🚨 [RED] BUG-84: around_weight=0.0 — 需 CEO 决策修复优先级
- 🚨 [RED] BUG-85: slot collapse — decoder 架构问题
- ⚠️ [YELLOW] /home 99% (46GB)
