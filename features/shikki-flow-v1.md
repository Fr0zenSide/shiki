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

**CLI:** `shikki inbox` — full list. `shikki inbox --prs` — PRs only. `shikki inbox --count` — just the number. `shikki inbox --company maya` — scoped.

**Piping to review:** `shikki review inbox` — auto-opens review for all PRs from inbox (equivalent to `shikki review --from inbox`). Also: `shikki review 14..18` — range notation for batch PR review. Each review pipes to external diff tools: `shikki review 14 | bat`, `shikki review 14 | delta`.

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
6. **VersionBump** — semver bump based on commit types + git tag (`vX.Y.Z`) on the release commit
7. **Commit** — release commit with changelog + version + signed tag
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

**Implementation:** NATS subscriber on `shikki.events.>`. The event logger is just one consumer of the Shikki Mesh Protocol (NATS-based distributed bus). Same protocol carries commands, discovery, task claims, decisions. See below.

---

## Distributed Protocol: Shikki Mesh (NATS)

**The distributed node protocol is the root decision** — logger, mobile, report are all leaves that subscribe to it.

**Protocol:** NATS (Core v1, JetStream v2 when `nats.swift` supports it)
**Transport:** `nats-server` single binary (20MB Go), localhost:4222 for v1, TLS leaf nodes for v2
**Persistence:** ShikiDB for replay/state, NATS for real-time transport only
**Auth:** NKeys (Ed25519 keypairs per agent node)

**Topic hierarchy:**
```
shikki.events.{company}.{type}     — pub/sub events (fire-and-forget)
shikki.commands.{node_id}          — directed commands (request/reply)
shikki.discovery.announce          — heartbeats (30s interval)
shikki.discovery.query             — "who's alive?" (request/reply)
shikki.tasks.{workspace}.available — task queue
shikki.tasks.{workspace}.claimed   — task claims
shikki.decisions.pending           — decisions needing input
```

**Why NATS:** Only protocol with native pub/sub AND request/reply. Single binary, zero config. NKeys auth. Topic hierarchy. Scale path: single server → cluster → leaf nodes → superclusters. Language agnostic (Swift, TS, Go, Rust clients).

**Format:** `[HH:MM:SS] {uuid8} company:agent scope what`

Each event line includes a short UUID (8 chars). Copy-paste the UUID to the main orchestrator → it retrieves the full event context from ShikkiDB for discussion and course-correction.

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
- **The wizard is a GAME, not a form** — inspired by Kinetype (type-to-play rogue-lite). Each step IS a real Shikki command that produces tangible output. The user learns by DOING, not reading.
- **Progressive disclosure** — start simple (backlog add), unlock tools as you progress (decide, spec, run). Like levels.
- **Tangible reward per step** — every wizard step produces something real (a backlog item, a decision, a spec, a PR). Not "configuration complete" — "you just shipped your first feature."
- **Replayable** — `shikki wizard` re-run teaches new features added since last run. New levels unlocked.
- Idempotent — run again without losing data

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
1. **`shikki spec`** — THE first stone. /md-feature was the first stone of what became Shikki. Wraps skill into ShikiCore SpecPipeline. Produces specs that feed the entire flow.
2. **ListReviewer** TUI component (interactive mode — everything after spec depends on this)
3. **`shikki backlog`** (first list consumer of ListReviewer)
4. **`shikki inbox`** (second consumer — pipes to review)
5. **`shikki run`** (dispatch from approved specs)
6. **`shikki quick`** CLI entry point (wraps skill + auto-escalation)
7. **`shikki report`** (aggregation from ShikkiDB — daily/weekly/per-company/personal auto-reports)
8. **`shikki ship`** (8-gate pipeline — ShipService + ShipGate + git tag)
9. **Event logger pane** (NATS subscriber)
10. **`shikki wizard`** (onboarding game)
11. Polish `shikki decide` (adopt ListReviewer)
12. Polish `shikki review` (rename + inbox piping + range notation + context popup)

---

## ListReviewer — Enhanced UX Features (validated by @Hanami)

These features are part of the ListReviewer shared component. All list commands inherit them.

1. **Fuzzy search** — Type `/` in any list to filter by keyword. Fast scan over large lists.
2. **Inline preview** — Press `Enter` to expand a 3-line preview without leaving the list. Like `less` for structured data.
3. **Batch actions** — Select multiple items with `Space`, apply action to all. "Approve 3, 5, 7" in one gesture.
4. **Undo last action** — `Ctrl-Z` undoes the last approve/kill/defer. Irreversible actions (ship) still require confirmation.
5. **Hybrid smart ordering** — Default: @shi team auto-sorts by composite score (age + priority + deps + blocking-impact). User can override by manually reordering items to the top (pinned items stay pinned across sessions). System proposes, user disposes. `--sort manual` disables auto-sort entirely.
6. **Progress persistence** — Review 4 of 8, quit, next `shikki inbox` resumes from #5. Stored in ShikkiDB (worker-scoped, private, not shared with companies). The system will be distributed — local JSON doesn't survive across nodes. ShikkiDB ensures progress is backed up, replicated, and available from any Shikki device. Local JSON only as offline cache.
7. **Scoped color-coded urgency** — Colors are relative to each company/project scope, not global. Red = blocking within that scope. Yellow = aging within that scope's cadence. Green = ready. Dim = deferred. A maya P1 and a kintsugi P1 don't share the same urgency — `shikki inbox --company maya` shows maya's heatmap, `shikki inbox` groups by company with per-scope coloring.
8. **Pipe-friendly** — `shikki inbox --json` for scripting. `shikki inbox --count` for just the number. Every list command is both TUI and pipe.
9. **Context injection** — In `shikki review`, press `?` to open a tmux popup pane (like Ctrl+F in user's custom tmux setup) showing the event logger context (agent decisions during implementation). Toggle with `?` to open, `Esc` or `?` again to close. Works in any shikki command during a tmux session. Emacs/vi-style shortcuts for navigating the popup content.
10. **Completion signal** — Terminal bell + ntfy push when all inbox items validated. Inbox zero should be tangible.

**Implementation priority — v1:** Features 3 (batch actions), 5 (smart ordering), 6 (progress persistence), 7 (color urgency), 8 (pipe-friendly). **v1.1:** Features 1 (fuzzy search), 2 (inline preview), 4 (undo), 9 (context injection), 10 (completion signal).

---

## ShikkiDB Schema — Privacy & Scope Separation

**Fundamental principle:** Personal data and company data are strictly separated in the schema.

### Three data scopes

1. **Worker scope (private)** — personal preferences, reading progress, inbox state, personal reports, AI conversation history. NEVER shared with companies. Encrypted at rest. Only the user can query this.

2. **Company scope (shared, bounded)** — work sessions, PRs, task completions, code contributions, CODIR reports. Shared within the company but NOT across companies. A worker's activity for Company A is invisible to Company B.

3. **Global scope (system)** — Shikki system state, agent configurations, NATS topology. No personal data.

### Report scoping

- `shikki report` defaults to `--all` (user sees everything)
- `shikki report --company maya` — only maya work. This is the shareable version.
- Sharing a report to a colleague = auto-scoped to their company. No privacy leaks.
- **Manager level** — sees team activity for their company only. Can generate CODIR reports.
- **CODIR level** — sees project/team aggregates. CANNOT see individual worker struggles.
- **Worker protection** — if a worker is in trouble (low output, high context churn), this is visible ONLY to their direct manager, NOT to CODIR. Managers open the discussion — no judgment, just numbers and human care.

### Philosophy: Humans at the center

> "We are defining the way we gonna work with generative AI for the next decades. These great tools need to improve us, augment us, but not reduce us. We need to work together at every level, not against each other."

- No surveillance metrics visible to executives
- No "productivity score" that ranks workers
- Reports show progress, not performance
- AI augments the worker — it doesn't replace the conversation between manager and team member
- The right to disconnect: a worker's personal Shikki data (outside work hours) is invisible to the company

### GitHub independence path

`shikki review 14..18` (range notation) + ShikkiDB comment system + ShikkiDB PR storage = GitHub becomes optional. Future: replace GitHub Actions with self-hosted CI (n8n, Woodpecker, Dagger), reduce GAFAM dependency. The code lives in git. The workflow lives in Shikki.

---

## Marketplace (backlog — obyw.one core)

Third-party marketplace for Shikki, Brainy, and future OBYW products. Like an App Store but for extensions/plugins/sources.

- Validate or reject external tools that improve products
- Revenue model TBD (free tier + premium, or pure validation without commission)
- Source plugins (Brainy), skills (Shikki), themes (DSKintsugi) — all distributed via marketplace
- Built as a core OBYW.one service, shared across all products

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

---

## Business Rules

### Flow Lifecycle (BR-F-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-F-01 | Every flow item starts in `raw` state. No item can skip `raw`. | FlowStateMachine | P0 |
| BR-F-02 | `raw` → `enriched` requires at least one context addition (tag, note, or link). | BacklogManager | P0 |
| BR-F-03 | `enriched` → `ready` requires all linked decisions to be answered. | BacklogManager + DecisionQueue | P0 |
| BR-F-04 | `ready` → `specced` requires a spec file produced by `shikki spec`. | SpecPipeline | P0 |
| BR-F-05 | `specced` → `approved` requires @Daimyo validation via ListReviewer. | ListReviewer | P0 |
| BR-F-06 | `approved` → `running` triggers DispatchManager. No manual agent launch. | DispatchManager | P0 |
| BR-F-07 | `running` → `inbox` happens automatically when agent completes (PR created). | DispatchManager + InboxManager | P0 |
| BR-F-08 | `inbox` → `reviewed` requires at least one `shikki review` session with progress > 0. | ReviewPipeline | P0 |
| BR-F-09 | `reviewed` → `shipped` requires all 8 ship gates to pass. | ShipService | P0 |
| BR-F-10 | `shipped` → `reported` happens automatically — report data is computed, not manually entered. | ReportAggregator | P1 |
| BR-F-11 | Quick flow: `raw` → `running` is allowed ONLY for items touching ≤3 files. Auto-escalation to spec if >3 files or >30min elapsed. | QuickPipeline | P0 |
| BR-F-12 | A flow item can be `killed` from any state. Killed items are archived, never deleted. | FlowStateMachine | P0 |
| BR-F-13 | A flow item can be `deferred` from any state except `running` and `shipped`. | FlowStateMachine | P1 |
| BR-F-14 | No flow item can transition backwards (e.g., `approved` → `enriched`). Only forward or kill/defer. | FlowStateMachine | P0 |

### ListReviewer (BR-L-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-L-01 | Batch selection with `Space` key. Visual checkbox indicator `[x]`. | ListReviewer | P0 |
| BR-L-02 | Batch action applies sequentially to all selected items. If one fails, continue with next. | ListReviewer | P0 |
| BR-L-03 | Progress persists to ShikkiDB (worker scope). Resume from last index on relaunch. | ListReviewer + ShikkiDB | P0 |
| BR-L-04 | Hybrid ordering: system proposes composite score, user pins override. Pins persist across sessions. | ListReviewer | P0 |
| BR-L-05 | Urgency colors are scoped per company. A maya P1 and a kintsugi P1 have independent urgency. | ListReviewer | P1 |
| BR-L-06 | Pipe mode: detect non-TTY (isatty). Output `--json` or `--count` instead of interactive TUI. | ListReviewer | P0 |
| BR-L-07 | Context popup: `?` key toggles tmux popup pane with event context. `Esc` or `?` to close. | ListReviewer | P1 |
| BR-L-08 | Action callback is async. Consumer handles the result. ListReviewer never blocks on action. | ListReviewer | P0 |

### Data Privacy (BR-P-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-P-01 | ShikkiDB has 3 scopes: worker (private), company (shared), global (system). | ShikkiDB Schema | P0 |
| BR-P-02 | Worker scope data is NEVER readable by company queries. Enforced at DB level (separate tables or row-level security). | ShikkiDB Schema | P0 |
| BR-P-03 | Reports auto-scope to recipient's company. `shikki report --company maya` shows only maya work. | ReportAggregator | P0 |
| BR-P-04 | Worker struggles (low output, high churn) visible ONLY to direct manager, never CODIR. | ReportAggregator | P0 |
| BR-P-05 | Personal Shikki data outside work hours is invisible to any company scope. | ShikkiDB Schema | P0 |
| BR-P-06 | Cross-company data leak is a P0 bug. A worker for Company A sees zero data from Company B. | ShikkiDB Schema | P0 |
| BR-P-07 | Event bus UUID: every event line includes 8-char UUID. Copy UUID to orchestrator retrieves full context. | EventLogger | P1 |

### Inbox & Review (BR-I-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-I-01 | `shikki review inbox` pipes all PRs from inbox to review pipeline. | InboxManager + ReviewPipeline | P0 |
| BR-I-02 | `shikki review 14..18` processes PRs 14, 15, 16, 17, 18 sequentially. | ReviewPipeline | P0 |
| BR-I-03 | `shikki review <N> \| bat` pipes PR diff to external tool. Stdout is the diff, not TUI. | ReviewPipeline | P0 |
| BR-I-04 | Review progress saves per-file state (reviewed/pending) to ShikkiDB. | ReviewPipeline | P0 |
| BR-I-05 | Validating a PR in review = validates the inbox item. Single action, two state changes. | InboxManager + ReviewPipeline | P0 |

### Ship (BR-S-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-S-01 | All 8 gates must pass for ship to succeed. No gate can be skipped (except `--dry-run`). | ShipService | P0 |
| BR-S-02 | VersionBump creates a git tag (`vX.Y.Z`) on the release commit. | ShipGate | P0 |
| BR-S-03 | `--dry-run` executes read-only commands but stubs writes. NOT all-stub (Bug from dogfood PR #37). | ShipService | P0 |
| BR-S-04 | Ship log requires mandatory `--why` field. No ship without a reason. | ShipCommand | P0 |
| BR-S-05 | ntfy notification on ship success or failure. | ShipService | P1 |

### Dispatch (BR-D-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-D-01 | Swift agents use `--scratch-path` per agent. Full parallelism, no serialization. | DispatchManager | P0 |
| BR-D-02 | `SKIP_E2E=1` enforced for all non-interactive agents. | DispatchManager | P0 |
| BR-D-03 | Max 6 agents per machine, max 2 per company. Budget enforced. | ConcurrencyGate | P0 |
| BR-D-04 | Agent crash: 1 retry with fresh worktree. Second crash → escalate to inbox. | DispatchManager | P0 |
| BR-D-05 | Agent timeout (>30min for quick, >2h for spec): no retry, escalate as scope problem. | DispatchManager | P1 |
| BR-D-06 | Worktree cleanup: merged worktrees deleted automatically. Orphans reaped after 4h TTL. | WorktreeManager | P1 |

### Spec (BR-SP-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-SP-01 | `shikki spec` is the #1 priority component. The first stone of Shikki. | SpecPipeline | P0 |
| BR-SP-02 | Spec output: `features/*.md` file + ShikkiDB plan record + inbox item for review. | SpecPipeline | P0 |
| BR-SP-03 | Spec accepts backlog item ID, `#N` shorthand, or free text. | SpecCommand | P0 |
| BR-SP-04 | Spec completion triggers inbox item automatically. No manual step. | SpecPipeline + InboxManager | P0 |
| BR-SP-05 | Multi-project: spec can target any company/project via `--company` flag. | SpecPipeline | P1 |

### Report (BR-R-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-R-01 | `shikki report --daily` and `--weekly` for personal auto-reports. | ReportAggregator | P0 |
| BR-R-02 | Reports include: LOC added/deleted (net), PRs merged, tasks completed, budget spent. | ReportAggregator | P0 |
| BR-R-03 | Historical reconstruction from ShikkiDB agent_events — reports available from day one. | ReportAggregator | P1 |
| BR-R-04 | CODIR mode: `shikki codir` shows project/team aggregates. No individual worker metrics. | ReportAggregator | P1 |
| BR-R-05 | Output formats: TUI table (default), markdown (`--md`), JSON (`--json`). | ReportCommand | P0 |

### Wizard (BR-W-*)

| BR | Rule | Component | Priority |
|----|------|-----------|----------|
| BR-W-01 | First-run detection: auto-launch wizard on bare `shikki` if no config exists. | WizardFlow | P0 |
| BR-W-02 | Every wizard level executes a REAL shikki command, not a simulation. | WizardFlow | P0 |
| BR-W-03 | Wizard saves progress. Resume from last level on relaunch. | WizardFlow | P0 |
| BR-W-04 | Environment setup (Docker, LLM, workspace) happens DURING the game, not before. | WizardFlow | P0 |
| BR-W-05 | `shikki wizard` is replayable — new features unlock new levels. | WizardFlow | P1 |

---

## Test-Driven Development Plan (TDDP)

### Testing Strategy

Every BR above is a test case. Implementation follows strict TDD:
1. Write failing test from BR
2. Implement minimum code to pass
3. Refactor
4. Run full suite

### Test Organization

```
Tests/ShikiCtlKitTests/
├── Flow/
│   ├── FlowStateMachineTests.swift          — BR-F-01 through BR-F-14 (14 tests)
│   ├── QuickFlowEscalationTests.swift       — BR-F-11 (3 tests: ≤3 files ok, >3 escalates, >30min escalates)
│   └── FlowTransitionIntegrationTests.swift — Full pipeline: raw→shipped (1 integration test)
├── ListReviewer/
│   ├── ListReviewerBatchTests.swift         — BR-L-01, BR-L-02 (5 tests)
│   ├── ListReviewerPersistenceTests.swift   — BR-L-03 (3 tests: save, resume, cross-session)
│   ├── ListReviewerOrderingTests.swift      — BR-L-04 (4 tests: composite score, pin override, manual mode)
│   ├── ListReviewerUrgencyTests.swift       — BR-L-05 (3 tests: per-company scoping)
│   ├── ListReviewerPipeModeTests.swift      — BR-L-06 (3 tests: json, count, non-tty detection)
│   └── ListReviewerContextPopupTests.swift  — BR-L-07 (2 tests: toggle open, toggle close)
├── Privacy/
│   ├── ScopeIsolationTests.swift            — BR-P-01 through BR-P-06 (6 tests)
│   └── ReportScopingTests.swift             — BR-P-03, BR-P-04 (4 tests: company filter, manager-only, no cross-company)
├── Inbox/
│   ├── InboxReviewPipingTests.swift         — BR-I-01 through BR-I-03 (5 tests)
│   ├── ReviewProgressTests.swift            — BR-I-04 (3 tests: per-file state, resume, completion)
│   └── InboxValidationTests.swift           — BR-I-05 (2 tests: review validates inbox item)
├── Ship/
│   ├── ShipGateTests.swift                  — BR-S-01 (8 tests: one per gate)
│   ├── ShipDryRunTests.swift                — BR-S-03 (3 tests: read-only executes, writes stub, not all-stub)
│   ├── ShipTagTests.swift                   — BR-S-02 (2 tests: tag created, tag format)
│   └── ShipLogTests.swift                   — BR-S-04 (2 tests: --why required, log persisted)
├── Dispatch/
│   ├── DispatchIsolationTests.swift         — BR-D-01, BR-D-02 (3 tests: scratch-path, skip-e2e, cache-path)
│   ├── DispatchConcurrencyTests.swift       — BR-D-03 (4 tests: max agents, max per-company, budget)
│   ├── DispatchFailureTests.swift           — BR-D-04, BR-D-05 (4 tests: retry, escalate, timeout)
│   └── WorktreeLifecycleTests.swift         — BR-D-06 (3 tests: cleanup merged, reap orphans, preserve active)
├── Spec/
│   ├── SpecPipelineTests.swift              — BR-SP-01 through BR-SP-05 (5 tests)
│   └── SpecOutputTests.swift                — BR-SP-02 (3 tests: file created, DB record, inbox item)
├── Report/
│   ├── ReportAggregationTests.swift         — BR-R-01, BR-R-02 (5 tests: daily, weekly, LOC, PRs, budget)
│   ├── ReportHistoryTests.swift             — BR-R-03 (2 tests: historical reconstruction, day-one data)
│   ├── CODIRReportTests.swift               — BR-R-04 (3 tests: aggregates only, no individual, project-level)
│   └── ReportFormatTests.swift              — BR-R-05 (3 tests: tui, markdown, json)
└── Wizard/
    ├── WizardFirstRunTests.swift            — BR-W-01 (2 tests: auto-detect, skip if configured)
    ├── WizardRealCommandTests.swift         — BR-W-02 (3 tests: backlog add executes, spec produces file)
    ├── WizardProgressTests.swift            — BR-W-03 (2 tests: save progress, resume)
    └── WizardEnvSetupTests.swift            — BR-W-04 (2 tests: docker during game, llm during game)
```

### Test Count Summary

| Category | BRs | Tests | Priority |
|----------|-----|-------|----------|
| Flow Lifecycle | 14 | 18 | P0 |
| ListReviewer | 8 | 20 | P0 |
| Privacy | 7 | 10 | P0 |
| Inbox & Review | 5 | 10 | P0 |
| Ship | 5 | 15 | P0 |
| Dispatch | 6 | 14 | P0 |
| Spec | 5 | 8 | P0 |
| Report | 5 | 13 | P0/P1 |
| Wizard | 5 | 9 | P0/P1 |
| **Total** | **60** | **117** | |

### Verification Checklist

Before claiming any component is "done":

- [ ] All BRs for the component have corresponding test files
- [ ] All tests are failing BEFORE implementation (TDD red phase)
- [ ] All tests pass AFTER implementation (TDD green phase)
- [ ] `SKIP_E2E=1 swift test` passes full suite with 0 regressions
- [ ] No `print()` in test files (feedback: kills parallel test speed)
- [ ] BR coverage report: every BR-* has at least one `@Test` with the BR ID in the test name
- [ ] ShikkiDB privacy: no worker-scope data exposed in company-scope queries (run scope isolation tests)
