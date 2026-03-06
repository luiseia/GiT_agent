#!/bin/bash
# =============================================================
# sync_loop.sh — Supervisor 的自动同步循环
# 每 60 秒扫描 pending/ 并投递指令
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
CODE_DIR="/home/UNT/yz0370/projects/GiT"
LOG="${AGENT_DIR}/shared/logs/supervisor.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"
}

log "🔁 Supervisor 同步循环启动"

while true; do
    cd "$AGENT_DIR"
    git pull --quiet 2>/dev/null

    # ─── 投递 PENDING 指令 → Admin ────────────────
    for f in "${AGENT_DIR}"/shared/pending/ORCH_*.md; do
        [ -f "$f" ] || continue
        if grep -q "PENDING" "$f" 2>/dev/null; then
            fname=$(basename "$f")
            if tmux has-session -t agent-admin 2>/dev/null; then
                # Admin 需要在 GiT_agent 里 pull 看指令
                tmux send-keys -t agent-admin \
                    "cd ${AGENT_DIR} && git pull && cat shared/pending/${fname} && echo '📬 新指令: ${fname}' && cd ${CODE_DIR}" Enter
                sed -i 's/PENDING/DELIVERED/' "$f"
                log "📨 投递: ${fname} → admin"
                git add "$f" "$LOG" && git commit -m "supervisor: delivered ${fname}" --quiet
                git push --quiet 2>/dev/null
            else
                log "⚠️ agent-admin 不在线，跳过 ${fname}"
            fi
        fi
    done

    # ─── 通知 Critic 有新审计请求 ──────────────────
    for f in "${AGENT_DIR}"/shared/audit/AUDIT_REQUEST_*.md; do
        [ -f "$f" ] || continue
        id=$(basename "$f" | sed 's/AUDIT_REQUEST_//' | sed 's/\.md//')
        if [ ! -f "${AGENT_DIR}/shared/audit/VERDICT_${id}.md" ]; then
            if tmux has-session -t agent-critic 2>/dev/null; then
                tmux send-keys -t agent-critic \
                    "cd ${AGENT_DIR} && git pull && echo '🔔 审计请求: ${id}'" Enter
                log "🔔 通知 Critic: REQUEST_${id}"
            fi
        fi
    done

    sleep 60
done
