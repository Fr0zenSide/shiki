Launch and manage the Shiki orchestrator — the 24/7 autonomous multi-company agency loop.

## Usage

```
/orchestrate                    # Show orchestrator status
/orchestrate status             # Same as above
/orchestrate start              # Launch the heartbeat loop
/orchestrate stop               # Stop the heartbeat loop
/orchestrate wake <company>     # Force-launch a company session
/orchestrate pause <company>    # Pause a company mid-session
/orchestrate decide             # Batch-answer all pending T1 decisions
/orchestrate report             # Cross-company digest (today's activity)
```

## Arguments

Parse `$ARGUMENTS` for subcommand.

## `status` (default)

Query the orchestrator overview and display:

```bash
curl -s http://localhost:3900/api/orchestrator/status
```

```markdown
## Orchestrator Status

| Metric | Value |
|--------|-------|
| Active companies | 3 |
| Pending tasks | 12 |
| Running tasks | 2 |
| Blocked tasks | 1 |
| Pending decisions (T1) | 2 |
| Today's spend | $4.23 |

### Active Companies
| Company | Status | Tasks (P/R/B) | Heartbeat | Today $ |
|---------|--------|---------------|-----------|---------|

### Pending Decisions (T1 — Blocking)
| Company | Question | Tier | Age |
|---------|----------|------|-----|
```

## `start`

**This is the heartbeat loop.** It runs continuously.

### Loop Logic (every 60 seconds)

```
1. DECISIONS
   - Query: GET /api/decision-queue/pending
   - If any T1 pending: send ntfy push
     "🔴 N decisions needed (Company1: X, Company2: Y)"

2. COMPLETIONS
   - Query: GET /api/decision-queue?answered=true (since last check)
   - For each newly answered decision with a blocked task:
     the API auto-unblocks — just log it

3. HEALTH
   - For each active company:
     if last_heartbeat_at > 5 min ago AND status='active':
       log warning, attempt crash recovery
       (relaunch company session from last pipeline checkpoint)

4. BUDGET
   - For each active company:
     GET /api/companies/<id> → check budget.spent_today_usd vs budget.daily_usd
     if exceeded: PATCH status='paused', send ntfy alert

5. SCHEDULE
   - For each active company with pending tasks and no running session:
     check schedule.active_hours against current time in schedule.timezone
     if within window: launch company session (see "wake" below)

6. Sleep 60s, repeat
```

### State Tracking

Keep a local object `lastCheck` with timestamps per check type. Reset on each cycle.

## `wake <company>`

Launch a company Claude session in a tmux pane:

```bash
tmux new-window -t shiki-board -n "co:<slug>" \
  "cd projects/<project-path> && SHIKI_COMPANY_ID=<company-id> claude --system-prompt 'You are running as company <slug>. Check in with the orchestrator, claim tasks from the task queue, and run /autopilot on each. Write T1 questions to the decision queue instead of blocking interactively. Exit when the queue is empty.' 'Run /company-heartbeat'"
```

## `pause <company>`

1. PATCH company status to 'paused'
2. If a tmux pane `co:<slug>` exists, send it a graceful exit signal

## `decide`

Shortcut to `/decide` but scoped to cross-company decision queue:

1. GET /api/decision-queue/pending
2. Group by company
3. Present in the standard `/decide` ballot format
4. On answer: PATCH /api/decision-queue/<id> with answer

## `report`

Cross-company daily digest:

```markdown
## Daily Report — <date>

### Per Company
| Company | Tasks Done | Tasks Failed | PRs Created | Decisions Asked | Spend |
|---------|-----------|-------------|-------------|----------------|-------|

### Highlights
- [auto-generated from completed task results]

### Blocked
- [list of currently blocked tasks with their blocking questions]
```

## Rules

- The orchestrator NEVER writes code. It only queries DB, launches sessions, and routes decisions.
- Companies are demand-driven: no pending tasks = no session launched = no tokens burned.
- Always check `schedule.active_hours` before launching a company outside business hours.
- Budget enforcement is hard: if `spent_today_usd >= daily_usd`, pause immediately.
- ntfy notifications use the existing `shiki-notify` system (`scripts/shiki-notify-lib.sh` or `./shiki notify`).
