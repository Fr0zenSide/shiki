---
title: "ShikkiCore CodeGen Engine — Parallel AI Code Production Protocol"
status: validated
priority: P0
project: shikki
created: 2026-03-25
validated: 2026-03-25
co-designed-with: "@Daimyo + @team challenge session"
---

# ShikkiCore CodeGen Engine

## Vision

Shikki's core value: **AI code production engine**, not a coding assistant. Developer writes specs, Shikki produces code — in parallel, with architecture awareness, and self-healing test loops.

Three innovations:
1. **Protocol-First Parallel Compilation** — spec → protocols → N parallel agents → merge → test → fix
2. **Architecture Cache MCP** — per-project architecture knowledge instantly queryable, no re-reading files
3. **CodeGen Protocol in ShikkiCore** — formalized pipeline, not a skill

## 1. Protocol-First Parallel Compilation

### Problem
Sequential code generation: read 20 files → write file A → read more → write file B → build → fix → repeat.
Each file depends on the previous. One agent, one thread, serial execution.

### Solution
Protocols are the contract. If every agent implements against the same protocol, their code composes at merge without sequential dependency.

```
Spec/TDDP
  → Protocol Compiler: generates types + interfaces + test contracts
  → Verify: protocols compile (green = contracts valid)
  → Split: N WorkUnits, each implementing against protocols
  → Dispatch: each WorkUnit → separate agent in own git worktree
  → Merge: rebase all worktrees → run scoped tests
  → Fix: if red, split failed tests by scope → parallel fix agents → re-merge
  → Cache: update architecture DB for next wave
```

### Key Insight
The protocol layer is both the **compilation firewall** (each agent only needs protocols, not other implementations) and the **merge contract** (if all agents satisfy the protocol, composition works).

### Failure Recovery Protocol
```
Test results: 47 green, 3 red
  → Classify failures by file/module scope
  → Group failures into fixable units
  → IF < 5 failures: single agent fixes all
  → IF 5-20 failures: split by module, parallel fix agents (1 per module)
  → IF > 20 failures: architectural issue → escalate to developer
  → Each fix agent gets: protocol context + failing test + implementation file
  → Fix agents work in worktrees → rebase → re-run red tests only
  → Loop until green or max 3 iterations (then escalate)
```

## 2. Architecture Cache MCP

### Problem
Every subagent re-discovers the project architecture from scratch. Agent A reads 20 files to understand Brainy. Agent B reads the same 20 files. Agent C reads them again. This is 60 redundant file reads.

### Solution
Per-project architecture cache in ShikkiDB, queryable via MCP. One ingestion pass, instant recall for all agents.

### Ingestion Pipeline
```
shikki ingest <project-path>
  → Parse Package.swift (dependencies, targets)
  → Parse all protocols (methods, conformances, files)
  → Parse all types (fields, relationships, generic constraints)
  → Parse test patterns (mock conventions, fixture patterns, assertion styles)
  → Build dependency graph (type A uses type B, module X imports module Y)
  → Detect code patterns (error handling, DI, naming conventions)
  → Store all in ShikkiDB scoped by project ID
```

### MCP Tools
```
get_project_context(project, scope?)
  → Returns: package structure, key protocols, naming conventions, test framework
  → ~2K tokens instead of reading 20 files (~30K tokens)

get_protocol(name)
  → Returns: full definition + all implementations + consumers + tests
  → Agent knows exactly what to implement against

get_type(name)
  → Returns: definition + fields + relationships + usage sites

get_pattern(name)
  → Returns: reusable code template with filled examples from this project
  → e.g., "error_pattern" → "enum XxxError: Error, LocalizedError, Equatable { ... }"

get_dependency_graph(module?)
  → Returns: what imports what, shared packages used, type flow

suggest_implementation(protocol_name, context?)
  → Returns: skeleton implementation based on project patterns
```

### Cache Invalidation
- Updated after each wave completes (post-merge)
- Invalidated on branch switch
- Versioned by git commit hash

## 3. CodeGen Protocol (ShikkiCore)

### Pipeline Protocol
```swift
public protocol CodeGenerationPipeline: Sendable {
    func compileProtocols(from spec: FeatureSpec) async throws -> ProtocolLayer
    func verifyContracts(_ layer: ProtocolLayer) async throws -> BuildResult
    func planParallelWork(_ layer: ProtocolLayer) -> [WorkUnit]
    func dispatch(_ units: [WorkUnit]) async throws -> [WorktreeResult]
    func merge(_ results: [WorktreeResult]) async throws -> MergeResult
    func fixFailures(_ failures: [TestFailure]) async throws -> MergeResult
    func updateArchitectureCache(project: String) async throws
}
```

### Work Unit
```swift
public struct WorkUnit: Sendable {
    let id: String
    let description: String
    let protocolContext: ProtocolLayer
    let architectureSnapshot: ProjectContext  // from MCP cache
    let files: [FileSpec]
    let worktreeBranch: String
    let testScope: [String]  // which tests verify this unit
}
```

### CLI Interface
```bash
# Full pipeline from spec
shikki wave "add payment system" --spec features/payment.md

# Resume from failure
shikki wave --resume --fix-red

# Ingest project architecture
shikki ingest projects/brainy

# Query architecture
shikki context brainy --protocols
shikki context brainy --type TranslationPipeline
```

## Implementation Waves

### Wave 1 — Architecture Cache MCP (~800 LOC)
- Project ingestion: parse Package.swift, protocols, types
- ShikkiDB storage (per-project scope)
- MCP tools: get_project_context, get_protocol, get_type, get_pattern

### Wave 2 — Protocol Compiler (~600 LOC)
- Spec parser → protocol/type extraction
- Contract verification (swift build on protocol layer only)
- WorkUnit planner (split by file/module)

### Wave 3 — Parallel Dispatch (~500 LOC)
- Worktree management (create, dispatch, collect)
- Agent prompt generator (protocol context + architecture cache)
- Result collector (wait for all, report progress)

### Wave 4 — Merge + Test Loop (~400 LOC)
- Rebase strategy (sequential by dependency order)
- Scoped test runner (only tests for this feature)
- Failure classifier (by module, by scope)

### Wave 5 — Fix Loop (~300 LOC)
- Failure → WorkUnit converter
- Parallel fix dispatch
- Re-merge + re-test loop (max 3 iterations)

### Wave 6 — CLI + Integration (~400 LOC)
- `shikki wave` command
- `shikki ingest` command
- `shikki context` command
- ShikkiCore FeatureLifecycle integration

**Total: ~3,000 LOC, ~100 tests**

## Competitive Position

| Tool | What it does | Level |
|---|---|---|
| GitHub Copilot | Autocomplete lines | Line-level |
| Cursor | Edit files with AI | File-level |
| Claude Code | AI pair programmer | Task-level |
| **Shikki** | **AI code production engine** | **Feature-level** |

Developers install Shikki. Write a spec. Get a feature. Tested. Merged. Next.

---

## Refined Design Decisions (Challenge Session 2026-03-25)

### TDDP IS the Protocol Source
The /spec pipeline produces the TDDP (test-driven development plan). That IS the contract.
No "protocol compiler from English prose." The TDDP process IS the compiler.

- `/spec` path → protocols come from TDDP → parallel dispatch possible
- `/quick` path → sequential until enough protocols exist → then can parallelize
- The developer validates the TDDP. Validation = contracts are locked. Dispatch begins.

### Single Protocol Owner
One agent creates ALL protocols for a wave. Never split protocol creation.
If implementation agents discover they need more:
1. Add the need to an "intentions backlog" for the feature
2. Main process consumes backlog after current dispatch completes
3. Re-dispatches new work → loops until backlog empty + tests green

### Smart Splitting Rules
- **2-5 files**: don't spawn agents, do it directly (spawn overhead > impl time)
- **5-15 files**: 2-3 agents max, split by module boundary
- **15+ files**: N agents, one per logical module
- Adjust dynamically: if smaller splits appear possible, take them
- "Fast and smart, not micro-managing agents for two prints"

### Failure Protocol
```
Red tests → classify by scope
  IF < 5 failures → single agent fixes all
  IF 5-20 → split by module, parallel fix (1 agent per module)
  IF > 20 → architectural issue, explain to developer
  Max 3 fix iterations → then ask the developer
  "They're engineers — explain the problem, they can help debug"
```

### Cache Trust Model
```
Sub-agents:     TRUST the cache blindly (speed is king)
Orchestrator:   CHALLENGE the cache at every spec validation
Background:     Periodic audit agent verifies cache vs reality

Rebuild triggers:
  - Big git moves (force push, history rewrite)
  - Cached git hash not reachable in current tree
  - Long project inactivity
  - Manual: shikki ingest --rebuild <project>

Cache metadata: { gitHash, date, constructionTimestamp }
Versioned like git — if hash is stale, rebuild.
```

### Spec Review Process (NEW — before ANY code generation)
Like PR review, but for specs and contracts. The quality gate BEFORE dispatch.

```
/spec → TDDP draft → @team review → @Daimyo validates
                          │
                          ├── Product check: is this solving the right problem?
                          ├── Architecture check: do protocols compose correctly?
                          ├── Test coverage: are edge cases covered?
                          └── Feasibility check: can this be split for parallel dispatch?

If spec passes → contracts are bulletproof → generate, ship to beta with confidence
If spec fails → iterate on spec, NOT on code
```

Same tooling as PR review (potentially same pipeline, adapted). Brainstorm with @team.

### Wave-Context Code Review (NEW)
Review output shows spec-to-code mapping in wave chronological order:

```
=== Wave 1: Core Models ===
  Spec: "TranslationPage holds regions, tracks progress"
  → Sources/BrainyCore/Translation/TranslationPage.swift (+65 lines)
  → Sources/BrainyCore/Translation/TextRegion.swift (+52 lines)
  → Tests/TranslationTests.swift: TranslationPageTests (+18 lines)

=== Wave 2: OCR Adapters ===
  Spec: "Apple Vision for Latin, PaddleOCR for CJK"
  → Sources/Brainy/Translation/OCR/AppleVisionOCR.swift (+95 lines)
  → Sources/Brainy/Translation/Mocks/MockOCRProvider.swift (+25 lines)
  → Tests/OCRTests.swift (+50 lines)

[Express mode: wave summary + smart-sorted diff]
[Full mode: complete spec → code pairs with wave history]
```

Reviewer sees WHERE each file comes from. Files sorted: archi > protocol > impl > tests.
History preserved: code reviewed in Wave 4 may reference patterns from Wave 1.

### "I Changed My Mind" = Git
No complex mid-flight handling. Developer reverts, course corrects, or cancels.
Git IS the undo system. Don't over-engineer interruption handling.

---

## First External Validation
Faustin (Maya co-founder, ADHD, unstructured work process) is already using Shikki.
Perfect --yolo mode user. Validates the product for non-structured developers.
Step-by-step toward readme, website, branding, storytelling — when mature enough.
