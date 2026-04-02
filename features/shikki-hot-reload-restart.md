---
title: "Hot-Reload Restart with Version Check + Dependency Upgrade"
status: draft
priority: P0
project: shikki
created: 2026-04-02
authors: ["@Daimyo"]
tags: [cli, restart, hot-reload, binary-swap, setup]
depends-on: ["shikki-setup-swift"]
---

# Feature: Hot-Reload Restart with Version Check + Dependency Upgrade
> Created: 2026-04-02 | Status: Spec Draft | Owner: @Daimyo

## Context

When `shikki restart` is called, the system should detect if a newer built binary exists, validate it, swap it in-place via `execv()`, and re-check dependencies — all WITHOUT killing the tmux session or losing the layout.

Currently `RestartCommand` has all logic inline (tmux interaction, process spawning) and only looks at `.build/debug/shikki`. No version comparison, no dependency re-check, no binary validation.

### @t Brainstorm Consensus

| # | Decision |
|---|----------|
| C-01 | Use `execv()` for binary swap — no wrapper script, no `Process()` |
| C-02 | Pre-swap `--healthcheck` probe mandatory before `execv()` |
| C-03 | Reuse `SetupGuard.check()` for post-swap dependency validation |
| C-04 | Extract `RestartService` into ShikkiKit with protocol-injected dependencies |
| C-05 | Keep one rollback level (`shikki.prev`), not a history stack |
| C-06 | Never run `sudo` implicitly during restart |
| C-07 | Two-phase restart: pre-swap (old binary) + post-swap (new binary) |
| C-08 | `restart` is NOT exempt from SetupGuard (free dep checks on version bump) |

## Business Rules

| BR | Rule |
|----|------|
| BR-01 | `shikki restart` MUST preserve all tmux panes, windows, and non-orchestrator processes |
| BR-02 | Binary swap MUST use `execv()` syscall to replace the current process in-place (no new PID) |
| BR-03 | Pre-swap validation MUST run the new binary with `--healthcheck` flag and verify exit code 0 |
| BR-04 | Pre-swap validation MUST verify binary file ownership (current user), permissions (executable), and magic bytes (Mach-O `0xFEEDFACF` / ELF `0x7F454C46`) |
| BR-05 | Pre-swap phase MUST save a Checkpoint via `CheckpointManager` before any swap attempt |
| BR-06 | Pre-swap phase MUST copy current binary to `~/.shikki/bin/shikki.prev` for rollback |
| BR-07 | Binary resolution MUST check in order: `~/.shikki/bin/shikki`, `.build/release/shikki`, `.build/debug/shikki` |
| BR-08 | Version comparison MUST use `SemanticVersion` parsing — skip swap if new == current (unless `--force`) |
| BR-09 | Version downgrade (new < current) MUST print warning and require `--force` to proceed |
| BR-10 | Post-swap phase MUST call `SetupGuard.check()` to trigger dependency validation on version change |
| BR-11 | Dependency upgrades (`brew upgrade` / `apt upgrade`) MUST be opt-in via `--upgrade-deps` flag |
| BR-12 | Restart MUST NOT run `sudo` implicitly — print command and exit with instructions if needed |
| BR-13 | If `execv()` fails, the old binary MUST continue running with an error message (graceful degradation) |
| BR-14 | If the new binary file is changing (mtime drift within 100ms window), abort with "Build in progress" |
| BR-15 | Post-swap phase receives `--phase post-swap` arg and skips pre-swap logic |
| BR-16 | `RestartService` MUST emit `ShikkiEvent.restart(oldVersion:newVersion:)` after successful swap |
| BR-17 | Lockfile MUST NOT be released before `execv()` — new process inherits the file descriptor |
| BR-18 | SHA-256 of the running binary MUST be stored at `~/.shikki/binary.sha256` and compared pre-swap |

## Architecture

### Two-Phase Restart

```
Phase 1 (old binary):
  1. Save checkpoint (CheckpointManager)
  2. Save tmux checkpoint (tmux-checkpoint.sh)
  3. Resolve new binary (priority: installed > release > debug)
  4. Compare versions (SemanticVersion)
  5. Validate: permissions, magic bytes, SHA-256
  6. Run --healthcheck probe
  7. Copy current to shikki.prev
  8. execv() into new binary with ["restart", "--phase", "post-swap"]

Phase 2 (new binary):
  1. Detect --phase post-swap
  2. SetupGuard.check() → triggers dep validation if version changed
  3. Emit ShikkiEvent.restart
  4. Resume normal orchestrator loop
```

### Key Types

```swift
// Protocol for testability
public protocol BinarySwapping: Sendable {
    func exec(path: String, args: [String]) throws -> Never
}

// Production: calls execv()
public struct PosixBinarySwapper: BinarySwapping { ... }

// Test: records call, throws known error
public struct MockBinarySwapper: BinarySwapping { ... }

// Core service
public struct RestartService: Sendable {
    let checkpointManager: CheckpointManager
    let setupGuard: SetupGuard
    let binarySwapper: any BinarySwapping
    let shellExecutor: any ShellExecuting

    func restart(force: Bool, upgradeDeps: Bool) async throws -> RestartResult
}

public enum RestartResult {
    case swapped(oldVersion: String, newVersion: String)
    case skipped(reason: String)
    case aborted(reason: String)
}
```

### Binary Resolution Priority

```
1. ~/.shikki/bin/shikki        (installed)
2. {workspace}/.build/release/shikki  (release build)
3. {workspace}/.build/debug/shikki    (debug build)
```

First path that exists AND is newer than the running binary wins.

### Rollback

```
shikki rollback  →  cp ~/.shikki/bin/shikki.prev ~/.shikki/bin/shikki
```

One level only. Overwritten on every successful restart.

## Test Scenarios (14)

| # | Scenario | BRs | Expected |
|---|----------|-----|----------|
| 1 | Happy path — newer binary, healthcheck passes | BR-02,03,05,06 | `.swapped` |
| 2 | Same version — no-op | BR-08 | `.skipped` |
| 3 | Healthcheck fails | BR-03 | `.aborted` |
| 4 | Wrong permissions (not executable) | BR-04 | `.aborted` |
| 5 | Build in progress (mtime drift) | BR-14 | `.aborted` |
| 6 | Downgrade without `--force` | BR-09 | `.aborted` |
| 7 | Downgrade with `--force` | BR-09 | `.swapped` |
| 8 | tmux session gone | BR-01 | `.aborted` |
| 9 | Checkpoint save fails (disk full) | BR-05 | `.aborted` |
| 10 | `execv()` fails — graceful degradation | BR-13 | Old binary continues |
| 11 | Post-swap dep check on version bump | BR-10 | SetupService runs |
| 12 | Binary resolution priority order | BR-07 | Highest priority picked |
| 13 | Rollback binary created | BR-06 | `shikki.prev` matches SHA |
| 14 | `--upgrade-deps` triggers brew upgrade | BR-11 | Upgrade runs only with flag |

## Implementation Plan

### Wave 1: RestartService + BinarySwapper (~200 LOC)
- `Sources/ShikkiKit/Services/RestartService.swift` — core logic
- `Sources/ShikkiKit/Protocols/BinarySwapping.swift` — protocol + PosixBinarySwapper

### Wave 2: RestartCommand refactor + CLI flags (~50 LOC delta)
- `Sources/shikki/Commands/RestartCommand.swift` — delegate to RestartService, add `--upgrade-deps`, `--force`, `--phase`

### Wave 3: Tests (~350 LOC)
- `Tests/ShikkiKitTests/RestartServiceTests.swift` — 14 scenarios with MockBinarySwapper

### Wave 4: Integration
- Wire `SetupGuard.check()` post-swap path
- Emit `ShikkiEvent.restart` on EventBus
- Extract `SemanticVersion` to shared type if needed

**Total estimate**: 3 new files + 1 modified, ~600 LOC

## @Daimyo Decisions Needed

| # | Question | Default |
|---|----------|---------|
| Q-01 | Should `shikki restart` trigger `swift build` if no newer binary? | No (swap only) |
| Q-02 | Should dep upgrades (`brew upgrade`) be opt-in or automatic? | Opt-in (`--upgrade-deps`) |
| Q-03 | Should `--force` skip healthcheck? | No (healthcheck always runs) |
| Q-04 | Rollback binary: full copy or hardlink? | Full copy (portable) |
| Q-05 | Emit NATS `shikki.restart` event for multi-node? | Yes (future-proof) |

## @shi Mini-Challenge

1. **@Ronin**: What if `execv()` succeeds but the new binary hangs during Phase 2? No watchdog covers this gap.
2. **@Katana**: Should `binary.sha256` also store the build timestamp and git commit hash for audit?
3. **@Kenshi**: How does this interact with `shikki ship` — should shipping auto-restart after binary install?
