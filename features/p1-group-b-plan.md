# P1 Group B — Implementation Specs

> Author: @Sensei (CTO) | Date: 2026-03-23 | Status: Ready for @Daimyo review
> Scope: 3 tasks — OpenRouterProvider + LocalProvider, DecisionQueue + ShikiAgentClient, BackendClient NetKit migration
> Estimated total: ~650 LOC, ~38 tests, 3 sub-agents (parallelizable)

---

## Task 1: OpenRouterProvider + LocalProvider (ShikiCore Wave 6)

### What & Why

The `AgentProvider` protocol exists in ShikiCore (`packages/ShikiCore/Sources/ShikiCore/Agent/AgentProvider.swift`) with a working `ClaudeProvider` implementation. Wave 6 delivers multi-provider routing so non-critical agent tasks (research, summaries, embeddings) can use cheaper models via OpenRouter, and local LLMs via LM Studio/Ollama for privacy-sensitive or offline work.

This is the "no AI lock-in" principle made real: `CompanyManager` picks a provider per task based on cost tier, model capability, and availability.

### Current State

**Exists:**
- `AgentProvider` protocol: `dispatch(prompt:workingDirectory:options:) async throws -> AgentResult`, `cancel()`, `currentSessionSpend`
- `AgentOptions`: model, maxTokens, outputFormat (.json/.text), allowedTools
- `AgentResult`: output, exitCode, tokensUsed, duration
- `ClaudeProvider` (actor): wraps `claude -p` via `Process`, parses spend from JSON output
- 6 tests in `AgentProviderTests.swift`

**Missing:**
- `OpenRouterProvider` — HTTP-based, uses NetKit (or URLSession until NetKit migration in Task 3)
- `LocalProvider` — HTTP to `127.0.0.1:1234` (LM Studio) or `11434` (Ollama)
- `FallbackChain` — tries providers in order, falls back on failure
- `ProviderRegistry` — central registry for available providers, selection by capability

### Implementation Steps

1. **OpenRouterProvider.swift** (actor, ~120 LOC)
   - Init with `apiKey: String`, `baseURL: String = "https://openrouter.ai/api/v1"`
   - `dispatch()` sends POST to `/chat/completions` with OpenAI-compatible payload
   - Maps `AgentOptions.model` to OpenRouter model string (e.g. "anthropic/claude-sonnet", "google/gemini-flash")
   - Parses `usage.total_tokens` into `AgentResult.tokensUsed`
   - Parses `usage.total_cost` or estimates from token count for `currentSessionSpend`
   - Uses `URLSession` directly (no curl subprocess) — same pattern as `EventPersister`
   - `cancel()` cancels the in-flight `URLSession` task via stored `Task` handle
   - Reads API key from environment `OPENROUTER_API_KEY` or explicit init param

2. **LocalProvider.swift** (actor, ~90 LOC)
   - Init with `baseURL: String = "http://127.0.0.1:1234"` (LM Studio default)
   - Same OpenAI-compatible `/v1/chat/completions` endpoint (LM Studio and Ollama both support this)
   - `currentSessionSpend` always returns 0 (local = free)
   - `tokensUsed` parsed from response `usage` field
   - Health check: GET `/v1/models` — if unreachable, throw `AgentProviderError.unavailable`
   - No API key needed (local)

3. **FallbackChain.swift** (~60 LOC)
   - Conforms to `AgentProvider`
   - Init with `providers: [AgentProvider]` (ordered by preference)
   - `dispatch()` tries each provider in order; on failure, logs warning + tries next
   - `currentSessionSpend` sums all providers
   - `cancel()` cancels all providers

4. **ProviderRegistry.swift** (~50 LOC)
   - Static registry: `register(name:provider:)`, `provider(named:) -> AgentProvider?`
   - `defaultChain() -> FallbackChain` — builds chain from available providers (Claude > OpenRouter > Local)
   - Capability tags: `.codeExecution`, `.longContext`, `.cheap`, `.offline`

5. **AgentProviderError.swift** (~20 LOC)
   - `.unavailable(provider: String)`
   - `.authenticationFailed(provider: String)`
   - `.rateLimited(retryAfter: Duration?)`
   - `.invalidResponse(provider: String, detail: String)`

### Files to create/modify

| Action | Path | LOC |
|--------|------|-----|
| Create | `packages/ShikiCore/Sources/ShikiCore/Agent/OpenRouterProvider.swift` | ~120 |
| Create | `packages/ShikiCore/Sources/ShikiCore/Agent/LocalProvider.swift` | ~90 |
| Create | `packages/ShikiCore/Sources/ShikiCore/Agent/FallbackChain.swift` | ~60 |
| Create | `packages/ShikiCore/Sources/ShikiCore/Agent/ProviderRegistry.swift` | ~50 |
| Create | `packages/ShikiCore/Sources/ShikiCore/Agent/AgentProviderError.swift` | ~20 |
| Create | `packages/ShikiCore/Tests/ShikiCoreTests/OpenRouterProviderTests.swift` | ~80 |
| Create | `packages/ShikiCore/Tests/ShikiCoreTests/LocalProviderTests.swift` | ~50 |
| Create | `packages/ShikiCore/Tests/ShikiCoreTests/FallbackChainTests.swift` | ~60 |

### Tests

| Suite | Tests | Strategy |
|-------|-------|----------|
| OpenRouterProviderTests | 6 | Mock URLSession via protocol injection. Test: request building (URL, headers, body JSON), model mapping, token parsing, spend accumulation, error mapping (401 -> authFailed, 429 -> rateLimited) |
| LocalProviderTests | 4 | Mock URLSession. Test: request to localhost, zero spend, health check failure -> unavailable, model listing |
| FallbackChainTests | 5 | Inject mock providers. Test: first succeeds -> done, first fails -> second tried, all fail -> throws last error, cancel propagates to all, spend sums correctly |
| ProviderRegistryTests | 3 | Test: register/retrieve, default chain construction, capability filtering |
| **Total** | **18** | |

### Sub-agent split

**Single sub-agent** — all files are in `packages/ShikiCore/Sources/ShikiCore/Agent/`. No cross-directory dependencies. Branch: `feature/shikicore-wave6-providers`.

### Dependencies

- `AgentProvider` protocol (exists, Wave 1 — no changes needed)
- `URLSession` (Foundation — no new SPM deps)
- OpenRouter API key in env (runtime, not build-time)
- LM Studio running at 127.0.0.1:1234 (for integration tests only, unit tests use mocks)

---

## Task 2: DecisionQueue + ShikiAgentClient (ShikiCore Wave 3 gaps)

### What & Why

The backend has a complete `decision_queue` table (migration 004) and REST API (`/api/decision-queue/*`). The CLI has a `DecideCommand` that reads and answers pending decisions. But ShikiCore has NO `DecisionQueue` or `ShikiAgentClient` — the FSM (`FeatureLifecycle`) cannot programmatically create decisions or dispatch agents. These are the two missing pieces that make `FeatureLifecycle` actually drive features through the pipeline.

### Current State

**Backend (complete):**
- Table `decision_queue`: id, company_id, task_id, pipeline_run_id, tier (1-3), question, options (JSONB), context, answered, answer, answered_by, answered_at, metadata (JSONB)
- `POST /api/decision-queue` — create decision (DecisionCreateSchema: companyId, taskId?, pipelineRunId?, tier, question, options?, context?, metadata?)
- `GET /api/decision-queue/pending` — list pending with company JOIN
- `PATCH /api/decision-queue/:id` — answer (auto-unblocks task if all decisions answered)
- `GET /api/decision-queue?company_id=&answered=&tier=` — filtered list

**CLI (partial):**
- `DecideCommand` in `tools/shiki-ctl/Sources/shikki/Commands/DecideCommand.swift` — interactive TUI for answering T1 decisions
- `BackendClient.getPendingDecisions()` and `answerDecision(id:answer:answeredBy:)` exist
- `BackendClient` has NO `createDecision()` method
- `HeartbeatLoop.checkDecisions()` polls pending decisions and notifies via ntfy on new T1s

**ShikiCore (missing):**
- No `DecisionQueue.swift` in `Orchestration/`
- No `ShikiAgentClient.swift` in `Agent/`
- `FeatureLifecycle.swift` exists but cannot block on decisions or dispatch agents

### Implementation Steps

1. **Add `createDecision` to BackendClient** (~15 LOC)
   - `func createDecision(_ input: DecisionInput) async throws -> Decision`
   - POST to `/api/decision-queue` with body matching `DecisionCreateSchema`
   - New `DecisionInput` struct (companyId, taskId?, pipelineRunId?, tier, question, options?, context?, metadata?)

2. **DecisionQueue.swift** in ShikiCore (actor, ~120 LOC)
   - Properties: `dbURL: String`, `pollInterval: Duration = .seconds(10)`
   - `func ask(tier: DecisionTier, question: String, companyId: String, taskId: String?, context: String?, options: [String: String]?) async throws -> String`
     - POST to `/api/decision-queue` to create
     - Poll `GET /api/decision-queue/:id` until `answered == true`
     - Return `answer` string
     - Emit `LifecycleEvent.decisionAsked` and `LifecycleEvent.decisionAnswered`
   - `func askBatch(questions: [DecisionRequest]) async throws -> [String: String]`
     - Create all decisions, poll until all answered (or timeout)
   - `DecisionTier` enum: `.t1` (blocks, ntfy push), `.t2` (blocks, silent), `.t3` (non-blocking, auto-timeout 24h)
   - `DecisionRequest` struct: tier, question, context?, options?
   - Timeout: T1 = unlimited (governor gate), T2 = 4h, T3 = 24h (auto-answer with default)
   - Integration with `EventPersister`: emit events on create/answer

3. **ShikiAgentClient.swift** (actor, ~150 LOC)
   - The central dispatch actor — `FeatureLifecycle` calls this to run agent work
   - Properties: `provider: AgentProvider`, `eventPersister: EventPersister`
   - `func dispatch(prompt: String, workingDirectory: URL, options: AgentOptions) async throws -> AgentResult`
     - Wraps `provider.dispatch()` with event emission (start/end/error)
     - Tracks active sessions for cancel-all
   - `func dispatchWithRetry(prompt:workingDirectory:options:maxRetries:) async throws -> AgentResult`
     - Retries on transient failures (rate limit, timeout) with exponential backoff
   - `func cancel() async` — cancel current dispatch
   - `func cancelAll() async` — cancel all active dispatches
   - `var activeSessions: Int { get async }` — count of running dispatches
   - `var totalSpend: Double { get async }` — accumulated USD from provider

4. **Wire into FeatureLifecycle** (~30 LOC changes)
   - Add `agentClient: ShikiAgentClient` and `decisionQueue: DecisionQueue` as init params
   - In `decisions_needed` state: call `decisionQueue.ask()` for each question
   - In `building` state: call `agentClient.dispatch()` with SDD prompt
   - In `gating` state: call `agentClient.dispatch()` with quality check prompt

### Files to create/modify

| Action | Path | LOC |
|--------|------|-----|
| Create | `packages/ShikiCore/Sources/ShikiCore/Orchestration/DecisionQueue.swift` | ~120 |
| Create | `packages/ShikiCore/Sources/ShikiCore/Agent/ShikiAgentClient.swift` | ~150 |
| Modify | `packages/ShikiCore/Sources/ShikiCore/Lifecycle/FeatureLifecycle.swift` | ~30 |
| Modify | `tools/shiki-ctl/Sources/ShikiCtlKit/Services/BackendClient.swift` | ~15 |
| Create | `tools/shiki-ctl/Sources/ShikiCtlKit/Models/DecisionInput.swift` | ~30 |
| Create | `packages/ShikiCore/Tests/ShikiCoreTests/DecisionQueueTests.swift` | ~70 |
| Create | `packages/ShikiCore/Tests/ShikiCoreTests/ShikiAgentClientTests.swift` | ~60 |

### Tests

| Suite | Tests | Strategy |
|-------|-------|----------|
| DecisionQueueTests | 6 | Mock HTTP layer. Test: create sends correct POST, poll loop resolves on answer, T3 auto-timeout, batch creates all then polls, event emission on ask/answer, timeout respects tier |
| ShikiAgentClientTests | 5 | Mock AgentProvider. Test: dispatch wraps provider, retry on rate limit, cancel stops active, cancelAll propagates, spend accumulates from provider |
| BackendClient+Decision | 2 | Test: createDecision builds correct curl args, DecisionInput encodes to expected JSON |
| **Total** | **13** | |

### Sub-agent split

**Single sub-agent** — touches `packages/ShikiCore/` and `tools/shiki-ctl/`. Branch: `feature/shikicore-wave3-decision-agent`.

### Dependencies

- `BackendClient` (exists — adding one method)
- `Decision` model (exists in `ShikiCtlKit/Models/Decision.swift`)
- `AgentProvider` protocol (exists)
- `EventPersister` (exists)
- `FeatureLifecycle` (exists — adding dependency injection params)
- Backend running at localhost:3900 (for integration tests)

---

## Task 3: Migrate BackendClient to NetKit

### What & Why

`BackendClient` currently shells out to `curl` via `Process` for every HTTP request. This was a deliberate v0.2.0 choice (AsyncHTTPClient connection pools went stale with Docker networking). Now that:

1. NetKit exists with a proper `NetworkProtocol` + `EndPoint` pattern using `URLSession`
2. `EventPersister` already uses `URLSession` directly with no issues
3. The curl approach has known problems: no proper HTTP status code visibility (feedback: `curl -sf` error blindness), `Process` spawning overhead, no connection reuse

Migration to NetKit gives: typed endpoints, proper error handling with HTTP status codes, connection reuse, testability via `MockNetworkService`, and eliminates the `curl` dependency.

### Current State

**BackendClient** (`tools/shiki-ctl/Sources/ShikiCtlKit/Services/BackendClient.swift`):
- Actor with `baseURL: String`
- 3 generic helpers: `get<T>()`, `post<T>()`, `patch<T>()` — all route through `curlRequest()`
- `curlRequest()` spawns `Process` with `/usr/bin/env curl`, pipes stdin for body, reads stdout
- `healthCheck()` uses separate curl -sf process
- 14 public API methods total

**Endpoints called (complete inventory):**

| Method | Path | Request Body | Response Type |
|--------|------|-------------|---------------|
| GET | `/health` | — | Bool (status check) |
| GET | `/api/orchestrator/status` | — | `OrchestratorStatus` |
| GET | `/api/orchestrator/stale?threshold_minutes=N` | — | `[Company]` |
| GET | `/api/orchestrator/ready` | — | `[Company]` |
| GET | `/api/orchestrator/dispatcher-queue` | — | `[DispatcherTask]` |
| GET | `/api/orchestrator/report?date=YYYY-MM-DD` | — | `DailyReport` |
| POST | `/api/orchestrator/heartbeat` | `{companyId, sessionId}` | `HeartbeatResponse` |
| GET | `/api/companies?status=X` | — | `[Company]` |
| PATCH | `/api/companies/:id` | `{...updates}` | `Company` |
| GET | `/api/decision-queue/pending` | — | `[Decision]` |
| PATCH | `/api/decision-queue/:id` | `{answer, answeredBy}` | `Decision` |
| POST | `/api/session-transcripts` | `SessionTranscriptInput` | `SessionTranscript` |
| GET | `/api/session-transcripts?...` | — | `[SessionTranscript]` |
| GET | `/api/session-transcripts/:id` | — | `SessionTranscript` |
| GET | `/api/orchestrator/board` | — | `[BoardEntry]` |

**NetKit** (`packages/NetKit/Sources/NetworkKit/`):
- `EndPoint` protocol: host, port, scheme, apiPath, path, method, header, body, queryParams
- `NetworkProtocol`: `createRequest(endPoint:) -> URLRequest`, `sendRequest<T>(endpoint:) async throws -> T`
- `NetworkService`: concrete implementation using `URLSession.shared`
- `MockNetworkService`: for testing
- `NetworkError`: requestFailed, unexpectedStatusCode, invalidData, jsonParsingFailed, wsError, unknown
- Uses Combine publisher variants too (WabiSabi legacy) — we only need the async/await path

### Implementation Steps

1. **ShikiBackendEndpoint enum** (~120 LOC)
   - Conforms to `EndPoint`
   - One case per API call, e.g.:
     ```swift
     enum ShikiBackendEndpoint: EndPoint {
         case health
         case orchestratorStatus
         case staleCompanies(thresholdMinutes: Int)
         case readyCompanies
         case dispatcherQueue
         case dailyReport(date: String?)
         case heartbeat(companyId: String, sessionId: String)
         case companies(status: String?)
         case patchCompany(id: String, updates: [String: Any])
         case pendingDecisions
         case answerDecision(id: String, answer: String, answeredBy: String)
         case createTranscript(SessionTranscriptInput)
         case listTranscripts(companySlug: String?, taskId: String?, limit: Int)
         case getTranscript(id: String)
         case boardOverview
     }
     ```
   - Each case computes `host`, `port`, `scheme`, `apiPath`, `path`, `method`, `header`, `body`, `queryParams`
   - Host defaults to `localhost`, port to `3900`, scheme to `http`

2. **Rewrite BackendClient internals** (~80 LOC delta)
   - Replace `curlRequest()` with `NetworkService().sendRequest(endpoint:)`
   - Replace `healthCheck()` curl with URLSession GET to `/health` (with 5s timeout)
   - Keep the same public API — all callers (HeartbeatLoop, DecideCommand, etc.) unchanged
   - Inject `NetworkProtocol` for testability: `init(network: NetworkProtocol = NetworkService(), ...)`
   - Remove `BackendError.httpError` — map to `NetworkError` instead (or keep as wrapper)

3. **Add ShikiCtlKit dependency on NetKit** (~5 LOC)
   - Update `tools/shiki-ctl/Package.swift`: add `.package(path: "../../packages/NetKit")` + target dep
   - Note: NetKit depends on CoreKit — transitive dependency, already handled by SPM

4. **Fix NetKit for server-side use** (~20 LOC)
   - NetKit's `NetworkProtocol+Implementations.swift` uses `decoder.pocketbaseDateDecodingStrategy()` from CoreKit — this is fine for WabiSabi but the backend uses ISO8601 strings. Add a configurable date strategy or use raw strings (current Decision model already decodes dates as String).
   - The `body: [String: Any]?` on `EndPoint` loses type safety — for this migration we match the existing pattern, but flag for future improvement (Encodable body).

5. **Health check special case** (~15 LOC)
   - `healthCheck()` needs to NOT throw on non-200 — just return Bool
   - Implement as raw `URLSession.data(for:)` with timeout, catch all errors -> false

### Files to create/modify

| Action | Path | LOC |
|--------|------|-----|
| Create | `tools/shiki-ctl/Sources/ShikiCtlKit/Endpoints/ShikiBackendEndpoint.swift` | ~120 |
| Modify | `tools/shiki-ctl/Sources/ShikiCtlKit/Services/BackendClient.swift` | ~80 (rewrite internals) |
| Modify | `tools/shiki-ctl/Package.swift` | ~5 (add NetKit dep) |
| Modify | `packages/NetKit/Sources/NetworkKit/NetworkProtocol+Implementations.swift` | ~10 (configurable date strategy) |
| Create | `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShikiBackendEndpointTests.swift` | ~80 |
| Create | `tools/shiki-ctl/Tests/ShikiCtlKitTests/BackendClientNetKitTests.swift` | ~50 |

### Tests

| Suite | Tests | Strategy |
|-------|-------|----------|
| ShikiBackendEndpointTests | 15 | Test each endpoint case: verify URL path, method, headers, body encoding, query params. Pure value tests — no network. |
| BackendClientNetKitTests | 5 | Inject `MockNetworkService`. Test: successful decode, error mapping (unexpectedStatusCode -> BackendError), health check true on 200, health check false on timeout, JSON error body extraction |
| Existing BackendClient tests | 0 | None exist — this migration adds the first real test coverage |
| **Total** | **20** | (but 15 are trivial endpoint value tests) |

### Sub-agent split

**Single sub-agent** — touches `tools/shiki-ctl/` and `packages/NetKit/`. Branch: `feature/backendclient-netkit-migration`.

### Dependencies

- NetKit package (exists at `packages/NetKit/`)
- CoreKit (transitive via NetKit — exists)
- All existing callers of BackendClient (HeartbeatLoop, DecideCommand, ShikkiEngine, etc.) — public API unchanged, no caller modifications needed
- Task 2 adds `createDecision()` to BackendClient — if both run in parallel, merge conflict is trivial (both add a method). Recommend: Task 3 goes first, Task 2 follows.

---

## Execution Plan

### Ordering & Parallelism

```
Task 3 (BackendClient -> NetKit)  ──┐
                                     ├──→ Task 2 (DecisionQueue + ShikiAgentClient)
Task 1 (OpenRouter + Local)  ───────┘
```

- **Task 1 and Task 3 are fully parallel** — no file overlap.
- **Task 2 depends softly on Task 3** — it modifies BackendClient. Run in parallel if we accept a trivial merge conflict (one added method), or sequence Task 3 -> Task 2.
- All three can run as separate worktree sub-agents.

### Branch Strategy

| Task | Branch | Base | Merges to |
|------|--------|------|-----------|
| 1 | `feature/shikicore-wave6-providers` | `develop` | `develop` |
| 2 | `feature/shikicore-wave3-decision-agent` | `develop` | `develop` |
| 3 | `feature/backendclient-netkit-migration` | `develop` | `develop` |

### Totals

| Metric | Task 1 | Task 2 | Task 3 | Total |
|--------|--------|--------|--------|-------|
| New files | 8 | 7 | 6 | 21 |
| LOC (est.) | ~340 | ~345 | ~235 | ~920 |
| Tests | 18 | 13 | 20 | 51 |
| Risk | Low (additive) | Medium (wires into FSM) | Medium (replaces transport) |

---

## Review History

| Date | Reviewer | Decision |
|------|----------|----------|
| 2026-03-23 | @Sensei | Spec drafted from codebase audit |
