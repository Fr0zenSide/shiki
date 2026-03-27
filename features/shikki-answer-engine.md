---
title: "Shikki Answer Engine — Tabby Patterns for Codebase-Aware Engineering Q&A"
status: spec
priority: P1
project: shikki
created: 2026-03-28
authors: "@Sensei @Shogun @Hanami @Ronin + @Daimyo brainstorm"
relates-to:
  - shikki-codegen-engine.md
  - shiki-knowledge-mcp.md
  - shiki-observatory.md
---

# Shikki Answer Engine

## Context

Tabby (TabbyML/tabby, 33k+ stars) is a self-hosted Copilot alternative. It provides IDE-level code
completion + chat + an "Answer Engine" — RAG over a codebase for engineering Q&A. Rust, Apple Metal,
no cloud dependency.

Shikki operates at a different layer: **project-level orchestration**, not IDE-level completion.
They are complementary. This spec extracts four Tabby patterns and adapts them to Shikki's layer.

---

## Agent Input

### @Sensei — Architecture

**Answer Engine vs ArchitectureCache vs ShikkiMCP: what's the difference?**

Three distinct layers, each with a different purpose:

| Layer | What it is | Freshness | Query style |
|-------|-----------|-----------|-------------|
| `ArchitectureCache` | Static snapshot of types, protocols, deps | Per-commit, pre-built | Structured field lookup |
| `ShikkiMCP` | Typed tool layer over ShikiDB memories/events | Live, event-driven | Semantic search, typed tools |
| **Answer Engine** (new) | RAG over full codebase + docs + DB, queryable in natural language | Near-real-time | "how does X work?" |

ArchitectureCache is a **compiled snapshot** (great for agents generating code — they get structured
types without reading files). ShikkiMCP is a **knowledge persistence layer** (events, decisions,
specs). The Answer Engine is a **question-answering system** that synthesises across all three plus
raw source files.

Architecture: three retrieval sources, one unified query interface.

```
shikki ask "how does the event bus work?"
          │
          ▼
    AnswerEngine
    ┌─────────────────────────────────────────────┐
    │  1. ArchitectureCache  (types, protocols)   │
    │  2. ShikkiMCP search   (specs, decisions)   │
    │  3. Source RAG         (actual .swift files)│
    │  4. Docs RAG           (features/*.md)      │
    └─────────────────────────────────────────────┘
          │
          ▼
    Ranked + fused answer with source citations
```

The Source RAG chunk is the new piece. It requires an index — either built locally (BM25 + embedding)
or delegated to a running Tabby instance. The simplest v1: BM25 over `SourceChunk` objects derived
from the existing `ProjectAnalyzer` output.

**Key insight**: ArchitectureCache already extracts the right metadata (types, protocols, patterns).
The Answer Engine adds a full-text retrieval layer on top of the actual source bodies — the parts
ArchitectureCache intentionally skips.

---

### @Shogun — Market Signal

**Tabby: 33k stars. What does that tell us?**

Tabby's growth signals three things:

1. **Privacy-first wins developer trust.** Self-hosted, no cloud, Apple Metal. Developers don't want
   their code in OpenAI's training pipeline. Shikki's local-first stance (ShikiDB on-prem, no SaaS
   telemetry) is the same instinct — lean into it harder. "Your codebase never leaves your machine"
   should be explicit in Shikki's positioning.

2. **Answer Engine is their breakout feature, not completions.** Completions are a commodity (Copilot,
   Cursor, Supermaven). Their "chat with your codebase" angle is what differentiates. Shikki has a
   higher-value version of this: not just Q&A but Q&A that informs code generation. "Ask → understand
   → generate" is a stronger loop than Tabby's "ask → understand."

3. **Their growth is organic + dev-community.** No sales, GitHub stars compound. The pattern to steal:
   ship a feature that makes developers go "I didn't know I needed this until I saw it." The Answer
   Engine demo is that feature for Shikki. A 30-second terminal video: `shikki ask "how does checkout
   work?"` returns a precise answer with citations in 2 seconds → that demo will spread.

Shikki is not competing with Tabby (different layer). But Shikki should track Tabby as a
**potential integration target** — `shikki plugin add code-completion` pointing at a local Tabby
instance is a credible future offering.

---

### @Hanami — UX

**`shikki ask "how does the event bus work?"` — what does the experience feel like?**

The UX north star: **instant, cited, actionable**.

Not a chat interface. Not a scrolling conversation. A single-shot retrieval:

```
$ shikki ask "how does the event bus work?"

  EventBus — Shikki's async publish/subscribe backbone
  ─────────────────────────────────────────────────────
  EventBus.swift dispatches ShikkiEvent values to typed subscribers.
  Subscribers register via subscribe<E: ShikkiEvent>(handler:) and
  receive events on a background actor.

  Key types:
  · EventBus          — central hub, @globalActor
  · ShikkiEvent       — protocol, all events conform
  · EventSubscription — cancellable handle

  Sources cited:
  · Sources/ShikkiKit/Events/EventBus.swift (lines 12–45)
  · features/shiki-event-bus-architecture.md (§ Design)
  · ShikiDB: "Event bus architecture decision" (2026-03-15)
```

Design principles:
- **Fits in one screen.** No pagination. If the answer is longer, it's wrong.
- **Cited sources** are clickable in supported terminals (iTerm2, Kitty — OSC 8 hyperlinks).
- **Actionable suffix**: if the query matches a file/protocol, offer `shikki codegen --context <topic>`.
- **In CodeGen prompts**: same answer surface is used automatically by `AgentPromptGenerator` — no
  separate call, agents get answers injected into context before generation.

The `shikki ask` verb is intentional — not `shikki search` (implies keyword), not `shikki query`
(too SQL). "Ask" signals understanding, not retrieval.

---

### @Ronin — Adversarial

**Is wrapping Tabby worth the complexity vs building our own?**

Honest answer: wrapping Tabby is a trap for v1, a valid option for v2+.

**Against wrapping Tabby (now):**
- Tabby runs as a separate HTTP server. Adds a process dependency, port conflict risk, memory overhead.
  Shikki is a CLI tool — startup time matters. Spinning up a Tabby server on `shikki ask` is a 3-5s
  cold start. That kills the UX.
- Tabby's embedding models are optimised for completion context, not architecture Q&A. Our needs are
  different: we want semantic search over Swift protocol names and spec documents, not next-token
  prediction.
- Version coupling. Every Tabby API change breaks our adapter.

**For wrapping Tabby (later):**
- Tabby already has IDE plugins, team dashboards, usage analytics. If Shikki targets team workflows,
  a single Tabby instance serving both completions (to the IDE) and answer queries (to Shikki) is
  efficient. One process, shared index.
- Their embedding pipeline is production-grade. BM25 + tree-sitter chunking + reranker. We'd spend
  3 months rebuilding something they've already shipped.

**Recommendation:**
Build our own BM25-first Answer Engine in Wave 1 (no Tabby dependency). Design the
`AnswerEngineProtocol` to accept a `TabbyAdapter` as a future backend. When team usage emerges,
introduce the Tabby plugin path. This is the "use now, build later" philosophy from
`feedback_external-tools-philosophy.md` — except inverted: build first (lightweight), delegate
to external tool after we understand our real retrieval needs.

The risk of building first: we reinvent BM25. The risk of wrapping first: we ship a CLI tool that
requires a background HTTP server and 4GB of VRAM. The second risk is worse for Shikki's user profile
(solo developers on macOS, not teams with dedicated infra).

---

## Feature Brief

### Problem

Shikki agents (CodeGen, DispatchEngine, FixEngine) start every task with partial codebase knowledge.
`ArchitectureCache` provides structured metadata. But when an agent needs to understand **how a
system works** — not just that it exists — it must read raw source files. This is expensive (tokens),
slow (sequential file reads), and inconsistent (each agent re-reads, no shared understanding).

Developers face the same gap: `shikki codegen` knows the types but not the intent. Engineers asking
"how does X work?" get no answer from the current toolchain.

### Solution

The **Shikki Answer Engine**: natural language Q&A over the full codebase, fused with ShikiDB
knowledge and ArchitectureCache metadata. Queryable by humans (`shikki ask`) and agents (injected
into CodeGen context automatically).

### Key Behaviours

**BR-1 — Human Q&A**: `shikki ask "<natural language question>"` returns a cited answer synthesised
from source code, specs, and ShikiDB memories. Answer fits in one terminal screen. Cites file paths
and line ranges.

**BR-2 — Agent Context Injection**: `AgentPromptGenerator` calls `AnswerEngine.resolve(topic:)`
before building prompts for CodeGen, FixEngine, and DispatchEngine. Agents receive the answer as
structured context, not raw files.

**BR-3 — LSP-Augmented Retrieval**: When answering about a symbol (type name, protocol, function),
the engine queries the Swift LSP server for declarations, conformances, and call sites. Tabby does
this for completions — we do it for Q&A. Richer answers for code-related questions at near-zero cost
(LSP is already running).

**BR-4 — Multi-Source Fusion**: Results from ArchitectureCache (structured), BM25 over source
(full-text), and ShikkiMCP search (semantic/DB) are fused and ranked before synthesis. No single
source is authoritative alone.

**BR-5 — Usage Telemetry for Observatory**: Every `shikki ask` emits a `ShikkiEvent` with query,
sources cited, latency, and whether it was agent-invoked or human-invoked. Observatory can show:
queries per session, most-asked topics, cache hit rate. This is the analytics layer the Observatory
spec lacks today.

**BR-6 — Tabby Plugin Path**: `AnswerEngine` conforms to `AnswerEngineProtocol`. A `TabbyAdapter`
can be registered via `shikki plugin add code-completion --tabby-url http://localhost:8080`. When
registered, the engine routes embedding/reranking to Tabby's API while keeping synthesis in Shikki.
Shikki manages the Tabby process lifecycle via `ShikkiKernel` start/stop hooks.

### Non-Goals (v1)
- No persistent chat/conversation history (single-shot only — avoids session state complexity)
- No streaming answers (terminal output is fast enough for BM25-level retrieval)
- No cross-project Q&A (scoped to current `shikki` project root)
- No Tabby dependency in v1 (adapter only, not required)

---

## Architecture Sketch

```
AnswerEngineProtocol
  func ask(_ query: String, context: ProjectContext) async throws -> AnswerResult

AnswerResult
  var answer: String
  var citations: [Citation]        // file path + line range + source type
  var confidence: Float            // 0-1, for Observatory telemetry
  var latency: Duration

LocalAnswerEngine: AnswerEngineProtocol
  - BM25Index          (built from ProjectAnalyzer SourceChunks)
  - ArchitectureLookup (delegates to ArchitectureCache)
  - MCPSearchClient    (delegates to ShikkiMCP search tool)
  - LSPClient          (symbol declarations + call sites)
  - Synthesizer        (fuses ranked results → final answer via AgentProvider)

TabbyAdapter: AnswerEngineProtocol
  - Routes to Tabby HTTP API for embedding + reranking
  - Falls back to LocalAnswerEngine if Tabby unavailable

SourceChunk
  var file: String
  var startLine: Int
  var endLine: Int
  var content: String
  var symbols: [String]            // extracted from ArchitectureCache
```

---

## Delivery Waves

**Wave 1 — BM25 Core** (foundation)
- `SourceChunker`: splits Swift files into semantic chunks (function/type boundaries via SwiftSyntax)
- `BM25Index`: build + query, persisted alongside ArchitectureCache
- `shikki ask` command: query → BM25 → Synthesizer → cited answer
- Event emission for Observatory

**Wave 2 — Multi-Source Fusion**
- Integrate ArchitectureCache lookup + ShikkiMCP search into ranked fusion
- LSP symbol lookup for code-related queries
- `AgentPromptGenerator` integration (auto-inject into CodeGen context)

**Wave 3 — Tabby Plugin Path**
- `TabbyAdapter` conforming to `AnswerEngineProtocol`
- `shikki plugin add code-completion` CLI hook
- `ShikkiKernel` process lifecycle for Tabby server

---

## Metrics

| Metric | Target |
|--------|--------|
| `shikki ask` cold latency | < 2s (BM25, no embedding) |
| Answer screen fit | 100% (enforced truncation) |
| Citation accuracy | > 80% cited lines contain the answer basis |
| Agent context overhead | < 500 tokens added per CodeGen prompt |
| Observatory event coverage | 100% of `shikki ask` calls emitted |

---

## Open Questions

1. **SwiftSyntax chunking**: `ProjectAnalyzer` already uses tree-sitter-style parsing. Can
   `SourceChunker` reuse that traversal, or does it need a separate SwiftSyntax walk?
2. **Embedding in v2**: BM25 works for exact-ish queries. For "what's the philosophy behind X?"
   we need semantic embeddings. LM Studio (already running at `http://127.0.0.1:1234`) can serve
   local embeddings — no cloud. Design the `Embedder` protocol in Wave 1 even if not implemented.
3. **Index invalidation**: ArchitectureCache invalidates on git hash change. BM25Index should share
   the same invalidation key — confirm this is sufficient or if file-level mtimes are needed.
