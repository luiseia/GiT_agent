#!/bin/bash
# =============================================================
# all_loops_tmux.sh — 用独立 tmux 会话托管 all_loops.sh
# 用法:
#   bash scripts/all_loops_tmux.sh start
#   bash scripts/all_loops_tmux.sh stop
#   bash scripts/all_loops_tmux.sh restart
#   bash scripts/all_loops_tmux.sh status
#   bash scripts/all_loops_tmux.sh attach
# =============================================================

set -u

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
SESSION="ops-all-loops"
WINDOW="all_loops"
LOG="${AGENT_DIR}/shared/logs/all_loops.log"
HEARTBEAT="${AGENT_DIR}/shared/logs/all_loops.heartbeat"
LOCKFILE="/tmp/all_loops.lock"

is_session_up() {
    tmux has-session -t "$SESSION" 2>/dev/null
}

print_status() {
    if is_session_up; then
        echo "tmux_session=UP (${SESSION})"
    else
        echo "tmux_session=DOWN (${SESSION})"
    fi

    if pgrep -f "/home/UNT/yz0370/projects/GiT_agent/scripts/all_loops.sh" >/dev/null; then
        echo "all_loops_process=UP"
        pgrep -af "/home/UNT/yz0370/projects/GiT_agent/scripts/all_loops.sh"
    else
        echo "all_loops_process=DOWN"
    fi

    if [ -f "$HEARTBEAT" ]; then
        echo "--- heartbeat ---"
        cat "$HEARTBEAT"
    else
        echo "heartbeat=missing"
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
        "while true; do bash ${AGENT_DIR}/scripts/all_loops.sh; code=\$?; echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] all_loops_tmux: all_loops.sh exited code=\${code}, restarting in 5s\" >> ${LOG}; sleep 5; done" \
        C-m
    echo "started tmux session ${SESSION}"
    sleep 1
    print_status
}

stop_loop() {
    pkill -f "/home/UNT/yz0370/projects/GiT_agent/scripts/all_loops.sh" 2>/dev/null || true
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
