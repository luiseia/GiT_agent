#!/bin/bash
# =============================================================
# usage_watchdog.sh — 用量监控 + 自动休眠/恢复
# 每 10 分钟由 crontab 运行（flock 防重入）
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
LOG="${AGENT_DIR}/shared/logs/watchdog.log"
LOCKFILE="/tmp/usage_watchdog.lock"
HIBERNATE_FLAG="/tmp/usage_watchdog_hibernating"
SESSIONS=("agent-conductor" "agent-critic" "agent-supervisor" "agent-admin")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] watchdog: $1" | tee -a "$LOG"
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

# ─── 检测方式 1: /usage 命令 ──────────────────────────────
if tmux has-session -t agent-conductor 2>/dev/null; then
    tmux send-keys -t agent-conductor "/usage" Enter
    sleep 5
    USAGE_OUTPUT=$(tmux capture-pane -t agent-conductor -p -S -20)

    # 解析用量百分比: 匹配类似 "75%" 或 "75.3%" 的模式
    USAGE_PCT=$(echo "$USAGE_OUTPUT" | grep -oP '\d+\.?\d*%' | head -1 | tr -d '%')
    # 解析刷新倒计时: "Resets in X hr Y min" 或类似格式
    RESET_INFO=$(echo "$USAGE_OUTPUT" | grep -oiP '[Rr]esets?\s+in\s+.*' | head -1)

    if [ -n "$USAGE_PCT" ]; then
        log "用量: ${USAGE_PCT}%  |  ${RESET_INFO:-无刷新信息}"
        # 比较是否超过 80%
        OVER=$(echo "$USAGE_PCT >= 80" | bc -l 2>/dev/null)
        if [ "$OVER" = "1" ]; then
            TRIGGER=1
            TRIGGER_REASON="用量超过 80% (${USAGE_PCT}%)"
        fi
    else
        log "⚠️ 无法解析 /usage 输出"
    fi
fi

# ─── 检测方式 2: 限流关键词扫描 ──────────────────────────
RATE_LIMIT_PATTERN="rate limit|usage limit|too many requests|429|try again"
for session in "${SESSIONS[@]}"; do
    if tmux has-session -t "$session" 2>/dev/null; then
        PANE_OUTPUT=$(tmux capture-pane -t "$session" -p -S -50)
        MATCH=$(echo "$PANE_OUTPUT" | grep -iE "$RATE_LIMIT_PATTERN" | head -3)
        if [ -n "$MATCH" ]; then
            log "🚨 ${session} 检测到限流: $(echo "$MATCH" | head -1)"
            TRIGGER=1
            TRIGGER_REASON="${TRIGGER_REASON:+${TRIGGER_REASON} | }${session} 触发限流关键词"
        fi
    fi
done

# ─── 未触发：正常退出 ────────────────────────────────────
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
    if [ "$CALC" -gt 0 ]; then
        SLEEP_SECONDS=$CALC
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

# ─── 杀掉 all_loops.sh ──────────────────────────────────
ALL_LOOPS_PID=$(pgrep -f "all_loops.sh" | head -1)
if [ -n "$ALL_LOOPS_PID" ]; then
    kill "$ALL_LOOPS_PID" 2>/dev/null
    log "已停止 all_loops.sh (PID ${ALL_LOOPS_PID})"
fi

# ─── 休眠等待 ────────────────────────────────────────────
log "💤 开始休眠 ${SLEEP_SECONDS} 秒，预计 ${RESUME_TIME} 恢复"
sleep "$SLEEP_SECONDS"

# =============================================================
# 恢复流程
# =============================================================
log "⏰ 休眠结束，开始恢复"
rm -f "$HIBERNATE_FLAG"

# ─── 重启 all_loops.sh ──────────────────────────────────
nohup bash "${AGENT_DIR}/scripts/all_loops.sh" >> "${AGENT_DIR}/shared/logs/all_loops.log" 2>&1 &
NEW_PID=$!
log "✅ all_loops.sh 已重启 (PID ${NEW_PID})"

# ─── 给每个 Agent 发送恢复指令 ────────────────────────────
if tmux has-session -t agent-conductor 2>/dev/null; then
    tmux send-keys -t agent-conductor \
        "用量已刷新，请读取 shared/logs/hibernate_conductor.md 恢复工作" Enter
    log "→ conductor: 恢复指令已发送"
fi

if tmux has-session -t agent-admin 2>/dev/null; then
    tmux send-keys -t agent-admin \
        "用量已刷新，请读取 shared/logs/hibernate_admin.md 恢复工作" Enter
    log "→ admin: 恢复指令已发送"
fi

if tmux has-session -t agent-critic 2>/dev/null; then
    tmux send-keys -t agent-critic \
        "用量已刷新，请读取 shared/logs/hibernate_critic.md 恢复工作" Enter
    log "→ critic: 恢复指令已发送"
fi

if tmux has-session -t agent-supervisor 2>/dev/null; then
    tmux send-keys -t agent-supervisor \
        "用量已刷新，请读取 shared/logs/hibernate_supervisor.md 恢复工作" Enter
    log "→ supervisor: 恢复指令已发送"
fi

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
