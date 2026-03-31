# Shikki Flow — Current State vs Vision

> Generated: 2026-03-21 | Source: session analysis + roadmap + thesis

---

## 1. Current State (v0.2.0 — what works TODAY)

```
┌─────────────────────────────────────────────────────────────┐
│                    @Daimyo (User)                            │
│                                                             │
│  "Add animations to Maya and WabiSabi"                      │
│  "Fix the pipe deadlock"                                    │
│  "Review PR #13"                                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Claude Code (Single Session)                    │
│                                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐      │
│  │ MEMORY.md   │  │ .claude/     │  │ ShikkiDB      │      │
│  │ (flat file) │  │ skills/      │  │ (curl/MCP)    │      │
│  └──────┬──────┘  │ commands/    │  └───────┬───────┘      │
│         │         └──────┬───────┘          │              │
│         └────────────────┼──────────────────┘              │
│                          ▼                                  │
│  ┌───────────────────────────────────────────┐              │
│  │         Single Context Window             │              │
│  │                                           │              │
│  │  Read code → Write code → Run tests       │              │
│  │  Spawn subagent (worktree) ──┐            │              │
│  │  Spawn subagent (worktree) ──┤            │              │
│  │  Spawn subagent (worktree) ──┘            │              │
│  │         ↑ all share same context budget    │              │
│  └───────────────────────────────────────────┘              │
│                          │                                  │
│  ┌───────────────────────▼───────────────────┐              │
│  │              Output                       │              │
│  │  • git commit/push                        │              │
│  │  • gh pr create                           │              │
│  │  • ShikkiDB events (curl/MCP)             │              │
│  │  • Terminal output                        │              │
│  └───────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘

tmux status bar:
┌────────┬────────┬────────┬──────────┬──────────┬──────────┐
│ shikki │ orch.  │  CPU   │   RAM    │ Q:0 $0/31│  +1 ?53  │
└────────┴────────┴────────┴──────────┴──────────┴──────────┘
```

### What works
- `/spec` → 8-phase feature pipeline
- `/pre-pr` → 9-gate quality pipeline with @shi team
- `/review` → interactive PR review
- `/ship` → 8-gate release pipeline (dry-run only so far)
- `shikki session pause/resume` → checkpoint to JSON + ShikkiDB
- `shikki status --mini/--project/--git` → tmux segments
- `shikki pr N | jq/delta` → JSON pipe
- ShikkiMCP → 11 typed tools for DB (replaces curl)
- ShikiCore → lifecycle FSM, PipelineRunner, BudgetEnforcer
- Subagent dispatch → worktrees for parallel work
- @Ronin v2 → ✗⚡~◐✓ adversarial review
- Memory + ShikkiDB → cross-session persistence

### What's broken / missing
- ❌ Subagents share the SAME context window budget
- ❌ No real multi-process orchestration (subagents are threads, not processes)
- ❌ No real-time event stream from sub-agents (they complete, then report)
- ❌ Session resume outputs text but doesn't LAUNCH anything
- ❌ Budget display is placeholder ($0), not real API spend
- ❌ No animated splash screen
- ❌ No personality persistence (memory files approximate it)
- ❌ One tmux window, but no dynamic pane management
- ❌ Can't dispatch agents into DIFFERENT project directories as separate Claude processes

---

## 2. Next Milestone (v1.0 — what we're building NOW)

```
┌─────────────────────────────────────────────────────────────┐
│                    @Daimyo (User)                            │
│                                                             │
│  "Add animations to Maya and WabiSabi"                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│           Shikki Orchestrator (Main Claude)                  │
│                                                             │
│  ┌────────────────────────────────────────────┐             │
│  │  1. UNDERSTAND intent                      │             │
│  │  2. SCOPE → 2 projects, parallel           │             │
│  │  3. PLAN → 2 epic branches, 10 animations  │             │
│  │  4. PRESENT → one-shot validation          │             │
│  └─────────────────┬──────────────────────────┘             │
│                    │ @Daimyo validates                       │
│                    ▼                                         │
│  ┌────────────────────────────────────────────┐             │
│  │  5. DISPATCH (parallel)                    │             │
│  │                                            │             │
│  │  ┌──────────────┐    ┌──────────────┐      │             │
│  │  │ Sub-Agent A  │    │ Sub-Agent B  │      │             │
│  │  │ Maya         │    │ WabiSabi     │      │             │
│  │  │ (worktree)   │    │ (worktree)   │      │             │
│  │  │              │    │              │      │             │
│  │  │ epic/maya-   │    │ epic/wabi-   │      │             │
│  │  │ animations   │    │ animations   │      │             │
│  │  └──────┬───────┘    └──────┬───────┘      │             │
│  │         │                   │              │             │
│  │         ▼                   ▼              │             │
│  │    ShikkiDB ◄──────────────────────────►   │             │
│  │    (event stream)                          │             │
│  └────────────────────────────────────────────┘             │
│                    │                                         │
│  ┌─────────────────▼──────────────────────────┐             │
│  │  6. MONITOR (ShikkiDB event loop)          │             │
│  │     task_started ✓                          │             │
│  │     test_passed (15/23) ██████░░ 65%        │             │
│  │     test_passed (29/29) ████████ 100% ✓     │             │
│  │     pr_created #19 (WabiSabi) ✓             │             │
│  │     test_passed (23/23) ████████ 100% ✓     │             │
│  │     pr_created #20 (Maya) ✓                 │             │
│  └─────────────────┬──────────────────────────┘             │
│                    │                                         │
│  ┌─────────────────▼──────────────────────────┐             │
│  │  7. COLLECT                                │             │
│  │     /pre-pr --autofix on epic/maya-anim     │             │
│  │     /pre-pr --autofix on epic/wabi-anim     │             │
│  │                                            │             │
│  │  8. REPORT to @Daimyo                      │             │
│  │     "2 PRs ready: #19 (WabiSabi), #20      │             │
│  │      (Maya). 52 tests green. Review?"       │             │
│  └────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘

tmux (ONE window, dynamic panes):
┌─────────────────────────────────────────────────────────────┐
│  Orchestrator (main pane)                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Shikki Orchestrator — 2 agents active                  │ │
│  │ Maya:     ██████░░ 65% (15/23 tests)                   │ │
│  │ WabiSabi: ████████ 100% ✓ PR #19 created               │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────┬─────────────────────────────────┐ │
│  │ Agent A (Maya)       │ Agent B (WabiSabi)              │ │
│  │ Building Wave 3...   │ ✓ Complete                      │ │
│  └──────────────────────┴─────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│ CPU 6% │ RAM 34GB │◀Q:0 $12/$31│◀Swift 6.2│◀+1 !2 ≡7     │
└─────────────────────────────────────────────────────────────┘
```

### What v1.0 adds
- ✅ Orchestrator DNA (the 8-step loop)
- ✅ Sub-agent dispatch into project directories
- ✅ ShikkiDB event stream for monitoring
- ✅ /pre-pr --autofix on epic branches
- ✅ `shikki session resume` actually LAUNCHES (not just text)
- ✅ Real budget tracking (per provider)
- ✅ Scoped testing (TPDD — run only relevant tests)
- ✅ Epic branching (scope container for multi-wave work)
- ✅ SUI Video API for animation/E2E visual QA

### What's still missing at v1.0
- ❌ Sub-agents are still worktree subprocesses, not separate Claude processes
- ❌ No real-time streaming (poll ShikkiDB, not stream)
- ❌ No animated splash screen
- ❌ No personality evolution (memory files, not ML)
- ❌ No physical device

---

## 3. Vision (v2.0+ — The Jarvis)

```
┌─────────────────────────────────────────────────────────────┐
│                    @Daimyo (anywhere)                        │
│                                                             │
│  iPhone / Apple Watch / tvOS / Terminal / Future Device      │
│                                                             │
│  "Build the onboarding for the new app"                     │
│  [ntfy push] [Shikki iOS app] [voice via Flsh]              │
└──────────────────────┬──────────────────────────────────────┘
                       │ shikki push (universal input)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                 Shikki Core (The Brain)                      │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │Lifecycle │  │Company   │  │Budget    │  │Crash       │  │
│  │FSM       │  │Manager   │  │Enforcer  │  │Recovery    │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘  │
│       └──────────────┼──────────────┼─────────────┘         │
│                      ▼                                      │
│  ┌───────────────────────────────────────────┐              │
│  │         Decision Engine                   │              │
│  │                                           │              │
│  │  • Reads @Daimyo's rhythm (ShikkiDB)      │              │
│  │  • Checks budget across providers         │              │
│  │  • Evaluates priority (roadmap)           │              │
│  │  • Routes to best provider:               │              │
│  │    Claude / OpenRouter / Local MLX         │              │
│  │  • Knows when NOT to work                 │              │
│  │    ("commit quality ↓ since hour 10")     │              │
│  └───────────────────┬───────────────────────┘              │
│                      ▼                                      │
│  ┌───────────────────────────────────────────┐              │
│  │        Multi-Agent Dispatcher             │              │
│  │                                           │              │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐        │              │
│  │  │ Ag1 │ │ Ag2 │ │ Ag3 │ │ Ag4 │        │              │
│  │  │Maya │ │Wabi │ │Flsh │ │Infra│        │              │
│  │  │     │ │Sabi │ │     │ │     │        │              │
│  │  │Claude│ │Open │ │Local│ │Claude│       │              │
│  │  │     │ │Route│ │MLX  │ │     │        │              │
│  │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘        │              │
│  │     │       │       │       │            │              │
│  │     ▼       ▼       ▼       ▼            │              │
│  │  ┌───────────────────────────────┐       │              │
│  │  │     Event Bus (real-time)     │       │              │
│  │  │  ShikkiDB ← events stream    │       │              │
│  │  │  ntfy → iPhone/Watch push     │       │              │
│  │  │  tmux → status bar update     │       │              │
│  │  │  Shikki iOS → live dashboard  │       │              │
│  │  └───────────────────────────────┘       │              │
│  └───────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  The Vault (Personal)                        │
│                                                             │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐    │
│  │ ShikkiDB   │  │ Personality│  │ Session History     │    │
│  │ (events,   │  │ (evolving  │  │ (every decision,   │    │
│  │  decisions,│  │  tone,     │  │  every session,     │    │
│  │  plans)    │  │  reflexes, │  │  every checkpoint)  │    │
│  │            │  │  rhythm)   │  │                     │    │
│  └────────────┘  └────────────┘  └────────────────────┘    │
│                                                             │
│  🔐 Encrypted at rest. User-owned keys. Zero-knowledge.    │
│  📱 Syncs to Shikki iOS app (local-first, opt-in cloud).   │
│  🧠 Personality emerges from work, not from a prompt.       │
└─────────────────────────────────────────────────────────────┘

Surfaces:
┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐
│   Terminal   │ │  iOS App    │ │ Apple Watch │ │  tvOS     │
│   (tmux)     │ │  (monitor)  │ │ (ntfy+quick)│ │ (dashboard│
│              │ │             │ │             │ │  monitor) │
│ • status bar │ │ • dashboard │ │ • approve   │ │ • company │
│ • search     │ │ • review    │ │ • nudge     │ │   status  │
│ • tooltip    │ │ • vault     │ │ • break     │ │ • event   │
│ • splash     │ │ • spend     │ │   reminder  │ │   stream  │
└─────────────┘ └─────────────┘ └─────────────┘ └───────────┘
```

### What v2.0 adds
- ✅ True multi-process agents (separate Claude sessions, not worktrees)
- ✅ Real-time event streaming (WebSocket, not polling)
- ✅ Multi-provider routing (Claude for complex, OpenRouter for fast, MLX for private)
- ✅ Personality evolution (behavioral observations → tone persistence)
- ✅ Productivity insights ("commit quality ↓, take a break" — data, not advice)
- ✅ Native iOS app (dashboard, vault, review)
- ✅ Apple Watch (approve/deny, break reminders, quick input via Flsh)
- ✅ tvOS (monitoring dashboard — cheap display)
- ✅ `shikki push` (universal input from any device)
- ✅ Animated splash screen (terminal art + session resume)
- ✅ Encrypted vault (user-owned keys, zero-knowledge)

### What v2.0 does NOT do
- ❌ No physical device yet (software proves the relationship first)
- ❌ No team/enterprise features (v3.0 — ShikkiWS)
- ❌ No ML-based personality (rule-based observations for now)

---

## 4. The Gap — What Bridges v0.2 to v1.0

```
TODAY (v0.2)                          v1.0 TARGET
────────────                          ──────────

Subagent worktrees ─────────────────► Sub-agent dispatch protocol
(same context budget)                 (separate contexts, ShikkiDB events)

Memory files ───────────────────────► Personality.md (append-only)
(facts only)                          (behavioral observations)

shikki session pause ───────────────► Auto-save on exit
(manual, text output)                 (auto-load on start, launches tmux)

$0/$31 placeholder ─────────────────► Real spend per provider
                                      (AgentProvider.currentSessionSpend)

3 tmux windows ─────────────────────► 1 window, dynamic panes
(resurrect legacy)                    (orchestrator manages layout)

/pre-pr manual ─────────────────────► /pre-pr --autofix
                                      (auto-fix + re-run, human reviews result)

Scoped tests (concept) ────────────► TestScope on WaveNode
                                      (enforced, validated, counted)

Epic branches (concept) ───────────► epic/ branches in git flow
                                      (PRGate accepts, changelog scoped)

5 feature specs ────────────────────► Orchestrator DNA
(process docs)                        (compiled behavior in ShikkiCore)
```

---

## 5. The Moat Evolution

```
v0.2 Moat: "I have skills and memory files"
           (anyone can copy .claude/skills/)

v1.0 Moat: "I have an orchestration engine + event persistence"
           (harder to copy — compiled Swift + ShikkiDB)

v2.0 Moat: "I know YOUR rhythm, YOUR decisions, YOUR projects"
           (impossible to copy — the data is personal)

v3.0 Moat: "I run your company's engineering org"
           (enterprise lock-in — teams depend on the relationship)
```

Each version's moat makes the next version's moat possible.
Skills → Engine → Relationship → Organization.

The competitors are stuck at v0.2 (skills/templates).
We're building v1.0 (engine).
The thesis is v2.0 (relationship).
The business is v3.0 (organization).

Nobody else is thinking past v0.2 right now.
