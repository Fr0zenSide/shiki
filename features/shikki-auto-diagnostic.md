---
title: "Shikki Auto Diagnostic + Context Recovery from ShikiDB"
status: validated
priority: P1
project: shikki
created: 2026-03-26
validated: 2026-03-26
co-designed-with: "@Daimyo + @Sensei + @Hanami + @Ronin + @Kintsugi"
depends-on:
  - ShikkiDoctor (existing)
  - CheckpointManager (existing)
  - DBSyncClient (existing)
  - BackendClient (existing)
  - RecoveryManager (existing)
  - ShikkiEvent bus (existing)
---

# Shikki Auto Diagnostic + Context Recovery

## Vision

When Shikki restarts or an agent loses context, the system should be able to reconstruct what was happening by reading its own history from ShikiDB. Today `shikki doctor` checks environment health (binaries, docker, disk, git) but knows nothing about *what you were working on*. This feature adds **context recovery** — the ability to read ShikiDB events, session transcripts, checkpoints, and git state, then rebuild a coherent snapshot of recent work.

The output serves two audiences: the human operator ("what was I doing?") and the agent ("inject this context so I can resume").

---

## Phase 1 — Inspiration (Brainstorm)

### @Sensei (Architecture) — 3 Ideas

| # | Idea | Detail |
|---|------|--------|
| S1 | **Three-Layer Recovery Chain** | Query in order: (1) ShikiDB `agent_events` table — richest data (events, transcripts, decisions), (2) local checkpoint at `~/.shikki/checkpoint.json` — last known FSM state + context snippet, (3) git workspace — recent commits, dirty files, worktrees. Each layer has a confidence score. The output merges all three, deduplicating by timestamp. If DB is down, layers 2+3 still produce useful context. |
| S2 | **Time-Windowed Event Query** | New `GET /api/events?since=<ISO8601>&until=<ISO8601>&types=<csv>` endpoint on the backend. Default window: 2 hours. The diagnostic service queries this, groups events by scope (session/project), and builds a timeline. Heavy events (raw logs, large payloads) are excluded by default — only summaries. A `--verbose` flag pulls full payloads. |
| S3 | **Agent-Optimized Context Injection** | The `--format agent` output produces a compact XML/markdown block designed to be pasted into an agent's system prompt. Structure: `<context-recovery>` with sections for active-branch, last-N-commits, pending-decisions, open-PRs, recent-errors. Token budget: ~2KB default (fits in any model's context). `--budget 4k` flag to expand. This is what `shikki` auto-injects on startup when it detects a stale checkpoint. |

### @Hanami (UX) — 2 Ideas

| # | Idea | Detail |
|---|------|--------|
| H1 | **Progressive Disclosure Output** | Default human output shows a compact summary: state, branch, last 3 events, any errors. Pipe-friendly — no ANSI when stdout is not a TTY. Add `--detail` for full timeline. The summary uses the same attention-zone coloring as the dashboard (bright = recent, dim = older). Clipboard integration: `shikki diagnostic \| pbcopy` works cleanly, or `--copy` flag to auto-copy. |
| H2 | **Recovery Confidence Indicator** | Show a visual confidence meter: "Context recovery: [=====-----] 52% (DB partial, checkpoint stale 4h, git clean)". Each source contributes a weighted score. If confidence < 30%, suggest `shikki doctor --fix` to re-sync. This helps the user decide whether to trust the recovered context or start fresh. |

### @Ronin (Adversarial) — 3 Concerns

| # | Concern | Mitigation |
|---|---------|------------|
| R1 | **DB Corrupted or Returning Garbage** | Events from DB must be validated: check `id` is UUID, `timestamp` is parseable, `type` is known enum. Unknown event types are logged but skipped (forward compatibility). If >50% of events fail validation, mark DB source as "corrupted" and fall through to checkpoint+git. Never crash on bad data. |
| R2 | **Stale Context Injection Causes Wrong Decisions** | Every recovered context block includes a `recovered_at` timestamp and a `staleness` indicator (e.g., "2h old" / "24h old — STALE"). Agents must see this. If context is >6h old, the agent format includes a warning: `<!-- STALE CONTEXT: last activity 6h+ ago. Verify before acting. -->`. The `--from` flag is capped at 7 days to prevent archaeology. |
| R3 | **Git Fallback Leaks Sensitive Data** | When falling back to git, only read: branch name, commit messages, file paths changed (not diffs), worktree list. Never read file contents or `.env` files. The `--format json` output must not include diff hunks. Commit messages are the richest safe signal. |

### @Kintsugi (Philosophy) — 1 Idea

| # | Idea | Detail |
|---|------|--------|
| K1 | **Kintsugi for Knowledge — Repairing Memory with Gold** | A broken session is not a failure — it is an opportunity to rebuild with visible seams. The diagnostic output should not pretend continuity. It should explicitly show the gaps: "Events from 14:32 to 15:10 are missing (DB was unreachable)." The golden repair is the act of recovery itself: each gap is annotated with what source filled it (checkpoint, git, inference). This makes the recovery *trustworthy* — you see exactly what is real data and what is reconstructed. The `provenance` field on each recovered item (`db`, `checkpoint`, `git`, `inferred`) is the gold in the cracks. |

---

## Phase 2 — Synthesis

### Feature Brief

**Name:** `shikki diagnostic` (also accessible as `shikki doctor --context`)

**One-liner:** Recover recent work context from ShikiDB, local checkpoints, and git — for humans and agents.

### Scope v1

- New `DiagnosticCommand` subcommand with `--from`, `--format`, `--copy`, `--verbose` flags
- `ContextRecoveryService` in ShikkiKit: three-layer recovery chain (DB -> checkpoint -> git)
- New backend endpoint `GET /api/events` with time window and type filtering
- Three output formats: `human` (default), `agent` (compact injection block), `json` (machine-readable)
- Confidence scoring per source and overall
- Provenance tagging on every recovered item
- Staleness warnings for old context
- Auto-TTY detection (no ANSI when piped)
- `--copy` flag for clipboard (macOS `pbcopy`)
- Integration with `ShikkiEngine.dispatch()`: on resume, auto-run diagnostic and inject into welcome message

### Scope v1.1 (follow-up)

- Backend `GET /api/memories/search` integration for semantic context (beyond event timeline)
- `shikki diagnostic --inject` to auto-pipe into a running agent session
- Persistent recovery log: every diagnostic run saved to `~/.shikki/recovery-log.jsonl` for audit
- `--diff` mode: compare two time windows ("what changed between yesterday and now")
- ShikkiMCP tool for `diagnostic` (agents call it directly without CLI)

### Success Criteria

1. `shikki diagnostic` returns context within 2 seconds when DB is healthy
2. `shikki diagnostic` returns context within 500ms when DB is down (checkpoint+git fallback)
3. Agent-format output fits within 2KB by default (configurable to 4KB)
4. Zero crashes on corrupted/missing/partial data from any source
5. Confidence score accurately reflects data quality (tested with synthetic scenarios)
6. `shikki diagnostic --format json | jq .` produces valid JSON in all cases

---

## Phase 3 — Business Rules

### Context Retrieval

**BR-01:** The default time window is 2 hours from the current time. The `--from` flag accepts durations: `2h`, `24h`, `30m`, `3600s`, `7d`. Maximum allowed: `7d` (168 hours). Values above 7d are clamped with a warning.

**BR-02:** The recovery chain executes in order: (1) ShikiDB events API, (2) local checkpoint file, (3) git workspace. Each source runs independently — a failure in one does not block the others.

**BR-03:** Each recovered item carries a `provenance` field: `.db`, `.checkpoint`, `.git`, or `.inferred`. Inferred items are synthesized from combining partial data (e.g., a git commit that matches a DB event timestamp).

**BR-04:** The backend `GET /api/events` endpoint accepts query parameters: `since` (ISO8601), `until` (ISO8601, default: now), `types` (comma-separated EventType values), `scope` (EventScope filter), `limit` (default: 200, max: 1000).

**BR-05:** Events are deduplicated by `id` (UUID). If the same event appears in DB and local cache, the DB version wins (richer metadata).

### Time Windows

**BR-06:** Duration parsing supports: `Nh` (hours), `Nm` (minutes), `Ns` (seconds), `Nd` (days). Invalid formats produce a clear error message with examples.

**BR-07:** When `--from` is not specified, the service checks the local checkpoint timestamp. If a checkpoint exists and is newer than 2h, the window starts from the checkpoint's `timestamp` minus 10 minutes (overlap for context). If no checkpoint or checkpoint is older than 2h, the default 2h window applies.

### Output Formats

**BR-08:** `--format human` (default): ANSI-colored output with sections: State, Branch, Timeline (last N events), Errors, Pending Decisions, Confidence. When stdout is not a TTY, ANSI codes are stripped automatically.

**BR-09:** `--format agent`: Compact markdown block wrapped in `<context-recovery>` tags. Sections: active-branch, recent-commits (last 5), recent-events (last 10, one-line each), pending-decisions, errors. Total output capped at 2KB by default. `--budget <size>` overrides (e.g., `--budget 4k`).

**BR-10:** `--format json`: Full structured output. Root object with `recoveredAt`, `timeWindow`, `confidence`, `sources` (array of source results), `timeline` (merged event list), `workspace` (git state). Must be valid JSON in all cases — errors are included as `"errors": [...]` field, never printed to stdout.

**BR-11:** `--verbose` flag: In human format, shows full event payloads. In agent format, increases budget to 4KB. In JSON format, includes raw event payloads (normally summarized).

### Fallback Chain

**BR-12:** ShikiDB is queried with a 3-second timeout (matches `DBSyncClient.timeoutSeconds`). If the request fails or times out, the DB source is marked as `unavailable` and the chain continues.

**BR-13:** Local checkpoint fallback reads `~/.shikki/checkpoint.json` via `CheckpointManager.load()`. Extracts: FSM state, branch, context snippet, session stats, tmux layout.

**BR-14:** Git fallback collects: current branch name, last N commit messages (default: 10) with timestamps and authors, list of modified/untracked files (paths only, no content), list of active worktrees with their branches, ahead/behind counts vs remote.

**BR-15:** If all three sources fail (DB unreachable, no checkpoint, not a git repo), the command outputs a minimal diagnostic: "No context available. Run `shikki doctor` to check environment health." Exit code 0 (not an error — absence of context is a valid result).

### Confidence Scoring

**BR-16:** Confidence is a percentage (0-100) computed as weighted sum: DB events (50%), checkpoint (30%), git (20%). Each source scores 0 (unavailable/empty) to 100 (rich data within time window). Overall = weighted average.

**BR-17:** DB source score: 100 if >10 events in window, 70 if 1-10 events, 0 if unreachable or empty.

**BR-18:** Checkpoint source score: 100 if checkpoint exists and is within time window, 50 if checkpoint exists but is older than window, 0 if no checkpoint.

**BR-19:** Git source score: 100 if commits exist in window, 50 if dirty working tree (activity but no commits), 0 if clean and no recent commits.

### Staleness

**BR-20:** Every output format includes a staleness indicator. Fresh: <1h since last event. Recent: 1-6h. Stale: 6-24h. Ancient: >24h.

**BR-21:** In agent format, if staleness is "stale" or "ancient", a warning comment is prepended: `<!-- WARNING: Context is {N}h old. Verify current state before acting. -->`.

### Injection into Agents

**BR-22:** When `ShikkiEngine.dispatch()` returns `.resume(checkpoint)`, the engine calls `ContextRecoveryService.recover(from: checkpoint.timestamp)` and passes the agent-format output to `WelcomeRenderer` for display. The agent-format block is also written to `~/.shikki/last-recovery.md` for manual inspection.

**BR-23:** The `--copy` flag pipes the output through `pbcopy` (macOS). If `pbcopy` is not available (Linux), falls back to writing to `~/.shikki/last-recovery.md` and printing the path.

### Data Safety

**BR-24:** Git fallback never reads file contents, diffs, or environment files. Only: branch names, commit messages, file paths, worktree metadata.

**BR-25:** The `--format json` output never includes raw file contents. Commit messages are the richest text included from git.

**BR-26:** Event payloads from DB are included in full only with `--verbose`. Default: payload keys are listed but values are summarized (string length, number value, bool).

### Error Handling

**BR-27:** The command never crashes. All errors are caught and reported in the output. Exit code 0 for successful recovery (even if partial). Exit code 1 only for argument parsing errors.

**BR-28:** If DB returns HTTP errors, the error code and message are included in the output under a `"dbError"` field (JSON) or a dimmed line (human format). Never silent failure (no `curl -sf`).

---

## Phase 4 — Test Plan

### Context Retrieval Tests

```swift
// ContextRecoveryServiceTests.swift

@Test func recoverFromDB_returnsEventsWithinTimeWindow()
@Test func recoverFromDB_excludesEventsOutsideWindow()
@Test func recoverFromDB_deduplicatesByEventId()
@Test func recoverFromDB_provenanceIsDB()
@Test func recoverFromCheckpoint_extractsFSMState()
@Test func recoverFromCheckpoint_extractsBranchAndStats()
@Test func recoverFromCheckpoint_provenanceIsCheckpoint()
@Test func recoverFromGit_collectsRecentCommits()
@Test func recoverFromGit_collectsModifiedFiles()
@Test func recoverFromGit_collectsWorktreeList()
@Test func recoverFromGit_provenanceIsGit()
@Test func recoverFromGit_neverReadsFileContents()
@Test func recoverMergesAllSources_sortedByTimestamp()
@Test func recoverWithInferredItems_matchesGitCommitToDBEvent()
```

### Time Window Tests

```swift
// TimeWindowTests.swift

@Test func parseDuration_hours() // "2h" → 7200s
@Test func parseDuration_minutes() // "30m" → 1800s
@Test func parseDuration_seconds() // "3600s" → 3600s
@Test func parseDuration_days() // "7d" → 604800s
@Test func parseDuration_invalidFormat_throwsError()
@Test func parseDuration_exceedsMax_clampsTo7d()
@Test func defaultWindow_noCheckpoint_returns2h()
@Test func defaultWindow_freshCheckpoint_startsFromCheckpointMinus10m()
@Test func defaultWindow_staleCheckpoint_returns2h()
```

### Output Format Tests

```swift
// DiagnosticOutputTests.swift

@Test func humanFormat_includesStateAndBranch()
@Test func humanFormat_stripsANSI_whenNotTTY()
@Test func humanFormat_showsConfidenceMeter()
@Test func humanFormat_showsStalenessIndicator()
@Test func humanFormat_verbose_showsFullPayloads()

@Test func agentFormat_wrapsInContextRecoveryTags()
@Test func agentFormat_defaultBudget_under2KB()
@Test func agentFormat_customBudget_respectsLimit()
@Test func agentFormat_staleContext_includesWarningComment()
@Test func agentFormat_includesRecentCommits()
@Test func agentFormat_includesPendingDecisions()

@Test func jsonFormat_isValidJSON_always()
@Test func jsonFormat_includesRecoveredAtTimestamp()
@Test func jsonFormat_includesConfidenceScore()
@Test func jsonFormat_includesSourceResults()
@Test func jsonFormat_includesErrors_neverPrintsToStdout()
@Test func jsonFormat_verbose_includesFullPayloads()
```

### Fallback Chain Tests

```swift
// FallbackChainTests.swift

@Test func dbUnavailable_fallsToCheckpointAndGit()
@Test func dbTimeout_respectsThreeSecondLimit()
@Test func noCheckpoint_fallsToGit()
@Test func allSourcesFail_returnsMinimalDiagnostic()
@Test func allSourcesFail_exitCodeIsZero()
@Test func dbReturnsGarbage_skipsCorruptedEvents()
@Test func dbReturnsPartial_marksSourceAsPartial()
@Test func dbReturnsUnknownEventTypes_skipsGracefully()
@Test func dbEventsOverFiftyPercentInvalid_marksCorrupted()
```

### Confidence Scoring Tests

```swift
// ConfidenceScoreTests.swift

@Test func fullDB_fullCheckpoint_fullGit_returns100()
@Test func emptyDB_fullCheckpoint_fullGit_returns50()
@Test func dbOnly_tenPlusEvents_returns50()
@Test func checkpointOnly_fresh_returns30()
@Test func checkpointOnly_stale_returns15()
@Test func gitOnly_withCommits_returns20()
@Test func gitOnly_dirtyTree_returns10()
@Test func noSources_returnsZero()
@Test func weightedAverage_matchesFormula()
```

### Staleness Tests

```swift
// StalenessTests.swift

@Test func fresh_underOneHour()
@Test func recent_oneToSixHours()
@Test func stale_sixToTwentyFourHours()
@Test func ancient_overTwentyFourHours()
@Test func agentFormat_stale_includesWarning()
@Test func agentFormat_fresh_noWarning()
```

### Integration Tests

```swift
// DiagnosticIntegrationTests.swift

@Test func diagnosticCommand_defaultArgs_producesHumanOutput()
@Test func diagnosticCommand_formatJSON_producesValidJSON()
@Test func diagnosticCommand_formatAgent_producesCompactBlock()
@Test func diagnosticCommand_from24h_expandsWindow()
@Test func diagnosticCommand_copyFlag_writeToLastRecoveryFile()
@Test func engineResume_autoRunsDiagnostic()
@Test func engineResume_injectsAgentContext_intoWelcome()
@Test func pipeToShikkiCommand_worksCleanly()
```

### Data Safety Tests

```swift
// DataSafetyTests.swift

@Test func gitFallback_neverReadsFileContents()
@Test func gitFallback_neverReadsDiffs()
@Test func gitFallback_neverReadsEnvFiles()
@Test func jsonOutput_neverIncludesRawFileContents()
@Test func dbPayloads_summarizedByDefault()
@Test func dbPayloads_fullOnlyWithVerbose()
```

---

## Architecture

### New Types

```
ShikkiKit/
├── Services/
│   ├── ContextRecoveryService.swift    # Three-layer recovery chain
│   ├── DiagnosticFormatter.swift       # Human/agent/JSON output formatting
│   └── DurationParser.swift            # Parse "2h", "30m", "7d" etc.
├── Models/
│   ├── RecoveryContext.swift            # Unified recovery result model
│   ├── RecoveredItem.swift             # Single item with provenance
│   └── ConfidenceScore.swift           # Weighted confidence calculation

shikki/Commands/
└── DiagnosticCommand.swift             # CLI entry point
```

### ContextRecoveryService API

```swift
public struct ContextRecoveryService: Sendable {
    /// Recover context from all available sources.
    public func recover(
        window: TimeWindow,
        verbose: Bool = false
    ) async -> RecoveryContext

    /// Recover and format for agent injection.
    public func recoverForAgent(
        window: TimeWindow,
        budget: Int = 2048
    ) async -> String
}
```

### RecoveryContext Model

```swift
public struct RecoveryContext: Sendable, Codable {
    public let recoveredAt: Date
    public let timeWindow: TimeWindow
    public let confidence: ConfidenceScore
    public let sources: [SourceResult]
    public let timeline: [RecoveredItem]
    public let workspace: WorkspaceSnapshot
    public let errors: [String]
}

public struct RecoveredItem: Sendable, Codable {
    public let timestamp: Date
    public let provenance: Provenance
    public let kind: ItemKind          // event, commit, checkpoint, decision
    public let summary: String
    public let detail: String?         // only with --verbose
}

public enum Provenance: String, Sendable, Codable {
    case db, checkpoint, git, inferred
}
```

### Backend Endpoint

```
GET /api/events?since=2026-03-26T10:00:00Z&until=2026-03-26T12:00:00Z&types=sessionStart,codeChange&limit=200
```

Returns: `[ShikkiEvent]` sorted by timestamp descending.

---

## Estimated Effort

| Wave | Scope | LOC | Tests |
|------|-------|-----|-------|
| 1 | `DurationParser` + `ConfidenceScore` + `RecoveryContext` models | ~200 | ~18 |
| 2 | `ContextRecoveryService` (3-layer chain) | ~350 | ~20 |
| 3 | `DiagnosticFormatter` (3 output formats) | ~250 | ~18 |
| 4 | `DiagnosticCommand` CLI + integration with `ShikkiEngine` | ~150 | ~8 |
| 5 | Backend `GET /api/events` endpoint | ~100 | ~6 |
| **Total** | | **~1,050** | **~70** |
