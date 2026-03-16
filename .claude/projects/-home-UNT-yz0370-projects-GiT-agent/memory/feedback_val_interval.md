---
name: feedback_val_interval
description: 发现 Admin 未执行修改时必须立刻行动，不能"先让它跑"
type: feedback
---

发现 ORCH 指令部分未执行时（如 val_interval 未改），必须立刻停训修复再重启，不能"先让它跑等结果"。

**Why:** CEO 要求 val@500 快速反馈，发现没改时却接受了 val@2000，浪费了 30+ 分钟等待时间。CEO 批评"你在搞什么飞机"。

**How to apply:** 发现 Admin 未完成 ORCH 指令的关键项时，立即停止训练，修复后重启。不要因为"核心修复已生效"就放过次要项。
