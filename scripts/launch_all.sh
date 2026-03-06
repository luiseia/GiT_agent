#!/bin/bash
# =============================================================
# launch_all.sh — 一键启动 5 个 Agent 的 tmux 会话
# 双仓库模式: Admin → GiT/   其他 Agent → GiT_agent/
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
CODE_DIR="/home/UNT/yz0370/projects/GiT"

echo "🚀 启动 GiT_agent 多 Agent 实验室（双仓库模式）"
echo "   调度仓库: ${AGENT_DIR}"
echo "   代码仓库: ${CODE_DIR}"
echo "================================================"

# Agent 名 → 工作目录
declare -A WORKDIRS=(
    [conductor]="$AGENT_DIR"
    [critic]="$AGENT_DIR"
    [supervisor]="$AGENT_DIR"
    [admin]="$CODE_DIR"
    [ops]="$AGENT_DIR"
)

for agent in conductor critic supervisor admin ops; do
    SESSION="agent-${agent}"
    WORKDIR="${WORKDIRS[$agent]}"
    CLAUDE_MD="${AGENT_DIR}/agents/claude_${agent}/CLAUDE.md"

    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "⏭️  ${SESSION} 已在运行，跳过"
        continue
    fi

    tmux new-session -d -s "$SESSION" -c "$WORKDIR"
    tmux rename-window -t "$SESSION" "${agent}"

    # 两个仓库都 pull
    tmux send-keys -t "$SESSION" "cd ${AGENT_DIR} && git pull 2>/dev/null" Enter
    if [ "$agent" = "admin" ]; then
        sleep 1
        tmux send-keys -t "$SESSION" "cd ${CODE_DIR} && git pull 2>/dev/null" Enter
    fi

    sleep 1
    tmux send-keys -t "$SESSION" "echo ''" Enter
    tmux send-keys -t "$SESSION" "echo '🤖 Agent: claude_${agent}'" Enter
    tmux send-keys -t "$SESSION" "echo '📂 工作目录: ${WORKDIR}'" Enter
    tmux send-keys -t "$SESSION" "echo '📄 CLAUDE.md: ${CLAUDE_MD}'" Enter

    if [ "$agent" = "admin" ]; then
        tmux send-keys -t "$SESSION" "echo '⚡ 双仓库模式: CODE=${CODE_DIR}  AGENT=${AGENT_DIR}'" Enter
        tmux send-keys -t "$SESSION" "export CODE=${CODE_DIR}" Enter
        tmux send-keys -t "$SESSION" "export AGENT=${AGENT_DIR}" Enter
    fi

    tmux send-keys -t "$SESSION" "echo '➡️  请执行 claude 启动 Claude Code'" Enter

    echo "✅ ${SESSION} 已创建 → ${WORKDIR}"
done

echo ""
echo "================================================"
echo "📋 tmux 会话列表:"
tmux list-sessions 2>/dev/null || echo "  (无)"
echo ""
echo "💡 操作:"
echo "  tmux attach -t agent-conductor    # 进入指挥家"
echo "  tmux attach -t agent-admin        # 进入研究员（GiT 目录）"
echo "  tmux attach -t agent-ops          # 进入运维管理员"
echo "  Ctrl+B D                           # 退出（不关闭）"
echo "  bash scripts/health_check.sh       # 快速健康检查"
echo "================================================"
