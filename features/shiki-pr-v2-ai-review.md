# Feature: `shiki pr` v2 — AI-Augmented Code Review System

> **Status**: Spec (pending validation)
> **Author**: @Sensei + @Hanami + @Kintsugi (team challenge)
> **Date**: 2026-03-17
> **Scope**: Shiki CLI (`tools/shiki-ctl`), ShikiCtlKit, ShikiKit (events)
> **Dependencies**: delta (external), fzf (external), qmd (external)
> **Blocks**: Team onboarding, large PR review workflow

---

## 1. Problem Statement

The current PR review process doesn't scale:

- **50k+ line PRs** are unreadable linearly — senior engineers scan by smell, not by file order
- **Review generates feedback but not fixes** — gh-dash/diffnav let you approve, not act
- **No semantic search** — grep finds keywords, not intent ("all auth changes")
- **No AI context during review** — the agent that could fix what you found can't see what you see
- **Single-user today, multi-user tomorrow** — need to overview what team members + AI agents produce
- **Events die in the terminal** — no way to observe, subscribe, or react from other tools

## 2. Vision

**Shiki as an observable data stream.** Every action (agent writes code, human reviews, fix spawns) is a `ShikiEvent`. Tools subscribe to the stream at different depths:

| Depth | Tool | What they see |
|-------|------|--------------|
| Glance | ntfy / status bar | System healthy? Agents running? |
| Scan | TUI dashboard / native app | What each agent does, risk heat map |
| Watch | Pinned preview panel | Live stream of one agent's actions |
| Intervene | Inline prompt / course-correct | Redirect agent mid-work |

The PR review TUI is the first **Watch + Intervene** subscriber. Same event protocol powers future subscribers (native app, web dashboard, team view).

## 3. Architecture

### 3.1 Event Protocol (ShikiKit)

```
ShikiEvent (Codable, Sendable)
  ├── id: UUID
  ├── timestamp: Date
  ├── source: EventSource       // .agent(id), .human, .orchestrator, .process
  ├── type: EventType            // .codeChange, .reviewVerdict, .riskAssessment,
  │                              //  .searchQuery, .fixSpawned, .courseCorrect, ...
  ├── scope: EventScope          // .pr(number), .session(id), .project(slug)
  ├── payload: [String: AnyCodable]
  └── metadata: EventMetadata    // branch, file, line range (optional)

EventBus (protocol)
  ├── publish(_ event: ShikiEvent)
  ├── subscribe(filter: EventFilter) -> AsyncStream<ShikiEvent>
  └── unsubscribe(_ id: SubscriptionID)

Transport (protocol)  // abstracted — swap without changing subscribers
  ├── LocalPipe       // in-process (TUI, current)
  ├── UnixSocket      // SwiftNIO (native app, future)
  ├── WebSocket       // browser dashboard (future)
  └── Shiki DB        // persistent subscriber (already partial via agent_events)
```

**Decision**: ShikiEvent goes into `packages/ShikiKit` (already exists on `story/swift-platform-migration`). This makes it available to the CLI, future native app, and any Swift consumer.

### 3.2 PR Cache Engine

```
docs/pr<N>-cache/
  ├── meta.json          # PR metadata (branch, files, stats, timestamps)
  ├── diff.md            # Full diff, file-by-file, method signatures extracted
  ├── files.json         # File list: path, +/-, category, risk score
  ├── methods.json       # Changed methods: name, file, line, before/after sig
  ├── risk-map.json      # AI risk assessment per file
  └── review-state.json  # Human verdicts, comments, progress (already exists)
```

**Rebuild flow**: `shiki pr <N> --build` generates the cache. `--rebuild` re-generates only files that changed since last build (diffstat comparison). The cache IS the qmd collection — indexed once, queried many times.

### 3.3 Search Layer (qmd)

```
shiki pr <N> --build
  → generates diff.md + files.json + methods.json
  → qmd collection add docs/pr<N>-cache/ --name pr-<N>
  → qmd embed (generate vectors, ~30s for 50k lines)
  → indexed, ready for queries

During review:
  '/' key → qmd query "authentication error handling"
            → returns ranked file list with relevance scores
  'i' key → AI asks qmd via MCP for context about selected file
  'F' key → fix agent gets qmd as context source
```

**MCP integration**: qmd exposes `query`, `get`, `multi_get` via MCP. Claude agents call these natively during fix work — no manual file reading, no token waste on irrelevant code.

### 3.4 Risk Triage Engine

AI-generated risk assessment per file, produced during `--build`:

```
Risk levels:
  🔴 HIGH   — architecture change, API contract, no tests, complexity spike
  🟡 MEDIUM — new dependency, large file, naming drift, test gap
  🟢 LOW    — config, docs, models, well-tested changes
  ⚪ SKIP   — generated code, lock files, assets

Risk signals (computed, not guessed):
  - Cyclomatic complexity delta (before/after)
  - Test coverage gap (changed code without corresponding test changes)
  - Dependency introduction (new import statements)
  - File size anomaly (>500 lines or >2x growth)
  - Method signature changes (public API surface)
  - Cross-file coupling (file touches 3+ other changed files)
```

The risk map is the **default view**. Senior engineer scans red → yellow, skips green. Promotes/demotes based on gut feeling. This is the "smell" workflow made explicit.

### 3.5 Key Mode System

```swift
enum KeyMode: String, Codable, Sendable {
    case emacs   // Ctrl-n/p/f/b/v, Ctrl-s, Meta-v
    case vim     // j/k/h/l/g/G, Ctrl-d/u, /
    case arrows  // Arrow keys, Enter, Escape (current v1)
}
```

Config file: `~/.config/shiki/review.yml`

```yaml
keyMode: emacs
editor: $EDITOR
diffTool: delta
fuzzyFinder: fzf
searchEngine: qmd
defaultView: risk-map    # risk-map | section-list | file-list
```

### 3.6 External Tool Integration

| Key | Tool | Integration |
|-----|------|------------|
| `d` | delta | `git diff <base>...<head> -- <file> \| delta` |
| `f` | fzf | Pipe file list + method list → fzf → jump to selection |
| `/` | qmd | `qmd query "<input>" --collection pr-<N> --json` → ranked results |
| `o` | $EDITOR | Open file at changed line number |
| `g` | rg | `rg <pattern>` across all changed files |

Each integration is a `Process.run()` call — 5-15 lines. External tools are optional; if missing, the feature degrades gracefully (fzf missing → numbered list fallback, delta missing → raw diff, qmd missing → rg fallback).

### 3.7 AI Fix Agent

From the review TUI, press `F` on any file:

```
1. Create git worktree: .claude/worktrees/pr<N>-fix-<file>
2. Spawn Claude agent with context:
   - The review doc (pr<N>-review.md)
   - Your comments/verdicts so far
   - The specific file + surrounding context (via qmd multi_get)
   - The risk assessment for that file
3. Agent works in the worktree (doesn't touch your branch)
4. Emits ShikiEvents: fix_started, code_change, fix_completed
5. TUI shows progress indicator on the file row
6. When done: "Fix ready for <file> — [Enter] to see diff, [m] to merge"
```

**Course correction**: While the fix agent runs, press `i` to inject a prompt. This emits a `course_correct` event that the agent subscribes to (via the event bus).

## 4. Phases

### Phase 1: Foundation — Cache + Risk + Key Modes (~400 lines, 1-2 days)

**New files:**
- `ShikiCtlKit/Services/PRCacheBuilder.swift` (~150 lines) — generate diff.md, files.json, methods.json from git diff
- `ShikiCtlKit/Services/PRRiskEngine.swift` (~100 lines) — compute risk scores per file from diff stats + heuristics
- `ShikiCtlKit/TUI/KeyMode.swift` (~80 lines) — key mode abstraction, emacs/vim/arrows mappings
- `ShikiCtlKit/Services/PRConfig.swift` (~40 lines) — load ~/.config/shiki/review.yml

**Modified files:**
- `PRCommand.swift` — add `--build`, `--rebuild` flags
- `PRReviewEngine.swift` — accept risk map, sort by risk
- `PRReviewRenderer.swift` — risk heat map view, key mode hints in footer
- `TerminalInput.swift` — key mode dispatch

**Tests:**
- `PRCacheBuilderTests.swift` — parse git diff output, generate file list
- `PRRiskEngineTests.swift` — risk scoring heuristics
- `KeyModeTests.swift` — emacs/vim/arrows all map to same abstract actions

**Verification:**
- `shiki pr 5 --build` generates cache directory
- `shiki pr 5` shows risk-first view with colored heat map
- Emacs keys work: Ctrl-n/p navigate, Ctrl-v pages

### Phase 2: External Tools — delta + fzf + qmd (~200 lines, 1 day)

**New files:**
- `ShikiCtlKit/Services/ExternalTools.swift` (~120 lines) — tool detection, shell-out helpers, graceful degradation
- `ShikiCtlKit/Services/QMDClient.swift` (~80 lines) — qmd CLI wrapper: collection add, embed, query, get

**Modified files:**
- `PRCommand.swift` — auto-index qmd collection on `--build`
- `PRReviewEngine.swift` — new screen states: `.search`, `.diffView`
- `PRReviewRenderer.swift` — search results view, diff viewer integration

**Tests:**
- `ExternalToolsTests.swift` — tool detection, graceful fallback
- `QMDClientTests.swift` — parse qmd JSON output

**Verification:**
- `d` on a file opens delta with syntax-highlighted diff
- `f` opens fzf with all changed files + methods
- `/` triggers qmd semantic search → ranked results
- Missing tools don't crash — fallback to basic alternatives

### Phase 3: AI Fix Agent (~250 lines, 1-2 days)

**New files:**
- `ShikiCtlKit/Services/PRFixAgent.swift` (~150 lines) — worktree creation, agent spawning, context injection, progress tracking
- `ShikiCtlKit/Models/ShikiEvent.swift` (~100 lines) — event protocol (first draft, moves to ShikiKit later)

**Modified files:**
- `PRReviewEngine.swift` — fix states: `.fixRunning(file)`, `.fixComplete(file)`
- `PRReviewRenderer.swift` — progress indicators, fix result preview
- `PRCommand.swift` — `--fix <file>` standalone mode

**Tests:**
- `PRFixAgentTests.swift` — worktree creation, context assembly, event emission
- `ShikiEventTests.swift` — event serialization, filter matching

**Verification:**
- `F` on a file spawns agent in worktree
- TUI shows spinner while fix runs
- Fix complete → diff preview available inline
- `i` during fix sends course-correct prompt

### Phase 4: Event Architecture Formalization (~200 lines, 1 day)

**New files:**
- `ShikiCtlKit/Events/EventBus.swift` (~80 lines) — in-process event bus with AsyncStream subscribers
- `ShikiCtlKit/Events/EventLogger.swift` (~60 lines) — persistent subscriber → Shiki DB
- `ShikiCtlKit/Events/LocalTransport.swift` (~40 lines) — in-process pipe (first transport)

**Modified files:**
- `PRReviewEngine.swift` — emit events for all state transitions
- `PRFixAgent.swift` — emit events for fix lifecycle
- `PRCacheBuilder.swift` — emit events for cache build progress
- `HeartbeatLoop.swift` — migrate existing agent_events to ShikiEvent

**Tests:**
- `EventBusTests.swift` — publish/subscribe, filter, multiple subscribers

**Verification:**
- All PR review actions emit ShikiEvents
- Events logged to Shiki DB (replaces raw agent_events)
- Multiple subscribers receive same events

### Phase 5: Large PR Optimization (~200 lines, 1 day)

**Improvements:**
- `PRCacheBuilder.swift` — chunked AI processing (20 files/batch)
- `QMDClient.swift` — incremental re-index (only changed files)
- `PRRiskEngine.swift` — method-level risk (not just file-level)
- `PRReviewEngine.swift` — lazy section loading (don't parse all bodies upfront)

**New files:**
- `ShikiCtlKit/Services/PRMethodIndex.swift` (~100 lines) — extract method signatures, build searchable index

**Tests:**
- `PRMethodIndexTests.swift` — Swift/Go/TS method extraction

**Verification:**
- 50k-line PR builds cache in <30s
- Rebuild after fix touches only changed files
- Method-level search works: `/ "handleStaleCompany"` → exact jump

### Phase 6: Polish + Team Readiness (~150 lines, 1 day)

- Configurable review.yml loaded on startup
- `shiki pr --list` shows all cached PRs with review progress
- `shiki pr <N> --export` generates review summary markdown (for sharing)
- `shiki pr <N> --assign <person>` tags sections for specific reviewers (future team use)
- Help overlay (`?` key) showing all keybindings for current mode
- Zsh completions updated for new flags

## 5. Scope Summary

| Phase | New Files | Lines (est.) | External Deps |
|-------|-----------|-------------|---------------|
| 1. Cache + Risk + Keys | 4 new, 4 modified | ~400 | none |
| 2. External Tools | 2 new, 3 modified | ~200 | delta, fzf, qmd |
| 3. AI Fix Agent | 2 new, 3 modified | ~250 | claude (worktree) |
| 4. Event Architecture | 3 new, 4 modified | ~200 | none |
| 5. Large PR Optimization | 1 new, 4 modified | ~200 | none |
| 6. Polish + Team | 0 new, 6 modified | ~150 | none |
| **Total** | **12 new, ~15 modified** | **~1,400** | delta, fzf, qmd |

## 6. External Dependencies

| Tool | Required? | Install | Fallback |
|------|-----------|---------|----------|
| delta | Recommended | `brew install git-delta` | Raw `git diff` output |
| fzf | Recommended | `brew install fzf` | Numbered list + readLine |
| qmd | Recommended | `npm install -g @tobilu/qmd` | `rg` keyword search |

All are optional. `shiki pr` works without any of them (degrades to current v1 behavior). Each tool unlocks a capability layer.

## 7. Migration from v1

v1 (`shiki pr <N>`) continues to work unchanged:
- Reads `docs/pr<N>-review.md` → structured sections → TUI
- v2 adds `--build` to generate cache + risk map
- If cache exists, default view becomes risk-map
- If no cache, falls back to section list (v1 behavior)

No breaking changes. v1 is a subset of v2.

## 8. Future: Beyond CLI

The event architecture enables:

| Subscriber | Transport | When |
|-----------|-----------|------|
| TUI (shiki pr) | LocalPipe | Now |
| Shiki DB logger | LocalPipe | Phase 4 |
| Native macOS app | UnixSocket (SwiftNIO) | After orchestrator v3 |
| Web dashboard | WebSocket | When team grows |
| Mobile (Watch) | Push via ntfy | Already partial |
| Team member view | WebSocket + auth | When onboarding starts |

The protocol is the same. Only the transport changes.

## 9. Success Criteria

1. `shiki pr 5 --build` generates cache + risk map in <10s for current PR size
2. Risk-first view lets senior engineer focus on 3-5 red files out of 28
3. `qmd query` returns semantically relevant results from PR code
4. `F` spawns fix agent that produces working code in worktree
5. All actions emit ShikiEvents that persist to DB
6. Full review of a 50-file PR takes <15 minutes (vs current ~45 min reading linearly)
7. Emacs keybindings work as default

## 10. Decisions (closed 2026-03-17)

- [x] **Risk scoring**: CLI shell-out to `qmd query` with `--json`. qmd already has llama.cpp locally — use it. No Claude API call for risk scoring (saves tokens, works offline). If qmd isn't installed, fall back to heuristics-only (file size, +/- ratio, test gap detection).

- [x] **Event bus persistence**: In-memory first (`InProcessEventBus` actor), persist to Shiki DB via `ShikiDBEventLogger` subscriber (HTTP POST to `/api/data-sync`). No local SQLite for events — the DB is already there, don't duplicate storage. If DB is down, events still flow locally and are lost on exit. Acceptable — the TUI is the primary consumer, DB is best-effort history.

- [x] **qmd integration**: CLI shell-out (`Process.run()`), not MCP daemon. Reason: same philosophy as delta/fzf — external tool, not a dependency. `qmd query "..." --collection pr-N --json` piped through our parser. If MCP proves faster for AI agents later, add daemon mode as an option in `review.yml`, don't make it default.

- [x] **Fix agent**: Use Claude Code's native worktree feature (`EnterWorktree` tool). Don't build custom worktree management — Claude Code already handles creation, branch isolation, and cleanup. The fix command composes: assemble context (review state + file + qmd results) → spawn subagent with `isolation: "worktree"` → monitor via event bus.
