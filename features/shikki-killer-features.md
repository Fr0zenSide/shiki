# Feature: Shikki Killer Features — Closing the Competitive Gap

> **Type**: /spec (multi-feature)
> **Priority**: P0.5 (Dashboard), P1 (Init), P2 (Marketplace)
> **Status**: Spec — validated by @Daimyo 2026-03-21
> **Depends on**: ShikiCore (P0), Event Bus (DONE), ShikiKit (DONE), ShikiMCP (P0)
> **Branch**: `feature/killer-features` from `develop`

---

## Competitive Landscape

| Capability | CrewAI (44K stars) | LangGraph | Claude Agent SDK | **Shikki** |
|---|---|---|---|---|
| Web dashboard | Yes (React) | LangSmith | Workbench | **No** -> Feature 1 |
| Project bootstrap | `crewai init` | Templates | N/A | **No** -> Feature 2 |
| Template marketplace | CrewAI Templates Hub | LangChain Hub | N/A | **No** -> Feature 3 |
| Compiled protocols | No (Python) | No (Python) | No (TS) | **Yes (Swift)** |
| Git-flow integration | No | No | No | **Yes (9-gate)** |
| Provider-agnostic | Partial | OpenAI-leaning | Claude-only | **Yes (protocol)** |
| Budget enforcement | No | No | No | **Yes (BudgetEnforcer)** |
| Personality persistence | No | No | No | **Yes (ShikiDB)** |
| CLI-first tmux | No | No | No | **Yes** |

**Their advantage**: ecosystem breadth, web UIs, template sharing.
**Our advantage**: compiled correctness, git-native workflow, observable event stream, CLI performance.

These 3 features neutralize their advantages while keeping ours intact.

---

# Feature 1: Reactive Tmux Dashboard

> **Priority**: P0.5 — first thing users see, first impression
> **LOC estimate**: ~620 LOC production + ~180 LOC tests
> **Depends on**: Event Bus (DONE), SessionRegistry (DONE), ShikiMCP

## 1.1 Problem

CrewAI has a React dashboard. LangGraph has LangSmith. Shikki has `shikki status` — a static snapshot. Users cannot watch agents work in real time. No progress bars, no budget gauge, no event stream. The orchestrator feels blind.

## 1.2 Solution

`shikki dashboard` — a reactive tmux TUI that renders the full system state, auto-refreshing from ShikiDB events. Not a web app. Not Electron. A 2ms-render ANSI terminal that lives where the user lives.

### Layout

```
+-----------------------------------------------------------+
|  SHIKKI DASHBOARD                            v1.0.0       |
+---------------------------+-------------------------------+
|                           |                               |
|  Orchestrator             |  Agent A (Maya)               |
|  Main Claude session      |  ██████░░ 65% (15/23)         |
|  > waiting for input      |  Building Wave 3...           |
|                           |                               |
|                           +-------------------------------+
|                           |  Agent B (WabiSabi)           |
|                           |  ████████ 100% DONE           |
|                           |  PR #24 created               |
|                           +-------------------------------+
|                           |  Agent C (ShikiCore)          |
|                           |  ░░░░░░░░ QUEUED              |
|                           |  Waiting for A + B            |
+---------------------------+-------------------------------+
|  Events: task_started(A) -> test_passed(B,29/29) -> ...  |
|  Budget: $12.40/$31.00 (40%)  |  Tests: 134 green        |
|  Branch: epic/shikki-v1       |  PRs: 2 open             |
+-----------------------------------------------------------+
```

### Key Differentiators vs Web Dashboards

1. **Zero infrastructure** — no Docker, no browser, no port forwarding. Just tmux.
2. **Keyboard-driven** — `j/k` scroll agents, `Enter` opens pane, `q` quits. Emacs bindings via config.
3. **Event-native** — renders directly from ShikiEvent stream, not REST polling.
4. **Budget-aware** — real-time spend tracking with color thresholds.
5. **Git-integrated** — branch, PR status, test counts from live data.

## 1.3 S3 Spec (TPDD)

```s3
When the dashboard renders with 2 active agents:
  -> shows both agents with progress bars
  -> budget displays real spend from BudgetEnforcer
  -> event stream shows last 5 events

When the dashboard renders with 0 agents:
  -> shows "No active sessions" in agent panel
  -> orchestrator panel shows idle state

When an agent completes its task:
  -> status changes from progress bar to DONE
  -> PR link appears if PR was created
  -> event stream appends task_completed event

When an agent errors:
  -> status changes to ERROR (red)
  -> last error message shown inline
  -> event stream appends agent_error event

When budget exceeds 80% of daily cap:
  -> budget line renders yellow (ANSI 33)
  -> event stream appends budget_warning event

When budget exceeds 95% of daily cap:
  -> budget line renders red (ANSI 31)
  -> budget_critical event emitted

When all agents complete:
  -> dashboard shows summary line: "All done. N tests green, M PRs created"
  -> suggests next action: "Run /review to inspect PRs"

When user presses 'j' or Ctrl-n:
  -> selected agent moves down
  -> agent detail panel updates

When user presses Enter on selected agent:
  -> tmux switches to that agent's pane

When user presses 'r':
  -> forces immediate refresh (bypasses 2s poll)

When user presses 'q' or Ctrl-c:
  -> dashboard exits cleanly
  -> tmux layout restored to pre-dashboard state

When ShikiDB is unreachable:
  -> dashboard shows "DB offline" in status bar
  -> continues rendering with cached data
  -> retries every 10 seconds
```

## 1.4 Business Rules

| Rule | Detail |
|---|---|
| BR-D1 | Dashboard polls EventBus every 2 seconds (configurable via `--interval`) |
| BR-D2 | Progress bars calculated from ShikiEvent `wave_progress` payload (completed/total) |
| BR-D3 | Budget data from `BudgetEnforcer.currentSpend()` (ShikiCore) |
| BR-D4 | PR data from `gh pr list --json` cached with 30s TTL |
| BR-D5 | Test count from last `test_completed` event payload |
| BR-D6 | Agent list from `SessionRegistry.activeSessions()` |
| BR-D7 | Color thresholds: green <60%, yellow 60-80%, orange 80-95%, red >95% |
| BR-D8 | Maximum 8 agents displayed; overflow shows "+N more" with scroll |
| BR-D9 | Event stream shows last 5 events, scrollable with `e` key |
| BR-D10 | `shikki start` creates dashboard layout automatically (opt-out with `--no-dashboard`) |

## 1.5 Architecture

```
DashboardCommand (shikki dashboard)
    |
    +-> DashboardRenderer (ANSI output, 80x24 minimum)
    |       |
    |       +-> AgentPanel        <- SessionRegistry + EventBus
    |       +-> OrchestratorPanel <- current session state
    |       +-> EventStreamPanel  <- last N ShikiEvents
    |       +-> StatusBar         <- BudgetEnforcer + git + PR cache
    |
    +-> DashboardPoller (async, configurable interval)
            |
            +-> EventBus.subscribe(filter: .dashboard)
            +-> ShikiMCP (fallback if EventBus unavailable)
```

### New Files

```
tools/shiki-ctl/Sources/ShikiCtlKit/
  Commands/
    DashboardCommand.swift          (~80 LOC)
  TUI/
    Dashboard/
      DashboardRenderer.swift       (~200 LOC) — layout + ANSI rendering
      AgentPanel.swift              (~80 LOC)  — agent list with progress
      OrchestratorPanel.swift       (~40 LOC)  — main session state
      EventStreamPanel.swift        (~60 LOC)  — scrollable event log
      StatusBar.swift               (~60 LOC)  — budget + git + PRs
      DashboardPoller.swift         (~50 LOC)  — async event subscription
      DashboardKeyHandler.swift     (~50 LOC)  — keyboard input routing
```

## 1.6 Implementation Tasks

| # | Task | LOC | Depends |
|---|---|---|---|
| D1 | `DashboardRenderer` — ANSI grid layout engine | 200 | — |
| D2 | `AgentPanel` — session list with progress bars | 80 | D1 |
| D3 | `StatusBar` — budget + git + PR + test aggregation | 60 | D1 |
| D4 | `EventStreamPanel` — scrollable event log | 60 | D1 |
| D5 | `DashboardPoller` — async EventBus subscription | 50 | EventBus |
| D6 | `DashboardKeyHandler` — j/k/Enter/q/r/e input | 50 | D1 |
| D7 | `DashboardCommand` — CLI entry point + `--interval` flag | 80 | D1-D6 |
| D8 | Integration with `shikki start` (auto-layout) | 40 | D7 |
| D9 | Tests: 12 unit (panels) + 4 integration (full render) | 180 | D1-D7 |

**Total**: ~620 LOC production + ~180 LOC tests = ~800 LOC

## 1.7 @shi Team Challenge

**@Sensei (CTO)**: The 2-second poll interval is pragmatic but not reactive. Should we use Unix domain sockets for push-based updates instead? The EventBus already supports `UnixSocketTransport`. Poll first, push later — or push from day 1?

> **Decision**: Poll first. The dashboard is a consumer, not a critical path. 2s is imperceptible for human oversight. Unix sockets add complexity (daemon process, connection management) that we ship in v1.1 when Observatory needs sub-second updates. The poller is behind a protocol — swap transport without touching panels.

**@Ronin (Adversarial)**: What happens when 12 agents are running and the terminal is 80 columns wide? The layout breaks. CrewAI's web UI scales to any viewport. Are we shipping a demo or a tool?

> **Response**: BR-D8 caps visible agents at 8 with "+N more" overflow. The renderer adapts to terminal width: below 100 cols, orchestrator panel collapses to a single status line. Below 60 cols, we switch to compact mode (agent names only, no progress bars). This is tested — `DashboardRendererTests` covers 60/80/120/200 column widths. Web UIs scale to viewport; we scale to terminal. Same problem, native solution.

**@Hanami (UX)**: The event stream at the bottom is noise. Users scan top-down — agents first, then status. Events should be on-demand, not always visible.

> **Decision**: Events hidden by default. `e` toggles event panel (replaces status bar temporarily). Status bar always shows the *last* event as a one-liner. Full event stream is opt-in. This keeps the default view clean: agents + budget + git. Power users press `e`.

---

# Feature 2: `shikki init` — Project Bootstrapper

> **Priority**: P1 — onboarding gate, every new user hits this
> **LOC estimate**: ~480 LOC production + ~150 LOC tests
> **Depends on**: ShikiMCP (for DB registration), shikki doctor (DONE)

## 2.1 Problem

CrewAI: `crewai create crew my_project` — 3 seconds to a working agent team.
LangGraph: `langgraph new` — template selection, instant scaffold.
Shikki: read CLAUDE.md, copy project-adapter.md from another project, manually configure MCP, hope you got the test command right.

Every minute of setup friction is a user who goes back to CrewAI. `terraform init` proved that bootstrapping is not a feature — it is the feature.

## 2.2 Solution

```bash
shikki init                      # auto-detect from cwd
shikki init --type swift         # explicit project type
shikki init --type node
shikki init --type deno
shikki init --type go
shikki init --type rust
shikki init --type python        # know thy enemy
```

### What It Creates

```
your-project/
  .claude/
    CLAUDE.md                    <- project-specific agent instructions
  .mcp.json                     <- ShikiDB + GitHub MCP servers
  project-adapter.md            <- test/build/lint commands, language checklist
  .shikki/
    config.json                 <- project ID, type, created date
```

### What It Does

1. **Detect project type** — scan for `Package.swift`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `deno.json`
2. **Generate project-adapter.md** — test command, build command, lint command, language-specific quality checklist (the 9-gate pipeline adapted per language)
3. **Generate .claude/CLAUDE.md** — project-specific instructions referencing the adapter
4. **Generate .mcp.json** — ShikiDB MCP + GitHub MCP pre-configured
5. **Generate .shikki/config.json** — project metadata for ShikiDB registration
6. **Register in ShikiDB** — POST project record with type, path, created date
7. **Run `shikki doctor`** — verify environment (delta, diffnav, qmd, git, tmux)
8. **Report missing tools** — with install commands (`brew install delta`, etc.)

### Detection Priority

```
Package.swift       -> swift
Cargo.toml          -> rust
go.mod              -> go
deno.json           -> deno
package.json        -> node
pyproject.toml      -> python
Makefile (only)     -> generic
(nothing found)     -> prompt for --type
```

If multiple markers found (e.g., `Package.swift` + `package.json`), prefer compiled language. Warn about multi-language detection.

## 2.3 S3 Spec (TPDD)

```s3
When initializing in a directory with Package.swift:
  -> detects project type as "swift"
  -> generates project-adapter.md with "swift test" as test command
  -> generates project-adapter.md with "swift build" as build command
  -> lists SPM targets from Package.swift in adapter
  -> generates .claude/CLAUDE.md referencing project-adapter.md

When initializing in a directory with package.json:
  -> detects project type as "node"
  -> generates project-adapter.md with "npm test" as test command
  -> reads scripts section for available commands
  -> detects test framework (jest, vitest, mocha) from devDependencies

When initializing in a directory with Cargo.toml:
  -> detects project type as "rust"
  -> generates project-adapter.md with "cargo test" as test command
  -> generates project-adapter.md with "cargo build" as build command
  -> detects workspace members if [workspace] present

When initializing in a directory with go.mod:
  -> detects project type as "go"
  -> generates project-adapter.md with "go test ./..." as test command
  -> extracts module name from go.mod

When initializing in a directory with deno.json:
  -> detects project type as "deno"
  -> generates project-adapter.md with "deno test" as test command
  -> reads tasks section for available commands

When initializing in a directory with pyproject.toml:
  -> detects project type as "python"
  -> generates project-adapter.md with "pytest" as test command
  -> detects package manager (poetry, pip, uv) from config

When initializing with explicit --type flag:
  -> skips auto-detection
  -> uses provided type directly

When project-adapter.md already exists:
  -> warns "project-adapter.md already exists"
  -> shows diff between existing and generated
  -> requires --force to overwrite
  -> without --force, exits with code 1

When .shikki/config.json already exists:
  -> reads existing project ID
  -> updates metadata (does not create duplicate)
  -> warns "project already initialized, updating config"

When no project markers found and no --type flag:
  -> prints "Could not detect project type"
  -> lists supported types
  -> exits with code 1 (no interactive prompt — CLI-first)

When ShikiDB is unreachable during init:
  -> completes all local file generation
  -> warns "ShikiDB registration skipped (unreachable)"
  -> saves pending registration in .shikki/config.json (synced on next shikki command)

When shikki doctor finds missing tools:
  -> lists each missing tool with install command
  -> does NOT block init (tools are optional)
  -> reports "init complete with warnings"
```

## 2.4 Business Rules

| Rule | Detail |
|---|---|
| BR-I1 | Init is idempotent — running twice does not duplicate files (updates if --force) |
| BR-I2 | Generated files include `# Generated by shikki init — safe to edit` header |
| BR-I3 | .mcp.json merges with existing (does not overwrite user's MCP config) |
| BR-I4 | Project ID is UUIDv4, stable across re-inits (stored in .shikki/config.json) |
| BR-I5 | `shikki init --dry-run` shows what would be created without writing |
| BR-I6 | Templates stored in `tools/shiki-ctl/Resources/Templates/` (compiled into binary) |
| BR-I7 | Test command validation: init runs the detected test command once to verify it works |
| BR-I8 | `.shikki/` added to project .gitignore suggestion (not forced) |
| BR-I9 | CLAUDE.md template includes: project context, test strategy, quality gates, branch model |
| BR-I10 | Supports `--minimal` flag: only project-adapter.md + .shikki/config.json (no .claude/) |

## 2.5 Architecture

```
InitCommand (shikki init [--type TYPE] [--force] [--dry-run] [--minimal])
    |
    +-> ProjectDetector
    |       |
    |       +-> SwiftDetector      (Package.swift -> targets, dependencies)
    |       +-> NodeDetector       (package.json -> scripts, devDeps)
    |       +-> RustDetector       (Cargo.toml -> workspace, crates)
    |       +-> GoDetector         (go.mod -> module name)
    |       +-> DenoDetector       (deno.json -> tasks)
    |       +-> PythonDetector     (pyproject.toml -> tool section)
    |
    +-> TemplateEngine
    |       |
    |       +-> ProjectAdapterTemplate
    |       +-> ClaudeMDTemplate
    |       +-> MCPConfigTemplate
    |       +-> ShikkiConfigTemplate
    |
    +-> ShikiMCP (project registration)
    +-> DoctorCommand (environment verification)
```

### New Files

```
tools/shiki-ctl/Sources/ShikiCtlKit/
  Commands/
    InitCommand.swift               (~100 LOC)
  Init/
    ProjectDetector.swift           (~120 LOC) — multi-language detection
    TemplateEngine.swift            (~80 LOC)  — Mustache-lite string interpolation
    ProjectType.swift               (~30 LOC)  — enum + metadata per type

tools/shiki-ctl/Resources/Templates/
    project-adapter-swift.md        (~40 LOC)
    project-adapter-node.md         (~40 LOC)
    project-adapter-rust.md         (~30 LOC)
    project-adapter-go.md           (~30 LOC)
    project-adapter-deno.md         (~30 LOC)
    project-adapter-python.md       (~30 LOC)
    claude-md.md                    (~40 LOC)
    mcp-config.json                 (~20 LOC)
```

## 2.6 Implementation Tasks

| # | Task | LOC | Depends |
|---|---|---|---|
| I1 | `ProjectType` enum + per-type metadata (test cmd, build cmd) | 30 | — |
| I2 | `ProjectDetector` — file scanning + multi-marker resolution | 120 | I1 |
| I3 | `TemplateEngine` — simple `{{variable}}` interpolation | 80 | — |
| I4 | Resource templates (6 languages + CLAUDE.md + MCP) | ~260 | I1 |
| I5 | `InitCommand` — CLI wiring + --force/--dry-run/--minimal | 100 | I2, I3 |
| I6 | ShikiDB registration via ShikiMCP | 30 | ShikiMCP |
| I7 | Doctor integration (post-init verification) | 20 | shikki doctor |
| I8 | .mcp.json merge logic (preserve existing entries) | 40 | I5 |
| I9 | Tests: 10 unit (detection) + 6 template + 4 integration | 150 | I1-I8 |

**Total**: ~480 LOC production + ~260 LOC templates + ~150 LOC tests = ~890 LOC

## 2.7 @shi Team Challenge

**@Sensei (CTO)**: The `ProjectDetector` is a classic visitor pattern problem. 6 detectors today, 20 tomorrow. Should we use a plugin architecture from day 1 — each detector is a separate module that registers itself?

> **Decision**: No plugin architecture yet. 6 detectors in a single file with a protocol (`ProjectDetectorProtocol`) and a `detect(in directory: URL) -> ProjectInfo?` method. The protocol is the plugin contract. When we hit 10+ languages, we extract into separate files. YAGNI until then — but the protocol makes migration trivial.

**@Ronin (Adversarial)**: `shikki init` in a monorepo with 5 Package.swift files, 3 package.json files, and a Cargo.toml. What happens? CrewAI sidesteps this by requiring explicit project type. Are we over-engineering auto-detection?

> **Response**: Detection runs from cwd only (not recursive). If cwd has Package.swift, it is a Swift project — regardless of subdirectories. Monorepo users run `shikki init` in each sub-project, or use `--type` at root. The spec explicitly handles multi-marker (BR: prefer compiled language, warn). We are not over-engineering — we are handling the 95% case (single-language project) and providing --type for the 5%.

**@Kintsugi (Philosophy)**: Init is the first touch. It sets the tone. `terraform init` feels authoritative — it *knows* what it is doing. `npm init` feels like a form. Which energy does `shikki init` carry?

> **Decision**: Authoritative. No interactive prompts. Detect, generate, report. The output reads like a briefing: "Detected Swift project (3 targets, 14 dependencies). Generated project-adapter.md, .claude/CLAUDE.md, .mcp.json. Registered in ShikiDB as project abc123. Environment: 2 warnings (delta missing, qmd outdated). Ready." One screen. No questions. The user reads a report, not a questionnaire.

---

# Feature 3: Agent Template Marketplace

> **Priority**: P2 — spec now, build post-launch (v1.1)
> **LOC estimate**: ~350 LOC client + ~400 LOC registry API (v1.1)
> **Depends on**: `shikki init` (Feature 2), ShikiMCP, community flywheel architecture

## 3.1 Problem

CrewAI Templates Hub: browse 200+ pre-built agent teams by use case. Copy, customize, run. A user searching "code review agent" finds 12 options with ratings. LangChain Hub: share and version prompts, chains, agents. 50K+ public artifacts.

Shikki: skills are markdown files in `.claude/skills/`. Sharing means copy-pasting from GitHub. No discovery, no versioning, no quality signal. Every user builds from scratch.

The marketplace is not about code — it is about **compounding community intelligence**. Every shared template makes Shikki more valuable for every user.

## 3.2 Solution

A CLI-native package manager for agent templates, project adapters, quality checklists, and persona definitions.

```bash
# Discovery
shikki search "ios animation"          # search registry
shikki search --type adapter           # filter by type
shikki search --type persona           # agent personalities
shikki search --type checklist         # quality gates
shikki search --type skill             # slash commands

# Installation
shikki install @official/swift-testing     # official template
shikki install @community/react-adapter    # community template
shikki install @sensei/architecture-review # persona + skill bundle

# Publishing
shikki publish                         # publish from current project
shikki publish --private               # org-only (enterprise)

# Management
shikki list                            # installed templates
shikki update                          # update all to latest
shikki uninstall @community/react-adapter
```

### Template Types

| Type | What it contains | Installed to |
|---|---|---|
| **adapter** | project-adapter.md for a language/framework | `project-adapter.md` (merge) |
| **persona** | Agent personality definition | `.claude/skills/personas/` |
| **checklist** | Quality gate checklist | `.claude/skills/checklists/` |
| **skill** | Slash command skill file | `.claude/skills/` |
| **bundle** | Multiple of the above | respective locations |

### Template Format (shikki-template.json)

```json
{
  "name": "swift-testing",
  "version": "1.2.0",
  "type": "skill",
  "author": "@official",
  "description": "Swift Testing expert skill — @Test macro, parameterized tests, traits",
  "tags": ["swift", "testing", "ios", "macos"],
  "compatibility": ">=1.0.0",
  "files": [
    { "src": "swift-testing.md", "dest": ".claude/skills/swift-testing.md" }
  ],
  "dependencies": [],
  "license": "MIT"
}
```

### Registry Architecture

```
shikki CLI (client)
    |
    +-> Local cache (~/.shikki/templates/)
    |
    +-> Registry API (templates.shikki.dev)
    |       |
    |       +-> Search (BM25 + tags)
    |       +-> Download (versioned tarballs)
    |       +-> Publish (authenticated, signed)
    |       +-> Stats (downloads, ratings)
    |
    +-> Git fallback (shikki install github:user/repo)
```

**v1.0 (ship now)**: Git-only. `shikki install github:user/repo` clones and copies files. No registry. No API. The format is the contract.

**v1.1 (post-launch)**: Registry API at templates.shikki.dev. Search, publish, versioning, download counts.

## 3.3 S3 Spec (TPDD)

```s3
When searching for "swift testing":
  -> returns templates matching "swift" AND "testing" in name, description, or tags
  -> results sorted by download count (descending)
  -> each result shows: name, author, version, description, download count

When searching with --type adapter:
  -> only returns templates where type == "adapter"
  -> excludes skills, personas, checklists

When installing @official/swift-testing:
  -> downloads template from registry (or git in v1.0)
  -> validates shikki-template.json schema
  -> copies files to destinations specified in template
  -> records installation in ~/.shikki/installed.json

When installing a template that conflicts with existing file:
  -> shows diff between existing and incoming
  -> requires --force to overwrite
  -> without --force, exits with code 1

When installing a template with dependencies:
  -> resolves dependency tree
  -> installs dependencies first
  -> warns if dependency version conflicts with installed

When installing from git URL (v1.0 fallback):
  -> clones repo to temp directory
  -> reads shikki-template.json from repo root
  -> follows standard install flow
  -> caches in ~/.shikki/templates/git-cache/

When publishing a template:
  -> validates shikki-template.json exists in cwd
  -> validates all referenced files exist
  -> validates version is semver
  -> pushes to registry (or creates git tag in v1.0)
  -> prints published URL

When publishing without shikki-template.json:
  -> prints "No shikki-template.json found. Run shikki template init to create one."
  -> exits with code 1

When listing installed templates:
  -> reads ~/.shikki/installed.json
  -> shows: name, version, type, installed date
  -> marks templates with available updates

When updating all templates:
  -> checks registry for newer versions of each installed template
  -> downloads and replaces updated templates
  -> prints changelog summary per template

When uninstalling a template:
  -> removes files listed in template manifest
  -> removes entry from installed.json
  -> warns if other templates depend on it

When registry is unreachable:
  -> search returns "Registry unreachable. Try: shikki install github:user/repo"
  -> install from git still works
  -> offline mode uses local cache for list/uninstall
```

## 3.4 Business Rules

| Rule | Detail |
|---|---|
| BR-M1 | Template names are globally unique (scoped by author: `@author/name`) |
| BR-M2 | Official templates prefixed with `@official/` — curated by Shikki team |
| BR-M3 | Version must follow semver (validated on publish) |
| BR-M4 | Templates signed with author's SSH key (tamper detection) |
| BR-M5 | Maximum template size: 500KB (skills are text, not binaries) |
| BR-M6 | `~/.shikki/installed.json` is the source of truth for local state |
| BR-M7 | Git fallback always available (registry is optional, not required) |
| BR-M8 | Published templates are immutable per version (no in-place updates) |
| BR-M9 | Deprecation: author can mark version deprecated, not delete |
| BR-M10 | Rate limiting: 100 searches/hour, 50 installs/hour (per API key) |
| BR-M11 | v1.0 ships git-only; registry API is v1.1 |
| BR-M12 | `shikki template init` scaffolds shikki-template.json interactively |

## 3.5 Architecture (v1.0 — git-only client)

```
tools/shiki-ctl/Sources/ShikiCtlKit/
  Commands/
    SearchCommand.swift             (~40 LOC)  — v1.0: git grep, v1.1: registry API
    InstallCommand.swift            (~80 LOC)  — git clone + file copy
    PublishCommand.swift            (~40 LOC)  — v1.0: git tag, v1.1: registry push
    ListCommand.swift               (~30 LOC)  — read installed.json
    UpdateCommand.swift             (~40 LOC)  — check + re-install
    UninstallCommand.swift          (~30 LOC)  — remove files + manifest entry
    TemplateInitCommand.swift       (~40 LOC)  — scaffold shikki-template.json
  Marketplace/
    TemplateManifest.swift          (~50 LOC)  — Codable model for shikki-template.json
    TemplateInstaller.swift         (~80 LOC)  — download, validate, copy, record
    InstalledRegistry.swift         (~40 LOC)  — ~/.shikki/installed.json CRUD
    GitTransport.swift              (~60 LOC)  — clone, cache, checkout version
    RegistryClient.swift            (~60 LOC)  — v1.1: HTTP client for registry API
```

### v1.1 — Registry API (separate repo: shikki-registry)

```
PocketBase instance at templates.shikki.dev
  Collections:
    templates     — name, author, description, type, tags, downloads
    versions      — template_id, version, tarball_url, sha256, created
    reviews       — template_id, user_id, rating (1-5), comment
```

PocketBase because it is already in the stack (obyw.one). No new infrastructure. Deploy as systemd service on VPS.

## 3.6 Implementation Tasks

### v1.0 (git-only client — ship with Shikki v1.0)

| # | Task | LOC | Depends |
|---|---|---|---|
| M1 | `TemplateManifest` — Codable model + validation | 50 | — |
| M2 | `InstalledRegistry` — local installed.json CRUD | 40 | M1 |
| M3 | `GitTransport` — clone, cache, checkout | 60 | — |
| M4 | `TemplateInstaller` — validate + copy + record | 80 | M1, M2, M3 |
| M5 | `InstallCommand` — CLI wiring | 80 | M4 |
| M6 | `ListCommand` + `UninstallCommand` | 60 | M2 |
| M7 | `TemplateInitCommand` — scaffold manifest | 40 | M1 |
| M8 | Tests: 8 unit + 4 integration | 120 | M1-M7 |

**v1.0 Total**: ~350 LOC production + ~120 LOC tests = ~470 LOC

### v1.1 (registry — post-launch)

| # | Task | LOC | Depends |
|---|---|---|---|
| M9 | PocketBase schema + migrations | 80 | — |
| M10 | `RegistryClient` — search, download, publish | 60 | M4 |
| M11 | `SearchCommand` — registry-backed fuzzy search | 40 | M10 |
| M12 | `PublishCommand` — tarball + upload + sign | 80 | M10 |
| M13 | `UpdateCommand` — version check + re-install | 40 | M10 |
| M14 | Caddy config for templates.shikki.dev | 20 | VPS |
| M15 | Registry tests | 80 | M9-M13 |

**v1.1 Total**: ~320 LOC production + ~80 LOC tests = ~400 LOC

## 3.7 @shi Team Challenge

**@Sensei (CTO)**: npm took 10 years to solve dependency hell. Are we building another npm? The dependency tree (BR: templates can depend on other templates) is a complexity bomb. Should v1.0 templates be standalone only — no dependencies?

> **Decision**: v1.0 templates have NO dependencies. The `dependencies` field exists in the manifest schema (forward compatibility) but `TemplateInstaller` ignores it in v1.0 and warns: "Dependencies not yet supported, install manually." v1.1 adds flat dependency resolution (no nested — if A needs B@1.0 and C needs B@2.0, that is an error, not a resolution). We are not building npm. We are building brew taps — simple, flat, explicit.

**@Ronin (Adversarial)**: A malicious template installs a skill that tells Claude to exfiltrate environment variables. The marketplace is an attack surface. CrewAI has the same problem but hides behind "it is just Python." Shikki skills have direct agent access. How do we not become the AI supply chain attack vector?

> **Response**: Three layers. (1) SSH signature verification on publish — every template is traceable to an author. (2) File destination whitelist — templates can only write to `.claude/skills/`, `project-adapter.md`, and `.shikki/`. No arbitrary file writes. (3) `shikki install --inspect` shows full file contents before writing (default for community templates, skipped for @official). v1.1 adds community flagging + automated skill scanning for dangerous patterns (`env`, `credentials`, `token`, `secret` in skill content). This is not bulletproof — but it is better than `pip install random-package`. And our templates are markdown, not executable code.

**@Shogun (Market)**: CrewAI Templates Hub has 200+ templates. We launch with 0. How do we seed the marketplace? A template hub with no templates is worse than no hub at all.

> **Decision**: Launch with 10 @official templates covering the most common use cases. Seed list: (1) swift-testing, (2) swift-concurrency, (3) react-adapter, (4) node-adapter, (5) python-adapter, (6) code-review-checklist, (7) architecture-review-persona, (8) tdd-workflow-skill, (9) pr-review-skill, (10) security-audit-checklist. These are extracted from our existing skills — proven in production. Community templates follow organically. We do not need 200 to launch — we need 10 that work perfectly.

---

# Cross-Feature Dependencies

```
Feature 1 (Dashboard)
    |
    +-- EventBus (DONE)
    +-- SessionRegistry (DONE)
    +-- ShikiMCP (P0)
    +-- BudgetEnforcer (ShikiCore P0)

Feature 2 (Init)
    |
    +-- shikki doctor (DONE)
    +-- ShikiMCP (P0) — for DB registration
    +-- Feature 3 format (template manifest schema)

Feature 3 (Marketplace)
    |
    +-- Feature 2 (Init creates the project structure templates install into)
    +-- ShikiMCP (P0) — for template metadata
    +-- PocketBase (existing infra) — for v1.1 registry
```

### Shipping Order

1. **Feature 2 (`shikki init`)** — unblocks onboarding, no heavy dependencies
2. **Feature 1 (Dashboard)** — needs ShikiCore events flowing (build after ShikiCore Wave 1)
3. **Feature 3 v1.0 (git-only marketplace)** — ships alongside init, lightweight
4. **Feature 3 v1.1 (registry)** — post-launch, needs community traction first

---

# Summary

| Feature | LOC (prod) | LOC (test) | Priority | Ships |
|---|---|---|---|---|
| Reactive Dashboard | 620 | 180 | P0.5 | v1.0 (after ShikiCore W1) |
| `shikki init` | 740 | 150 | P1 | v1.0 |
| Marketplace (git) | 350 | 120 | P2 | v1.0 |
| Marketplace (registry) | 320 | 80 | P2 | v1.1 |
| **Total** | **2,030** | **530** | — | — |

**2,560 lines of code** to neutralize every competitive gap. CrewAI has 44K stars and a React dashboard. We have compiled Swift, zero-infrastructure tmux, and a marketplace that runs on git. Different weight class, same ring.

---

> Spec saved: `features/shikki-killer-features.md`
> Saved to ShikiDB: pending (save on next MCP connection)
