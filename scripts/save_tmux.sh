#!/bin/bash
# =============================================================
# save_tmux.sh — Ops Agent 的核心脚本：保存 tmux 快照 + 健康检查
# 每 5 分钟由 claude_ops 调用（或 crontab）
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
SNAPSHOT_DIR="${AGENT_DIR}/shared/snapshots"
STATUS_FILE="${AGENT_DIR}/STATUS.md"
OPS_LOG="${AGENT_DIR}/shared/logs/ops.log"
RETENTION_MIN=1440  # 24 小时

SESSIONS=("agent-conductor" "agent-critic" "agent-supervisor" "agent-admin")
TS=$(date +%Y%m%d_%H%M%S)
NOW=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$NOW] $1" | tee -a "$OPS_LOG"
}

# ─── 1. 捕获 tmux 快照 ───────────────────────────────────
log "=== 快照开始 ==="

for session in "${SESSIONS[@]}"; do
    outfile="${SNAPSHOT_DIR}/${session}_${TS}.log"
    if tmux has-session -t "$session" 2>/dev/null; then
        tmux capture-pane -t "$session" -p -S -3000 > "$outfile"
        lines=$(wc -l < "$outfile")
        log "✅ ${session}: ${lines} 行"
    else
        log "❌ ${session}: 会话不存在"
    fi
done

# ─── 2. 清理过期快照 ──────────────────────────────────────
cleaned=$(find "$SNAPSHOT_DIR" -name "agent-*.log" -mmin +${RETENTION_MIN} -delete -print | wc -l)
[ "$cleaned" -gt 0 ] && log "🧹 清理 ${cleaned} 个过期快照"

# ─── 3. 生成 STATUS.md ───────────────────────────────────
{
    echo "# 实验室状态面板"
    echo "> 最后更新: $NOW"
    echo "> 由 claude_ops 自动生成，请勿手动编辑"
    echo ""
    echo "| Agent | tmux | 最后快照 | 备注 |"
    echo "|-------|------|---------|------|"

    ALL=("agent-conductor" "agent-critic" "agent-supervisor" "agent-admin" "agent-ops")
    for session in "${ALL[@]}"; do
        name=$(echo "$session" | sed 's/agent-//')

        if tmux has-session -t "$session" 2>/dev/null; then
            status="✅ UP"
        else
            status="❌ DOWN"
        fi

        latest=$(ls -t "${SNAPSHOT_DIR}/${session}_"*.log 2>/dev/null | head -1)
        if [ -n "$latest" ]; then
            snap_time=$(basename "$latest" | grep -oP '\d{8}_\d{6}')
            snap_info="${snap_time}"
        else
            snap_info="-"
        fi

        echo "| ${name} | ${status} | ${snap_info} | - |"
    done

    echo ""
    echo "## 告警"
    ALERTS=0

    # 积压的 PENDING 指令
    for f in "${AGENT_DIR}"/shared/pending/ORCH_*.md; do
        [ -f "$f" ] || continue
        if grep -q "PENDING" "$f"; then
            # 检查文件修改时间
            if [ "$(uname)" = "Darwin" ]; then
                mtime=$(stat -f %m "$f")
            else
                mtime=$(stat -c %Y "$f")
            fi
            now_epoch=$(date +%s)
            age_min=$(( (now_epoch - mtime) / 60 ))
            if [ "$age_min" -gt 30 ]; then
                echo "- ⚠️ $(basename $f) 已 PENDING ${age_min} 分钟"
                ALERTS=$((ALERTS + 1))
            fi
        fi
    done

    # 宕机的 Agent
    for session in "${ALL[@]}"; do
        if ! tmux has-session -t "$session" 2>/dev/null; then
            echo "- 🚨 ${session} 已宕机！"
            ALERTS=$((ALERTS + 1))
        fi
    done

    [ "$ALERTS" -eq 0 ] && echo "- ✅ 无告警"

    # ─── 基础设施状态 ─────────────────────────────────
    echo ""
    echo "## 基础设施"
    echo "| 组件 | 状态 | 详情 |"
    echo "|------|------|------|"

    now_epoch=$(date +%s)

    # all_loops.sh 进程
    LOOPS_PID=$(pgrep -f "all_loops.sh" | head -1)
    if [ -n "$LOOPS_PID" ]; then
        start_epoch=$(stat -c %Y /proc/"$LOOPS_PID" 2>/dev/null || echo "$now_epoch")
        elapsed=$(( (now_epoch - start_epoch) / 60 ))
        if [ "$elapsed" -ge 60 ]; then
            elapsed_str="$((elapsed / 60))h$((elapsed % 60))m"
        else
            elapsed_str="${elapsed}m"
        fi
        echo "| all_loops.sh | ✅ PID ${LOOPS_PID} | 运行 ${elapsed_str} |"
    else
        echo "| all_loops.sh | ❌ 未运行 | - |"
    fi

    # sync_loop 进程
    SYNC_PID=$(pgrep -f "sync_loop.sh" | head -1)
    if [ -n "$SYNC_PID" ]; then
        sync_start=$(stat -c %Y /proc/"$SYNC_PID" 2>/dev/null || echo "$now_epoch")
        sync_elapsed=$(( (now_epoch - sync_start) / 60 ))
        if [ "$sync_elapsed" -ge 60 ]; then
            sync_str="$((sync_elapsed / 60))h$((sync_elapsed % 60))m"
        else
            sync_str="${sync_elapsed}m"
        fi
        echo "| sync_loop | ✅ PID ${SYNC_PID} | 运行 ${sync_str} |"
    else
        echo "| sync_loop | ❌ 未运行 | - |"
    fi

    # usage_watchdog crontab
    if crontab -l 2>/dev/null | grep -q "watchdog"; then
        wd_log="${AGENT_DIR}/shared/logs/watchdog_cron.log"
        if [ -f "$wd_log" ]; then
            wd_mtime=$(stat -c %Y "$wd_log")
            wd_ago=$(( (now_epoch - wd_mtime) / 60 ))
            echo "| watchdog | ✅ crontab | 最后活跃 ${wd_ago}min ago |"
        else
            echo "| watchdog | ✅ crontab | 无日志记录 |"
        fi
    else
        echo "| watchdog | ❌ 未在 crontab | - |"
    fi

} > "$STATUS_FILE"

log "📊 STATUS.md 已更新 (告警: ${ALERTS:-0})"

# ─── 4. Git 同步 ──────────────────────────────────────────
cd "$AGENT_DIR"
git add shared/snapshots/ STATUS.md shared/logs/ops.log 2>/dev/null
if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "ops: snapshot ${TS}" --quiet
    git push --quiet 2>/dev/null && log "📤 已推送" || log "⚠️ push 失败"
fi

log "=== 快照完成 ==="
