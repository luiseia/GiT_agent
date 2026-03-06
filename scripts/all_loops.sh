#!/bin/bash
# =============================================================
# all_loops.sh — 所有 Agent 的 30 分钟闹钟
# 每 1800 秒给每个 Agent 的 tmux 会话发送一条循环指令
# 用法: nohup bash scripts/all_loops.sh &
#
# 修复:
# - flock 防多实例
# - 发送前检测 Agent 是否空闲（❯ 提示符）
# - 不空闲则跳过本轮，避免打断正在工作的 Agent
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
LOG="${AGENT_DIR}/shared/logs/all_loops.log"
LOCKFILE="/tmp/all_loops.lock"

# ─── flock 防多实例 ──────────────────────────────────────
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] all_loops: 另一个实例已在运行，退出" >> "$LOG"
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] all_loops: $1" | tee -a "$LOG"
}

# ─── 检测 Agent 是否空闲（❯ 提示符在最后几行）─────────────
is_idle() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1  # 会话不存在
    fi
    local last_lines
    last_lines=$(tmux capture-pane -t "$session" -p | tail -5)
    # 检测 ❯ 提示符 或 "bypass permissions" 提示行
    if echo "$last_lines" | grep -qE '❯|^\$'; then
        return 0  # 空闲
    fi
    return 1  # 忙碌
}

# ─── 检测 Claude Code 是否还在运行 ────────────────────────
is_claude_alive() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    local last_lines
    last_lines=$(tmux capture-pane -t "$session" -p | tail -10)
    # 如果能看到 "bypass permissions" 或 ❯ 或 thinking/working 标志，说明 Claude Code 在运行
    if echo "$last_lines" | grep -qE 'bypass permissions|❯|Thinking|Working|Channeling|Tempering|Churning|Fluttering|Sautéed|Brewed|Worked'; then
        return 0
    fi
    return 1
}

log "all_loops.sh 启动 (PID $$)"

while true; do
    log "=== 发送 30 分钟循环指令 ==="

    # ─── agent-conductor ──────────────────────────
    if tmux has-session -t agent-conductor 2>/dev/null; then
        if ! is_claude_alive agent-conductor; then
            log "⚠️ conductor: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-conductor "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-conductor "请阅读 agents/claude_conductor/CLAUDE.md 并开始自主循环" Enter
            log "→ conductor: 已重启"
        elif is_idle agent-conductor; then
            tmux send-keys -t agent-conductor \
                "请执行下一轮自主循环：git pull → CEO_CMD.md → 训练日志 → 评估 → 决策 → git push" Enter
            log "→ conductor: 指令已发送"
        else
            log "→ conductor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ conductor: 会话不存在"
    fi

    # ─── agent-ops: 不给自己发消息，直接执行快照 ──
    log "→ ops: 执行 save_tmux.sh"
    bash "${AGENT_DIR}/scripts/save_tmux.sh"

    # ─── agent-supervisor ─────────────────────────
    if tmux has-session -t agent-supervisor 2>/dev/null; then
        if ! is_claude_alive agent-supervisor; then
            log "⚠️ supervisor: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-supervisor "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-supervisor "请阅读 agents/claude_supervisor/CLAUDE.md 并开始自主循环" Enter
            log "→ supervisor: 已重启"
        elif is_idle agent-supervisor; then
            tmux send-keys -t agent-supervisor \
                "请执行下一轮自主循环：git pull → 深度检查 → 积压告警 → git push" Enter
            log "→ supervisor: 指令已发送"
        else
            log "→ supervisor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ supervisor: 会话不存在"
    fi

    # ─── agent-critic ─────────────────────────────
    if tmux has-session -t agent-critic 2>/dev/null; then
        if ! is_claude_alive agent-critic; then
            log "⚠️ critic: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-critic "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-critic "请阅读 agents/claude_critic/CLAUDE.md 并开始自主循环" Enter
            log "→ critic: 已重启"
        elif is_idle agent-critic; then
            tmux send-keys -t agent-critic \
                "请执行下一轮检查：git pull → 检查 shared/audit/ 是否有未处理的 AUDIT_REQUEST，有则审计，无则回复无待审计" Enter
            log "→ critic: 指令已发送"
        else
            log "→ critic: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ critic: 会话不存在"
    fi

    # ─── agent-admin ──────────────────────────────
    if tmux has-session -t agent-admin 2>/dev/null; then
        if ! is_claude_alive agent-admin; then
            log "⚠️ admin: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-admin "cd /home/UNT/yz0370/projects/GiT && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-admin "请阅读 /home/UNT/yz0370/projects/GiT_agent/agents/claude_admin/CLAUDE.md 并开始自主循环" Enter
            log "→ admin: 已重启"
        elif is_idle agent-admin; then
            tmux send-keys -t agent-admin \
                "请执行下一轮检查：git pull → 检查 shared/pending/ 是否有 DELIVERED 状态的 ORCH 指令，有则执行，无则回复无待执行" Enter
            log "→ admin: 指令已发送"
        else
            log "→ admin: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ admin: 会话不存在"
    fi

    log "=== 循环指令发送完毕，等待 1800 秒 ==="
    sleep 1800
done