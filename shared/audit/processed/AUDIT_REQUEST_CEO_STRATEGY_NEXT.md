# AUDIT_REQUEST: CEO 战略方案 + Conductor 补充方案
- 签发: Conductor | Cycle #87 Phase 1
- 时间: 2026-03-08 ~17:00
- 优先级: HIGH — CEO 明确要求送审

---

## 背景

ORCH_024 Full nuScenes 训练已启动 (60/40000, 4 GPU DDP, ETA 3月11日)。CEO 在 ORCH_024 启动前 (06:56) 签发了新战略指令，要求审计以下方案。

**当前状态**: ORCH_024 使用 Linear(4096,2048)+GELU+Linear(2048,768) + 在线 DINOv3 frozen, 4 GPU DDP, loss 正常下降。

**CEO_CMD.md 修改时间**: 06:56 — 早于 ORCH_024 签发 (16:10)。CEO 提到的 "当前 Linear(4096,768)" 在 ORCH_024 中已经改为 2048+GELU 双层投影。

---

## 第一部分: CEO 方案

### CEO 方案 A: DINOv3 适配层改进 (更深投影)
> Linear(4096,1024)+GELU+Linear(1024,768)

CEO 认为 4096→768 的 5.3:1 压缩是结构性瓶颈, sqrt 加权无法根治类别子空间干扰。

**Conductor 注释**:
- ORCH_024 已使用 Linear(4096,2048)+GELU+Linear(2048,768), 是方案 A 的**更宽版本**
- P5b (1024+GELU) car_P=0.116; P6 (2048, noGELU) car_P=0.129; P2 (2048+GELU) 收敛更快
- CEO 提出的 1024 hidden dim 已在 P5b 中隐式验证, 2048 更优
- **方案 A 实质上已被 ORCH_024 涵盖**, 除非 CEO 要探索更窄的瓶颈

### CEO 方案 B: DINOv3 Unfreeze (部分层)
> 直接将 DINOv3 纳入训练 (unfreeze 部分层), 同时增加更多适应层

CEO 建议:
- 先在 mini 上单类 car 验证
- 用 GPU 1,3 调试

**Conductor 注释**:
- BUG-35 曾标记 unfreeze DINOv3 有特征漂移风险
- DINOv3 ViT-7B ~7B 参数. 即使 unfreeze 最后 2 blocks, 新增可训练参数可能达 500M+
- **显存估算**: 当前 frozen 占 36-37 GB/GPU. Unfreeze 需额外存储梯度 + 优化器状态 (AdamW 3x), 粗估 +15-20 GB → 超出 A6000 48GB
- **GPU 冲突**: 当前 4 GPU 全被 ORCH_024 占用, 无法同时用 GPU 1,3 做 mini 实验

### CEO 方案 C: 单类 Car Mini 验证
> 只做 car 单类数据集验证, 确认方案有效后再扩展

CEO 认为类别竞争导致 recall 和 precision 不能同时上升。

**Conductor 注释**:
- **BUG-27 教训**: 改变 num_vocal 会使实验结果不可比. 单类需大幅改 vocab (从 230 降到 ~40?), 模型结构本质不同
- 但 CEO 的逻辑有道理: 如果单类 car 都无法获得高 P/R, 多类只会更差. 这是一个**下界测试**
- 替代方案: 保持 10 类, 但只关注 car 指标. 这样 vocab 不变, 结果可比

### CEO 方案 D: 3D 空间编码路线图
> 历史 occ box 占用信息编码 → ego 轨迹 → V2X
> 只做车辆相关类 (car/truck/bus/trailer/construction_vehicle)
> 先用过去最近 1 帧

CEO 的分阶段路线图:
1. 验证历史 occ box (过去 1 帧)
2. 加 ego 轨迹
3. V2X

**Conductor 注释**:
- nuScenes keyframes 间隔 0.5s. 60 km/h 的车在 0.5s 内移动 ~8.3m. 单帧历史的时间上下文有限
- CEO 建议只用 1 帧, Conductor 认为 2-3 帧 (1-1.5s) 更合理, 可估计速度方向
- 但 CEO 也说了 "你可以批判", 这个需要 Critic 判断
- 车辆类优先: 同意. 大目标, 运动轨迹可预测, GT 充足

---

## 第二部分: Conductor 补充方案

### Conductor 方案 E: LoRA/Adapter (替代 Unfreeze)
如果 CEO 的核心目标是让 DINOv3 适应 BEV 占用域, 全量 unfreeze 的内存和风险都太高. 建议:
- 在 frozen DINOv3 每层后插入轻量 adapter (LoRA rank=16/32)
- 新增可训练参数 ~10-50M (vs unfreeze ~500M+)
- 显存增量可控 (~2-5 GB)
- 保留 DINOv3 预训练知识, 同时获得域适应
- **同样在 mini 上先验证, 不改 num_vocal**

### Conductor 方案 F: 多尺度 DINOv3 特征聚合
当前只用 DINOv3 最终层输出 (4096 dim). 但 ViT 中间层捕获不同抽象层次:
- 早期层: 纹理/边缘, 对小目标有用
- 后期层: 语义, 对大目标有用
- 聚合多层特征 (如 FPN 式结构) 可能改善类别不均问题
- 缺点: 增加计算量和内存, 需要仔细设计聚合方式

### Conductor 方案 G: 等 ORCH_024 @2000 再决策
- ORCH_024 @2000 val ETA ~20:00 今天
- 这是 Full nuScenes 的第一个有意义 eval
- **建议: 先不打断 ORCH_024, 等 @2000 结果出来再决定是否需要探索替代方案**
- 如果 car_P > 0.10 @2000: ORCH_024 路线正确, CEO 方案可作为后续优化
- 如果 car_P < 0.05 @2000: 可能需要重新考虑, 此时释放 GPU 做 mini 实验

---

## 审计问题 (请 Critic 逐一回答)

### Q1: GPU 资源冲突
CEO 要求用 GPU 1,3 做 mini 实验, 但 ORCH_024 占用 4 GPU. 应该:
- (a) 中断 ORCH_024, 缩至 2 GPU (训练时间翻倍至 ~6 天)
- (b) 等 ORCH_024 @2000 结果 (~20:00 今天) 再决策
- (c) 等 ORCH_024 完成 (~3 月 11 日) 再做新实验
- (d) 其他

### Q2: DINOv3 Unfreeze (方案 B) 可行性
考虑 BUG-35 (特征漂移), A6000 48GB 显存限制, 和 7B 参数量:
- 全量/部分 unfreeze 是否值得尝试?
- LoRA/Adapter (方案 E) 是否是更好的替代?
- 如果要做, 在 mini 单类还是多类上验证?

### Q3: 单类 Car 验证 (方案 C) 的实验设计
- 改 num_vocal 做单类: 结果是否可推广到多类? (BUG-27 教训)
- 如果做, vocab 应该怎么设计?
- 保持 10 类只看 car 指标是否足够替代?

### Q4: 历史 Occ Box 时间窗口
- CEO 建议 1 帧, Conductor 建议 2-3 帧. 哪个更合理?
- nuScenes 提供多少历史帧? 计算/内存开销如何?
- 编码方式: 直接拼接 token 还是用 attention?

### Q5: 方案优先级排序
考虑当前状态 (ORCH_024 运行中, 3 天后完成), 请排序:
- ORCH_024 继续 vs 中断
- 方案 B (unfreeze) vs 方案 E (LoRA) vs 方案 F (多尺度)
- 单类验证 vs 多类
- 3D 编码何时开始
- 整体路线图建议

### Q6: CEO 方案 A 是否已被 ORCH_024 涵盖?
CEO 提出的 Linear(4096,1024)+GELU+Linear(1024,768) 与当前 ORCH_024 的 Linear(4096,2048)+GELU+Linear(2048,768) 相比:
- 2048 已经解决了 CEO 担心的 5.3:1 压缩问题?
- 还是需要额外探索 1024 或其他 hidden dim?

---

## 决策约束

1. **ORCH_024 是当前最高优先级** — Mini 验证已完成, Full nuScenes 是核心目标
2. **GPU 资源有限** — 4 × A6000, 当前全占满
3. **BUG-27/31 教训** — 改 num_vocal = 实验无效, 必须警惕
4. **BUG-35 教训** — DINOv3 unfreeze 有特征漂移风险
5. **CEO 明确要求送审** — 需要 Critic 对所有方案做独立评估

---

## 期望输出

1. 每个方案的独立评估 (可行性, 风险, 预期收益)
2. 方案优先级排序
3. GPU 资源分配建议 (是否中断 ORCH_024)
4. 实验设计建议 (如果做 mini 实验, 具体参数)
5. 3D 编码路线图建议 (时间窗口, 编码方式, 时间线)
