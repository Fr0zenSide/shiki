# Feature: Scoped Testing — TPDD with Targeted Test Runs

> Created: 2026-03-19 | Status: Spec Draft | Owner: @Daimyo
> Priority: **P0** — affects every implementation cycle velocity
> Package: `packages/ShikiCore/` (TestPlan + PipelineRunner integration)
> Depends on: Epic Branching (features/shiki-epic-branching.md)

---

## Context

Today's 6-wave session ran `swift test` repeatedly across 248+ tests in shiki-ctl, even when working on ShikiMCP (a completely separate package). Each full test run costs 30-60 seconds. Over 6 waves with multiple TDD cycles, that's 10+ minutes wasted running tests that can't possibly fail from the current change.

TDD is mandatory. But TDD means "run the tests that matter for what you're building," not "run every test in the monorepo every time."

## Problem

1. **Full test suite on every change** — `swift test` runs ALL targets. Building ShikiMCP doesn't need shiki-ctl's 248 tests.
2. **No scope declaration** — agents don't know which tests are relevant to their wave/task. They run everything "to be safe."
3. **Velocity tax** — 30-60s per run × 20+ TDD cycles per wave = 10-20 minutes of pure waste per wave.
4. **Full suite is still needed** — but only ONCE, at /pre-pr on the epic branch. Not during development.

## Solution: Test Scope Declaration + Targeted Runs

### The Flow

```
Feature Start
    │
    ├── 1. SCOPE DECLARATION
    │   Identify: which package? which files? which test targets?
    │   Output: TestScope { package, testFilter, files }
    │
    ├── 2. TDD CYCLE (per task)
    │   Write test → run SCOPED tests → implement → run SCOPED tests → green
    │   Command: swift test --package-path <pkg> --filter <Suite>
    │   Fast: 1-5 seconds instead of 30-60
    │
    ├── 3. WAVE COMPLETE
    │   Run scoped tests one final time → commit
    │   Still scoped — not full suite
    │
    └── 4. /PRE-PR ON EPIC
        Run FULL test suite across ALL packages
        First time all tests run together
        Failures → fix/epic-pre-pr branch → autofix → re-run
        Green → PR to develop
```

### Business Rules

**BR-01**: Every wave/task MUST declare a `TestScope` before writing any code. The scope defines: target package, test filter pattern (suite name or file glob), and expected new test count.

**BR-02**: During TDD cycles, agents run ONLY the scoped tests. Never `swift test` without `--filter` or `--package-path` during development. The full suite is explicitly forbidden during wave implementation.

**BR-03**: The scoped test command MUST complete in under 10 seconds. If it takes longer, the scope is too broad — narrow it.

**BR-04**: New tests written during a wave MUST be within the declared scope. If a change requires tests outside the scope, that's a scope change — document it and expand the TestScope.

**BR-05**: At wave completion (before commit), run the scoped tests one final time. This is the "wave green check." Not the full suite.

**BR-06**: The FULL test suite runs exactly ONCE per epic: at `/pre-pr` time on the epic branch. This is the first time all packages are tested together.

**BR-07**: If the full suite fails at /pre-pr, create `fix/epic-pre-pr` targeting the epic branch. Fix failures, run full suite again. This branch is part of the epic scope.

**BR-08**: The TestScope is stored in the DependencyTree's WaveNode. Each wave knows its test filter. The PipelineRunner uses this to run scoped tests during gate evaluation.

**BR-09**: Test scope format:
```
Package: packages/ShikiMCP
Filter: ShikiMCPTests
Files: Sources/ShikiMCP/**/*.swift
Expected new tests: ~25
Run command: swift test --package-path packages/ShikiMCP
```

For shiki-ctl with a specific suite:
```
Package: tools/shiki-ctl
Filter: ShipGateTests,ShipServiceTests,VersionBumperTests,ChangelogGeneratorTests
Files: Sources/ShikiCtlKit/Services/Ship*.swift, Sources/ShikiCtlKit/Services/Version*.swift, Sources/ShikiCtlKit/Services/Changelog*.swift
Expected new tests: ~24
Run command: swift test --package-path tools/shiki-ctl --filter "ShipGateTests|ShipServiceTests|VersionBumperTests|ChangelogGeneratorTests"
```

**BR-10**: The TestScope is validated at wave start: the filter pattern must match at least one existing test suite (or be a new suite that will be created). Invalid scopes fail fast.

**BR-11**: Coverage check at /pre-pr: changed files in the epic diff must have corresponding test files. This catches the case where wave A changes a file but wave B's scope didn't include regression tests for it.

**BR-12**: `shiki ship --epic` includes test scope summary in the changelog: "X tests added across Y scopes, full suite green at pre-pr."

## Impact on ShikiCore

### WaveNode Changes

```swift
// WaveNode already exists — add testScope
public struct WaveNode: Codable, Sendable, Identifiable {
    // ... existing fields ...
    public var testScope: TestScope?  // NEW
}

public struct TestScope: Codable, Sendable {
    public let packagePath: String        // "packages/ShikiMCP"
    public let filterPattern: String      // "ShikiMCPTests" or "ShipGateTests|VersionBumperTests"
    public let sourceGlob: String         // "Sources/ShikiMCP/**/*.swift"
    public let expectedNewTests: Int      // ~25

    /// Build the scoped test command
    public var runCommand: String {
        if filterPattern.isEmpty {
            return "swift test --package-path \(packagePath)"
        }
        return "swift test --package-path \(packagePath) --filter \"\(filterPattern)\""
    }
}
```

### PipelineRunner Changes

```swift
// QualityGate uses TestScope instead of full suite
public struct QualityGate: PipelineGate {
    let testScope: TestScope?  // nil = full suite (pre-pr mode)

    public func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
        let command = testScope?.runCommand ?? "swift test"
        let result = try await context.shell(command)
        // ...
    }
}
```

### TestPlan Integration

```swift
// TestPlan already has scenarios — add scope
public struct TestPlan: Codable, Sendable {
    // ... existing fields ...
    public var scope: TestScope?  // NEW — which tests to run during dev
}
```

### /pre-pr Gate 3 Change

Gate 3 (Test Coverage) gains two modes:
- **Wave mode** (during development): run `testScope.runCommand` — fast, scoped
- **Epic mode** (at /pre-pr): run `swift test` for ALL packages — full suite, one time

```swift
// In pre-pr pipeline
if isEpicPrePR {
    // Full suite: every package
    for package in ["packages/ShikiCore", "packages/ShikiMCP", "tools/shiki-ctl"] {
        let result = try await context.shell("swift test --package-path \(package)")
        // collect results
    }
} else {
    // Scoped: only this wave's tests
    let result = try await context.shell(wave.testScope.runCommand)
}
```

## Velocity Impact (measured from today's session)

| Metric | Full Suite | Scoped | Savings |
|--------|-----------|--------|---------|
| shiki-ctl test run | ~30-60s | ~2-5s (filtered) | 90% |
| ShikiMCP test run | ~5s | ~2s (already scoped) | 60% |
| ShikiCore test run | ~3s | ~1s (filtered) | 67% |
| TDD cycles per wave | ~10 | ~10 | — |
| Total test time per wave | ~5-10min | ~20-50s | **90%** |
| Full suite (once at /pre-pr) | ~60s | ~60s | 0% (intentional) |

Over 6 waves: **30-60 minutes saved** in pure test execution time.

## Implementation Plan

### Task 1: Add TestScope to WaveNode
- File: `packages/ShikiCore/Sources/ShikiCore/Planning/WaveNode.swift`
- Add `TestScope` struct + `testScope` property on WaveNode
- Test: TestScope.runCommand builds correct filter command

### Task 2: QualityGate scoped mode
- File: `packages/ShikiCore/Sources/ShikiCore/Pipeline/QualityGate.swift`
- Accept optional `TestScope` — scoped when present, full when nil
- Test: QualityGate with scope runs filtered command, without scope runs full

### Task 3: /pre-pr epic mode (Gate 3)
- Update pre-pr pipeline skill to detect epic branch
- Epic mode: iterate all packages, run full suite
- Wave mode: use declared scope
- On failure: create `fix/epic-pre-pr` branch targeting epic

### Task 4: Scope validation at wave start
- Before any TDD cycle, validate the TestScope filter matches existing suites
- Warn if scope is too broad (>50 tests) — suggest narrowing

## Success Criteria

1. No `swift test` without `--filter` or `--package-path` during wave implementation
2. TDD cycle under 10 seconds (scoped run)
3. Full suite runs exactly once per epic (at /pre-pr)
4. /pre-pr failures produce `fix/epic-pre-pr` branch
5. TestScope stored in WaveNode, queryable from DependencyTree

---

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-19 | Spec | @Daimyo | Draft | From session observation — 30-60s test runs during TDD |
| 2026-03-19 | Review | @Sensei | CONDITIONAL | Add test count assertion, scope on PipelineContext not gate, remove from TestPlan |
| 2026-03-19 | Review | @Hanami | CONDITIONAL | Soften BR-02 forbidden→not-required, add smoke test option |
| 2026-03-19 | Review | @Kintsugi | PASS | "Rescues TDD from the slow loop that was quietly killing it" |

## Post-Review Corrections

### Critical (must fix before implementation)
1. **Remove TestScope from TestPlan** — belongs on WaveNode only. TestPlan is specification, not execution.
2. **Add Task 5: Test count assertion** — parse scoped test output, assert count >= expectedNewTests. Catches silent --filter typo (0 tests = false green).
3. **Soften BR-02** — change "forbidden" to "not required during development." Developer agency preserved.
4. **Move TestScope injection** from QualityGate constructor to PipelineContext. Keeps gates stateless.
5. **Add expected-vs-actual test count report** at wave-end. Not a blocker, but never silent divergence.
6. **Clarify BR-11** — "corresponding test file" = filename convention (Foo.swift → FooTests.swift).
7. **Single-package per wave** recommended. If multi-package needed, support `[TestScope]` on WaveNode.

### Revised Task List (v1)
1. TestScope struct on WaveNode
2. QualityGate scoped mode (via PipelineContext)
3. /pre-pr epic mode (full suite across all packages)
4. Scope validation at wave start
5. Test count assertion (parse output, catch zero-match)
