#!/bin/bash
# =============================================================
# conductor_handoff_sync.sh — 人工 Conductor -> auto Conductor 状态同步
# 每 60 秒检查 compact_conductor.md 是否更新；如更新则投递给 agent-conductor-auto
# =============================================================

set -u

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
SESSION="agent-conductor-auto"
LOG="${AGENT_DIR}/shared/logs/conductor_handoff_sync.log"
HANDOFF_FILE="${AGENT_DIR}/shared/logs/compact_conductor.md"
DRAFT_FILE="${AGENT_DIR}/shared/logs/DRAFT_ORCH_050.md"
STATE_FILE="/tmp/conductor_handoff_sync.state"
LOCKFILE="/tmp/conductor_handoff_sync.lock"

exec 201>"$LOCKFILE"
if ! flock -n 201; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] handoff: another instance already running" >> "$LOG"
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] handoff: $1" >> "$LOG"
}

send_agent_message() {
    local session="$1"
    local message="$2"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    tmux send-keys -t "$session" Escape
    sleep 1
    tmux send-keys -t "$session" C-u
    sleep 1
    tmux send-keys -l -t "$session" "$message"
    tmux send-keys -t "$session" C-m
    return 0
}

get_pane_command() {
    local session="$1"
    tmux display-message -p -t "$session" '#{pane_current_command}' 2>/dev/null
}

is_idle() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    local current_cmd
    current_cmd=$(get_pane_command "$session")
    if ! echo "$current_cmd" | grep -qE '^(claude|node)$'; then
        return 1
    fi
    local last_lines
    last_lines=$(tmux capture-pane -t "$session" -p | tail -5)
    if echo "$last_lines" | grep -qE 'Working \(|Thinking \(|Running…|Press up to edit queued messages'; then
        return 1
    fi
    if echo "$last_lines" | grep -q 'bypass permissions'; then
        return 0
    fi
    return 1
}

is_claude_alive() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    local current_cmd
    current_cmd=$(get_pane_command "$session")
    if echo "$current_cmd" | grep -qE '^(claude|node)$'; then
        return 0
    fi
    local last_lines
    last_lines=$(tmux capture-pane -t "$session" -p | tail -10)
    if echo "$last_lines" | grep -qE 'bypass permissions|Thinking|Working|esc to interrupt'; then
        return 0
    fi
    return 1
}

ensure_session() {
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux new-session -d -s "$SESSION" -c "$AGENT_DIR"
        tmux rename-window -t "$SESSION" "conductor-auto"
        log "created tmux session ${SESSION}"
    fi
    if ! is_claude_alive "$SESSION"; then
        send_agent_message "$SESSION" "cd ${AGENT_DIR} && claude --dangerously-skip-permissions"
        sleep 15
        send_agent_message "$SESSION" "请阅读 agents/claude_conductor/CLAUDE.md 并等待指令"
        log "restarted Claude in ${SESSION}"
        sleep 10
    fi
}

last_mtime=0
if [ -f "$STATE_FILE" ]; then
    last_mtime=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
fi

log "sync loop started"

while true; do
    if [ -f "$HANDOFF_FILE" ]; then
        current_mtime=$(stat -c %Y "$HANDOFF_FILE" 2>/dev/null || echo 0)
        if [ "$current_mtime" -gt "$last_mtime" ]; then
            ensure_session
            if is_idle "$SESSION"; then
                send_agent_message "$SESSION" "cat shared/commands/conductor_auto_shadow.md"
                log "delivered updated handoff (mtime=${current_mtime})"
                last_mtime="$current_mtime"
                echo "$last_mtime" > "$STATE_FILE"
            else
                log "handoff updated but ${SESSION} is busy; retry next cycle"
            fi
        fi
    fi
    sleep 60
done
