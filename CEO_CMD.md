# CEO 指令

请调查以下问题并撰写分析报告，保存到 shared/logs/car_precision_investigation.md 并 git push。

## 调查问题

### 1. 设计一个可信的单类 car 实验
Plan K 因 BUG-27（vocab 不兼容）结论不可信。我们需要重新设计一个干净的实验来回答"类竞争是否为 precision 上不去的瓶颈"：
- 必须使用当前最新的 vocab（num_vocal=230）和代码
- 使用当前最优的架构（2048+GELU 投影层）
- 从 P5b@3000 或更合适的 checkpoint 加载
- 在 nuScenes-mini 上只训练 car 单类，其他类全部视为背景
- 对照组：同一个 config 跑 10 类（或用已有的 P6/Plan P2 数据）
- 如果单类 car_P 显著高于 10 类 car_P（比如 0.20 vs 0.12），说明类竞争确实是瓶颈
- 如果单类 car_P 也只有 ~0.12，说明瓶颈在别处（解码长度？标签质量？特征不足？）
- 请设计具体的 config 和判定标准，准备签发 ORCH

### 2. 5 类车辆方案评估
CEO 认为完整数据集上直接做 10 类难度太大，建议先只做 5 类车辆（car/truck/bus/trailer/construction_vehicle）：
- 这样做的优势和风险是什么？
- vocab 需要怎么调整？
- 能否从当前 ORCH_024 的 10 类 checkpoint 加载并只训练 5 类？还是必须从头开始？
- 5 类 vs 10 类的显存和训练速度差异大吗？

### 3. 特征漂移深度分析
Plan M 的 car_R 从 0.699 崩到 0.489：
- 具体是 DINOv3 的哪些层发生了漂移？
- frozen 方案（Plan N）虽然稳定但 car_P 只有 0.05，这是否说明 DINOv3 的特征跟我们的任务有本质 gap？
- LoRA 方案（方案 E）能否在不漂移的前提下做域适应？预估效果如何？

### 4. ORCH_024 Full nuScenes 进展
- 当前 iter 到了多少？有没有 @2000 的 val 结果？
- 10 类在完整数据集上的表现如何？类竞争问题是否缓解？

### 5. 行动要求
- 如果分析完认为单类实验值得做，直接签发 ORCH 让 Admin 执行（用 GPU 1 或 3，不影响 ORCH_024）
- 如果认为不需要单类实验（比如 ORCH_024 @2000 数据已经回答了这个问题），说明理由
- 如果需要 Critic 深入审计某个具体问题，签发 AUDIT_REQUEST

注意：签发 ORCH 必须包含「- **状态**: PENDING」行。
