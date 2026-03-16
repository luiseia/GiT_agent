#!/bin/bash
# =============================================================
# usage_watchdog.sh — 用量监控 + context 监控 + 自动休眠/恢复
# 由 crontab 运行: 0,10,20,30,40,50 * * * * (flock 防重入)
#
# 功能:
# 1. /usage 发给 ops，不打断 conductor/critic
# 2. 发 /usage 前检测 agent 是否空闲
# 3. 限流关键词收紧为完整短语
# 4. 跳过 agent-ops 的限流扫描
# 5. context 监控 + 保存上下文 + /compact + 恢复上下文
# 6. 恢复后检查 Claude Code 是否存活，自动重启
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
LOG="${AGENT_DIR}/shared/logs/watchdog.log"
LOCKFILE="/tmp/usage_watchdog.lock"
HIBERNATE_FLAG="/tmp/usage_watchdog_hibernating"
NO_USAGE_FLAG="/tmp/usage_watchdog_no_usage_cmd"
SESSIONS=("agent-conductor" "agent-critic" "agent-supervisor" "agent-admin")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] watchdog: $1" | tee -a "$LOG"
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

# ─── 检测 Claude Code 是否还在运行 ────────────────────────
is_claude_alive() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    local last_lines
    last_lines=$(tmux capture-pane -t "$session" -p | tail -10)
    if echo "$last_lines" | grep -qE 'bypass permissions|❯|Thinking|Working|Channeling|Tempering|Churning|Fluttering|Sautéed|Brewed|Worked'; then
        return 0
    fi
    return 1
}

# ─── 如果正在休眠中，跳过 ─────────────────────────────────
if [ -f "$HIBERNATE_FLAG" ]; then
    log "休眠中，跳过本轮检查"
    exit 0
fi

log "=== 用量检查开始 ==="

TRIGGER=0
TRIGGER_REASON=""
USAGE_PCT=""
RESET_INFO=""

# =============================================================
# 检测方式 1: /usage 命令
# 发给 ops，避免打断 conductor/critic
# 若当前客户端不支持 /usage，则自动停用该检测方式
# =============================================================
USAGE_TARGET="agent-ops"
if [ -f "$NO_USAGE_FLAG" ]; then
    log "→ 已检测到当前客户端不支持 /usage，跳过用量检查"
elif tmux has-session -t "$USAGE_TARGET" 2>/dev/null && is_idle "$USAGE_TARGET"; then
    tmux send-keys -t "$USAGE_TARGET" "/usage" Enter
    sleep 5
    USAGE_OUTPUT=$(tmux capture-pane -t "$USAGE_TARGET" -p -S -30)
    tmux send-keys -t "$USAGE_TARGET" Escape
    sleep 1

    if echo "$USAGE_OUTPUT" | grep -qi 'Status dialog dismissed'; then
        log "⚠️ /usage 在当前客户端不可用（Status dialog dismissed），后续跳过该检测"
        touch "$NO_USAGE_FLAG"
        USAGE_OUTPUT=""
    fi

    # 解析用量百分比
    USAGE_PCT=$(echo "$USAGE_OUTPUT" | grep -oP '\d+\.?\d*%\s+used' | head -1 | grep -oP '\d+\.?\d*')
    # 解析刷新
    RESET_INFO=$(echo "$USAGE_OUTPUT" | grep -oiP 'Resets\s+.*' | head -1)

    if [ -n "$USAGE_PCT" ]; then
        log "用量: ${USAGE_PCT}%  |  ${RESET_INFO:-无刷新信息}"
        OVER=$(echo "$USAGE_PCT >= 80" | bc -l 2>/dev/null)
        if [ "$OVER" = "1" ]; then
            TRIGGER=1
            TRIGGER_REASON="用量超过 80% (${USAGE_PCT}%)"
        fi
    else
        log "⚠️ 无法解析 /usage 输出（target: ${USAGE_TARGET}）"
    fi
elif tmux has-session -t "$USAGE_TARGET" 2>/dev/null; then
    log "→ ${USAGE_TARGET} 正在忙碌，跳过用量检查"
else
    log "⚠️ ${USAGE_TARGET} 会话不存在，跳过用量检查"
fi

# =============================================================
# 检测方式 2: 限流关键词扫描（收紧匹配，跳过 agent-ops）
# =============================================================
RATE_LIMIT_PATTERN="usage limit reached|rate limit exceeded|too many requests|Error 429|you've hit your"
for session in "${SESSIONS[@]}"; do
    if tmux has-session -t "$session" 2>/dev/null; then
        PANE_OUTPUT=$(tmux capture-pane -t "$session" -p | tail -5)
        MATCH=$(echo "$PANE_OUTPUT" | grep -iE "$RATE_LIMIT_PATTERN" | head -3)
        if [ -n "$MATCH" ]; then
            log "🚨 ${session} 检测到限流: $(echo "$MATCH" | head -1)"
            TRIGGER=1
            TRIGGER_REASON="${TRIGGER_REASON:+${TRIGGER_REASON} | }${session} 触发限流"
        fi
    fi
done

# =============================================================
# 检测方式 3: Context 剩余监控 + 保存上下文 + /compact + 恢复
# 注意: /compact 是 CLI 命令，必须由 bash 直接发送，不能让 Agent 自己执行
# 支持两种格式: "Context left until auto-compact: X%" 和 "X% until auto-compact"
# =============================================================

for session in "${SESSIONS[@]}"; do
    if tmux has-session -t "$session" 2>/dev/null; then
        PANE_OUTPUT=$(tmux capture-pane -t "$session" -p | tail -10)
        CTX_LEFT=""
        # 格式 1: "8% until auto-compact"
        CTX_LEFT=$(echo "$PANE_OUTPUT" | grep -oP '\d+(?=%\s*until auto-compact)' | tail -1)
        # 格式 2: "Context left until auto-compact: 8%"  或 "Context left: 8"
        if [ -z "$CTX_LEFT" ]; then
            CTX_LEFT=$(echo "$PANE_OUTPUT" | grep -oiP 'Context left[^:]*:\s*\d+' | grep -oP '\d+' | tail -1)
        fi
        if [ -n "$CTX_LEFT" ] && [ "$CTX_LEFT" -lt 15 ]; then
            agent_name=$(echo "$session" | sed 's/agent-//')
            log "⚠️ ${session} context 剩余 ${CTX_LEFT}%"
            if is_idle "$session"; then
                # 步骤1: 让 Agent 保存上下文
                tmux send-keys -t "$session" \
                    "请将当前工作上下文（正在做什么、进度、待办、关键数据）保存到 shared/logs/compact_${agent_name}.md 并 git push" Enter
                log "→ ${session}: 已发送保存指令，等待 60 秒"
                sleep 60

                # 步骤2: bash 直接发 /compact（CLI 命令）
                tmux send-keys -t "$session" "/compact" Enter
                log "→ ${session}: 已发送 /compact，等待 30 秒"
                sleep 30

                # 步骤3: 让 Agent 恢复上下文
                tmux send-keys -t "$session" \
                    "compact 已完成，请读取 shared/logs/compact_${agent_name}.md 恢复上下文并继续工作" Enter
                log "→ ${session}: 已发送恢复指令"
            else
                log "→ ${session}: 需要 compact 但正在忙碌，下轮再试"
            fi
        fi
    fi
done

# =============================================================
# 未触发：正常退出
# =============================================================
if [ "$TRIGGER" -eq 0 ]; then
    log "✅ 用量正常，无需休眠"
    exit 0
fi

# =============================================================
# 触发休眠流程
# =============================================================
log "🚨🚨🚨 触发休眠: ${TRIGGER_REASON}"
touch "$HIBERNATE_FLAG"

# ─── 计算精确恢复秒数 ────────────────────────────────────
SLEEP_SECONDS=3600  # 默认 1 小时
if [ -n "$RESET_INFO" ]; then
    HOURS=$(echo "$RESET_INFO" | grep -oP '\d+(?=\s*hr)' || echo 0)
    MINUTES=$(echo "$RESET_INFO" | grep -oP '\d+(?=\s*min)' || echo 0)
    [ -z "$HOURS" ] && HOURS=0
    [ -z "$MINUTES" ] && MINUTES=0
    CALC=$((HOURS * 3600 + MINUTES * 60 + 300))  # +5 分钟缓冲
    if [ "$CALC" -gt 300 ]; then
        SLEEP_SECONDS=$CALC
    fi
fi

# 也尝试解析 "Resets 5am" 格式
if echo "$RESET_INFO" | grep -qiP 'Resets\s+\d+\s*(am|pm)'; then
    RESET_HOUR=$(echo "$RESET_INFO" | grep -oiP '\d+(?=\s*(am|pm))' | head -1)
    AMPM=$(echo "$RESET_INFO" | grep -oiP '(am|pm)' | head -1 | tr 'A-Z' 'a-z')
    if [ "$AMPM" = "pm" ] && [ "$RESET_HOUR" -ne 12 ]; then
        RESET_HOUR=$((RESET_HOUR + 12))
    elif [ "$AMPM" = "am" ] && [ "$RESET_HOUR" -eq 12 ]; then
        RESET_HOUR=0
    fi
    NOW_EPOCH=$(date +%s)
    TODAY_RESET=$(date -d "today ${RESET_HOUR}:00" +%s 2>/dev/null)
    if [ -n "$TODAY_RESET" ]; then
        if [ "$TODAY_RESET" -le "$NOW_EPOCH" ]; then
            TODAY_RESET=$((TODAY_RESET + 86400))
        fi
        CALC=$((TODAY_RESET - NOW_EPOCH + 300))
        if [ "$CALC" -gt 300 ]; then
            SLEEP_SECONDS=$CALC
        fi
    fi
fi

RESUME_TIME=$(date -d "+${SLEEP_SECONDS} seconds" '+%Y-%m-%d %H:%M:%S')
log "预计恢复时间: ${RESUME_TIME} (休眠 ${SLEEP_SECONDS} 秒)"

# ─── 给每个 Agent 发送保存指令 ────────────────────────────
if tmux has-session -t agent-conductor 2>/dev/null; then
    tmux send-keys -t agent-conductor \
        "紧急休眠：请将当前所有任务状态、MASTER_PLAN 进度、待处理决策保存到 shared/logs/hibernate_conductor.md，然后 git push" Enter
    log "→ conductor: 休眠保存指令已发送"
fi

if tmux has-session -t agent-admin 2>/dev/null; then
    tmux send-keys -t agent-admin \
        "紧急休眠：请将当前正在执行的 ORCH 指令、训练进度（iter/loss/lr）、未完成的代码修改保存到 shared/logs/hibernate_admin.md，然后 git push" Enter
    log "→ admin: 休眠保存指令已发送"
fi

if tmux has-session -t agent-critic 2>/dev/null; then
    tmux send-keys -t agent-critic \
        "紧急休眠：请将当前正在进行的审计状态、已发现但未写入的 BUG 保存到 shared/logs/hibernate_critic.md，然后 git push" Enter
    log "→ critic: 休眠保存指令已发送"
fi

if tmux has-session -t agent-supervisor 2>/dev/null; then
    tmux send-keys -t agent-supervisor \
        "紧急休眠：请将当前投递队列状态、未完成的投递记录保存到 shared/logs/hibernate_supervisor.md，然后 git push" Enter
    log "→ supervisor: 休眠保存指令已发送"
fi

# ─── ops 自己写入休眠状态 ─────────────────────────────────
{
    echo "# Ops 休眠快照"
    echo "> 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## 触发原因"
    echo "- ${TRIGGER_REASON}"
    echo "- 用量: ${USAGE_PCT:-未知}%"
    echo "- 刷新信息: ${RESET_INFO:-未知}"
    echo "- 预计恢复: ${RESUME_TIME}"
    echo "- 休眠秒数: ${SLEEP_SECONDS}"
    echo ""
    echo "## 各 Agent tmux 最后状态"
    for session in "${SESSIONS[@]}" agent-ops; do
        echo ""
        echo "### ${session}"
        if tmux has-session -t "$session" 2>/dev/null; then
            echo '```'
            tmux capture-pane -t "$session" -p -S -30 | tail -20
            echo '```'
        else
            echo "会话不存在"
        fi
    done
} > "${AGENT_DIR}/shared/logs/hibernate_ops.md"
log "→ ops: hibernate_ops.md 已写入"

# ─── 等待 3 分钟让 Agent 完成保存 ────────────────────────
log "等待 180 秒让所有 Agent 完成保存..."
sleep 180

# ─── git push 保存所有休眠数据 ────────────────────────────
cd "$AGENT_DIR"
git add shared/logs/hibernate_*.md shared/logs/watchdog.log STATUS.md 2>/dev/null
git diff --cached --quiet || {
    git commit -m "ops: hibernate — ${TRIGGER_REASON}"
    git push
}
log "休眠数据已 push"

# ─── 停止 all_loops tmux 托管 ───────────────────────────
if bash "${AGENT_DIR}/scripts/all_loops_tmux.sh" stop >> "$LOG" 2>&1; then
    log "已停止 all_loops tmux 托管"
else
    log "⚠️ 停止 all_loops tmux 托管失败"
fi

# ─── 休眠等待 ────────────────────────────────────────────
log "💤 开始休眠 ${SLEEP_SECONDS} 秒，预计 ${RESUME_TIME} 恢复"
sleep "$SLEEP_SECONDS"

# =============================================================
# 恢复流程
# =============================================================
log "⏰ 休眠结束，开始恢复"
rm -f "$HIBERNATE_FLAG"

# ─── 重启 all_loops tmux 托管 ───────────────────────────
if bash "${AGENT_DIR}/scripts/all_loops_tmux.sh" start >> "$LOG" 2>&1; then
    log "✅ all_loops tmux 托管已重启"
else
    log "⚠️ all_loops tmux 托管重启失败"
fi

# ─── 检查每个 Agent 是否存活，死了就重启 ──────────────────
for session in "${SESSIONS[@]}"; do
    if tmux has-session -t "$session" 2>/dev/null; then
        if ! is_claude_alive "$session"; then
            agent_name=$(echo "$session" | sed 's/agent-//')
            if [ "$agent_name" = "admin" ]; then
                WORK_DIR="/home/UNT/yz0370/projects/GiT"
            else
                WORK_DIR="$AGENT_DIR"
            fi
            log "⚠️ ${session}: Claude Code 已退出，正在重启..."
            tmux send-keys -t "$session" "cd ${WORK_DIR} && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t "$session" "请阅读 ${AGENT_DIR}/agents/claude_${agent_name}/CLAUDE.md，然后读取 shared/logs/hibernate_${agent_name}.md 恢复工作" Enter
            log "→ ${session}: 已重启并发送恢复指令"
        else
            agent_name=$(echo "$session" | sed 's/agent-//')
            tmux send-keys -t "$session" \
                "用量已刷新，请读取 shared/logs/hibernate_${agent_name}.md 恢复工作" Enter
            log "→ ${session}: 恢复指令已发送"
        fi
    else
        log "⚠️ ${session}: 会话不存在，无法恢复"
    fi
done

# ─── ops 自行读取休眠快照 ────────────────────────────────
if [ -f "${AGENT_DIR}/shared/logs/hibernate_ops.md" ]; then
    log "ops 休眠快照内容:"
    cat "${AGENT_DIR}/shared/logs/hibernate_ops.md" >> "$LOG"
fi

# ─── 恢复后 git push ────────────────────────────────────
cd "$AGENT_DIR"
git add shared/logs/watchdog.log 2>/dev/null
git diff --cached --quiet || {
    git commit -m "ops: resume from hibernate"
    git push
}

log "✅ 恢复完成，系统恢复运行"
rm -f /tmp/usage_watchdog.lock
