#!/bin/bash
# =============================================================
# health_check.sh — 快速检查所有 Agent 状态
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
SESSIONS=("agent-conductor" "agent-critic" "agent-supervisor" "agent-admin" "agent-ops")

echo "🏥 Agent 健康检查 — $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"

UP=0; DOWN=0
for session in "${SESSIONS[@]}"; do
    name=$(echo "$session" | sed 's/agent-//')
    if tmux has-session -t "$session" 2>/dev/null; then
        printf "  ✅ %-15s UP\n" "$name"
        UP=$((UP + 1))
    else
        printf "  ❌ %-15s DOWN\n" "$name"
        DOWN=$((DOWN + 1))
    fi
done

echo "------------------------------------------------"

# 检查积压指令
pending=0
for f in "${AGENT_DIR}"/shared/pending/ORCH_*.md; do
    [ -f "$f" ] || continue
    grep -q "PENDING\|DELIVERED" "$f" && pending=$((pending + 1))
done

# 检查待审计
unaudited=0
for f in "${AGENT_DIR}"/shared/audit/AUDIT_REQUEST_*.md; do
    [ -f "$f" ] || continue
    id=$(basename "$f" | sed 's/AUDIT_REQUEST_//' | sed 's/\.md//')
    [ ! -f "${AGENT_DIR}/shared/audit/VERDICT_${id}.md" ] && unaudited=$((unaudited + 1))
done

echo "  Agent:  ${UP} 在线 / ${DOWN} 离线"
echo "  指令:   ${pending} 个待处理"
echo "  审计:   ${unaudited} 个待判决"
echo "================================================"
