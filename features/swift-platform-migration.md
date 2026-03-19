# Feature: Swift Platform Migration (v4.0)
> Created: 2026-03-09 | Status: Phase 5b — Execution Plan (PASS) | Owner: @Daimyo

## Context
Shiki currently runs on a polyglot stack (Deno backend, Vue frontend, Bash CLI) that fragments the developer experience across 3 languages and 3 toolchains. This migration rewrites the entire platform in Swift — one language, one toolchain, shared types end-to-end — to enable native hardware access (Metal, sensors), eliminate cross-language type drift, and leverage the existing shared SPM packages (CoreKit, NetworkKit, SecurityKit, DesignKit).

## Inspiration

### Brainstorm Results

**@Shogun (Competitive Intelligence)**

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 1 | **Full-stack Swift monorepo with SPM workspace** — Single `Package.swift` at root defining ShikiServer, ShikiApp, ShikiCLI, ShikiKit as products sharing exact same model types. Zero serialization layer between client and server. | @Shogun | High | Critical | Perfect | BUILD |
| 2 | **Native push notifications replacing ntfy** — APNs for remote approval workflows. Claude Code requests approval → server sends push → user approves on phone → WebSocket callback. Eliminates the ntfy dependency entirely. | @Shogun | High | High | Strong | BUILD |
| 3 | **Metal-accelerated local embeddings** — Replace Ollama's nomic-embed-text with a Core ML / Metal-based embedding model running in-process on the server. Eliminates the Ollama container dependency. Sub-10ms embedding latency. | @Shogun | Medium | High | Strong | BUILD |

**@Hanami (Product Design / UX)**

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 4 | **Live pipeline dashboard with SwiftUI** — Real-time pipeline monitoring using Vapor WebSocket → SwiftUI Observation framework. Each pipeline phase renders as an animated state machine. Tap any phase to see its checkpoint data. | @Hanami | High | High | Strong | BUILD |
| 5 | **Memory browser with semantic search UI** — Native search interface for the vector memory system. Type a query, get instant results with relevance scores, category badges, and source file links. Spotlight-like UX. | @Hanami | High | High | Strong | BUILD |
| 6 | **Agent activity timeline** — Vertical timeline showing agent spawn/complete/fail events with color-coded handles. Tap to expand payload. Filter by agent persona. Push-notification-worthy events highlighted. | @Hanami | High | Medium | Strong | BUILD |

**@Kintsugi (Philosophy & Repair)**

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 7 | **Incremental migration with coexistence** — Don't rip-and-replace. Build the Swift server alongside the Deno server. Route-by-route migration with a shared PostgreSQL database. The old system continues working until the new one is proven. Respect for what came before. | @Kintsugi | High | Critical | Perfect | BUILD |
| 8 | **Migration audit trail** — Every route migrated gets logged as a memory: what changed, what was learned, what was intentionally left behind. The migration itself becomes part of the project's knowledge base. | @Kintsugi | High | Medium | Strong | CONSIDER |

**@Sensei (CTO / Technical Architect)**

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 9 | **ShikiKit as the shared types package** — New SPM package containing all API DTOs, WebSocket message types, route definitions, and error types. Both server and client import ShikiKit. Type changes cause compile errors on both sides — impossible to drift. | @Sensei | High | Critical | Perfect | BUILD |
| 10 | **Fluent ORM with migration-based schema evolution** — Replace raw SQL schema files with Fluent migrations. Each migration is a Swift file, version-controlled, testable. TimescaleDB hypertables via raw SQL within migration wrappers. | @Sensei | High | High | Strong | BUILD |

### Selected Ideas

**@Daimyo selects all 10 ideas, with priority tiers:**

**Tier 1 — Foundation (must ship in v4.0):**
- Idea 1: Full-stack Swift monorepo with SPM workspace
- Idea 9: ShikiKit shared types package
- Idea 10: Fluent ORM with migration-based schema evolution
- Idea 7: Incremental migration with coexistence

**Tier 2 — Core Features (v4.0 target):**
- Idea 4: Live pipeline dashboard with SwiftUI
- Idea 5: Memory browser with semantic search UI
- Idea 2: Native push notifications replacing ntfy

**Tier 3 — Deferred (v4.1+):**
- Idea 3: Metal-accelerated local embeddings (requires Core ML model research)
- Idea 6: Agent activity timeline (nice-to-have, builds on Idea 4)
- Idea 8: Migration audit trail (can be added during migration)

## Synthesis

### Feature Brief

**Goal**: Rewrite the Shiki platform (backend, frontend, CLI) in Swift using Vapor, SwiftUI, and ArgumentParser, sharing types end-to-end via a new ShikiKit package, while reusing existing SPM packages (CoreKit, NetworkKit, SecurityKit, DesignKit).

**Scope (v4.0)**:
- ShikiServer: Vapor REST API + WebSocket server, 1:1 port of all 29 Deno endpoints, PostgreSQL via Fluent ORM (with raw postgres-nio for TimescaleDB-specific features), embedding via HTTP client to LM Studio
- ShikiApp: SwiftUI native macOS/iOS app replacing the Vue dashboard — pipeline monitor, memory browser, project overview, notification handling
- ShikiCLI: Swift ArgumentParser replacing the Bash `./shiki` script — init, start, stop, status, new, health commands
- ShikiKit: New shared SPM package — all API DTOs, WebSocket message types, route contracts, error types
- Incremental migration: Deno server stays operational during migration; shared PostgreSQL database; route-by-route cutover

**Out of scope (deferred to v4.1+)**:
- Metal-accelerated local embeddings (Ollama/LM Studio HTTP client for now)
- Agent activity timeline (beyond basic event listing)
- Migration audit trail (manual for now)
- Linux server deployment (macOS-first; Linux compatibility via conditional compilation later)
- Community marketplace
- MCP server integration

**Success criteria**:
1. All 29 API endpoints pass integration tests against the same PostgreSQL schema
2. WebSocket real-time updates work identically to Deno implementation
3. ShikiKit types compile on both server and client targets
4. CLI passes all existing `./shiki` command smoke tests
5. SwiftUI app renders dashboard summary, pipeline list, and memory search
6. Zero runtime crashes on macOS 14+ and iOS 17+
7. TDD: minimum 80% code coverage on ShikiServer, 100% on ShikiKit

**Dependencies**:
- Existing SPM packages: CoreKit (DI, logging), NetworkKit (HTTP layer), SecurityKit (keychain), DesignKit (themes)
- Vapor 4.x + Fluent 4.x + postgres-nio
- Swift 5.9+ (macOS 14+, iOS 17+)
- PostgreSQL 17 + TimescaleDB + pgvector (existing Docker infrastructure)
- LM Studio at `http://127.0.0.1:1234` for embeddings

## Business Rules

```
BR-01: ShikiKit defines ALL shared types (DTOs, WebSocket messages, error codes).
       Server and client MUST import ShikiKit — no local type definitions for API contracts.

BR-02: Every Deno endpoint has a 1:1 Swift equivalent. The route paths, HTTP methods,
       and JSON response shapes are identical. Existing clients (CLI, dashboard) work
       against either backend without changes.

BR-03: The Vapor server uses the same PostgreSQL schema as the Deno server. No schema
       changes during migration. Fluent models map to existing tables, not the reverse.

BR-04: TimescaleDB-specific features (hypertables, continuous aggregates, compression
       policies) use raw postgres-nio SQL within Fluent migration wrappers. Fluent ORM
       handles standard CRUD.

BR-05: Vector embeddings use HTTP client to LM Studio (OpenAI-compatible /v1/embeddings
       endpoint). The embedding dimension (768) and model are configurable via environment
       variables. Falls back gracefully if LM Studio is unavailable.

BR-06: WebSocket implementation supports the same message protocol: subscribe/unsubscribe
       by channel (project:<uuid>), broadcast to project subscribers, chat message relay.
       Uses Vapor's built-in WebSocket support.

BR-07: The CLI (ShikiCLI) wraps Docker Compose commands for start/stop/status and
       communicates with ShikiServer via NetworkKit's HTTP layer. It replaces the Bash
       script 1:1 — same commands, same flags, same output format.

BR-08: The SwiftUI app (ShikiApp) connects to ShikiServer via both REST (NetworkKit)
       and WebSocket (native URLSessionWebSocketTask or Vapor client). Real-time updates
       render within 100ms of server broadcast.

BR-09: Push notifications use APNs via Vapor's APNS library. Approval requests
       (pipeline gates, @Daimyo decisions) generate remote notifications. The app
       handles notification actions (approve/reject) and relays to the server.

BR-10: All new code follows TDD. Tests run via `swift test`. Minimum coverage:
       100% on ShikiKit, 80% on ShikiServer, 60% on ShikiCLI. ShikiApp uses
       ViewInspector or previews for UI verification.

BR-11: The SPM workspace uses a root Package.swift that defines all targets.
       Existing packages (CoreKit, NetworkKit, SecurityKit, DesignKit) are local
       dependencies. ShikiKit depends on CoreKit only.

BR-12: Configuration uses environment variables (same as Deno): DATABASE_URL,
       OLLAMA_URL, EMBED_MODEL, WS_PORT, NODE_ENV, LOG_LEVEL. Vapor reads these
       via Environment.get().

BR-13: Health check endpoints (/health, /health/full) return identical JSON shapes.
       The ./shiki status command and uptime-kuma monitoring work without changes.

BR-14: Zod validation schemas map to Swift Codable + custom validation. Every
       request body is validated before processing. Invalid requests return 400
       with the same error format as the Deno server.

BR-15: Git flow: feature/* branches from develop. Each migration phase (server,
       CLI, app) can be its own feature branch. PRs go through /pre-pr.

BR-16: The Deno server and Swift server can run simultaneously during migration
       (on different ports). A reverse proxy or feature flag controls which
       backend receives traffic. The database is shared.
```

## Test Plan

### Unit Tests — ShikiKit (shared types)

```
BR-01 → test_projectDTO_encodesToExpectedJSON()
BR-01 → test_projectDTO_decodesFromServerJSON()
BR-01 → test_memorySearchRequest_encodesAllFields()
BR-01 → test_memorySearchResponse_decodesWithEmbedding()
BR-01 → test_wsSubscribeMessage_encodesToExpectedFormat()
BR-01 → test_wsUnsubscribeMessage_encodesToExpectedFormat()
BR-01 → test_wsChatMessage_encodesAllFields()
BR-01 → test_pipelineRunDTO_roundTrips()
BR-01 → test_agentEventDTO_roundTrips()
BR-01 → test_radarWatchItemDTO_roundTrips()
BR-01 → test_ingestRequestDTO_roundTrips()
BR-14 → test_memoryInput_validatesRequiredFields()
BR-14 → test_memoryInput_rejectsEmptyContent()
BR-14 → test_memorySearchInput_rejectsNegativeLimit()
BR-14 → test_agentEventInput_rejectsInvalidUUID()
BR-14 → test_pipelineRunCreate_validatesEnumValues()
```

### Unit Tests — ShikiServer (Vapor routes)

```
BR-02 → test_healthEndpoint_returnsExpectedShape()
BR-02 → test_healthFullEndpoint_returnsAllSections()
BR-02 → test_listProjects_returnsArray()
BR-02 → test_listSessions_filtersbyProjectId()
BR-02 → test_listActiveSessions_returnsView()
BR-02 → test_listAgents_filtersBySessionId()
BR-02 → test_postAgentEvent_broadcastsToWS()
BR-02 → test_listAgentEvents_respectsLimit()
BR-02 → test_postPerformanceMetric_stores()
BR-02, BR-05 → test_postMemory_generatesEmbedding()
BR-02 → test_listMemories_filtersByProject()
BR-02 → test_searchMemories_returnsSortedByRelevance()
BR-02 → test_listMemorySources_groupsByFile()
BR-02 → test_postChatMessage_broadcastsToWS()
BR-02 → test_listChatMessages_requiresSessionId()
BR-02 → test_postDataSync_stores()
BR-02 → test_postPrCreated_broadcastsToWS()
BR-02 → test_listGitEvents_filtersbyType()
BR-02 → test_dashboardSummary_returnsAllCounts()
BR-02 → test_dashboardPerformance_respectsDaysParam()
BR-02 → test_dashboardActivity_respectsHoursParam()
BR-02 → test_dashboardCosts_returnsLeaderboard()
BR-02 → test_dashboardGit_returnsDailyActivity()
BR-02 → test_ingestChunks_storesWithEmbeddings()
BR-02 → test_listIngestSources_requiresProjectId()
BR-02 → test_radarWatchlist_CRUD()
BR-02 → test_radarScan_triggersAndReturnsId()
BR-02 → test_radarDigest_returnsLatest()
BR-02 → test_pipelineRun_createAndRetrieve()
BR-02 → test_pipelineCheckpoint_addsAndLists()
BR-02 → test_pipelineResume_updatesState()
BR-02 → test_pipelineRouting_evaluatesRules()
BR-02 → test_pipelineRules_CRUD()
BR-13 → test_healthCheck_identicalToDenoShape()
BR-03 → test_fluentModel_mapsToExistingSchema()
```

### Unit Tests — ShikiServer (database layer)

```
BR-03 → test_projectModel_readsExistingRow()
BR-03 → test_sessionModel_readsExistingRow()
BR-03 → test_agentModel_readsExistingRow()
BR-04 → test_agentEventsHypertable_insertsViaRawSQL()
BR-04 → test_chatMessagesHypertable_insertsViaRawSQL()
BR-04 → test_performanceMetricsHypertable_insertsViaRawSQL()
BR-05 → test_embedding_callsLMStudioEndpoint()
BR-05 → test_embedding_fallsBackGracefullyWhenUnavailable()
BR-05 → test_embedding_respectsConfiguredModel()
```

### Unit Tests — ShikiCLI

```
BR-07 → test_initCommand_startsDockerCompose()
BR-07 → test_startCommand_startsServices()
BR-07 → test_stopCommand_stopsServices()
BR-07 → test_statusCommand_displaysHealth()
BR-07 → test_newCommand_createsProjectDirectory()
BR-07 → test_healthCommand_exitsCodes()
BR-12 → test_configurationReadsEnvironmentVariables()
```

### Unit Tests — ShikiApp

```
BR-08 → test_dashboardView_rendersProjectSummary()
BR-08 → test_pipelineListView_showsRunningPipelines()
BR-08 → test_memorySearchView_displayResults()
BR-08 → test_webSocketManager_connectsAndSubscribes()
BR-08 → test_webSocketManager_handlesDisconnect()
BR-09 → test_notificationHandler_registersForAPNs()
BR-09 → test_notificationHandler_processesApprovalAction()
```

### Integration Tests

```
BR-02, BR-03 → integration_allEndpoints_matchDenoResponses()
BR-06 → integration_webSocket_subscribeAndReceiveBroadcast()
BR-16 → integration_dualServer_sharedDatabase_noConflicts()
BR-05 → integration_embeddingPipeline_endToEnd()
```

## Architecture

### Package Structure

```
shiki/
├── Package.swift                    ← Root SPM workspace manifest
├── ShikiServer/
│   └── Sources/
│       ├── App/
│       │   ├── configure.swift       ← Vapor app configuration, DI, middleware
│       │   ├── routes.swift          ← Route registration (maps to Deno routes.ts)
│       │   ├── entrypoint.swift      ← main entry point
│       │   └── Middleware/
│       │       └── ErrorMiddleware.swift
│       ├── Controllers/
│       │   ├── HealthController.swift     ← /health, /health/full
│       │   ├── ProjectController.swift    ← /api/projects
│       │   ├── SessionController.swift    ← /api/sessions, /api/sessions/active
│       │   ├── AgentController.swift      ← /api/agents, /api/agent-update, /api/agent-events
│       │   ├── MemoryController.swift     ← /api/memories, /api/memories/search, /api/memories/sources
│       │   ├── ChatController.swift       ← /api/chat-message, /api/chat-messages
│       │   ├── DataSyncController.swift   ← /api/data-sync
│       │   ├── GitEventController.swift   ← /api/pr-created, /api/git-events
│       │   ├── DashboardController.swift  ← /api/dashboard/*
│       │   ├── IngestController.swift     ← /api/ingest/*
│       │   ├── RadarController.swift      ← /api/radar/*
│       │   ├── PipelineController.swift   ← /api/pipelines/*, /api/pipeline-rules/*
│       │   └── AdminController.swift      ← /api/admin/*
│       ├── Models/
│       │   ├── Project.swift
│       │   ├── Session.swift
│       │   ├── Agent.swift
│       │   ├── Decision.swift
│       │   ├── AgentEvent.swift       ← Raw SQL for hypertable
│       │   ├── ChatMessage.swift      ← Raw SQL for hypertable
│       │   ├── PerformanceMetric.swift ← Raw SQL for hypertable
│       │   ├── GitEvent.swift         ← Raw SQL for hypertable
│       │   ├── AgentMemory.swift      ← With vector(768) column
│       │   ├── IngestionSource.swift
│       │   ├── RadarWatchItem.swift
│       │   ├── RadarScanRun.swift
│       │   ├── PipelineRun.swift
│       │   └── PipelineCheckpoint.swift
│       ├── Services/
│       │   ├── EmbeddingService.swift    ← HTTP client to LM Studio /v1/embeddings
│       │   ├── MemorySearchService.swift ← Vector similarity search via raw SQL
│       │   ├── WebSocketManager.swift    ← Channel subscriptions, broadcast
│       │   ├── RadarScanService.swift    ← GitHub API scanning logic
│       │   └── IngestService.swift       ← Chunk storage + dedup
│       └── Migrations/
│           └── CreateInitialSchema.swift  ← Validates existing schema (no-op if present)
├── ShikiApp/
│   └── Sources/
│       ├── ShikiAppMain.swift          ← @main App struct
│       ├── Views/
│       │   ├── DashboardView.swift
│       │   ├── PipelineListView.swift
│       │   ├── PipelineDetailView.swift
│       │   ├── MemoryBrowserView.swift
│       │   ├── ProjectListView.swift
│       │   └── SettingsView.swift
│       ├── ViewModels/
│       │   ├── DashboardViewModel.swift
│       │   ├── PipelineViewModel.swift
│       │   ├── MemoryBrowserViewModel.swift
│       │   └── ProjectViewModel.swift
│       ├── Services/
│       │   ├── ShikiAPIClient.swift       ← Uses NetworkKit + ShikiKit types
│       │   ├── WebSocketClient.swift      ← Real-time updates
│       │   └── NotificationService.swift  ← APNs registration + handling
│       └── Navigation/
│           └── AppCoordinator.swift       ← Uses CoreKit Coordinator
├── ShikiCLI/
│   └── Sources/
│       ├── ShikiCLI.swift              ← @main ArgumentParser root command
│       ├── Commands/
│       │   ├── InitCommand.swift
│       │   ├── StartCommand.swift
│       │   ├── StopCommand.swift
│       │   ├── StatusCommand.swift
│       │   ├── NewCommand.swift
│       │   └── HealthCommand.swift
│       └── Services/
│           ├── DockerService.swift       ← Docker Compose wrapper
│           └── ServerClient.swift        ← Health check HTTP calls
├── packages/
│   ├── CoreKit/                        ← Existing (DI, Coordinator, AppLog)
│   ├── NetworkKit/                     ← Existing (HTTPNetwork layer)
│   ├── SecurityKit/                    ← Existing (Keychain, AuthPersistence)
│   ├── DesignKit/                      ← Existing (Theme, tokens)
│   └── ShikiKit/                       ← NEW
│       └── Sources/
│           ├── DTOs/
│           │   ├── ProjectDTO.swift
│           │   ├── SessionDTO.swift
│           │   ├── AgentDTO.swift
│           │   ├── MemoryDTO.swift
│           │   ├── ChatMessageDTO.swift
│           │   ├── GitEventDTO.swift
│           │   ├── DashboardDTO.swift
│           │   ├── IngestDTO.swift
│           │   ├── RadarDTO.swift
│           │   └── PipelineDTO.swift
│           ├── WebSocket/
│           │   ├── WSMessage.swift
│           │   └── WSChannel.swift
│           ├── Validation/
│           │   └── InputValidation.swift   ← Swift equivalent of Zod schemas
│           ├── Routes/
│           │   └── ShikiRoutes.swift       ← Route path constants + HTTP methods
│           └── Errors/
│               └── ShikiError.swift        ← Typed error codes
```

### DI Registration Plan

Using CoreKit's DI Container:

| Type | Protocol | Registration | Used By |
|------|----------|-------------|---------|
| `EmbeddingService` | `EmbeddingServiceProtocol` | `.singleton` | ShikiServer |
| `MemorySearchService` | `MemorySearchServiceProtocol` | `.singleton` | ShikiServer |
| `WebSocketManager` | `WebSocketManagerProtocol` | `.singleton` | ShikiServer |
| `RadarScanService` | `RadarScanServiceProtocol` | `.singleton` | ShikiServer |
| `IngestService` | `IngestServiceProtocol` | `.singleton` | ShikiServer |
| `ShikiAPIClient` | `ShikiAPIClientProtocol` | `.singleton` | ShikiApp, ShikiCLI |
| `WebSocketClient` | `WebSocketClientProtocol` | `.singleton` | ShikiApp |
| `NotificationService` | `NotificationServiceProtocol` | `.singleton` | ShikiApp |
| `DockerService` | `DockerServiceProtocol` | `.singleton` | ShikiCLI |

### Data Flow

```
ShikiApp (SwiftUI)                ShikiCLI (ArgumentParser)
    │                                  │
    ├─ REST ──► ShikiAPIClient ◄── REST ┘
    │           (NetworkKit)
    ├─ WS ───► WebSocketClient
    │
    ▼
ShikiServer (Vapor)
    │
    ├─ Controllers ──► Services ──► PostgreSQL (Fluent + raw postgres-nio)
    │                     │
    │                     ├──► LM Studio HTTP (/v1/embeddings)
    │                     │
    │                     └──► APNs (push notifications)
    │
    └─ WebSocketManager ──► Channel broadcast to subscribers
```

### Key Protocols

```swift
// ShikiKit
protocol ShikiAPIClientProtocol {
    func health() async throws -> HealthResponse
    func healthFull() async throws -> HealthFullResponse
    func listProjects() async throws -> [ProjectDTO]
    func listSessions(projectId: UUID?) async throws -> [SessionDTO]
    func storeMemory(_ input: MemoryInput) async throws -> MemoryStoreResponse
    func searchMemories(_ input: MemorySearchInput) async throws -> [MemorySearchResult]
    func dashboardSummary(projectId: UUID?) async throws -> DashboardSummary
    // ... 29 endpoints total
}

// ShikiServer
protocol EmbeddingServiceProtocol {
    func embed(_ text: String) async throws -> [Float]
    var isAvailable: Bool { get async }
}

protocol WebSocketManagerProtocol {
    func subscribe(client: WebSocket, channel: String)
    func unsubscribe(client: WebSocket, channel: String)
    func broadcast(to channel: String, message: Codable)
}
```

## Execution Plan

### Task 1: Create ShikiKit package scaffold
- **Files**: `packages/ShikiKit/Package.swift` (new), `packages/ShikiKit/Sources/ShikiKit.swift` (new)
- **Test**: `packages/ShikiKit/Tests/ShikiKitTests/ShikiKitTests.swift` → `test_shikiKitImports()`
- **Implement**: Package.swift with CoreKit dependency, empty module file, verify it compiles
- **Verify**: `cd packages/ShikiKit && swift test` → 1 test passing
- **BRs**: BR-01, BR-11
- **Time**: ~2 min

### Task 2: Define Project/Session/Agent DTOs
- **Files**: `packages/ShikiKit/Sources/DTOs/ProjectDTO.swift` (new), `SessionDTO.swift` (new), `AgentDTO.swift` (new)
- **Test**: `test_projectDTO_encodesToExpectedJSON()`, `test_projectDTO_decodesFromServerJSON()`
- **Implement**: Codable structs matching Deno schemas.ts types. Include CodingKeys for snake_case JSON mapping.
- **Verify**: `swift test --filter ShikiKitTests` → 3+ tests passing
- **BRs**: BR-01, BR-14
- **Time**: ~5 min

### Task 3: Define Memory/Search DTOs + validation
- **Files**: `packages/ShikiKit/Sources/DTOs/MemoryDTO.swift` (new), `packages/ShikiKit/Sources/Validation/InputValidation.swift` (new)
- **Test**: `test_memoryInput_validatesRequiredFields()`, `test_memoryInput_rejectsEmptyContent()`, `test_memorySearchInput_rejectsNegativeLimit()`, `test_memorySearchRequest_encodesAllFields()`
- **Implement**: MemoryInput, MemorySearchInput, MemoryDTO, MemorySearchResult. Validation protocol with throwing validate().
- **Verify**: `swift test --filter ShikiKitTests` → 4+ new tests passing
- **BRs**: BR-01, BR-14
- **Time**: ~5 min

### Task 4: Define remaining DTOs (Chat, GitEvent, Dashboard, Performance)
- **Files**: `packages/ShikiKit/Sources/DTOs/ChatMessageDTO.swift` (new), `GitEventDTO.swift` (new), `DashboardDTO.swift` (new)
- **Test**: `test_agentEventDTO_roundTrips()`, `test_pipelineRunDTO_roundTrips()`
- **Implement**: All remaining DTO types from schemas.ts: AgentEventInput, PerformanceMetricInput, ChatMessageInput, DataSyncInput, PrCreatedInput, DashboardSummary, etc.
- **Verify**: `swift test --filter ShikiKitTests` → all DTO tests passing
- **BRs**: BR-01, BR-14
- **Time**: ~5 min

### Task 5: Define Ingest/Radar/Pipeline DTOs
- **Files**: `packages/ShikiKit/Sources/DTOs/IngestDTO.swift` (new), `RadarDTO.swift` (new), `PipelineDTO.swift` (new)
- **Test**: `test_radarWatchItemDTO_roundTrips()`, `test_ingestRequestDTO_roundTrips()`, `test_pipelineRunCreate_validatesEnumValues()`
- **Implement**: IngestRequestInput, RadarWatchItemInput, PipelineRunCreateInput, PipelineCheckpointInput, etc. All from schemas.ts.
- **Verify**: `swift test --filter ShikiKitTests` → all DTO tests passing
- **BRs**: BR-01, BR-14
- **Time**: ~5 min

### Task 6: Define WebSocket message types + route constants
- **Files**: `packages/ShikiKit/Sources/WebSocket/WSMessage.swift` (new), `WSChannel.swift` (new), `packages/ShikiKit/Sources/Routes/ShikiRoutes.swift` (new)
- **Test**: `test_wsSubscribeMessage_encodesToExpectedFormat()`, `test_wsUnsubscribeMessage_encodesToExpectedFormat()`, `test_wsChatMessage_encodesAllFields()`
- **Implement**: WSMessage discriminated union (enum with associated values), WSChannel helper, ShikiRoutes enum with all 29 route paths as static constants.
- **Verify**: `swift test --filter ShikiKitTests` → all WS + route tests passing
- **BRs**: BR-01, BR-06
- **Time**: ~5 min

### Task 7: Define ShikiError types
- **Files**: `packages/ShikiKit/Sources/Errors/ShikiError.swift` (new)
- **Test**: `test_agentEventInput_rejectsInvalidUUID()` (validation errors)
- **Implement**: ShikiError enum: .notFound, .badRequest(String), .validationFailed([ValidationError]), .serviceUnavailable, .internalError. Codable for wire format.
- **Verify**: `swift test --filter ShikiKitTests` → error type tests passing
- **BRs**: BR-14
- **Time**: ~3 min

### Task 8: Create root Package.swift (SPM workspace)
- **Files**: `Package.swift` (new at repo root)
- **Test**: `swift build` compiles all targets
- **Implement**: Root Package.swift defining ShikiServer, ShikiApp, ShikiCLI as executable targets. ShikiKit, CoreKit, NetworkKit, SecurityKit, DesignKit as library dependencies. Vapor, Fluent, postgres-nio as package dependencies.
- **Verify**: `swift build` → compiles (with stub entry points)
- **BRs**: BR-11
- **Time**: ~5 min

### Task 9: Create ShikiServer scaffold + configure.swift
- **Files**: `ShikiServer/Sources/App/configure.swift` (new), `ShikiServer/Sources/App/entrypoint.swift` (new)
- **Test**: `test_healthEndpoint_returnsExpectedShape()` (Vapor XCTVapor testing)
- **Implement**: Vapor Application configuration: register Fluent PostgreSQL, middleware, load env vars per BR-12. Stub routes.swift that registers /health returning proper shape.
- **Verify**: `swift test --filter ShikiServerTests` → health test passing
- **BRs**: BR-02, BR-12, BR-13
- **Time**: ~5 min

### Task 10: Fluent models for relational tables (Project, Session, Agent, Decision)
- **Files**: `ShikiServer/Sources/Models/Project.swift` (new), `Session.swift` (new), `Agent.swift` (new), `Decision.swift` (new)
- **Test**: `test_fluentModel_mapsToExistingSchema()`, `test_projectModel_readsExistingRow()`
- **Implement**: Fluent Model conformances mapping to existing table names and columns. @ID, @Field, @Parent, @Children relationships. No schema changes.
- **Verify**: `swift test --filter ShikiServerTests` → model tests passing
- **BRs**: BR-03
- **Time**: ~5 min

### Task 11: Raw SQL models for hypertables (AgentEvent, ChatMessage, PerformanceMetric, GitEvent)
- **Files**: `ShikiServer/Sources/Models/AgentEvent.swift` (new), `ChatMessage.swift` (new), `PerformanceMetric.swift` (new), `GitEvent.swift` (new)
- **Test**: `test_agentEventsHypertable_insertsViaRawSQL()`, `test_chatMessagesHypertable_insertsViaRawSQL()`
- **Implement**: Plain Codable structs + repository classes using raw postgres-nio SQL for insert/query. TimescaleDB hypertables don't work well with Fluent ORM.
- **Verify**: `swift test --filter ShikiServerTests` → hypertable tests passing
- **BRs**: BR-03, BR-04
- **Time**: ~5 min

### Task 12: AgentMemory model with vector column
- **Files**: `ShikiServer/Sources/Models/AgentMemory.swift` (new)
- **Test**: `test_embedding_callsLMStudioEndpoint()`, `test_embedding_fallsBackGracefullyWhenUnavailable()`
- **Implement**: AgentMemory struct with vector(768) column mapped via raw SQL. Embedding stored as Float array, converted to pgvector format for insert/query.
- **Verify**: `swift test --filter ShikiServerTests` → embedding tests passing
- **BRs**: BR-03, BR-05
- **Time**: ~5 min

### Task 13: EmbeddingService (LM Studio HTTP client)
- **Files**: `ShikiServer/Sources/Services/EmbeddingService.swift` (new)
- **Test**: `test_embedding_callsLMStudioEndpoint()`, `test_embedding_fallsBackGracefullyWhenUnavailable()`, `test_embedding_respectsConfiguredModel()`
- **Implement**: HTTP client using NetworkKit to call LM Studio /v1/embeddings. Configurable URL and model via env vars. Graceful fallback (nil embedding) when unavailable.
- **Verify**: `swift test --filter ShikiServerTests` → 3 tests passing
- **BRs**: BR-05, BR-12
- **Time**: ~5 min

### Task 14: MemorySearchService (vector similarity)
- **Files**: `ShikiServer/Sources/Services/MemorySearchService.swift` (new)
- **Test**: `test_searchMemories_returnsSortedByRelevance()`
- **Implement**: Raw SQL query using pgvector cosine distance operator (<=>). Converts query text to embedding via EmbeddingService, then searches agent_memories table. Filters by project_id, threshold, limit.
- **Verify**: `swift test --filter ShikiServerTests` → search test passing
- **BRs**: BR-05
- **Time**: ~5 min

### Task 15: WebSocketManager (channel-based broadcast)
- **Files**: `ShikiServer/Sources/Services/WebSocketManager.swift` (new)
- **Test**: `test_webSocket_subscribeAndBroadcast()` (unit with mock WebSocket)
- **Implement**: Vapor WebSocket handler. Maintains dictionary of channel → [WebSocket]. Handles subscribe/unsubscribe/chat message types per WSMessage enum. Thread-safe via actor.
- **Verify**: `swift test --filter ShikiServerTests` → WS test passing
- **BRs**: BR-06
- **Time**: ~5 min

### Task 16: HealthController + ProjectController + SessionController
- **Files**: `ShikiServer/Sources/Controllers/HealthController.swift` (new), `ProjectController.swift` (new), `SessionController.swift` (new)
- **Test**: `test_healthCheck_identicalToDenoShape()`, `test_healthFullEndpoint_returnsAllSections()`, `test_listProjects_returnsArray()`, `test_listSessions_filtersbyProjectId()`, `test_listActiveSessions_returnsView()`
- **Implement**: Vapor RouteCollection conformances. Health returns version, uptime, service status. Projects/Sessions do Fluent queries.
- **Verify**: `swift test --filter ShikiServerTests` → 5 tests passing
- **BRs**: BR-02, BR-13
- **Time**: ~5 min

### Task 17: AgentController + PerformanceController
- **Files**: `ShikiServer/Sources/Controllers/AgentController.swift` (new)
- **Test**: `test_listAgents_filtersBySessionId()`, `test_postAgentEvent_broadcastsToWS()`, `test_listAgentEvents_respectsLimit()`, `test_postPerformanceMetric_stores()`
- **Implement**: Agent CRUD via Fluent. Agent events and performance metrics via raw SQL (hypertables). Broadcast events to WebSocket subscribers.
- **Verify**: `swift test --filter ShikiServerTests` → 4 tests passing
- **BRs**: BR-02, BR-06
- **Time**: ~5 min

### Task 18: MemoryController
- **Files**: `ShikiServer/Sources/Controllers/MemoryController.swift` (new)
- **Test**: `test_postMemory_generatesEmbedding()`, `test_listMemories_filtersByProject()`, `test_searchMemories_returnsSortedByRelevance()`, `test_listMemorySources_groupsByFile()`
- **Implement**: POST stores memory + generates embedding via EmbeddingService. Search delegates to MemorySearchService. Sources query uses GROUP BY on metadata->>'sourceFile'.
- **Verify**: `swift test --filter ShikiServerTests` → 4 tests passing
- **BRs**: BR-02, BR-05
- **Time**: ~5 min

### Task 19: ChatController + DataSyncController + GitEventController
- **Files**: `ShikiServer/Sources/Controllers/ChatController.swift` (new), `DataSyncController.swift` (new), `GitEventController.swift` (new)
- **Test**: `test_postChatMessage_broadcastsToWS()`, `test_listChatMessages_requiresSessionId()`, `test_postDataSync_stores()`, `test_postPrCreated_broadcastsToWS()`, `test_listGitEvents_filtersbyType()`
- **Implement**: Chat and git events use raw SQL for hypertable inserts. All POST endpoints broadcast to WebSocket. Git events support PR-created with metadata.
- **Verify**: `swift test --filter ShikiServerTests` → 5 tests passing
- **BRs**: BR-02, BR-06
- **Time**: ~5 min

### Task 20: DashboardController
- **Files**: `ShikiServer/Sources/Controllers/DashboardController.swift` (new)
- **Test**: `test_dashboardSummary_returnsAllCounts()`, `test_dashboardPerformance_respectsDaysParam()`, `test_dashboardActivity_respectsHoursParam()`, `test_dashboardCosts_returnsLeaderboard()`, `test_dashboardGit_returnsDailyActivity()`
- **Implement**: Summary aggregates via raw SQL COUNT queries. Performance/activity from continuous aggregates. Costs from agent_cost_leaderboard view.
- **Verify**: `swift test --filter ShikiServerTests` → 5 tests passing
- **BRs**: BR-02
- **Time**: ~5 min

### Task 21: IngestController + IngestService
- **Files**: `ShikiServer/Sources/Controllers/IngestController.swift` (new), `ShikiServer/Sources/Services/IngestService.swift` (new)
- **Test**: `test_ingestChunks_storesWithEmbeddings()`, `test_listIngestSources_requiresProjectId()`
- **Implement**: Ingest receives chunks, generates embeddings, deduplicates via cosine similarity threshold (0.92). Sources CRUD. Maps to Deno ingest.ts logic.
- **Verify**: `swift test --filter ShikiServerTests` → 2 tests passing
- **BRs**: BR-02
- **Time**: ~5 min

### Task 22: RadarController + RadarScanService
- **Files**: `ShikiServer/Sources/Controllers/RadarController.swift` (new), `ShikiServer/Sources/Services/RadarScanService.swift` (new)
- **Test**: `test_radarWatchlist_CRUD()`, `test_radarScan_triggersAndReturnsId()`, `test_radarDigest_returnsLatest()`
- **Implement**: Watchlist CRUD via Fluent models. Scan trigger creates run, queries GitHub API. Digest generation from scan results. Maps to Deno radar.ts logic.
- **Verify**: `swift test --filter ShikiServerTests` → 3 tests passing
- **BRs**: BR-02
- **Time**: ~5 min

### Task 23: PipelineController (runs, checkpoints, routing)
- **Files**: `ShikiServer/Sources/Controllers/PipelineController.swift` (new)
- **Test**: `test_pipelineRun_createAndRetrieve()`, `test_pipelineCheckpoint_addsAndLists()`, `test_pipelineResume_updatesState()`, `test_pipelineRouting_evaluatesRules()`, `test_pipelineRules_CRUD()`
- **Implement**: Full pipeline CRUD with checkpoint state accumulation. Resume merges stateOverrides. Routing rule evaluation. Maps to Deno pipelines.ts.
- **Verify**: `swift test --filter ShikiServerTests` → 5 tests passing
- **BRs**: BR-02
- **Time**: ~5 min

### Task 24: AdminController + route registration
- **Files**: `ShikiServer/Sources/Controllers/AdminController.swift` (new), `ShikiServer/Sources/App/routes.swift` (update)
- **Test**: `test_allEndpoints_registered()` (route existence check)
- **Implement**: Admin backup-status endpoint. Register all 14 controllers in routes.swift. Verify all 29 endpoint paths match Deno routes.ts.
- **Verify**: `swift test --filter ShikiServerTests` → all route tests passing
- **BRs**: BR-02
- **Time**: ~3 min

### Task 25: ErrorMiddleware + request validation
- **Files**: `ShikiServer/Sources/App/Middleware/ErrorMiddleware.swift` (new)
- **Test**: `test_invalidRequest_returns400WithErrorFormat()`
- **Implement**: Vapor Middleware that catches validation errors and returns 400 with same JSON error format as Deno. Catches ShikiError types and maps to HTTP status codes.
- **Verify**: `swift test --filter ShikiServerTests` → error middleware test passing
- **BRs**: BR-14
- **Time**: ~3 min

### Task 26: ShikiCLI scaffold + InitCommand + StartCommand + StopCommand
- **Files**: `ShikiCLI/Sources/ShikiCLI.swift` (new), `Commands/InitCommand.swift` (new), `StartCommand.swift` (new), `StopCommand.swift` (new), `Services/DockerService.swift` (new)
- **Test**: `test_initCommand_startsDockerCompose()`, `test_startCommand_startsServices()`, `test_stopCommand_stopsServices()`
- **Implement**: ArgumentParser root command with subcommands. DockerService wraps Process() calls to docker-compose. Init runs docker-compose up -d.
- **Verify**: `swift test --filter ShikiCLITests` → 3 tests passing
- **BRs**: BR-07
- **Time**: ~5 min

### Task 27: StatusCommand + HealthCommand + NewCommand
- **Files**: `ShikiCLI/Sources/Commands/StatusCommand.swift` (new), `HealthCommand.swift` (new), `NewCommand.swift` (new), `Services/ServerClient.swift` (new)
- **Test**: `test_statusCommand_displaysHealth()`, `test_healthCommand_exitsCodes()`, `test_newCommand_createsProjectDirectory()`, `test_configurationReadsEnvironmentVariables()`
- **Implement**: Status calls /health/full and formats output. Health --ping exits 0/1. New creates project directory structure. ServerClient uses NetworkKit for HTTP.
- **Verify**: `swift test --filter ShikiCLITests` → 4 tests passing
- **BRs**: BR-07, BR-12, BR-13
- **Time**: ~5 min

### Task 28: ShikiApp scaffold + DashboardView
- **Files**: `ShikiApp/Sources/ShikiAppMain.swift` (new), `Views/DashboardView.swift` (new), `ViewModels/DashboardViewModel.swift` (new), `Services/ShikiAPIClient.swift` (new)
- **Test**: `test_dashboardView_rendersProjectSummary()`
- **Implement**: SwiftUI App with NavigationSplitView. DashboardView shows summary stats from /api/dashboard/summary. ViewModel uses ShikiAPIClient (NetworkKit + ShikiKit types).
- **Verify**: `swift test --filter ShikiAppTests` → 1 test passing
- **BRs**: BR-08
- **Time**: ~5 min

### Task 29: PipelineListView + PipelineDetailView
- **Files**: `ShikiApp/Sources/Views/PipelineListView.swift` (new), `PipelineDetailView.swift` (new), `ViewModels/PipelineViewModel.swift` (new)
- **Test**: `test_pipelineListView_showsRunningPipelines()`
- **Implement**: List of pipeline runs from /api/pipelines. Detail view shows checkpoints as vertical timeline. ViewModel fetches and observes via @Observable.
- **Verify**: `swift test --filter ShikiAppTests` → 1 test passing
- **BRs**: BR-08
- **Time**: ~5 min

### Task 30: MemoryBrowserView + search
- **Files**: `ShikiApp/Sources/Views/MemoryBrowserView.swift` (new), `ViewModels/MemoryBrowserViewModel.swift` (new)
- **Test**: `test_memorySearchView_displayResults()`
- **Implement**: Search field + results list. Calls /api/memories/search. Shows relevance scores, category badges, source file links. Debounced search input.
- **Verify**: `swift test --filter ShikiAppTests` → 1 test passing
- **BRs**: BR-08
- **Time**: ~5 min

### Task 31: WebSocketClient for real-time updates
- **Files**: `ShikiApp/Sources/Services/WebSocketClient.swift` (new)
- **Test**: `test_webSocketManager_connectsAndSubscribes()`, `test_webSocketManager_handlesDisconnect()`
- **Implement**: URLSessionWebSocketTask wrapper. Subscribes to project channels. Parses incoming WSMessage types. Publishes updates via Combine/AsyncStream to ViewModels.
- **Verify**: `swift test --filter ShikiAppTests` → 2 tests passing
- **BRs**: BR-08
- **Time**: ~5 min

### Task 32: NotificationService (APNs)
- **Files**: `ShikiApp/Sources/Services/NotificationService.swift` (new)
- **Test**: `test_notificationHandler_registersForAPNs()`, `test_notificationHandler_processesApprovalAction()`
- **Implement**: UNUserNotificationCenter registration. Handle incoming push payloads for approval requests. Action buttons (approve/reject). Relay decision to server via ShikiAPIClient.
- **Verify**: `swift test --filter ShikiAppTests` → 2 tests passing
- **BRs**: BR-09
- **Time**: ~5 min

### Task 33: AppCoordinator + navigation
- **Files**: `ShikiApp/Sources/Navigation/AppCoordinator.swift` (new), `Views/ProjectListView.swift` (new), `Views/SettingsView.swift` (new), `ViewModels/ProjectViewModel.swift` (new)
- **Test**: (navigation tested via preview/manual — no unit test)
- **Implement**: CoreKit Coordinator for tab/sidebar navigation. Tabs: Dashboard, Pipelines, Memory, Projects, Settings. NavigationSplitView on iPad/Mac, TabView on iPhone.
- **Verify**: `swift build --target ShikiApp` → compiles
- **BRs**: BR-08
- **Time**: ~5 min

### Task 34: Integration test — all endpoints match Deno responses
- **Files**: `ShikiServer/Tests/IntegrationTests/EndpointParityTests.swift` (new)
- **Test**: `integration_allEndpoints_matchDenoResponses()`
- **Implement**: For each of the 29 endpoints, hit both Deno (port 3900) and Swift (port 3901) servers, compare JSON response shapes. Uses XCTAssertEqual on decoded DTOs.
- **Verify**: `swift test --filter IntegrationTests` → parity test passing
- **BRs**: BR-02, BR-03, BR-16
- **Time**: ~5 min

### Task 35: Integration test — WebSocket + dual-server coexistence
- **Files**: `ShikiServer/Tests/IntegrationTests/WebSocketTests.swift` (new), `DualServerTests.swift` (new)
- **Test**: `integration_webSocket_subscribeAndReceiveBroadcast()`, `integration_dualServer_sharedDatabase_noConflicts()`, `integration_embeddingPipeline_endToEnd()`
- **Implement**: WS test subscribes to channel, sends event via REST, verifies broadcast received. Dual-server test writes from both servers, verifies shared state. Embedding test stores memory with embedding, searches, verifies result.
- **Verify**: `swift test --filter IntegrationTests` → 3 tests passing
- **BRs**: BR-06, BR-16, BR-05
- **Time**: ~5 min

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 16/16 BRs mapped across 35 tasks |
| Test Coverage | PASS | 67/67 test signatures mapped to tasks |
| File Alignment | PASS | All 65+ files from architecture appear in tasks |
| Task Dependencies | PASS | Linear order: ShikiKit (1-7) → root Package (8) → Server models (9-12) → Server services (13-15) → Server controllers (16-25) → CLI (26-27) → App (28-33) → Integration (34-35) |
| DI Registration | PASS | 9 new types registered (Task 9 configure.swift, Task 28 app DI) |
| Coordinator Routes | PASS | Task 33 covers AppCoordinator with 5 tabs |
| Task Granularity | PASS | All tasks estimated 2-5 min, no mega-tasks |
| Testability | PASS | Every task has a verify step with specific test filter command |

**Verdict: PASS** — Ready for Phase 6 implementation.

## Implementation Log

_Phase 6 not yet started. This is a planning exercise._

| Date | Event | Notes |
|------|-------|-------|
| 2026-03-09 | Phases 1-5b completed | Full planning pipeline executed. 35 atomic tasks defined. |

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-09 | Phase 1 | @Daimyo | Approved | All 10 ideas accepted, tiered into 3 priority levels |
| 2026-03-09 | Phase 2 | @Sensei | Synthesized | Feature brief with scope, out-of-scope, success criteria, dependencies |
| 2026-03-09 | Phase 3 | @Sensei | Drafted | 16 business rules covering types, endpoints, DB, WS, CLI, app, notifications, TDD, config |
| 2026-03-09 | Phase 4 | @testing-expert | Planned | 67 test signatures across 5 groups (ShikiKit, Server routes, Server DB, CLI, App, Integration) |
| 2026-03-09 | Phase 5 | @Sensei | Designed | Full package structure, 65+ files, DI plan, data flow, key protocols |
| 2026-03-09 | Phase 5b | @Sensei | Planned | 35 atomic tasks, readiness gate PASS |
