# Conductor Report: Plan D iter 500 Assessment
**Time**: 2026-03-05 18:32
**Decision Cycle**: #2

---

## Situation Summary

Plan D (reg_w=1.0, loaded from Plan C iter_1000) reached iter 500 validation at 18:29. Training continues normally (iter 560+ as of 18:32).

## iter 500 Key Metrics

| Metric | Value | Red Line | Status |
|--------|-------|----------|--------|
| truck_R | 0.148 | < 0.08 | SAFE (margin: +0.068) |
| bg_FA | 0.207 | > 0.25 | SAFE (margin: -0.043) |
| truck_P | 0.202 | — | BEST EVER @500 |
| bus_R | 0.612 | — | BEST EVER @500 (2x Plan C) |
| cls/reg ratio | 1.21:1 | — | RESTORED (was 1:3-4 in Plan C) |

## Strategic Assessment

### What reg_w=1.0 Fixed
1. **Gradient parity restored**: cls and reg loss are now comparable (0.87 vs 0.72)
2. **truck_P dramatically improved**: 0.202 vs Plan C's 0.058 — cls gradients no longer starved
3. **bus_R surged**: 0.612 vs 0.322 — bus features can now learn without reg domination

### What reg_w=1.0 Did NOT Fix
1. **bg_FA still rising**: 0.207 > Plan C's 0.156. BUG-2 (bg_balance_weight=3.0 may be insufficient) persists
2. **car_P dropped**: 0.095 vs Plan C's 0.143. More false car predictions
3. **Grad norm still insane**: avg 23.0, 100% clipped at 0.5. BUG-9 unaddressed
4. **BUG-10 (optimizer cold start)**: resume=False means first 100-200 iters unstable

### Unresolved Critic Bugs
- BUG-8 (cls loss missing bg_weight): UNPATCHED
- BUG-9 (permanent gradient clipping): UNPATCHED — affects ALL plans
- BUG-10 (optimizer cold start): UNPATCHED — may explain iter 500 volatility
- BUG-11 (class order mismatch risk): UNPATCHED

## Decisions Made

1. **Plan D: CONTINUE** — no red lines triggered, need iter 1000 for proper trend analysis
2. **P1 (Center/Around): DEFERRED** — need clean P0 baseline first; GPU 1,3 margin too tight (1.5GB)
3. **ORCH_20260305_1832 issued** — researcher instructed to monitor and prepare P1 for iter_1000 launch
4. **GPU 1,3 strategy**: CEO authorized use. Will attempt when yl0826 memory drops or completes. Current 17.3GB free vs 15.8GB needed = too risky.

## Next Decision Point

- **iter 1000** (~18:50-19:00): Full trend analysis, P1 launch decision
- Red line watch: truck_R (trending down from C@1000=0.114, need recovery), bg_FA (trending up)

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| truck_R collapses below 0.08 | Medium | RED LINE | Monitor closely at iter 1000 |
| bg_FA crosses 0.25 | Medium | RED LINE | Consider bg_weight=5.0 if triggered |
| BUG-9 prevents convergence | High | Severe | Needs architectural fix (grad clip threshold or loss scaling) |
| yl0826 OOM if we use GPU 1,3 | High | Severe | Wait for memory drop |

---
*The Conductor, Decision Cycle #2*
