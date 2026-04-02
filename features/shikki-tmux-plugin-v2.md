---
title: "Tmux Plugin v2 — Dynamic Project Scoping + Inbox Integration"
status: draft
priority: P1
project: shikki
created: 2026-04-02
---

# Feature: Tmux Plugin v2

## Context

The tmux status bar plugin broke after the v0.3.0 mega-merge: the binary was renamed `shiki` to `shikki` (now settling on `shi`) but the segments script still referenced the old name. The fix was trivial but exposed deeper issues — the plugin has no concept of project scoping, no inbox urgency awareness, and the segments script is hand-maintained instead of generated.

## Problem

The v1 plugin shows agent counts and budget but has no idea *which project* matters right now. A user juggling Shikki, WabiSabi, and Maya sees a flat `●3 Q:2 $8/$20` with no project context. They must mentally map which agents belong to which project. The segments script is also fragile — any binary rename breaks it silently, and reloading `.tmux.conf` can duplicate segments.

## Business Rules

| ID | Rule |
|----|------|
| BR-01 | Segments script references `shi` binary (not `shiki` or `shikki`) |
| BR-02 | `ProjectScorer` queries ShikiDB inbox computed view to rank projects by summed urgency |
| BR-03 | ShikiDB unreachable: use cached scores from `~/.shikki/tmux-cache.json` |
| BR-04 | Cache missing: show `?` icon (never crash) |
| BR-05 | Pin state persisted in `TmuxStateManager` (`pinnedProject` + `pinnedUntil` timestamp) |
| BR-06 | Pin duration default 120 seconds, configurable via `~/.config/shiki/tmux-state.json` |
| BR-07 | After pin timeout expires, revert to auto-detection (highest-scoring project) |
| BR-08 | Display max 3 project icons in status bar, collapse remainder as `+N` |
| BR-09 | Each segment callback returns within 100ms (80ms HTTP timeout to ShikiDB) |
| BR-10 | Segments script must be idempotent — no duplication on `.tmux.conf` reload |
| BR-11 | `shi start` regenerates the segments script at `~/.config/shiki/tmux-segments.conf` |
| BR-12 | Auto-switch minimum dwell time: 5 minutes before changing active project (prevents jitter) |

## TDDP — Test-Driven Development Plan

| Test | BR | Tier | Type | Description |
|------|-----|------|------|-------------|
| T-01 | BR-02 | Core (80%) | Unit | ProjectScorer returns ranked projects from mock ShikiDB response |
| T-02 | BR-03,09 | Core (80%) | Unit | ProjectScorer falls back to cached scores when HTTP fails (80ms timeout) |
| T-03 | BR-04 | Core (80%) | Unit | MiniStatusFormatter renders `?` when cache missing and DB unreachable |
| T-04 | BR-05,06,07 | Core (80%) | Unit | Pin expires after configured duration, auto-detection resumes |
| T-05 | BR-08 | Core (80%) | Unit | Multi-project display shows max 3 icons, collapses 4th+ as `+N` |
| T-06 | BR-12 | Core (80%) | Unit | Auto-switch blocked when dwell time < 5 min, allowed when >= 5 min |
| T-07 | BR-01 | Smoke (CLI) | Unit | Segments script references `shi` binary, not `shiki` or `shikki` |
| T-08 | BR-10 | Smoke (CLI) | Integration | `.tmux.conf` reload does not duplicate segments |
| T-09 | BR-11 | Smoke (CLI) | Integration | `shi start` regenerates segments script at correct path |
| T-10 | BR-09 | Core (80%) | Unit | Each segment callback returns within 100ms (mock HTTP <=80ms) |
| T-11 | BR-05 | Core (80%) | Unit | Pin persists across TmuxStateManager save/load cycle |
| T-12 | BR-06 | Core (80%) | Unit | Custom pin duration from config overrides default 120s |

## Wave Dispatch Tree

```
Wave 1: ProjectScorer + Cache
  ├── ProjectScorer (ShikiDB inbox query, urgency scoring)
  ├── tmux-cache.json read/write
  └── HTTP timeout enforcement (80ms)
  Tests: T-01, T-02, T-03, T-10
  Gate: swift test --filter ProjectScorer → all green

Wave 2: TmuxStateManager + MiniStatusFormatter ← BLOCKED BY Wave 1
  ├── pinnedProject, pinnedUntil, pinDurationSeconds fields
  ├── pin() and clearPinIfExpired() methods
  ├── shouldSwitch() with 5-min dwell time
  └── formatMultiProject (top 3 icons + +N collapse)
  Tests: T-04, T-05, T-06, T-11, T-12
  Gate: swift test --filter Tmux → all green

Wave 3: TmuxCommand + shi start ← BLOCKED BY Wave 2
  ├── shi tmux install / uninstall subcommands
  ├── Idempotent segments script generation
  ├── shi start hooks segment generation
  └── Binary name = shi (not shiki/shikki)
  Tests: T-07, T-08, T-09
  Gate: full swift test green + manual tmux verification
```

## Status Bar Mockups

Single project (Shikki active, 2 agents working):
```
S ●2 Q:1 $4/$15 | 6.0 ✓310 | main +3!1
```

Multi-project (Shikki active, Brainy and Maya background):
```
S●B○M○ Q:3 $8/$20 | 6.0 ✓310 | dev +2!4
```

Collapsed (Shikki active, 2+ background projects):
```
S●+2 Q:5 $12/$30 | 1.46 | main ⇡1
```

Legend: First letter = project initial, `●` = active/working, `○` = idle/background. Git segment shows branch, staged (`+N`), modified (`!N`), ahead (`⇡N`).

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `ShikkiKit/Services/ProjectScorer.swift` | NEW | Query ShikiDB inbox, compute per-project urgency scores, manage cache |
| `shikki/Commands/TmuxCommand.swift` | NEW | `shi tmux install` / `shi tmux uninstall` subcommands |
| `ShikkiKit/Services/TmuxStateManager.swift` | EXTEND | Add `pinnedProject`, `pinnedUntil`, `pinDurationSeconds`, `lastSwitchAt` fields |
| `ShikkiKit/Services/MiniStatusFormatter.swift` | EXTEND | Multi-project icon rendering, `+N` collapse logic |
| `shikki/Commands/StatusCommand.swift` | EXTEND | Wire `--pin <project>` flag, pass scored projects to formatter |

## Reuse Audit

- `TmuxStateManager` — existing JSON persistence, extend with pin fields (no new file)
- `MiniStatusFormatter.wrapWithArrows` — reuse for segment wrapping
- `BackendClient` — reuse HTTP client for ShikiDB queries (or add `ProjectScorer` as thin wrapper)
- `GitStatusFormatter` / `ProjectStatusFormatter` — existing segments, unchanged

## Implementation Waves

### Wave 1: ProjectScorer + Cache (2 files, ~120 LOC)
- **Files**: `ShikkiKit/Services/ProjectScorer.swift`, `Tests/ShikkiKitTests/ProjectScorerTests.swift`
- **Tests**: T-01, T-02, T-03, T-10
- **BRs**: BR-02, BR-03, BR-04, BR-09
- **Deps**: BackendClient (exists), ShikiDB (exists)
- **Gate**: `swift test --filter ProjectScorer` green

### Wave 2: TmuxStateManager + MiniStatusFormatter (~80 LOC) ← BLOCKED BY Wave 1
- **Files**: `ShikkiKit/Services/TmuxStateManager.swift` (extend), `ShikkiKit/Services/MiniStatusFormatter.swift` (extend)
- **Tests**: T-04, T-05, T-06, T-11, T-12
- **BRs**: BR-05, BR-06, BR-07, BR-08, BR-12
- **Deps**: Wave 1 (ProjectScorer)
- **Gate**: `swift test --filter Tmux` green

### Wave 3: TmuxCommand + shi start integration (~60 LOC) ← BLOCKED BY Wave 2
- **Files**: `Commands/TmuxCommand.swift`, `shi start` hook
- **Tests**: T-07, T-08, T-09
- **BRs**: BR-01, BR-10, BR-11
- **Deps**: Wave 2 (TmuxStateManager, MiniStatusFormatter)
- **Gate**: full `swift test` green + manual tmux verification

## Test Scenarios

| # | Scenario | Validates |
|---|----------|-----------|
| T-01 | ProjectScorer returns ranked projects from mock ShikiDB response | BR-02 |
| T-02 | ProjectScorer falls back to cached scores when HTTP fails (80ms timeout) | BR-03, BR-09 |
| T-03 | MiniStatusFormatter renders `?` when cache is missing and DB is unreachable | BR-04 |
| T-04 | Pin expires after configured duration, auto-detection resumes | BR-05, BR-06, BR-07 |
| T-05 | Multi-project display shows max 3 icons, collapses 4th+ as `+N` | BR-08 |
| T-06 | Auto-switch blocked when dwell time < 5 minutes, allowed when >= 5 minutes | BR-12 |
