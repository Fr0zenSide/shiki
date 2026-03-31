---
title: "ShikkiTestRunner — Architecture-Scoped Parallel Test Execution with SQLite History"
status: spec (validated by @Daimyo 2026-03-31)
priority: P0
project: shikki
created: 2026-03-31
authors: "@shi full team + @Daimyo brainstorm + review"
depends-on:
  - moto-dns-for-code.md (MotoCacheReader for architecture analysis)
relates-to:
  - shiki-scoped-testing.md (TPDD foundation)
  - shikki-native-scheduler.md (parallel execution patterns)
inspiration:
  - "apple/swift lit test runner — timeout per test, REQUIRES: directive, parallel workers"
  - "chromium BigQuery test history — regression detection across commits"
  - "rust compiletest — parallel execution + JSON output"
---

# ShikkiTestRunner

> Every test runs in < 100ms. Every run is recorded. Every failure is traceable to a commit.
> Swift testing Swift. No Python. Powered by Moto.

---

## 1. Problem

1,800+ tests in one SPM target. `swift test` takes 5+ minutes. Logger output from real kernel boot pollutes test results. No history — you can't answer "when did this test start failing?" No per-test timeout — one hung async continuation blocks everything forever.

**Root cause from analysis (2026-03-31)**: Tests that boot the real ShikkiKernel with real services, writing logs to stdout. Individual tests are fast (0.001s) but kernel boot + service lifecycle + logger I/O + retry backoff add minutes of wall-clock time.

---

## 2. Testing Pyramid

```
            /\
           /  \     E2E (full kernel + DB + NATS)
          / 3% \    → CI nightly, pre-release
         /______\
        /        \   SUI (visual regression, snapshots)
       /    7%    \  → pre-release, design changes
      /____________\
     /              \  SCOPED INTEGRATION (Moto groups)
    /     55%        \ → per-scope, architecture-aware
   /___________________\
  /                      \ UNIT (pure logic, zero deps)
 /         35%            \→ always, instant, no mock needed
/___________________________\
```

Unit tests don't need scoping — they're fast, isolated, no deps. The Moto-scoped layer is where the value is: tests that touch real dependency graphs (EventBus, Kernel, NATS) but don't need the full system. SUI sits between scoped integration and E2E — needs real rendering but not the full stack.

---

## 3. Three Test Categories

| Category | What | Speed | SPM Target |
|----------|------|-------|------------|
| **Unit** | Pure logic, no I/O, no kernel, no network | < 100ms each | `ShikkiKitTests` |
| **Integration / E2E** | Kernel boot, service lifecycle, DB calls | < 5s each | `ShikkiIntegrationTests` |
| **SUI / Snapshot** | Visual regression, UI rendering comparison | < 2s each | `ShikkiSnapshotTests` |

---

## 4. Architecture-Scoped Groups (from Moto Cache)

Tests are grouped by architecture scope derived from the Moto cache — **dynamic, architecture-aware grouping**. The Moto cache knows which types depend on which, so tests that touch `EventBus` run with tests that touch `EventRouter`, even if they're in different directories.

This is novel — Linux/Chromium use static directory-based grouping. We use the dependency graph.

```
shikki test --scopes

Available test scopes (from .moto cache):
  nats           6 files   57 tests   deps: NATSClientProtocol, EventBus
  flywheel       6 files   80 tests   deps: CalibrationStore, RiskScoringEngine
  tui            7 files   89 tests   deps: TerminalOutput, ANSI, PaletteEngine
  safety         1 file    55 tests   deps: BudgetACL, AuditLogger
  codegen       13 files  153 tests   deps: ArchitectureCache, SpecParser
  observatory    3 files   68 tests   deps: DecisionJournal, EventBus
  ship           4 files   79 tests   deps: ShipGate, VersionBumper
  kernel         5 files   49 tests   deps: ShikkiKernel, ManagedService
  answer-engine  5 files   72 tests   deps: BM25Index, SourceChunker
  s3-parser      4 files   72 tests   deps: S3Parser, S3Validator
  blue-flame     3 files   78 tests   deps: FlameEmotion, FlameRenderer
  moto           2 files   45 tests   deps: MotoDotfile, MotoCacheBuilder
  memory         2 files   47 tests   deps: MemoryClassifier, MemoryFileScanner
  unscoped       X files    Y tests   (everything not claimed — safety net)
```

### Scoping Algorithm

```
1. Read .moto cache → get architecture graph (types, deps, modules)
2. For each test file, analyze imports + types used → map to scope
3. Group test files into scopes
4. Verify: every test file appears in exactly one scope
5. Leftovers → "unscoped" group (always runs)
6. Dispatch scopes to parallel workers
```

Equivalent to Swift's `// REQUIRES: swift_stdlib` — but automatic from architecture analysis, not manual annotation.

---

## 5. Where Each Level Runs

```
Sub-agent (worktree):   shikki test --scope <changed>
Pre-PR gate:            shikki test --scope <changed> + deps
Merge to integration:   shikki test --parallel (all scopes)
Release tag:            shikki test --all + E2E + snapshots
```

This is the missing piece in the sub-agent workflow. Agents running `swift test` (full suite, 5+ minutes) instead of testing just their scope caused timeouts and rate limit exhaustion during the v0.3.0-pre dispatch.

---

## 6. Core Engine — Swift's `lit`, in Swift

`lit` (LLVM Integrated Tester) is Python-based. We steal its core ideas and implement natively in Swift:

| lit feature | ShikkiTestRunner equivalent |
|---|---|
| Per-test timeout | `Task.withTimeout` per test event |
| `REQUIRES:` directive | Moto scope (automatic, not manual) |
| Parallel workers | Swift concurrency `TaskGroup` |
| TAP output format | Swift Testing JSON event stream |
| Config per directory | Scope config from Moto cache |
| Exit on first fail | `--fail-fast` flag |

### Event Stream Parser

```swift
// ShikkiTestRunner wraps swift test with structured event stream
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = [
    "test",
    "--parallel",
    "--filter", scope.filter,
    "--experimental-event-stream-output"  // JSON events, not text
]

// Parse events in real-time
for try await line in process.stdout.lines {
    let event = try JSONDecoder().decode(TestEvent.self, from: line.data)
    switch event.kind {
    case .testStarted:
        startTimeout(event.testID, limit: .seconds(5))
    case .testPassed:
        cancelTimeout(event.testID)
        store.record(event, status: .passed)
        reporter.updateProgress(scope)
    case .testFailed:
        cancelTimeout(event.testID)
        store.record(event, status: .failed)
        reporter.showFailure(event)
    }
}
```

The timeout is the killer feature: start a timer on `testStarted`, kill if `testPassed`/`testFailed` doesn't arrive within threshold. No more hung tests blocking everything.

---

## 7. SQLite Persistence

### Temporary DB (per run)

```
/tmp/shikki-test-{run_id}.sqlite
```

Captures raw output per test as it runs. Logger noise goes here, not terminal.

### Persistent DB (project history)

```
{project}/.shikki/test-history.sqlite  (.gitignored)
```

After each run, results merge from tmp → persistent. Indexed by git hash + branch.

### Schema

```sql
CREATE TABLE test_runs (
    run_id TEXT PRIMARY KEY,
    git_hash TEXT NOT NULL,
    branch_name TEXT,               -- "fix/mega-merge-compilation"
    started_at DATETIME NOT NULL,
    finished_at DATETIME,
    total_tests INTEGER,
    passed INTEGER,
    failed INTEGER,
    skipped INTEGER,
    duration_ms INTEGER,
    moto_cache_hash TEXT            -- links to architecture snapshot
);

CREATE TABLE test_groups (
    id INTEGER PRIMARY KEY,
    run_id TEXT REFERENCES test_runs(run_id),
    scope_name TEXT NOT NULL,       -- "nats", "flywheel", "kernel"
    started_at DATETIME,
    finished_at DATETIME,
    total_tests INTEGER,
    passed INTEGER,
    failed INTEGER,
    skipped INTEGER,
    duration_ms INTEGER
);

CREATE TABLE test_results (
    id INTEGER PRIMARY KEY,
    run_id TEXT REFERENCES test_runs(run_id),
    group_id INTEGER REFERENCES test_groups(id),
    test_file TEXT NOT NULL,
    test_name TEXT NOT NULL,
    suite_name TEXT,
    status TEXT CHECK(status IN ('passed', 'failed', 'skipped', 'timeout')),
    duration_ms INTEGER,
    error_message TEXT,
    error_file TEXT,                -- "HeartbeatLoopTests.swift:468:9"
    raw_output TEXT                 -- full captured output including logs
);

CREATE INDEX idx_runs_hash ON test_runs(git_hash);
CREATE INDEX idx_runs_branch ON test_runs(branch_name);
CREATE INDEX idx_results_status ON test_results(status);
CREATE INDEX idx_results_test ON test_results(test_name);
CREATE INDEX idx_results_group ON test_results(group_id);
```

### Key Queries

```sql
-- When did this test start failing?
SELECT r.git_hash, r.branch_name, t.status, t.duration_ms
FROM test_results t JOIN test_runs r ON t.run_id = r.run_id
WHERE t.test_name = 'publishFailureHandled'
ORDER BY r.started_at DESC;

-- Which scope has the most failures this week?
SELECT g.scope_name, SUM(g.failed) as total_failed
FROM test_groups g JOIN test_runs r ON g.run_id = r.run_id
WHERE r.started_at > datetime('now', '-7 days')
GROUP BY g.scope_name ORDER BY total_failed DESC;

-- Regression detection: test was green, now red
SELECT t.test_name, r.git_hash, r.branch_name
FROM test_results t JOIN test_runs r ON t.run_id = r.run_id
WHERE t.status = 'failed'
AND t.test_name IN (
    SELECT t2.test_name FROM test_results t2
    JOIN test_runs r2 ON t2.run_id = r2.run_id
    WHERE t2.status = 'passed'
    ORDER BY r2.started_at DESC LIMIT 1
);
```

---

## 8. TUI Output

### Verbosity Levels

```
shikki test                    → clean output (one-liners only)
shikki test --verbose          → one-liners + full log file path at end
shikki test --verbose --live   → one-liners + logs streaming real-time
```

Default: clean. Logs always go to SQLite regardless. `--verbose` dumps the log file path so you can `bat` it.

### During Execution (per scope)

```
◇ NATS          running...  [12/57]
◆ Flywheel      0.2s        80/80
◆ TUI           0.1s        89/89
◇ Safety        running...  [31/55]
◇ CodeGen       running...  [89/153]
```

### All Green

```
  􁁛 [12:34:56] NATS        [0.3s]  57/57
  􁁛 [12:34:56] Flywheel    [0.2s]  80/80
  􁁛 [12:34:57] TUI         [0.1s]  89/89
  􁁛 [12:34:57] Safety      [0.2s]  55/55
  􁁛 [12:35:07] Kernel      [0.4s]  49/49
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  􁁛 [12:35:07] abc123f fix/mega-merge [1.2s] 330/330
```

No noise. Green means green. No `0 ❌` — if everything passes, you only see green.

### Some Failures

```
  􁁛 [12:34:56] NATS        [0.3s]  57/57
  􁁛 [12:34:56] Flywheel    [0.2s]  80/80
  􁁛 [12:34:57] TUI         [0.1s]  89/89
  􀢄 [12:34:57] Safety      [0.2s]  52/55 !!3
    [0.001s] Safety/BudgetACL — TOCTOU: concurrent check both passed
    [0.001s] Safety/Anomaly — offHoursAccess: timezone mismatch
    [10.2s]  Safety/Timer — countdownCompletes: SLOW (>2s threshold)
  􁁛 [12:35:07] Kernel      [0.4s]  49/49
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  􀢄 [12:35:07] abc123f fix/mega-merge [1.2s] 327/330 !!3
```

`!!3` = 3 need your attention. Detail lines follow immediately.

### Failures + Timeouts/Skipped

```
  􀢄 [12:34:57] Safety      [0.2s]  51/55 !!3 ??1
    [0.001s] Safety/BudgetACL — TOCTOU: concurrent check both passed
    [0.001s] Safety/Anomaly — offHoursAccess: timezone mismatch
    [10.2s]  Safety/Timer — countdownCompletes: SLOW (>2s threshold)
    [??]     Safety/Integration — skipped: requires DB connection
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  􀢄 [12:35:07] abc123f fix/mega-merge [1.2s] 327/330 !!3 ??1
```

`??1` = 1 we couldn't answer (skipped/timeout). Math: `51 + 3 + 1 = 55`.

### Partial Run (--scope)

```
  􁁛 [12:34:56] NATS        [0.3s]  57/57
  􁁛 [12:34:57] TUI         [0.1s]  89/89
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  􀟈 [12:34:57] abc123f fix/mega-merge [0.4s] 146/330
```

`􀟈` = partial run, not everything was tested.

### Verbose (log file path)

```
  􀢄 [12:35:07] abc123f fix/mega-merge [1.2s] 327/330 !!3

  Full log: .shikki/test-logs/2026-03-31-abc123f.log
```

---

## 9. Logger Silencing

All `Logging` output during test execution is captured to SQLite `raw_output`, not printed to terminal. The test runner redirects the swift-log backend to a buffer.

```swift
LoggingSystem.bootstrap { label in
    BufferLogHandler(label: label, buffer: testOutputBuffer)
}
```

The `--verbose --live` flag re-enables terminal output for debugging. The `--verbose` flag shows the log file path for post-mortem analysis.

---

## 10. CLI Commands

```
shikki test                    — run all scopes sequentially
shikki test --parallel         — run all scopes in parallel workers
shikki test --scope nats       — run only NATS scope
shikki test --scope nats,tui   — run multiple scopes
shikki test --scopes           — list available scopes from Moto cache
shikki test --fail-fast        — stop on first failure
shikki test --verbose          — show log file path at end
shikki test --verbose --live   — stream logs in real-time
shikki test --history          — show recent runs from SQLite
shikki test --history 10       — last 10 runs
shikki test --failures         — show failures from last run
shikki test --regression       — find tests that were green, now red
shikki test --slow             — find tests > 2s (candidates for mock clock)
```

---

## 11. SPM Package: ShikkiTestRunner

```
packages/ShikkiTestRunner/
  Package.swift
  Sources/ShikkiTestRunner/
    Core/
      TestGrouper.swift           — Moto cache → scope groups
      ScopeAnalyzer.swift         — import/type analysis → scope assignment
      ParallelExecutor.swift      — dispatch scope groups to workers
      TimeoutManager.swift        — per-test timeout (lit-style)
    Capture/
      TestOutputCapture.swift     — redirect logger + stdout → buffer
      EventStreamParser.swift     — parse Swift Testing JSON events
      ResultParser.swift          — structured test results
    Storage/
      SQLiteStore.swift           — tmp + persistent DB operations
      HistoryManager.swift        — git hash + branch → run linkage
      RegressionDetector.swift    — compare runs, find new failures
    Rendering/
      TUIReporter.swift           — one-liner + failure detail rendering
      ProgressRenderer.swift      — live progress during execution
      VerboseRenderer.swift       — log file path + live streaming
  Tests/ShikkiTestRunnerTests/
    TestGrouperTests.swift
    ScopeAnalyzerTests.swift
    ParallelExecutorTests.swift
    TimeoutManagerTests.swift
    EventStreamParserTests.swift
    SQLiteStoreTests.swift
    TUIReporterTests.swift
    RegressionDetectorTests.swift
```

Depends on: `sqlite3` (system), Moto cache types

---

## 12. Implementation Waves

### Wave 1: Event Stream + SQLite
- EventStreamParser (parse `--experimental-event-stream-output`)
- SQLiteStore (create/query/merge tmp → persistent)
- TimeoutManager (per-test kill)
- Basic `shikki test` command (sequential, captures to DB)
- **15 tests**

### Wave 2: Moto-Based Scoping
- TestGrouper + ScopeAnalyzer
- `--scopes` listing from Moto cache
- `--scope <name>` filtering
- Unscoped safety net (verify all files covered)
- **20 tests**

### Wave 3: Parallel Execution + TUI
- ParallelExecutor with TaskGroup worker pool
- `--parallel` flag
- Logger capture (swift-log → buffer → SQLite)
- TUI progress rendering (one-liners, `!!`, `??`)
- **15 tests**

### Wave 4: History + Regression
- HistoryManager (git hash + branch linkage)
- RegressionDetector (green→red across commits)
- `--history`, `--regression`, `--slow` commands
- **10 tests**

### Wave 5: Dispatch Integration
- Sub-agent scope detection (changed files → affected scopes)
- Pre-PR gate: scope + deps
- Merge gate: all parallel
- Release gate: all + E2E + snapshots
- **10 tests**

---

## 13. Acceptance Criteria

- [ ] `shikki test --parallel` completes in < 30s for 1,800 tests
- [ ] Per-test timeout kills hung tests after 5s
- [ ] Every test file assigned to a scope (zero unscoped, or explicitly unscoped)
- [ ] Zero logger output in terminal during default execution
- [ ] SQLite history queryable by git hash + branch name
- [ ] Regression detection works across commits
- [ ] One-liner scope summary with 􁁛 / 􀢄 / 􀟈 markers
- [ ] `!!N` for failures, `??N` for skipped/timeout, detail lines below
- [ ] `--verbose` shows log file path, `--verbose --live` streams
- [ ] `shikki test --scope nats` runs only NATS tests in < 2s
- [ ] Sub-agents use `--scope <changed>` instead of full suite

---

## 14. @shi Mini-Challenge

1. **@Ronin**: If a test passes in isolation but fails when run with its scope group, is that a test bug or an architecture bug? Should the runner detect this?
2. **@Katana**: The SQLite history is `.gitignored` but lives in the project tree. Should test history sync to ShikiDB for multi-machine regression detection?
3. **@Sensei**: Moto cache gives static dependency analysis. Some tests have runtime deps (imports `ShikkiKit` but only uses `EventBus`). Should scoping be static (imports) or dynamic (runtime coverage)?
4. **@Hanami**: The `!!3 ??1` suffix — should warnings (slow tests > 2s but not timeout) get their own marker? Like `~~2` for "these worked but suspiciously slow"?
5. **@Kintsugi**: Test history linked to git commits creates a "memory of quality" across time. Is this the Patina Protocol applied to code confidence — freshness decay on untested paths?
