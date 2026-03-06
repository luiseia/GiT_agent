# GiT_agent — 多 Agent 调度中心（方案 B：双仓库分离）

## 一、设计哲学

```
GiT           → 研究代码 + 模型权重 + 训练日志   (Admin 的代码工作区)
GiT_agent     → Agent 配置 + 调度通信 + 状态快照  (所有 Agent 的共享意识)
```

两个仓库完全独立，各自有干净的 git 历史：
- GiT 的 commit 全是代码变更：`fix eval bug`, `add P1 loss function`
- GiT_agent 的 commit 全是调度事件：`conductor: orch 2114`, `ops: snapshot 21:30`

## 二、目录结构

```
/home/UNT/yz0370/projects/
│
├── GiT/                          ← 研究代码仓库（已有，不动）
│   ├── *.py                      # 训练/评估脚本
│   ├── configs/                  # 实验配置
│   ├── checkpoints/              # 模型权重
│   └── logs/                     # 训练原始日志
│
└── GiT_agent/                    ← 调度仓库（新建）
    ├── ARCHITECTURE.md           # 本文件
    ├── MASTER_PLAN.md            # Conductor 维护的全局战略
    ├── STATUS.md                 # Ops 自动生成的实时状态面板
    │
    ├── agents/                   # 每个 Agent 的 CLAUDE.md
    │   ├── claude_conductor/
    │   ├── claude_critic/
    │   ├── claude_supervisor/
    │   ├── claude_admin/
    │   └── claude_ops/
    │
    ├── shared/                   # Agent 间共享通信区
    │   ├── pending/              # ORCH 指令队列
    │   ├── audit/                # 审计请求与判决
    │   ├── logs/                 # Agent 运行日志（非训练日志）
    │   └── snapshots/            # tmux 屏幕快照
    │
    └── scripts/                  # 运维脚本
        ├── launch_all.sh
        ├── save_tmux.sh
        ├── sync_loop.sh
        └── health_check.sh
```

## 三、Agent 角色矩阵

| Agent | tmux 会话名 | 工作目录 | 职责 |
|-------|------------|----------|------|
| **Conductor** | `agent-conductor` | `GiT_agent/` | 决策、规划、调度 |
| **Critic** | `agent-critic` | `GiT_agent/` (读 `GiT/` 审计代码) | 逻辑审计 |
| **Supervisor** | `agent-supervisor` | `GiT_agent/` | 指令投递、同步 |
| **Admin** | `agent-admin` | **`GiT/`** (读写代码) + 读 `GiT_agent/shared/` | 代码执行 |
| **Ops** | `agent-ops` | `GiT_agent/` | tmux 快照、健康监控 |

### 关键：Admin 的双仓库操作

Admin 是唯一需要操作两个仓库的 Agent：
```bash
# Admin 改代码 → 在 GiT 里 commit
cd /home/UNT/yz0370/projects/GiT
vim occ_2d_box_eval.py
git add . && git commit -m "fix BUG-12" && git push

# Admin 汇报完成 → 在 GiT_agent 里更新
cd /home/UNT/yz0370/projects/GiT_agent
sed -i 's/DELIVERED/DONE/' shared/pending/ORCH_XXXX.md
echo "[$(date)] DONE ORCH_XXXX: fixed BUG-12" >> shared/logs/admin.log
git add . && git commit -m "admin: done ORCH_XXXX" && git push
```

## 四、数据桥接：训练日志如何流向 Conductor

Admin 不复制训练日志到 GiT_agent。而是 Conductor 直接去 GiT/ 读：
```bash
# Conductor 读取训练数据（只读，不修改 GiT 仓库）
cat /home/UNT/yz0370/projects/GiT/logs/training_P1.log
cat /home/UNT/yz0370/projects/GiT/logs/eval_P1_iter1000.json
```

或者 Admin 在完成指令时，把**摘要**写入 GiT_agent：
```bash
# Admin 写摘要（不是复制整个日志）
cat > shared/logs/report_ORCH_XXXX.md << 'EOF'
## 训练摘要 — ORCH_XXXX
- iter: 1000 → 2000
- loss: 0.234 → 0.189 (↓19%)
- 完整日志: GiT/logs/training_P1_20250615.log
EOF
```

## 五、通信协议（与方案 A 相同）

### 5.1 指令流
```
Conductor 写入:  GiT_agent/shared/pending/ORCH_{ts}_{id}.md   → PENDING
Supervisor 投递: 通知 Admin → 标记 DELIVERED
Admin 执行完成:  标记 DONE + 写摘要到 shared/logs/
```

### 5.2 审计流
```
Conductor:  shared/audit/AUDIT_REQUEST_{id}.md
Critic:     读 GiT/ 审查代码 → shared/audit/VERDICT_{id}.md
```

### 5.3 快照流
```
Ops 每 5 分钟: 捕获 tmux → shared/snapshots/ → 更新 STATUS.md → git push
```

## 六、迁移检查清单

- [ ] GiT 仓库保持不动
- [ ] 在 /projects/ 下创建 GiT_agent 目录（解压本包）
- [ ] `gh repo create GiT_agent --private` 并推送
- [ ] 运行 `bash scripts/launch_all.sh` 启动 5 个 tmux
- [ ] 每个 tmux 窗口中 `cd` 到正确目录并启动 Claude Code
- [ ] 验证 Admin 能同时操作两个仓库
- [ ] 验证 Conductor 能读到 GiT/logs/ 的训练数据
