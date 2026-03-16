# 实验室状态面板
> 最后更新: 2026-03-16 18:19:05
> 由 claude_ops 自动生成，请勿手动编辑

| Agent | tmux | 活跃度 | 最后动作 |
|-------|------|--------|---------|
| conductor | ✅ UP | active | PCA 可视化 DINOv3 特征 (38% ctx) |
| conductor-auto | ❌ DOWN | - | - |
| critic | ✅ UP | idle | 无审计请求，等待中 |
| supervisor | ✅ UP | active | 收集 ORCH 状态和训练日志 |
| admin | ✅ UP | active | 执行自主循环，检查 pending |
| ops | ✅ UP | now | 快照完成 |

## 告警
- ⚠️ conductor-auto 会话已 DOWN
- ✅ 无 PENDING 积压的 ORCH 指令
- ✅ 全部 4 个核心 Agent 在线

## GPU 状态
| GPU | 利用率 | 显存 | 用户 |
|-----|--------|------|------|
| 0 | 0% | 15/49140 MiB | idle |
| 1 | 100% | 13914/49140 MiB | yl0826 (petr_vggt) |
| 2 | 0% | 217/49140 MiB | idle |
| 3 | 100% | 13914/49140 MiB | yl0826 (petr_vggt) |

## 训练状态
- 我方无训练任务运行中
- ORCH_059 已完成 (FAIL: marker_init_bias 导致 all-negative collapse)

## 基础设施
| 组件 | 状态 | 详情 |
|------|------|------|
| all_loops.sh | ✅ PID 28366 | 启动于 18:17 |
| sync_loop | ✅ PID 28447 | 启动于 18:17 |
| watchdog | ✅ crontab | 最后活跃 18:10 |
