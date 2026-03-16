#!/bin/bash
# =============================================================
# all_loops.sh — 所有 Agent 的 10 分钟闹钟
# 用法: 由 scripts/all_loops_tmux.sh 托管启动
#
# 执行顺序:
# 1. rate limit 弹窗检查
# 2. sync_loop 存活检查
# 3. Supervisor → 等待完成
# 4. 训练质量健康检查
# 5. Conductor Phase 1（信息收集 + 审计决策）→ 等待完成
# 6. 检查是否有 pending audit → 启动 Critic → 等待 VERDICT
# 7. Conductor Phase 2（读 VERDICT + 决策 + 行动）→ 等待完成
# 8. Admin
# 9. Ops (save_tmux) — 循环最后执行
# 10. 动态等待补够 10 分钟
# =============================================================

AGENT_DIR="/home/UNT/yz0370/projects/GiT_agent"
LOG="${AGENT_DIR}/shared/logs/all_loops.log"
HEARTBEAT="${AGENT_DIR}/shared/logs/all_loops.heartbeat"
LOCKFILE="/tmp/all_loops.lock"
LOOP_INTERVAL=600
SUPERVISOR_WAIT_MIN=3
CONDUCTOR_P1_WAIT_MIN=3
CONDUCTOR_IDLE_WAIT_MIN=2
CONDUCTOR_P2_WAIT_MIN=3
CRITIC_WAIT_MIN=5

# ─── flock 防多实例 ──────────────────────────────────────
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] all_loops: 另一个实例已在运行，退出" >> "$LOG"
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] all_loops: $1" >> "$LOG"
}

heartbeat() {
    local phase="$1"
    local state="$2"
    cat > "$HEARTBEAT" << EOF
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
pid=$$
phase=${phase}
state=${state}
EOF
}

send_agent_message() {
    local session="$1"
    local message="$2"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi
    # 先尝试退出弹窗/多行草稿态，再清空当前输入框。
    tmux send-keys -t "$session" Escape
    sleep 1
    tmux send-keys -t "$session" C-u
    sleep 1
    tmux send-keys -l -t "$session" "$message"
    tmux send-keys -t "$session" C-m
    return 0
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
    heartbeat "$label" "waiting"
    for wait in $(seq 1 "$max_minutes"); do
        sleep 60
        if is_idle "$session"; then
            heartbeat "$label" "completed"
            log "→ ${label}: 已完成（等待 ${wait} 分钟）"
            return 0
        fi
        if [ "$wait" = "$max_minutes" ]; then
            heartbeat "$label" "timeout"
            log "⚠️ ${label}: 等待超时（${max_minutes} 分钟），继续执行"
            return 1
        else
            heartbeat "$label" "waiting ${wait}/${max_minutes}"
            log "→ ${label}: 仍在工作... ${wait}/${max_minutes} 分钟"
        fi
    done
}

log "all_loops.sh 启动 (PID $$)"
heartbeat "startup" "alive"

while true; do
    LOOP_START=$(date +%s)
    log "=== 新一轮循环开始 ==="
    heartbeat "loop" "started"

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
            send_agent_message agent-supervisor "cd ${AGENT_DIR} && claude --dangerously-skip-permissions"
            sleep 15
            send_agent_message agent-supervisor "请阅读 agents/claude_supervisor/CLAUDE.md 并开始自主循环"
            log "→ supervisor: 已重启"
            SUPERVISOR_SENT=1
        elif is_idle agent-supervisor; then
            send_agent_message agent-supervisor "cat shared/commands/supervisor_cmd.md"
            log "→ supervisor: 指令已发送"
            SUPERVISOR_SENT=1
        else
            log "→ supervisor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ supervisor: 会话不存在"
    fi

    # 等待 Supervisor 完成（最多 3 分钟）
    if [ "$SUPERVISOR_SENT" = "1" ]; then
        wait_for_idle agent-supervisor "$SUPERVISOR_WAIT_MIN" "supervisor"
    fi

    # ─── 4. 训练质量健康检查（自动审计触发）─────
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
            send_agent_message agent-conductor "cd ${AGENT_DIR} && claude --dangerously-skip-permissions"
            sleep 15
            send_agent_message agent-conductor "请阅读 agents/claude_conductor/CLAUDE.md 并等待指令"
            log "→ conductor: 已重启"
            sleep 10
        fi
        if is_idle agent-conductor; then
            send_agent_message agent-conductor "cat shared/commands/phase1_cmd.md"
            log "→ conductor Phase 1: 指令已发送"
            CONDUCTOR_P1_SENT=1
        else
            log "→ conductor: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ conductor: 会话不存在"
    fi

    # 等待 Conductor Phase 1 完成（最多 3 分钟）
    if [ "$CONDUCTOR_P1_SENT" = "1" ]; then
        wait_for_idle agent-conductor "$CONDUCTOR_P1_WAIT_MIN" "conductor Phase 1"
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
            cat > "${AGENT_DIR}/shared/commands/critic_cmd.md" << 'CRITICEOF'
# Critic 审计指令 — AUDIT_ID_PLACEHOLDER

严格按以下步骤执行，不可跳过任何步骤：

## 1. PULL
cd /home/UNT/yz0370/projects/GiT_agent && git pull
cd /home/UNT/yz0370/projects/GiT && git pull

## 2. 阅读角色定义
读取 agents/claude_critic/CLAUDE.md，理解你的职责、性格规则和写入边界

## 3. 读取审计请求
读取 shared/audit/requests/AUDIT_REQUEST_AUDIT_ID_PLACEHOLDER.md

## 4. 读取 MASTER_PLAN
读取 MASTER_PLAN.md，审视 Conductor 的计划和决策是否合理

## 5. 全链路特征流诊断（CRITICAL — 必须执行）

这是训练质量的核心检查。每次审计必须运行此诊断，产出下面这张表：

### 5.1 找到最新的训练 checkpoint 和 config
```bash
# 找到最新训练目录
ls -t /mnt/SSD/GiT_Yihao/Train/ | head -3
# 找到最新 checkpoint
ls -t /mnt/SSD/GiT_Yihao/Train/<最新目录>/*.pth | head -3
# 找到对应 config
ls /home/UNT/yz0370/projects/GiT/configs/GiT/plan_*.py
```

### 5.2 运行特征流诊断脚本
```bash
cd /home/UNT/yz0370/projects/GiT
conda activate GiT  # 确认环境
python scripts/diagnose_v3_precise.py  # 修改脚本中的 checkpoint 路径和 config 路径
```
如果脚本路径有变化或不存在，按照以下原理自己写诊断脚本（写入 ssd_workspace/Debug/ 目录）：
- monkey-patch `decoder_inference`，在推理过程中捕获每一层的中间特征
- 用 2-3 个不同的 val 样本分别推理
- 计算每个检查点的 cross-sample 相对差异

### 5.3 产出特征流诊断表（VERDICT 中必须包含）

在 VERDICT 中必须包含以下格式的表格：

```
| 检查点                          | cross-sample 相对差异 | 判定                       |
|--------------------------------|----------------------|---------------------------|
| patch_embed_input (特征提取器)  | X.XX%                | ✅/⚠️/🔴                  |
| grid_interp_feat_layer0        | X.XX%                | ✅/⚠️/🔴                  |
| image_patch_encoded (backbone) | X.XX%                | ✅/⚠️/🔴                  |
| pre_kv_layer0_k                | X.XX%                | ✅/⚠️/🔴                  |
| pre_kv_last_k                  | X.XX%                | ✅/⚠️/🔴                  |
| decoder_out_pos0               | X.XX%                | ✅/⚠️/🔴                  |
| logits_pos0                    | X.XX%                | ✅/⚠️/🔴                  |
| pred_token_pos0 (argmax)       | XX% 相同             | ✅/⚠️/🔴                  |
```

### 5.4 判定标准

**阈值定义**：
- ✅ 正常: cross-sample 相对差异 > 1%
- ⚠️ 偏弱: 0.1% < 差异 ≤ 1%（信号在衰减）
- 🔴 危险: 差异 ≤ 0.1% 或 argmax >80% 相同（模型忽略图像）

**关键比率 — diff/Margin**：
```bash
python scripts/diagnose_v3c_single_ckpt.py <ckpt_name> <ckpt_dir> <config_path>
```
- diff/Margin > 50%: ✅ 模型在利用图像特征
- 10% < diff/Margin ≤ 50%: ⚠️ 图像信号偏弱
- diff/Margin ≤ 10%: 🔴 CRITICAL — 图像信号无法改变决策，确认 mode collapse

**趋势分析（如果有多个 checkpoint）**：
```bash
# 对多个 checkpoint 分别运行
python scripts/diagnose_v3c_single_ckpt.py iter_4000 <dir> <config>
python scripts/diagnose_v3c_single_ckpt.py iter_8000 <dir> <config>
```
- diff/Margin 随训练增大 → ✅ 模型在学习使用图像
- diff/Margin 随训练减小 → 🔴 CRITICAL — mode collapse 正在加剧，立即停止训练
- prediction identical 随训练增大 → 🔴 CRITICAL — 同上

### 5.5 配置审查（不需要 GPU）
直接读取当前训练 config 文件，检查：
- [ ] `train_pipeline` 是否包含数据增强（RandomFlip / PhotoMetricDistortion / RandomResize）→ 没有则 🔴 CRITICAL
- [ ] `train_pipeline` 是否等于 `test_pipeline` → 相同则 🔴 HIGH RISK
- [ ] occ 任务的 `grid_start_embed` 是否注入了 position embedding（检查 git.py 中 `if self.mode != 'occupancy_prediction'`）
- [ ] `grid_interpolate_feats` 是否只在 pos_id==0 注入（检查 occ_head 的 decoder_inference）
- [ ] 是否使用 scheduled sampling → 没有则 ⚠️ MEDIUM

## 6. 审计请求专项审查
按 AUDIT_REQUEST 中的具体要求，深度审查 GiT/ 代码，追踪完整调用链

## 7. 调试验证（如需）
调试脚本写入：/home/UNT/yz0370/projects/GiT/ssd_workspace/Debug/Debug_YYYYMMDD/
文件名必须以 debug_ 前缀

## 8. 写入判决
写入 shared/audit/pending/VERDICT_AUDIT_ID_PLACEHOLDER.md
判决必须包含以下所有部分：

```markdown
# 审计判决 — AUDIT_ID_PLACEHOLDER

## 结论: PROCEED / STOP / CONDITIONAL

## 特征流诊断结果
<步骤 5.3 的表格>
- diff/Margin 比率: X.X%
- 趋势: 增大/减小/持平
- 诊断结论: <模型是否在利用图像特征>

## 配置审查结果
- [ ] 数据增强: 有/无 → <判定>
- [ ] Pipeline 分离: 是/否 → <判定>
- [ ] Position embedding: 有/无 → <判定>
- [ ] 特征注入频率: 每步/仅首步 → <判定>
- [ ] Scheduled sampling: 有/无 → <判定>

## 发现的问题
1. **BUG-XX**: <描述>
   - 严重性: CRITICAL / HIGH / MEDIUM / LOW
   - 位置: `GiT/<path/to/file.py>:L<行号>`
   - 修复建议: <具体方案>

## 对 Conductor 计划的评价
- MASTER_PLAN.md 中的决策是否合理
- 优先级排序是否正确
- 有无遗漏的风险
```

## 9. 提交
cd /home/UNT/yz0370/projects/GiT_agent
git add shared/audit/pending/ && git commit -m "critic: verdict AUDIT_ID_PLACEHOLDER" && git push
CRITICEOF
            # 替换占位符为实际 audit ID
            sed -i "s/AUDIT_ID_PLACEHOLDER/${id}/g" "${AGENT_DIR}/shared/commands/critic_cmd.md"
            sed -i "s/YYYYMMDD/$(date +%Y%m%d)/g" "${AGENT_DIR}/shared/commands/critic_cmd.md"

            if tmux has-session -t agent-critic 2>/dev/null; then
                if ! is_claude_alive agent-critic; then
                    log "⚠️ critic: Claude Code 已退出，正在重启..."
                    send_agent_message agent-critic "cd ${AGENT_DIR} && claude --dangerously-skip-permissions"
                    sleep 15
                fi
                send_agent_message agent-critic "cat shared/commands/critic_cmd.md"
                log "→ critic: 审计指令已发送 (${id})"
            else
                log "⚠️ critic: 会话不存在，无法执行审计"
            fi
            break
        fi
    done

    # 等待 Critic 完成审计（最多 5 分钟）
    if [ "$AUDIT_NEEDED" = "1" ]; then
        log "→ critic: 等待审计完成..."
        VERDICT_FOUND=0
        for wait in $(seq 1 "$CRITIC_WAIT_MIN"); do
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
            if [ "$wait" = "$CRITIC_WAIT_MIN" ]; then
                log "⚠️ critic: 审计超时（${CRITIC_WAIT_MIN} 分钟），继续执行"
            else
                log "→ critic: 仍在审计... ${wait}/${CRITIC_WAIT_MIN} 分钟"
            fi
        done
    fi

    # ─── 7. Conductor Phase 2 ────────────────────
    if [ "$CONDUCTOR_P1_SENT" = "1" ]; then
        if tmux has-session -t agent-conductor 2>/dev/null; then
            if ! is_idle agent-conductor; then
                wait_for_idle agent-conductor "$CONDUCTOR_IDLE_WAIT_MIN" "conductor 等待空闲"
            fi
            send_agent_message agent-conductor "cat shared/commands/phase2_cmd.md"
            log "→ conductor Phase 2: 指令已发送"
            wait_for_idle agent-conductor "$CONDUCTOR_P2_WAIT_MIN" "conductor Phase 2"
        fi
    fi

    # ─── 8. Admin ────────────────────────────────
    if tmux has-session -t agent-admin 2>/dev/null; then
        if ! is_claude_alive agent-admin; then
            log "⚠️ admin: Claude Code 已退出，正在重启..."
            send_agent_message agent-admin "cd /home/UNT/yz0370/projects/GiT && claude --dangerously-skip-permissions"
            sleep 15
            send_agent_message agent-admin "请阅读 /home/UNT/yz0370/projects/GiT_agent/agents/claude_admin/CLAUDE.md 并开始自主循环"
            log "→ admin: 已重启"
        elif is_idle agent-admin; then
            send_agent_message agent-admin "cat /home/UNT/yz0370/projects/GiT_agent/shared/commands/admin_cmd.md"
            log "→ admin: 指令已发送"
        else
            log "→ admin: 正在忙碌，跳过本轮"
        fi
    else
        log "⚠️ admin: 会话不存在"
    fi

    # ─── 9. Ops: 执行快照（循环最后）────────────
    log "→ ops: 执行 save_tmux.sh"
    heartbeat "ops" "save_tmux"
    if timeout 180 bash "${AGENT_DIR}/scripts/save_tmux.sh"; then
        heartbeat "ops" "save_tmux_done"
    else
        heartbeat "ops" "save_tmux_timeout"
        log "⚠️ ops: save_tmux.sh 超时或失败，继续下一轮"
    fi

    # ─── 10. 动态等待补够 10 分钟 ─────────────────
    LOOP_END=$(date +%s)
    ELAPSED=$(( LOOP_END - LOOP_START ))
    REMAINING=$(( LOOP_INTERVAL - ELAPSED ))
    if [ "$REMAINING" -gt 60 ]; then
        REMAINING_MIN=$(( REMAINING / 60 ))
        log "=== 循环耗时 $((ELAPSED/60)) 分钟，等待 ${REMAINING_MIN} 分钟补够 10 分钟 ==="
        heartbeat "sleep" "waiting ${REMAINING_MIN} min"
        for i in $(seq 1 "$REMAINING_MIN"); do
            sleep 60
            heartbeat "sleep" "waiting ${i}/${REMAINING_MIN}"
            log "⏳ 等待中... ${i}/${REMAINING_MIN} 分钟"
        done
    else
        heartbeat "loop" "overrun"
        log "=== 循环耗时 $((ELAPSED/60)) 分钟，已超过 10 分钟，立即开始下一轮 ==="
    fi
done
