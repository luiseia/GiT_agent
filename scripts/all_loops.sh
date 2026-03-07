#!/bin/bash
# =============================================================
# all_loops.sh — 所有 Agent 的 30 分钟闹钟
# 每 1800 秒给每个 Agent 的 tmux 会话发送一条循环指令
# 用法: nohup bash scripts/all_loops.sh &
#
# 功能:
# - flock 防多实例
# - 发送前检测 Agent 是否空闲（esc to interrupt / bypass permissions）
# - 不空闲则跳过本轮，避免打断正在工作的 Agent
# - 自动重启退出的 Claude Code
# - 自动重启挂掉的 sync_loop.sh
# - 自动关闭 rate limit 弹窗
# - 正确的启动顺序：Supervisor → 等待完成 → Conductor
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

# ─── 检测 Agent 是否空闲 ─────────────────────────────────
is_idle() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    local last_lines
    last_lines=$(tmux capture-pane -t "$session" -p | tail -5)
    # 有 "esc to interrupt" → 忙碌
    if echo "$last_lines" | grep -q 'esc to interrupt'; then
        return 1
    fi
    # 有 "bypass permissions" → 空闲
    if echo "$last_lines" | grep -q 'bypass permissions'; then
        return 0
    fi
    return 1  # 无法判断，视为忙碌
}

# ─── 检测并关闭 rate limit 弹窗 ──────────────────────────
dismiss_rate_limit() {
    local session="$1"
    local screen
    screen=$(tmux capture-pane -t "$session" -p | tail -10)
    if echo "$screen" | grep -q "Stop and wait for limit to reset"; then
        tmux send-keys -t "$session" Escape
        sleep 2
        log "⚠️ ${session}: 检测到 rate limit 弹窗，已发送 Escape 关闭"
    fi
}

# ─── 检测 Claude Code 是否还在运行 ────────────────────────
is_claude_alive() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    local last_lines
    last_lines=$(tmux capture-pane -t "$session" -p | tail -10)
    if echo "$last_lines" | grep -qE 'bypass permissions|Thinking|Working|Channeling|Tempering|Churning|Fluttering|Sautéed|Brewed|Worked|Baked|Moonwalking|Flummoxing|esc to interrupt'; then
        return 0
    fi
    return 1
}

log "all_loops.sh 启动 (PID $$)"

while true; do
    log "=== 发送 30 分钟循环指令 ==="

    # ─── 1. 检查并关闭所有 rate limit 弹窗 ───────
    for s in agent-conductor agent-supervisor agent-admin agent-critic agent-ops; do
        if tmux has-session -t "$s" 2>/dev/null; then
            dismiss_rate_limit "$s"
        fi
    done

    # ─── 2. 检查 sync_loop.sh 是否存活 ──────────
    if ! pgrep -f "sync_loop.sh" > /dev/null; then
        log "⚠️ sync_loop 已挂，正在重启..."
        rm -f /tmp/sync_loop.lock
        nohup bash "${AGENT_DIR}/scripts/sync_loop.sh" >> "${AGENT_DIR}/shared/logs/sync_cron.log" 2>&1 &
        log "✅ sync_loop 已重启 (PID $!)"
    fi

    # ─── 3. agent-supervisor（最先启动，产出摘要）──
    SUPERVISOR_SENT=0
    if tmux has-session -t agent-supervisor 2>/dev/null; then
        if ! is_claude_alive agent-supervisor; then
            log "⚠️ supervisor: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-supervisor "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-supervisor "请阅读 agents/claude_supervisor/CLAUDE.md 并开始自主循环" Enter
            log "→ supervisor: 已重启"
            SUPERVISOR_SENT=1
        elif is_idle agent-supervisor; then
            tmux send-keys -t agent-supervisor \
                "请执行下一轮自主循环：git pull 两个仓库 → 读 GiT/logs/ 训练日志和 eval 结果 → 写 shared/logs/supervisor_report_latest.md 精简摘要 → 检查指令投递状态 → 深度监控 → git push" Enter
            log "→ supervisor: 指令已发送"
            SUPERVISOR_SENT=1
        else
            log "→ supervisor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ supervisor: 会话不存在"
    fi

    # ─── 4. 等待 Supervisor 完成（最多 10 分钟）──
    if [ "$SUPERVISOR_SENT" = "1" ]; then
        log "→ supervisor: 等待完成..."
        for wait in $(seq 1 10); do
            sleep 60
            if is_idle agent-supervisor; then
                log "→ supervisor: 已完成（等待 ${wait} 分钟）"
                break
            fi
            if [ "$wait" = "10" ]; then
                log "⚠️ supervisor: 等待超时（10 分钟），继续执行"
            else
                log "→ supervisor: 仍在工作... ${wait}/10 分钟"
            fi
        done
    fi

    # ─── 5. agent-ops: 执行快照 ──────────────────
    log "→ ops: 执行 save_tmux.sh"
    bash "${AGENT_DIR}/scripts/save_tmux.sh"

    # ─── 6. agent-conductor（读到最新 Supervisor 摘要后再决策）
    if tmux has-session -t agent-conductor 2>/dev/null; then
        if ! is_claude_alive agent-conductor; then
            log "⚠️ conductor: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-conductor "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-conductor "请阅读 agents/claude_conductor/CLAUDE.md 并开始自主循环" Enter
            log "→ conductor: 已重启"
        elif is_idle agent-conductor; then
            tmux send-keys -t agent-conductor \
                "请执行下一轮自主循环：git pull → CEO_CMD.md → 读 shared/logs/supervisor_report_latest.md → STATUS.md → 检查 VERDICT → 检查 ORCH 回执 → 决策 → 更新 MASTER_PLAN.md → git push" Enter
            log "→ conductor: 指令已发送"
        else
            log "→ conductor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ conductor: 会话不存在"
    fi

    # ─── 7. agent-critic ─────────────────────────
    if tmux has-session -t agent-critic 2>/dev/null; then
        if ! is_claude_alive agent-critic; then
            PENDING_AUDITS=$(ls ${AGENT_DIR}/shared/audit/AUDIT_REQUEST_*.md 2>/dev/null | while read f; do
                id=$(basename "$f" | sed 's/AUDIT_REQUEST_//' | sed 's/\.md//')
                [ ! -f "${AGENT_DIR}/shared/audit/VERDICT_${id}.md" ] && echo "$f"
            done)
            if [ -n "$PENDING_AUDITS" ]; then
                log "⚠️ critic: 已退出但有待审计，正在重启..."
                tmux send-keys -t agent-critic "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
                sleep 15
                tmux send-keys -t agent-critic "请阅读 agents/claude_critic/CLAUDE.md 并开始自主循环" Enter
                log "→ critic: 已重启"
            else
                log "→ critic: 已退出，无待审计，不重启"
            fi
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

    # ─── 8. agent-admin ──────────────────────────
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

    log "=== 循环指令发送完毕，等待 30 分钟 ==="
    for i in $(seq 1 30); do
        sleep 60
        log "⏳ 等待中... ${i}/30 分钟"
    done
done