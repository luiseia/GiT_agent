#!/bin/bash
# =============================================================
# all_loops.sh — 所有 Agent 的 30 分钟闹钟
# 用法: nohup bash scripts/all_loops.sh &
#
# 执行顺序:
# 1. rate limit 弹窗检查
# 2. sync_loop 存活检查
# 3. Supervisor → 等待完成
# 4. Ops (save_tmux)
# 5. Conductor Phase 1（信息收集 + 审计决策）→ 等待完成
# 6. 检查是否有 pending audit → 启动 Critic → 等待 VERDICT
# 7. Conductor Phase 2（读 VERDICT + 决策 + 行动）→ 等待完成
# 8. Admin
# 9. 动态等待补够 30 分钟
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
    if echo "$last_lines" | grep -q 'esc to interrupt'; then
        return 1
    fi
    if echo "$last_lines" | grep -q 'bypass permissions'; then
        return 0
    fi
    return 1
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

# ─── 等待 Agent 完成（通用函数）─────────────────────────
wait_for_idle() {
    local session="$1"
    local max_minutes="$2"
    local label="$3"
    for wait in $(seq 1 "$max_minutes"); do
        sleep 60
        if is_idle "$session"; then
            log "→ ${label}: 已完成（等待 ${wait} 分钟）"
            return 0
        fi
        if [ "$wait" = "$max_minutes" ]; then
            log "⚠️ ${label}: 等待超时（${max_minutes} 分钟），继续执行"
            return 1
        else
            log "→ ${label}: 仍在工作... ${wait}/${max_minutes} 分钟"
        fi
    done
}

log "all_loops.sh 启动 (PID $$)"

while true; do
    LOOP_START=$(date +%s)
    log "=== 新一轮循环开始 ==="

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

    # ─── 3. Supervisor（最先启动，产出摘要）───────
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
            tmux send-keys -t agent-supervisor "cat shared/commands/supervisor_cmd.md" Enter
            log "→ supervisor: 指令已发送"
            SUPERVISOR_SENT=1
        else
            log "→ supervisor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ supervisor: 会话不存在"
    fi

    # 等待 Supervisor 完成（最多 10 分钟）
    if [ "$SUPERVISOR_SENT" = "1" ]; then
        wait_for_idle agent-supervisor 10 "supervisor"
    fi

    # ─── 4. Ops: 执行快照 ────────────────────────
    log "→ ops: 执行 save_tmux.sh"
    bash "${AGENT_DIR}/scripts/save_tmux.sh"

    # ─── 4.5 训练质量健康检查（自动审计触发）─────
    HEALTH_ALERT=0
    HEALTH_REPORT="${AGENT_DIR}/shared/logs/supervisor_report_latest.md"
    if [ -f "$HEALTH_REPORT" ]; then
        # 检查 supervisor 报告中是否有 🚨 训练质量告警
        if grep -q "训练质量告警" "$HEALTH_REPORT" 2>/dev/null; then
            if grep -q "\[RED\]" "$HEALTH_REPORT" 2>/dev/null; then
                HEALTH_ALERT=2
                log "🚨🚨 训练质量 RED 告警！自动触发紧急审计"
            elif grep -q "\[YELLOW\]" "$HEALTH_REPORT" 2>/dev/null; then
                HEALTH_ALERT=1
                log "⚠️ 训练质量 YELLOW 告警"
            fi
        fi
    fi

    # 如果发现 RED 告警，自动签发紧急审计请求（无需等 Conductor 决策）
    if [ "$HEALTH_ALERT" -ge 2 ]; then
        HEALTH_AUDIT_ID="HEALTH_$(date +%Y%m%d_%H%M)"
        HEALTH_AUDIT_FILE="${AGENT_DIR}/shared/audit/requests/AUDIT_REQUEST_${HEALTH_AUDIT_ID}.md"
        if [ ! -f "$HEALTH_AUDIT_FILE" ]; then
            mkdir -p "${AGENT_DIR}/shared/audit/requests"
            cat > "$HEALTH_AUDIT_FILE" << HEALTHEOF
# 紧急审计请求 — ${HEALTH_AUDIT_ID}

## 触发方式: 自动健康检查（all_loops.sh）

## 审计类型: TRAINING_HEALTH

## 背景
Supervisor 报告中检测到 RED 级训练质量告警。
请执行以下紧急审计：

## 审计要点

### 1. 预测多样性验证
- 运行 \`scripts/diagnose_v3c_single_ckpt.py\` 检查最新 checkpoint 的跨样本预测差异
- 如果 >90% 预测相同 → 确认 mode collapse
- 如果 diff/Margin < 10% → 确认模型在忽略图像输入

### 2. 训练配置审查
- 检查当前 config 的 train_pipeline 是否有数据增强
- 检查 train_pipeline 和 test_pipeline 是否分离
- 检查是否有已知的 mode collapse 风险因素

### 3. Loss-指标背离分析
- 对比最近 checkpoints 的 loss 趋势和实际预测质量
- 确认是否存在 shortcut learning

## 紧急程度: P0 — 训练可能在浪费 GPU 时间
HEALTHEOF
            cd "$AGENT_DIR" && git add shared/audit/requests/ && \
                git commit -m "auto: emergency health audit ${HEALTH_AUDIT_ID}" && \
                git push 2>/dev/null
            log "→ 已自动签发紧急审计: ${HEALTH_AUDIT_ID}"
        fi
    fi

    # ─── 5. Conductor Phase 1 ────────────────────
    CONDUCTOR_P1_SENT=0
    if tmux has-session -t agent-conductor 2>/dev/null; then
        if ! is_claude_alive agent-conductor; then
            log "⚠️ conductor: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-conductor "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-conductor "请阅读 agents/claude_conductor/CLAUDE.md 并等待指令" Enter
            log "→ conductor: 已重启"
            sleep 10
        fi
        if is_idle agent-conductor || is_claude_alive agent-conductor; then
            tmux send-keys -t agent-conductor "cat shared/commands/phase1_cmd.md" Enter
            log "→ conductor Phase 1: 指令已发送"
            CONDUCTOR_P1_SENT=1
        else
            log "→ conductor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ conductor: 会话不存在"
    fi

    # 等待 Conductor Phase 1 完成（最多 10 分钟）
    if [ "$CONDUCTOR_P1_SENT" = "1" ]; then
        wait_for_idle agent-conductor 10 "conductor Phase 1"
    fi

    # ─── 6. 检查是否有 pending audit → 启动 Critic ─
    AUDIT_NEEDED=0
    for f in "${AGENT_DIR}"/shared/audit/requests/AUDIT_REQUEST_*.md; do
        [ -f "$f" ] || continue
        id=$(basename "$f" | sed 's/AUDIT_REQUEST_//' | sed 's/\.md//')
        if [ ! -f "${AGENT_DIR}/shared/audit/pending/VERDICT_${id}.md" ]; then
            AUDIT_NEEDED=1
            log "🔔 发现待审计: ${id}"

            # 生成动态审计命令文件
            cat > "${AGENT_DIR}/shared/commands/critic_cmd.md" << CRITICEOF
# Critic 审计指令 — ${id}

严格按以下步骤执行：

## 1. PULL
cd /home/UNT/yz0370/projects/GiT_agent && git pull
cd /home/UNT/yz0370/projects/GiT && git pull

## 2. 阅读角色定义
读取 agents/claude_critic/CLAUDE.md，理解你的职责和规则（特别注意"训练质量健康检查清单"）

## 3. 读取审计请求
读取 shared/audit/requests/AUDIT_REQUEST_${id}.md

## 4. 读取 MASTER_PLAN
读取 MASTER_PLAN.md，审视 Conductor 的计划和决策是否合理

## 5. 训练质量健康检查（必须执行）
按照 CLAUDE.md 中的"训练质量健康检查清单"，逐项检查：
- A. Mode Collapse 检测（数据增强、预测多样性、marker 分布、训练趋势）
- B. Shortcut Learning 检测（loss-指标背离、teacher forcing 风险）
- C. 架构风险检测（位置编码、特征注入、维度匹配）
- D. 资源浪费检测（无效训练、checkpoint 价值）
如果发现任何 CRITICAL 问题，优先于审计请求本身的内容报告。

## 6. 深度审查代码
按审计请求要求，深度审查 GiT/ 中相关代码，追踪完整调用链

## 7. 调试验证（如需）
调试脚本写入：/home/UNT/yz0370/projects/GiT/ssd_workspace/Debug/Debug_\$(date +%Y%m%d)/
文件名必须以 debug_ 前缀

## 8. 写入判决
写入 shared/audit/pending/VERDICT_${id}.md
判决必须包含：
- 结论(PROCEED/STOP/CONDITIONAL)
- 健康检查结果（逐项列出 A/B/C/D 的检查结论）
- 发现的问题(附文件路径+行号)
- 对 Conductor 计划的评价

## 9. 提交
cd /home/UNT/yz0370/projects/GiT_agent
git add shared/audit/pending/ && git commit -m "critic: verdict ${id}" && git push
CRITICEOF

            if tmux has-session -t agent-critic 2>/dev/null; then
                if ! is_claude_alive agent-critic; then
                    log "⚠️ critic: Claude Code 已退出，正在重启..."
                    tmux send-keys -t agent-critic "cd ${AGENT_DIR} && claude --dangerously-skip-permissions" Enter
                    sleep 15
                fi
                tmux send-keys -t agent-critic "cat shared/commands/critic_cmd.md" Enter
                log "→ critic: 审计指令已发送 (${id})"
            else
                log "⚠️ critic: 会话不存在，无法执行审计"
            fi
            break
        fi
    done

    # 等待 Critic 完成审计（最多 15 分钟）
    if [ "$AUDIT_NEEDED" = "1" ]; then
        log "→ critic: 等待审计完成..."
        VERDICT_FOUND=0
        for wait in $(seq 1 15); do
            sleep 60
            # 检查 pending/ 里是否出现了 VERDICT
            cd "$AGENT_DIR" && git pull --quiet 2>/dev/null
            for f in "${AGENT_DIR}"/shared/audit/requests/AUDIT_REQUEST_*.md; do
                [ -f "$f" ] || continue
                id=$(basename "$f" | sed 's/AUDIT_REQUEST_//' | sed 's/\.md//')
                if [ -f "${AGENT_DIR}/shared/audit/pending/VERDICT_${id}.md" ]; then
                    VERDICT_FOUND=1
                    log "→ critic: VERDICT_${id} 已产出（等待 ${wait} 分钟）"
                    break 2
                fi
            done
            if [ "$wait" = "15" ]; then
                log "⚠️ critic: 审计超时（15 分钟），继续执行"
            else
                log "→ critic: 仍在审计... ${wait}/15 分钟"
            fi
        done
    fi

    # ─── 7. Conductor Phase 2 ────────────────────
    if [ "$CONDUCTOR_P1_SENT" = "1" ]; then
        if tmux has-session -t agent-conductor 2>/dev/null; then
            if ! is_idle agent-conductor; then
                wait_for_idle agent-conductor 5 "conductor 等待空闲"
            fi
            tmux send-keys -t agent-conductor "cat shared/commands/phase2_cmd.md" Enter
            log "→ conductor Phase 2: 指令已发送"
            wait_for_idle agent-conductor 10 "conductor Phase 2"
        fi
    fi

    # ─── 8. Admin ────────────────────────────────
    if tmux has-session -t agent-admin 2>/dev/null; then
        if ! is_claude_alive agent-admin; then
            log "⚠️ admin: Claude Code 已退出，正在重启..."
            tmux send-keys -t agent-admin "cd /home/UNT/yz0370/projects/GiT && claude --dangerously-skip-permissions" Enter
            sleep 15
            tmux send-keys -t agent-admin "请阅读 /home/UNT/yz0370/projects/GiT_agent/agents/claude_admin/CLAUDE.md 并开始自主循环" Enter
            log "→ admin: 已重启"
        elif is_idle agent-admin; then
            tmux send-keys -t agent-admin "cat /home/UNT/yz0370/projects/GiT_agent/shared/commands/admin_cmd.md" Enter
            log "→ admin: 指令已发送"
        else
            log "→ admin: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ admin: 会话不存在"
    fi

    # ─── 9. 动态等待补够 30 分钟 ─────────────────
    LOOP_END=$(date +%s)
    ELAPSED=$(( LOOP_END - LOOP_START ))
    REMAINING=$(( 1800 - ELAPSED ))
    if [ "$REMAINING" -gt 60 ]; then
        REMAINING_MIN=$(( REMAINING / 60 ))
        log "=== 循环耗时 $((ELAPSED/60)) 分钟，等待 ${REMAINING_MIN} 分钟补够 30 分钟 ==="
        for i in $(seq 1 "$REMAINING_MIN"); do
            sleep 60
            log "⏳ 等待中... ${i}/${REMAINING_MIN} 分钟"
        done
    else
        log "=== 循环耗时 $((ELAPSED/60)) 分钟，已超过 30 分钟，立即开始下一轮 ==="
    fi
done