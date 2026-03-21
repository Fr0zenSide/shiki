# Feature: shiki ship
> Created: 2026-03-19 | Status: Phase 3 — Business Rules | Owner: @Daimyo
> Agent: @Kenshi (Release Engineer)

## Context

Shipping is manual and fragmented — git tag, changelog, version bump, PR, each step done by hand. gstack's `/ship` proved the one-command pattern works (10K LOC/week claim). We need the same velocity with Shiki's depth: event bus integration, persistent release history, risk scoring from DB, and zero terminal babysitting.

## Inspiration

### Brainstorm Results

| # | Idea | Source | Verdict |
|---|------|--------|---------|
| 1 | Pipeline-of-Gates Service (`ShipGate` protocol, `DryRunContext`) | @Sensei | BUILD |
| 2 | ShipEvent as ShikiEvent subtype (full event bus integration) | @Sensei | BUILD |
| 3 | Silent River (single status line + ntfy, no scrolling output) | @Hanami | BUILD |
| 4 | Preflight Glow (one-screen manifest, one keystroke to launch) | @Hanami | BUILD |
| 5 | Release Risk Score with Memory (DB-powered go/no-go) | @Shogun | BUILD |
| 6 | Ship Log, Not Ship Count (mandatory "why" per release) | @Kintsugi | BUILD |
| 7 | Rewind Tape (retroactive pipeline trace) | @Hanami | v1.1 |
| 8 | Multi-Stage Changelog with Event Replay | @Shogun | v1.1 |
| 9 | Bisect-Safe Release Gate (per-commit test verification) | @Shogun | DEFER |
| 10 | Pause Before Release (mandatory reflection step) | @Kintsugi | DEFER (covered by Preflight Glow) |

### Selected Ideas (v1)
1. Pipeline-of-Gates architecture
2. ShipEvent event bus integration
3. Silent River UX
4. Preflight Glow manifest
5. Release Risk Score from DB
6. Ship Log with mandatory "why"

## Synthesis

**Goal**: `shiki ship` collapses release engineering into one command — quality-gated, event-driven, zero babysitting.

**Scope (v1)**:
- `ShipCommand` in shiki-ctl with `--dry-run` and `--target` (defaults to develop)
- `ShipService` as pipeline-of-gates (`ShipGate` protocol)
- 8 gates: CleanBranch, Test, Coverage, Risk, Changelog, VersionBump, Commit, PR
- `ShipEvent: ShikiEvent` emitted at each step → event bus → DB
- Preflight manifest (single-screen summary before launch)
- Silent River (single status line during execution, ntfy on done/fail)
- Ship log entry with mandatory "why" field
- Release risk score from DB (graceful degradation if DB unavailable)

**Out of scope**: Bisect-safe per-commit verification, multi-stage changelog with event replay, rewind tape, automated commit splitting.

**Success criteria**:
- Feature branch → PR on develop in < 2 minutes (excluding test runtime)
- `--dry-run` shows full plan without side effects
- Every gate independently testable (Swift Testing)
- ShipEvents queryable in DB (`shiki ship --history`)
- ntfy notification on success/failure

**Dependencies**: ShikiKit (ShikiEvent), PRRiskEngine, Shiki DB HTTP, ntfy

## Business Rules

### Pipeline Flow

```
shiki ship [--dry-run] [--target develop] [--why "reason"]
    │
    ├── Preflight: show manifest, wait for Enter (skip in --dry-run)
    │
    ├── Gate 1: CleanBranchGate
    ├── Gate 2: TestGate
    ├── Gate 3: CoverageGate
    ├── Gate 4: RiskGate
    ├── Gate 5: ChangelogGate
    ├── Gate 6: VersionBumpGate
    ├── Gate 7: CommitGate
    ├── Gate 8: PRGate
    │
    ├── Ship Log: append entry
    └── ntfy: push result
```

### Rules

BR-01: `shiki ship` MUST verify the working tree is clean (no uncommitted changes, no untracked files in src/) before proceeding. Fail immediately if dirty.

BR-02: `shiki ship` MUST run the full test suite. Test failure is a hard gate — no override, no `--force`, no exceptions. If tests fail, ship aborts.

BR-03: Coverage check is a soft gate. If coverage drops below the project threshold (configurable, default 80%), emit a WARNING but do not block. If coverage drops by more than 5% from the previous release, emit a RISK and include in risk score.

BR-04: RiskGate reuses PRRiskEngine to compute a risk score for the diff. Score is informational — displayed in preflight and PR body. Does not block shipping (the human saw it in preflight and chose to proceed).

BR-05: ChangelogGate scans commits since the last git tag. Groups by Conventional Commit prefix: `feat:` → Added, `fix:` → Fixed, `refactor:` → Changed, `chore:` → Maintenance. Entries are commit subject lines. If no commits have conventional prefixes, fall back to raw commit subjects under "Changes."

BR-06: VersionBumpGate determines the next version from commit prefixes since last tag:
- Any `BREAKING CHANGE:` or `!:` suffix → major bump
- Any `feat:` → minor bump
- Only `fix:`/`chore:`/`refactor:` → patch bump
- `--version <semver>` overrides auto-detection

BR-07: CommitGate creates a single merge-ready commit (or leaves existing commits as-is, depending on `--squash` flag). Default: no squash (preserve commit history for bisect).

BR-08: PRGate creates a PR targeting `--target` (default: develop). PR body includes: version, changelog, risk score, test results, coverage delta, ship log "why" entry. Uses `gh pr create`.

BR-09: `--dry-run` runs ALL gates but replaces side-effecting operations with no-ops. Same pipeline, same validation, same output — just no git writes, no PR creation. DryRunContext is injected, not a separate code path.

BR-10: Every gate emits a `ShipEvent` on start, pass, or fail. Events flow through the InProcessEventBus. If Shiki DB is available, events are persisted. If not, pipeline continues without persistence (graceful degradation).

BR-11: `--target` MUST be `develop` or a `release/*` branch. Attempting to target `main` directly is rejected with an error explaining git flow.

BR-12: Ship log entry is appended to `~/.shiki/ship-log.md` with: date, version, project, branch, "why" field, risk score, gate results summary. If `--why` is not provided, prompt interactively (not skippable — @Kintsugi's "Ship Log, Not Ship Count" rule).

BR-13: Preflight manifest displays: current branch, target branch, version (current → next), commit count, test count, coverage %, risk score (if DB available), changelog preview (first 5 entries). Waits for Enter to proceed. In `--dry-run`, shows manifest but does not wait.

BR-14: During execution, output is a single persistent status line: `[gate N/8] GateName... ✓ (elapsed)`. No scrolling. Previous gate results overwrite to a compact summary above the active line. ntfy push on completion (success or failure with gate name).

BR-15: `shiki ship --history` queries Shiki DB for past ShipEvents and displays: date, version, project, risk score, gate pass/fail, duration. If DB unavailable, reads from `~/.shiki/ship-log.md` as fallback.

BR-16: If any gate fails, the pipeline aborts immediately. The abort event is persisted. The status line shows which gate failed and why. ntfy push includes the failure reason.

### Event Types

```swift
enum ShipEvent: ShikiEvent {
    case shipStarted(branch: String, target: String)
    case gateStarted(gate: String, index: Int)
    case gatePassed(gate: String, index: Int, duration: Duration)
    case gateFailed(gate: String, index: Int, reason: String)
    case shipCompleted(version: String, prURL: String?, duration: Duration)
    case shipAborted(gate: String, reason: String)
}
```

## Test Plan

### Unit Tests — ShipGate Protocol

```
BR-01 → test_cleanBranchGate_dirtyWorkingTree_fails()
BR-01 → test_cleanBranchGate_cleanTree_passes()
BR-02 → test_testGate_testsPass_passes()
BR-02 → test_testGate_testsFail_failsHard()
BR-03 → test_coverageGate_aboveThreshold_passes()
BR-03 → test_coverageGate_belowThreshold_warnsButPasses()
BR-03 → test_coverageGate_dropMoreThan5Percent_emitsRisk()
BR-05 → test_changelogGate_conventionalCommits_groupsCorrectly()
BR-05 → test_changelogGate_noConventionalCommits_fallsBackToRaw()
BR-06 → test_versionBumpGate_breakingChange_majorBump()
BR-06 → test_versionBumpGate_feat_minorBump()
BR-06 → test_versionBumpGate_fixOnly_patchBump()
BR-06 → test_versionBumpGate_manualOverride_usesProvided()
BR-11 → test_prGate_targetMain_rejectsWithError()
BR-11 → test_prGate_targetDevelop_passes()
```

### Unit Tests — ShipService Pipeline

```
BR-09 → test_shipService_dryRun_noSideEffects()
BR-09 → test_shipService_dryRun_sameValidationAsFull()
BR-10 → test_shipService_emitsEventsPerGate()
BR-10 → test_shipService_dbUnavailable_continuesWithoutPersistence()
BR-16 → test_shipService_gateFailure_abortsImmediately()
BR-16 → test_shipService_gateFailure_emitsAbortEvent()
```

### Unit Tests — Supporting

```
BR-12 → test_shipLog_appendsEntry()
BR-12 → test_shipLog_missingWhy_promptsInteractively()
BR-13 → test_preflightManifest_displaysAllFields()
BR-14 → test_statusRenderer_singleLineOutput()
BR-15 → test_shipHistory_queriesDB()
BR-15 → test_shipHistory_dbUnavailable_fallsToLogFile()
```

### Integration Tests

```
BR-08 → test_prGate_createsRealPR_targeting_develop()  // needs git repo fixture
BR-07 → test_commitGate_squash_createsOneCommit()
BR-07 → test_commitGate_noSquash_preservesHistory()
```

## Architecture

### Files to Create/Modify

| Path | Purpose | Status |
|------|---------|--------|
| `Sources/ShikiCtlKit/Services/ShipService.swift` | Pipeline orchestrator, gate runner | New |
| `Sources/ShikiCtlKit/Services/ShipGate.swift` | `ShipGate` protocol + all gate implementations | New |
| `Sources/ShikiCtlKit/Services/ShipEvent.swift` | `ShipEvent: ShikiEvent` enum | New |
| `Sources/ShikiCtlKit/Services/ShipLog.swift` | Ship log append/read (file-based) | New |
| `Sources/ShikiCtlKit/Services/ChangelogGenerator.swift` | Conventional Commits → grouped changelog | New |
| `Sources/ShikiCtlKit/Services/VersionBumper.swift` | Semver detection from commit prefixes | New |
| `Sources/shiki-ctl/Commands/ShipCommand.swift` | CLI command (ArgumentParser) | New |
| `Sources/shiki-ctl/Formatters/ShipRenderer.swift` | Preflight manifest + status line | New |
| `Tests/ShikiCtlKitTests/ShipServiceTests.swift` | Pipeline tests | New |
| `Tests/ShikiCtlKitTests/ShipGateTests.swift` | Per-gate tests | New |
| `Tests/ShikiCtlKitTests/ChangelogGeneratorTests.swift` | Changelog parsing tests | New |
| `Tests/ShikiCtlKitTests/VersionBumperTests.swift` | Version bump logic tests | New |

### Key Protocols

```swift
/// A single quality gate in the ship pipeline
protocol ShipGate {
    var name: String { get }
    var index: Int { get }
    func evaluate(context: ShipContext) async throws -> GateResult
}

enum GateResult {
    case pass(detail: String?)
    case warn(reason: String)
    case fail(reason: String)
}

/// Injected context — real or dry-run
protocol ShipContext {
    var isDryRun: Bool { get }
    var branch: String { get }
    var target: String { get }
    var projectRoot: URL { get }
    func shell(_ command: String) async throws -> String
    func emit(_ event: ShipEvent) async
}
```

### Data Flow

```
ShipCommand (CLI)
    │ parse args
    ↓
ShipService.run(context:)
    │ build gate pipeline
    ↓
[CleanBranchGate → TestGate → CoverageGate → RiskGate → ChangelogGate → VersionBumpGate → CommitGate → PRGate]
    │ each gate: evaluate(context:) → emit ShipEvent
    ↓
ShipRenderer (single status line)
    │ observes events
    ↓
InProcessEventBus → ShikiDB (if available)
    │
    ↓
ntfy push (on complete/fail)
```

### DI Registration

- `ShipService` — registered in StoreFactory
- `ShipRenderer` — instantiated by ShipCommand (presentation layer)
- `ShipContext` — `RealShipContext` or `DryRunShipContext` based on `--dry-run` flag
- `RiskGate` — self-contained (PRRiskEngine extracted to ShikiQA — no longer in shiki-ctl)

### Post-Clean Adaptation

PRRiskEngine, PRReviewEngine, and all PR-related services are being extracted to a separate ShikiQA project (`chore: extract ShikiQA`). After the clean:
- RiskGate is **self-contained** — lightweight diff risk scorer, not wrapping PRRiskEngine
- No dependency on ShikiQA from ShipService
- Ship can import ShikiQA later if deeper risk scoring is needed (v1.1)

## Execution Plan

### Pre-Implementation Checklist

1. Wait for the ShikiQA extraction clean to be committed on `feature/tmux-status-plugin`
2. Verify `swift build --package-path tools/shiki-ctl` compiles clean
3. Verify `swift test --package-path tools/shiki-ctl` passes (check current test count)
4. Create worktree: `git worktree add .claude/worktrees/ship feature/tmux-status-plugin -b feature/shiki-ship`
5. Run `scripts/worktree-setup.sh` to fix local SPM paths
6. All work happens in the worktree — never touch the main worktree

### Task 1: ShipEvent enum + ShipContext protocol

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipEvent.swift` (new)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipServiceTests.swift` → `test_shipEvent_casesExist()`
- **Implement**:
  - `ShipEvent` enum with cases: `shipStarted`, `gateStarted`, `gatePassed`, `gateFailed`, `shipCompleted`, `shipAborted`
  - `ShipContext` protocol with: `isDryRun`, `branch`, `target`, `projectRoot`, `shell(_:)`, `emit(_:)`
  - `GateResult` enum: `.pass`, `.warn`, `.fail`
  - `ShipGate` protocol: `name`, `index`, `evaluate(context:) async throws -> GateResult`
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipServiceTests` → 1 test passing
- **BRs**: BR-10 (events), BR-09 (context protocol)
- **Time**: ~3 min

### Task 2: RealShipContext + DryRunShipContext

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipEvent.swift` (append)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipServiceTests.swift` → `test_shipService_dryRun_noSideEffects()`
- **Implement**:
  - `RealShipContext`: runs shell commands for real, emits events to bus
  - `DryRunShipContext`: captures shell commands without executing, still emits events
  - Both conform to `ShipContext`
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipServiceTests` → 2 tests passing
- **BRs**: BR-09 (dry-run same pipeline)
- **Time**: ~3 min
- **Depends on**: Task 1

### Task 3: CleanBranchGate

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipGate.swift` (new)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipGateTests.swift` (new) → `test_cleanBranchGate_dirtyWorkingTree_fails()`, `test_cleanBranchGate_cleanTree_passes()`
- **Implement**:
  - `CleanBranchGate: ShipGate` — runs `git status --porcelain` via context.shell, fails if output non-empty
  - Also checks `git diff --cached` for staged changes
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipGateTests` → 2 tests passing
- **BRs**: BR-01
- **Time**: ~3 min
- **Depends on**: Task 1

### Task 4: TestGate

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipGate.swift` (append)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipGateTests.swift` → `test_testGate_testsPass_passes()`, `test_testGate_testsFail_failsHard()`
- **Implement**:
  - `TestGate: ShipGate` — runs test command from project detection (swift test / npm test / deno test)
  - Hard gate: any non-zero exit = `.fail`, no override
  - Parses test count from output for display
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipGateTests` → 4 tests passing
- **BRs**: BR-02
- **Time**: ~3 min
- **Depends on**: Task 1

### Task 5: CoverageGate

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipGate.swift` (append)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipGateTests.swift` → `test_coverageGate_aboveThreshold_passes()`, `test_coverageGate_belowThreshold_warnsButPasses()`, `test_coverageGate_dropMoreThan5Percent_emitsRisk()`
- **Implement**:
  - `CoverageGate: ShipGate` — parses coverage from test output or lcov
  - Soft gate: below threshold = `.warn`, drop >5% = `.warn` with risk flag
  - Configurable threshold (default 80%)
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipGateTests` → 7 tests passing
- **BRs**: BR-03
- **Time**: ~4 min
- **Depends on**: Task 1

### Task 6: VersionBumper

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/VersionBumper.swift` (new)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/VersionBumperTests.swift` (new) → `test_versionBumpGate_breakingChange_majorBump()`, `test_versionBumpGate_feat_minorBump()`, `test_versionBumpGate_fixOnly_patchBump()`, `test_versionBumpGate_manualOverride_usesProvided()`
- **Implement**:
  - `VersionBumper` struct: takes commit messages array, returns next semver
  - Parses Conventional Commit prefixes: `BREAKING`/`!:` → major, `feat:` → minor, else → patch
  - `bump(from: String, commits: [String], override: String?) -> String`
- **Verify**: `swift test --package-path tools/shiki-ctl --filter VersionBumperTests` → 4 tests passing
- **BRs**: BR-06
- **Time**: ~3 min

### Task 7: ChangelogGenerator

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ChangelogGenerator.swift` (new)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ChangelogGeneratorTests.swift` (new) → `test_changelogGate_conventionalCommits_groupsCorrectly()`, `test_changelogGate_noConventionalCommits_fallsBackToRaw()`
- **Implement**:
  - `ChangelogGenerator` struct: takes commit subjects, groups by prefix
  - `feat:` → "Added", `fix:` → "Fixed", `refactor:` → "Changed", `chore:` → "Maintenance"
  - Fallback: no conventional prefixes → list under "Changes"
  - Returns structured `ChangelogEntry` array + markdown string
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ChangelogGeneratorTests` → 2 tests passing
- **BRs**: BR-05
- **Time**: ~3 min

### Task 8: RiskGate (self-contained) + VersionBumpGate + ChangelogGate + CommitGate + PRGate

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipGate.swift` (append)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipGateTests.swift` → `test_prGate_targetMain_rejectsWithError()`, `test_prGate_targetDevelop_passes()`
- **Implement**:
  - `RiskGate: ShipGate` — lightweight diff size + file count scorer (no PRRiskEngine dependency). Informational only (always `.pass` with detail)
  - `VersionBumpGate: ShipGate` — wraps VersionBumper, emits next version
  - `ChangelogGate: ShipGate` — wraps ChangelogGenerator
  - `CommitGate: ShipGate` — optional squash via `git merge --squash` or passthrough
  - `PRGate: ShipGate` — runs `gh pr create` targeting `--target`. Rejects `main` (BR-11). Uses context.shell (no-op in dry-run)
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipGateTests` → 9+ tests passing
- **BRs**: BR-04, BR-06, BR-05, BR-07, BR-08, BR-11
- **Time**: ~5 min
- **Depends on**: Tasks 6, 7

### Task 9: ShipService (pipeline orchestrator)

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipService.swift` (new)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipServiceTests.swift` → `test_shipService_emitsEventsPerGate()`, `test_shipService_gateFailure_abortsImmediately()`, `test_shipService_gateFailure_emitsAbortEvent()`, `test_shipService_dryRun_sameValidationAsFull()`, `test_shipService_dbUnavailable_continuesWithoutPersistence()`
- **Implement**:
  - `ShipService`: takes ordered array of `ShipGate`, iterates with context
  - On each gate: emit `gateStarted`, evaluate, emit `gatePassed`/`gateFailed`
  - On fail: emit `shipAborted`, return immediately
  - On all pass: emit `shipCompleted`
  - DB persistence: POST events if available, skip silently if not
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipServiceTests` → 7+ tests passing
- **BRs**: BR-10, BR-16, BR-09
- **Time**: ~5 min
- **Depends on**: Tasks 1-8

### Task 10: ShipLog

- **Files**: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipLog.swift` (new)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipServiceTests.swift` → `test_shipLog_appendsEntry()`, `test_shipLog_missingWhy_promptsInteractively()`, `test_shipHistory_queriesDB()`, `test_shipHistory_dbUnavailable_fallsToLogFile()`
- **Implement**:
  - `ShipLog`: append entries to `~/.shiki/ship-log.md` (date, version, project, branch, why, risk score, gate summary)
  - `readHistory()`: query DB first, fall back to file
  - Mandatory "why" field — if nil, return error (CLI layer handles interactive prompt)
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipServiceTests` → 11+ tests passing
- **BRs**: BR-12, BR-15
- **Time**: ~3 min

### Task 11: ShipRenderer (Preflight Glow + Silent River)

- **Files**: `tools/shiki-ctl/Sources/shiki-ctl/Formatters/ShipRenderer.swift` (new)
- **Test**: `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipServiceTests.swift` → `test_preflightManifest_displaysAllFields()`, `test_statusRenderer_singleLineOutput()`
- **Implement**:
  - `renderPreflight(manifest:)` — single-screen: branch, target, version (current → next), commit count, test count, coverage %, risk score, changelog preview (first 5). Uses Rainbow for color.
  - `renderGateProgress(gate:index:total:elapsed:result:)` — single persistent line: `[N/8] GateName... ✓ (Xs)`. Overwrites previous line with ANSI escape.
  - `renderSummary(result:)` — final compact receipt
- **Verify**: `swift test --package-path tools/shiki-ctl --filter ShipServiceTests` → 13+ tests passing
- **BRs**: BR-13, BR-14
- **Time**: ~4 min

### Task 12: ShipCommand (CLI entry point)

- **Files**: `tools/shiki-ctl/Sources/shiki-ctl/Commands/ShipCommand.swift` (new), `tools/shiki-ctl/Sources/shiki-ctl/ShikiCtl.swift` (modify — register subcommand)
- **Test**: Manual — `swift build --package-path tools/shiki-ctl && .build/debug/shiki-ctl ship --dry-run --why "test run"`
- **Implement**:
  - `ShipCommand: AsyncParsableCommand` with options: `--dry-run`, `--target` (default "develop"), `--why`, `--version`, `--squash`, `--history`
  - Builds gate pipeline in order, creates context (Real or DryRun), calls ShipService.run()
  - Renders preflight → waits for Enter (skip in dry-run) → renders gate progress → renders summary
  - Sends ntfy push on complete/fail
  - `--history` mode: calls ShipLog.readHistory(), renders table
- **Verify**: `swift build --package-path tools/shiki-ctl` compiles, `shiki-ctl ship --help` shows options
- **BRs**: BR-09, BR-11, BR-12, BR-13, BR-14, BR-16
- **Time**: ~5 min
- **Depends on**: Tasks 9, 10, 11

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 16/16 BRs mapped to tasks |
| Test Coverage | PASS | 24/24 signatures mapped |
| File Alignment | PASS | 12/12 files covered |
| Task Dependencies | PASS | Linear order, no cycles (1→2→3-8→9→10-11→12) |
| DI Registration | PASS | ShipService in StoreFactory (Task 9) |
| Coordinator Routes | N/A | CLI command, no navigation |
| Task Granularity | PASS | All tasks 3-5 min |
| Testability | PASS | Every task has verify step |
| Worktree Setup | PASS | Pre-implementation checklist defines worktree creation |
| Post-Clean Dependency | PASS | RiskGate self-contained, no ShikiQA import |

**Verdict: PASS** — ready for Phase 6 after ShikiQA clean lands and @Daimyo approves.

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-19 | Phase 1 | @Shogun, @Hanami, @Kintsugi, @Sensei | 10 ideas, 6 selected | Parallel brainstorm |
| 2026-03-19 | Phase 2 | Orchestrator | Synthesized | No Q&A needed — context from research session |
| 2026-03-19 | Phase 3 | @Sensei | 16 BRs drafted | Awaiting @Daimyo approval |
| 2026-03-19 | Phase 4 | @Sensei | 24 test signatures | Unit + integration |
| 2026-03-19 | Phase 5 | @Sensei | 12 files, 2 protocols | Pipeline-of-Gates architecture |
| 2026-03-19 | Phase 5b | @Sensei | 12 tasks, readiness PASS | Adapted: RiskGate self-contained (PRRiskEngine extracted to ShikiQA). Worktree from post-clean branch. |
