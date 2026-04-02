# Shikki Review -- PR #49

**Title**: fix: quality hardening -- 6 P0 security features + inbox producers
**Branch**: `fix/quality-hardening-2026-04-02` -> `main`
**Size**: 64 files, +9064/-229
**Commits**: 10
**Test Delta**: 2096 -> 2148 (52 new tests)
**Reviewers**: @Sensei (CTO) + @Ronin (Security/Adversarial) + @Metsuke (Quality)
**Date**: 2026-04-02

---

## Summary

Large PR delivering 6 P0 security features (FixEngine hardening, template path sanitization, plugin sandbox, spec tracking fields, node security, Swift setup wizard), 3 inbox producers, crash recovery via tmux checkpoint, plus 10 new spec documents. Implementation quality is generally high with proper protocol injection for testability, comprehensive test suites for each feature, and consistent BR-tagged documentation. However, the PR bundles too many concerns into a single merge unit, and several security features have gaps that need attention before release. The code is well-structured with clear separation of concerns, but a few TOCTOU vulnerabilities and missing thread-safety annotations warrant fixes.

---

## Per-Feature Review

### 1. FixEngine Hardening

**Files**: `FixEngine.swift` (+280 lines), `FixEngineTests.swift` (+285 lines)
**Spec**: `features/shikki-fixengine-hardening.md` (340 lines)

**@Sensei (Architecture)**:
- Good protocol decomposition: `GitOperationsProvider`, `ContractVerifierProtocol`, `TestRunnerProtocol` all cleanly extracted. The default implementations (`DefaultGitOps`, `DefaultContractVerifierAdapter`, `DefaultTestRunner`) wrap the concrete `MergeEngine` and `ContractVerifier` -- proper adapter pattern.
- Two `init` signatures (public production + internal testing) is the right tradeoff. The testing init avoids leaking test infrastructure into the public API.
- The `IterationOutcome` enum is well-scoped as `private`.

**@Ronin (Security)**:
- BR-03 (regression rollback) is solid: after `git reset --hard`, the failure list is correctly restored from the previous iteration's state (`iterations.last?.remainingFailures ?? failures`). This avoids the stale-state bug where `currentFailures` would still hold the post-regression counts.
- BR-04 (test file guard): the `hasSuffix("Tests.swift")` check is too narrow -- it would miss files like `TestHelper.swift`, `XCTestCase+Extensions.swift`, or test fixtures. However, for the stated goal (prevent weakening test assertions), `*Tests.swift` is the right boundary.
- BR-06 (timeout): the `withThrowingTaskGroup` + `Task.sleep` racing pattern is correct. First task to complete wins, then `group.cancelAll()` fires. **However**, the agent runner's subprocess may outlive Swift Task cancellation. The `@shi mini-challenge` in the spec correctly identifies this -- need a PID tracking mechanism for force-kill.
- The `FixEventCollector` mock is marked `@unchecked Sendable` -- acceptable for test-only code, but the `_events` array has no synchronization. In parallel test execution, this could cause data races. Low risk since tests are sequential per-suite, but should be a proper `OSAllocatedUnfairLock`-backed collection.

**@Metsuke (Quality)**:
- 6 new tests covering all 6 BRs. Each test follows the same pattern: setup mocks, run engine, assert events + rollback calls. Clean and readable.
- The em-dash replacement (`\u{2014}`) in string literals is cosmetic but pollutes the diff. Should have been in a separate commit.
- Test coverage: the happy path test verifies 2 iterations, but does not verify that `snapshotHead()` was called exactly twice. Consider adding `git.snapshotCalls` counter to `MockGitOps`.

**Verdict**: SHIP WITH FIX (FixEventCollector thread safety)

---

### 2. Template Path Sanitization

**Files**: `TemplateRegistry.swift` (+120 lines), `TemplateRegistryTests.swift` (+219 lines)
**Spec**: `features/shikki-template-sanitization.md` (366 lines)

**@Sensei (Architecture)**:
- The validation-before-I/O pattern is correct: all paths and executable flags are checked in a loop before any file write. This is atomic from a safety perspective -- no partial writes on validation failure.
- `resolveCanonicalPath` walks up the directory tree to find the deepest existing ancestor, resolves symlinks on that, then re-appends the suffix. This is a good approach for non-existent target paths.
- The `apply()` signature change (`allowExecutables: Bool = false`) preserves backward compatibility via default parameter.

**@Ronin (Security)**:
- BR-01 (`..` rejection): implemented via `NSString.pathComponents` which correctly handles edge cases like `a/../b` (splits into `["a", "..", "b"]`). The `..` check is per-component, so `"..."`  is correctly allowed (not `..`).
- BR-02 (symlink escape): **TOCTOU vulnerability exists.** The `resolveCanonicalPath` is called during the per-file write loop (line ~253 in the diff), not during the pre-validation loop. Between validation and write, a symlink could be created. The spec's own `@shi mini-challenge` from @Katana identifies this exact issue. Should re-validate after `createDirectory`.
- BR-05 (force does not bypass): explicitly tested in `forceDoesNotBypassPathValidation`. Solid.
- The symlink escape test (`applyRejectsSymlinkEscape`) creates real symlinks in `/tmp` and verifies rejection. This is a proper integration test.

**@Metsuke (Quality)**:
- 7 new tests, all well-structured with proper cleanup (`defer { cleanup(dir) }`).
- The `applyRejectsMultipleTraversalPatterns` test covers 3 variants including `./../../etc/shadow` (dot-slash-then-traversal). Good edge case coverage.
- `RegistryError.pathTraversal` exposes the offending path in the error message. As @Ronin's mini-challenge notes, this could leak filesystem structure to a malicious template author. Low risk since error messages are local-only (not sent to template source), but worth noting.

**Verdict**: SHIP WITH FIX (TOCTOU in symlink resolution)

---

### 3. Plugin/Template Sandbox

**Files**: `PluginSandbox.swift` (220 lines), `PluginRunner.swift` (229 lines), `PluginManifest.swift` (+85 lines), `PluginRegistry.swift` (+109 lines), `PluginSandboxTests.swift` (294 lines)
**Spec**: `features/shikki-plugin-sandbox.md` (424 lines)

**@Sensei (Architecture)**:
- Clean layering: `PluginSandbox` handles path validation, `PluginRunner` handles subprocess isolation, `PluginRegistry` orchestrates both. No circular dependencies.
- The sandbox validation flow (secret -> protected -> scope -> delete -> declared+cert -> deny) is well-ordered. The decision tree in the spec matches the code.
- `PluginRunner` is an `actor` -- good for managing mutable state (`violations`, `hasCrashed`). `PluginSandbox` is a `struct` (stateless validation) -- also correct.
- The `CertificationLevel >= .enterpriseSafe` comparison works because `CertificationLevel` is `Comparable`. Verified that the ordering is `uncertified < communityReviewed < shikkiCertified < enterpriseSafe`.

**@Ronin (Security)**:
- BR-03 (secret patterns): the patterns list is hardcoded (`[".env", ".aws/", ".ssh/", ...]`). This is the right approach -- no config file to tamper with. However, the pattern matching uses `String.contains()` which could false-positive on paths like `/data/.environment/` (matches `.env`). The `isSecretPath` method does check for `/\(pattern)` prefix or filename equality, which mitigates most false positives.
- BR-07 (env sanitization): the `allowedEnvVars` allowlist is static and well-curated. `SHIKKI_MESH_TOKEN`, `DATABASE_URL`, `AWS_SECRET_ACCESS_KEY` are all excluded. Good. However, `PATH` is allowed -- a malicious plugin could call tools that read credentials (e.g., `aws configure`). The spec's @Katana mini-challenge correctly identifies this. Acceptable for v0.3 since all plugins are local/trusted.
- **Critical gap**: the sandbox validates at the ShikkiKit API layer, but `PluginRunner` spawns a real `Process`. The subprocess has full OS-level filesystem access -- it can bypass the sandbox by making raw syscalls. The spec acknowledges this (`sandbox-exec` / `seccomp` is deferred). This is acceptable for v0.3 with the understanding that plugins are local-only, but must be addressed before marketplace launch.
- Plugin ID validation in `PluginManifest.validate()` now rejects `..`, leading `/`, and enforces `org/name` format with alphanumeric+hyphen+dot segments. This closes the path traversal vector through plugin IDs.

**@Metsuke (Quality)**:
- 12 tests across 2 suites (`PluginSandboxTests` + `PluginRunnerTests`).
- The uninstall cleanup test (`uninstallCleanup`) uses real filesystem operations with proper temp directory cleanup. Tests that the other plugin's directory survives uninstall -- important edge case.
- The `PluginRunner` crash isolation test spawns `nonexistent-binary-that-does-not-exist-xyz` -- this verifies crash isolation without requiring a real crashing binary.

**Verdict**: SHIP (acceptable risk for v0.3 local-only plugins)

---

### 4. Spec Tracking Fields

**Files**: `SpecMetadata.swift` (+20 lines), `SpecFrontmatterParser.swift` (+10 lines), `SpecFrontmatterService.swift` (+30 lines), `SpecValidateCommand.swift` (+18 lines), `SpecTrackingFieldsTests.swift` (212 lines)
**Spec**: `features/shikki-spec-tracking-fields.md` (363 lines)

**@Sensei (Architecture)**:
- Three new optional fields (`epicBranch`, `validatedCommit`, `testRunId`) added to `SpecMetadata` with proper `CodingKeys` mapping to hyphenated YAML keys. Backward compatible -- all nil by default.
- The parser, service, and migration service all handle the new fields. The `countSections` consolidation into `SpecCommandUtilities.countSections(in:)` is a good DRY cleanup.
- `SpecValidateCommand` now captures `git rev-parse HEAD` inline using `Process`. This is pragmatic but should eventually use `ShellRunner` for consistency and testability.

**@Ronin (Security)**:
- `validated-commit` is auto-set by `SpecValidateCommand` using the output of `git rev-parse HEAD`. The spec says this should "never be manual" and the serializer should reject manual writes (BR-02). **However**, the current implementation does not enforce rejection of manual edits -- any value in the YAML frontmatter will be parsed and accepted. The enforcement exists only as a process constraint (the command sets it), not as a code constraint.
- `test-run-id` references a ShikiDB event ID. As the spec's @Katana mini-challenge notes, an agent could forge this by posting a fake `test_run_completed` event. This is a real vector but acceptable for v0.3 (single-user system). Must be addressed before multi-agent deployment.

**@Metsuke (Quality)**:
- 7 tests covering parse, serialize, round-trip, backward compat, migration preservation, and service parsing. Thorough coverage.
- The round-trip test (`roundTrip`) is particularly good -- it verifies that parse -> serialize -> parse produces identical tracking field values.
- The YAML escape utility (`SpecCommandUtilities.escapeYAML`) is now used consistently across all quoted YAML values (title, authors, reviewer who, notes, flsh summary). Good consolidation.

**Verdict**: SHIP (enforcement of manual-edit rejection deferred to Part B)

---

### 5. Node Security (Auth + Leader Election)

**Files**: `MeshTokenProvider.swift` (58 lines), `LeaderElection.swift` (304 lines), `NodeIdentity.swift` (+12 lines), `NodeHeartbeat.swift` (+20 lines), `NodeRegistry.swift` (+80 lines), `EventLoggerNATS.swift` (+4 lines), `NodeSecurityTests.swift` (266 lines)
**Spec**: `features/shikki-node-security.md` (368 lines)

**@Sensei (Architecture)**:
- `LeaderElection` is an `actor` -- correct for managing FSM state (`_state`, `missedHeartbeatCount`). The FSM transitions are clean: `idle -> shadow -> verify -> promoting -> primary`.
- `MeshTokenProvider` is a stateless `struct` with static methods -- right pattern for a utility.
- The `NodeRegistry.registerWithAuth()` method is a new code path alongside the existing `register()`. The old `register()` is preserved for backward compat (legacy nodes without mesh tokens). The heartbeat subscriber in `NodeHeartbeat` routes to the correct method based on whether `meshTokenHash` is present.
- `NATSSubjectMapper.nodePrimary` added as a static computed property -- consistent with existing subject mapping pattern.

**@Ronin (Security)**:
- BR-02/BR-09 (silent drop): `registerWithAuth` returns `false` without logging when the token doesn't match. The `logger.info` call only fires for successful registrations. No information leak. **Correct implementation**.
- BR-04 (startedAt fencing): older primary wins. The implementation compares `existing.identity.startedAt <= identity.startedAt`. The `<=` means ties go to the existing node -- this is the right choice to prevent flip-flopping.
- BR-10 (auto-promote): the monitor loop checks `registry.primaryNode` every heartbeat interval. If nil for 3 consecutive checks, it calls `requestPromotion()`. **Gap**: the code checks `primary == nil` but should also check if the primary is stale (already in the registry but not heartbeating). The `registry.isStale()` check is done inside `requestPromotion()`, but the monitor loop does not call `markStale()` -- it relies on the registry's staleness detection. This creates a dependency on the registry's stale threshold being aligned with `3 * heartbeatInterval`. Should verify alignment.
- The `meshToken` is hashed via SHA-256 before transmission -- the raw token never leaves the node. Good. However, SHA-256 of a short token is vulnerable to brute force. The spec should recommend minimum token length (32+ chars).
- **Test 7 (primaryCount alert)**: this test uses `registry.register()` (non-auth) to simulate split-brain by bypassing fencing. This is a valid test approach -- it proves that `primaryCount` and `hasSplitBrain` detect the condition even when it occurs through a bug.

**@Metsuke (Quality)**:
- 8 tests covering all BRs. The tests use `MockNATSClient` which already existed -- good reuse.
- Test 5 (leader election sequence) verifies the full FSM: `idle -> shadow -> verify -> promoting -> primary`. It also decodes the published `PrimaryClaim` and verifies the `meshTokenHash` matches. Thorough.
- Test 6 (auto-promote) uses `registry.markStale()` to simulate missed heartbeats. This is a shortcut (the real system would wait for the stale threshold) but acceptable for unit testing.
- `MeshTokenProvider.hash` is verified to be deterministic and produce 64-char hex output (SHA-256). Good.

**Verdict**: SHIP WITH FIX (document minimum token length, verify stale threshold alignment)

---

### 6. Swift Setup System

**Files**: `DependencyChecker.swift` (138 lines), `OptionalDependency.swift` (165 lines), `SetupVerifier.swift` (119 lines), `SetupWizard.swift` (275 lines), `DependencyCheckerTests.swift` (170 lines), `SetupWizardTests.swift` (242 lines)
**Spec**: `features/shikki-setup-swift.md` (514 lines)

**@Sensei (Architecture)**:
- Clean separation: `DependencyChecker` (discovery), `SetupVerifier` (verification), `SetupWizard` (orchestration). The `ShellExecuting` protocol enables full mock injection.
- `RequiredTool` is `git, tmux, claude` (not `swift, sqlite3` as in the spec). The spec says required tools are `git, tmux, swift, sqlite3`. The implementation diverges -- `swift` and `sqlite3` are omitted, `claude` is added. This is a spec-code mismatch that should be documented.
- `SetupState` uses a simple `[String: Bool]` dictionary for step tracking. Simpler than the spec's `Step` enum approach, but loses type safety. The `isStepComplete(_:)` method uses raw strings -- typos would silently pass.
- `Platform.current` uses `#if os(macOS)` -- correct per BR-07. No runtime `uname` calls.

**@Ronin (Security)**:
- `DefaultShellExecutor.run()` uses `/usr/bin/env` as the executable with the command as the first argument. This is safe -- it resolves from PATH without shell interpretation (no injection risk).
- The wizard creates directories at `cwd/.shikki/` which may not be the right location (should be `~/.shikki/` as the spec says). The `createWorkspaceDirs()` method uses `fm.currentDirectoryPath + "/" + dir` -- this creates `.shikki/` in whatever directory the binary happens to be running from, not necessarily the user's home. **This is a bug if the wizard runs from a non-project directory**.

**@Metsuke (Quality)**:
- 12 tests across 2 suites. The `WizardMockShell` tracks all calls via `StepTracker` -- allows verification of execution order and skipped steps.
- `forceRerunsEverything` test pre-populates state as complete, then verifies force mode skips nothing.
- `idempotent` test runs the wizard twice and verifies the second run skips all steps. Good.
- Missing test: no test verifies the splash + background pre-loading overlap (BR-02). The `skipSplash: true` flag bypasses this in all tests. Consider a dedicated test that measures timing.
- The `SetupState` type uses `SetupState.markComplete(version:path:)` static method for creating a fully-complete state -- clean test utility.

**Verdict**: SHIP WITH FIX (workspace directory location bug)

---

### 7. Inbox Producers

**Files**: `SpecInboxSource.swift` (88 lines), `TaskInboxSource.swift` (64 lines), `GateInboxSource.swift` (73 lines), `DecisionInboxSource.swift` (-61 lines removed)

**@Sensei (Architecture)**:
- Three stub sources moved from inline in `DecisionInboxSource.swift` to dedicated files. Each is now a proper implementation: `SpecInboxSource` scans `features/*.md`, `GateInboxSource` reads `PrePRStatusStore`, `TaskInboxSource` calls `client.getDispatcherQueue()`.
- `SpecInboxSource` uses `SpecFrontmatterParser` to read metadata from spec files -- proper reuse of existing infrastructure.
- `GateInboxSource` filters to only show items when there are failures -- passing gates don't clutter the inbox. Good UX decision.
- All three sources have graceful error fallback (`catch { return [] }`). Backend/shell failures do not crash the inbox.

**@Metsuke (Quality)**:
- No dedicated tests for the inbox sources. The sources are relatively simple (parse existing data, map to `InboxItem`), but `SpecInboxSource` does shell execution (`git rev-parse --show-toplevel`) and file system operations that should be tested.
- `TaskInboxSource` sets `age = 0` for all tasks because `DispatcherTask` lacks a `createdAt` field. This means urgency scoring is entirely priority-based for tasks. Should be documented as a known limitation.

**Verdict**: SHIP (should-fix: add basic tests for inbox sources)

---

## Cross-Cutting Concerns

### @Sensei: Architecture Consistency

1. **DRY consolidation done right**: `countSections` consolidated into `SpecCommandUtilities`, `escapeYAML` added as shared utility, `pluginDirectoryName(for:)` shared between install/uninstall. These follow the `should-fix` items from PR review #3.

2. **Protocol injection pattern consistent**: `GitOperationsProvider`, `ContractVerifierProtocol`, `TestRunnerProtocol` (FixEngine), `ShellExecuting` (Setup), `NATSClientProtocol` (Node Security) all follow the same pattern -- protocol in production code, mock in tests.

3. **Module boundaries respected**: New types live in appropriate directories -- `NATS/` for node security, `Plugins/` for sandbox, `Setup/` for wizard, `CodeGen/` for FixEngine, `Services/Inbox/` for sources. No cross-module pollution.

4. **Spec bundling concern**: 10 new spec documents in `features/` are included in this PR. Some are drafts (`status: draft`) for features not implemented in this PR (e.g., `shikki-hot-reload-restart.md`, `shikki-practice-memory.md`, `shikki-inbox-v2.md`). These should have been in a separate docs-only commit to keep the PR focused on implementation.

### @Ronin: Cross-Feature Attack Surface

1. **Path traversal defense in depth**: Three independent path traversal guards now exist -- `TemplateRegistry.validateRelativePath()`, `PluginManifest.validate()` (ID format), and `SlopScanGate` (file path guard). They use slightly different techniques (`pathComponents` vs `contains("..")` vs `URL.standardized`). Should standardize on one canonical utility.

2. **Subprocess isolation is application-level only**: Both `PluginRunner` and `FixEngine` spawn subprocesses. Neither uses OS-level sandboxing (`sandbox-exec` on macOS, `seccomp` on Linux). This is acceptable for v0.3 but creates a consistent gap across features.

3. **Secret protection patterns**: `PluginSandbox.secretPatterns` and `PluginRunner.allowedEnvVars` define security boundaries. These should be centralized in a `SecurityConstants` type to avoid drift between the two lists.

### @Metsuke: Naming and Code Quality

1. **Naming consistency**: All new types follow existing conventions -- `PascalCase` types, `camelCase` methods, `BR-XX` tags in comments. `FixProgressEvent` cases follow the `case eventName(param:)` pattern.

2. **TODO/FIXME scan**: No `TODO` or `FIXME` found in any new source files. The disabled TUI snapshot tests have a `.disabled()` annotation with a clear reason -- not a silent skip.

3. **Dead code**: `MeshTokenProvider.loadFromValue(_:)` is a passthrough method (`return value`). It exists for test convenience but provides no value. Could be removed in favor of direct string usage.

4. **Import hygiene**: `import Logging` added to `TemplateRegistry.swift` and `LeaderElection.swift` for the new logging. `import CryptoKit` in `MeshTokenProvider.swift` for SHA-256. All imports are used.

5. **Test naming**: tests follow `func testNameVerb()` pattern consistently. `@Test("descriptive string")` annotations provide readable names in test output.

---

## Verdict

**SHIP WITH FIX**

The core security features are well-implemented with proper protocol decomposition, comprehensive test suites, and consistent patterns. The 3 must-fix items below are real issues that should be addressed before merging to `develop`. The should-fix items can be tracked as follow-up.

---

## Must-Fix (before merge)

| # | File | Issue | Severity |
|---|------|-------|----------|
| 1 | `TemplateRegistry.swift` | TOCTOU in symlink resolution: `resolveCanonicalPath` is called per-file during write loop, not atomically during pre-validation. A symlink could be created between validation and write. Re-validate after `createDirectory` or move the canonical check into the validation loop. | Medium |
| 2 | `SetupWizard.swift` | `createWorkspaceDirs()` creates `.shikki/` relative to `cwd`, not `~/.shikki/`. If the wizard runs from a non-project directory, directories are created in the wrong location. Use `NSHomeDirectory()` or `SetupState.defaultPath` parent. | Medium |
| 3 | `FixEngineTests.swift` | `FixEventCollector` uses an unprotected `[FixProgressEvent]` array. While unlikely to cause test failures today, this is a data race under `@unchecked Sendable`. Add `NSLock` or use `OSAllocatedUnfairLock`. | Low |

## Should-Fix (next iteration)

| # | File | Issue |
|---|------|-------|
| 1 | `PluginSandbox.swift` + `PluginRunner.swift` | Centralize secret patterns and allowed env vars into a shared `SecurityConstants` type to prevent drift. |
| 2 | `TemplateRegistry.swift` + `PluginManifest.swift` + `SlopScanGate` | Standardize path traversal validation into a single utility (e.g., `PathSanitizer`) instead of 3 independent implementations. |
| 3 | `LeaderElection.swift` | Document minimum `SHIKKI_MESH_TOKEN` length (recommend 32+ chars). Short tokens are brute-forceable even with SHA-256 hashing. |
| 4 | `SpecValidateCommand.swift` | Use `ShellRunner` instead of inline `Process` for `git rev-parse HEAD`. This improves testability and consistency. |
| 5 | `OptionalDependency.swift` | Spec says required tools are `git, tmux, swift, sqlite3`. Code has `git, tmux, claude`. Document the divergence or update the spec. |
| 6 | `SpecInboxSource.swift`, `TaskInboxSource.swift`, `GateInboxSource.swift` | Add basic unit tests for the three inbox sources. |
| 7 | `LeaderElection.swift` | Verify alignment between `registry.staleThreshold` and `3 * heartbeatInterval` to ensure auto-promote timing is correct. |
| 8 | PR scope | Future PRs should not bundle unimplemented spec drafts (hot-reload, practice memory, inbox v2) with implementation code. Keep spec-only additions in separate commits. |

---

*Review generated by @Sensei (CTO) + @Ronin (adversarial) + @Metsuke (quality) on 2026-04-02.*
*PR #49: 64 files, +9064/-229, 52 new tests.*
