#!/bin/bash
# 指令中继 - 每60秒检查 user_cmd.md 和 orchestrator_cmd.md
REPO_DIR="$HOME/projects/claude_supervisor"
CMD_DIR="$REPO_DIR/commands"
LOG="$CMD_DIR/relay.log"

cd "$REPO_DIR" || exit 1

relay_cmd() {
    local FILE="$1"
    local LABEL="$2"
    local CONTENT
    CONTENT=$(cat "$FILE" 2>/dev/null | sed '/^[[:space:]]*$/d')
    if [ -n "$CONTENT" ]; then
        local TS=$(date '+%Y%m%d_%H%M%S')
        local HHMM=$(date '+%H%M')
        echo "[$TS] [$LABEL] 转发: $CONTENT" >> "$LOG"
        tmux send-keys -t claude_admin "$CONTENT" Enter 2>>"$LOG"
        echo "# [$LABEL] 已执行 — $TS" > "$CMD_DIR/archive_${LABEL}_${TS}.md"
        echo "$CONTENT" >> "$CMD_DIR/archive_${LABEL}_${TS}.md"
        echo "" > "$FILE"
        echo "[$TS] [$LABEL] 已转发并存档" >> "$LOG"
        return 0
    fi
    return 1
}

while true; do
    git pull --quiet origin master 2>/dev/null
    CHANGED=0
    relay_cmd "$CMD_DIR/user_cmd.md" "USER" && CHANGED=1
    relay_cmd "$CMD_DIR/orchestrator_cmd.md" "ORCH" && CHANGED=1
    if [ "$CHANGED" -eq 1 ]; then
        git add commands/
        git commit -m "relay update

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>" 2>/dev/null
        git push origin master 2>/dev/null
    fi
    sleep 60
done
