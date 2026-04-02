# Shiki Cheat Sheet

## Getting Started

```bash
shiki start                # Launch everything from scratch
tmux attach-session        # Reconnect to running session
shiki stop                 # Kill tmux session (containers stay up)
```

## tmux Navigation

| Action | Shortcut |
|--------|----------|
| Switch tabs | `Opt + Shift + ←/→` |
| Switch panes | `Opt + ←/↑/↓/→` |
| Zoom/unzoom pane | `Ctrl-b` then `z` |
| Scroll up in pane | `Ctrl-b` then `[` (then arrows, `q` to exit) |
| Detach (session stays alive) | `Ctrl-b` then `d` |

### Session Layout

```
Tab 1: orchestrator   ← your main Claude + heartbeat loop
Tab 2: board          ← dynamic task panes (appear/disappear as tasks dispatch)
Tab 3: research       ← 4 terminals (INGEST · RADAR · EXPLORE · SCRATCH)
```

Board panes are named `{company}:{task-short}` (e.g. `maya:mayakit-public-`).
They appear when tasks are dispatched and disappear when completed.

## Orchestrator Commands

```bash
shiki status               # Company overview (active/queued/idle + budget)
shiki board                # Rich board: progress bars, budget, health, last session
shiki history maya         # Session transcript history for maya
shiki history --detail ID  # Full transcript: plan, files, tests, PRs
shiki decide               # Answer pending T1 decisions (interactive)
shiki report               # Daily cross-company digest
shiki report --date 2026-03-14   # Specific date
```

### shikki (direct)

```bash
shikki status           # Same as shikki status
shikki status --legacy  # Old table format
shikki board            # Rich board overview (tasks, budget, health, sessions)
shikki history maya     # Transcript history for a company
shikki history --task ID       # Filter by task
shikki history --phase failed  # Filter by phase
shikki history --detail ID     # Full transcript detail
shikki history --raw --detail ID  # Include raw terminal log
shikki start            # Run heartbeat loop (auto-dispatches tasks)
shikki wake maya        # Force-launch a company session
shikki pause brainy     # Pause a company
shikki decide           # Answer T1 decisions
shikki report           # Daily digest
```

## Process Commands (inside any project Claude)

| Command | When | What |
|---------|------|------|
| `/quick "fix X"` | Small change (< 3 files) | 4-step pipeline |
| `/md-feature "X"` | New feature | 8-phase pipeline |
| `/pre-pr` | Before any PR | 9-gate quality review |
| `/review <PR#>` | Reviewing PRs | 3-agent pre-analysis |
| `/dispatch` | Large feature | Parallel worktree implementation |
| `/ingest <url>` | Import knowledge | Repo/URL → vector DB |
| `/radar scan` | Monitor deps | Breaking changes + updates |
| `/remember "X"` | Recall decisions | Search memory + DB + git |

## Agent Team

Mention `@Name` in any Claude session to invoke:

| Agent | Role | When |
|-------|------|------|
| `@Sensei` | CTO | Architecture decisions |
| `@Hanami` | Designer | UX, accessibility |
| `@Kintsugi` | Philosophy | Design principles |
| `@Ronin` | Reviewer | Security, edge cases |
| `@Indy` | Memory | "What did we decide about X?" |
| `@Daimyo` | Founder (you) | Final call |

## Infrastructure

```bash
docker compose up -d       # Start DB + Ollama + backend
docker compose down        # Stop everything
docker compose logs -f backend   # Watch backend logs

./shiki status             # Health check (services + memory + pipelines)
curl localhost:3900/health # Quick API check
```

## API Endpoints (new)

```bash
# Board overview
curl localhost:3900/api/orchestrator/board

# Dispatcher queue (pending tasks ordered by priority)
curl localhost:3900/api/orchestrator/dispatcher-queue

# Session transcripts
curl localhost:3900/api/session-transcripts?company_slug=maya
curl localhost:3900/api/session-transcripts?company_slug=maya&phase=completed&limit=5
curl localhost:3900/api/session-transcripts/<id>
```

## Common Workflows

### Morning Startup
```bash
shiki start                # Everything boots
# → Tab 2: tasks auto-dispatch based on priority + budget
# → Tab 1: you're in Claude, ready to direct
shiki board                # See what's running, what's queued
```

### Check What's Happening
```bash
shiki board                # Rich overview: progress, budget, health, last session
shiki status               # Quick overview: active/queued/idle
# or Opt+Shift+→ to Tab 2 and see active task panes live
```

### Review What Happened
```bash
shiki history maya         # What did maya do recently?
shiki history --detail ID  # Full plan + files + test results + PRs
shiki history wabisabi --phase failed  # What failed?
```

### Unblock Agents
```bash
shiki decide               # Answer T1 decisions from terminal
# or in Tab 1: "answer the 3 pending decisions"
```

### End of Day
```bash
shiki report               # What shipped today
shiki board                # Final health check
# Ctrl-b then d to detach (dispatcher keeps running)
```

### Research Session
```bash
# Opt+Shift+→ to Tab 3 (research)
# Opt+arrows to pick a pane
claude                     # Start Claude in the research project
/ingest https://github.com/interesting/repo
/radar scan
```
