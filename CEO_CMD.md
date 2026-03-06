# CEO 指令1

请在本轮决策中阅读以下历史文件，提取对当前优化有价值的信息：

1. `shared/logs/archive/old_critic/reports/2026-03-05/critique/` — 目录下所有审计报告，包含 BUG-1~12 的发现过程和修复建议
2. `shared/logs/archive/old_conductor/reports/2026-03-05/1805_CEO质询_标签分配算法.md` — 早期标签分配算法的分析

⚠️ 重要勘误：上述第 2 个文件中提到"Construction Vehicle 独立为第五类"，这个说法是错误的。在我们使用的 nuScenes-mini 数据集中，Construction Vehicle 和 truck 本就是相互独立的类别，不需要额外拆分。请忽略该文件中关于此点的建议，其余分析内容可正常参考。

请将提取到的有价值信息整合到本轮决策中，并在 MASTER_PLAN.md 中记录你从这些历史文件中获得的关键洞察。
# CEO 指令2

请转达给 Ops（通过 tmux send-keys -t agent-ops）：

scripts/usage_watchdog.sh 有误报 BUG：扫描 agent-ops 自己的 tmux 输出时，把屏幕上表格文字中的 "rate limit" 等关键词当成了真正的限流信号，导致误触发休眠。

请修复 usage_watchdog.sh：扫描限流关键词时跳过 agent-ops，只扫描 agent-conductor、agent-admin、agent-critic、agent-supervisor。修复后 git push。
