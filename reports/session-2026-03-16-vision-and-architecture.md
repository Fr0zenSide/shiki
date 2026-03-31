# Shiki Session 2026-03-16 — Vision, Architecture & Implementation

> **Session**: `c914f0eb-5e2c-46df-89cf-61f1c03694f6` (55 user messages, 187KB)
> **Branch**: `feature/cli-core-architecture`
> **Status**: Session crashed at message 55 (ghost process self-kill via `shiki stop --force && shiki start`)

---

## Table of Contents

1. [Session Overview](#1-session-overview)
2. [What Was Built (v0.2.0)](#2-what-was-built-v020)
3. [Bugs Found & Fixed](#3-bugs-found--fixed)
4. [Bugs Found & NOT Fixed](#4-bugs-found--not-fixed)
5. [Product Vision](#5-product-vision)
6. [@shi Team Debates](#6-shi-team-debates)
7. [Architecture Decisions](#7-architecture-decisions)
8. [Entity Model](#8-entity-model)
9. [The Hard Truth — Scope Challenge](#8-the-hard-truth--scope-challenge)
10. [Concentric Product Circles](#9-concentric-product-circles)
11. [Phasing & Roadmap](#10-phasing--roadmap)
12. [Research & Ingests](#11-research--ingests)
13. [Unsaved Work & Uncommitted Code](#12-unsaved-work--uncommitted-code)
14. [Open Questions](#13-open-questions)

---

## 1. Session Overview

The session started with 7 work items from the user and evolved into a full product vision discussion. Timeline:

| Time | Activity |
|------|----------|
| Start | Fix `shiki start`, `shiki decide`, add restart/stop confirmation, /tdd process |
| Mid-session | CLI audit (all commands tested, 23→38 tests), smart startup, workspace detection |
| Late session | @shi team vision debate: multi-workspace, MDM, master/slave, knowledge commons |
| 17:22 | README rewritten (496→150 lines) |
| 17:27 | `shiki start` working with dashboard, heartbeat, 4 T1 decisions |
| 17:31 | User ran `shiki stop --force && shiki start` — killed the session |
| 17:56 | Heartbeat killed the board tab (bug). Ghost Claude processes survived (bug). |
| 17:56 | **Session died.** Last message: "I want you use /tdd and improve the stop/restart process" |

---

## 2. What Was Built (v0.2.0)

### New Commands & Features

| Feature | Details | Status |
|---------|---------|--------|
| **Bash → Swift migration** | 196-line bash wrapper → native Swift binary. 12 subcommands. | Done |
| **Smart startup** (`shiki start`) | 6-step: environment detection (Docker, Colima, LM Studio, backend), Docker bootstrap, data check, status display, tmux layout, auto-attach | Done |
| **Status display** | Box-drawing dashboard: session stats, git +/- lines, maturity indicator, weekly aggregate, pending decisions | Done |
| **Session stats** | Git diff stats between sessions. `~/.config/shiki/last-session` tracks timestamps. Weekly: +93,706 / -15,906 across 4 projects | Done |
| **Workspace auto-detect** | Resolves from binary symlink → known path → cwd | Done |
| **Dynamic session naming** | Tmux session = workspace folder name. Supports multiple workspaces side-by-side. | Done |
| **Status with workspace info** | `shiki status` shows workspace path + all detected shiki tmux sessions | Done |
| **`shiki decide` multiline** | Double-enter to submit. Pasted multiline text collected correctly. | Done |
| **`shiki stop`** | Confirmation prompt, `--force` flag, active window count | Done |
| **`shiki restart`** | Preserves tmux session, restarts heartbeat only (Ctrl-C + relaunch) | Done |
| **`shiki attach`** | Attach to running tmux session | Done |
| **`shiki heartbeat`** | Internal command — runs the orchestrator loop | Done |
| **Zsh autocompletion** | All 12 subcommands + flags. Auto-refreshes on `shiki start` when binary is newer. | Done |
| **`/tdd` skill** | Formalized bug-fix loop: test → plan → challenge → fix → retest → commit → PR → pre-pr → merge | Done |
| **Orchestrator split pane** | Top 80% = Claude session, Bottom 20% = heartbeat logs | Done |
| **Board tab layout** | Tab 2 for dispatched task windows | Done |
| **Research tab** | Tab 3 with 4 panes: INGEST/RADAR/EXPLORE/SCRATCH | Done |

### Tests

- **38 tests across 8 suites**, all green, zero warnings
- **23 original** + 15 new tests added during session

### Process Improvements

| Item | Details |
|------|---------|
| `/tdd` skill | `.claude/skills/shiki-process/tdd.md` — mandatory TDD loop for all changes |
| PR review offline | Generate `.md` file, don't burn tokens on interactive navigation |
| No silent workarounds | Never work around broken commands — TDD fix immediately |
| Context tracking | POST session events to Shiki DB `agent_events` table |

---

## 3. Bugs Found & Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| `shiki decide` eating multiline input | `readLine()` treats each pasted line as separate answer | Rewrote input to collect until empty line (double-enter) |
| `shiki stop` no confirmation | Direct `tmux kill-session` | Added confirmation prompt + `--force` flag |
| No `shiki restart` | Didn't exist | New command: Ctrl-C to orchestrator pane + relaunch heartbeat |
| HTTPClient `connectTimeout` | `AsyncHTTPClient` connection pool goes stale with Docker networking | **Replaced with curl subprocess** — no connection pool, reliable across Docker restarts |
| Task dispatched to wrong tmux session | `TmuxProcessLauncher` defaults to `session: "shiki-board"` but session renamed to `shiki` | Pass session name from startup through heartbeat to launcher |
| "board" tab killed by cleanup | `cleanupIdleSessions()` treated "board" as company session | Added "board" to `reservedWindows` set (was only "orchestrator" + "research") |
| Pane labels swapped | After `split-window`, pane indices unpredictable across tmux versions | Used explicit pane IDs instead of index guessing |
| Claude not launching in top pane | Targeted wrong pane after split | Captured pane ID before split, target explicitly |

---

## 4. Bugs Found & NOT Fixed

> These were discovered at the END of the session. The previous Claude was about to fix them via /tdd when it died.

### Bug 1: Ghost Claude Processes (CRITICAL)

**Problem**: When `shiki stop` runs `tmux kill-session`, child processes (Claude, xcodebuild, Simulator) survive as orphans. User reported: "I killed every shiki and detached all tmux and still I have a simulator running something."

**Evidence**: Orphaned PIDs found:
- Claude sub-agent (PID 72857) running `xcodebuild test` on Maya
- WabiSabi also running in Simulator (PID 61939)

**Planned fix** (never implemented):
1. Before killing tmux, capture all pane PIDs and their process trees
2. Kill task windows individually (SIGTERM → wait → SIGKILL)
3. Kill tmux session last
4. Handle self-kill when running from inside the session

### Bug 2: Companies Not Working After `shiki decide`

**Problem**: Companies dispatch tasks, Claude sub-agents ask T1 decisions, user answers via `shiki decide`, but:
- The session that asked the question may have died while waiting
- `checkStaleCompanies()` is **disabled** (line 42 of HeartbeatLoop.swift)
- No mechanism to re-dispatch after answered decisions unblock tasks

**Planned fix** (never implemented):
1. Re-enable `checkStaleCompanies` with smart logic (only relaunch if task was in-progress)
2. After `checkDecisions()`, detect newly-answered decisions → re-dispatch
3. Add session health monitoring (heartbeat FROM sub-agents, not just TO backend)

### Bug 3: Self-Kill via `shiki stop --force`

**Problem**: Running `shiki stop --force && shiki start` from inside the tmux session kills the caller. The `&&` chain means `shiki start` runs from the surviving login shell, but the Claude instance dies.

### Bug 4: Companies Can't Reach Backend (curl exit 28)

**Problem**: All company sub-agents timeout trying to reach `localhost:3900`. Visible in orchestrator logs as repeated "why send failed (curl exit 28)". May be related to tmux-spawned processes and Docker networking.

---

## 5. Product Vision

### Core Identity

**Shiki is a distributed workspace system for multi-users working on multi-projects through different companies, with AI-centric processes (Claude-augmented, provider-agnostic).**

It's not a project manager — it's a **Professional Operating System** for builders who think in code and work in terminal.

### The Graph, Not a Tree

The system is a **directed acyclic graph** with shared nodes:

```
DSKintsugi ──────→ C-Tech project
     │──────────→ Maya (FJ Studio)
     │──────────→ WabiSabi (OBYW.one)
     └──────────→ Games project

CoreKit ─────────→ ALL iOS projects across ALL workspaces

Memory "MapLibre" → referenced by any project that does maps
Research "/ingest bubbletea" → used by any project building TUIs
```

### Professional Topology (Real, Not Hypothetical)

| Workspace | Entity | Collaborators | Projects | Shared Resources |
|-----------|--------|---------------|----------|-----------------|
| **OBYW.one** | User's company | Solo | WabiSabi, Brainy, Flsh, landing pages | SPM packages, DSKintsugi |
| **FJ Studio** | Partnership | Faustin | Maya, edl, future sports/fitness apps | Maya, edl, future apps, SPM |
| **C-Tech / C-Media** | Collaboration | Magency coworker | TBD | DSKintsugi |
| **Games** | Personal+collab | Brother | TBD | TBD |

### Personal Scope (Non-Professional, Private)

- Photo management tool
- Home tech management
- Personal ideas that may become products
- Things built for self first, maybe sellable later

---

## 6. @shi Team Debates

### Debate 1: Multi-Workspace — Build Now or Later?

**Initial position** (@Sensei): Don't build now — you have one workspace.

**User's counter**: "I have 4 scopes with 3 collaborators. Building single-workspace Shiki is building for 25% of my life."

**@Sensei retracted**: "You win. 4 scopes, 3 collaborators — this is NOT hypothetical."

**Resolution**: Build multi-workspace now, phased approach.

### Debate 2: The MDM Vision — Real or Fantasy?

**User proposed**: Shiki as MDM-equivalent for dev teams. `shiki join --invite <token>` → full context from day 1.

**@Sensei initial**: Called it "fantasy" for real-time sync and AI agents as users.

**@Sensei retracted** after user's counter-argument (Master/Slave = Postgres replication + Git + tmux):
> "What I called 'fantasy' was actually just 'distributed Postgres + Git + tmux.' Every component exists. The innovation is the COMPOSITION."

**Resolution**: Architecture supports it from day 1. Build iteratively.

### Debate 3: --workspace Flag

**User**: "Do we even need `--workspace path`?"

**Resolution**: Drop path flag. Keep `-w slug` shorthand. Config file resolves paths. Default workspace = transparent, zero config.

### Debate 4: Config Format

**User**: "I see .yml, I want Apple pkl."

**@Sensei initially agreed** with pkl.

**Later research revealed**: pkl requires JVM runtime → dealbreaker for a tool built on native binaries.

**Resolution**: **pkl: NO GO**. Use JSON + Swift Codable (typed structs, no external runtime). `shiki config edit` opens in `$EDITOR`.

### Debate 5: Privacy Model

**@Kintsugi**: "What is private, stays private." Personal workspace NEVER syncs to any master.

**@Daimyo**: CODIR reports at team level, not user level. Consolidation = outcomes, not activity.

**Resolution**: Privacy by architecture. Separate DBs. Team-level reporting only.

### Debate 6: Auth Provider

| Provider | Language | Self-hosted | Device Flow | Verdict |
|----------|----------|-------------|-------------|---------|
| Descope | SaaS | No | Yes | **Rejected** (proprietary, data goes through their servers) |
| Hanko | Go | Yes | Yes (passkeys) | Backup choice |
| ZITADEL | Go | Yes | Yes (native) | **Primary choice** (RBAC, Go, Apache 2.0) |
| authentik | Python | Yes | Yes | Too heavy |
| Keycloak | Java | Yes | Yes | Way too heavy |

### Debate 7: AI Provider Lock-in

**@Ronin**: Shiki must be AI provider agnostic. Claude is mastermind orchestrator today, but sub-agents can be any provider.

```swift
protocol AgentProvider {
    func execute(prompt: String, context: AgentContext) async throws -> AgentResponse
    var name: String { get }
    var costPerToken: Double { get }
}
```

**Resolution**: Each workspace can have a DIFFERENT AI provider. Company or user pays.

---

## 7. Architecture Decisions

### Master/Slave Distributed Architecture

```
┌─────────────────────────────────────────────────┐
│           COMPANY VPS / Cloud Server             │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │        Shiki Master (the brain)              │ │
│  │  - Full knowledge DB                        │ │
│  │  - All workspaces, all companies            │ │
│  │  - ACL per user, per team                   │ │
│  │  - Weekly consolidation → CODIR reports     │ │
│  │  - AI orchestrator (the expensive one)      │ │
│  └──────────┬──────────────────────────────────┘ │
│             │ sync API                            │
└─────────────┼────────────────────────────────────┘
              │
    ┌─────────┼─────────┬──────────────┐
    │         │         │              │
┌───▼───┐ ┌──▼────┐ ┌──▼────┐  ┌─────▼──────┐
│Dev A  │ │Dev B  │ │Dev C  │  │Contractor  │
│(local)│ │(local)│ │(local)│  │(cloud/mosh)│
│Shiki  │ │Shiki  │ │Shiki  │  │Shiki       │
│Slave  │ │Slave  │ │Slave  │  │Sandboxed   │
│Team A │ │Team A │ │Team B │  │Time-limited│
│scope  │ │scope  │ │scope  │  │Audit only  │
│+personal│+personal│+personal│ │No personal │
│workspace│workspace│workspace│ │workspace   │
└────────┘└────────┘└────────┘ └────────────┘
```

**What already exists today:**
- Git for code sync → already works
- Postgres with RLS for scoped data → standard feature
- mosh + tmux for cloud sessions → already used
- Master/slave DB sync → logical replication in Postgres
- Scoped tokens → OAuth device flow (Hanko, ZITADEL)
- Time-limited sandbox access → invite token + expiry

### Entity Model

```
User Identity
├── Private Layer (invisible to everyone)
│   ├── Personal workspace (my side projects)
│   ├── Full Knowledge Commons (memories, research, radar)
│   └── Cross-workspace insights
│
├── Professional Layer(s) (visible to team)
│   ├── Company A workspace (scoped)
│   ├── Company B workspace (scoped — freelancer)
│   └── Contractor gig workspace (sandboxed, temporary)
│
└── Shiki itself
    ├── Local slave (my machine)
    └── Connected master(s) (company VPS(es))
```

### Three Layers That Must Be Separate

| Layer | Contains | Storage | Shared? |
|-------|----------|---------|---------|
| **Knowledge Commons** | Memories, /ingest, /radar, skills, process | Local Postgres (your machine) | NEVER directly. Read-only projections to collaborators. |
| **Shared Infrastructure** | SPM packages, DSKintsugi, CI/CD templates | Git repos | Via Git (already works) |
| **Workspace Data** | Companies, tasks, decisions, transcripts | Per-workspace DB (local for solo, remote for collab) | With workspace collaborators |

### Progressive Disclosure as Architecture

- **Level 0 (solo)**: `shiki start`. One workspace, no ACL. Works today.
- **Level 1 (multi-project)**: `shiki workspace add`. Unlocks multi-workspace.
- **Level 2 (collaborators)**: `shiki invite`. Unlocks ACL, vault, knowledge projections.
- **Level 3 (platform)**: `shiki admin`. Unlocks full MDM capabilities.

Each level is opt-in. Help text changes based on activated features.

### Knowledge Sharing Model

Collaborators don't access your workspace. They access **knowledge projections**:

- **Data level**: Here are the tasks. Do them.
- **Knowledge level**: Tasks + why they exist + patterns to follow.
- **Wisdom level**: Full philosophy (only you have this).

Collaborators get Knowledge. AI agents operate at Knowledge level with Wisdom as system prompt.

### Security

- **Vault**: `age` encryption (not GPG), per-workspace keys
- **Key hierarchy**: Master key → Workspace key → User key → Session key
- **Invite tokens**: One-time use, time-limited, workspace-scoped
- **Contractor sandbox**: mosh session on server, code never leaves, self-destructs on expiry
- **Separate DB per collaborative workspace** (@Ronin recommendation)

### Thin Client Vision

iPad + Blink Shell + mosh → tmux session on powerful server. Or MacBook Air + Mac Studio server. The expensive compute (AI orchestrator) runs on the server. The lightweight client just connects.

### Business Model (To Be Studied)

| Tier | Target | Features |
|------|--------|----------|
| **Free** | Solo dev | 1 workspace, local only |
| **Pro** ($20/mo) | Freelancers | Multi-workspace, backup, idea inbox |
| **Team** ($15/user/mo) | Dev teams | Collaborators, vault, knowledge projections, `shiki join` |
| **Enterprise** | Companies | Self-hosted master, SSO, audit logs, CODIR reports |

---

## 8. The Hard Truth — Scope Challenge

The @shi team unanimously supported the vision, but challenged @Daimyo hard on **sequencing**:

### @Sensei's Retraction

@Sensei initially pushed back: "Don't build multi-workspace yet. You have ONE workspace." Then @Daimyo listed 4 real scopes, 3 real collaborators, shared infrastructure crossing all of them. @Sensei's response:

> "You win. I withdraw my 'don't build it now' recommendation. [...] That's 4 scopes with 3 different collaborators and shared infrastructure that crosses all of them. This is NOT hypothetical — this is your actual professional topology today. Building single-workspace shiki is building a tool for 25% of your life."

And later, when @Daimyo reduced the "fantasy" to engineering:

> "What I called 'fantasy' was actually just 'distributed Postgres + Git + tmux.' Every component exists. The innovation is the COMPOSITION — putting them together into a coherent developer experience. I retract. This is buildable."

### @Kintsugi's Naming Insight

> "Shiki means 'four seasons' — it was ALWAYS meant to hold multiple cycles. The name 四季 literally means the four seasons coexisting in one system. One year contains spring, summer, autumn, winter — each distinct, each beautiful, all part of one whole. Your four workspaces ARE the four seasons."

And the philosophical framing that shaped the architecture:

> "Shared roots, separate branches. Like a tree. The packages are the roots. The workspaces are the branches. The design system is the trunk. You don't plant four trees — you grow one tree with four branches."

On knowledge sharing levels:
> "Collaborators get Knowledge. Only you have Wisdom. AI agents can operate at Knowledge level with your Wisdom as system prompt."

### @Shogun's Market Timing

> "Ship fast, get Faustin using it, iterate. [...] The killer feature isn't the project management — it's the context transfer. New dev joins → Claude already knows the codebase, the decisions, the patterns, the why behind everything."

But also the hard pushback:
> "You have 0 users outside yourself. Building a platform before having 10 happy solo users is a mistake. Ship the solo experience first, make it excellent, THEN add collaboration."

### @Hanami's Complexity Budget

Progressive disclosure as architecture — the answer to "this is too complex":
> "Every feature you add for power users makes it harder for new users to understand the system. If a new user types `shiki --help` and sees 30 subcommands, they close the terminal."

Solution: each level is opt-in. Help text literally changes based on what features are activated. Solo users never see workspace commands. Workspace users never see platform commands.

### The Synthesis — Three Products in One

The team challenged @Daimyo: **you are designing three products at once.** Each is real. Each serves a different market. Don't build them as a monolith — build them as **concentric circles** where each layer is a complete product:

- **Inner circle (NOW)**: Shiki Solo — what works today, make it excellent
- **Middle circle (2-3 months)**: Shiki Workspaces — multi-scope, knowledge graph
- **Outer circle (6+ months)**: Shiki Platform — MDM, vault, teams, cloud

The architecture SUPPORTS all three from day 1. The code only IMPLEMENTS the inner circle now. The key constraint:

> "You can't sell a platform you don't use yourself first."

## 9. Concentric Product Circles

```
        ┌─────────────────────────┐
        │    Shiki Platform       │  ← Phase 3 (6+ months)
        │   MDM, vault, teams     │
        │  ┌───────────────────┐  │
        │  │ Shiki Workspaces  │  │  ← Phase 2 (2-3 months)
        │  │  multi-scope,     │  │
        │  │  knowledge graph  │  │
        │  │ ┌───────────────┐ │  │
        │  │ │  Shiki Solo   │ │  │  ← Phase 1 (NOW — v0.2.0)
        │  │ │  what works   │ │  │
        │  │ │  today        │ │  │
        │  │ └───────────────┘ │  │
        │  └───────────────────┘  │
        └─────────────────────────┘
```

Each circle is a **complete product** at its level. Solo users never see Workspace features. Workspace users never see Platform features.

---

## 10. Phasing & Roadmap

### Immediate (v0.2.0 Release)

| # | Task | Status |
|---|------|--------|
| 1 | Fix ghost process cleanup in `shiki stop` | **NOT DONE** (session crashed) |
| 2 | Re-enable `checkStaleCompanies` with smart logic | **NOT DONE** |
| 3 | Decision-unblock → re-dispatch flow | **NOT DONE** |
| 4 | Session health monitoring (orchestrator as real manager) | **NOT DONE** |
| 5 | Commit all uncommitted work (36 files) | **NOT DONE** |
| 12 | README rewrite | Done (in working tree, uncommitted) |
| 13 | Batch PR review + release | Not started |
| 14 | LICENSE + business model study | Not started |

### Post-Release

1. `/md-feature "shiki-workspaces"` — design the full data model
2. `shiki wizard` — onboarding for new users
3. Get Faustin on board (30-day target from 2026-03-16)

### Full Phasing

| Phase | What | When |
|-------|------|------|
| **0** | Ship v0.2.0 (solo experience) | NOW |
| **1** | Workspace registry + JSON config + `workspace add/list/switch` | Next sprint |
| **2** | Knowledge Commons separation | After Phase 1 |
| **3** | Idea Inbox | After Phase 2 |
| **4** | Backup per workspace | After Phase 3 |
| **5** | Collaborator access (ZITADEL auth + sync) | When needed |
| **6** | License + business model | After Phase 5 |
| **7** | Platform features (CODIR, cloud workstations) | 6+ months |

---

## 11. Research & Ingests

### Ingested During Session (Research Lab DB)

| Source | Chunks | Categories |
|--------|--------|------------|
| gh-dash (GitHub repo) | 11 | overview, architecture, api, security |
| gh-dash (website) | 1 | product |
| diffnav (GitHub repo) | 7 | overview, features, installation, config, keybindings, architecture |
| diffnav (website) | 7 | overview, features, install, config, keybindings, architecture |
| bubbletea (GitHub repo) | 18 | architecture, api, patterns, ecosystem, migration |
| VHS (GitHub repo) | 18 | architecture, api, testing, patterns, dependencies |
| Blink Shell (GitHub repo) | 11 | overview, architecture, api, security |
| Blink Shell (website) | 1 | product |
| Blink Shell (GitHub org) | 3 | overview, architecture |
| Hanko (auth) | Ingested | architecture, auth |
| pkl (Apple) | Ingested | config, language |
| authentik | Ingested | auth |
| ZITADEL | Ingested | auth |

### Radar Watchlist Added

| Item | Tags | Status |
|------|------|--------|
| gh-dash | tui, github, dashboard | Watching |
| diffnav | tui, git, diff | Watching |
| Bubble Tea | tui, go, framework | Watching |
| VHS | tui, testing, recording | Watching |
| Blink Shell | terminal, ios, mosh, ssh | Watching |
| pkl | config, apple, type-safe | **NO GO** (JVM dependency) |
| Hanko | auth, go, passkeys | Watching (backup to ZITADEL) |
| ZITADEL | auth, go, rbac, device-flow | **Primary choice** |

---

## 12. Unsaved Work & Uncommitted Code

### Modified Files (on `feature/cli-core-architecture`)

| File | Changes |
|------|---------|
| `README.md` | Full rewrite (496→~150 lines) |
| `scripts/shiki` | Added restart subcommand, improved stop |
| `Package.swift` | Dependency changes |
| `Package.resolved` | Updated |
| `BackendClient.swift` | AsyncHTTPClient → curl subprocess |
| `CompanyLauncher.swift` | Added "board" to reserved windows, fixed pane IDs, session name passthrough |
| `HeartbeatLoop.swift` | Session name parameter, disabled stale company check |
| `NotificationService.swift` | Updated |
| `DecideCommand.swift` | Multiline input (double-enter to submit) |
| `StartCommand.swift` | **DELETED** (replaced by StartupCommand) |
| `StatusCommand.swift` | Added workspace + session detection |
| `ShikiCtl.swift` | New command registration |
| `CommandParsingTests.swift` | Updated for new commands |

### New Untracked Files

| File | Purpose |
|------|---------|
| `StartupCommand.swift` | Smart 6-step startup with env detection |
| `StopCommand.swift` | Confirmation prompt, force flag |
| `RestartCommand.swift` | Preserves session, restarts heartbeat |
| `AttachCommand.swift` | Attach to tmux session |
| `HeartbeatCommand.swift` | Internal orchestrator loop command |
| `EnvironmentDetector.swift` | Docker, Colima, LM Studio, backend detection |
| `SessionStats.swift` | Git diff stats between sessions |
| `StartupRenderer.swift` | Dashboard box-drawing renderer |
| `BackendClientConnectionTests.swift` | New tests |
| `EnvironmentDetectorTests.swift` | New tests |
| `SessionStatsTests.swift` | New tests |
| `StartupRendererTests.swift` | New tests |

### Commit Plan (from session, never executed)

```
feat(shiki): migrate CLI from bash to Swift v0.2.0
feat(shiki): smart startup with env detection + status display
feat(shiki): add stop/restart/attach commands
feat(shiki): decide multiline input
feat(shiki): zsh autocompletion + install script
feat(process): add /tdd skill
docs: rewrite README for v0.2.0
```

---

## 13. Open Questions

1. **Ghost process cleanup**: How to kill Claude sub-processes without self-killing?
2. **Companies not resuming**: After `shiki decide`, how does the orchestrator detect answered decisions and re-dispatch?
3. **curl exit 28**: Why do sub-Claude agents timeout on localhost:3900?
4. **Orchestrator as manager**: How to track sub-agent health (heartbeats FROM agents, PID tracking)?
5. **LICENSE**: What license for Shiki? Open source vs source-available vs commercial?
6. **Faustin onboarding**: 30-day target — what's the minimal viable workspace for FJ Studio?

---

## Appendix: Key Quotes from @Daimyo

> "It represent a full mental projection of my professional life and it's messy a lot inside my mind so let's clean that and make me to never see back in the past for search a better alternative way to work."

> "What is private, stays private."

> "Today we need a computer and share credentials + git repo for a new comer, tomorrow with shiki, we add a new users to our db with the right acl and he can directly start."

> "The ai gonna be a part we run as a sub agent scope, only the orchestrator need a real power, because it's him manage the overview of all sub agents."

---

*Document generated from session transcript `c914f0eb-5e2c-46df-89cf-61f1c03694f6` on 2026-03-16.*
*Full session text saved at `/tmp/shiki-vision-session-full.md` (187KB, 55 user messages).*
