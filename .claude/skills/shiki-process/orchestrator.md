# Orchestrator Skill — Multi-Company Autonomous Agency

The orchestrator is the top-level coordination layer for Shiki's 24/7 autonomous development agency. It manages multiple "companies" (project wrappers with orchestration metadata), routes decisions across them, enforces budgets, and ensures crash recovery.

## Architecture

```
@Daimyo (human)
     │
     ntfy push ← decisions needed / PRs ready
     │
┌────┴────────────────┐
│  ORCHESTRATOR       │  Layer 1: Main Claude session
│  /orchestrate       │  tmux session "shiki-board"
│  heartbeat loop     │  CWD: workspace root
│  NEVER writes code  │  reads DB, launches companies
└────┬────────────────┘
     │ tmux panes
     ├── co:wabisabi    → /autopilot in projects/wabisabi/
     ├── co:maya        → /autopilot in projects/Maya/
     ├── co:brainy      → /autopilot in projects/brainy/
     └── co:kintsugi    → /autopilot in projects/kintsugi-ds/
```

## Company Lifecycle

```
created → active → paused → active → archived
                ↑         ↓
                └─────────┘ (budget exceeded / schedule / manual)
```

- **active**: eligible for task processing
- **paused**: temporarily stopped (budget, schedule, or manual)
- **archived**: permanently retired

## Decision Flow

```
Company autopilot hits T1 question
  → INSERT into decision_queue (tier=1)
  → SET task status='blocked'
  → Continue to next non-blocked task
  → Poll decision_queue every 30s for answer

Orchestrator detects pending T1
  → Send ntfy push to @Daimyo
  → Present in /orchestrate decide (or /decide)
  → User answers
  → PATCH decision_queue with answer
  → API auto-unblocks the task (sets status='pending')
  → Company resumes blocked task on next poll
```

## Budget Enforcement

```
Company session reports cost via performance_metrics
  → Orchestrator sums today's spend per company
  → If spent_today_usd >= daily_usd cap:
    → PATCH company status='paused'
    → Send ntfy alert
    → Company session exits gracefully
```

Budget is tracked in `company_budget_log` (hypertable) and summarized in `companies.budget.spent_today_usd`.

## Crash Recovery

```
Orchestrator detects stale heartbeat (> 5 min):
  1. Check last pipeline checkpoint for the company's running task
  2. If checkpoint exists: relaunch company, resume from checkpoint
  3. If no checkpoint: mark task as 'failed', move to next
  4. Log recovery event to audit_log
```

## Shared Package Safety

Packages at `packages/` are shared across companies. When a task touches `packages/*`:

1. Task is tagged with `source='cross_company'`
2. Orchestrator serializes: only ONE cross_company task per package runs at a time
3. After merge: orchestrator signals all active companies to rebase
4. Companies rebase worktree branches before claiming next task

## DB Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /api/orchestrator/status` | Full overview |
| `GET /api/companies` | List companies |
| `GET /api/companies/:id` | Company status view |
| `PATCH /api/companies/:id` | Update status/budget/config |
| `POST /api/task-queue` | Add tasks |
| `POST /api/task-queue/:id/claim` | Atomic task checkout |
| `PATCH /api/task-queue/:id` | Update task status |
| `GET /api/decision-queue/pending` | All unanswered decisions |
| `POST /api/decision-queue` | Create a decision |
| `PATCH /api/decision-queue/:id` | Answer a decision |

## Anti-Patterns

| Temptation | Why it's wrong |
|------------|---------------|
| "Keep company sessions running when idle" | Burns tokens. Exit on empty queue, relaunch on demand. |
| "Answer T2/T3 questions via orchestrator" | Only T1 goes through orchestrator. T2/T3 handled within company (defaults or --yolo). |
| "Let orchestrator write code" | NEVER. Orchestrator reads DB, launches sessions, routes decisions. That's it. |
| "Skip heartbeat checks" | Stale sessions waste money and block tasks. 5-min threshold is non-negotiable. |
| "Ignore budget caps" | Caps exist for a reason. Pause immediately, don't warn and continue. |
