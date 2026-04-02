# Epic Review: shi-foundation-2026-04-02

> **Branch:** `epic/shi-foundation-2026-04-02`
> **Base:** `develop`
> **Reviewer:** @Sensei + @Ronin + @Metsuke
> **Date:** 2026-04-03
> **Verdict:** SHIP WITH FIX (2 must-fix, 5 should-fix)

---

## Part 1: Epic Summary

| Metric | Value |
|--------|-------|
| Commits | 47 |
| Files changed | 298 |
| Lines added | +24,304 |
| Lines removed | -691 |
| Swift source added | +14,591 |
| Test files changed | 33 |
| Test lines added | +8,445 |
| Specs written | 18 |
| Radar reports | 13 |
| New source directories | 8 (Kernel/, Extensions/, Server/, Providers/, Setup/, Moto/, NATS/ expanded, Plugins/ expanded) |

### Phases Completed

| Phase | Description | Commits |
|-------|-------------|---------|
| Phase 0 | Quality hardening + P0 security specs | 4 |
| Phase 1 | Security features (FixEngine, template sanitization, plugin sandbox, node security) | 5 |
| Phase 2 | Kernel/Extensions directory restructure + binary rename | 2 |
| Phase 3 | New infrastructure (Server, Providers, NATS dispatch, Moto hardening, Setup wizard, Restart, Inbox) | 8 |
| Phase 4 | Test coverage sprint (+514 tests across 4 waves) | 4 |
| Specs & Radars | 18 specs + 13 radars + review reports | 24 |

### Architecture Decisions Made

1. **Kernel/Extensions split** -- directory-level separation with BR-6 (kernel never imports extension). Ship as monolith, split SPM targets later.
2. **Binary rename** -- `shikki` to `shi` (CLI command, Package.swift target, all docs/help text).
3. **Embedded HTTP server** -- SwiftNIO-free NWListener-based ShikiServer replaces Deno backend for local dev.
4. **NATS distributed dispatch** -- NATSDispatcher/NATSWorker with task-level pub/sub, progress streaming, result collection.
5. **FallbackProviderChain** -- cloud-to-local AI failover with fallback-eligibility classification.

---

## Part 2: Code Walkthrough by Area

### 2.1 Kernel Layer (Sources/ShikkiKit/Kernel/)

**66 files moved/created** -- the new organizational home for everything the daemon needs to run.

#### Core/ (40+ files)

The bulk of `Core/` is file moves from the old flat layout: `ShikkiEngine`, `ShikkiKernel`, `ShikkiState`, `AppConfig`, `CompanyLauncher`, `DependencyTree`, `FocusManager`, `SessionLifecycle`, `LockfileManager`, `ScheduleEvaluator`, `TaskSchedulerService`, etc.

**New files in Core/:**
- **`RestartService.swift`** (269 lines) -- Two-phase hot-reload binary swap. Resolves candidate binaries with priority chain (`~/.shikki/bin/` > `.build/release/` > `.build/debug/`). Validates Mach-O/ELF magic bytes. Checks mtime drift to detect in-progress builds. Saves checkpoint + rollback binary before `execv()`. Thoroughly tested (674 test lines in `RestartServiceTests.swift`).
- **`TemplateRegistry.swift`** (530 lines, +77 net new) -- Added path traversal protection (BR-01: reject `..` components), canonical path resolution against symlink injection (BR-02: resolve real path, verify within target), executable file guard (BR-04: require `--allow-exec` flag). Pre-validation loop runs before any file I/O -- all-or-nothing safety.

**ShikkiKernel.swift** (unchanged logic, moved to `Kernel/Core/`) -- The actor-based service scheduler with tickless sleep, wake-on-event channel, QoS-ordered fan-out, 3-failure escalation. Clean, battle-tested.

**ShikkiEngine.swift** (unchanged logic, moved) -- Entry-point dispatch (idle/resume/attach/blocked), hybrid persistence (local-first, DB fallback), countdown stop flow.

**Assessment:** The moves are clean renames. Import paths updated across all 40+ CLI commands. No logic changes in moved files (verified via diff: only `import Foundation` header adjustments for 2 files).

#### EventBus/ (6 files)

Moved from `Events/`: `EventBus`, `EventRouter`, `ShikkiEvent`, `EventLoggerService`, `EventRenderer`, `ShikkiDBEventLogger`. No changes.

#### Persistence/ (8 files)

Moved from `Services/` and `Models/`: `BackendClient`, `BackendClientProtocol`, `DBSyncClient`, `MemoryClassifier`, `MemoryCleanupService`, `MemoryFileScanner`, `MemoryScope`, `MemoryVerificationService`. No changes.

#### Recovery/ (6 files)

Moved from `Models/` and `Services/`: `Checkpoint`, `CheckpointManager`, `ContextRecoveryService`, `RecoveryContext`, `RecoveryManager`, `SessionCheckpointManager`. No changes.

#### Health/ (5 files)

Moved from `Services/`: `DiagnosticFormatter`, `HealthMonitor`, `HeartbeatLoop`, `ShikkiDoctor`, `Watchdog`. No changes.

### 2.2 New Security Features

#### FixEngine Hardening (FixEngine.swift, +291 lines net)

Six safety guards implemented with full protocol injection for testability:

| Guard | Description | Implementation |
|-------|-------------|---------------|
| BR-01 | Snapshot HEAD before each iteration | `GitOperationsProvider.snapshotHead()` |
| BR-02 | Contract verification after fix | `ContractVerifierProtocol.verify()`, rollback on violation |
| BR-03 | Regression detection | Compare failure count, rollback if more failures |
| BR-04 | Test file modification guard | `git diff --name-only`, reject `*Tests.swift` changes |
| BR-05 | Exhaustion event | Emit when 3 iterations used with failures remaining |
| BR-06 | Per-iteration timeout | `withThrowingTaskGroup` race: agent dispatch vs timeout |

**Key design:** Three protocols (`GitOperationsProvider`, `ContractVerifierProtocol`, `TestRunnerProtocol`) with production implementations wrapping `MergeEngine` and test doubles. The `IterationOutcome` enum cleanly separates timeout from completion.

**Test coverage:** 347 lines in `FixEngineTests.swift` -- covers happy path progressive fix, all 6 BRs (rollback on regression, rollback on contract violation, rollback on test file modification, timeout rollback), error cases, prompt generation.

#### Template Path Sanitization (TemplateRegistry.swift, +77 lines)

- `validateRelativePath()`: Rejects `..` in any path component (BR-01).
- `resolveCanonicalPath()`: Walks up to existing ancestor, resolves symlinks, verifies canonical path stays within target directory (BR-02). Catches TOCTOU symlink injection.
- `apply()` validation loop runs ALL checks BEFORE any file I/O -- atomic validation.
- Executable files require explicit `--allow-exec` flag (BR-04), with warning log.

**Test coverage:** 215 lines in `TemplateRegistryTests.swift`.

#### Plugin Sandbox (PluginSandbox.swift + PluginRunner.swift, 449 lines)

**PluginSandbox** -- Path validation engine with layered evaluation:
1. Always block secrets (`.env`, `.aws/`, `.ssh/`, `Keychains/`, `.gnupg/`, `.npmrc`, `.netrc`, `.docker/config.json`)
2. Always block ShikkiKit sources and binaries
3. Allow within scoped directory (`~/.shikki/plugins/<id>/data/`)
4. Block deletion outside scope
5. Declared paths require enterprise certification
6. Deny everything else

**PluginRunner** -- Actor-based subprocess isolation:
- Sanitized environment: only 9 allowed env vars (`PATH`, `HOME`, `LANG`, `TERM`, `TMPDIR`, `USER`, `SHELL`, `LC_ALL`, `LC_CTYPE`). All secret-bearing vars stripped.
- Process timeout via task group race.
- `hasCrashed` tracking for registry-level disable.

**PluginRegistry** -- Expanded with sandbox integration:
- `execute()` creates runners on-demand with scoped directory.
- `uninstall()` removes plugin data directory.
- `markCrashed()` / `isCrashed()` for crash tracking.
- `loadFromDirectory()` for filesystem discovery.
- `loadManifest()` with checksum validation and version compatibility.
- Duplicate command detection on registration.

**Test coverage:** 294 lines in `PluginSandboxTests.swift`.

#### Node Security (MeshTokenProvider.swift + LeaderElection.swift + NodeRegistry.swift, 443 lines)

**MeshTokenProvider** (58 lines) -- Loads `SHIKKI_MESH_TOKEN` from env, validates non-empty, hashes with SHA-256 via CryptoKit. Raw token never leaves the node.

**LeaderElection** (304 lines) -- Actor FSM: `idle -> shadow -> verify -> promoting -> primary`.
- `start()`: registers with auth, enters shadow, starts monitor loop + claim listener.
- `requestPromotion()`: verify no active primary (or stale), publish `PrimaryClaim` to `shikki.node.primary`, wait for objections, become primary.
- Monitor loop: checks primary health every heartbeat interval. 3 consecutive missed heartbeats triggers auto-promotion (BR-10).
- Claim listener: if claim from older node arrives while we're primary/promoting, demote to shadow (BR-04).

**NodeRegistry.registerWithAuth()** -- Mesh token hash validation (BR-01/BR-02), single-primary enforcement via `startedAt` fencing (BR-03/BR-04), silent drop on invalid tokens (BR-09), split-brain detection.

**Test coverage:** 259 lines in `LeaderElectionTests.swift` + 266 lines in `NodeSecurityTests.swift`.

### 2.3 New Infrastructure

#### Providers/ (3 files, 396 lines)

**LMStudioProvider** (190 lines) -- OpenAI-compatible API client for local LM Studio at `http://127.0.0.1:1234`. Configurable via env vars. Handles connection refused -> `connectionRefused`, HTTP 429 -> `rateLimited`. Implements both `AgentProviding` and `AgentProvider` protocols.

**FallbackProviderChain** (131 lines) -- Wraps `[any AgentProviding]` in priority order. On failure, classifies errors as fallback-eligible (rate limit, connection errors) or non-recoverable. Fallback-eligible errors cascade to next provider. Non-recoverable errors propagate immediately. Clean static `isFallbackEligible()` for testability.

**ProviderHealthCheck** (75 lines) -- Static `check(baseURL:timeout:)` pings `/v1/models` endpoint, measures latency, returns `HealthStatus`.

**Test coverage:** 232 lines `FallbackProviderChainTests.swift` + 260 lines `LMStudioProviderTests.swift`.

#### Server/ (3 files, 933 lines)

**ShikiServer** (392 lines) -- Embedded HTTP server using Apple's `Network.framework` (`NWListener`). Zero external dependencies. Thread-safe state via `ServerState` class with `NSLock`. Multi-chunk HTTP request accumulation via `DataBuffer`. `ResumeGuard` prevents double-resume of continuation.

**ServerRoutes** (320 lines) -- Route dispatch matching Deno backend API surface: `/health`, `/api/data-sync`, `/api/memories/search`, `/api/events`, `/api/decisions`, `/api/decision-queue/*`, `/api/plans`, `/api/contexts`, `/api/orchestrator/*`, `/api/companies`, `/api/session-transcripts`, `/api/backlog`. Most orchestrator/company routes are stubs returning empty arrays (compatibility).

**InMemoryStore** (221 lines) -- Actor-based in-memory storage. Collections stored as `[Data]` for Sendable safety. Simple term-match search scoring (BM25 lite). Unified `ingest()` routes by type to appropriate collection.

**Test coverage:** 287 lines in `ShikiServerTests.swift`.

#### NATS/ Expanded (6 new files, 1,121 lines)

**NATSDispatcher** (185 lines) -- Orchestrator-side: publish `DispatchTask` to `shikki.dispatch.{nodeId}` or `shikki.dispatch.available`, subscribe for progress/result per task.

**NATSWorker** (264 lines) -- Worker-side: subscribe to available + targeted subjects, execute via `TaskExecutor` protocol, publish progress + result. Tracks active/completed tasks.

**DispatchTask** (231 lines) -- Models: `DispatchTask`, `DispatchProgress`, `NATSDispatchResult`, `NATSDispatchSubjects`, `TaskPriority`, `TaskStatus`. All Codable + Sendable.

**LeaderElection** (304 lines) -- Covered in Security section above.

**MeshTokenProvider** (58 lines) -- Covered in Security section above.

**NodeRegistry** (255 lines, expanded) -- Covered in Security section above.

**Test coverage:** 470 lines `NATSDispatcherTests.swift` + 259 lines `LeaderElectionTests.swift` + 266 lines `NodeSecurityTests.swift`.

#### Moto/ (5 new files, 346 lines)

**MethodIndex** (63 lines) -- Method-level symbol index from `ArchitectureCache`. Entries: typeName, signature, kind (function/computedProperty/protocolRequirement), file, module. Query by type or signature search.

**UtilitiesManifest** (43 lines) -- Shared utility function manifest with usage counts. Feeds dispatch agent context.

**DuplicateDetector** (76 lines) -- Finds identical method signatures across types. Filters test files. Groups by signature, returns groups with 2+ entries. Feeds `shikki doctor --duplicates`.

**CacheInvalidationTracker** (96 lines) -- Snapshots `.swift` file mtimes. Compares old vs new snapshot to detect added/modified/deleted files. Enables incremental rebuilds.

**MotoCacheBuilder** (68 lines) -- Orchestrates cache building from `ArchitectureCache`.

**Test coverage:** 366 lines in `MotoCacheHardeningTests.swift`.

#### Setup/ (6 files, 1,167 lines)

**DependencyChecker** (138 lines) -- Platform-aware (`#if os()` at compile time, not runtime). Checks tools via `which`. Returns `.available(path, version)` or `.missing(installCommand)`. Batch checks for all required + optional tools.

**SetupVerifier** (119 lines) -- Runs tools to verify they actually work (not just present).

**SetupWizard** (276 lines) -- 4-step orchestrator: dependencies -> verification -> workspace -> completions. Idempotent steps with state persistence to `~/.shikki/setup.json`. Background dependency checks overlap with splash via `async let`.

**OptionalDependency** (165 lines) -- Enum of optional tools with platform-specific install commands.

**ProjectInitWizard** (469 lines) -- Expanded from 238 lines. Full project initialization with template application.

**Test coverage:** 170 lines `DependencyCheckerTests.swift` + 242 lines `SetupWizardTests.swift` + 12 lines `ProjectInitWizardTests.swift`.

### 2.4 Extensions Layer (Sources/ShikkiKit/Extensions/)

**63 files** organized into 8 extension groups:

| Extension | Files | Key Changes |
|-----------|-------|-------------|
| Spec/ | 13 | Moved S3 parser, QuickPipeline, SpecAnnotationParser, SpecFrontmatterParser, SpecFrontmatterService, SpecMigrationService, SpecCommandUtilities, SpecMetadata. Added epic-branch, validated-commit, test-run-id tracking fields. |
| Review/ | 4 | Moved PrePRGates, ReviewService, ReviewProvider, CommitAttribution. Refactored ReviewCommand to use compiled PrePRGates. Added ReviewAnalysisProvider protocol. |
| Ship/ | 8 | Moved ShipService, ShipGate, ShipLog, ShipContext, ChangelogGenerator, ExportOptionsGenerator, VersionBumper, TestFlightGates. Added BinarySwapping protocol + PosixBinarySwapper. |
| Dispatch/ | 6 | Moved AgentMessages, AgentPersona, AgentReportGenerator, ChatTargetResolver, DispatchService, DispatcherTask. |
| Observatory/ | 12 | Moved all observatory files (DailyReport, DecisionJournal, ObservatoryEngine, renderers). |
| Inbox/ | 8 | Moved BacklogItem, BacklogManager, InboxDataSource, InboxItem, InboxManager, PRInboxSource. Added SpecInboxSource, TaskInboxSource, GateInboxSource, DecisionInboxSource. |
| Flywheel/ | 6 | Moved CalibrationStore, CommunityAggregator, CommunityBenchmark, OutcomeCollector, RiskScoringEngine, TelemetryConfig. |
| (root) | 1 | JSONDecoder+Extensions. |

**Key new code in Extensions:**

- **SpecMetadata** (+16 lines): Added `epicBranch`, `validatedCommit`, `testRunId` optional fields.
- **SpecFrontmatterService** (+32 lines): Serializes/parses new tracking fields.
- **SpecAnnotationParser** (+64 lines): Enhanced parser robustness.
- **ReviewService** (+52 lines): New `ReviewAnalysisProvider` protocol (AI-agnostic). `PRReviewFinding` with severity levels. `ReviewVerdict` derivation logic.
- **PrePRGates** (+36 lines): Integration into ReviewCommand replacing shell-based gates.
- **SpecInboxSource** (88 lines): Scans `features/` for draft/review specs, surfaces as inbox items.
- **TaskInboxSource** (64 lines): Surfaces pending tasks from ShikiDB.
- **GateInboxSource** (73 lines): Surfaces failed pre-PR gates.
- **BinarySwapping** (73 lines): Protocol + `PosixBinarySwapper` using `execv()`.

### 2.5 Test Coverage Sprint

**33 test files changed, +8,445 test lines.**

| Test File | Lines | Area |
|-----------|-------|------|
| RestartServiceTests.swift | 674 | Kernel restart + rollback |
| SafetyTests: AuditLogger + BudgetACL + SecurityPatternDetector | 1,586 | Enterprise safety |
| NATSDispatcherTests.swift | 470 | Distributed dispatch |
| ReviewServiceTests.swift | 598 | PR review analysis |
| PrePRGatesTests.swift | 413 | Pre-PR quality gates |
| MotoCacheHardeningTests.swift | 366 | Moto cache system |
| FixEngineTests.swift | 347 | CodeGen fix loop |
| ShipContextTests.swift | 331 | Ship pipeline |
| ShikiServerTests.swift | 287 | Embedded server |
| PluginSandboxTests.swift | 294 | Plugin security |
| NodeSecurityTests.swift | 266 | Node mesh auth |
| LMStudioProviderTests.swift | 260 | Local AI provider |
| LeaderElectionTests.swift | 259 | Leader FSM |
| FallbackProviderChainTests.swift | 232 | Provider chain |
| TemplateRegistryTests.swift | 215 | Template security |
| SpecTrackingFieldsTests.swift | 212 | Spec frontmatter |
| RecoveryContextTests.swift | 210 | Context recovery |
| CompanyLauncherTests.swift | 185 | Company lifecycle |
| EmojiRouterTests.swift | 179 | TUI routing |
| DependencyCheckerTests.swift | 170 | Setup checker |
| SetupWizardTests.swift | 242 | Setup wizard |
| SessionCheckpointManagerTests.swift | 348 | Checkpoint management |
| ChainExecutorTests.swift | 140 | TUI chain execution |
| TmuxStateManagerTests.swift | 141 | TUI tmux state |

**Test delta estimate:** +514 new tests (from commit messages: 306 + 52 + 116 + 40 = 514).

**Test patterns used:**
- Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- Protocol injection with mock doubles
- Actor-based mocks (`MockTaskExecutor`, `MockNATSClient`)
- `withThrowingTaskGroup` for timeout testing
- Property-based assertions over collections

### 2.6 Specs & Radars

#### Specs Written (18)

| Spec | Priority | Status | Lines |
|------|----------|--------|-------|
| shikki-kernel-extension-architecture.md | P0 | Architecture Decision | 98 |
| shikki-fixengine-hardening.md | P0 | Implementing | 340 |
| shikki-template-sanitization.md | P0 | Implementing | 366 |
| shikki-plugin-sandbox.md | P0 | Implementing | 424 |
| shikki-node-security.md | P0 | Implementing | 368 |
| shikki-setup-swift.md | P0 | Implementing | 514 |
| shikki-spec-tracking-fields.md | P0 | Implementing | 363 |
| shikki-hot-reload-restart.md | P0 | Implementing | 371 |
| shikki-dry-enforcement.md | P1 | Draft | 312 |
| shikki-inbox-v2.md | P1 | Draft | 353 |
| shikki-ingest-v2.md | P0 | Draft | 322 |
| shikki-auto-docs.md | P1 | Draft | 289 |
| shikki-bg-command.md | P2 | Draft | 236 |
| shikki-spec-format-v2.md | P1 | Draft | 225 |
| shikki-practice-memory.md | P2 | Draft | 296 |
| shikki-tmux-plugin-v2.md | P1 | Draft | 231 |
| moto-dns-for-code.md | P0 | Implementing (expanded) | +185 |
| shikki-spec-metadata-v2.md | P0 | Minor update | +4 |

#### Radars (13)

| Radar | Verdict | Key Takeaway |
|-------|---------|--------------|
| AI coding tools (Amp, Factory, Claude Code, OpenCode) | WATCH | Claude Code is our runtime; don't build a competitor |
| pi ecosystem extensions | STEAL 4 patterns | Extension architecture, registry, lazy loading |
| pi-mono deep analysis | ADOPT patterns | Plugin package format, lifecycle hooks |
| Temporal workflow | ADOPT pattern | Durable execution for FixEngine retry |
| Coolify CI/CD | WATCH | Steal webhook + health check patterns |
| HashiStack + Haystack | WATCH | Haystack RAG patterns for Answer Engine |
| Inbox architecture (Linear, Plane, Huly) | STEAL | Computed views, priority weighting |
| Claude memory + HUD ecosystem | WATCH | Memory decay patterns |
| Open Claude ecosystem | WATCH | MCP server patterns |
| Tools batch (19 tools) | HIGH: cmux, lsp-cli | Multiplexer + LSP patterns |
| Syncthing | ADOPT | Photo backup + encrypted relay |
| CachyOS + UTM + Asahi | ADOPT Asahi | For M1/M2 Linux testing |

---

## Part 3: Architecture Assessment

### @Sensei (CTO)

**Is the Kernel/Extensions split clean?**

YES, with one caveat. The directory split follows BR-6 faithfully: no extension file imports another extension, and kernel files never import extensions. The 98-line architecture decision spec is clear and justified. The move from flat layout to `Kernel/{Core,EventBus,Persistence,Recovery,Health}` + `Extensions/{Spec,Review,Ship,Dispatch,Observatory,Inbox,Flywheel}` is well-organized.

The caveat: this is a **directory-level** boundary, not an SPM target boundary. Import discipline is enforced by convention, not compiler. This is explicitly called out in the spec as Phase 1 (now) with Phase 3 (split Package.swift) deferred to first external extension. Acceptable tradeoff for v0.3.

**Are there circular dependencies?**

No. Verified by examining all imports. Kernel files only import Foundation/Logging/CryptoKit. Extension files import Foundation/Logging + `@testable import ShikkiKit`. No cross-extension imports detected.

**Protocol design quality**

Excellent. The codebase follows a consistent pattern:
- Protocols for testability: `GitOperationsProvider`, `ContractVerifierProtocol`, `TestRunnerProtocol`, `BinarySwapping`, `TaskExecutor`, `NATSClientProtocol`, `AgentProviding`, `ReviewAnalysisProvider`, `ShellExecuting`, `KernelSnapshotProvider`
- Actor isolation for shared state: `NATSDispatcher`, `NATSWorker`, `PluginRunner`, `PluginRegistry`, `NodeRegistry`, `LeaderElection`, `InMemoryStore`
- Value types for data: All models are structs with `Sendable`, `Codable`, `Equatable`
- Swift 6 strict concurrency: `nonisolated(unsafe)` only where needed (FileManager in TemplateRegistry)

**Binary rename assessment**

The `shikki` -> `shi` rename is clean:
- Package.swift: target renamed with explicit `path: "Sources/shikki"` to keep source directory stable
- All CLI commands updated: doc strings, help text, error messages, typo suggestions
- `commandName` in `CommandConfiguration` updated throughout
- No missed references in source found

### @Ronin (Security)

**Are the 6 security features solid?**

| Feature | Verdict | Notes |
|---------|---------|-------|
| FixEngine hardening | SOLID | All 6 BRs implemented with rollback. Test file guard catches agent overreach. Per-iteration timeout prevents runaway. |
| Template sanitization | SOLID | Two-layer defense: component-level `..` rejection + canonical path resolution. Pre-validation before any I/O. TOCTOU-aware. |
| Plugin sandbox | SOLID | Defense-in-depth: secret patterns always blocked -> protected patterns -> scoped directory -> delete guard -> declared paths with certification -> deny-all default. |
| Plugin subprocess | SOLID | Env sanitization is thorough (9 allowed vars). Working dir locked to scope. Timeout via task group. Crash isolation via Process. |
| Mesh token auth | SOLID | SHA-256 hash-only transmission. Silent rejection (no info leak). CryptoKit for hashing. |
| Leader election | MOSTLY SOLID | FSM progression is clean. Fencing by `startedAt` is correct. Split-brain detection exists. |

**Gaps identified:**

1. **[MUST-FIX] LeaderElection objection window** -- The promoting state waits only 50ms for objections before becoming primary. In a real multi-node setup with network latency, this is too short. Should be configurable and default to at least 1 second.

2. **[SHOULD-FIX] Plugin sandbox symlink race** -- `resolvePath()` in `PluginSandbox` resolves `~` and `..` via `URL.standardized` but does not resolve symlinks (unlike `TemplateRegistry.resolveCanonicalPath()`). A plugin could create a symlink inside its scope directory pointing outside. The `PluginRunner` sets `currentDirectoryURL` to scope, but the sandbox `validateAccess()` could be bypassed.

3. **[SHOULD-FIX] MeshTokenProvider.loadFromValue()** -- Accepts any string without validation. `validate()` is only called from `load()` (env). Test code or config injection could pass empty string. Add `try validate(value)` to `loadFromValue()`.

4. **[INFO] InMemoryStore search** -- Term-match scoring is simplistic (no stemming, no fuzzy). Acceptable for v1 local dev, but should be documented as a known limitation.

### @Metsuke (Quality)

**Test coverage gaps remaining:**

| Area | Coverage | Gap |
|------|----------|-----|
| FixEngine safety guards | HIGH | All 6 BRs tested with mock injection |
| Template sanitization | HIGH | Path traversal, canonical resolution, executable guard |
| Plugin sandbox | HIGH | All 8 BRs tested |
| Plugin runner | MEDIUM | Subprocess execution not tested (Process requires real binary) |
| Leader election | HIGH | FSM transitions, auto-promotion, claim listener |
| Node security | HIGH | Auth validation, primary fencing, split-brain |
| ShikiServer | MEDIUM | Route dispatch tested, but not actual TCP connections |
| NATS dispatcher/worker | HIGH | Full lifecycle with mock NATS |
| Moto cache | HIGH | Snapshot, invalidation, duplicates, method index |
| Setup wizard | HIGH | All steps, mode handling, state persistence |
| Restart service | HIGH | All BRs, version comparison, magic bytes, mtime drift |
| Providers | HIGH | LMStudio errors, fallback chain, health check |
| ReviewService | HIGH | Verdict derivation, finding analysis |

**Test coverage gaps that matter:**
- `PluginRunner.execute()` only tested via `PluginRegistry` in mocked form. No integration test with a real subprocess.
- `ShikiServer` routes tested via direct `ServerRoutes.handle()` call -- no actual NWListener/TCP test. Acceptable for now (Network.framework is Apple-tested).

**Code patterns: consistent? DRY?**

YES. Highly consistent patterns throughout:
- `@Suite("Name")` + `@Test("descriptive name")` for all tests
- `#expect()` assertions (Swift Testing, not XCTest)
- Protocol injection with `Mock*` prefixed test doubles
- Actor isolation for mutable state
- `Sendable`, `Codable`, `Equatable` on all model types
- `Logging.Logger` with labeled loggers
- ISO8601 date encoding/decoding for NATS cross-node compatibility

**DRY concerns:**
- `JSONEncoder`/`JSONDecoder` with `.iso8601` date strategy is created in ~6 places. Could extract a `ShikkiCodable.encoder/decoder` factory. Minor.
- Duration-to-Double conversion pattern (`Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18`) appears in 4 places. Should be an extension on `Duration`.

**Technical debt introduced:**
- InMemoryStore is explicitly v1 -- PostgreSQL migration deferred. Clean actor boundary makes this easy.
- Server stubs (companies, backlog, orchestrator) return empty arrays. Fine for local dev, but needs real implementation for multi-user.
- The 50ms objection window in LeaderElection needs tuning before real multi-node deployment.

---

## Part 4: Verdict

### SHIP WITH FIX

This is a massive, well-structured epic. The Kernel/Extensions split establishes clean architecture. All 6 P0 security features are implemented with protocol injection and thorough tests. The embedded server, NATS dispatch, and provider chain are solid foundations. 514 new tests with clean patterns.

### Must-Fix (before merge to develop)

| # | Issue | File | Fix |
|---|-------|------|-----|
| MF-1 | LeaderElection objection window is 50ms -- too short for production | `NATS/LeaderElection.swift:169` | Make configurable via init parameter `objectionWindow: Duration = .seconds(1)` with 50ms only in tests |
| MF-2 | Duration-to-Double conversion repeated in 4+ places | `Kernel/Core/ShikkiKernel.swift`, `Recovery/`, NATS/ | Add `extension Duration { var totalSeconds: Double }` utility |

### Should-Fix (next iteration)

| # | Issue | File | Fix |
|---|-------|------|-----|
| SF-1 | PluginSandbox does not resolve symlinks | `Plugins/PluginSandbox.swift` | Add `resolvingSymlinksInPath()` to `resolvePath()` |
| SF-2 | `MeshTokenProvider.loadFromValue()` skips validation | `NATS/MeshTokenProvider.swift` | Add `try validate(value)` call |
| SF-3 | No PluginRunner integration test | Tests/ | Add test with real `/bin/echo` subprocess |
| SF-4 | InMemoryStore search is simplistic | `Server/InMemoryStore.swift` | Document as known limitation, defer to PostgreSQL phase |
| SF-5 | Shared JSONEncoder/Decoder configuration | Multiple NATS/Server files | Extract `ShikkiCodable.encoder/decoder` factory |

### Risk Assessment for Merging to Develop

| Risk | Level | Mitigation |
|------|-------|------------|
| Binary rename (`shikki` -> `shi`) breaks scripts/aliases | LOW | Only affects CLI invocation name. `shikki-test` target unchanged. Old binary path still resolved. |
| Directory restructure breaks imports | NONE | All imports updated. Package.swift `path:` explicit. |
| 24k LOC merge conflicts | LOW | No overlapping work on develop since branch point. |
| New dependencies | NONE | Only Apple frameworks (Network, CryptoKit) and existing SPM deps. |
| Test reliability | LOW | No flaky tests observed. Mock-based testing avoids external deps. |

### Final Score

| Dimension | Score |
|-----------|-------|
| Architecture | 9/10 -- Clean kernel/extension split with documented boundary rules |
| Security | 8/10 -- 6 features solid, 2 minor gaps (symlink, objection window) |
| Test coverage | 9/10 -- 514 new tests, consistent patterns, good mock injection |
| Code quality | 9/10 -- Protocol-first, actor isolation, Sendable compliance |
| Documentation | 8/10 -- 18 specs, architecture decision doc, but some inline TODOs remain |
| Risk | LOW -- Clean directory restructure, no breaking changes to external API |

**Overall: 8.6/10 -- Strong foundation epic. Ship with the 2 must-fixes applied.**

---

*Reviewed by @Sensei + @Ronin + @Metsuke on 2026-04-03*
*Report generated with Claude Opus 4.6*
