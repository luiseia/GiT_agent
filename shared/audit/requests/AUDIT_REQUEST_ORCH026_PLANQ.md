# AUDIT REQUEST: ORCH_026 Plan Q 结果 — 类竞争无关
> 签发: Conductor | Cycle #120 | 2026-03-09 08:45

## 审计对象
ORCH_026 (Plan Q 单类 Car 诊断) 实验结果及其对战略方向的影响

## 背景
Plan Q 设计目的: 回答 "类竞争是否为 car_P 瓶颈"。在 Mini nuScenes 上仅保留 car 类 GT (class_filter=['car']), 使用 2048+GELU proj + 预提取 DINOv3, 训练 3000 iter。

## 实验结果
- car_P@best = 0.083 (@2500)
- 判定标准: <0.12 = 类竞争无关
- **结论: 类竞争不是 car precision 瓶颈**

### 对比
| 实验 | car_P | car_R | bg_FA |
|------|-------|-------|-------|
| Plan Q @best (单类) | 0.083 | 0.513 | 0.169 |
| P6@4000 (10类, Mini) | 0.126 | 0.301 | 0.232 |
| Full@6000 (10类, DDP) | 0.090 | 0.455 | 0.331 |

## 需要审计的问题

### Q1: 结论有效性
Plan Q 使用 P5b checkpoint (1024 dim proj), 但 Plan Q 使用 2048+GELU proj, 投影层因 shape mismatch 随机初始化。Report 论证 "3000 iter 足够学习线性映射, off_cx@1500 恢复基线"。**这个混淆因素是否足以推翻 "类竞争无关" 的结论?**

### Q2: 战略影响
如果类竞争确实无关, 当前优先级需修改:
- BUG-17 (bicycle sqrt balance ~11x weight): 从 CRITICAL 降级? (它不影响 car_P)
- Deep Supervision: 仍是 #1 优先 (独立于此结论)
- 方案 D (历史 occ box): 不受影响
- 新增: 什么才是 car_P 的真正瓶颈? (数据质量? 模型容量? 训练策略?)

### Q3: 与 Full @6000 的联合解读
Full@6000 car_P=0.090 > Plan Q@best=0.083, 且 Full 仍在上升。这是否说明:
1. Full nuScenes 数据量是关键 (而非类竞争)
2. ORCH_024 方向正确, 继续训练可期待更高 car_P
3. Mini 实验已无参考价值 (永久规则#5 确认)

### Q4: BUG-17 严重性重评
如果类竞争无关, bicycle 154K FP + 振荡是否仍需修复?
- 它增加 bg_FA (资源浪费) 但不影响 car_P
- 是否降为 MEDIUM? 还是保持 CRITICAL (因为影响整体检测质量)?

### Q5: 下一步方向
结合以上, ORCH_024 后的实验优先级是否应调整为:
1. Deep Supervision (不变)
2. 方案 D 历史 occ box (不变)
3. 方案 E LoRA (上升?)
4. BUG-17 修复 (下降?)

---
*请 Critic 评估并给出 VERDICT*
