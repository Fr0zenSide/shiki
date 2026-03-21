# Radar Scan: Notion Architecture Analysis

**Date**: 2026-03-18
**Purpose**: Extract patterns from Notion's product architecture for Shiki's augmented search, command palette, and TUI design.

---

## 1. Block System -- Core Data Model

### How It Works

Notion's single foundational decision: **model everything as a block**. A paragraph, heading, image, database row, page, and even a full database are all blocks with the same backend schema. This uniform representation is what gives Notion its "shows almost nothing but can build everything" character.

**Key structural properties:**

| Property | Description |
|----------|-------------|
| `id` | UUID for every block |
| `type` | Determines rendering (paragraph, heading_1, to_do, database, page, etc.) |
| `parent` | Upward pointer -- used for permissions |
| `content` | Downward pointers -- ordered list of child block IDs |
| `properties` | Type-specific data (text content, checkbox state, URL, etc.) |

**Tree structure**: Blocks form a render tree via bidirectional pointers. Indentation is structural, not presentational -- indenting a block makes it a child of the block above. The `loadPageChunk` API call descends from a page block ID down the content tree, returning blocks + dependent records needed to render.

**Backend**: All blocks stored in PostgreSQL, sharded by workspace ID (480 logical shards across 96 physical instances as of 2023). Workspace ID as partition key means all blocks for a workspace live on the same shard -- no cross-shard joins for normal operations.

### What Shiki Can Steal

- **Uniform entity model**: Everything in Shiki's search index could be a "node" with the same base schema -- a session, a pane, a task, a file, a git ref, an agent. Different `type` discriminator, same query interface.
- **Parent-child tree**: Sessions contain panes, panes contain processes, processes produce outputs. This is already implicit in our tmux model -- making it explicit as a block tree enables tree-walking queries ("show me everything under session #3").
- **Bidirectional pointers**: If a file references a session and a session references a file, we get automatic backlinks. Enables "where is this file used?" without a separate index.

---

## 2. Slash Commands -- Universal Creation Interface

### How It Works

Typing `/` in any editable text block opens a filtered command palette. As you type, it fuzzy-matches against all available block types and actions. Arrow keys navigate, Enter executes. Commands are context-aware -- available commands may differ based on where you are.

**Command categories:**
- **Basic blocks**: Text, Page, To-do, Heading 1/2/3, Bulleted list, Toggle, Divider
- **Inline**: Mention person, Mention page, Date, Emoji
- **Database**: Table view, Board view, Gallery, Timeline, Calendar, List
- **Media**: Image, Video, Bookmark, Code, File
- **Advanced**: Table of contents, Synced block, Template button, Breadcrumb
- **Actions**: Delete, Duplicate, Move to, Turn into (block type conversion)

The key insight: `/` is not a menu -- it's a **creation and transformation interface**. You can create new blocks or transform existing ones through the same mechanism.

### What Shiki Can Steal

- **`/` command palette** maps directly to Shiki's planned command palette. Same fuzzy-match, same contextual filtering.
- **Creation + transformation in one interface**: `shiki /session` creates, `shiki /kill` destroys, `shiki /view board` transforms the current view. One entry point, polymorphic actions.
- **Context-aware filtering**: Commands available in a session context differ from commands in the board view. Filter the palette based on current focus.

### What Doesn't Apply

- Notion's slash commands are inline (cursor position matters). In a TUI, we don't have a cursor-in-document metaphor. Our `/` is a modal command palette, not an inline insertion point.

---

## 3. @ Mentions -- Inline Reference System

### How It Works

Typing `@` opens a search palette scoped to referenceable entities:

| Target | Behavior |
|--------|----------|
| **Person** | Creates clickable mention, sends notification, appears in their inbox |
| **Page** | Creates inline link that auto-updates if page title changes, creates backlink |
| **Date** | Inline date chip with date picker, supports natural language ("tomorrow", "next Friday") |
| **Reminder** | Date mention + notification at specified time |
| **@here** | Pings all current viewers of the page |

**Backlinks are automatic**: Mentioning a page creates a backlink on that page. If you rename the target page, every `@mention` of it updates everywhere. This is the "node graph" forming organically through usage.

### What Shiki Can Steal

- **`@` targeting system** maps to Shiki's agent/entity targeting. `@Sensei` targets an agent, `@session/3` targets a session, `@file/Package.swift` targets a file. Same fuzzy search, scoped to entity types.
- **Auto-updating references**: If a session is renamed or a file moves, references should update. This is the backlink/forward-link pair.
- **Natural language dates**: `@tomorrow`, `@next-friday` for scheduling -- useful for task deadlines in the board view.

### What Doesn't Apply

- Person notifications (we don't have multi-user collaboration)
- @here (single-user TUI)

---

## 4. Synced Blocks -- Content Mirroring

### How It Works

A synced block creates a **single source of truth** that can appear in multiple pages. Edit any instance, all instances update. Under the hood, it's a reference to the original block -- copies are "windows" back to the source.

**Constraints:**
- Viewers need access to the original page to see synced copies
- Editors need edit access to the original to modify any copy
- Permissions flow through the parent pointer chain

**Linked databases** are a related but distinct concept: they show the same dataset with different filters/sorts/views, rather than mirroring a block.

### What Shiki Can Steal

- **Synced views**: A process (e.g., running test suite) could appear in both the session view and the board view simultaneously. Same underlying data, multiple projections.
- **Single source of truth**: Agent output, session logs, task status -- one canonical source, multiple display contexts.
- **Linked database pattern**: The board view and the session list are linked views of the same session registry. Filter differently, sort differently, but it's the same data.

### What Doesn't Apply

- Block-level content mirroring is a document collaboration feature. In a TUI, we don't edit shared content blocks across pages. The pattern translates to "same data, multiple views" which is already our database view model.

---

## 5. Database Views -- Same Data, Different Lenses

### How It Works

A single Notion database supports 6 view types:

| View | Best For | Key Property |
|------|----------|--------------|
| **Table** | Spreadsheet-style data entry | All properties visible as columns |
| **Board** | Kanban workflow (status tracking) | Groups by select/multi-select/status property |
| **Timeline** | Gantt-style project planning | Requires date property with start/end |
| **Calendar** | Date-based scheduling | Requires date property |
| **Gallery** | Visual cards (image-heavy) | Highlights cover image + key fields |
| **List** | Minimal, clean display | Title + optional subtitle |

**Architecture**: Views are projections, not copies. Each view stores its own filter/sort/group configuration but reads from the same underlying dataset. Editing a record in any view updates all views.

**2025 update -- Data Sources**: A single database can now hold multiple data sources (e.g., "Tasks", "Projects", "Meetings" in one database), enabling cross-source views and automation.

### What Shiki Can Steal

- **Board view** is already in our orchestrator spec. Direct mapping: sessions as cards, grouped by status (active/paused/completed).
- **Table view** maps to a detailed session list with sortable columns (agent, duration, status, last activity).
- **List view** maps to our current minimal session display.
- **Timeline view** could visualize session duration and overlap -- useful for understanding concurrency patterns.
- **View switching**: Same data, toggle between views with a keybinding. `Ctrl-v t` for table, `Ctrl-v b` for board, `Ctrl-v l` for list.
- **Filters and sorts per view**: Each view saves its own filter state. Board filters to active sessions, table shows everything.

### What Doesn't Apply

- **Gallery view**: Image-heavy display doesn't translate to TUI.
- **Calendar view**: Sessions aren't calendar-event-shaped. Could be useful later for scheduled tasks but not now.

---

## 6. API / Integration Model

### How It Works

Notion exposes blocks, pages, databases, and users through a REST API:

- **Block CRUD**: Create, read, update, delete any block by ID
- **Database queries**: Filter, sort, paginate database entries via API
- **Search**: Full-text search across all accessible pages
- **Webhooks** (2025): Real-time HTTP POST on page/database/comment changes
- **Webhook Actions**: No-code HTTP triggers from buttons and automations

**Integration model**: OAuth 2.0 for third-party apps, internal integrations use API tokens scoped to specific pages/databases.

### What Shiki Can Steal

- **Event-driven architecture**: Our ShikiEvent bus already mirrors the webhook pattern. External tools should be able to subscribe to Shiki events (session started, agent spawned, task completed).
- **Block-level API**: If everything is a node, external tools can query/modify individual nodes. MCP servers could read/write to the Shiki node graph.
- **Scoped access**: Integrations see only what they're granted access to. Agent providers should only see their own session data.

### What Doesn't Apply

- OAuth 2.0 flow (single-user CLI tool)
- Webhook Actions as no-code automation (we're code-first)

---

## 7. AnyType -- What They Copied, What They Changed

### What AnyType Keeps From Notion

- **Everything is an object** (= block): Pages, tasks, contacts, bookmarks are all objects with the same base schema
- **Block-based content**: Pages are composed of content blocks (text, headings, lists, etc.)
- **Relations** (= properties): Attributes attached to objects (name, date, status, tags)
- **Multiple views**: Same dataset viewable as grid, list, gallery, board, calendar
- **Slash commands**: `/` to create blocks, same UX pattern
- **@ mentions**: Cross-reference objects inline

### What AnyType Changes

| Aspect | Notion | AnyType |
|--------|--------|---------|
| **Storage** | Cloud (PostgreSQL on AWS) | Local-first (device storage + IPFS backup) |
| **Sync** | Server-mediated | P2P via AnySync protocol, no central server |
| **Encryption** | Server-side, business-controlled | End-to-end, user-controlled keys |
| **Type system** | Implicit (database = type) | Explicit Object Types (Book, Contact, Project, Task...) with inheritance |
| **Relations** | Scoped to one database | Global -- any relation can connect any types |
| **Graph** | Implicit via backlinks | Explicit graph view, objects are nodes, relations are edges |
| **Open source** | Proprietary | Apache 2.0 (anyproto) |
| **Offline** | Limited, requires connection | Full offline, sync on reconnect |
| **Architecture** | Monolith PostgreSQL | CRDTs + IPFS content-addressed storage |

### Key AnyType Innovation: Global Relations

In Notion, a "Status" property exists per-database. In AnyType, "Status" is a global relation that can be attached to any object type. This means you can query "all objects with Status = In Progress" across Books, Tasks, Projects, and Contacts -- without building cross-database rollups.

This is the **knowledge graph** pattern: relations are first-class entities, not property columns.

---

## Recommendations for Shiki

### ADOPT -- High-Value Patterns

| Pattern | Source | Shiki Mapping | Priority |
|---------|--------|---------------|----------|
| **Uniform node model** | Notion blocks | Everything is a `ShikiNode` -- session, pane, task, file, agent | P0 |
| **`/` command palette** | Notion slash commands | Already planned. Fuzzy-match, context-aware filtering | P0 |
| **`@` entity targeting** | Notion @ mentions | `@agent`, `@session/N`, `@file/path` -- unified reference system | P0 |
| **View switching** | Notion database views | Board / Table / List views of session registry, same data | P1 |
| **Bidirectional links** | Notion backlinks | If A references B, B knows about A. Enables "where-used" queries | P1 |
| **Global relations** | AnyType | Relations not scoped to one type. Status, Priority, Agent apply across all node types | P1 |
| **Event bus as API** | Notion webhooks | ShikiEvent bus already designed. Expose to MCP/external tools | P2 |
| **Local-first storage** | AnyType | Already our architecture. SQLite/libsql, no cloud dependency | P0 (done) |

### ADAPT -- Useful But Needs TUI Translation

| Pattern | Why Adapt | How |
|---------|-----------|-----|
| **Synced blocks** | No document mirroring in TUI | Translate to: same node visible in multiple views (board + list + detail pane) |
| **Inline @ references** | No inline document editing | Translate to: `@` as a command modifier, not inline text decoration |
| **Database data sources** | Multi-source databases are Notion-specific | Translate to: unified search across heterogeneous node types (sessions + files + git refs) |
| **Graph view** | AnyType's visual graph is GUI-only | Translate to: tree/list representation of graph relationships in TUI. `shiki graph @session/3` shows connected nodes |

### SKIP -- Doesn't Apply to TUI

| Pattern | Why Skip |
|---------|----------|
| **Gallery view** | Image-heavy, no TUI equivalent |
| **Calendar view** | Sessions aren't calendar events (revisit if we add scheduling) |
| **Real-time collaboration** | Single-user tool |
| **OAuth integration model** | No third-party app marketplace |
| **IPFS/P2P sync** | Over-engineered for single-machine CLI. Local SQLite is sufficient |
| **CRDT conflict resolution** | No multi-device concurrent editing |
| **Block-level permissions** | Single-user, no permission model needed |

### Architecture Recommendation: ShikiNode Protocol

The strongest pattern across both Notion and AnyType is the **uniform entity model**. Proposed for ShikiKit:

```
ShikiNode protocol:
  - id: UUID
  - type: NodeType (session, pane, task, file, agent, gitRef)
  - parent: ShikiNode?
  - children: [ShikiNode]
  - relations: [Relation]  -- global, cross-type (status, priority, agent, tags)
  - created: Date
  - modified: Date
  - content: NodeContent   -- type-specific payload
```

This gives us:
1. **Unified search**: One query interface across all entity types
2. **Tree walking**: Navigate parent/child hierarchies
3. **Graph queries**: Follow relations across types ("all nodes with agent = @Sensei")
4. **View projections**: Board/Table/List are different renderers of the same `[ShikiNode]`
5. **Event bus integration**: `ShikiEvent` can reference any `ShikiNode` by ID

The `/` palette creates nodes, the `@` system references them, the view system renders them, and the event bus observes them. One data model, four interaction modes.

---

## Sources

- [Exploring Notion's Data Model: A Block-Based Architecture](https://www.notion.com/blog/data-model-behind-notion)
- [Notion System Design Explained](https://www.educative.io/blog/notion-system-design)
- [Herding Elephants: Sharding Postgres at Notion](https://www.notion.com/blog/sharding-postgres-at-notion)
- [Notion Data Sources Explained (2025)](https://www.notionapps.com/blog/notion-data-sources-update-2025)
- [How Notion Stores Data and Scales to Millions of Users](https://wildwildtech.substack.com/p/how-notion-stores-the-data-and-scale)
- [Examining Notion's Backend Architecture](https://labs.relbis.com/blog/2024-04-18_notion_backend/)
- [Notion Block API Reference](https://developers.notion.com/reference/block)
- [Notion Webhooks API Reference](https://developers.notion.com/reference/webhooks)
- [Using Slash Commands -- Notion Help](https://www.notion.com/help/guides/using-slash-commands)
- [Comments, Mentions & Reactions -- Notion Help](https://www.notion.com/help/comments-mentions-and-reminders)
- [Synced Blocks -- Notion Help](https://www.notion.com/help/synced-blocks)
- [Using Database Views -- Notion Help](https://www.notion.com/help/guides/using-database-views)
- [AnyType vs Notion: Side-by-Side Comparison (2026)](https://thebusinessdive.com/anytype-vs-notion)
- [AnyType: From Second Brain to Social Brain with Types and Graphs](https://volodymyrpavlyshyn.medium.com/anytype-from-second-brain-to-social-brain-with-types-and-graphs-e6eb6611ec7d)
- [AnyType Object Types and Relations -- DeepWiki](https://deepwiki.com/anyproto/anytype-heart/3.1-object-types-and-relations)
- [AnyType Relations System (Swift) -- DeepWiki](https://deepwiki.com/anyproto/anytype-swift/5.2-relations-system)
- [Minimalist Notion Implementation: Everything Is a Block](https://medium.com/@arcilamatt/minimalist-notion-implementation-part-1-everything-is-a-block-debda338b61a)
- [Storing 200 Billion Entities: Notion's Data Lake Project](https://blog.bytebytego.com/p/storing-200-billion-entities-notions)
