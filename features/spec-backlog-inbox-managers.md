# Spec: BacklogManager + InboxManager

> Implementation spec for the two core list managers in ShikiCore.
> Author: @Sensei | Date: 2026-03-23 | Status: Ready for review

---

## Table of Contents

1. [Architecture Decision: Backlog Storage](#1-architecture-decision-backlog-storage)
2. [BacklogManager](#2-backlogmanager)
3. [InboxManager](#3-inboxmanager)
4. [Shared Infrastructure](#4-shared-infrastructure)
5. [Implementation Waves](#5-implementation-waves)
6. [Test Plan](#6-test-plan)
7. [LOC Estimates](#7-loc-estimates)

---

## 1. Architecture Decision: Backlog Storage

**Decision: New `backlog_items` table. Do NOT reuse `task_queue`.**

Rationale:

- `task_queue` is an execution artifact — it tracks work claimed by agents, with `claimed_by`, `claimed_at`, `blocking_question_ids`, `pipeline_run_id`. Backlog items have none of these concerns.
- `task_queue.status` enum (`pending → claimed → running → blocked → completed → failed → cancelled`) is an execution lifecycle. Backlog status (`raw → enriched → ready → deferred → killed`) is a curation lifecycle. Mixing them in one column with compound CHECK constraints creates a semantic mess.
- `task_queue.source = 'backlog'` was a forward reference but doesn't model the backlog lifecycle — it marks where a task *came from*, not where it *is*.
- Backlog items have fields task_queue lacks: `enrichment_notes`, `kill_reason`, `sort_order`, `source_type` (push/flsh/conversation/manual), `promoted_to_task_id` (foreign key linking to task_queue when promoted).
- Clean separation means backlog can evolve independently (split, merge, tagging) without polluting the execution model.

**Promotion bridge:** When a backlog item reaches `ready` status and the user promotes it, BacklogManager creates a `task_queue` row with `source = 'backlog'` and writes `promoted_to_task_id` back to the backlog item. This is a one-way link — the task does not reference the backlog item (task_queue schema unchanged).

---

## 2. BacklogManager

### 2.1 DB Schema — Migration `007_backlog_items.sql`

```sql
-- ═══════════════════════════════════════════════════════════════════
-- BACKLOG ITEMS — idea curation before execution
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE backlog_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          UUID REFERENCES companies(id) ON DELETE CASCADE,
    -- company_id is nullable: cross-company or workspace-level ideas
    title               TEXT NOT NULL,
    description         TEXT,
    source_type         TEXT NOT NULL DEFAULT 'manual'
                        CHECK (source_type IN ('manual', 'push', 'flsh', 'conversation', 'agent')),
    source_ref          TEXT,
    -- source_ref: free-form origin trace ("session:abc123", "flsh:voice-note-42", "push:ntfy-2026-03-23")
    status              TEXT NOT NULL DEFAULT 'raw'
                        CHECK (status IN ('raw', 'enriched', 'ready', 'deferred', 'killed')),
    priority            SMALLINT NOT NULL DEFAULT 50
                        CHECK (priority >= 0 AND priority <= 99),
    sort_order          INTEGER NOT NULL DEFAULT 0,
    -- sort_order: user-pinned ordering. 0 = auto-sorted by composite score.
    -- Negative values = pinned to top (lower = higher). Positive = pinned to bottom.
    enrichment_notes    TEXT,
    -- enrichment_notes: context added during enrich action (links, references, constraints)
    kill_reason         TEXT,
    tags                TEXT[] NOT NULL DEFAULT '{}',
    parent_id           UUID REFERENCES backlog_items(id),
    -- parent_id: for split items — tracks lineage
    promoted_to_task_id UUID,
    -- promoted_to_task_id: set when item is promoted to task_queue. Not a FK
    -- to avoid cross-table coupling; just a tracing reference.
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata            JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_backlog_company ON backlog_items(company_id) WHERE company_id IS NOT NULL;
CREATE INDEX idx_backlog_status ON backlog_items(status);
CREATE INDEX idx_backlog_active ON backlog_items(sort_order, priority, created_at)
    WHERE status IN ('raw', 'enriched', 'ready');
CREATE INDEX idx_backlog_parent ON backlog_items(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX idx_backlog_tags ON backlog_items USING GIN(tags);

-- Trigger: auto-update updated_at
CREATE TRIGGER trg_backlog_items_updated
    BEFORE UPDATE ON backlog_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
-- NOTE: update_updated_at() already exists from migration 004_orchestrator.sql
```

### 2.2 State Machine

```
                ┌──────────┐
      add ────→ │   raw    │
                └────┬─────┘
                     │ enrich (add context/notes)
                     ▼
                ┌──────────┐
                │ enriched │◄─── un-defer
                └────┬─────┘         ▲
                     │ promote       │
                     ▼               │
                ┌──────────┐    ┌──────────┐
                │  ready   │    │ deferred │
                └────┬─────┘    └──────────┘
                     │               ▲
                     │               │ defer (from raw/enriched/ready)
                     │               │
                     ▼               │
              ┌─────────────┐        │
              │ task_queue   │   ┌──────────┐
              │ (promoted)   │   │  killed  │
              └─────────────┘   └──────────┘
                                     ▲
                                     │ kill (from any state except killed)
```

**Transitions:**
| From | To | Action | Side effects |
|---|---|---|---|
| (new) | `raw` | `add` | Insert row |
| `raw` | `enriched` | `enrich` | Write `enrichment_notes` |
| `enriched` | `ready` | `promote` | None — item is now eligible for decide/spec |
| `raw` | `ready` | `promote` | Allowed shortcut for obvious items |
| `ready` | (task_queue) | `dispatch` | Create task_queue row, write `promoted_to_task_id` |
| any except `killed` | `deferred` | `defer` | Parking state, preserves all fields |
| `deferred` | previous status | `un-defer` | Restore to `enriched` (safe default) |
| any except `killed` | `killed` | `kill` | Write `kill_reason`, soft delete |

**Invalid transitions:** `killed` to anything (terminal state). `ready` back to `raw` (enrich is forward-only).

### 2.3 Backend Zod Schemas — `schemas.ts` additions

```typescript
// --- Backlog ---
export const BacklogCreateSchema = z.object({
  companyId: z.string().uuid().optional(),
  title: z.string().min(1).max(500),
  description: z.string().max(10000).optional(),
  sourceType: z.enum(["manual", "push", "flsh", "conversation", "agent"]).optional().default("manual"),
  sourceRef: z.string().max(500).optional(),
  priority: z.number().int().min(0).max(99).optional().default(50),
  tags: z.array(z.string().max(50)).optional().default([]),
  parentId: z.string().uuid().optional(),
  metadata: z.record(z.unknown()).optional().default({}),
});

export const BacklogUpdateSchema = z.object({
  status: z.enum(["raw", "enriched", "ready", "deferred", "killed"]).optional(),
  priority: z.number().int().min(0).max(99).optional(),
  sortOrder: z.number().int().optional(),
  enrichmentNotes: z.string().max(10000).optional(),
  killReason: z.string().max(2000).optional(),
  tags: z.array(z.string().max(50)).optional(),
  description: z.string().max(10000).optional(),
  metadata: z.record(z.unknown()).optional(),
});

export const BacklogReorderSchema = z.object({
  items: z.array(z.object({
    id: z.string().uuid(),
    sortOrder: z.number().int(),
  })).min(1).max(100),
});

export const BacklogEnrichSchema = z.object({
  enrichmentNotes: z.string().min(1).max(10000),
  tags: z.array(z.string().max(50)).optional(),
  description: z.string().max(10000).optional(),
});

export const BacklogPromoteSchema = z.object({
  companyId: z.string().uuid(),
  // companyId required at promotion time — workspace-level items must be assigned
  taskDescription: z.string().max(10000).optional(),
  taskPriority: z.number().int().min(0).max(99).optional(),
});
```

### 2.4 API Endpoints — `routes.ts` additions

| Method | Path | Schema | Description |
|--------|------|--------|-------------|
| `GET` | `/api/backlog` | query: `?status=`, `?company_id=`, `?tags=`, `?sort=priority\|age\|manual` | List backlog items (active by default: `raw`, `enriched`, `ready`) |
| `POST` | `/api/backlog` | `BacklogCreateSchema` | Add new backlog item |
| `GET` | `/api/backlog/:id` | — | Get single item |
| `PATCH` | `/api/backlog/:id` | `BacklogUpdateSchema` | Update status, priority, description, tags |
| `POST` | `/api/backlog/:id/enrich` | `BacklogEnrichSchema` | Add enrichment context (transitions `raw` to `enriched`) |
| `POST` | `/api/backlog/:id/promote` | `BacklogPromoteSchema` | Promote `ready` item to task_queue. Returns the created task. |
| `POST` | `/api/backlog/:id/kill` | `{ killReason: string }` | Kill with reason (terminal) |
| `POST` | `/api/backlog/reorder` | `BacklogReorderSchema` | Batch update sort_order for pinned items |
| `GET` | `/api/backlog/count` | query: `?status=`, `?company_id=` | Count items by filter (for `--count` flag) |

**Route registration order in `routes.ts`:** Place `/api/backlog/count` and `/api/backlog/reorder` BEFORE the `/api/backlog/:id` wildcard match, same pattern as `decision-queue/pending`.

### 2.5 BackendClient Swift Additions — `BackendClientProtocol.swift`

```swift
// --- Backlog ---
func listBacklogItems(
    status: BacklogItem.Status?,
    companyId: String?,
    tags: [String]?,
    sort: BacklogSort?
) async throws -> [BacklogItem]

func getBacklogItem(id: String) async throws -> BacklogItem

func createBacklogItem(
    title: String,
    description: String?,
    companyId: String?,
    sourceType: BacklogItem.SourceType,
    sourceRef: String?,
    priority: Int?,
    tags: [String]
) async throws -> BacklogItem

func updateBacklogItem(
    id: String,
    status: BacklogItem.Status?,
    priority: Int?,
    sortOrder: Int?,
    tags: [String]?,
    description: String?
) async throws -> BacklogItem

func enrichBacklogItem(
    id: String,
    notes: String,
    tags: [String]?,
    description: String?
) async throws -> BacklogItem

func promoteBacklogItem(
    id: String,
    companyId: String,
    taskDescription: String?,
    taskPriority: Int?
) async throws -> OrchestratorTask
// Returns the created task, not the backlog item

func killBacklogItem(id: String, reason: String) async throws -> BacklogItem

func reorderBacklogItems(_ items: [(id: String, sortOrder: Int)]) async throws

func getBacklogCount(status: BacklogItem.Status?, companyId: String?) async throws -> Int
```

Default parameter extensions:
```swift
public extension BackendClientProtocol {
    func listBacklogItems() async throws -> [BacklogItem] {
        try await listBacklogItems(status: nil, companyId: nil, tags: nil, sort: nil)
    }
    func getBacklogCount() async throws -> Int {
        try await getBacklogCount(status: nil, companyId: nil)
    }
}
```

### 2.6 Swift Model — `BacklogItem.swift`

```swift
public struct BacklogItem: Codable, Sendable, Identifiable {
    public let id: String
    public let companyId: String?
    public let title: String
    public let description: String?
    public let sourceType: SourceType
    public let sourceRef: String?
    public let status: Status
    public let priority: Int
    public let sortOrder: Int
    public let enrichmentNotes: String?
    public let killReason: String?
    public let tags: [String]
    public let parentId: String?
    public let promotedToTaskId: String?
    public let createdAt: String
    public let updatedAt: String
    public let metadata: [String: AnyCodable]

    public enum Status: String, Codable, Sendable, CaseIterable {
        case raw, enriched, ready, deferred, killed
    }

    public enum SourceType: String, Codable, Sendable {
        case manual, push, flsh, conversation, agent
    }

    // CodingKeys: snake_case mapping (same pattern as Decision/OrchestratorTask)
}

public enum BacklogSort: String, Sendable {
    case priority, age, manual
}
```

### 2.7 CLI — `BacklogCommand.swift`

```
shikki backlog                         # Interactive ListReviewer (active items)
shikki backlog add "idea text"         # Quick add (raw status, manual source)
shikki backlog add "idea" --company maya --priority 10 --tags "perf,ux"
shikki backlog --status ready          # Filter by status
shikki backlog --company maya          # Filter by company
shikki backlog --killed                # Show killed items (archaeology)
shikki backlog --json                  # Pipe-friendly JSON output
shikki backlog --count                 # Just the number
shikki backlog --count --status raw    # Count raw items
```

**ArgumentParser structure:**
```
BacklogCommand (ParsableCommand)
├── BacklogListSubcommand (default)  — calls ListReviewer with backlog data source
├── BacklogAddSubcommand             — quick add, returns created item
└── (flags: --json, --count, --status, --company, --tags, --killed, --sort)
```

**ListReviewer actions for backlog context:**
| Key | Action | Transition |
|-----|--------|------------|
| `e` | Enrich | Prompts for notes, transitions to `enriched` |
| `p` | Promote | Transitions to `ready` (or straight to task_queue if `--yolo`) |
| `k` | Kill | Prompts for reason, transitions to `killed` |
| `d` | Defer | Transitions to `deferred` |
| `r` | Reorder | Move item up/down in sort order |
| `s` | Split | Create child items (prompts for sub-titles) |
| `?` | Details | Show full description + enrichment notes + metadata |

### 2.8 Backlog-to-Decide Bridge

When a backlog item reaches `ready`:

1. It appears in `shikki decide` as eligible for spec — the decide stage pulls items from `backlog_items WHERE status = 'ready'` as its input list.
2. The decide stage may create `decision_queue` rows (shadows/unknowns) linked via `metadata.backlog_item_id`.
3. Once all blocking decisions for an item are answered, the item is eligible for `shikki spec`.
4. Promotion to `task_queue` happens when the spec is approved and enters the `run` stage — not at the decide gate.

**Query for decide input:**
```sql
SELECT bi.*, c.slug AS company_slug
FROM backlog_items bi
LEFT JOIN companies c ON c.id = bi.company_id
WHERE bi.status = 'ready'
  AND bi.promoted_to_task_id IS NULL
ORDER BY bi.sort_order, bi.priority, bi.created_at;
```

---

## 3. InboxManager

### 3.1 Architecture Decision: No `inbox_items` Table

The inbox is a **virtual aggregation** — not a persisted table. It reads from multiple sources and presents them as a unified list. Persisting would create sync problems (stale PR status, ghost decisions).

**What the inbox reads:**

| Source | Table/API | Filter | Type tag |
|--------|-----------|--------|----------|
| GitHub PRs | `gh pr list --json` (shell-out) | open, review-requested, or created by shikki agents | `pr` |
| Pending decisions | `decision_queue` | `answered = FALSE` | `decision` |
| Specs awaiting review | `backlog_items` + local `features/*.md` scan | `status = 'ready'` + has associated spec file | `spec` |
| Completed agent tasks | `task_queue` | `status = 'completed'` + not yet reviewed (metadata flag) | `task` |
| Ship gate results | `pipeline_runs` | `pipeline_type = 'dispatch'` + `status IN ('completed', 'failed')` + not yet reviewed | `gate` |

**What gets persisted:** Review progress. The `~/.config/shiki/list-progress.json` file tracks which inbox items have been reviewed/validated/deferred. This is the ListReviewer's progress persistence (feature #6 from shikki-flow-v1.md), not a DB table.

### 3.2 Unified InboxItem Model — `InboxItem.swift`

```swift
public struct InboxItem: Sendable, Identifiable {
    public let id: String
    // id format: "{type}:{source_id}" — e.g. "pr:42", "decision:abc-123", "spec:p1-group-a"
    public let type: ItemType
    public let title: String
    public let subtitle: String?
    public let status: ReviewStatus
    public let age: TimeInterval
    // age: seconds since item became actionable
    public let companySlug: String?
    public let urgencyScore: Int
    // urgencyScore: 0-100 composite (age weight + priority weight + blocking impact)
    public let metadata: [String: String]
    // metadata: type-specific fields (pr: number/branch/author, decision: tier/question, etc.)

    public enum ItemType: String, Sendable, CaseIterable {
        case pr, decision, spec, task, gate
    }

    public enum ReviewStatus: String, Sendable {
        case pending       // not yet looked at
        case inReview      // opened but not validated
        case validated     // approved/merged/answered
        case corrected     // sent back with corrections
        case deferred      // pushed to later
    }
}
```

**urgencyScore formula:**
```
urgencyScore = ageWeight + priorityWeight + blockingWeight

ageWeight (0-40):
  - < 1 hour:  0
  - 1-4 hours: 10
  - 4-12 hours: 20
  - 12-24 hours: 30
  - > 24 hours: 40

priorityWeight (0-30):
  - PR: based on files changed (1-5: 5, 6-20: 15, 20+: 30)
  - Decision: tier 1=30, tier 2=20, tier 3=10
  - Spec: based on wave count (1: 10, 2-3: 20, 4+: 30)
  - Task: based on task priority (inverse: priority 0=30, 50=15, 99=0)
  - Gate: failed=30, completed=10

blockingWeight (0-30):
  - Blocks other items: 30
  - Blocks nothing: 0
  - Determination: decision with task_id where task is blocked = blocking.
    PR on branch that other PRs depend on = blocking. Spec that blocks run = blocking.
```

### 3.3 Data Source Adapters

Each source is an `InboxDataSource` protocol conformance:

```swift
public protocol InboxDataSource: Sendable {
    var sourceType: InboxItem.ItemType { get }
    func fetch(filters: InboxFilters) async throws -> [InboxItem]
}

public struct InboxFilters: Sendable {
    public let companySlug: String?
    public let types: Set<InboxItem.ItemType>?
    public let status: InboxItem.ReviewStatus?
}
```

**Adapters (5 total):**

1. **PRInboxSource** — shells out to `gh pr list --json number,title,createdAt,headRefName,author,labels,reviewRequests,additions,deletions --limit 50`. Maps each PR to `InboxItem`. Company detection: parse branch name prefix (e.g. `maya/feature-x` = maya) or label.

2. **DecisionInboxSource** — calls `BackendClient.getPendingDecisions()`. Maps `Decision` to `InboxItem`. Company from `companySlug` join field.

3. **SpecInboxSource** — calls `BackendClient.listBacklogItems(status: .ready)` + scans `features/*.md` for associated spec files. An item with a spec file = type `spec`. An item without = still in backlog, not in inbox.

4. **TaskInboxSource** — calls `BackendClient.listTasks(companyId:status:)` with `status = "completed"`. Filters to tasks where `metadata.reviewed != true`. Company from task's companyId.

5. **GateInboxSource** — calls `BackendClient.listPipelineRuns()` with recent completed/failed runs. Filters to runs where `metadata.reviewed != true`.

### 3.4 Backend API Additions

The inbox itself needs NO new backend endpoints — it aggregates existing ones client-side. However, two additions support inbox workflows:

| Method | Path | Schema | Description |
|--------|------|--------|-------------|
| `PATCH` | `/api/task-queue/:id` | `TaskUpdateSchema` (extended) | Add `metadata.reviewed = true` flag via existing PATCH |
| `PATCH` | `/api/pipelines/:id` | `PipelineRunUpdateSchema` | Add `metadata.reviewed = true` flag via existing PATCH |

**No schema changes needed** — both already accept arbitrary `metadata` JSONB updates.

One new endpoint for inbox count (avoids fetching all data just to count):

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/inbox/count` | Server-side aggregate count: pending decisions + completed-unreviewed tasks + failed pipelines. Does NOT include PRs (that's a `gh` call). Returns `{ decisions: N, tasks: N, gates: N, total: N }` |

**Query for `/api/inbox/count`:**
```sql
SELECT
  (SELECT COUNT(*) FROM decision_queue WHERE answered = FALSE) AS decisions,
  (SELECT COUNT(*) FROM task_queue WHERE status = 'completed'
    AND (metadata->>'reviewed')::boolean IS NOT TRUE) AS tasks,
  (SELECT COUNT(*) FROM pipeline_runs WHERE status IN ('completed', 'failed')
    AND (metadata->>'reviewed')::boolean IS NOT TRUE
    AND created_at > NOW() - INTERVAL '7 days') AS gates;
```

### 3.5 BackendClient Swift Additions for Inbox

```swift
// Only one new method — the inbox count endpoint
func getInboxCount() async throws -> InboxCount

// Model:
public struct InboxCount: Codable, Sendable {
    public let decisions: Int
    public let tasks: Int
    public let gates: Int
    public let total: Int
}
```

### 3.6 Inbox-to-Review Integration

When the user selects a PR item in the inbox ListReviewer and presses `Enter` or `o` (open):

1. InboxManager extracts the PR number from `InboxItem.id` ("pr:42" -> 42).
2. Invokes `ReviewCommand.run(prNumber: 42)` programmatically — the existing `shikki review` code path.
3. On return from review (approve/correct), InboxManager marks the item's `ReviewStatus` in progress persistence.

**Pipe integration:** `shikki inbox --prs --json | shikki review --stdin` — review command accepts PR numbers from stdin pipe.

### 3.7 Inbox-to-Decide Integration

When the user selects a decision item and presses `Enter` or `o`:

1. InboxManager extracts the decision ID from `InboxItem.id` ("decision:abc-123").
2. Invokes `DecideCommand.run(decisionId: "abc-123")` — the existing decide flow.
3. On return (answered/deferred), InboxManager updates progress.

### 3.8 CLI — `InboxCommand.swift`

```
shikki inbox                           # Interactive ListReviewer (all pending items)
shikki inbox --prs                     # PRs only
shikki inbox --decisions               # Decisions only
shikki inbox --specs                   # Specs awaiting review only
shikki inbox --tasks                   # Completed tasks only
shikki inbox --gates                   # Ship gate results only
shikki inbox --company maya            # Filter by company
shikki inbox --count                   # Just the total number
shikki inbox --count --prs             # PR count only
shikki inbox --json                    # Pipe-friendly JSON output
shikki inbox --sort urgency|age|type   # Sort override (default: urgency)
```

**ArgumentParser structure:**
```
InboxCommand (ParsableCommand)
├── (default: ListReviewer with all sources)
└── (flags: --prs, --decisions, --specs, --tasks, --gates,
     --company, --count, --json, --sort)
```

**ListReviewer actions for inbox context:**
| Key | Action | Effect |
|-----|--------|--------|
| `o` / `Enter` | Open | Route to type-specific handler (review for PR, decide for decision, etc.) |
| `v` | Validate | Mark as validated (approve PR, acknowledge task, etc.) |
| `c` | Correct | Send correction — prompts for feedback text, routes to orchestrator |
| `d` | Defer | Push to later — removed from active list, preserved in progress file |
| `?` | Details | Show full context (PR diff stats, decision options, spec summary) |
| `/` | Filter | Inline fuzzy search (v1.1 feature, stubbed in v1) |

---

## 4. Shared Infrastructure

### 4.1 InboxManager as Coordinator

```swift
public final class InboxManager: Sendable {
    private let sources: [InboxDataSource]
    private let progressStore: ListProgressStore
    private let client: BackendClientProtocol

    public init(
        client: BackendClientProtocol,
        sources: [InboxDataSource]? = nil,
        progressStore: ListProgressStore? = nil
    )

    /// Fetch all inbox items, sorted by urgency score descending
    public func fetchAll(filters: InboxFilters) async throws -> [InboxItem]

    /// Quick count without full data fetch (uses /api/inbox/count + gh pr list --json | jq length)
    public func count(filters: InboxFilters) async throws -> InboxCount

    /// Mark item as reviewed in progress store
    public func markReviewed(_ itemId: String) async

    /// Get unreviewed count from progress store
    public func unreviewedCount(from items: [InboxItem]) -> Int
}
```

### 4.2 BacklogManager as Coordinator

```swift
public final class BacklogManager: Sendable {
    private let client: BackendClientProtocol
    private let progressStore: ListProgressStore

    public init(client: BackendClientProtocol, progressStore: ListProgressStore? = nil)

    /// List active backlog items (raw + enriched + ready)
    public func listActive(companyId: String?, sort: BacklogSort?) async throws -> [BacklogItem]

    /// Quick add from CLI
    public func add(title: String, companyId: String?, sourceType: BacklogItem.SourceType,
                    tags: [String]) async throws -> BacklogItem

    /// Enrich with context
    public func enrich(id: String, notes: String, tags: [String]?) async throws -> BacklogItem

    /// Promote to ready (or directly to task_queue with dispatch flag)
    public func promote(id: String, companyId: String) async throws -> BacklogItem

    /// Promote and immediately create task (bypass decide for obvious items)
    public func dispatch(id: String, companyId: String) async throws -> OrchestratorTask

    /// Kill with reason
    public func kill(id: String, reason: String) async throws -> BacklogItem

    /// Defer (park)
    public func `defer`(id: String) async throws -> BacklogItem

    /// Batch reorder
    public func reorder(_ items: [(id: String, sortOrder: Int)]) async throws

    /// Count by status
    public func count(status: BacklogItem.Status?, companyId: String?) async throws -> Int
}
```

### 4.3 ListProgressStore (shared)

Already specified in shikki-flow-v1.md feature #6. File: `~/.config/shiki/list-progress.json`.

```swift
public struct ListProgressStore: Sendable {
    private let filePath: URL
    // ~/.config/shiki/list-progress.json

    public func load(listId: String) -> ListProgress
    public func save(_ progress: ListProgress, listId: String)
}

public struct ListProgress: Codable, Sendable {
    public let listId: String
    // listId: "backlog", "inbox", "inbox:prs", "inbox:maya", etc.
    public var reviewedItemIds: Set<String>
    public var pinnedOrder: [String]
    // pinnedOrder: item IDs in user-pinned order
    public var lastIndex: Int
}
```

---

## 5. Implementation Waves

### Wave 1: DB + Backend (backend team / Deno)

**Files touched:**
- `src/db/migrations/007_backlog_items.sql` (new)
- `src/backend/src/schemas.ts` (add 5 schemas)
- `src/backend/src/backlog.ts` (new — CRUD functions, ~200 LOC)
- `src/backend/src/routes.ts` (add 9 route handlers + 1 inbox count, ~150 LOC)

**Deliverables:** Migration runs clean, all 10 endpoints return correct responses, tested with curl.

### Wave 2: Swift Models + BackendClient (shiki-ctl)

**Files touched:**
- `Sources/ShikiCtlKit/Models/BacklogItem.swift` (new)
- `Sources/ShikiCtlKit/Models/InboxItem.swift` (new)
- `Sources/ShikiCtlKit/Models/InboxCount.swift` (new)
- `Sources/ShikiCtlKit/Protocols/BackendClientProtocol.swift` (add 9 methods)
- `Sources/ShikiCtlKit/Services/BackendClient.swift` (implement 9 methods)

**Deliverables:** All new models decode correctly from backend JSON. BackendClient methods tested against running backend.

### Wave 3: BacklogManager + BacklogCommand (shiki-ctl)

**Files touched:**
- `Sources/ShikiCtlKit/Managers/BacklogManager.swift` (new)
- `Sources/ShikiCtlKit/Commands/BacklogCommand.swift` (new)
- `Sources/ShikiCtlKit/Commands/ShikkiCommand.swift` (register subcommand)

**Deliverables:** `shikki backlog add "test"` creates item. `shikki backlog` lists items. `shikki backlog --json` outputs JSON. `shikki backlog --count` outputs number.

### Wave 4: InboxManager + InboxCommand (shiki-ctl)

**Files touched:**
- `Sources/ShikiCtlKit/Managers/InboxManager.swift` (new)
- `Sources/ShikiCtlKit/Protocols/InboxDataSource.swift` (new)
- `Sources/ShikiCtlKit/Managers/Inbox/PRInboxSource.swift` (new)
- `Sources/ShikiCtlKit/Managers/Inbox/DecisionInboxSource.swift` (new)
- `Sources/ShikiCtlKit/Managers/Inbox/SpecInboxSource.swift` (new)
- `Sources/ShikiCtlKit/Managers/Inbox/TaskInboxSource.swift` (new)
- `Sources/ShikiCtlKit/Managers/Inbox/GateInboxSource.swift` (new)
- `Sources/ShikiCtlKit/Commands/InboxCommand.swift` (new)
- `Sources/ShikiCtlKit/Commands/ShikkiCommand.swift` (register subcommand)

**Deliverables:** `shikki inbox` displays unified list. `shikki inbox --count` outputs number. `shikki inbox --prs` filters to PRs. `shikki inbox --json` outputs JSON.

### Wave 5: ListReviewer Integration (depends on ListReviewer TUI widget)

**Files touched:**
- `Sources/ShikiCtlKit/Commands/BacklogCommand.swift` (swap static list for ListReviewer)
- `Sources/ShikiCtlKit/Commands/InboxCommand.swift` (swap static list for ListReviewer)
- `Sources/ShikiCtlKit/Services/ListProgressStore.swift` (new)

**Deliverables:** Interactive mode with keyboard actions, progress persistence across sessions.

---

## 6. Test Plan

### Backend Tests (Deno)

| Test | What it verifies |
|------|-----------------|
| `backlog_crud_test.ts` | Create, read, update, list, count |
| `backlog_lifecycle_test.ts` | State transitions: raw->enriched->ready, kill from any state, deferred parking |
| `backlog_promote_test.ts` | Promotion creates task_queue row with source='backlog', writes promoted_to_task_id |
| `backlog_reorder_test.ts` | Batch reorder updates sort_order, ordering reflects in list response |
| `backlog_filters_test.ts` | Filter by status, company_id, tags; sort by priority/age/manual |
| `inbox_count_test.ts` | Count endpoint returns correct aggregation across tables |
| `backlog_invalid_transitions_test.ts` | Kill->anything returns 422, ready->raw returns 422 |

**Count: ~14 test cases across 7 files**

### Swift Tests (ShikiCtlKit)

| Test | What it verifies |
|------|-----------------|
| `BacklogItemDecodingTests` | JSON decoding from backend, snake_case mapping, nullable fields |
| `InboxItemTests` | InboxItem construction, urgencyScore calculation, id format parsing |
| `BacklogManagerTests` | add/enrich/promote/kill/defer flow through mocked BackendClient |
| `InboxManagerTests` | Aggregation from multiple mock sources, sorting by urgency, filtering |
| `PRInboxSourceTests` | gh JSON parsing, company detection from branch name |
| `DecisionInboxSourceTests` | Maps Decision to InboxItem correctly |
| `ListProgressStoreTests` | Save/load/merge progress, handles missing file gracefully |
| `BacklogCommandTests` | ArgumentParser parsing for all subcommands and flags |
| `InboxCommandTests` | ArgumentParser parsing for all flags and filters |
| `InboxCountDecodingTests` | JSON decoding from /api/inbox/count endpoint |

**Count: ~32 test cases across 10 files**

---

## 7. LOC Estimates

| Component | File | Est. LOC |
|-----------|------|----------|
| **DB migration** | `007_backlog_items.sql` | ~40 |
| **Backend schemas** | `schemas.ts` additions | ~60 |
| **Backend CRUD** | `backlog.ts` (new) | ~200 |
| **Backend routes** | `routes.ts` additions | ~150 |
| **Swift BacklogItem model** | `BacklogItem.swift` | ~80 |
| **Swift InboxItem model** | `InboxItem.swift` | ~70 |
| **Swift InboxCount model** | `InboxCount.swift` | ~15 |
| **BackendClient protocol additions** | `BackendClientProtocol.swift` | ~30 |
| **BackendClient implementation** | `BackendClient.swift` additions | ~120 |
| **BacklogManager** | `BacklogManager.swift` | ~100 |
| **InboxManager** | `InboxManager.swift` | ~90 |
| **InboxDataSource protocol** | `InboxDataSource.swift` | ~20 |
| **5 inbox adapters** | `*InboxSource.swift` (5 files) | ~250 |
| **BacklogCommand** | `BacklogCommand.swift` | ~120 |
| **InboxCommand** | `InboxCommand.swift` | ~110 |
| **ListProgressStore** | `ListProgressStore.swift` | ~60 |
| **Backend tests** | 7 test files | ~300 |
| **Swift tests** | 10 test files | ~450 |
| | **Total** | **~2,265** |

---

## Appendix: Migration Checklist

Before implementation:

- [ ] Verify `update_updated_at()` trigger function exists (from 004_orchestrator.sql)
- [ ] Confirm `companies` table exists and is populated (migration 004)
- [ ] Run `scripts/worktree-setup.sh` if working in a worktree
- [ ] `gh` CLI authenticated (required for PRInboxSource)

Post-implementation:

- [ ] `shikki backlog add "test" && shikki backlog --count` returns 1
- [ ] `shikki backlog --json | jq '.[0].status'` returns `"raw"`
- [ ] `shikki inbox --count` returns aggregated number
- [ ] Promote flow: backlog add -> enrich -> promote -> verify task_queue row exists
- [ ] Kill flow: backlog add -> kill "reason" -> verify status=killed and kill_reason set
- [ ] Progress persistence: open inbox, review 2 items, quit, reopen -> resumes from item 3
