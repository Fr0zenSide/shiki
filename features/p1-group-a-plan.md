# P1 Group A — Implementation Specs

> Created: 2026-03-23 | Author: @Sensei (CTO) | Status: Ready for @Daimyo approval
> Covers: 4 P1 tasks from the validated roadmap (`memory/project_shiki-full-roadmap-v1.md`)

---

## Task 1: shiki ship --dry-run dogfood test

### What & Why

The `shiki ship` pipeline has 24 unit tests and 8 gates, but has never been exercised against a real project. A dry-run dogfood proves the pipeline works end-to-end outside of mocked test doubles. Without this, we ship a ship command that has never shipped anything.

### Current State

- ShipCommand exists at `tools/shiki-ctl/Sources/shikki/Commands/ShipCommand.swift`
- ShipService + ShipGate implementations at `tools/shiki-ctl/Sources/ShikiCtlKit/Services/`
- 24 unit tests pass (`ShipServiceTests.swift`)
- No integration/e2e test against a real repository
- Known issue from roadmap: "E2E test skip flag for shiki-ctl (tests hang on stdin)" — the interactive `--why` prompt blocks in CI

### Target Project: kintsugi-ds (not Flsh)

Flsh was originally suggested, but **kintsugi-ds is the better candidate**:

| Criteria | kintsugi-ds | Flsh |
|----------|-------------|------|
| Has git repo | Yes (`Fr0zenSide/kintsugi-ds`, 5 commits) | No active repo |
| Has tests | Yes (snapshot + contract tests) | Dormant |
| Has conventional commits | Yes (`feat:`, `fix:`, `test:`) | N/A |
| Size | Small (~20 source files, 3 token files) | Unknown |
| Package.swift | Yes (SPM with swift-snapshot-testing) | N/A |
| Branches | Has develop workflow | N/A |

### Implementation Steps

1. **Build shikki binary** — `swift build --package-path tools/shiki-ctl`
2. **Create test branch** — in kintsugi-ds: `git checkout -b test/ship-dryrun` from develop, add a trivial change (e.g., bump a token value)
3. **Run dry-run** — `.build/debug/shikki ship --dry-run --why "dogfood test: validate pipeline e2e" --target develop`
4. **Verify each gate** (all 8 gates must produce output):

| Gate | Expected Behavior | Verification |
|------|-------------------|--------------|
| 1. CleanBranchGate | PASS — we committed the change | stdout: `[1/8] CleanBranch... pass` |
| 2. TestGate | PASS or FAIL depending on test suite | Runs `swift test --package-path .` (detects Package.swift) |
| 3. CoverageGate | WARN (soft gate, no lcov baseline) | Shows coverage % or "no coverage data" warning |
| 4. RiskGate | PASS with low score (trivial diff) | Risk score < 20 |
| 5. ChangelogGate | PASS — parses conventional commit subjects | Groups entries by prefix |
| 6. VersionBumpGate | PASS — detects patch/minor from commit prefix | Shows `current → next` version |
| 7. CommitGate | NO-OP (dry-run) | Logged as skipped |
| 8. PRGate | NO-OP (dry-run, no `gh pr create`) | Logged as skipped, target=develop validated |

5. **Capture output** — redirect to `features/ship-dryrun-output.txt` for review
6. **Verify ShipEvents** — if Shiki DB is running, query `agent_events` for `event_type = 'data_sync'` with ship events. If not, verify ship-log.md was written to `~/.shiki/ship-log.md`
7. **Verify preflight manifest** — screenshot or copy the single-screen manifest output
8. **Fix any discovered issues** — file as inline fixes, not separate PRs

### Files to create/modify

| Path | Action |
|------|--------|
| `features/ship-dryrun-output.txt` | New — captured test output |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipService.swift` | Fix — any bugs found |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipGate.swift` | Fix — any gate issues |

### Tests

No new unit tests — this IS the test. Success criteria:
- All 8 gates execute (even if some warn)
- No crashes or hangs
- Preflight manifest renders correctly
- Ship log entry written
- `--why` flag accepted without interactive prompt (avoids stdin hang)

### Sub-agent split

Single agent. This is a manual validation pass, not parallelizable.

### Dependencies on other tasks

None. Can run independently. Should run FIRST — bugs found here may affect Task 3 (@Ronin fixes).

---

## Task 2: Deno Backend OpenAPI Spec

### What & Why

The backend has 60+ endpoints across 8 domains (health, memories, pipelines, companies, orchestrator, radar, ingestion, sessions). Zero documentation beyond reading routes.ts. An OpenAPI 3.1 spec:
1. Documents the API for any consumer (ShikiMCP, ShikiCore, future Swift migration)
2. Generates TypeScript types for test mocks
3. Validates request/response shapes at CI time
4. Becomes the contract when migrating from Deno to Swift

### Current State

- `src/backend/src/routes.ts` — 897 lines, flat `if/else` router, no framework
- `src/backend/src/schemas.ts` — 338 lines, 20+ Zod schemas (well-typed input validation)
- No OpenAPI spec, no generated types, no request validation middleware
- Schemas are Zod (runtime validation) — can be mechanically translated to JSON Schema (which is what OpenAPI uses)

### Approach: Manual spec file (recommended)

Auto-generation (e.g., zod-to-openapi) would require refactoring routes.ts to use a framework (Hono, Oak). Not worth it — the API is stable and the backend is a migration candidate anyway. Manual spec gives more control over descriptions, examples, and grouping.

### Complete Endpoint Inventory

Extracted from routes.ts (all 63 endpoints):

#### Health (2)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/health` | — | `{ status, version, uptime, db, ollama }` | — |
| GET | `/health/full` | — | Extended health with pool stats | — |

#### Projects & Sessions (3)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/projects` | — | `Project[]` | — |
| GET | `/api/sessions` | `?project_id` | `Session[]` (limit 50) | — |
| GET | `/api/sessions/active` | — | `ActiveSession[]` | — |

#### Agents & Events (4)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/agents` | `?session_id` | `Agent[]` | — |
| POST | `/api/agent-update` | `AgentEventSchema` | `{ ok: true }` | `AgentEventSchema` |
| GET | `/api/agent-events` | `?session_id, ?limit` | `AgentEvent[]` | — |
| POST | `/api/stats-update` | `PerformanceMetricSchema` | `{ ok: true }` | `PerformanceMetricSchema` |

#### Memories (4)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| POST | `/api/memories` | `MemorySchema` | `{ id }` | `MemorySchema` |
| GET | `/api/memories` | `?project_id, ?limit` | `Memory[]` | — |
| POST | `/api/memories/search` | `MemorySearchSchema` | `SearchResult[]` | `MemorySearchSchema` |
| GET | `/api/memories/sources` | `?project_id` | `MemorySource[]` | — |

#### Chat (2)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| POST | `/api/chat-message` | `ChatMessageSchema` | `{ ok: true }` | `ChatMessageSchema` |
| GET | `/api/chat-messages` | `?session_id` (required), `?limit` | `ChatMessage[]` | — |

#### Data Sync & Git (3)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| POST | `/api/data-sync` | `DataSyncSchema` | `{ ok: true }` | `DataSyncSchema` |
| POST | `/api/pr-created` | `PrCreatedSchema` | `{ ok: true }` | `PrCreatedSchema` |
| GET | `/api/git-events` | `?project_id, ?event_type, ?limit` | `GitEvent[]` | — |

#### Dashboard (5)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/dashboard/summary` | `?project_id` | `DashboardSummary` | — |
| GET | `/api/dashboard/performance` | `?project_id, ?days` | `DailyPerformance[]` | — |
| GET | `/api/dashboard/activity` | `?project_id, ?hours` | `ActivityBucket[]` | — |
| GET | `/api/dashboard/costs` | — | `CostLeaderboard[]` | — |
| GET | `/api/dashboard/git` | `?project_id, ?days` | `GitActivity[]` | — |

#### Ingestion (5)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| POST | `/api/ingest` | `IngestRequestSchema` | `IngestResult` | `IngestRequestSchema` |
| GET | `/api/ingest/sources` | `?project_id` (required) | `IngestSource[]` | `IngestSourceQuerySchema` |
| GET | `/api/ingest/sources/:id` | — | `IngestSource` | — |
| DELETE | `/api/ingest/sources/:id` | — | `{ ok: true }` | — |
| POST | `/api/ingest/reingest/:id` | — | `{ sourceId, status, message }` | — |

#### Radar (10)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/radar/watchlist` | `?kind, ?tag` | `WatchItem[]` | — |
| POST | `/api/radar/watchlist` | `RadarWatchItemSchema` | `WatchItem` (201) | `RadarWatchItemSchema` |
| PUT | `/api/radar/watchlist/:id` | partial body | `WatchItem` | — |
| DELETE | `/api/radar/watchlist/:id` | — | `{ ok: true }` | — |
| POST | `/api/radar/scan` | `RadarScanTriggerSchema` | `{ scanRunId, status }` | `RadarScanTriggerSchema` |
| GET | `/api/radar/scans/:runId` | — | `ScanResult[]` | — |
| GET | `/api/radar/scans` | `?limit` | `ScanHistory[]` | — |
| GET | `/api/radar/digest/latest` | — | `Digest` | — |
| GET | `/api/radar/digest/:runId` | — | `Digest` | — |
| POST | `/api/radar/ingest` | `RadarIngestSchema` | `{ ok, memoriesCreated }` | `RadarIngestSchema` |

#### Pipelines (12)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| POST | `/api/pipelines` | `PipelineRunCreateSchema` | `PipelineRun` (201) | `PipelineRunCreateSchema` |
| GET | `/api/pipelines` | `?pipeline_type, ?status, ?project_id, ?limit` | `PipelineRun[]` | — |
| GET | `/api/pipelines/latest` | `?pipeline_type` | `PipelineRun` | — |
| GET | `/api/pipelines/:id` | — | `PipelineRunSummary` | — |
| PATCH | `/api/pipelines/:id` | `PipelineRunUpdateSchema` | `PipelineRun` | `PipelineRunUpdateSchema` |
| POST | `/api/pipelines/:id/checkpoints` | `PipelineCheckpointSchema` | `Checkpoint` (201) | `PipelineCheckpointSchema` |
| GET | `/api/pipelines/:id/checkpoints` | — | `Checkpoint[]` | — |
| GET | `/api/pipelines/:id/checkpoints/:phase` | — | `Checkpoint` | — |
| POST | `/api/pipelines/:id/resume` | `PipelineResumeSchema` | `ResumeResult` | `PipelineResumeSchema` |
| POST | `/api/pipelines/:id/route` | `PipelineRouteEvalSchema` | `RouteResult` | `PipelineRouteEvalSchema` |
| GET | `/api/pipeline-rules` | `?pipeline_type` | `RoutingRule[]` | — |
| POST | `/api/pipeline-rules` | `PipelineRoutingRuleSchema` | `RoutingRule` (201) | `PipelineRoutingRuleSchema` |
| PUT | `/api/pipeline-rules/:id` | partial body | `RoutingRule` | — |
| DELETE | `/api/pipeline-rules/:id` | — | `{ ok: true }` | — |

#### Companies (3)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/companies` | `?status` | `Company[]` | — |
| POST | `/api/companies` | `CompanyCreateSchema` | `Company` (201) | `CompanyCreateSchema` |
| GET | `/api/companies/:id` | — | `CompanyStatus` | — |
| PATCH | `/api/companies/:id` | `CompanyUpdateSchema` | `Company` | `CompanyUpdateSchema` |
| GET | `/api/companies/:id/tasks` | `?status` | `Task[]` | — |

#### Task Queue (4)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| POST | `/api/task-queue` | `TaskCreateSchema` | `Task` (201) | `TaskCreateSchema` |
| GET | `/api/task-queue/:id` | — | `Task` | — |
| PATCH | `/api/task-queue/:id` | `TaskUpdateSchema` | `Task` | `TaskUpdateSchema` |
| POST | `/api/task-queue/claim` | `TaskClaimSchema` | `Task` | `TaskClaimSchema` |

#### Decision Queue (4)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/decision-queue` | `?company_id, ?answered, ?tier` | `Decision[]` | — |
| POST | `/api/decision-queue` | `DecisionCreateSchema` | `Decision` (201) | `DecisionCreateSchema` |
| GET | `/api/decision-queue/pending` | — | `Decision[]` | — |
| PATCH | `/api/decision-queue/:id` | `DecisionAnswerSchema` | `Decision` | `DecisionAnswerSchema` |

#### Orchestrator (8)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/orchestrator/status` | — | `OrchestratorStatus` | — |
| GET | `/api/orchestrator/stale` | `?threshold_minutes` | `StaleCompany[]` | — |
| GET | `/api/orchestrator/ready` | — | `ReadyCompany[]` | — |
| GET | `/api/orchestrator/report` | `?date` | `DailyReport` | — |
| POST | `/api/orchestrator/heartbeat` | `CompanyHeartbeatSchema` | `HeartbeatResult` | `CompanyHeartbeatSchema` |
| GET | `/api/orchestrator/locks` | — | `PackageLock[]` | — |
| POST | `/api/orchestrator/locks` | `PackageLockSchema` | `PackageLock` (201) | `PackageLockSchema` |
| POST | `/api/orchestrator/locks/release` | `PackageUnlockSchema` | `{ ok: true }` | `PackageUnlockSchema` |
| GET | `/api/orchestrator/audit` | `?company_id, ?limit` | `AuditEntry[]` | — |
| GET | `/api/orchestrator/board` | — | `BoardOverview` | — |
| GET | `/api/orchestrator/dispatcher-queue` | — | `DispatcherQueue` | — |

#### Session Transcripts (3)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/session-transcripts` | `?company_slug, ?company_id, ?task_id, ?phase, ?limit, ?include_raw_log` | `Transcript[]` | — |
| POST | `/api/session-transcripts` | `SessionTranscriptCreateSchema` | `Transcript` (201) | `SessionTranscriptCreateSchema` |
| GET | `/api/session-transcripts/:id` | — | `Transcript` | — |

#### Admin (1)
| Method | Path | Request | Response | Schema |
|--------|------|---------|----------|--------|
| GET | `/api/admin/backup-status` | — | `BackupStatus` | — |

**Total: ~67 endpoints across 14 domain groups.**

### Implementation Steps

1. **Create `src/backend/openapi.yml`** — OpenAPI 3.1.0 spec with:
   - `info` block (title: "Shiki DB API", version: "3.1.0")
   - `servers` block (localhost:3900)
   - `tags` for each domain group (14 tags)
   - All 67 paths with methods, parameters, request bodies, response schemas
   - `components/schemas` — mechanically translate each Zod schema from schemas.ts to JSON Schema
   - WebSocket endpoint documented as x-extension (not natively supported in OpenAPI)

2. **Validate the spec** — `npx @redocly/cli lint src/backend/openapi.yml`

3. **Add npm scripts** to `src/backend/package.json`:
   - `"api:lint": "npx @redocly/cli lint openapi.yml"`
   - `"api:types": "npx openapi-typescript openapi.yml -o src/generated/api-types.ts"`

4. **Generate TypeScript types** — `openapi-typescript` produces types from the spec, usable in test mocks

5. **Add CI check** — in GitHub Actions, lint the spec on every PR touching `src/backend/`

### Files to create/modify

| Path | Action |
|------|--------|
| `src/backend/openapi.yml` | New — the full OpenAPI 3.1.0 spec |
| `src/backend/package.json` | Modify — add lint/types scripts |
| `src/backend/src/generated/api-types.ts` | New — generated TypeScript types |

### Tests

- `npx @redocly/cli lint openapi.yml` — must pass with 0 errors
- Manually verify 5 endpoints match actual behavior: `/health`, `/api/memories/search`, `/api/pipelines`, `/api/companies`, `/api/orchestrator/status`
- Smoke test: start backend, run 3 requests, compare response shapes to spec

### Sub-agent split

Parallelizable into 2 agents:
- **Agent A**: Write the spec (paths + schemas for domains 1-7: health through dashboard)
- **Agent B**: Write the spec (paths + schemas for domains 8-14: ingestion through admin)
- **Merge**: Combine into single file, validate

### Dependencies on other tasks

None. Fully independent.

### Migration path to Swift

The OpenAPI spec becomes the contract for a future Swift backend:
1. Use `swift-openapi-generator` to produce Swift types + client stubs
2. Implement route handlers against the generated protocols
3. Run the same spec validation against both backends during migration
4. Zero-downtime cutover: proxy switches from Deno to Swift, spec ensures compatibility

---

## Task 3: @Ronin v1.1 Fixes

### What & Why

Three known bugs were flagged during the @Ronin v2 review cycle and deferred to v1.1. All three are in the ShikiCore/ShikiMCP Swift packages. They affect pipeline reliability and MCP server correctness.

### Current State

**Fix 1: PipelineResult tuple -> struct**

In `packages/ShikiCore/Sources/ShikiCore/Pipeline/PipelineRunner.swift` (line 13, 53):

```swift
// Current — tuple array
public let gateResults: [(gate: String, result: PipelineGateResult, duration: Duration)]
```

Problem: Tuples are not `Codable`. `PipelineResult` cannot be serialized to JSON for event persistence or DB storage. The struct is `Sendable` but not `Codable` — a silent data loss bug. Any attempt to persist pipeline results via `EventPersister` will crash or silently drop the gate results.

**Fix 2: MCPServer readLine blocking**

In `packages/ShikiMCP/Sources/ShikiMCP/MCPServer.swift` (line 26):

```swift
while let line = readLine() {  // blocks the actor
```

Problem: `readLine()` is a synchronous, blocking call inside an `actor`. This blocks the actor's serial executor. If any other actor method is called while waiting for input (e.g., a health check, a concurrent tool call), it deadlocks. The MCP protocol allows multiplexed requests — a blocking read makes that impossible.

**Fix 3: Type name collisions**

ShikiCore exports these public types that could collide with ShikiMCP or consumer code:
- `PipelineGateResult` vs `GateResult` (if shiki-ctl still has its own)
- `PipelineContext` vs `ShipContext` (both are "context" protocols for gates)
- `AgentResult` (ShikiCore) could collide with any consumer's `AgentResult`
- `DispatchEvent` (ShikiCore) is generic enough to collide

The risk is not immediate (separate modules), but becomes real when ShikiCore + ShikiMCP + shiki-ctl are composed in a single binary.

### Implementation Steps

**Fix 1: PipelineResult tuple -> struct** (ShikiCore)

1. Create `GateEvaluation` struct:
```swift
public struct GateEvaluation: Codable, Sendable {
    public let gate: String
    public let result: PipelineGateResult
    public let duration: Duration
}
```
2. Make `PipelineGateResult` conform to `Codable`
3. Replace tuple array in `PipelineResult.gateResults` with `[GateEvaluation]`
4. Update `PipelineRunner.run()` to construct `GateEvaluation` instead of tuples
5. Make `PipelineResult` conform to `Codable`
6. Update all test call sites

**Fix 2: MCPServer readLine -> async stdin** (ShikiMCP)

1. Replace `readLine()` with async `FileHandle.standardInput` reading:
```swift
func run() async {
    let stdin = FileHandle.standardInput
    let stdout = FileHandle.standardOutput

    for try await line in stdin.bytes.lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let responseJSON = await handleMessage(trimmed)
        // ...
    }
}
```
2. This makes the read non-blocking relative to the actor — other calls can interleave between lines
3. Add a `Task` cancellation check for graceful shutdown

**Fix 3: Type name prefixing** (ShikiCore)

Conservative approach — only prefix types that are genuinely ambiguous:
1. `AgentResult` -> `AgentProviderResult` (clarifies it's from the provider protocol)
2. `AgentOptions` -> `AgentProviderOptions` (same)
3. Leave `PipelineResult`, `PipelineGateResult`, `PipelineContext` as-is — they are namespaced by the Pipeline domain and won't collide with ShipGate/ShipContext (different module)
4. Add module-level doc comments explaining the naming convention

### Files to create/modify

| Path | Action |
|------|--------|
| `packages/ShikiCore/Sources/ShikiCore/Pipeline/PipelineRunner.swift` | Modify — GateEvaluation struct, Codable conformance |
| `packages/ShikiCore/Sources/ShikiCore/Pipeline/PipelineGate.swift` | Modify — PipelineGateResult Codable |
| `packages/ShikiCore/Sources/ShikiCore/Agent/AgentProvider.swift` | Modify — rename AgentResult/Options |
| `packages/ShikiCore/Sources/ShikiCore/Agent/ClaudeProvider.swift` | Modify — update renamed types |
| `packages/ShikiCore/Tests/ShikiCoreTests/` | Modify — update test call sites |
| `packages/ShikiMCP/Sources/ShikiMCP/MCPServer.swift` | Modify — async stdin |
| `packages/ShikiMCP/Tests/ShikiMCPTests/` | Modify — update tests if needed |

### Tests

**Fix 1:**
- `test_pipelineResult_isCodable()` — encode/decode round-trip
- `test_gateEvaluation_preservesDuration()` — Duration serialization
- Existing PipelineRunner tests must still pass

**Fix 2:**
- `test_mcpServer_handlesMultiplexedRequests()` — send 2 requests without waiting for first response
- `test_mcpServer_gracefulShutdown()` — cancel task, verify clean exit
- Existing MCP tests must still pass (they use `handleMessage` directly, not stdin)

**Fix 3:**
- Compile-only verification — `swift build` with all 3 packages imported
- No behavioral change, just naming

### Sub-agent split

Parallelizable into 2 agents:
- **Agent A**: Fix 1 + Fix 3 (both in ShikiCore)
- **Agent B**: Fix 2 (ShikiMCP, independent package)

### Dependencies on other tasks

- Should run AFTER Task 1 (dogfood may reveal additional bugs in the same files)
- No dependency on Task 2 or Task 4

---

## Task 4: DSKintsugi Repo Setup

### What & Why

DSKintsugi is the cross-platform design system (replacing DesignKit). It already has a GitHub repo (`Fr0zenSide/kintsugi-ds`) with 5 commits, Package.swift, sources, tests, tokens, and a Style Dictionary pipeline. But it is missing: CI, README, proper Swift package publishing, and Claude/Shiki integration. It exists as a working codebase without the surrounding infrastructure for consumption or contribution.

### Current State

**What exists:**
- GitHub repo: `Fr0zenSide/kintsugi-ds` (origin remote configured)
- 5 commits: snapshot testing, DocC, Style Dictionary v4 pipeline, toast fix
- `Package.swift` — 2 products: `DSKintsugi` (library), `DSKintsugiGallery` (library)
- Dependency: `swift-snapshot-testing` (PointFree)
- Platforms: iOS 16+, macOS 13+, visionOS 1+
- Sources: Components, Extensions, Generated (tokens), Theme, ViewModifiers, DocC
- Tokens: `color.tokens.json`, `spacing.tokens.json`, `typography.tokens.json` (W3C DTCG)
- Style Dictionary config: `style-dictionary.config.mjs`
- Node modules + npm pipeline for token generation
- Gallery app for visual testing
- Symlink: `projects/kintsugi-ds/kintsugi-ds -> /Users/jeoffrey/Documents/Workspaces/xcode/26-Perso/kintsugi-ds`

**What is missing:**
- No `.github/workflows/` — zero CI
- No README.md
- No `.claude/` config (only worktrees dir)
- No CHANGELOG.md
- No release tags
- No Swift package registry publication
- No badge/shield for build status

### Implementation Steps

1. **Create GitHub Actions CI** — `.github/workflows/ci.yml`:
   - Trigger: push to `main`/`develop`, PRs
   - Matrix: macOS-latest, Xcode 16
   - Steps: `swift build`, `swift test` (snapshot tests need simulator for iOS targets — run macOS target only in CI)
   - Add token generation step: `npm ci && npm run build` (regenerate tokens, verify no diff)

2. **Create README.md** — concise, not marketing:
   - What: Cross-platform SwiftUI design system with W3C DTCG tokens
   - Install: SPM `https://github.com/Fr0zenSide/kintsugi-ds.git`
   - Usage: import DSKintsugi, key types, gallery
   - Token pipeline: how to edit tokens, regenerate Swift code
   - License: match repo license

3. **Tag initial release** — `git tag v0.1.0` on current HEAD, push

4. **Add CHANGELOG.md** — auto-generated from the 5 existing conventional commits

5. **Verify SPM resolution** — from a clean directory, `swift package resolve --package-url https://github.com/Fr0zenSide/kintsugi-ds.git --from 0.1.0`

6. **Add `.claude/settings.json`** — match Shiki workspace conventions for Claude Code

7. **Wire into WabiSabi** — update WabiSabi's Package.swift to depend on `DSKintsugi` instead of local DesignKit (if not already done)

### Files to create/modify

All paths relative to `projects/kintsugi-ds/`:

| Path | Action |
|------|--------|
| `.github/workflows/ci.yml` | New — GitHub Actions CI |
| `README.md` | New — package documentation |
| `CHANGELOG.md` | New — generated from git log |
| `.claude/settings.json` | New — Claude Code project config |

### Tests

- CI workflow passes on push (verify via `gh run list` after push)
- `swift package resolve` works from a clean consumer project
- `swift build` succeeds on both macOS and iOS (simulated in Xcode) targets
- Token regeneration produces no diff (`npm run build && git diff --exit-code Sources/DSKintsugi/Generated/`)

### Sub-agent split

Single agent — small scope, sequential steps.

### Dependencies on other tasks

None. Fully independent. Can run in parallel with all other tasks.

---

## Execution Order

```
          Task 1 (dogfood)
              │
              ▼
          Task 3 (@Ronin fixes)     Task 2 (OpenAPI)     Task 4 (DSKintsugi)
            ┌───┐                      ┌───┐
            │ A │ ShikiCore            │ A │ Domains 1-7
            │ B │ ShikiMCP             │ B │ Domains 8-14
            └───┘                      └───┘
```

- **Task 1 first** — validates shiki ship pipeline, may surface bugs that inform Task 3
- **Tasks 2, 3, 4 in parallel** after Task 1 completes
- **Task 3** splits into 2 sub-agents (ShikiCore vs ShikiMCP)
- **Task 2** splits into 2 sub-agents (domain halves)
- **Task 4** is a single agent

**Total agent-hours estimate**: ~4h elapsed (with parallelism), ~8h sequential.
