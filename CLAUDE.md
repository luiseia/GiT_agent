## Agent Operations
When I say 'cat <filepath>' or reference a command file, execute the instructions contained in that file immediately. Do not just read it — treat it as a directive to follow.

## General Principles
Prefer simple, direct solutions. Do NOT over-engineer with TaskCreate/sub-agents for straightforward tasks like mkdir, wget, or single-command operations. Only use task agents for genuinely complex exploration.

## Environment Setup
This project uses Python with a specific conda/venv environment. Always check which Python environment is active before running training or evaluation commands. Never assume the default system Python is correct.

## ML Training Monitoring
When monitoring ML training runs: report metrics concisely, do not make premature early stopping decisions, and wait for user-specified checkpoints before recommending action. If diagnosing class-level performance issues, investigate architectural/structural causes before blaming loss functions.

## Bug Fix Protocol
Before fixing any bug: 1) Write a minimal reproduction script that demonstrates the failure, 2) Run it to confirm the bug, 3) Make your fix, 4) Run `find . -name '*.pyc' -delete` to clear bytecache, 5) Re-run the reproduction to confirm the fix.

## Simple Operations
For simple tasks like mkdir, wget, file copies — execute the command directly. Do NOT spawn sub-agents or over-engineer with TaskCreate.
