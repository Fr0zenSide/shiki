# P0 — Immediate Plan

> Created: 2026-03-23 | Author: @Sensei | Status: draft

## Task 1: curl → MCP Cleanup

### Current State

The `develop` branch and current feature branch have **already migrated** all 6 skill/command files from curl to ShikiMCP tools. The `main` branch still has the old curl calls. These will be resolved when `develop` merges to `main` via the next release.

**Files already migrated on develop (no work needed):**

| File | Old curl pattern | New MCP instruction | Status |
|------|-----------------|---------------------|--------|
| `.claude/skills/shiki-process/quick-flow.md` | `curl -sf http://localhost:3900/health`, `curl -sf -X POST .../api/pipelines`, `curl -sf -X PATCH` | `shiki_health` MCP tool, `shiki_save_event` MCP tool | DONE on develop |
| `.claude/skills/shiki-process/pre-pr-pipeline.md` | Same curl pattern for pipeline checkpointing | Same MCP migration | DONE on develop |
| `.claude/skills/shiki-process/feature-pipeline.md` | Same curl pattern for pipeline checkpointing | Same MCP migration | DONE on develop |
| `.claude/commands/ingest.md` | `curl -X POST .../api/ingest`, `curl .../api/ingest/sources`, `curl -X DELETE` | `shiki_save_event`, `shiki_search` MCP tools | DONE on develop |
| `.claude/commands/radar.md` | `curl -s .../api/radar/watchlist`, `curl -s -X POST`, `curl -s -X DELETE`, `curl -s .../api/radar/scans` | `shiki_search`, `shiki_save_event` MCP tools | DONE on develop |
| `.claude/commands/retry.md` | `curl -s .../api/pipelines?status=failed`, `curl -s -X POST .../resume`, `curl -s .../api/pipelines?limit=10` | `shiki_search`, `shiki_save_event` MCP tools | DONE on develop |

### Remaining curl Usage (NOT in skills/commands — separate scope)

These are **not** skill/command files. They are shell scripts and Swift source code that use curl as a subprocess for HTTP calls. These are tracked separately as the "NetKit migration" backlog item (P2).

| Location | Type | curl Usage | Future Migration |
|----------|------|-----------|-----------------|
| `scripts/shiki` | Shell | Health checks, company count | Replace with shikki CLI subcommand |
| `scripts/orchestrate.sh` | Shell | Health check | Replace with shikki CLI |
| `scripts/seed-companies.sh` | Shell | API calls to backend | Replace with shikki CLI |
| `scripts/shiki-board.sh` | Shell | Health check | Replace with shikki CLI |
| `scripts/board-watch.sh` | Shell | Orchestrator status | Replace with shikki CLI |
| `scripts/shiki-idle.sh` | Shell | ntfy notification | Keep (shell-to-ntfy is fine) |
| `scripts/shiki-approval.sh` | Shell | ntfy notification | Keep (shell-to-ntfy is fine) |
| `scripts/ingest-memories.sh` | Shell | Memory API calls | Replace with shikki CLI or delete |
| `tools/shiki-ctl/.../BackendClient.swift` | Swift | All HTTP via curl subprocess | Migrate to NetKit (URLSession/NIO) |
| `tools/shiki-ctl/.../DBSyncClient.swift` | Swift | DB sync via curl subprocess | Migrate to NetKit |
| `tools/shiki-ctl/.../EnvironmentDetector.swift` | Swift | Health probes via curl | Migrate to NetKit |
| `tools/shiki-ctl/.../NotificationService.swift` | Swift | ntfy via curl | Migrate to NetKit |
| `tools/shiki-ctl/.../StartupCommand.swift` | Swift | Health check via curl | Migrate to NetKit |
| `tools/shiki-ctl/.../ShipCommand.swift` | Swift | ntfy via curl | Migrate to NetKit |

### Migration Pattern (Reference — already applied on develop)

The pattern used for the skill/command migration:

**Before (curl):**
```
If Shiki backend is available (`curl -sf http://localhost:3900/health`), checkpoint...

RUN_ID=$(curl -sf -X POST http://localhost:3900/api/pipelines \
  -H 'Content-Type: application/json' \
  -d '{"type":"quick","config":{}}' | jq -r '.id')
```

**After (MCP):**
```
If ShikiMCP tools are available (verify with `shiki_health` MCP tool), checkpoint...

**On start**: Use the `shiki_save_event` MCP tool with:
{ "type": "pipeline_started", "scope": "quick", "data": { "pipelineType": "quick", "config": {} } }
Store the returned ID as RUN_ID.
```

**Key mapping:**
| curl endpoint | MCP tool |
|---------------|----------|
| `GET /health` | `shiki_health` |
| `POST /api/memories/search` | `shiki_search` |
| `POST /api/data-sync` (write) | `shiki_save_event`, `shiki_save_decision`, `shiki_save_plan`, `shiki_save_context` |
| `GET /api/decisions` | `shiki_get_decisions` |
| `GET /api/reports` | `shiki_get_reports` |
| `GET /api/context` | `shiki_get_context` |
| `GET /api/plans` | `shiki_get_plans` |

### Edge Cases

1. **`curl -sf` silent failure** — The old pattern hid HTTP errors (the very problem documented in `memory/feedback_curl-sf-error-blindness.md`). MCP tools return structured errors, so this is automatically fixed.
2. **Health check gating** — Skills that gate on backend availability now use `shiki_health` which returns a structured response. If the MCP server itself is unreachable, the tool call fails and the skill falls back to "skip checkpointing silently."
3. **Pipeline API endpoints** — The old curl calls hit `/api/pipelines/*` which are backend REST endpoints. The MCP tools route through `shiki_save_event` with structured event types. The backend must handle the event types (`pipeline_started`, `pipeline_checkpoint`, etc.).
4. **`settings.json` allowlist** — `Bash(curl:*)` is still in `.claude/settings.json`. This can be removed once the NetKit migration (Swift source curl) is complete. For now it is needed by the Swift binary.

### Dependency Tree

```
main ← develop (merge resolves all 6 files)
         ↑
         already done — no new work for skill/command curl cleanup
```

### Sub-agent Split

**No sub-agents needed.** The migration is complete on develop. The only action is:
1. Verify the next `release/*` → `main` merge carries the changes
2. Track the NetKit migration (Swift curl subprocess) as a separate P2 backlog item

---

## Task 2: E2E Test Skip Flag

### Problem

`E2EScenarioTests` in `tools/shiki-ctl/Tests/ShikiCtlTests/` spawns the compiled binary via `Process()`. Some tests can hang when:
- The binary reads from stdin (interactive prompts)
- The binary spawns tmux sessions that block
- The binary waits for backend connectivity with long timeouts

Currently there are 7 E2E tests. Most are safe (they pass `--help`, `--version`, or `--url` to force offline behavior), but as E2E coverage grows, stdin-dependent tests will become a problem for CI and `swift test` runs.

### Approach: Swift Testing Tags + Environment Variable

Swift Testing (the framework already used throughout the test suite) supports **tags** for test filtering. Combined with the `.enabled(if:)` condition trait, we can skip E2E tests based on an environment variable.

**Strategy:**
1. Define a custom `Tag` for E2E tests
2. Add `.enabled(if:)` condition that checks for `SKIP_E2E` environment variable
3. Apply the condition at the `@Suite` level so all tests in the suite are skipped together

### Implementation

#### Step 1: Define a Tag extension

Create a new file or add to an existing test utilities file:

**File: `tools/shiki-ctl/Tests/ShikiCtlTests/TestTags.swift`**
```swift
import Testing

extension Tag {
    /// Tests that spawn the compiled binary and assert on exit codes/output.
    /// These require a prior `swift build` and may hang if the binary reads stdin.
    /// Skip with: SKIP_E2E=1 swift test
    @Tag static var e2e: Self
}
```

#### Step 2: Add condition to E2EScenarioTests

**File: `tools/shiki-ctl/Tests/ShikiCtlTests/E2EScenarioTests.swift`**

Add the `.enabled(if:)` trait to the `@Suite`:

```swift
@Suite(
    "E2E Command Scenarios",
    .tags(.e2e),
    .enabled(if: ProcessInfo.processInfo.environment["SKIP_E2E"] == nil)
)
struct E2EScenarioTests {
    // ... existing code unchanged
}
```

When `SKIP_E2E=1` (or any value) is set, the entire suite is skipped with a clear reason.

#### Step 3: Add convenience to the test command

Users can filter tests two ways:

```bash
# Option A: Environment variable (skip E2E)
SKIP_E2E=1 swift test

# Option B: Swift Testing filter (run ONLY E2E)
swift test --filter E2EScenarioTests

# Option C: Swift Testing filter (exclude E2E)
swift test --skip E2EScenarioTests
```

Option A is the recommended approach for CI since it is declarative and self-documenting.

### Files to Modify

| File | Change |
|------|--------|
| `tools/shiki-ctl/Tests/ShikiCtlTests/TestTags.swift` | **NEW** — Tag extension defining `.e2e` |
| `tools/shiki-ctl/Tests/ShikiCtlTests/E2EScenarioTests.swift` | Add `.tags(.e2e)` + `.enabled(if:)` to `@Suite` |

### Tests to Add

| Test | Location | Purpose |
|------|----------|---------|
| `test_e2eSkipFlag_respectsEnvironment` | `E2EScenarioTests.swift` or separate | Verify that when `SKIP_E2E` is set, the suite reports as skipped (meta-test — optional, since Swift Testing handles this natively) |

**Recommendation:** Do NOT add a meta-test. Swift Testing's `.enabled(if:)` is framework-level behavior. Testing it would be testing the framework, not our code. Instead, verify manually once and document.

### Future-Proofing

As more test suites need conditional skipping (e.g., integration tests requiring a running backend, snapshot tests requiring a simulator), extend the pattern:

```swift
extension Tag {
    @Tag static var e2e: Self
    @Tag static var integration: Self    // requires running backend
    @Tag static var snapshot: Self       // requires simulator
}
```

Each suite declares its tag and condition:

```swift
@Suite(.tags(.integration), .enabled(if: ProcessInfo.processInfo.environment["SKIP_INTEGRATION"] == nil))
```

Or use a single `TEST_LEVEL` variable:

```swift
// TEST_LEVEL=unit  → skip e2e + integration + snapshot
// TEST_LEVEL=ci    → skip snapshot only
// (unset)          → run everything
```

This is a design decision for later. For now, `SKIP_E2E` is sufficient and minimal.

---

## Execution Order

| # | Task | Effort | Dependency |
|---|------|--------|------------|
| 1 | **Task 2: E2E skip flag** | 15 min | None — can start immediately |
| 2 | **Task 1: curl→MCP verification** | 5 min | Verify develop has all changes, no action needed |

Task 2 is the only actionable work. Task 1 is already done.

## Estimated Effort

| Task | Lines changed | Time |
|------|--------------|------|
| Task 1: curl→MCP cleanup | 0 (already done on develop) | 0 min active work |
| Task 2: E2E skip flag | ~15 lines (1 new file, 1 edit) | 15 min |
| **Total** | ~15 lines | **15 min** |

## Decision Record

**Q: Should we also migrate curl from Swift source (BackendClient, DBSyncClient, etc.)?**
**A:** No — that is a separate P2 item (NetKit migration). The Swift curl subprocess pattern works and is tested. The skill/command curl cleanup (the actual P0) is done. Don't scope-creep.

**Q: Should we use `--skip` filter or environment variable for E2E?**
**A:** Environment variable via `.enabled(if:)`. It is declarative, works at suite level, and integrates with CI environment configuration. The `--skip` flag requires knowing the test name and does not compose well.
