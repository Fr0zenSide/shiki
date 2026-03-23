# The Shikki Flow — Product Reference Spec

> Source of truth for Shikki's core pipeline. Validated 2026-03-23 by @Daimyo.

## Philosophy

Shikki is a **list-processing machine**. Every stage produces a list. Every list has the same UX: sort, validate, kill, add context, move forward. The user (@Daimyo) is the gatekeeper at every gate — except in `--yolo` mode.

**No multi-pane chaos.** One list at a time. Focus, not surveillance. The event bus logger is the only real-time stream — and it's free tokens (data mirroring, not LLM calls).

## The Flow

```
INPUT ──→ BACKLOG ──→ DECIDE ──→ SPEC ──→ REVIEW PLAN ──→ RUN ──→ INBOX ──→ REVIEW PR ──→ SHIP ──→ REPORT
  │          │           │         │          │              │        │          │             │         │
  ▼          ▼           ▼         ▼          ▼              ▼        ▼          ▼             ▼         ▼
prompts   sort/kill   Q&A to    @shi team  validate/     dispatch  PR list   pipe to       gate-of-   budget
notes     validate    resolve   specs      correct       to nodes  ready     diff tools    gates      LOC/sprint
Flsh      add ctx     shadows   plans      the plan      event bus for       save          release    per company
push                                                     logger    review    progress      to target  per project
```

**All stages are ShikiCore components** — compiled Swift, not skills or commands that agents can skip. The `quick` flow is a FeatureLifecycle preset that enters at RUN and exits at INBOX. Skills (`.claude/skills/`) are the UI interface that invokes ShikiCore — they don't own the logic.

## Stages in Detail

### 1. INPUT — Sources of Ideas

**What enters:** Raw ideas, prompts to main orchestrator, push notes from external apps (Flsh, ntfy, any `shiki push` producer).

**Where it lands:** The **backlog** — a persistent ordered list in ShikiDB.

**Commands:** None specific. Input is implicit (conversation with orchestrator, `shiki push`, Flsh voice notes).

---

### 2. BACKLOG — `shikki backlog`

**Purpose:** Treat the raw idea list. Sort by priority, validate or kill items, add context to vague ideas.

**UX:** List interface (like `shikki review`/`shikki pr`). Each item shows:
- Title + one-line description
- Source (who/when/how it entered)
- Priority (draggable or numeric)
- Status: `raw` → `enriched` → `ready` → `killed`

**Actions per item:**
- **Enrich** — add context, links, references
- **Promote** — mark as `ready` (eligible for `decide` + `spec`)
- **Kill** — remove with reason
- **Reorder** — change priority
- **Split** — break into sub-items

**Storage:** ShikiDB `backlog_items` table (or `task_queue` extended with backlog lifecycle).

**CLI:** `shikki backlog` — opens the list. `shikki backlog add "idea"` — quick add.

---

### 3. DECIDE — `shikki decide`

**Purpose:** Resolve shadows. Every idea that's `ready` in the backlog may have unknowns — technical feasibility, design choices, scope boundaries, dependencies. `decide` is the Q&A module that surfaces and resolves these before spec.

**UX:** Same list interface. Each decision shows:
- Question (from @shi team or from spec analysis)
- Tier (T1 = blocks everything, T2 = blocks one task, T3 = nice to have)
- Options (if any)
- Context (what triggered this question)

**Actions per item:**
- **Answer** — provide the decision
- **Delegate** — forward to a specific agent for research
- **Defer** — push to next sprint (with reason)
- **Auto-resolve** — @Sensei proposes, @Daimyo approves in one shot

**Already exists:** Backend API + `shiki decide` CLI. Needs polish: list UX, progression tracking, batch mode.

---

### 4. SPEC — `shikki spec`

**Purpose:** @shi team takes the decided, enriched backlog items and produces the best parallel execution plan. Multi-project, multi-company, multi-scope.

**Output:** One or more spec documents (`features/*.md`) with:
- Wave breakdown (what runs in parallel)
- Dependency tree (what blocks what)
- Sub-agent assignments (which agent handles which sub-task)
- Test strategy per task
- Estimated effort

**UX:** Not a list — this is the generative phase. The orchestrator dispatches spec agents, they produce plans, plans land as files.

**Already exists:** `/spec` skill (8-phase pipeline). Needs: `shikki spec` CLI entry point that triggers the skill programmatically.

---

### 5. REVIEW PLAN — List of Specs to Validate

**Purpose:** The spec phase produces N plans. @Daimyo reviews each one — validate, correct, or reject.

**UX:** Same list interface as backlog/inbox. Each item is a spec file:
- Title + summary
- Files it will touch
- Dependencies
- @shi team confidence score

**Actions per item:**
- **Approve** — move to `run` queue
- **Correct** — `/course-correct` with adjustments
- **Reject** — back to backlog with reason
- **Challenge** — request @Ronin adversarial review

**Not a separate command.** This is `shikki inbox` with a filter: `shikki inbox --specs` or just part of the unified inbox.

---

### 6. RUN — `shikki run`

**Purpose:** The "let's go" moment. Approved specs are dispatched to execution nodes.

**What happens:**
- Parallel dispatch to sub-agents (worktrees, company panes, or background processes)
- Each agent works in TDD mode
- Progress + events stream to ShikiDB event bus
- The **event logger pane** (right side, above heartbeat) shows real-time: `[who] [where] [what]` — one line per event, no LLM tokens spent

**CLI:** `shikki run` — dispatches all approved specs. `shikki run --spec p1-group-a` — dispatch specific spec.

**Event bus format:**
```
[14:32:01] maya:agent-a1  spec/p1-group-a  task-1: tests passing (8/8)
[14:32:15] shiki:agent-b3 spec/p0          e2e-skip: committed d4f2a1b
[14:32:30] wabisabi:agent-c2 spec/p1-b     netkit: PR #31 created
```

---

### 7. INBOX — `shikki inbox`

**Purpose:** Centralized list of everything that needs @Daimyo's attention. PRs, completed specs, failed gates, decisions.

**UX:** Same list interface. Each item shows:
- Type icon: PR / spec / decision / gate-failure
- Title
- Status: `pending` → `in-review` → `validated` / `corrected`
- Age (how long it's been waiting)

**Actions per item:**
- **Open** — jump to review (pipes to `shikki review` for PRs)
- **Validate** — approve and close
- **Correct** — send correction to orchestrator
- **Defer** — push to later

**CLI:** `shikki inbox` — full list. `shikki inbox --prs` — PRs only. `shikki inbox --count` — just the number.

---

### 8. REVIEW PR — `shikki review <N>`

**Purpose:** Deep review of a specific PR. Pipes to external diff tools.

**UX:** Not a list — this is the deep-dive phase.

**CLI:** `shikki review 14 --from #13 --diff | diffnav` or `| delta`

**Features:**
- Save progress (which files reviewed, which pending)
- Add comments (corrections piped back to orchestrator)
- Approve = validates the inbox item
- Batch mode: `shikki review 14..18` — review a range

**Already exists:** `shiki pr` with read/comment/delta/progress tracking. Needs: rename to `shikki review`, batch notation, inbox integration.

---

### 9. SHIP — `shikki ship`

**Purpose:** The release gate. PRs are reviewed and approved — now ship them. Pipeline-of-gates architecture: each gate must pass before the next runs.

**8 Gates:**
1. **CleanBranch** — no uncommitted changes, on correct branch
2. **Test** — full test suite passes
3. **Coverage** — meets threshold (configurable per project)
4. **Risk** — release risk score from ShikiDB (graceful if DB down)
5. **Changelog** — auto-generated from conventional commits
6. **VersionBump** — semver bump based on commit types
7. **Commit** — release commit with changelog + version
8. **PR** — create PR to target branch (or merge directly)

**UX:**
- **Preflight Glow** — single-screen manifest showing what will happen before launch
- **Silent River** — single status line during execution (not scrolling output)
- ntfy notification on success/failure
- Mandatory "why" field — ship log, not ship count

**CLI:** `shikki ship` — full pipeline. `shikki ship --dry-run` — show plan without side effects. `shikki ship --history` — past releases from DB.

**Already exists:** `ShipCommand` spec + `ShipGate` protocol design. See `features/shiki-ship.md`. Needs: implementation of the 8 gates as ShikiCore components, ShipEvent integration with event bus.

**ShikiCore integration:** `ShipService` is a peer to `FeatureLifecycle` — both are top-level ShikiCore components. ShipEvents are ShikiEvents, persisted via EventPersister.

---

### 10. REPORT — `shikki report` / `shikki codir`

**Purpose:** Productivity dashboard. The CODIR board.

**Shows:**
- Activity summary per sprint (Shikki flow cycle)
- Budget spent per company, per project, per workspace
- LOC delta (+/-) per sprint
- Tasks completed / in-progress / blocked
- Agent utilization (context %, compaction count)
- PR merge rate, review time

**CLI:** `shikki report` — last sprint summary. `shikki report --weekly` — weekly rollup. `shikki codir` — executive board view.

**Storage:** Aggregated from ShikiDB events (agent_events, task_queue, decision_queue, session_transcripts).

---

## The Shared List UX

Every list command (`backlog`, `decide`, `inbox`, `review plan`) shares the same interaction model:

1. **Display**: Numbered list with status indicators
2. **Navigate**: Arrow keys or numbers to select
3. **Act**: Single-key actions (a=approve, k=kill, e=enrich, d=defer)
4. **Filter**: `--status`, `--company`, `--priority`
5. **Sort**: `--sort priority|age|company`
6. **Progress**: Checkmark progression (X of N reviewed)
7. **Persistence**: Progress saved between sessions

This is the **ListReviewer** component — one TUI widget, reused across all list commands.

---

## Event Bus Logger

**Not an LLM feature.** Pure data stream — zero token cost.

**Implementation:** A heartbeat-like loop that subscribes to ShikiDB's WebSocket channel (`/ws`) and renders events in a tmux pane.

**Format:** `[HH:MM:SS] company:agent scope what`

**Pane location:** Right side of main window, above heartbeat. ~40% of the right column height.

**Already exists partially:** WebSocket support in the backend (`WsSubscribeSchema`). Needs: CLI subscriber + tmux pane integration.

---

## Fast Lane — `shikki quick`

**Purpose:** Bypass the full flow for small, well-understood changes. Bug fixes, 1-3 file tweaks, config changes. If it takes longer than one agent session, it wasn't quick — escalate to `shikki spec`.

**When to use:** The change is obvious. No shadows to resolve. No multi-project impact. No decision needed. Just do it.

**Flow:** `shikki quick "fix the heartbeat interval"` → agent claims it → TDD (failing test → fix → green) → PR created → lands in `shikki inbox` for review.

**Already exists:** `/quick` skill (4-step pipeline). Needs: `shikki quick` CLI entry point + auto-escalation detection (if scope grows beyond 3 files, suggest `/spec` instead).

**Not in the main flow diagram** — it's a shortcut that enters at RUN and exits at INBOX, skipping backlog/decide/spec entirely. Still a ShikiCore component — `quick` is a FeatureLifecycle preset, not a skill bypass.

---

## Onramp — `shikki wizard`

**Purpose:** First-run onboarding. Make Shikki natural for new users from the first command.

**Flow:**
1. **Detect first run** — no `~/.config/shiki/` or no companies in DB
2. **Interactive setup:**
   - Workspace location (auto-detect or ask)
   - Scan for projects (git repos in `projects/`)
   - Create companies from discovered projects
   - Configure LLM provider (API key, local LLM, or OpenRouter)
   - Backend health check + Docker bootstrap if needed
3. **Guided tour:**
   - Explain the Shikki flow in 30 seconds (backlog → spec → run → inbox → review)
   - Create a sample backlog item from a real project issue
   - Walk through one `shikki quick` fix end-to-end
   - Show `shikki inbox` with the resulting PR
4. **Graduate:** "You're ready. Type `shikki` to start."

**Design principles:**
- Never ask more than 3 questions per screen
- Auto-detect everything possible (git, docker, API keys from env)
- Show, don't tell — the tour does a real task, not a dry demo
- Idempotent — run `shikki wizard` again to reconfigure without losing data

**Already exists partially:** `StartupCommand` does environment detection + Docker bootstrap. Needs: interactive project scanning, guided tour, company creation from discovered repos.

---

## What Exists Today vs. What's Missing

| Stage | Command | Exists? | Gap |
|-------|---------|---------|-----|
| Input | (implicit) | Partial | `shiki push` not built |
| Backlog | `shikki backlog` | No | New command + DB table |
| Decide | `shikki decide` | Yes (basic) | Needs list UX, batch mode |
| Spec | `shikki spec` | Yes (skill) | Needs CLI entry point |
| Review Plan | `shikki inbox --specs` | No | Part of inbox |
| Run | `shikki run` | No | New dispatch command |
| Inbox | `shikki inbox` | No | New command + unified list |
| Review PR | `shikki review` | Yes (`shiki pr`) | Rename + inbox integration |
| Report | `shikki report` | No | New command + aggregation |
| Ship | `shikki ship` | Yes (spec) | Needs 8-gate implementation in ShikiCore |
| Quick | `shikki quick` | Yes (skill) | Needs CLI entry + auto-escalation |
| Wizard | `shikki wizard` | Partial (StartupCommand) | Needs interactive tour + project scan |
| Event Logger | (pane) | No | WS subscriber + pane |
| ListReviewer | (TUI widget) | No | Shared component |

**Core missing pieces (build order):**
1. **ListReviewer** TUI component (everything depends on this)
2. **`shikki backlog`** (first consumer of ListReviewer)
3. **`shikki inbox`** (second consumer, replaces multi-pane)
4. **`shikki quick`** CLI entry point (wraps existing /quick skill + auto-escalation)
5. **`shikki run`** (dispatch from approved specs)
6. **Event logger pane** (WS subscriber)
7. **`shikki report`** (aggregation from DB)
8. **`shikki ship`** (8-gate pipeline in ShikiCore — ShipService + ShipGate protocol)
9. **`shikki wizard`** (onboarding tour + project scanner)
10. **`shikki spec`** CLI entry point (wraps existing skill into ShikiCore)
11. Polish `shikki decide` (adopt ListReviewer)
12. Polish `shikki review` (rename + inbox integration)

---

## ListReviewer — Enhanced UX Features (validated by @Hanami)

These features are part of the ListReviewer shared component. All list commands inherit them.

1. **Fuzzy search** — Type `/` in any list to filter by keyword. Fast scan over large lists.
2. **Inline preview** — Press `Enter` to expand a 3-line preview without leaving the list. Like `less` for structured data.
3. **Batch actions** — Select multiple items with `Space`, apply action to all. "Approve 3, 5, 7" in one gesture.
4. **Undo last action** — `Ctrl-Z` undoes the last approve/kill/defer. Irreversible actions (ship) still require confirmation.
5. **Smart ordering** — Auto-sort by composite score: age + priority + dependencies. Item #1 is always what you should handle first. Override with `--sort`.
6. **Progress persistence** — Review 4 of 8, quit, next `shikki inbox` resumes from #5. No lost progress across sessions.
7. **Color-coded urgency** — Red = blocking other work. Yellow = aging (>24h). Green = ready. Dim = deferred. The list is a heatmap.
8. **Pipe-friendly** — `shikki inbox --json` for scripting. `shikki inbox --count` for just the number. Every list command is both TUI and pipe.
9. **Context injection** — In `shikki review`, press `?` to see the event logger context (agent decisions during implementation) without leaving the review.
10. **Completion signal** — Terminal bell + ntfy push when all inbox items validated. Inbox zero should be tangible.

**Implementation priority — v1:** Features 3 (batch actions), 5 (smart ordering), 6 (progress persistence), 7 (color urgency), 8 (pipe-friendly). **v1.1:** Features 1 (fuzzy search), 2 (inline preview), 4 (undo), 9 (context injection), 10 (completion signal).

---

## Constraint: Swift Build Isolation

**Problem:** Multiple Swift agents running `swift build/test` cause SPM `.build/.lock` contention (exit 144).

**Solution: `--scratch-path` per agent (FULL parallelism)**

```bash
AGENT_ID="$(basename $(git rev-parse --show-toplevel))"
swift build --scratch-path "/tmp/shiki-builds/${AGENT_ID}/.build"
swift test  --scratch-path "/tmp/shiki-builds/${AGENT_ID}/.build"
```

Each agent gets its own `.build/.lock`, `build.db`, compiled artifacts. Shared dependency cache reused. First build cold (~30s), subsequent incremental. No serialization needed.

**DispatchManager rules:**
- All Swift agents use `--scratch-path /tmp/shiki-builds/$AGENT_ID/.build`
- Always `SKIP_E2E=1` for non-interactive agents
- If dependency resolution contends: add `--cache-path /tmp/shiki-builds/$AGENT_ID/cache`
