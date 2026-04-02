---
title: "Spec Tracking Fields — Traceability from Dispatch to Verified Green"
status: spec
priority: P0
project: shikki
created: 2026-04-02
authors: "@Daimyo + @Sensei"
tags:
  - testing
  - traceability
  - quality
  - shikidb
depends-on:
  - shikki-spec-metadata-v2.md (frontmatter lifecycle)
  - shikki-ship-testflight.md (ship gate pipeline)
  - shikki-test-runner.md (ShikkiTestRunner)
relates-to:
  - shiki-knowledge-mcp.md (ShikiDB event API)
  - shikki-codegen-engine.md (FixEngine uses test results)
  - shikki-dispatch-resilience.md (orchestrator verification)
---

# Spec Tracking Fields

> Every green must have a verifiable test run ID. No proof, no ship.

---

## 1. Problem

Specs today have no link to their implementation or validation proof:

- **No branch traceability**: A spec says nothing about which branch implements it. Dispatch has to guess or rely on naming conventions.
- **No validation proof**: When a spec transitions to `validated`, there is no record of which commit was validated. The status is a human assertion with no cryptographic anchor.
- **No test evidence**: When an agent reports "all green", the orchestrator has no way to verify. The claim could be hallucinated, stale, or from a different branch entirely.
- **Local-only test data**: ShikkiTestRunner stores results in local SQLite. The orchestrator cannot query it. Parallel branches writing to the same SQLite file would conflict.
- **Ship gate is blind**: The pre-PR gate pipeline checks code quality but cannot verify that tests actually passed for the current HEAD.

---

## 2. Solution

Two complementary changes:

**Part A** — Add three traceability fields to spec frontmatter: `epic-branch`, `validated-commit`, and `test-run-id`. These fields create a verifiable chain from spec to branch to commit to test evidence.

**Part B** — Post test results to ShikiDB after every run, making them queryable by the orchestrator and ship gate. Local SQLite becomes a fast cache; ShikiDB is source of truth.

---

## 3. Part A — Spec Frontmatter Tracking Fields

### 3.1 New Fields

```yaml
---
title: "Some Feature Spec"
status: validated
priority: P0
project: shikki
created: 2026-04-02
epic-branch: epic/spec-metadata          # Root branch for dispatch
validated-commit: abc1234def5678          # Git SHA when spec was validated
test-run-id: "evt_2026-04-02_run001"     # ShikiDB event proving tests green
---
```

### 3.2 Field Semantics

| Field | Type | Set by | When | Required |
|-------|------|--------|------|----------|
| `epic-branch` | String | Author (manual) | Before dispatch | Yes, for dispatch |
| `validated-commit` | String (SHA) | `shikki spec review` (auto) | On validation transition | Auto-set, never manual |
| `test-run-id` | String (event ID) | Ship gate (auto) | When tests pass for branch | Auto-set, never manual |

### 3.3 Behavior

**`epic-branch`**: The author sets this field in the spec before calling `/dispatch`. The dispatch system reads it to determine the base branch from which to create feature branches. If absent, dispatch refuses to start (BR-01).

**`validated-commit`**: When `shikki spec review` transitions a spec to `validated` status, it captures the current `HEAD` SHA and writes it into the frontmatter. This anchors the validation to a specific point in git history. Manual edits to this field are rejected by the serializer (BR-02).

**`test-run-id`**: When the ship gate runs and all tests pass, it queries ShikiDB for the latest `test_run_completed` event matching the current branch. If found and the commit SHA matches HEAD, it writes the event ID into the spec frontmatter. This is the proof that tests passed (BR-03).

### 3.4 SpecMetadata Model Changes

```swift
public struct SpecMetadata: Codable, Equatable, Sendable {
    // ... existing fields ...

    // NEW — Tracking fields
    public var epicBranch: String?
    public var validatedCommit: String?
    public var testRunId: String?

    enum CodingKeys: String, CodingKey {
        // ... existing keys ...
        case epicBranch = "epic-branch"
        case validatedCommit = "validated-commit"
        case testRunId = "test-run-id"
    }
}
```

### 3.5 Parser and Serializer

The `SpecFrontmatterParser` must:
- Parse `epic-branch`, `validated-commit`, and `test-run-id` from YAML frontmatter
- Treat all three as optional strings
- Preserve unknown fields (forward compatibility)

The `SpecFrontmatterService` serializer must:
- Output `epic-branch` only if non-nil
- Output `validated-commit` only if non-nil
- Output `test-run-id` only if non-nil
- Maintain field ordering consistent with existing frontmatter

---

## 4. Part B — Test Results in ShikiDB

### 4.1 Architecture

```
ShikkiTestRunner
    │
    ├─── [existing] SQLite (local cache, fast reads)
    │
    └─── [NEW] ShikiDB via shiki_save_event
              │
              └─── event type: test_run_completed
                   │
                   └─── queryable by orchestrator + ship gate
```

### 4.2 TestRunEvent

```swift
public struct TestRunEvent: Codable, Sendable {
    public let runId: String           // "evt_2026-04-02_run001"
    public let branch: String          // "feature/spec-tracking"
    public let commit: String          // Full SHA
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let duration: TimeInterval  // Seconds
    public let suites: [String]        // ["SpecMetadataTests", "ShipGateTests"]
    public let timestamp: Date
}
```

### 4.3 ShikiDB Event Format

Posted via `shiki_save_event` MCP tool:

```json
{
  "type": "test_run_completed",
  "source": "shikki-test-runner",
  "data": {
    "runId": "evt_2026-04-02_run001",
    "branch": "feature/spec-tracking",
    "commit": "abc1234def5678901234567890abcdef12345678",
    "passed": 42,
    "failed": 0,
    "skipped": 2,
    "duration": 12.34,
    "suites": ["SpecMetadataTests", "ShipGateTests"],
    "timestamp": "2026-04-02T14:30:00Z"
  }
}
```

### 4.4 Dual-Write Flow

After every test run:

1. ShikkiTestRunner writes results to local SQLite (existing behavior, unchanged)
2. ShikkiTestRunner posts `test_run_completed` event to ShikiDB via `shiki_save_event`
3. If ShikiDB post fails: log warning, continue (local SQLite is fallback)
4. The `runId` is generated deterministically: `evt_{date}_{branch-slug}_{shortSHA}`

### 4.5 Retention Policy

- **Detail retention**: 90 days (configurable via `~/.config/shikki/config.toml`)
- **Summary retention**: Forever (runId, branch, commit, passed/failed/skipped, duration, timestamp)
- **Rotation**: Background task in ShikkiKernel, runs daily, deletes suite-level detail for events older than threshold
- **Config key**: `test-results.retention-days = 90`

---

## 5. Orchestrator Arbitration

### 5.1 Verification Flow

When the orchestrator receives "all green" from a sub-agent:

```
Sub-agent reports: "Tests pass, test-run-id = evt_2026-04-02_run001"
    │
    ├─── Query ShikiDB: search for event with runId
    │
    ├─── NOT FOUND ──→ REJECT
    │         "No test evidence in ShikiDB. Possible hallucination."
    │
    ├─── FOUND, commit != HEAD ──→ WARN
    │         "Test results are stale. Run ID commit {x} != HEAD {y}."
    │
    └─── FOUND, commit == HEAD, failed == 0 ──→ ACCEPT
              "Verified green. test-run-id written to spec."
```

### 5.2 Rejection Handling

On REJECT:
- Log the event as `test_verification_failed` in ShikiDB
- Notify orchestrator dashboard (Observatory)
- Sub-agent is asked to re-run tests

On WARN (stale):
- Log warning
- Sub-agent is asked to re-run tests on current HEAD
- If re-run passes, update test-run-id

---

## 6. Ship Gate Integration

### 6.1 TestRunVerificationGate

New gate in the `PrePRGates` pipeline:

```swift
public struct TestRunVerificationGate: ShipGate {
    public let name = "test-run-verification"

    public func evaluate(context: ShipContext) async throws -> GateResult {
        // 1. Query ShikiDB for latest test_run_completed on this branch
        // 2. Verify commit SHA matches HEAD
        // 3. Verify zero failures
        // 4. Write test-run-id into spec frontmatter (if spec exists)
        // 5. Return .passed or .failed with reason
    }
}
```

### 6.2 Gate Behavior

| Condition | Result | Action |
|-----------|--------|--------|
| No test_run_completed event for branch | `.failed` | "No test evidence found. Run tests first." |
| Event found, commit != HEAD | `.failed` | "Test results stale. Re-run tests." |
| Event found, commit == HEAD, failures > 0 | `.failed` | "Tests have {n} failures." |
| Event found, commit == HEAD, failures == 0 | `.passed` | Write `test-run-id` to spec frontmatter |

### 6.3 Fail-Closed Policy

If ShikiDB is unreachable during gate evaluation:
- Gate returns `.failed` with reason "ShikiDB unreachable. Cannot verify test results."
- This is a deliberate fail-closed design (BR-04). Shipping without proof is not allowed.
- Mitigation: `--skip-verification` flag for emergency deploys (logged as override event in ShikiDB when it recovers)

---

## 7. Business Rules

| ID | Rule | Enforcement |
|----|------|-------------|
| BR-01 | `epic-branch` MUST be present in spec before dispatch can begin | Dispatch system checks frontmatter |
| BR-02 | `validated-commit` MUST be auto-set by `shikki spec review` on validation, never manually | Serializer rejects manual writes |
| BR-03 | `test-run-id` MUST reference a real ShikiDB event, verified by ship gate | TestRunVerificationGate |
| BR-04 | Ship gate MUST reject if `test-run-id` does not exist in ShikiDB | Fail-closed gate policy |
| BR-05 | Ship gate MUST warn if `test-run-id` commit does not match current HEAD | Stale result detection |
| BR-06 | ShikkiTestRunner MUST post results to ShikiDB after every test run | Dual-write in test runner |
| BR-07 | Local SQLite remains as fast cache, ShikiDB is source of truth | Read from DB for verification |
| BR-08 | Test results older than 90 days SHOULD be rotated (keep summary, drop details) | Background rotation task |
| BR-09 | Orchestrator MUST verify `test-run-id` before accepting "all green" from sub-agents | Arbitration flow in kernel |
| BR-10 | `shikki spec validate` MUST check that validated specs have `validated-commit` set | Validation command logic |

---

## 8. TDDP

### Part A: Spec Fields (Wave 1-2)

| # | Test | State |
|---|------|-------|
| 1 | `SpecMetadata` model has `epicBranch`, `validatedCommit`, `testRunId` fields | RED |
| 2 | Impl: Add 3 fields to `SpecMetadata` + `CodingKeys` | GREEN |
| 3 | `SpecFrontmatterParser` parses `epic-branch` from YAML | RED |
| 4 | Impl: Parse new fields in `parseYAML` methods | GREEN |
| 5 | `SpecFrontmatterService` serializes new fields to YAML | RED |
| 6 | Impl: `serializeToYAML` outputs new fields | GREEN |
| 7 | `shikki spec review` sets `validated-commit` on validation | RED |
| 8 | Impl: `SpecReviewCommand` reads HEAD SHA and updates frontmatter | GREEN |

### Part B: Test Results DB (Wave 3-5)

| # | Test | State |
|---|------|-------|
| 9 | `TestRunEvent` model serializes to ShikiDB format | RED |
| 10 | Impl: `TestRunEvent` struct + `shiki_save_event` integration | GREEN |
| 11 | ShikkiTestRunner posts results to ShikiDB after run | RED |
| 12 | Impl: Post-run hook calling `shiki_save_event` | GREEN |
| 13 | `TestRunVerificationGate` queries ShikiDB for `test-run-id` | RED |
| 14 | Impl: Gate with HTTP query to ShikiDB search endpoint | GREEN |
| 15 | `TestRunVerificationGate` rejects missing/stale `test-run-id` | RED |
| 16 | Impl: Commit SHA comparison + rejection logic | GREEN |
| 17 | Orchestrator verifies `test-run-id` before accepting green | RED |
| 18 | Impl: Kernel verification step in task completion handler | GREEN |

---

## 9. Implementation Waves

### Wave 1 (P0): SpecMetadata Fields + Parser/Serializer
- Add `epicBranch`, `validatedCommit`, `testRunId` to `SpecMetadata`
- Update `SpecFrontmatterParser` to parse new fields from YAML
- Update `SpecFrontmatterService` to serialize new fields
- TDDP tests 1-6
- **Files**: `SpecMetadata.swift`, `SpecFrontmatterParser.swift`, `SpecFrontmatterService.swift`

### Wave 2 (P0): Spec Review Auto-Sets validated-commit
- `shikki spec review` captures HEAD SHA on validation transition
- Write `validated-commit` into frontmatter atomically
- Reject manual edits to `validated-commit` in serializer
- TDDP tests 7-8
- **Files**: `SpecReviewCommand.swift`, `SpecFrontmatterService.swift`

### Wave 3 (P1): TestRunEvent + ShikiDB Posting
- Define `TestRunEvent` model
- Dual-write: SQLite + ShikiDB `shiki_save_event`
- Deterministic `runId` generation
- Graceful fallback if ShikiDB unreachable
- TDDP tests 9-12
- **Files**: `TestRunEvent.swift`, `ShikkiTestRunner.swift` (post-run hook)

### Wave 4 (P1): TestRunVerificationGate
- New `TestRunVerificationGate` in `PrePRGates`
- Query ShikiDB for `test_run_completed` by branch
- Verify commit SHA matches HEAD
- Verify zero failures
- Write `test-run-id` into spec frontmatter
- Fail-closed when ShikiDB unreachable
- TDDP tests 13-16
- **Files**: `TestRunVerificationGate.swift`, `PrePRGates.swift`

### Wave 5 (P1): Orchestrator Verification
- Kernel intercepts "all green" reports from sub-agents
- Queries ShikiDB to verify `test-run-id`
- REJECT / WARN / ACCEPT flow
- Logs `test_verification_failed` on rejection
- TDDP tests 17-18
- **Files**: `ShikkiKernel.swift` (task completion handler)

---

## 10. @shi Mini-Challenge

1. **@Ronin**: If ShikiDB is down, should ship gate fail-closed (reject) or fail-open (accept with warning)? Spec says fail-closed — safer, but blocks shipping when DB is down. Should `--skip-verification` exist, or is that a hole in the model?

2. **@Katana**: The `test-run-id` in frontmatter is a ShikiDB event ID. Could an agent forge this by posting a fake `test_run_completed` event with fabricated pass counts? Need event signing or agent identity verification to close this vector.

3. **@Sensei**: Should test result retention be time-based (90 days) or count-based (keep last N runs per branch)? Time-based is simpler but may lose important historical data for long-lived branches. Hybrid approach: keep last N per branch OR 90 days, whichever is longer?
