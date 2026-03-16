#!/bin/bash
# =============================================================
# conductor_handoff_tmux.sh — 用独立 tmux 会话托管 conductor_handoff_sync.sh
# 用法:
#   bash scripts/conductor_handoff_tmux.sh start
#   bash scripts/conductor_handoff_tmux.sh stop
#   bash scripts/conductor_handoff_tmux.sh restart
#   bash scripts/conductor_handoff_tmux.sh status
#   bash scripts/conductor_handoff_tmux.sh attach
# =============================================================

set -u

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
SESSION="ops-conductor-handoff"
WINDOW="handoff-sync"
LOG="${AGENT_DIR}/shared/logs/conductor_handoff_sync.log"
LOCKFILE="/tmp/conductor_handoff_sync.lock"

is_session_up() {
    tmux has-session -t "$SESSION" 2>/dev/null
}

print_status() {
    if is_session_up; then
        echo "tmux_session=UP (${SESSION})"
    else
        echo "tmux_session=DOWN (${SESSION})"
    fi

    if pgrep -f "/home/UNT/yz0370/projects/GiT_agent/scripts/conductor_handoff_sync.sh" >/dev/null; then
        echo "handoff_sync_process=UP"
        pgrep -af "/home/UNT/yz0370/projects/GiT_agent/scripts/conductor_handoff_sync.sh"
    else
        echo "handoff_sync_process=DOWN"
    fi
}

start_loop() {
    if is_session_up; then
        echo "tmux session ${SESSION} already exists"
        print_status
        return 0
    fi

    tmux new-session -d -s "$SESSION" -n "$WINDOW" -c "$AGENT_DIR"
    tmux send-keys -t "${SESSION}:${WINDOW}" \
        "while true; do bash ${AGENT_DIR}/scripts/conductor_handoff_sync.sh; code=\$?; echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] handoff_tmux: sync exited code=\${code}, restarting in 5s\" >> ${LOG}; sleep 5; done" \
        C-m
    echo "started tmux session ${SESSION}"
    sleep 1
    print_status
}

stop_loop() {
    pkill -f "/home/UNT/yz0370/projects/GiT_agent/scripts/conductor_handoff_sync.sh" 2>/dev/null || true
    if is_session_up; then
        tmux kill-session -t "$SESSION"
        echo "stopped tmux session ${SESSION}"
    else
        echo "tmux session ${SESSION} not running"
    fi
    rm -f "$LOCKFILE" 2>/dev/null || true
}

attach_loop() {
    if ! is_session_up; then
        echo "tmux session ${SESSION} not running"
        exit 1
    fi
    exec tmux attach -t "$SESSION"
}

case "${1:-status}" in
    start)
        start_loop
        ;;
    stop)
        stop_loop
        ;;
    restart)
        stop_loop
        sleep 1
        start_loop
        ;;
    status)
        print_status
        ;;
    attach)
        attach_loop
        ;;
    *)
        echo "usage: $0 {start|stop|restart|status|attach}"
        exit 1
        ;;
esac
