# High-Risk Code Walkthrough

**Date**: 2026-03-30
**Branches reviewed**: `feature/codegen-engine`, `feature/killer-features`, `feature/enterprise-safety`, `feature/nats-node-discovery-v2`
**Reviewer**: Claude Opus 4.6

---

## 1. feature/codegen-engine -- Self-Healing Fix Loop

### [CodeGen] -- Fix Loop Iteration Cap

**File**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
**Lines**: 72-79
**Risk Level**: MEDIUM

**What it does**:
The fix loop runs up to `maxIterations = 3` attempts to fix test failures via AI agents. Each iteration dispatches agents, then re-runs tests to see if failures decreased.

**The risk**:
The cap of 3 exists and is enforced. However, within each iteration the agent runner has no timeout constraint visible in this code -- if the agent hangs or produces a very slow response, the loop stalls indefinitely. There is no per-iteration wall-clock timeout.

**Code excerpt**:
```swift
public static let maxIterations = 3

// ...
for iteration in 1...Self.maxIterations {
    // ...
    let result = try await agentRunner.run(
        prompt: prompt,
        workingDirectory: projectRoot,
        unitId: unit.id
    )
    agentResults.append(result)
}
```

**Verdict**: SAFE (cap exists), NEEDS FIX (no per-iteration timeout)
**Recommendation**: Add a `Task.timeout` or `withThrowingTaskGroup` deadline around each `agentRunner.run` call to prevent indefinite hangs. The `AgentRunner` protocol should declare a timeout parameter.

---

### [CodeGen] -- No Rollback on Regression

**File**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
**Lines**: 114-122
**Risk Level**: HIGH

**What it does**:
After each fix iteration, the engine re-runs tests and computes `fixedThisIteration = previousCount - currentFailures.count`. If the count goes negative (more failures than before), the code clamps to `max(0, fixedThisIteration)` and continues.

**The risk**:
If a fix agent introduces NEW failures, the code does not rollback the agent's changes. It just records `fixedCount: 0` and proceeds to the next iteration. The codebase is now in a worse state than before, and subsequent iterations build on corrupted code. The early-exit on "no progress" (`fixedThisIteration <= 0 && iteration > 1`) helps limit damage but does not undo it.

**Code excerpt**:
```swift
let previousCount = currentFailures.count
currentFailures = testResult.failures
let fixedThisIteration = previousCount - currentFailures.count

let iterResult = FixIterationResult(
    iteration: iteration,
    fixedCount: max(0, fixedThisIteration),
    remainingFailures: currentFailures,
    agentResults: agentResults
)
// ...
// No progress? Don't loop more
if fixedThisIteration <= 0 && iteration > 1 {
    onProgress?(.noProgress(iteration: iteration))
    break
}
```

**Verdict**: NEEDS FIX
**Recommendation**: Before each fix iteration, snapshot the current git state (e.g., `git stash` or record the commit hash). If `fixedThisIteration < 0` (regression), `git checkout` back to the snapshot. This is the biggest safety gap in the codegen pipeline -- an AI agent can make things arbitrarily worse with no undo mechanism.

---

### [CodeGen] -- Agent Applies Arbitrary Code Without Human Gate

**File**: `projects/shikki/Sources/ShikkiKit/CodeGen/CodeGenerationPipeline.swift`
**Lines**: 195-220
**Risk Level**: HIGH

**What it does**:
The full pipeline runs `parse -> verify -> plan -> dispatch -> merge -> fix -> cache` in sequence. There is no human confirmation gate between any stage. The `dispatch` stage sends AI agents to write code in worktrees, `merge` rebases them into the main branch, and `fix` lets agents modify code further.

**The risk**:
Once the pipeline starts (and `isDryRun == false`), agents write, merge, and fix code autonomously. There is a `DryRunCodeGenContext` that captures commands without executing, which is good. But the real context path has zero confirmation steps. An agent could modify protocol implementations, change business logic, or introduce subtle bugs.

**Code excerpt**:
```swift
// Stage 4: Dispatch
let dispatchResult = try await dispatch(plan, layer: layer, cache: existingCache)

// Stage 5: Merge (parallel strategies only)
var mergeResult: MergeResult?
if plan.strategy != .sequential {
    mergeResult = try await merge(dispatchResult, plan: plan)
}

// Stage 6: Fix (if tests failed)
var fixResult: FixResult?
let testFailures = mergeResult?.testFailures ?? []
if !testFailures.isEmpty {
    fixResult = try await fix(testFailures, layer: layer, cache: existingCache)
}
```

**Verdict**: NEEDS FIX
**Recommendation**: Add an optional `humanGate` callback (or `ConfirmationGate` protocol) between the dispatch and merge stages, and between merge and fix. In CI/automated mode it can be a no-op; in interactive mode it should present a diff summary and wait for approval. The prompt already says "fix implementation code, NOT tests" which is good guardrail text, but text in a prompt is not enforcement.

---

### [CodeGen] -- Fix Prompt Scope Is Unbounded

**File**: `projects/shikki/Sources/ShikkiKit/CodeGen/FixEngine.swift`
**Lines**: 164-195
**Risk Level**: MEDIUM

**What it does**:
The fix prompt tells the agent to "fix implementation code to make the tests pass" and says "do not modify protocol definitions." The agent receives failure details, protocol contracts, and architecture context.

**The risk**:
The constraint is purely prompt-based. The agent could modify tests (despite being told not to), add new files, change unrelated code, or break protocols. There is no post-fix verification that only implementation files were modified and that protocol files remain unchanged. The `ContractVerifier` is only invoked in the `verifyContracts` stage, not after fix.

**Code excerpt**:
```swift
lines.append("## Rules")
lines.append("- Fix implementation code, NOT tests")
lines.append("- Do not modify protocol definitions")
lines.append("- Run `swift test` to verify your fix before finishing")
lines.append("- Keep changes minimal -- fix only what's broken")
```

**Verdict**: NEEDS TEST
**Recommendation**: After each fix iteration, re-run `verifyContracts` to confirm protocol integrity is preserved. Also consider a git-diff filter that rejects changes to `*Tests.swift` files and protocol definition files. This is defense-in-depth against prompt non-compliance.

---

### [CodeGen] -- Missing Integration Tests for Fix Loop

**File**: `projects/shikki/Tests/ShikkiKitTests/CodeGen/FixEngineTests.swift`
**Risk Level**: MEDIUM

**What it does**:
The test suite covers fix unit creation, prompt generation, error cases, and result tracking. Uses a `MockFixAgentRunner` that always returns `.completed`.

**The risk**:
No integration test actually runs the fix loop with a mock that simulates test re-runs. The mock always succeeds, so the "no progress" early-exit path, the regression path (more failures after fix), and the "all fixed after N iterations" path are never exercised end-to-end. Only the unit-level behaviors are tested.

**Verdict**: NEEDS TEST
**Recommendation**: Add a `MockMergeEngine` (or make `runTests` injectable) to simulate:
1. Fix iteration that reduces failures (happy path, 2 iterations)
2. Fix iteration that introduces new failures (regression, should ideally rollback)
3. Fix iteration with no progress (should break early after iteration 2)
4. All 3 iterations exhausted with remaining failures

---

## 2. feature/killer-features -- Template Marketplace

### [Templates] -- No Code Execution During Install (SAFE)

**File**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
**Lines**: 120-148
**Risk Level**: LOW

**What it does**:
`install()` reads a JSON file, decodes it into a `ProjectTemplate`, validates name/ID are non-empty, and saves it to the index. No code is executed during install.

**The risk**:
Minimal. Install is pure data persistence -- JSON decode + save. There is no post-install hook, no script execution, no network fetch (GitHub install is a placeholder that prints "coming soon").

**Code excerpt**:
```swift
public func install(template: ProjectTemplate, source: TemplateSource, sourceURL: String? = nil) throws {
    var installed = loadIndex()
    if installed.contains(where: { $0.template.id == template.id }) {
        throw RegistryError.templateAlreadyInstalled(template.id)
    }
    guard !template.name.isEmpty, !template.id.isEmpty else {
        throw RegistryError.invalidTemplate("Template must have a name and ID")
    }
    // ...
    try saveIndex(installed)
}
```

**Verdict**: SAFE
**Recommendation**: None for v1. When GitHub install is implemented, ensure the downloaded JSON is validated identically and no post-install scripts are executed.

---

### [Templates] -- Apply Creates Executable Files

**File**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
**Lines**: 158-185
**Risk Level**: MEDIUM

**What it does**:
`apply()` writes template files to disk. If `TemplateFile.executable == true`, it sets POSIX permissions to `0o755` on that file.

**The risk**:
A malicious template (installed from a local JSON or future GitHub source) could include an executable script in its files list. The template `apply` only writes files -- it does not execute them. However, a subsequent `swift build` or shell command could trigger them if they end up in a build script path. Also, the `relativePath` is not sanitized for path traversal (e.g., `../../.zshrc`).

**Code excerpt**:
```swift
for file in template.files {
    let filePath = (path as NSString).appendingPathComponent(file.relativePath)
    // ...
    try content.write(toFile: filePath, atomically: true, encoding: .utf8)

    if file.executable {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: filePath)
    }
    created.append(file.relativePath)
}
```

**Verdict**: NEEDS FIX
**Recommendation**:
1. **Path traversal**: Validate that `file.relativePath` does not contain `..` components. Resolve the path and confirm it stays within the target directory.
2. **Executable audit**: Log a warning when applying executable files. Consider requiring `--allow-exec` flag for templates that contain executable files.
3. Good: `apply` does not execute files, only writes them. The `force` flag is opt-in.

---

### [Templates] -- Variable Substitution Is Limited (SAFE)

**File**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
**Lines**: 232-234
**Risk Level**: LOW

**What it does**:
Variable substitution is a single `replaceOccurrences` for `{{PROJECT_NAME}}`. No eval, no shell expansion, no recursive substitution.

**The risk**:
None. This is about as safe as template substitution gets. No injection vector exists.

**Code excerpt**:
```swift
func substituteVariables(_ content: String, projectName: String) -> String {
    content.replacingOccurrences(of: "{{PROJECT_NAME}}", with: projectName)
}
```

**Verdict**: SAFE
**Recommendation**: None.

---

### [Templates] -- No Signature Verification

**File**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
**Risk Level**: LOW (currently), HIGH (when GitHub install ships)

**What it does**:
Templates are stored as plain JSON with no signing, hash verification, or integrity check.

**The risk**:
For v1 with local-only install, this is acceptable. When the GitHub install path is implemented, a malicious or tampered template could be installed without verification. The `installFromGitHub` function currently prints a placeholder message and does nothing.

**Code excerpt**:
```swift
private func installFromGitHub(registry: TemplateRegistry) {
    print(styled("GitHub install coming soon.", .yellow))
}
```

**Verdict**: SAFE (for now)
**Recommendation**: Before shipping GitHub install: (1) add SHA-256 hash verification, (2) consider GPG signature for "verified" templates, (3) at minimum validate the JSON schema strictly after download.

---

### [Templates] -- Test Coverage Is Solid

**File**: `projects/shikki/Tests/ShikkiKitTests/TemplateRegistryTests.swift`
**Risk Level**: LOW

**What it does**:
30 tests covering: builtins listing, get/search, install/uninstall, apply with force/skip, variable substitution, persistence, equatable, and error cases.

**The risk**:
Missing test: path traversal in `apply` (e.g., template with `relativePath: "../../etc/cron.d/evil"`). Missing test: template with very large file content (memory exhaustion). Both are edge cases but relevant for a file-writing operation.

**Verdict**: NEEDS TEST
**Recommendation**: Add a test that verifies `apply` rejects or safely handles `relativePath` containing `..`. Add a test for executable file permission setting.

---

## 3. feature/enterprise-safety -- Budget ACL + Anomaly Detection

### [Safety] -- Budget Check-Then-Spend Is Not Atomic

**File**: `projects/shikki/Sources/ShikkiKit/Safety/AuditLogger.swift`
**Lines**: 82-119
**Risk Level**: MEDIUM

**What it does**:
`logToolCall` first calls `acl.check()` to verify the user is within budget, then (if allowed) later calls `acl.recordSpend()` to debit the cost. Both BudgetACL and AuditLogger are actors, so individual method calls are serialized.

**The risk**:
The check-then-spend is not atomic across the two calls. Between `check()` returning `.allowed` and `recordSpend()` executing, another concurrent `logToolCall` for the same user could also pass the budget check. This is a classic TOCTOU (Time-Of-Check-Time-Of-Use) race condition. With actors, each call is serialized on the actor, but `AuditLogger.logToolCall` awaits the BudgetACL actor, releases AuditLogger's isolation, and another `logToolCall` can interleave.

**Code excerpt**:
```swift
// In AuditLogger (actor):
budgetResult = await acl.check(...)     // <-- await suspends AuditLogger
// ... other logToolCall can run here ...
if case .allowed = budgetResult {
    await acl.recordSpend(...)           // <-- await suspends again
}
```

**Verdict**: NEEDS FIX
**Recommendation**: Add a `checkAndRecord` atomic method on the `BudgetACL` actor that does both the check and the spend in a single actor-isolated call, eliminating the TOCTOU window. Example:
```swift
// On BudgetACL actor:
public func checkAndSpend(userId:, ..., costUsd:) async -> BudgetCheckResult {
    let result = check(...)  // no await -- same actor
    if case .allowed = result {
        recordSpend(...)     // no await -- same actor
    }
    return result
}
```

---

### [Safety] -- Budget Bypass via Missing Policy

**File**: `projects/shikki/Sources/ShikkiKit/Safety/BudgetACL.swift`
**Lines**: 91-117
**Risk Level**: MEDIUM

**What it does**:
The `check()` method iterates all budget periods. If no policy is found for any period, it returns `.noPolicyDefined`. The caller (AuditLogger) treats `.noPolicyDefined` as allowed -- it does not block.

**The risk**:
If a workspace admin forgets to set a budget policy (or sets it for `.daily` but not `.monthly`), all tool calls proceed without any budget limit. This is a fail-open design. For single-user Shikki this is fine. For enterprise multi-tenant, a missing policy should arguably default to a conservative cap, not unlimited.

**Code excerpt**:
```swift
if let remaining = tightestRemaining {
    return .allowed(remainingUsd: remaining)
}
return .noPolicyDefined  // <-- no policy = no enforcement
```

In AuditLogger:
```swift
// budgetResult is nil when no ACL configured, or .noPolicyDefined
// Neither triggers .blocked -- the call proceeds
```

**Verdict**: SAFE (for v1 single-user), NEEDS FIX (before enterprise)
**Recommendation**: For enterprise: add a `requirePolicy: Bool` configuration. When true, `.noPolicyDefined` should be treated as `.blocked(reason: "No budget policy configured")`. Add a test for the explicit fail-open vs fail-closed behavior.

---

### [Safety] -- In-Memory Ledger Loses Data on Crash

**File**: `projects/shikki/Sources/ShikkiKit/Safety/BudgetACL.swift`
**Lines**: 119-134
**Risk Level**: MEDIUM

**What it does**:
All budget spend entries are stored in an in-memory array on the `BudgetACL` actor. There is no persistence.

**The risk**:
If the process crashes or restarts mid-period, all spend tracking is lost. A user who spent $9.50 of a $10.00 daily budget can restart the process and get a fresh $10.00. The comment "for period reset" on `clearLedger()` hints this is known.

**Verdict**: SAFE (for v1), NEEDS FIX (before enterprise)
**Recommendation**: Persist ledger entries to disk (append-only JSONL file) or to ShikiDB. On startup, replay the current period's entries to reconstruct spend totals. The `BudgetLedgerEntry` is already `Codable`, so this is straightforward.

---

### [Safety] -- SecurityPatternDetector Uses Wall-Clock `Date()` in Detection

**File**: `projects/shikki/Sources/ShikkiKit/Safety/SecurityPatternDetector.swift`
**Lines**: 85-103
**Risk Level**: LOW

**What it does**:
Detection methods like `detectBulkExtraction()` compute the window start as `Date().addingTimeInterval(-config.bulkExtractionWindowSeconds)`. The records have their own timestamps from when they were recorded.

**The risk**:
The detector uses `Date()` at detection time rather than a testable clock. However, records are stamped at record time (also `Date()`). The tests work because they record and detect in quick succession. In production, there is a subtle inconsistency: the window is computed from "now" at detection time, not from the latest record time. This could cause a brief detection gap if `detect()` is called significantly after the last `record()`.

**Verdict**: SAFE (acceptable for current usage)
**Recommendation**: For consistency, consider injecting a `Clock` protocol (like BudgetACL does with `BudgetClock`). Low priority since the current approach works correctly in practice.

---

### [Safety] -- Anomaly Detection Actions Are Advisory Only

**File**: `projects/shikki/Sources/ShikkiKit/Safety/SecurityAnomaly.swift`
**Lines**: 51-72
**Risk Level**: MEDIUM

**What it does**:
`SecurityPolicyMap.action(for:)` maps each anomaly to an action like `.blockAndAlert` or `.logOnly`. But the detector only records incidents and invokes the `onIncidentDetected` callback.

**The risk**:
Despite `.blockAndAlert` being the action for `bulkExtraction`, nothing actually blocks. The action is metadata on the `SecurityIncident` struct. The caller must implement the blocking logic. In the current code, `AuditLogger.detectSecurityAnomalies()` returns incidents but does not feed them back into the budget check or request pipeline. A bulk extraction event is logged but not prevented.

**Code excerpt**:
```swift
// SecurityPolicyMap says:
case .bulkExtraction: return .blockAndAlert

// But SecurityPatternDetector only does:
incidents.append(incident)
await onIncidentDetected?(incident)
// No blocking happens
```

**Verdict**: NEEDS FIX
**Recommendation**: Wire the `.blockAndAlert` and `.throttleAndAlert` actions into the request pipeline. When `detect()` returns an incident with `.blockAndAlert`, the `AuditLogger` (or a middleware layer) should temporarily block the offending user's subsequent calls until an admin clears the incident. This is the gap between "making security visible" and "enforcing security."

---

### [Safety] -- Test Coverage Assessment

**File**: `projects/shikki/Tests/ShikkiKitTests/SafetyTests.swift`
**Risk Level**: LOW

**What it does**:
Comprehensive test suite: 40+ tests covering AuditEvent, AuditQuery, AuditReport, InMemoryAuditStore, AuditLogger (with budget + security integration), BudgetACL (under/over budget, inheritance, workspace isolation, callbacks), SecurityPatternDetector (all 6 anomaly types, no-false-positives, no-duplicates, window trimming, callback), BudgetClock variants.

**Missing test scenarios**:
1. **TOCTOU race**: No concurrent budget check test (two simultaneous `logToolCall` calls for the same user near the budget limit)
2. **Negative cost**: No test for `estimatedCostUsd: -1.0` (could a negative cost increase remaining budget?)
3. **Floating point edge**: No test for very small costs near the boundary (e.g., cap $1.00, spent $0.999999999)
4. **Period rollover**: No test for spend that crosses a period boundary (e.g., spend at 23:59, check at 00:01 next day)

**Verdict**: NEEDS TEST
**Recommendation**: Add the 4 missing test scenarios listed above. Priority: TOCTOU race test (even if it only demonstrates the issue), negative cost validation, and period rollover.

---

## 4. BONUS: feature/nats-node-discovery-v2 -- Auth Check

### [NATS] -- Unauthenticated Node Registration

**File**: `projects/shikki/Sources/ShikkiKit/NATS/NodeRegistry.swift`
**Lines**: 40-50
**Risk Level**: HIGH

**What it does**:
Any process that can publish to `shikki.discovery.announce` can register as a node. The `register()` method accepts a `NodeIdentity` and adds it to the registry with no authentication, no token verification, no challenge-response.

**The risk**:
A rogue process on the same NATS bus can inject a fake node with `role: .primary`, causing the mesh to believe there is a second primary. It can also inject nodes with fake `hostname` / `binaryVersion` to pollute the topology map. Since `NodeHeartbeat.start()` subscribes to announcements and auto-registers incoming heartbeats, the attack surface is any NATS publisher.

**Code excerpt**:
```swift
// NodeRegistry:
public func register(_ identity: NodeIdentity) {
    nodes[identity.nodeId] = NodeEntry(
        identity: identity,
        lastSeen: Date(),
        isStale: false
    )
}

// NodeHeartbeat (subscribes to announcements):
for await message in stream {
    guard let payload = try? heartbeatDecoder.decode(HeartbeatPayload.self, from: message.data) else {
        continue
    }
    await capturedRegistry.register(payload.identity)  // <-- auto-registers anything
}
```

**Verdict**: NEEDS FIX
**Recommendation**: Implement a shared secret or token-based auth for node registration:
1. **Minimum**: A pre-shared `meshToken` that must be included in `HeartbeatPayload` and validated before `register()`.
2. **Better**: NATS subject-level authorization (NATS supports per-subject ACLs). Restrict `shikki.discovery.announce` publish permissions to authenticated clients.
3. **Best**: Mutual TLS on the NATS connection, so only trusted binaries can connect at all.

---

### [NATS] -- Primary Role Self-Declaration Without Consensus

**File**: `projects/shikki/Sources/ShikkiKit/NATS/NodeIdentity.swift`
**Lines**: 47-62
**Risk Level**: HIGH

**What it does**:
A node declares its own role (including `.primary`) in its `NodeIdentity`. The `NodeRegistry.primaryNode` simply returns the first non-stale node with `role == .primary`. There is no leader election, no consensus protocol, no verification that only one primary exists.

**The risk**:
Multiple nodes can simultaneously claim `role: .primary`. The registry will return whichever it happens to find first. A split-brain scenario where two nodes both believe they are primary could lead to duplicate dispatch loops, conflicting git operations, or double-spending on AI API calls.

**Code excerpt**:
```swift
// NodeIdentity -- role is self-declared:
public static func current(
    nodeId: String,
    binaryVersion: String = "0.3.0-pre",
    role: NodeRole = .primary          // <-- defaults to primary!
) -> NodeIdentity { ... }

// NodeRegistry -- returns first primary found:
public var primaryNode: NodeIdentity? {
    nodes.values
        .filter { !$0.isStale && $0.identity.role == .primary }
        .map(\.identity)
        .first
}
```

**Verdict**: NEEDS FIX
**Recommendation**: Implement leader election. Options:
1. **NATS JetStream KV**: Use a NATS KV store with a lease/TTL as a distributed lock. First node to acquire the lock becomes primary.
2. **Simple fencing**: The registry should reject a `.primary` registration if another active primary already exists. Force the new node into `.shadow` and log a warning.
3. **At minimum**: Add a `primaryCount` property and a health check that fires an alert when `primaryCount > 1`.

---

### [NATS] -- Heartbeat Spoofing

**File**: `projects/shikki/Sources/ShikkiKit/NATS/NodeHeartbeat.swift`
**Lines**: 114-130
**Risk Level**: MEDIUM

**What it does**:
The heartbeat payload includes `uptimeSeconds`, `activeAgents`, and `contextUsedPct`. These are self-reported by the node with no verification.

**The risk**:
A spoofed heartbeat can report false metrics. If any future scheduling logic uses `activeAgents` or `contextUsedPct` to make dispatch decisions (e.g., "send work to the node with lowest context usage"), a malicious node could attract or deflect work. Currently these fields are set to `0` in `publishHeartbeat()` and unused, so the risk is theoretical.

**Code excerpt**:
```swift
let payload = HeartbeatPayload(
    identity: identity,
    timestamp: Date(),
    uptimeSeconds: uptime,
    activeAgents: 0,       // hardcoded for now
    contextUsedPct: 0      // hardcoded for now
)
```

**Verdict**: SAFE (currently unused), NEEDS FIX (before using metrics for scheduling)
**Recommendation**: When these metrics become functional: (1) validate that `uptimeSeconds` is monotonically increasing across heartbeats for the same node, (2) cross-validate `activeAgents` against the dispatch ledger, (3) rate-limit heartbeat frequency to prevent a node from artificially refreshing its "freshness."

---

### [NATS] -- Test Coverage Is Good but Missing Security Tests

**File**: `projects/shikki/Tests/ShikkiKitTests/NATS/NodeRegistryTests.swift` and `NodeHeartbeatTests.swift`
**Risk Level**: MEDIUM

**What it does**:
Tests cover registration, deregistration, stale detection, primary node queries, role filtering, heartbeat publishing, incoming heartbeat processing, stale callbacks, and error handling (publish failure).

**Missing test scenarios**:
1. **Duplicate primary**: No test for two nodes registering as `.primary` simultaneously -- what does `primaryNode` return?
2. **Malicious payload**: No test for a heartbeat with an impossibly old `startedAt` or negative `uptimeSeconds`
3. **Rapid re-registration**: No test for a node that re-registers every millisecond (DoS on the registry)

**Verdict**: NEEDS TEST
**Recommendation**: Add tests for the three scenarios above. The duplicate primary test is especially important since it documents the current (unsolved) split-brain behavior.

---

## Summary Table

| Feature | Risk | Verdict | Priority |
|---------|------|---------|----------|
| CodeGen: No rollback on regression | HIGH | NEEDS FIX | P0 |
| CodeGen: No human gate between stages | HIGH | NEEDS FIX | P1 |
| CodeGen: No per-iteration timeout | MEDIUM | NEEDS FIX | P1 |
| CodeGen: Fix prompt scope enforcement | MEDIUM | NEEDS TEST | P1 |
| CodeGen: Missing integration tests | MEDIUM | NEEDS TEST | P1 |
| Templates: Path traversal in apply | MEDIUM | NEEDS FIX | P1 |
| Templates: Executable file creation | MEDIUM | NEEDS TEST | P2 |
| Templates: No signature verification | LOW (now) | SAFE | P3 (before GH install) |
| Safety: TOCTOU budget race | MEDIUM | NEEDS FIX | P1 |
| Safety: Fail-open missing policy | MEDIUM | NEEDS FIX | P2 (before enterprise) |
| Safety: In-memory ledger | MEDIUM | NEEDS FIX | P2 (before enterprise) |
| Safety: Advisory-only anomaly actions | MEDIUM | NEEDS FIX | P1 |
| Safety: Missing test scenarios | LOW | NEEDS TEST | P2 |
| NATS: Unauthenticated registration | HIGH | NEEDS FIX | P0 |
| NATS: No leader election | HIGH | NEEDS FIX | P0 |
| NATS: Heartbeat spoofing | MEDIUM | SAFE (for now) | P2 |
| NATS: Missing security tests | MEDIUM | NEEDS TEST | P1 |

**Top 3 action items**:
1. **CodeGen rollback** -- Add git snapshot/restore before each fix iteration
2. **NATS auth** -- Add mesh token or NATS ACL before multi-node deployment
3. **NATS leader election** -- Prevent dual-primary split-brain
