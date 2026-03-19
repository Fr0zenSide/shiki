Show the dispatch board — a live status dashboard of all running background agents and tasks.

## What to Display

### 1. Dispatch Board (Feature Agents)

Check for active dispatches:
- Run `git worktree list` to find dispatch worktrees (`/tmp/wt-*`)
- For each worktree, check the branch and recent commits (`git -C <path> log --oneline -3`)
- Check for open PRs: `gh pr list --json number,title,headRefName,state`

Render a table:

```
## Dispatch Board
| Feature | Branch | Worktree | Status | Tasks | PR |
|---------|--------|----------|--------|-------|----|
```

### 2. Background Agents

Check for running background tasks using TaskList. For each task show:
- Description/name
- Status (running/completed/failed)
- Duration

Render a table:

```
## Background Agents
| Agent | Status | Duration |
|-------|--------|----------|
```

### 3. Pending Deliverables

List any recently completed background agents with their output summaries.

### 4. Company Status (Orchestrator)

If the orchestrator is running (check via `shiki_health` MCP tool), show:
<!-- TODO: migrate to shiki_health when orchestrator status is added to MCP -->

```
## Companies
| Company | Status | Tasks (P/R/B) | Decisions | Heartbeat | Today $ |
|---------|--------|---------------|-----------|-----------|---------|
```

Where P/R/B = pending/running/blocked. Heartbeat shows "healthy", "stale", or "dead".

If the orchestrator endpoint returns an error (tables don't exist yet), skip this section silently.

## Rules

- If no agents, worktrees, or companies are active, say "All clear — no active dispatches."
- Use progress bars: `░` (pending), `█` (done) — 8 chars wide, proportional to completion
- Show timestamps for completed items
- Keep it concise — this is a status check, not a report
