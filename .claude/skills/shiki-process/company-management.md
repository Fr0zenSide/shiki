# Company Management Skill

A "company" is the orchestration wrapper around a Shiki project. It adds scheduling, budgets, task queues, and decision routing to enable autonomous multi-project operation.

## Company ↔ Project Mapping

Each company maps 1:1 to an existing `projects` entry in Shiki DB:

| Company Slug | Project Slug | Display Name | Project Path |
|-------------|-------------|-------------|-------------|
| wabisabi | wabisabi | WabiSabi | projects/wabisabi/ |
| maya | maya | Maya | projects/Maya/ |
| brainy | brainy | Brainy | projects/brainy/ |
| kintsugi | kintsugi-ds | DSKintsugi | projects/kintsugi-ds/ |

## Company Config Schema

```json
{
  "budget": {
    "daily_usd": 5,
    "monthly_usd": 150,
    "spent_today_usd": 0
  },
  "schedule": {
    "active_hours": [8, 22],
    "timezone": "Europe/Paris",
    "days": [1, 2, 3, 4, 5, 6, 7]
  },
  "config": {
    "backlog_source": "memory/backlog.md",
    "autopilot_flags": "--yolo",
    "max_concurrent": 3,
    "auto_merge_threshold": null
  }
}
```

### Fields

- **budget.daily_usd**: hard cap on daily API spend per company
- **budget.monthly_usd**: soft cap on monthly spend (warning only)
- **schedule.active_hours**: [start, end] in 24h format
- **schedule.timezone**: IANA timezone for schedule evaluation
- **schedule.days**: ISO weekdays (1=Mon through 7=Sun)
- **config.backlog_source**: path to backlog file (relative to project root)
- **config.autopilot_flags**: flags passed to /autopilot when launched by orchestrator
- **config.max_concurrent**: max parallel worktrees per company
- **config.auto_merge_threshold**: if set, auto-merge PRs with fewer than N open issues

## Company Session Protocol

When the orchestrator launches a company:

1. **Environment**: `SHIKI_COMPANY_ID=<uuid>` is set
2. **CWD**: `projects/<path>/`
3. **Startup**: company reads project-adapter.md + bootstrap skill
4. **Heartbeat**: POST to `/api/data-sync` every 2 min:
   ```json
   {
     "projectId": "<uuid>",
     "type": "company_heartbeat",
     "data": {
       "company_id": "<uuid>",
       "session_id": "<uuid>",
       "status": "active"
     }
   }
   ```
5. **Task loop**: claim → run → complete → claim next
6. **Exit**: POST `company_idle`, exit tmux pane

## Task Sources

Tasks enter the queue from:

1. **backlog**: parsed from `memory/backlog.md` by orchestrator
2. **autopilot**: generated during Wave 0 planning
3. **manual**: user adds via `/company` or API
4. **cross_company**: orchestrator creates when shared packages need updates

## Priority System

- Company priority: determines which company gets sessions first (0=highest)
- Task priority: determines order within a company's queue (0=highest)
- Default: 5 for both
