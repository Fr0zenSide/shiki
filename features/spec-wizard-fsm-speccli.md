# Spec: Wizard, Flow State Machine, Spec CLI

> Implementation spec for three core Shikki components. Written by @Sensei, 2026-03-23.
> Depends on: ShikiCore (FeatureLifecycle, PipelineGate, EventPersister), ShikiCtlKit, ShikiDB.

---

## 1. Wizard — `shikki wizard`

### 1.1 Design Philosophy

The wizard is a **game**, not a form. Kinetype is the north star: each level IS a real Shikki command that produces a tangible artifact. The user learns by doing, never by reading. Configuration (Docker, LLM, workspace) happens invisibly DURING gameplay, not in a setup screen before it.

### 1.2 Level Design

| Level | Name | Command Taught | Real Artifact Produced | Environment Setup Hidden Inside |
|-------|------|---------------|----------------------|-------------------------------|
| 0 | "The Forge" | (auto) | `~/.config/shiki/` created, workspace detected | Workspace scan, Docker bootstrap, LLM provider detection |
| 1 | "Your First Idea" | `shikki backlog add` | A real backlog item in ShikiDB | Company creation from discovered git repos |
| 2 | "The Shadow" | `shikki decide` | A resolved decision record | Decision queue seeding for the idea from L1 |
| 3 | "The Plan" | `shikki spec` | A `features/*.md` spec file + DB plan record | Agent dispatch infra verification |
| 4 | "Let It Fly" | `shikki run` | An agent dispatched, event bus streaming | Event bus subscriber + tmux pane (if available) |
| 5 | "The Inbox" | `shikki inbox` | An inbox item (PR or completed task) | ListReviewer component first use |
| 6 | "The Review" | `shikki review` | Review progress saved, corrections sent | Diff tool detection (delta, difftastic, diffnav) |
| 7 | "Ship It" | `shikki ship` | A real release (or dry-run for safety) | Ship gate pipeline verification |
| Boss | "The Report" | `shikki report` | A sprint summary in terminal | Report aggregation from DB |

### 1.3 Level Mechanics

Each level follows the same 4-beat rhythm:

1. **Intro** (2 lines max) — narrative hook, no instructions. Example: *"Every great product starts with one idea. What's yours?"*
2. **Action** — the user types a real Shikki command. The wizard provides the command, user executes it. The command runs against real data (not a sandbox).
3. **Reward** — immediate visible output. The artifact is shown inline. Example: *"Backlog item #1 created: 'Add dark mode to WabiSabi'. Your journey begins."*
4. **Unlock** — the next level is revealed with a 1-line teaser. Example: *"But every idea has shadows. Level 2: The Shadow."*

### 1.4 Level 0 — "The Forge" (Environment Bootstrap)

Level 0 is NOT presented as configuration. It is the opening cinematic.

**Sequence:**
1. Print the Shikki splash (reuse `SplashRenderer`)
2. "Welcome, Daimyo. Let's forge your workspace."
3. Auto-detect workspace root (same logic as `StartupCommand.resolveWorkspace()`)
4. Scan `projects/` for git repos. For each discovered repo:
   - Extract project name from directory name
   - Check for `Package.swift` (Swift), `package.json` (TS/JS), `Cargo.toml` (Rust), `go.mod` (Go)
   - Present: "Found 5 projects: maya, wabisabi, brainy, flsh, kintsugi-ds. Creating companies..."
   - Auto-create companies in ShikiDB via backend API
5. Check Docker/Colima — start if needed (reuse `StartupCommand` bootstrap logic)
6. Check LLM provider — detect from env vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OLLAMA_URL`), or prompt once
7. Check backend health — start containers if needed
8. Write `~/.config/shiki/wizard-progress.json` with `{ "level": 0, "completedAt": "..." }`
9. "The forge is ready. Your tools await."

**Key constraint:** If any bootstrap step fails, the wizard DOES NOT abort. It warns and continues. A degraded workspace is better than an abandoned wizard. The failed component becomes a follow-up quest.

### 1.5 Progress Persistence

File: `~/.config/shiki/wizard-progress.json`

```
{
  "version": 1,
  "levels": {
    "0": { "completedAt": "2026-03-23T14:00:00Z", "artifactId": null },
    "1": { "completedAt": "2026-03-23T14:02:00Z", "artifactId": "backlog-item-uuid" },
    "2": { "completedAt": null, "artifactId": null }
  },
  "currentLevel": 2,
  "workspacePath": "/Users/jeoffrey/Documents/Workspaces/shiki",
  "companiesCreated": ["maya", "wabisabi", "brainy", "flsh", "kintsugi-ds"]
}
```

**Resume:** `shikki wizard` checks this file. If present, skip to `currentLevel`. If all 8 levels + boss complete, show a "mastery" message and offer replay for any new levels added since graduation.

### 1.6 First-Run Detection

`shikki` (no subcommand) checks:
1. Does `~/.config/shiki/` exist?
2. Does `wizard-progress.json` exist with `currentLevel >= 8`?

If either is false, print: *"Looks like your first time. Starting the wizard..."* and launch `WizardCommand`.

If the user explicitly runs `shikki start` or any other command, the wizard is NOT forced — respect intent.

### 1.7 Environment Setup Integration

The wizard does NOT call `StartupCommand` directly. Instead, it extracts the reusable pieces from `StartupCommand` into `ShikiCtlKit`:

- `EnvironmentDetector` — already exists, reuse as-is
- `WorkspaceScanner` — NEW. Scans a directory for git repos, returns `[DiscoveredProject]`
- `CompanyBootstrapper` — NEW. Takes `[DiscoveredProject]`, creates companies via backend API
- `LLMProviderDetector` — NEW. Checks env vars and known URLs, returns `LLMProviderConfig`

`StartupCommand` and `WizardCommand` both consume these components. No duplication.

### 1.8 Idempotency

Every level is idempotent. Running Level 1 twice does not create duplicate backlog items. The wizard checks: "Does the artifact from this level already exist?" If yes, show it and advance.

### 1.9 Replayability

After graduation, `shikki wizard` enters "New Levels" mode. If Shikki has added commands since the user's last wizard run (tracked by version in progress file), only those new levels are presented. Old levels show as completed with their original artifacts.

---

## 2. Flow State Machine

### 2.1 States

The Flow FSM tracks a **flow item** — a single idea from inception to report. This is NOT the same as `LifecycleState` in ShikiCore, which tracks a feature through the build pipeline (specDrafting through shipping). The Flow FSM is the outer shell; `FeatureLifecycle` is the inner engine for stages 4-7.

```
                                     ┌──────────────────────────────────────────────────────┐
                                     │            QUICK LANE (skip to running)              │
                                     │  raw ─────────────────────────────────→ running      │
                                     └──────────────────────────────────────────────────────┘

    ┌─────┐    ┌─────────┐    ┌────────┐    ┌──────────┐    ┌─────────┐    ┌─────────┐    ┌──────────┐    ┌─────────┐    ┌──────────┐
    │ raw │───→│ decided │───→│ specced │───→│ approved │───→│ running │───→│ inbox   │───→│ reviewed │───→│ shipped │───→│ reported │
    └─────┘    └─────────┘    └────────┘    └──────────┘    └─────────┘    └─────────┘    └──────────┘    └─────────┘    └──────────┘
       │            │              │              │               │              │              │               │
       ▼            ▼              ▼              ▼               ▼              ▼              ▼               ▼
    ┌──────┐    ┌──────┐      ┌──────┐      ┌──────┐        ┌──────┐      ┌──────┐      ┌──────┐        ┌──────┐
    │killed│    │killed│      │killed│      │rejected│      │failed│      │deferred│    │blocked│       │(done)│
    └──────┘    └──────┘      └──────┘      └──────┘        └──────┘      └──────┘      └──────┘        └──────┘
```

### 2.2 State Enum

```swift
public enum FlowStage: String, Codable, Sendable, CaseIterable {
    case raw            // Idea entered (backlog)
    case decided        // All shadows resolved (decide)
    case specced        // Spec file produced (spec)
    case approved       // @Daimyo validated the plan (review plan)
    case running        // Agents dispatched (run)
    case inbox          // Results ready for review (inbox)
    case reviewed       // PR reviewed and approved (review)
    case shipped        // Released through gates (ship)
    case reported       // Summary generated (report)

    // Terminal states
    case killed         // Removed from backlog with reason
    case failed         // Agent execution or gate failure
    case rejected       // Plan rejected by @Daimyo
    case deferred       // Pushed to later sprint
    case blocked        // External dependency blocking progress
}
```

### 2.3 Transition Table

| From | To | Trigger | Blocker | Gate |
|------|----|---------|---------|------|
| raw | decided | All T1/T2 decisions for this item resolved | Unresolved T1 decisions | None |
| raw | killed | User kills backlog item | None | None |
| raw | running | `shikki quick` (skip decide/spec) | None | Auto-escalation guard: if agent touches >3 files or runs >30min, escalate to `specced` |
| decided | specced | `/spec` skill produces `features/*.md` | None | Spec must be >50 lines (SpecGate) |
| decided | killed | User kills after deciding it's not worth it | None | None |
| specced | approved | @Daimyo validates the plan | None | Human gate (no auto-approve) |
| specced | rejected | @Daimyo rejects the plan | None | None |
| specced | killed | User kills the spec | None | None |
| approved | running | `shikki run` dispatches agents | Budget exceeded | BudgetEnforcer check |
| running | inbox | All agents complete, PRs created | None | Agent completion event |
| running | failed | Agent crashes, tests fail, timeout | None | None |
| inbox | reviewed | @Daimyo approves PR in `shikki review` | None | Human gate |
| inbox | deferred | @Daimyo defers review to later | None | None |
| reviewed | shipped | `shikki ship` passes all 8 gates | Any gate failure | ShipService 8-gate pipeline |
| reviewed | blocked | External dep blocks shipping | None | None |
| shipped | reported | `shikki report` generates summary | None | None |
| rejected | specced | Re-spec after corrections | None | None |
| failed | running | Retry after fix | None | None |
| blocked | (previous) | Blocker resolved | None | None |
| deferred | inbox | Re-enter inbox next sprint | None | None |

### 2.4 Integration with FeatureLifecycle

The Flow FSM and `FeatureLifecycle` are **not the same thing**. They are nested:

```
FlowItem (FSM)                    FeatureLifecycle (ShikiCore)
─────────────                     ────────────────────────────
raw                               (not started)
decided                           (not started)
specced                           idle
approved → running                idle → specDrafting → building → gating
inbox                             gating → shipping
reviewed                          shipping
shipped                           done
reported                          done
```

When a FlowItem transitions to `approved`, a `FeatureLifecycle` is created for it. The lifecycle manages the build pipeline internally. When the lifecycle reaches `done`, the FlowItem transitions to `inbox`.

**Bridge:** `FlowLifecycleBridge` — an observer that watches `FeatureLifecycle` state changes and triggers `FlowItem` transitions. Lives in ShikiCore, not in shikki CLI.

### 2.5 Persistence

**Option chosen: ShikiDB `flow_items` table (new table).**

Why not `agent_events`? Events are append-only logs. Flow items are stateful entities with a current stage, history, and linked artifacts. Different access pattern.

```sql
CREATE TABLE flow_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    stage TEXT NOT NULL DEFAULT 'raw',           -- FlowStage.rawValue
    source TEXT,                                  -- 'push', 'wizard', 'backlog', 'quick'
    company_slug TEXT,
    project_slug TEXT,
    backlog_item_id UUID REFERENCES backlog_items(id),
    spec_path TEXT,                               -- features/*.md
    lifecycle_id TEXT,                             -- FeatureLifecycle.featureId
    pr_numbers INTEGER[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    killed_reason TEXT,
    deferred_until TIMESTAMPTZ
);

CREATE TABLE flow_transitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_item_id UUID NOT NULL REFERENCES flow_items(id),
    from_stage TEXT NOT NULL,
    to_stage TEXT NOT NULL,
    actor TEXT NOT NULL,                          -- 'user:daimyo', 'agent:sensei', 'system'
    reason TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_flow_items_stage ON flow_items(stage);
CREATE INDEX idx_flow_items_company ON flow_items(company_slug);
CREATE INDEX idx_flow_transitions_item ON flow_transitions(flow_item_id);
```

### 2.6 Quick Lane — Auto-Escalation Guard

When a FlowItem enters `running` directly from `raw` (via `shikki quick`):

1. A background monitor tracks: files touched, elapsed time
2. If files touched > 3 OR elapsed time > 30 minutes:
   - Pause the agent
   - Emit `CoreEvent.autoEscalation(flowItemId:, reason:)`
   - Transition FlowItem to `specced` (force a spec phase)
   - Notify @Daimyo: "Quick task escalated — needs a spec."
3. The user can override with `--force-quick` (no escalation, you own the risk)

### 2.7 FlowItem in Swift

```swift
// In ShikiCore — packages/ShikiCore/Sources/ShikiCore/Flow/FlowItem.swift
public struct FlowItem: Codable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var description: String?
    public var stage: FlowStage
    public var source: FlowSource
    public var companySlug: String?
    public var projectSlug: String?
    public var specPath: String?
    public var lifecycleId: String?
    public var prNumbers: [Int]
    public let createdAt: Date
    public var updatedAt: Date
}

public enum FlowSource: String, Codable, Sendable {
    case push, wizard, backlog, quick, manual
}
```

### 2.8 FlowEngine

```swift
// In ShikiCore — packages/ShikiCore/Sources/ShikiCore/Flow/FlowEngine.swift
public actor FlowEngine {
    private let persister: any EventPersisting
    private let validator: FlowTransitionValidator

    /// Attempt a stage transition. Validates, persists, emits event.
    public func transition(_ item: inout FlowItem, to stage: FlowStage, actor: TransitionActor, reason: String) throws

    /// Get all items at a given stage.
    public func items(at stage: FlowStage) async throws -> [FlowItem]

    /// Get all items for a company.
    public func items(for companySlug: String) async throws -> [FlowItem]

    /// Create a new flow item from raw input.
    public func createItem(title: String, source: FlowSource, company: String?) async throws -> FlowItem

    /// Quick lane: raw → running with escalation guard.
    public func quickLane(_ item: inout FlowItem, agentId: String) async throws
}
```

---

## 3. Spec CLI — `shikki spec`

### 3.1 Purpose

Wrap the existing `/md-feature` skill (8-phase pipeline) into a CLI entry point that:
- Accepts a backlog item ID or free text as input
- Creates/advances a FlowItem through the `specced` stage
- Outputs a `features/*.md` file AND a ShikiDB plan record
- Triggers an inbox item for plan review upon completion

### 3.2 CLI Interface

```
USAGE: shikki spec <input> [options]

ARGUMENTS:
  <input>                 Backlog item ID (UUID or #N shorthand) or free text

OPTIONS:
  --company <slug>        Target company (auto-detected from cwd if omitted)
  --project <slug>        Target project within company
  --yolo                  Skip Phase 2 Q&A + Phase 5b readiness gate (see feature-pipeline.md)
  --dry-run               Show what would be specced without executing
  --resume                Resume an interrupted spec session
  -h, --help              Show help
```

### 3.3 Input Resolution

1. **UUID input** — look up `flow_items` table by ID. Must be in `decided` stage (or `raw` if user wants to skip decide).
2. **#N shorthand** — look up backlog item by display number (from `shikki backlog` list order). Resolve to flow_item_id.
3. **Free text** — create a new FlowItem with `source: .manual`, stage `raw`. Auto-advance to `decided` (no shadows to resolve for ad-hoc specs). Then proceed to spec.

### 3.4 Execution Flow

```
shikki spec "Add dark mode to WabiSabi" --company wabisabi

1. Resolve input → FlowItem (create if free text)
2. Validate FlowItem stage (must be decided or raw)
3. Transition FlowItem: decided → specced (in progress)
4. Invoke /md-feature skill programmatically:
   a. Build the prompt for claude -p (or AgentProvider)
   b. Include: feature name, company context, project adapter, decision history
   c. Run 8-phase pipeline (Phases 1-5b)
   d. Output: features/{slug}.md
5. Validate output via SpecGate (>50 lines, has wave breakdown)
6. POST plan to ShikiDB:
   POST /api/plans
   { title, specPath, waves, dependencies, effort, companySlug, projectSlug, flowItemId }
7. Transition FlowItem: specced (complete)
8. Create inbox item: type=spec, flowItemId, specPath
9. Print summary:
   "Spec complete: features/add-dark-mode-wabisabi.md (142 lines, 3 waves, ~4h effort)"
   "Plan saved to ShikiDB. Awaiting review in your inbox."
```

### 3.5 Agent Invocation

The spec command does NOT call `claude` directly. It goes through `AgentProvider` (ShikiCore):

```swift
let provider = ClaudeProvider(model: config.model)
let prompt = SpecPromptBuilder.build(
    featureName: input.resolvedTitle,
    company: company,
    project: project,
    decisions: relatedDecisions,
    existingSpecs: existingSpecPaths
)
let result = try await provider.run(prompt: prompt, timeout: .minutes(10))
```

This ensures AI-provider agnosticism (could be Claude, could be a local LLM via LM Studio).

### 3.6 Multi-Project Targeting

When `--company` is provided, the spec targets that company's context. When omitted:

1. Check cwd — if inside a known project directory, auto-detect company
2. If ambiguous or at workspace root, prompt: "Which company? [maya/wabisabi/...]"
3. `--project` narrows further within a multi-project company

The spec prompt includes the project adapter template (from `shiki-process/project-adapter-template.md`) to ensure project-specific conventions (language, test framework, directory structure) are respected.

### 3.7 Resume

If a spec session is interrupted (context reset, crash, Ctrl-C):

1. `shikki spec --resume` checks `~/.config/shiki/spec-sessions/` for incomplete sessions
2. Each session file records: flowItemId, current phase, partial output path, timestamp
3. Resume re-enters the pipeline at the interrupted phase
4. Stale sessions (>24h) are auto-cleaned with a warning

### 3.8 Spec Completion Triggers

When a spec completes successfully:

1. **FlowItem transition:** `decided` (or `raw`) -> `specced`
2. **ShikiDB plan record:** POST to `/api/plans` with full metadata
3. **Inbox item creation:** POST to `/api/inbox` (or equivalent) with type `spec_review`
4. **CoreEvent emission:** `CoreEvent.specCompleted(featureId:, specPath:, lineCount:)`
5. **ntfy notification:** Push to `shiki` topic: "Spec ready: {title} ({lines} lines). Review in inbox."

---

## 4. Files to Create

### Wizard

| File | Package | Description | LOC Est. |
|------|---------|-------------|----------|
| `Sources/shikki/Commands/WizardCommand.swift` | shikki CLI | ArgumentParser command, level orchestrator | ~180 |
| `Sources/ShikiCtlKit/Wizard/WizardLevel.swift` | ShikiCtlKit | Level protocol + 9 level implementations | ~300 |
| `Sources/ShikiCtlKit/Wizard/WizardProgress.swift` | ShikiCtlKit | Progress persistence (JSON file) | ~80 |
| `Sources/ShikiCtlKit/Wizard/WizardRenderer.swift` | ShikiCtlKit | Terminal output: intro, reward, unlock beats | ~120 |
| `Sources/ShikiCtlKit/Services/WorkspaceScanner.swift` | ShikiCtlKit | Scan directory for git repos | ~60 |
| `Sources/ShikiCtlKit/Services/CompanyBootstrapper.swift` | ShikiCtlKit | Create companies from discovered projects | ~70 |
| `Sources/ShikiCtlKit/Services/LLMProviderDetector.swift` | ShikiCtlKit | Detect LLM from env vars / known URLs | ~50 |
| **Wizard subtotal** | | | **~860** |

### Flow State Machine

| File | Package | Description | LOC Est. |
|------|---------|-------------|----------|
| `Sources/ShikiCore/Flow/FlowStage.swift` | ShikiCore | Stage enum + terminal state detection | ~40 |
| `Sources/ShikiCore/Flow/FlowItem.swift` | ShikiCore | FlowItem struct + FlowSource enum | ~50 |
| `Sources/ShikiCore/Flow/FlowEngine.swift` | ShikiCore | Actor: transitions, queries, quick lane | ~200 |
| `Sources/ShikiCore/Flow/FlowTransitionValidator.swift` | ShikiCore | Valid transition table + validation | ~90 |
| `Sources/ShikiCore/Flow/FlowLifecycleBridge.swift` | ShikiCore | Observer: FeatureLifecycle -> FlowItem sync | ~80 |
| `Sources/ShikiCore/Flow/FlowEvent.swift` | ShikiCore | CoreEvent factories for flow transitions | ~60 |
| `src/routes/flow-items.ts` | Backend (Deno) | CRUD + transition endpoints | ~120 |
| `src/migrations/007_flow_items.sql` | Backend (Deno) | DDL for flow_items + flow_transitions | ~30 |
| **FSM subtotal** | | | **~670** |

### Spec CLI

| File | Package | Description | LOC Est. |
|------|---------|-------------|----------|
| `Sources/shikki/Commands/SpecCommand.swift` | shikki CLI | ArgumentParser command, input resolution | ~130 |
| `Sources/ShikiCtlKit/Spec/SpecRunner.swift` | ShikiCtlKit | Orchestrates the 8-phase pipeline via AgentProvider | ~150 |
| `Sources/ShikiCtlKit/Spec/SpecPromptBuilder.swift` | ShikiCtlKit | Builds the agent prompt with context injection | ~100 |
| `Sources/ShikiCtlKit/Spec/SpecSessionManager.swift` | ShikiCtlKit | Resume support: save/load interrupted sessions | ~70 |
| `Sources/ShikiCtlKit/Spec/InputResolver.swift` | ShikiCtlKit | UUID / #N / free text → FlowItem | ~80 |
| **Spec CLI subtotal** | | | **~530** |

### **Grand total: ~2,060 LOC**

---

## 5. Tests

### Wizard Tests

| Test File | Tests | What It Covers |
|-----------|-------|----------------|
| `WizardProgressTests.swift` | 8 | Save/load/resume, level completion, version migration, idempotency |
| `WizardLevelTests.swift` | 10 | Each level's 4-beat rhythm, artifact detection, skip-if-exists |
| `WorkspaceScannerTests.swift` | 5 | Git repo detection, project type inference, empty dir handling |
| `CompanyBootstrapperTests.swift` | 4 | Company creation, duplicate detection, API failure graceful |
| `LLMProviderDetectorTests.swift` | 4 | Env var detection, URL probing, fallback |
| **Wizard test subtotal** | **31** | |

### Flow FSM Tests

| Test File | Tests | What It Covers |
|-----------|-------|----------------|
| `FlowStageTests.swift` | 6 | Enum raw values, terminal state detection, Codable round-trip |
| `FlowTransitionValidatorTests.swift` | 14 | Every valid transition, every invalid transition, quick lane path |
| `FlowEngineTests.swift` | 10 | Create item, transition, query by stage/company, concurrent access |
| `FlowLifecycleBridgeTests.swift` | 6 | Lifecycle done -> inbox, lifecycle failed -> failed, no double-fire |
| `FlowQuickLaneTests.swift` | 5 | Escalation at >3 files, escalation at >30min, --force-quick bypass |
| **FSM test subtotal** | **41** | |

### Spec CLI Tests

| Test File | Tests | What It Covers |
|-----------|-------|----------------|
| `InputResolverTests.swift` | 6 | UUID lookup, #N shorthand, free text creation, invalid input |
| `SpecPromptBuilderTests.swift` | 4 | Context injection, project adapter inclusion, decision history |
| `SpecRunnerTests.swift` | 5 | Happy path, SpecGate failure, resume from checkpoint, timeout |
| `SpecSessionManagerTests.swift` | 4 | Save/load/clean stale sessions, concurrent session prevention |
| `SpecCommandIntegrationTests.swift` | 3 | End-to-end: text input -> spec file + DB record + inbox item |
| **Spec CLI test subtotal** | **22** | |

### **Total tests: ~94**

---

## 6. Build Order

The three components have dependencies:

```
FlowStage/FlowItem (pure types, no deps)
    ↓
FlowTransitionValidator (depends on FlowStage)
    ↓
FlowEngine (depends on FlowItem, Validator, EventPersisting)
    ↓
FlowLifecycleBridge (depends on FlowEngine, FeatureLifecycle)
    ↓
SpecCommand + SpecRunner (depends on FlowEngine, AgentProvider)
    ↓
WizardCommand (depends on FlowEngine for L1-Boss, SpecRunner for L3)
```

**Wave 1 (parallel):**
- FlowStage, FlowItem, FlowSource, FlowEvent — pure types (~150 LOC, ~6 tests)
- WorkspaceScanner, LLMProviderDetector — standalone services (~110 LOC, ~9 tests)
- Backend migration 007 + flow-items route (~150 LOC)

**Wave 2 (parallel):**
- FlowTransitionValidator (~90 LOC, ~14 tests)
- CompanyBootstrapper (~70 LOC, ~4 tests)
- InputResolver (~80 LOC, ~6 tests)

**Wave 3:**
- FlowEngine (~200 LOC, ~10 tests)
- SpecPromptBuilder (~100 LOC, ~4 tests)

**Wave 4 (parallel):**
- FlowLifecycleBridge (~80 LOC, ~6 tests)
- SpecRunner + SpecSessionManager (~220 LOC, ~9 tests)
- SpecCommand (~130 LOC, ~3 tests)

**Wave 5:**
- WizardLevel + WizardProgress + WizardRenderer (~500 LOC, ~18 tests)
- WizardCommand (~180 LOC, ~5 tests)

**Wave 6:**
- FlowQuickLane escalation guard (~60 LOC, ~5 tests)
- Integration tests (~4 tests)

---

## 7. Open Questions for @Daimyo

1. **Wizard Level 4 safety** — `shikki run` dispatches a real agent. Should the wizard use `--dry-run` for Level 4, or is a real (small) dispatch acceptable during onboarding?
2. **Wizard Level 7 safety** — `shikki ship` releases for real. Should the wizard always use `--dry-run` here, or trust the user to pick a safe target?
3. **Flow items table vs. extending backlog_items** — this spec proposes a separate `flow_items` table. Alternative: add a `stage` column to the future `backlog_items` table and track the full lifecycle there. Separate table is cleaner but means backlog items and flow items are different entities that reference each other.
4. **Backend route ownership** — the `flow-items.ts` route is in the Deno backend. Should this block on ShikiMCP migration (typed MCP instead of REST), or build REST now and migrate later?
