# 审计请求 — P2_FINAL
- **审计对象**: P2 训练全程结果 + BUG-8 修复方案
- **关注点**:
  1. P2@6000 最终评估: 9/14 超越 P1, 但 truck_R -19%, car_R -5%, car_P -14% — 这些下降是否可接受?
  2. BUG-8 (cls loss 缺 bg_balance_weight, git_occ_head.py:871-881): 修复是否安全? 预期效果?
  3. P3 是否值得启动? 从 P2@6000 加载权重 + BUG-8 修复, 预期 truck_R 改善多少?
  4. 是否需要同时修复 BUG-10 (optimizer cold start)?
- **上下文**:
  - P2 验证了 BUG-9 fix (max_norm=10.0), 精度和 offset 全面超越 P1
  - truck_R 下降的根因: Sign-SGD "意外保护" 消失 + BUG-8 bg 梯度挤压
  - 历史洞察 #4: truck 仅占总梯度 2.1%, bg 14.3% (7x 差异)
  - 4 GPU 全部空闲, 可立即启动 P3
