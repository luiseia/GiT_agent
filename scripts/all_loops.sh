#!/bin/bash
# =============================================================
# all_loops.sh — 所有 Agent 的 30 分钟闹钟
# 每 1800 秒给每个 Agent 的 tmux 会话发送一条循环指令
# 用法: nohup bash scripts/all_loops.sh &
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
LOG="${AGENT_DIR}/shared/logs/ops.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] all_loops: $1" | tee -a "$LOG"
}

log "all_loops.sh 启动 (PID $$)"

while true; do
    log "=== 发送 30 分钟循环指令 ==="

    # ─── agent-conductor ──────────────────────────
    if tmux has-session -t agent-conductor 2>/dev/null; then
        tmux send-keys -t agent-conductor \
            "请执行下一轮自主循环：git pull → CEO_CMD.md → 训练日志 → 评估 → 决策 → git push" Enter
        log "→ conductor: 指令已发送"
    else
        log "⚠️ conductor: 会话不存在"
    fi

    # ─── agent-ops: 不给自己发消息，直接执行快照 ──
    log "→ ops: 执行 save_tmux.sh"
    bash "${AGENT_DIR}/scripts/save_tmux.sh"

    # ─── agent-supervisor ─────────────────────────
    if tmux has-session -t agent-supervisor 2>/dev/null; then
        tmux send-keys -t agent-supervisor \
            "请执行下一轮自主循环：git pull → 深度检查 → 积压告警 → git push" Enter
        log "→ supervisor: 指令已发送"
    else
        log "⚠️ supervisor: 会话不存在"
    fi

    # ─── agent-critic ─────────────────────────────
    if tmux has-session -t agent-critic 2>/dev/null; then
        tmux send-keys -t agent-critic \
            "请执行下一轮检查：git pull → 检查 shared/audit/ 是否有未处理的 AUDIT_REQUEST，有则审计，无则回复无待审计" Enter
        log "→ critic: 指令已发送"
    else
        log "⚠️ critic: 会话不存在"
    fi

    # ─── agent-admin ──────────────────────────────
    if tmux has-session -t agent-admin 2>/dev/null; then
        tmux send-keys -t agent-admin \
            "请执行下一轮检查：git pull → 检查 shared/pending/ 是否有 DELIVERED 状态的 ORCH 指令，有则执行，无则回复无待执行" Enter
        log "→ admin: 指令已发送"
    else
        log "⚠️ admin: 会话不存在"
    fi

    log "=== 循环指令发送完毕，等待 1800 秒 ==="
    sleep 1800
done
