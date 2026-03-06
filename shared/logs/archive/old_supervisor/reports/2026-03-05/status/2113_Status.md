# Status — 21:13 [ORCH_2113 BUG-12 FIX RELAYED]

- **Iter**: P1 440/6000 (7.3%), ~3.0s/iter, ETA ~4h36m
- **Loss**: 最近 0.829 (cls=0.338, reg=0.491)
- **GPU**: 0=100%(22.4GB), 2=100%(23GB) [P1]; 1,3=yl0826(31.2GB)
- **ML进程**: P1 Center/Around (PID 3067481)

## ORCH_20260305_2113 — BUG-12 EMERGENCY FIX
- **收到并中继至研究员**: 21:13
- **内容**: 修复 occ_2d_box_eval.py 中 eval slot ordering mismatch
- **问题**: 训练按 depth 排序分配 GT→slot, 评估按迭代顺序分配 → FP+FN 虚高
- **修复**: 在 eval 中加入 depth-sorted assignment
- **影响**: 不影响训练, 可能改善 30-50% 假阳性
- **Deadline**: P1 iter 500 验证前 (~21:16)

## 训练状态
- P1 训练正常, loss 波动范围 0.59–3.39
- 接近 iter 500 验证 (~21:16, 约 3 min 后)
- 偶发 loss spike (3.39 @ iter 320) 但无持续异常

## Context 系统脉搏
- Supervisor: 运行正常, 批判者唤醒逻辑已集成
- Researcher #1: 接收 ORCH_2113, 执行 BUG-12 修复中
- Critic: 活跃 (审计通过, 代码正确确认)

## 指令通道
- CEO: NO_CHANGE
- ORCH: ORCH_2113 已中继 (BUG-12 fix)

## 下次关键节点
- P1 iter 500 验证 ~21:16 (CRITICAL)
- BUG-12 修复完成 → iter 500 重新评估
- 下次状态报告 ~21:23
