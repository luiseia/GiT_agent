#!/bin/bash
# =============================================================
# log_cleaner.sh — 日志清理，超过 1 万行时删除前 5000 行
# crontab: 0 * * * * bash /home/UNT/yz0370/projects/GiT_agent/scripts/log_cleaner.sh
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"

LOGS=(
    "${AGENT_DIR}/shared/logs/all_loops.log"
    "${AGENT_DIR}/shared/logs/watchdog.log"
    "${AGENT_DIR}/shared/logs/watchdog_cron.log"
    "${AGENT_DIR}/shared/logs/ops.log"
    "${AGENT_DIR}/shared/logs/sync_cron.log"
    "${AGENT_DIR}/shared/logs/supervisor.log"
    "${AGENT_DIR}/shared/logs/save_cron.log"
)

for logfile in "${LOGS[@]}"; do
    if [ -f "$logfile" ]; then
        lines=$(wc -l < "$logfile")
        if [ "$lines" -gt 10000 ]; then
            tail -n 5000 "$logfile" > "${logfile}.tmp"
            mv "${logfile}.tmp" "$logfile"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] log_cleaner: ${logfile} 清理完成 (${lines} → 5000 行)"
        fi
    fi
done