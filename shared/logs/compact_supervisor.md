# Supervisor Compact Context Snapshot
> Timestamp: 2026-03-06 23:25
> Supervisor cycles: #103 — #106 (this session)
> Role: 信息中枢 (CLAUDE.md unchanged)
> Reason: CEO requested /compact

## Current System State

### P3 Training — IN PROGRESS (50%)
- Config: `configs/GiT/plan_f_bug8_fix.py`
- Key fixes: BUG-8 (bg cls loss, bg_balance_weight=3.0) + BUG-10 (LinearLR warmup 500 iter)
- Load from: P2@6000 checkpoint
- GPU: 0 + 2 (~22.4GB + 23GB)
- Progress: iter 2000 / 4000 (50%)
- 4 checkpoints saved: iter_500, 1000, 1500, 2000
- Work dir: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/`
- Train log: `/mnt/SSD/GiT_Yihao/Train/Train_20260306/plan_f_bug8_fix/train.log`
- LR: base_lr=5e-05 (constant since warmup ended at iter 500)
- **Next critical event: iter 2500 — 1st LR decay (5e-05 → 5e-06)**
- LR milestones: [2500, 3500]
- Val interval: every 500 iter
- Next val: iter 2500 (~00:00)
- ETA completion: ~00:50

### P3 Val Trajectory (all 4 checkpoints)

| Metric | @500 | @1000 | @1500 | @2000 | P2@6000 | Red Line |
|--------|------|-------|-------|-------|---------|----------|
| car_R | 0.576 | 0.578 | 0.598 | **0.608** | 0.596 | — |
| car_P | 0.075 | 0.087 | 0.083 | 0.074 | 0.079 | — |
| truck_R | 0.374 | 0.390 | 0.382 | **0.152** | 0.290 | <0.08 |
| truck_P | 0.254 | 0.250 | 0.118 | 0.167 | 0.190 | — |
| bus_R | 0.697 | 0.576 | 0.680 | **0.737** | 0.623 | — |
| bus_P | 0.125 | 0.081 | 0.127 | 0.142 | 0.150 | — |
| trailer_R | 0.667 | 0.511 | 0.756 | 0.689 | 0.689 | — |
| trailer_P | 0.044 | 0.022 | 0.024 | 0.023 | 0.066 | — |
| bg_FA | 0.212 | 0.206 | 0.227 | 0.216 | 0.198 | >0.25 |
| offset_cx | 0.085 | 0.055 | 0.066 | 0.071 | 0.068 | ≤0.05 |
| offset_cy | 0.127 | 0.119 | 0.107 | 0.148 | 0.095 | ≤0.10 |
| offset_th | 0.253 | 0.232 | 0.234 | **0.191** | 0.217 | ≤0.20 |

### Key Observations from P3 So Far

1. **BUG-8 fix validated at @500**: truck_R jumped to 0.374 (+29% vs P2), truck_P=0.254 (+33%)
2. **Model entered over-prediction phase @1500**: bg_FA peaked 0.227, truck_P collapsed to 0.118
3. **truck_R crashed at @2000**: 0.382→0.152 (-60%), bus_R anti-correlated (→0.737), likely truck→bus confusion
4. **offset_th FIRST EVER below red line at @2000**: 0.191 (target ≤0.20), never achieved in P1 or P2
5. **High LR oscillations throughout**: grad_norm spikes up to 76.6 (@730), 52.3 (@1140), 48.7 (@1670)
6. **P2 had similar pattern**: over-prediction peak at @3000 (bg_FA=0.284), resolved by LR decay

### P2 Reference (completed earlier today)
- Config: `configs/GiT/plan_e_bug9_fix.py`, max_norm=10.0 (BUG-9 fix)
- Final: P2@6000, metrics in table above
- Key P2 lesson: LR decay at @3000 resolved over-prediction, model stabilized @4500+

### Completed ORCH Instructions
| ID | Subject | Result |
|----|---------|--------|
| ORCH_001 | BUG-12 eval slot fix | truck_R +72% |
| ORCH_002 | BUG-9 grad clip diagnosis | max_norm=10.0 |
| ORCH_003 | P1 eval + P2 launch | P2 completed |
| ORCH_004 | BUG-8 + BUG-10 fix, P3 launch | P3 running |

### BUG Status
| BUG | Status |
|-----|--------|
| BUG-8 | **FIXED & VALIDATED** (bg cls loss, truck_R +29% at @500) |
| BUG-9 | FIXED (max_norm=10.0, validated in P2) |
| BUG-10 | FIXED (LinearLR warmup 500 iter) |
| BUG-12 | FIXED (eval slot ordering) |

All known BUGs fixed.

### GPU Status (as of 23:25)
| GPU | Used | Util | Task |
|-----|------|------|------|
| 0 | 22.4 GB | 99% | **P3 training** |
| 1 | 3.3 GB | 56% | External: yz0364 |
| 2 | 23.0 GB | 45% | **P3 training** |
| 3 | 3.3 GB | 65% | External: yz0364 |

### Agent Status
All 5 agent tmux sessions UP. 8 total sessions (3 legacy: dinov3_integrated, plan_a, plan_b).

### Key Files
- Latest report: `shared/logs/supervisor_report_latest.md`
- Report history: `shared/logs/supervisor_report_history.md`
- ORCH reports: `shared/logs/report_ORCH_{001,002,003,004}.md`
- CLAUDE.md: `agents/claude_supervisor/CLAUDE.md`
- P3 config: `configs/GiT/plan_f_bug8_fix.py`

### Resume After Compact
1. Read `agents/claude_supervisor/CLAUDE.md` for role definition
2. `git pull` both repos
3. P3 training IN PROGRESS — check current iter (should be past 2000)
4. **CRITICAL**: iter 2500 LR decay is the decisive turning point — capture @2500 val
5. Monitor truck_R recovery after LR decay (crashed to 0.152 at @2000)
6. Verify offset_th stays below 0.20 red line after LR decay
7. Check for new ORCH instructions
8. Resume 30-min monitoring cycles
