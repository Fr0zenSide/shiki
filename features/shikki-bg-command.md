---
title: "shi bg — Background AI Node with Local LLM"
status: draft
priority: P2
project: shikki
created: 2026-04-02
authors: "@Daimyo vision"
tags: [cli, local-llm, background, productivity]
---

# Feature: `shi bg` — Background AI Node with Local LLM
> Created: 2026-04-02 | Status: Draft | Owner: @Daimyo

## Context

Claude rate limits halt all productivity. When Opus hits its cap, the user stares at a timer. Meanwhile, a local LLM (LM Studio) sits idle on the same machine, perfectly capable of handling research, analysis, and review tasks — just not orchestration-grade work.

`shi bg` turns idle time into throughput. Background nodes use exclusively local LLMs to process prompts asynchronously while the main session continues (or waits for rate limits to lift). Context comes from ShikiDB, not the current Claude session, making bg nodes fully independent and session-survivable.

**Existing infrastructure** (all built):
- `LMStudioProvider` — OpenAI-compatible local LLM client (`ShikkiKit/Providers/LMStudioProvider.swift`)
- `FallbackProviderChain` — provider failover chain (`ShikkiKit/Providers/FallbackProviderChain.swift`)
- `NATSDispatcher` — pub/sub task dispatch with progress tracking (`ShikkiKit/NATS/NATSDispatcher.swift`)
- ShikiDB — persistent memory with `shiki_search`, `shiki_get_context`, `shiki_save_event`

## Problem

Rate limits on cloud LLMs create dead time. Research questions, code reviews, security analyses, and "think about this" prompts do not require Opus-grade intelligence. They need context + a competent model + time. Local LLMs provide all three, but there is no way to dispatch work to them from the Shikki CLI. The user must manually open LM Studio, paste context, and copy results back.

## Synthesis

**Goal**: `shi bg "prompt"` spawns an autonomous background node that uses local LLM, recovers context from ShikiDB, processes the prompt, persists the result, and notifies the main session — all without consuming cloud API tokens.

**Scope**:
- `BackgroundNode` actor: lifecycle management, LMStudioProvider integration, ShikiDB context recovery
- `BackgroundTaskStore`: ShikiDB-backed persistence for bg tasks and results
- CLI subcommands: `shi bg "prompt"`, `shi bg list`, `shi bg show <id>`, `shi bg cancel <id>`
- tmux status pane: persistent bg task tracker
- NATS notification: `shikki.bg.result.{taskId}` event on completion
- Overlay display: keybind-triggered popup showing bg results

**Out of scope**:
- Multi-turn bg conversations (single prompt/response only for v1)
- Bg nodes using cloud providers (local LLM only — this is the contract)
- Automatic prompt routing (user explicitly chooses `shi bg` vs normal prompt)

**Dependencies**:
- `LMStudioProvider` (exists)
- `FallbackProviderChain` (exists — bg nodes use local-only chain)
- `NATSDispatcher` (exists — extend with `shikki.bg.*` subjects)
- ShikiDB `shiki_save_event` / `shiki_get_context` (exists)

## Business Rules

```
BR-01: bg nodes MUST use LMStudioProvider exclusively — never Claude or any cloud provider
BR-02: Context MUST be recovered from ShikiDB (shiki_get_context + shiki_search), never from the current Claude session
BR-03: Results MUST be saved to ShikiDB as bg_result event type with full prompt, response, model, and duration
BR-04: Main node MUST be notified via NATS subject shikki.bg.result.{taskId} when a bg task completes
BR-05: A persistent tmux pane MUST track all bg tasks for the session: id, status (queued/running/done/failed), elapsed time
BR-06: bg tasks MUST survive session restart — state persisted in ShikiDB, resumable on next shi launch
BR-07: Maximum parallel bg tasks is configurable (default: 3) — additional tasks queue with FIFO ordering
BR-08: CLI MUST support: shi bg "prompt", shi bg list, shi bg show <id>, shi bg cancel <id>
BR-09: Results overlay MUST be accessible via configurable keybind (default: Ctrl+B g) in tmux
BR-10: bg results MUST have a TTL (default: 24h, configurable via settings.json) — expired results are pruned from ShikiDB
```

## CLI Interface

```bash
shi bg "analyze the security of our NATS auth"       # → bg#1 queued (model: qwen2.5-coder-32b)
shi bg --project shikki "review PluginRegistry"       # → bg#2 queued (context: 5 memories)
shi bg list                                           # table: id, status, prompt, elapsed
shi bg show 1                                         # full result in pager (bat/less)
shi bg cancel 3                                       # → bg#3 cancelled
```

## tmux Pane Design

The bg status pane sits in the existing Shikki tmux layout (bottom-right, 3 lines tall):

```
┌─ bg tasks ──────────────────────────────────┐
│ #1 ✓ done   2m14s  security of NATS auth    │
│ #2 ⟳ run    0m47s  PluginRegistry injection  │
│ #3 ◌ queue  —      event bus vs jetstream    │
└─────────────────────────────────────────────┘
```

Updates via NATS `shikki.bg.progress.{taskId}` — no polling.

## Architecture

```
shi bg "prompt" → CLI generates taskId (UUID), saves to ShikiDB (queued), publishes NATS shikki.bg.submit
  → BackgroundNode actor: shiki_get_context + shiki_search → builds system prompt → LMStudioProvider.complete
  → On completion: saves bg_result to ShikiDB, publishes shikki.bg.result.{taskId}
  → tmux pane subscribes to shikki.bg.result.* / shikki.bg.progress.*, updates status live
  → Ctrl+B g overlay renders full result with bat/less
```

## TDDP — Test-Driven Development Plan

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-03 | Core (80%) | Unit | When submitting bg task → saved queued + ID returned |
| T-02 | BR-01 | Security (100%) | Unit | When executing → LMStudioProvider only, zero cloud calls |
| T-03 | BR-02 | Core (80%) | Unit | When executing → shiki_get_context called before LLM |
| T-04 | BR-04 | Core (80%) | Unit | When task completes → NATS event published |
| T-05 | BR-07 | Core (80%) | Unit | When max parallel exceeded → queued FIFO |
| T-06 | BR-08 | Smoke (CLI) | Unit | When cancel → status "cancelled", task aborted |
| T-07 | BR-08 | Smoke (CLI) | Unit | When list → all tasks sorted by submission time |
| T-08 | BR-10 | Core (80%) | Unit | When TTL expired → excluded from list, pruned |
| T-09 | BR-06 | Core (80%) | Integration | When session restarts → bg task resumed from ShikiDB |
| T-10 | BR-05 | Smoke (CLI) | Integration | When NATS event received → tmux pane updates |

### S3 Test Scenarios

```
T-01 [BR-03, Core 80%]:
When submitting a bg task with a valid prompt:
  → task saved to ShikiDB with status "queued"
  → task ID returned (UUID format)
  → model field set to LM Studio model name

T-02 [BR-01, Security 100%]:
When BackgroundNode executes a prompt:
  if LMStudioProvider is available:
    → uses LMStudioProvider exclusively
    → NO cloud provider called (mock verifies zero Claude API calls)
  otherwise:
    → task queued with status "waiting_for_provider"

T-03 [BR-02, Core 80%]:
When BackgroundNode starts processing:
  → shiki_get_context called with correct project ID
  → shiki_search called with prompt keywords
  → recovered context injected as system prompt before LLM call

T-04 [BR-04, Core 80%]:
When bg task completes successfully:
  → NATS event published on shikki.bg.result.{taskId}
  → event payload contains: taskId, response, model, duration
  → bg_result saved to ShikiDB

T-05 [BR-07, Core 80%]:
When 4th bg task submitted with maxParallel=3:
  → 4th task status is "queued" (not "running")
  → when slot opens (task 1 completes):
    → 4th task transitions to "running" (FIFO)

T-06 [BR-08, Smoke CLI]:
When running shi bg cancel 2:
  → task #2 status set to "cancelled" in ShikiDB
  → running Task aborted (if in progress)
  → tmux pane shows "#2 ✗ cancelled"

T-07 [BR-08, Smoke CLI]:
When running shi bg list:
  → all tasks for current session returned
  → sorted by submission time ascending
  → columns: id, status, elapsed, prompt (truncated)

T-08 [BR-10, Core 80%]:
When bg results older than TTL (24h default):
  → excluded from shi bg list output
  → pruned from ShikiDB on next shi launch

T-09 [BR-06, Core 80%]:
When session crashes and restarts:
  → ShikiDB queried for tasks with status "running" or "queued"
  → "running" tasks reset to "queued" (retry)
  → BackgroundNode resumes processing queue

T-10 [BR-05, Smoke CLI]:
When NATS shikki.bg.result.{taskId} event received:
  → tmux bg pane updates task row: "⟳ run" → "✓ done"
  → elapsed time finalized
```

## Wave Dispatch Tree

```
Wave 1: Core Engine
  ├── BackgroundTask model (no deps)
  ├── BackgroundTaskStore (depends: ShikiDB)
  ├── BackgroundNode actor (depends: LMStudioProvider, BackgroundTaskStore)
  └── ConcurrencyLimiter (depends: BackgroundTaskStore)
  Tests: T-01, T-02, T-03, T-05, T-08
  Gate: swift test --filter Background → all green

Wave 2: CLI + NATS ← BLOCKED BY Wave 1
  ├── BackgroundCommand (depends: BackgroundNode, BackgroundTaskStore)
  ├── NATS bg subjects (depends: NATSDispatcher)
  └── Result notification (depends: BackgroundNode, NATS)
  Tests: T-04, T-06, T-07, T-09
  Gate: swift test --filter Background → all green + shi bg "ping" returns result

Wave 3: tmux + Overlay ← BLOCKED BY Wave 2
  ├── tmux pane renderer (depends: NATS bg subscription)
  ├── Overlay popup (depends: BackgroundTaskStore.list)
  └── Settings integration (depends: AppConfig)
  Tests: T-10
  Gate: full swift test green + manual tmux verification
```

## Implementation Waves

### Wave 1: Core Engine — BackgroundTask + BackgroundNode + Store
**Files:** `Kernel/Core/BackgroundTask.swift`, `Kernel/Core/BackgroundTaskStore.swift`, `Kernel/Core/BackgroundNode.swift`, `Kernel/Core/ConcurrencyLimiter.swift`
**Tests:** `Tests/BackgroundNodeTests.swift` (T-01, T-02, T-03, T-05, T-08)
**Deps:** LMStudioProvider (exists), ShikiDB (exists)
**Gate:** `swift test --filter Background` green

### Wave 2: CLI + NATS ← blocked by W1
**Files:** `Commands/BackgroundCommand.swift`, extend `NATSDispatcher` with bg subjects
**Tests:** `Tests/BackgroundCommandTests.swift` (T-04, T-06, T-07, T-09)
**Deps:** Wave 1, NATSDispatcher (exists)
**Gate:** `swift test --filter Background` green + `shi bg "ping"` E2E

### Wave 3: tmux + Overlay ← blocked by W2
**Files:** `TUI/BackgroundStatusPane.swift`, `TUI/BackgroundOverlay.swift`
**Tests:** T-10 (integration)
**Deps:** Wave 2, TUI primitives (exist)
**Gate:** full `swift test` green + manual tmux

## Reuse Audit

| Utility / Pattern | Exists In | Decision |
|---|---|---|
| `LMStudioProvider` | `ShikkiKit/Providers/LMStudioProvider.swift` | Reuse as-is |
| `FallbackProviderChain` | `ShikkiKit/Providers/FallbackProviderChain.swift` | Reuse with local-only config |
| `NATSDispatcher` | `ShikkiKit/NATS/NATSDispatcher.swift` | Extend with `shikki.bg.*` subjects |
| ShikiDB event persistence | `shiki_save_event` MCP tool | Reuse as-is |
| tmux pane rendering | `ShikkiKit/TUI/` | Reuse existing pane primitives |
| ArgumentParser subcommand | `Commands/` | Follow existing command patterns |
