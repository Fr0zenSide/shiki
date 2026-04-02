# Feature: FixEngine Hardening
> Created: 2026-03-30 | Status: Phase 5b — Implementation Ready | Owner: @Daimyo

## Context

The CodeGen `FixEngine` auto-applies code fixes in a loop (max 3 iterations). A high-risk code walkthrough revealed three critical gaps:

1. **No rollback on regression**: If a fix iteration introduces MORE failures than it resolves, the engine records `max(0, fixedThisIteration)` and continues. The broken state persists — there is no mechanism to restore the pre-fix working tree.
2. **No contract verification after fix**: The `ContractVerifier` is available (used in the pipeline's `verifyContracts` stage) but never invoked inside the fix loop. An agent could silently break protocol conformances while "fixing" tests.
3. **No test file protection**: The fix prompt says "fix implementation code, NOT tests" — but that is a text instruction to an LLM. Nothing in the engine enforces this. An agent can modify `*Tests.swift` files to make tests pass by weakening assertions.

**Current code**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift` (282 lines)
**Current tests**: `projects/shikki/Tests/ShikkiKitTests/CodeGen/FixEngineTests.swift` (163 lines, 10 tests)

## Problem

The fix loop is the most dangerous automated operation in the CodeGen pipeline — it modifies production code based on LLM output with no safety net. The three gaps above mean a regression can compound across iterations, protocol contracts can be silently violated, and test integrity can be undermined. This makes the entire pipeline unreliable for autonomous operation.

## Synthesis

**Goal**: Make the FixEngine fail-safe — every iteration is reversible, contract-verified, and test-file-protected.

**Scope**:
- Git state snapshot before each fix iteration (record commit hash via `MergeEngine.runGit`)
- `ContractVerifier.verify()` after each successful fix iteration
- Git-diff filter rejecting changes to `*Tests.swift` files
- Regression detection with automatic rollback
- Exhaustion reporting to orchestrator via `FixProgressEvent`
- Per-iteration timeout via `Task.sleep` + `withThrowingTaskGroup` cancellation

**Out of scope**:
- Changes to `MergeEngine`, `ContractVerifier`, or `AgentRunner` interfaces
- Changes to the `CodeGenerationPipeline` protocol (the pipeline already calls `fix()` — we harden internally)
- Fix prompt improvements (text-based guardrails are complementary, not a replacement for enforcement)

**Success criteria**:
- A regression (more failures after fix) triggers rollback to the pre-fix state and stops the loop
- A fix that modifies test files is rejected before test re-run
- A fix that breaks protocol contracts is rejected and rolled back
- Exhaustion after 3 iterations emits a `.exhausted` progress event with remaining failure details
- All existing tests continue to pass (no breaking API changes)

**Dependencies**: None — all required APIs (`MergeEngine.runGit`, `ContractVerifier.verify`, `MergeEngine.runTests`) already exist.

## Business Rules

```
BR-01: Before each fix iteration, record the current HEAD commit hash as a snapshot
BR-02: After each fix iteration, run ContractVerifier.verify() on the ProtocolLayer to ensure protocol integrity is preserved
BR-03: If fixedThisIteration < 0 (regression — more failures than before), rollback to snapshot via `git reset --hard <hash>` and stop the loop
BR-04: After each agent run, check `git diff --name-only` for changes to *Tests.swift files — if any are found, rollback to snapshot and skip that iteration (count as no-progress)
BR-05: If all 3 iterations are exhausted with remaining failures, emit a `.exhausted` progress event containing the remaining failure list — do not return a result that looks like silent success
BR-06: Each fix iteration (agent run + test re-run) must be wrapped in a per-iteration timeout; if exceeded, rollback to snapshot and stop
```

## Test Plan

### Scenario 1: Happy path — progressive fix across iterations
```
Setup:   MockFixAgentRunner returns .completed; MockMergeEngine returns decreasing failure counts
         Iteration 1: 10 failures → 5 remaining
         Iteration 2: 5 failures → 0 remaining
BR-01 → Snapshot recorded before iteration 1 and 2
BR-02 → ContractVerifier.verify() called after iteration 1 and 2 — both valid
Result:  FixResult.finallyPassed == true, totalFixedCount == 10, iterations.count == 2
```

### Scenario 2: Regression — fix introduces new failures, rollback
```
Setup:   MockFixAgentRunner returns .completed; MockMergeEngine returns:
         Iteration 1: 5 failures → 8 remaining (fixedThisIteration = -3)
BR-01 → Snapshot hash "abc123" recorded before iteration 1
BR-03 → fixedThisIteration < 0 detected → git reset --hard abc123 called → loop stops
Result:  FixResult.finallyPassed == false, iterations.count == 1, .regression progress event emitted
Verify:  MockMergeEngine.gitResetCalls contains "abc123"
```

### Scenario 3: Test file modification rejected
```
Setup:   MockFixAgentRunner returns .completed; MockMergeEngine.gitDiff returns ["Sources/Foo.swift", "Tests/FooTests.swift"]
BR-04 → *Tests.swift detected in diff → git reset --hard <snapshot> called
BR-04 → Iteration counted as no-progress (fixedThisIteration = 0)
Result:  If iteration > 1, loop breaks (no-progress rule). Progress event emitted.
Verify:  MockMergeEngine.gitResetCalls has 1 entry; agent was not re-dispatched for this iteration
```

### Scenario 4: Exhaustion — 3 loops, still failures
```
Setup:   MockFixAgentRunner returns .completed; MockMergeEngine returns:
         Iteration 1: 10 → 7 (fixed 3), Iteration 2: 7 → 4 (fixed 3), Iteration 3: 4 → 2 (fixed 2)
BR-01 → 3 snapshots recorded
BR-02 → 3 contract verifications, all valid
BR-05 → .exhausted(remaining: 2) progress event emitted after iteration 3
Result:  FixResult.finallyPassed == false, totalFixedCount == 8, remainingFailures.count == 2
Verify:  onProgress received .exhausted event with correct failure list
```

### Scenario 5: Contract verification fails after fix
```
Setup:   MockFixAgentRunner returns .completed; MockMergeEngine returns 0 remaining failures;
         MockContractVerifier returns ContractResult(isValid: false, issues: ["Duplicate declaration"])
BR-02 → Contract verification fails → rollback to snapshot → loop stops
Result:  FixResult.finallyPassed == false, progress event reports contract violation
Verify:  MockMergeEngine.gitResetCalls has 1 entry
```

### Scenario 6: Per-iteration timeout
```
Setup:   MockFixAgentRunner.run() sleeps for 5 seconds; timeout set to 1 second
BR-06 → Task cancelled after 1s → rollback to snapshot → loop stops
Result:  FixResult.finallyPassed == false, .timedOut progress event emitted
Verify:  MockMergeEngine.gitResetCalls has 1 entry; total duration < 3 seconds
```

## Architecture

### Files to Modify

| File | Modification | BRs |
|------|-------------|-----|
| `FixEngine.swift` | Add `snapshotState()` method — runs `git rev-parse HEAD` via MergeEngine | BR-01 |
| `FixEngine.swift` | Add `rollbackToSnapshot(_:)` method — runs `git reset --hard <hash>` via MergeEngine | BR-01, BR-03 |
| `FixEngine.swift` | Add `verifyContracts(_:)` call after each iteration in `fix()` | BR-02 |
| `FixEngine.swift` | Add `checkTestFileModification()` — runs `git diff --name-only` and filters `*Tests.swift` | BR-04 |
| `FixEngine.swift` | Add `.exhausted`, `.regression`, `.contractViolation`, `.testFileModification`, `.timedOut` cases to `FixProgressEvent` | BR-03, BR-04, BR-05, BR-06 |
| `FixEngine.swift` | Wrap iteration body in `withThrowingTaskGroup` + `Task.sleep` timeout | BR-06 |
| `FixEngine.swift` | Accept `ContractVerifier` and `iterationTimeoutSeconds` in `init` | BR-02, BR-06 |
| `FixEngineTests.swift` | Add 6 new test methods matching scenarios 1-6 | All BRs |

### Key Code Changes

**Before** (`fix()` loop body, lines 113-183):
```swift
for iteration in 1...Self.maxIterations {
    onProgress?(.iterationStarted(iteration: iteration, failureCount: currentFailures.count))
    // ... dispatch agents, re-run tests ...
    let fixedThisIteration = previousCount - currentFailures.count
    // No rollback, no contract check, no diff filter
    if fixedThisIteration <= 0 && iteration > 1 {
        onProgress?(.noProgress(iteration: iteration))
        break
    }
}
```

**After**:
```swift
for iteration in 1...Self.maxIterations {
    // BR-01: Snapshot
    let snapshot = try await snapshotState()

    onProgress?(.iterationStarted(iteration: iteration, failureCount: currentFailures.count))

    // BR-06: Per-iteration timeout
    let iterationResult = try await withTimeout(seconds: iterationTimeoutSeconds) {
        // ... dispatch agents ...

        // BR-04: Check for test file modifications
        let modifiedFiles = try await getModifiedFiles()
        let testFilesModified = modifiedFiles.filter { $0.hasSuffix("Tests.swift") }
        if !testFilesModified.isEmpty {
            try await rollbackToSnapshot(snapshot)
            onProgress?(.testFileModification(iteration: iteration, files: testFilesModified))
            return nil // Signal no-progress
        }

        // Re-run tests
        let testResult = try await mergeEngine.runTests(scope: testScope)
        return testResult
    }

    // Handle timeout
    guard let testResult = iterationResult else {
        // BR-04: test file modification — treat as no progress
        if iteration > 1 { break }
        continue
    }

    let previousCount = currentFailures.count
    currentFailures = testResult.failures
    let fixedThisIteration = previousCount - currentFailures.count

    // BR-03: Regression rollback
    if fixedThisIteration < 0 {
        try await rollbackToSnapshot(snapshot)
        onProgress?(.regression(iteration: iteration, delta: fixedThisIteration))
        break
    }

    // BR-02: Contract verification
    let contractResult = contractVerifier.verify(layer)
    if !contractResult.isValid {
        try await rollbackToSnapshot(snapshot)
        onProgress?(.contractViolation(iteration: iteration, issues: contractResult.issues))
        break
    }

    // ... rest of iteration logic (append result, check all-fixed, check no-progress) ...
}

// BR-05: Exhaustion reporting
if !currentFailures.isEmpty {
    onProgress?(.exhausted(remaining: currentFailures))
}
```

**New `FixProgressEvent` cases**:
```swift
public enum FixProgressEvent: Sendable {
    case iterationStarted(iteration: Int, failureCount: Int)
    case iterationCompleted(iteration: Int, fixed: Int, remaining: Int)
    case noProgress(iteration: Int)
    case regression(iteration: Int, delta: Int)
    case contractViolation(iteration: Int, issues: [String])
    case testFileModification(iteration: Int, files: [String])
    case exhausted(remaining: [TestFailure])
    case timedOut(iteration: Int)
}
```

**New `FixEngine.init` signature**:
```swift
public init(
    projectRoot: String,
    agentRunner: AgentRunner,
    contractVerifier: ContractVerifier = ContractVerifier(),
    iterationTimeoutSeconds: Int = 300
)
```

### Test Architecture

New mock required for controllable git operations:

```swift
final class MockGitMergeEngine: @unchecked Sendable {
    var headHash: String = "initial-hash"
    var testResultSequence: [TestRunResult] = []
    var diffFiles: [String] = []
    var gitResetCalls: [String] = []
    private var testCallIndex = 0
}
```

Existing `MockFixAgentRunner` is sufficient for agent dispatch testing.

## Execution Plan

### Task 1: Add snapshot and rollback methods
- **Files**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
- **Implement**: Add `snapshotState()` (calls `runGit(["rev-parse", "HEAD"])`) and `rollbackToSnapshot(_:)` (calls `runGit(["reset", "--hard", hash])`) as private methods using a new `gitRunner` closure or by accepting `MergeEngine` directly.
- **Verify**: Unit test — snapshot returns a hash string; rollback calls git reset with that hash.
- **BRs**: BR-01
- **Time**: ~5 min

### Task 2: Add test file modification check
- **Files**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
- **Implement**: Add `getModifiedFiles()` method (calls `runGit(["diff", "--name-only"])`) and filter for `*Tests.swift` suffix. Insert check after agent dispatch, before test re-run. On violation, rollback and emit `.testFileModification`.
- **Verify**: Unit test — diff containing `FooTests.swift` triggers rollback and progress event.
- **BRs**: BR-04
- **Time**: ~5 min

### Task 3: Add contract verification after each iteration
- **Files**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
- **Implement**: Accept `ContractVerifier` in init (default `ContractVerifier()`). After successful test re-run, call `contractVerifier.verify(layer)`. If `!isValid`, rollback and emit `.contractViolation`.
- **Verify**: Unit test — mock verifier returning invalid triggers rollback.
- **BRs**: BR-02
- **Time**: ~5 min

### Task 4: Add regression detection with rollback
- **Files**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
- **Implement**: Replace `if fixedThisIteration <= 0 && iteration > 1` with explicit regression check: if `fixedThisIteration < 0`, rollback and emit `.regression`. Keep no-progress check separately for `fixedThisIteration == 0 && iteration > 1`.
- **Verify**: Unit test — mock returning more failures than input triggers rollback.
- **BRs**: BR-03
- **Time**: ~3 min

### Task 5: Add exhaustion reporting
- **Files**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
- **Implement**: After the loop, if `!currentFailures.isEmpty`, emit `.exhausted(remaining: currentFailures)` before returning the `FixResult`.
- **Verify**: Unit test — 3 iterations with remaining failures triggers exhaustion event.
- **BRs**: BR-05
- **Time**: ~2 min

### Task 6: Add per-iteration timeout
- **Files**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
- **Implement**: Accept `iterationTimeoutSeconds` in init (default 300). Wrap iteration body in `withThrowingTaskGroup` with a sleep-based timeout task. On timeout, rollback and emit `.timedOut`.
- **Verify**: Unit test — mock agent sleeping 5s with 1s timeout triggers rollback within 3s.
- **BRs**: BR-06
- **Time**: ~8 min

### Task 7: Extend FixProgressEvent enum
- **Files**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
- **Implement**: Add `.regression`, `.contractViolation`, `.testFileModification`, `.exhausted`, `.timedOut` cases.
- **Verify**: Compile check — no downstream breakage (enum is only consumed via progress callback, not exhaustively switched).
- **BRs**: BR-03, BR-04, BR-05, BR-06
- **Time**: ~2 min

### Task 8: Write test scenarios 1-6
- **Files**: `projects/shikki/Tests/ShikkiKitTests/CodeGen/FixEngineTests.swift`
- **Implement**: Add `MockGitMergeEngine` and 6 new test methods matching the test plan scenarios. Use controllable mock sequences for test results and diff output.
- **Verify**: `swift test --filter FixEngineTests` — all 16 tests pass (10 existing + 6 new).
- **BRs**: All
- **Time**: ~15 min

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 6/6 BRs mapped to tasks (Task 1→BR-01, Task 2→BR-04, Task 3→BR-02, Task 4→BR-03, Task 5→BR-05, Task 6→BR-06) |
| Test Coverage | PASS | 6/6 scenarios mapped to Task 8 |
| File Alignment | PASS | 2 files: `FixEngine.swift` (source) + `FixEngineTests.swift` (tests) |
| Task Dependencies | PASS | Task 7 first (enum), then Tasks 1-6 in any order, Task 8 last |
| Task Granularity | PASS | All tasks 2-15 min |
| Testability | PASS | Each task has a verify step; mocks already exist or are specified |
| API Compatibility | PASS | `FixEngine.init` adds optional params with defaults — no breaking change |
| Existing Tests | PASS | All 10 existing tests unaffected (new params have defaults, new enum cases are additive) |

**Verdict: PASS** — ready for Phase 6.

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-30 | Phase 1-5b | @Daimyo | APPROVED | Spec from walkthrough findings |

---

### @shi mini-challenge
1. **@Ronin**: The `rollbackToSnapshot` uses `git reset --hard` — what happens if the agent created untracked files? Should we also `git clean -fd` in the rollback? Trade-off: safety vs data loss.
2. **@Sensei**: The `ContractVerifier.verify()` is a static analysis check. Should we also run `verifyAgainstCache()` inside the fix loop if a cache is available, or is that too expensive per-iteration?
3. **@Katana**: The timeout uses `Task.sleep` + cancellation. Is there a race condition where the agent process outlives the Swift Task cancellation? Should we also track the child process PID for force-kill?
