# P1 Group C — Implementation Specs

**Author**: @Sensei (CTO)
**Date**: 2026-03-23
**Branch**: `feature/p1-group-c`
**Base**: `develop`

---

## Task 1: Session Registry — Replace tmux Parsing in ProcessLauncher

### What & Why

`TmuxProcessLauncher.isSessionRunning()` and `listRunningSessions()` shell out to `tmux list-panes` on every call, parsing stdout strings to determine session state. This is fragile (zsh `precmd` overrides pane titles, race conditions between parse and action) and untestable without a real tmux session.

Meanwhile, `SessionRegistry` already exists as an actor with discover/reconcile/reap and is already injected into `HeartbeatLoop`. But `ProcessLauncher` does not use it — the two systems run in parallel, producing duplicate tmux queries and potentially contradictory state.

The fix: make `ProcessLauncher` delegate `isSessionRunning()` and `listRunningSessions()` to `SessionRegistry`, eliminating the duplicate tmux parsing path. `TmuxProcessLauncher` keeps its launch/stop/capture responsibilities (those genuinely need tmux commands) but no longer owns session state queries.

### Current State

- `SessionRegistry` (actor) already exists at `Sources/ShikiCtlKit/Services/SessionRegistry.swift` with `allSessions`, `sessionsByAttention()`, `register()`, `deregister()`, `refresh()`.
- `HeartbeatLoop` already holds a `registry: SessionRegistry` and calls `await registry.refresh()` every tick.
- `TmuxProcessLauncher.isSessionRunning()` (line 60-64) shells out to tmux.
- `TmuxProcessLauncher.listRunningSessions()` (line 104-128) shells out to tmux, parses `#{pane_title} #{pane_current_command}`.
- `HeartbeatLoop.checkAndDispatch()` calls `launcher.listRunningSessions()` (the tmux path) instead of `registry.allSessions`.
- Tests in `HeartbeatLoopTests.swift` use `MockProcessLauncher` which has its own `runningSlugs` set — no registry involvement.

### Recommendation: Actor-local dictionary (already built)

No new persistence layer needed. `SessionRegistry` is already an actor with an in-memory `[String: RegisteredSession]` dictionary. It reconciles with tmux on every heartbeat `refresh()`. On restart, the first `refresh()` rediscovers all live panes. This is the right answer — SQLite or /tmp JSON would add complexity for zero gain (sessions are ephemeral by nature; if shikki restarts, tmux panes still exist and get rediscovered).

### Implementation Steps

1. **Add query methods to `SessionRegistry`** — `isRunning(slug:) -> Bool` and `runningSlugs() -> [String]` that query the internal dictionary without tmux subprocess calls.

2. **Inject `SessionRegistry` into `TmuxProcessLauncher`** — Add an optional `registry: SessionRegistry?` parameter. When present, `isSessionRunning()` and `listRunningSessions()` delegate to the registry. When nil (standalone use), fall back to the current tmux parsing.

3. **Remove tmux queries from `HeartbeatLoop.checkAndDispatch()`** — Replace `await launcher.listRunningSessions()` with `await registry.runningSlugs()`. The launcher is still used for `launchTaskSession()` and `stopSession()`.

4. **Wire up in `HeartbeatLoop.init`** — Pass the registry to the launcher so both share the same source of truth.

5. **Update `MockProcessLauncher`** — Remove `runningSlugs` set. Instead, have it delegate to a `MockSessionRegistry` (or keep a thin set for tests that don't need full registry behavior).

### Files to create/modify

| File | Action |
|------|--------|
| `Sources/ShikiCtlKit/Services/SessionRegistry.swift` | Add `isRunning(slug:)`, `runningSlugs()` |
| `Sources/ShikiCtlKit/Services/CompanyLauncher.swift` | Add optional `registry` param, delegate queries |
| `Sources/ShikiCtlKit/Services/HeartbeatLoop.swift` | Replace `launcher.listRunningSessions()` with `registry.runningSlugs()` in `checkAndDispatch()`, `cleanupIdleSessions()`, `checkAnsweredDecisions()`, `checkStaleCompaniesSmart()` |
| `Tests/ShikiCtlKitTests/HeartbeatLoopTests.swift` | Update mocks to use registry |
| `Tests/ShikiCtlKitTests/SessionRegistryTests.swift` | Add tests for `isRunning()`, `runningSlugs()` |

### Tests

- `SessionRegistry.isRunning()` returns true for registered sessions, false for unknown slugs.
- `SessionRegistry.runningSlugs()` returns all non-reserved window names.
- `HeartbeatLoop.checkAndDispatch()` skips dispatch when registry reports slots full.
- `TmuxProcessLauncher` falls back to tmux parsing when no registry is injected.

### Sub-agent split

Single sub-agent. ~120 LOC changes, all in the same dependency chain. No parallelism possible.

### Dependencies

None. SessionRegistry already exists. This is pure wiring.

---

## Task 2: Autopilot Prompt from Template File

### What & Why

The autopilot prompt is hardcoded in `TmuxProcessLauncher.buildAutopilotPrompt()` (lines 189-235 of CompanyLauncher.swift). Every change requires recompilation. Users cannot customize per-workspace or per-company instructions. The prompt is the single most-tweaked piece of the orchestrator — it should be a template file.

### Current State

- `buildAutopilotPrompt()` is a `private static func` that string-interpolates `companyId`, `companySlug`, `taskId`, `title`.
- Called from `launchTaskSession()` (line 44).
- No template loading infrastructure exists.
- No config directory convention beyond `~/.config/shiki-notify/` (for ntfy).

### Implementation Steps

1. **Define template format** — Mustache-lite with 6 variables. No logic blocks, no partials, no escaping — pure find-and-replace. Variables:

   ```
   {{companyId}}       — UUID of the company
   {{companySlug}}     — URL-safe company name
   {{taskId}}          — UUID of the task (empty string for fallback launches)
   {{taskTitle}}       — Human-readable task title
   {{claimInstruction}} — Pre-built claim block (conditional on taskId presence)
   {{apiBaseURL}}      — Orchestrator API base (default http://localhost:3900)
   ```

   The `{{claimInstruction}}` block is computed by the code (it has conditional logic) and injected as a variable. The rest of the template is static text with placeholders.

2. **Create `PromptTemplateLoader`** — A struct (not actor, it is stateless) with:

   ```swift
   public struct PromptTemplateLoader: Sendable {
       /// Resolution chain: custom → bundled → hardcoded
       func loadTemplate() -> String
       /// Replace {{variables}} with values
       func render(template: String, variables: [String: String]) -> String
   }
   ```

   Resolution chain:
   - `~/.config/shiki/autopilot-prompt.md` — user override (per-machine)
   - `{workspacePath}/.shiki/autopilot-prompt.md` — workspace override (per-project)
   - Bundled default in SPM resource bundle — ships with binary
   - Hardcoded string constant — last resort (current behavior, never deleted)

   Priority: workspace > user > bundled > hardcoded. Most specific wins.

3. **Bundled default template** — Add `Resources/autopilot-prompt.md` to the SPM target. This becomes the "factory default" that ships with every binary. Content is the current hardcoded string, but with `{{placeholders}}`.

4. **Hot-reload on heartbeat tick** — `PromptTemplateLoader` caches the loaded template string and its source file's `modificationDate`. On each call to `loadTemplate()`, it checks `FileManager.attributesOfItem` for the mtime. If changed, re-reads the file. Cost: one `stat()` per heartbeat (60s) — negligible.

   Implementation: `PromptTemplateLoader` becomes a class (or uses a static cache) to hold the cached template + mtime. Thread-safe via `@Sendable` closure or `OSAllocatedUnfairLock`.

5. **Wire into `TmuxProcessLauncher`** — Replace `Self.buildAutopilotPrompt(...)` call with `templateLoader.render(template: templateLoader.loadTemplate(), variables: [...])`. The `claimInstruction` variable is still computed by Swift code, then passed as a variable to the template.

6. **CLI integration** — `shikki config show` prints the resolved template path. `shikki config edit prompt` opens it in `$EDITOR`.

### Template file content (default)

```markdown
You are an autonomous agent for the "{{companySlug}}" company in the Shiki orchestrator.

ORCHESTRATOR API: {{apiBaseURL}}

YOUR WORKFLOW:
{{claimInstruction}}
2. Work on the claimed task in this project directory
3. If you need a human decision, create one: POST /api/decision-queue with {"companyId":"{{companyId}}","taskId":"<task-id>","tier":1,"question":"<your question>"}
4. When done, update the task: PATCH /api/task-queue/<task-id> with {"status":"completed","result":{"summary":"what you did"}}
5. Claim the next task and repeat

HEARTBEAT (every 60s):
POST /api/orchestrator/heartbeat with:
{"companyId":"{{companyId}}","sessionId":"<your-session-id>","data":{
  "contextPct": <your current context usage %>,
  "compactionCount": <times you have been compacted this session>,
  "taskInProgress": "<current task title>"
}}

RULES:
- Follow TDD: write failing test first, then implement
- Run the full test suite after every change
- Use /pre-pr before any PR
- Send heartbeats every 60s with context data
- If you hit a blocker that needs human input, create a T1 decision and move to the next task
- Never push to main directly — use feature branches and PRs to develop

START NOW: claim your first task and begin working.
```

### Files to create/modify

| File | Action |
|------|--------|
| `Sources/ShikiCtlKit/Services/PromptTemplateLoader.swift` | **New** — loader + renderer + cache |
| `Sources/ShikiCtlKit/Resources/autopilot-prompt.md` | **New** — bundled default template |
| `Sources/ShikiCtlKit/Services/CompanyLauncher.swift` | Replace `buildAutopilotPrompt()` with `PromptTemplateLoader` call |
| `Package.swift` | Add `.process("Resources")` to ShikiCtlKit target resources |
| `Tests/ShikiCtlKitTests/PromptTemplateLoaderTests.swift` | **New** |

### Tests

- `render()` replaces all `{{variables}}` correctly, leaves unknown `{{placeholders}}` untouched.
- `render()` with empty variables dict returns template as-is.
- `loadTemplate()` prefers workspace file over user file over bundled.
- `loadTemplate()` falls back to bundled when no custom files exist.
- Hot-reload: modify file on disk, verify next `loadTemplate()` returns updated content.
- Hardcoded fallback: when bundled resource is missing (edge case), returns the constant.

### Sub-agent split

Single sub-agent. The loader, template file, wiring, and tests are tightly coupled — splitting would create merge conflicts.

### Dependencies

None. Pure additive — does not depend on Task 1 or Task 3.

---

## Task 3: HeartbeatLoop Unit Tests

### What & Why

`HeartbeatLoopTests.swift` currently has 3 tests that only exercise `MockProcessLauncher` and `MockNotificationSender` in isolation — they never instantiate `HeartbeatLoop` or call any of its methods. The core dispatcher (`checkAndDispatch`), cleanup (`cleanupIdleSessions`), stale detection (`checkStaleCompaniesSmart`), and decision handling (`checkDecisions`, `checkAnsweredDecisions`) have zero test coverage. These are the most critical paths in the orchestrator.

### Current State

- `HeartbeatLoop` is an actor with 5 internal methods: `checkAndDispatch()`, `cleanupIdleSessions()`, `checkDecisions()`, `checkAnsweredDecisions()`, `checkStaleCompaniesSmart()`.
- All methods are `func` (not `public`) but accessible from `@testable import`.
- Dependencies: `BackendClient` (actor, concrete class — no protocol), `ProcessLauncher` (protocol, mockable), `NotificationSender` (protocol, mockable), `SessionRegistry` (actor, takes a `SessionDiscoverer` protocol).
- `BackendClient` is NOT a protocol — it is a concrete actor that shells out to `curl`. This is the main testing obstacle.
- Existing mocks: `MockProcessLauncher`, `MockNotificationSender` (in HeartbeatLoopTests.swift), `MockSessionDiscoverer` (in SessionRegistryTests.swift).

### Mock Protocols Needed

**1. `BackendClientProtocol`** — Extract protocol from `BackendClient` actor.

```swift
public protocol BackendClientProtocol: Sendable {
    func healthCheck() throws -> Bool
    func getStatus() async throws -> OrchestratorStatus
    func getStaleCompanies(thresholdMinutes: Int) async throws -> [Company]
    func getDispatcherQueue() async throws -> [DispatcherTask]
    func getPendingDecisions() async throws -> [Decision]
    func getCompanies(status: String?) async throws -> [Company]
    func createSessionTranscript(_ input: SessionTranscriptInput) async throws -> SessionTranscript
}
```

Then `BackendClient` conforms to `BackendClientProtocol`, and `HeartbeatLoop` takes `BackendClientProtocol` instead of `BackendClient`.

**2. `MockBackendClient`** — Test double.

```swift
final class MockBackendClient: BackendClientProtocol, @unchecked Sendable {
    var healthCheckResult: Bool = true
    var dispatcherQueue: [DispatcherTask] = []
    var pendingDecisions: [Decision] = []
    var staleCompanies: [Company] = []
    var statusResponse: OrchestratorStatus = .empty
    var companies: [Company] = []
    var createdTranscripts: [SessionTranscriptInput] = []

    // Each method returns the configured value
}
```

**3. `MockProcessLauncher`** — Already exists, needs minor updates (track `captureSessionOutput` calls).

**4. `MockNotificationSender`** — Already exists, sufficient as-is.

### Implementation Steps

1. **Extract `BackendClientProtocol`** — New file `Protocols/BackendClientProtocol.swift`. Add conformance to existing `BackendClient`. Change `HeartbeatLoop.init` from `client: BackendClient` to `client: any BackendClientProtocol`. This is the gating step — all test methods depend on being able to inject a mock backend.

2. **Create `MockBackendClient`** in test target.

3. **Create `HeartbeatLoopTestHelpers.swift`** — Factory function:

   ```swift
   func makeHeartbeatLoop(
       client: BackendClientProtocol? = nil,
       launcher: ProcessLauncher? = nil,
       notifier: NotificationSender? = nil
   ) -> (HeartbeatLoop, MockBackendClient, MockProcessLauncher, MockNotificationSender)
   ```

4. **Write tests for each method**:

#### `checkAndDispatch()` — 7 tests

| Test | Scenario |
|------|----------|
| `dispatchesReadyTask` | 1 ready task, 0 running → launches session |
| `respectsMaxConcurrentSlots` | 6 running sessions → skips dispatch |
| `respectsBudgetLimit` | `spentToday >= dailyUsd` → skips task |
| `respectsScheduleWindow` | Task outside schedule → skips |
| `skipsAlreadyRunningCompany` | Company already has session → skips |
| `dispatchesMultipleTasksUpToSlotLimit` | 3 ready, 4 slots → launches 3 |
| `registersSessionInRegistry` | After launch, registry contains the session |

#### `cleanupIdleSessions()` — 4 tests

| Test | Scenario |
|------|----------|
| `killsInactiveCompanySessions` | Company not in `activeCompanies` → stops session |
| `keepsActiveCompanySessions` | Company still active → session untouched |
| `capturesTranscriptBeforeKill` | Verifies `createSessionTranscript` called before stop |
| `handlesEmptyRunningList` | No running sessions → no-op, no API calls |

#### `checkDecisions()` — 4 tests

| Test | Scenario |
|------|----------|
| `notifiesOnNewT1Decision` | New T1 decision → ntfy notification sent |
| `skipsAlreadyNotifiedDecisions` | Same decision on second tick → no duplicate notification |
| `cleansUpAnsweredDecisions` | Decision disappears from pending → removed from notifiedIds |
| `ignoresNonT1Decisions` | T2/T3 decisions → no notification |

#### `checkAnsweredDecisions()` — 3 tests

| Test | Scenario |
|------|----------|
| `detectsAnsweredDecisions` | Decision pending in tick N, gone in tick N+1 → logs re-dispatch hint |
| `noActionWhenNoneAnswered` | Same decisions both ticks → no log |
| `tracksPreviousPendingIds` | Verifies internal state updates between calls |

#### `checkStaleCompaniesSmart()` — 5 tests

| Test | Scenario |
|------|----------|
| `relaunchesStaleWithPendingTasks` | Stale company + has tasks + no session → launches |
| `skipsStaleWithoutTasks` | Stale company + no tasks → skips |
| `skipsStaleWithRunningSession` | Stale company + session running → skips |
| `skipsStaleWithExhaustedBudget` | Stale + tasks but budget spent → skips |
| `handlesEmptyStaleList` | No stale companies → no API calls |

**Total: 23 new tests.**

### Files to create/modify

| File | Action |
|------|--------|
| `Sources/ShikiCtlKit/Protocols/BackendClientProtocol.swift` | **New** — extracted protocol |
| `Sources/ShikiCtlKit/Services/BackendClient.swift` | Add `: BackendClientProtocol` conformance |
| `Sources/ShikiCtlKit/Services/HeartbeatLoop.swift` | Change `client: BackendClient` → `client: any BackendClientProtocol` |
| `Tests/ShikiCtlKitTests/Mocks/MockBackendClient.swift` | **New** |
| `Tests/ShikiCtlKitTests/HeartbeatLoopTests.swift` | Rewrite — 23 tests replacing the 3 shallow ones |

### Tests

See the 23-test matrix above. Each test instantiates a real `HeartbeatLoop` actor with mock dependencies, calls the specific method, and asserts on mock state (launched sessions, sent notifications, stopped slugs, created transcripts).

### Sub-agent split

**Two sub-agents in sequence:**

1. **Agent A** — Extract `BackendClientProtocol`, update `BackendClient` conformance, update `HeartbeatLoop` signature. Compile-verify. This is the prerequisite.
2. **Agent B** — Write all 23 tests + `MockBackendClient`. Depends on Agent A completing (needs the protocol to compile).

Cannot parallelize because Agent B's test file imports the protocol Agent A creates.

### Dependencies

- Depends on Task 1 if we want tests to use `registry.runningSlugs()` instead of `launcher.listRunningSessions()`. However, the tests can be written against the current interface first and updated in Task 1's PR. **Recommendation: implement Task 3 first against current interface, then Task 1 updates the tests.**
- No dependency on Task 2.

---

## Execution Order

```
Task 3 (Agent A: extract protocol) → Task 3 (Agent B: 23 tests)
                                            ↓
Task 1 (registry wiring — updates tests from Task 3)
Task 2 (template loader — independent, can run in parallel with Task 1)
```

Three PRs total, each targeting `develop`.
