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

When `shi restart` is called, the system should detect if a newer built binary exists, validate it, swap it in-place via `execv()`, and re-check dependencies — all WITHOUT killing the tmux session or losing the layout.

Currently `RestartCommand` has all logic inline (tmux interaction, process spawning) and only looks at `.build/debug/shikki`. No version comparison, no dependency re-check, no binary validation.

### Daemon Interaction

With `shi daemon` (headless kernel), restart has two modes:
1. **Interactive restart** (`shi restart` from tmux orchestrator): `execv()` replaces the orchestrator process, tmux panes preserved.
2. **Daemon restart** (`shi restart --daemon` or SIGHUP): restarts the daemon process. The daemon's DaemonPIDManager handles PID continuity. SIGHUP = config-only reload (no binary swap). Full restart = SIGTERM → relaunch via launchd/systemd.

Key concern: if daemon is running and user calls `shi restart` from a terminal, it should restart the **daemon** (send SIGTERM, let launchd relaunch), NOT try to `execv()` the terminal process.

### @t Brainstorm Consensus

| # | Decision |
|---|----------|
| C-01 | Use `execv()` for binary swap — no wrapper script, no `Process()` |
| C-02 | Pre-swap `--healthcheck` probe mandatory before `execv()` |
| C-03 | Reuse `SetupGuard.check()` for post-swap dependency validation |
| C-04 | Extract `RestartService` into ShikkiKit with protocol-injected dependencies |
| C-05 | Keep one rollback level (`shi.prev`), not a history stack |
| C-06 | Never run `sudo` implicitly during restart |
| C-07 | Two-phase restart: pre-swap (old binary) + post-swap (new binary) |
| C-08 | `restart` is NOT exempt from SetupGuard (free dep checks on version bump) |

## Business Rules

| BR | Rule |
|----|------|
| BR-01 | `shi restart` MUST preserve all tmux panes, windows, and non-orchestrator processes |
| BR-02 | Binary swap MUST use `execv()` syscall to replace the current process in-place (no new PID) |
| BR-03 | Pre-swap validation MUST run the new binary with `--healthcheck` flag and verify exit code 0 |
| BR-04 | Pre-swap validation MUST verify binary file ownership (current user), permissions (executable), and magic bytes (Mach-O `0xFEEDFACF` / ELF `0x7F454C46`) |
| BR-05 | Pre-swap phase MUST save a Checkpoint via `CheckpointManager` before any swap attempt |
| BR-06 | Pre-swap phase MUST copy current binary to `~/.shikki/bin/shi.prev` for rollback |
| BR-07 | Binary resolution MUST check in order: `~/.shikki/bin/shi`, `.build/release/shikki`, `.build/debug/shikki` |
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
| BR-19 | When daemon is running (daemon.pid alive), `shi restart` MUST restart the daemon by sending SIGTERM and letting launchd/systemd relaunch — NOT execv() the terminal process |
| BR-20 | `shi restart --daemon` MUST explicitly target the daemon process, even from interactive tmux |
| BR-21 | Daemon restart MUST copy new binary to `~/.shikki/bin/shi` BEFORE sending SIGTERM — launchd relaunches the updated binary |
| BR-22 | SIGHUP to daemon MUST trigger config-only reload (no binary swap) — use `shi restart` for binary swap |
| BR-23 | After daemon restart via launchd/systemd, daemon MUST emit `daemon_restarted` event with old/new version to ShikiDB |
| BR-24 | `shi restart --all` MUST restart both daemon AND interactive session (daemon first, then execv() orchestrator) |

## TDDP — Test-Driven Development Plan

| Test | BR | Tier | Type | Description |
|------|-----|------|------|-------------|
| T-01 | BR-02,03,05,06 | Core (80%) | Unit | Happy path — newer binary, healthcheck passes → `.swapped` |
| T-02 | BR-08 | Core (80%) | Unit | Same version — no `--force` → `.skipped` |
| T-03 | BR-03 | Core (80%) | Unit | Healthcheck fails (exit code != 0) → `.aborted` |
| T-04 | BR-04 | Security (100%) | Unit | Wrong permissions (not executable) → `.aborted` |
| T-05 | BR-14 | Core (80%) | Unit | Build in progress (mtime drift <100ms) → `.aborted` |
| T-06 | BR-09 | Core (80%) | Unit | Downgrade without `--force` → `.aborted` |
| T-07 | BR-09 | Core (80%) | Unit | Downgrade with `--force` → `.swapped` |
| T-08 | BR-01 | Core (80%) | Unit | tmux session gone → `.aborted`, no orphan processes |
| T-09 | BR-05 | Core (80%) | Unit | Checkpoint save fails (disk full) → `.aborted` before swap |
| T-10 | BR-13 | Security (100%) | Unit | `execv()` fails — old binary continues, error message emitted |
| T-11 | BR-10 | Core (80%) | Integration | Post-swap dep check on version bump → SetupGuard.check() runs |
| T-12 | BR-07 | Core (80%) | Unit | Binary resolution priority: installed > release > debug |
| T-13 | BR-06,18 | Security (100%) | Unit | Rollback binary created — `shi.prev` matches original SHA-256 |
| T-14 | BR-11 | Smoke (CLI) | Unit | `--upgrade-deps` triggers brew upgrade; absent = no upgrade |
| T-15 | BR-04 | Security (100%) | Unit | Magic bytes validation rejects non-Mach-O/non-ELF files |
| T-16 | BR-12 | Security (100%) | Unit | No `sudo` invoked — prints instructions and exits |
| T-17 | BR-16 | Core (80%) | Integration | Successful swap emits `ShikkiEvent.restart(oldVersion:newVersion:)` |
| T-18 | BR-17 | Core (80%) | Unit | Lockfile FD not released before `execv()` |
| T-19 | BR-15 | Core (80%) | Unit | `--phase post-swap` skips pre-swap logic, runs Phase 2 only |
| T-20 | BR-08 | Core (80%) | Unit | `--force` bypasses same-version skip |
| T-21 | BR-19 | Core (80%) | Unit | When daemon running → shi restart sends SIGTERM, not execv() |
| T-22 | BR-20 | Core (80%) | Unit | --daemon flag targets daemon PID regardless of context |
| T-23 | BR-21 | Core (80%) | Unit | New binary copied to ~/.shikki/bin/shi BEFORE daemon SIGTERM |
| T-24 | BR-22 | Core (80%) | Unit | SIGHUP reloads config, no binary swap |
| T-25 | BR-23 | Core (80%) | Unit | daemon_restarted event emitted with old/new version |
| T-26 | BR-24 | Core (80%) | Unit | --all restarts daemon first, then execv() orchestrator |

### S3 Test Scenarios

```
T-01 [BR-02,03,05,06, Core 80%]:
When restarting with a newer binary that passes healthcheck:
  → checkpoint saved via CheckpointManager
  → current binary copied to ~/.shikki/bin/shi.prev
  → healthcheck runs with --healthcheck flag and returns exit 0
  → execv() called with new binary path
  → result is .swapped(oldVersion, newVersion)

T-02 [BR-08, Core 80%]:
When restarting with same version and no --force flag:
  → binary version parsed as SemanticVersion
  → new version == current version detected
  → result is .skipped("Same version")

T-03 [BR-03, Core 80%]:
When restarting with a binary whose healthcheck fails:
  → --healthcheck run returns exit code != 0
  → no checkpoint saved
  → no binary copy
  → result is .aborted("Healthcheck failed")

T-04 [BR-04, Security 100%]:
When restarting with a binary that has wrong permissions:
  → file permissions checked (not executable)
  → result is .aborted("Binary not executable")
  → no healthcheck attempted

T-05 [BR-14, Core 80%]:
When restarting while build is in progress:
  → binary mtime sampled twice within 100ms window
  → mtime drift detected (file still changing)
  → result is .aborted("Build in progress")

T-06 [BR-09, Core 80%]:
When restarting with a downgrade (new < current) and no --force:
  → SemanticVersion comparison detects downgrade
  → warning printed to stderr
  → result is .aborted("Downgrade requires --force")

T-07 [BR-09, Core 80%]:
When restarting with a downgrade (new < current) and --force:
  → SemanticVersion comparison detects downgrade
  → --force bypasses downgrade check
  → healthcheck runs
  → result is .swapped(oldVersion, newVersion)

T-08 [BR-01, Core 80%]:
When restarting but tmux session is gone:
  → tmux session check returns no active session
  → result is .aborted("No tmux session")
  → no orphan processes left behind

T-09 [BR-05, Core 80%]:
When checkpoint save fails during restart:
  → CheckpointManager.save() throws (disk full)
  → swap never attempted
  → result is .aborted("Checkpoint save failed")

T-10 [BR-13, Security 100%]:
When execv() syscall fails:
  → execv() returns error (not Never)
  → old binary continues running (no crash)
  → error message emitted to stderr
  → ShikkiEvent.restartFailed emitted

T-11 [BR-10, Core 80%]:
When post-swap phase runs after version change:
  → --phase post-swap detected
  → SetupGuard.check() called
  → dependency validation triggered
  → normal orchestrator loop resumes

T-12 [BR-07, Core 80%]:
When resolving binary for restart:
  depending on available binaries:
    "~/.shikki/bin/shi" exists → selected (highest priority)
    ".build/release/shikki" exists, no installed → selected
    ".build/debug/shikki" exists, no release → selected
    none exist → .aborted("No binary found")

T-13 [BR-06,18, Security 100%]:
When creating rollback binary:
  → current binary copied to ~/.shikki/bin/shi.prev
  → SHA-256 of shi.prev computed
  → SHA-256 matches original binary hash stored at ~/.shikki/binary.sha256

T-14 [BR-11, Smoke CLI]:
When --upgrade-deps flag is provided:
  if --upgrade-deps present:
    → brew upgrade (or apt upgrade) triggered for managed dependencies
  otherwise:
    → no dependency upgrade attempted

T-15 [BR-04, Security 100%]:
When validating binary magic bytes:
  if file starts with 0xFEEDFACF:
    → accepted as valid Mach-O binary
  if file starts with 0x7F454C46:
    → accepted as valid ELF binary
  otherwise:
    → .aborted("Invalid binary format")

T-16 [BR-12, Security 100%]:
When restart requires elevated permissions:
  → no sudo invoked implicitly
  → instructions printed to stdout with exact sudo command
  → process exits with non-zero code

T-17 [BR-16, Core 80%]:
When binary swap succeeds:
  → ShikkiEvent.restart(oldVersion:newVersion:) emitted on EventBus
  → event contains both old and new version strings

T-18 [BR-17, Core 80%]:
When execv() is about to be called:
  → lockfile file descriptor is NOT closed before execv()
  → new process inherits the FD (no lock gap)

T-19 [BR-15, Core 80%]:
When --phase post-swap argument is present:
  → pre-swap logic skipped entirely (no checkpoint, no binary resolve, no validation)
  → Phase 2 runs directly (SetupGuard, event emission, orchestrator resume)

T-20 [BR-08, Core 80%]:
When restarting with same version and --force flag:
  → same-version check bypassed
  → healthcheck still runs
  → result is .swapped(currentVersion, currentVersion)

T-21 [BR-19, Core 80%]:
When shi restart is called and daemon.pid exists with alive process:
  → does NOT call execv() on current terminal process
  → copies new binary to ~/.shikki/bin/shi (if newer)
  → runs healthcheck on new binary
  → sends SIGTERM to daemon PID
  → launchd/systemd relaunches daemon with new binary
  → prints "Daemon restarted (PID: old → new)"

T-22 [BR-20, Core 80%]:
When shi restart --daemon is called:
  if daemon is running:
    → targets daemon PID (not current process)
    → same flow as T-21
  if daemon is not running:
    → prints "Daemon not running — use shi daemon to start"

T-23 [BR-21, Core 80%]:
When restarting daemon with newer binary:
  → new binary validated (healthcheck, magic bytes, permissions)
  → new binary copied to ~/.shikki/bin/shi
  → old binary saved to ~/.shikki/bin/shi.prev
  → THEN SIGTERM sent to daemon
  → launchd picks up the new binary at ~/.shikki/bin/shi on relaunch

T-24 [BR-22, Core 80%]:
When SIGHUP is sent to daemon process:
  → config.yaml re-read
  → TUITheme.active updated if theme changed
  → no binary swap attempted
  → daemon continues running same binary
  → log: "Config reloaded via SIGHUP"

T-25 [BR-23, Core 80%]:
When daemon restarts successfully via launchd/systemd:
  → daemon_restarted event posted to ShikiDB
  → event contains oldVersion, newVersion, restartMethod ("launchd"|"systemd"|"manual")
  → event contains timestamp and hostname

T-26 [BR-24, Core 80%]:
When shi restart --all is called:
  → daemon restarted first (copy binary, SIGTERM, wait for relaunch)
  → then orchestrator execv() into new binary
  → both processes running new version
  if daemon restart fails:
    → orchestrator restart aborted
    → prints "Daemon restart failed — aborting"
```

## Wave Dispatch Tree

```
Wave 1: RestartService + BinarySwapper + Validation
  ├── BinarySwapping protocol + PosixBinarySwapper + MockBinarySwapper
  ├── SemanticVersion parser + comparison
  ├── Binary validation (permissions, magic bytes, SHA-256, mtime drift)
  └── RestartService core logic (checkpoint, resolve, validate, swap)
  Tests: T-01, T-02, T-03, T-04, T-05, T-06, T-07, T-09, T-12, T-13, T-15, T-18, T-20
  Gate: swift test --filter RestartService → all green

Wave 2: CLI + Flags ← BLOCKED BY Wave 1
  ├── RestartCommand refactor (delegate to RestartService)
  ├── --force, --upgrade-deps, --phase flags
  └── No-sudo enforcement (print + exit)
  Tests: T-14, T-16, T-19
  Gate: swift test --filter Restart → all green

Wave 3: Integration — Event + SetupGuard + tmux ← BLOCKED BY Wave 1
  ├── Wire SetupGuard.check() on post-swap
  ├── Emit ShikkiEvent.restart on EventBus
  ├── execv() failure graceful degradation
  └── tmux session preservation check
  Tests: T-08, T-10, T-11, T-17
  Gate: full swift test green + manual restart verification

Wave 4: Daemon Restart Mode ← BLOCKED BY Wave 1
  ├── Detect daemon running → route to daemon restart flow
  ├── Copy binary → SIGTERM → launchd/systemd relaunch
  ├── --daemon flag, --all flag
  ├── daemon_restarted event to ShikiDB
  └── SIGHUP config-only reload (no binary swap)
  Tests: T-21, T-22, T-23, T-24, T-25, T-26
  Gate: shi restart with daemon running → daemon relaunches with new binary
```

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
  7. Copy current to shi.prev
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
1. ~/.shikki/bin/shi        (installed)
2. {workspace}/.build/release/shikki  (release build)
3. {workspace}/.build/debug/shikki    (debug build)
```

First path that exists AND is newer than the running binary wins.

### Rollback

```
shikki rollback  →  cp ~/.shikki/bin/shi.prev ~/.shikki/bin/shi
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
| 13 | Rollback binary created | BR-06 | `shi.prev` matches SHA |
| 14 | `--upgrade-deps` triggers brew upgrade | BR-11 | Upgrade runs only with flag |

## Implementation Waves

### Wave 1: RestartService + BinarySwapper + Validation (~250 LOC)
- **Files**: `Sources/ShikkiKit/Protocols/BinarySwapping.swift`, `Sources/ShikkiKit/Services/RestartService.swift`, `Sources/ShikkiKit/Models/SemanticVersion.swift`
- **Tests**: `Tests/ShikkiKitTests/RestartServiceTests.swift` (T-01..T-07, T-09, T-12, T-13, T-15, T-18, T-20)
- **BRs**: BR-02, BR-03, BR-04, BR-05, BR-06, BR-07, BR-08, BR-09, BR-14, BR-17, BR-18
- **Deps**: CheckpointManager (exists), ShellExecuting (exists)
- **Gate**: `swift test --filter RestartService` green

### Wave 2: CLI + Flags ← BLOCKED BY Wave 1 (~80 LOC delta)
- **Files**: `Sources/shikki/Commands/RestartCommand.swift`
- **Tests**: `Tests/ShikkiKitTests/RestartServiceTests.swift` (T-14, T-16, T-19)
- **BRs**: BR-11, BR-12, BR-15
- **Deps**: Wave 1 (RestartService)
- **Gate**: `swift test --filter Restart` green

### Wave 3: Integration ← BLOCKED BY Wave 1 (~120 LOC)
- **Files**: `Sources/ShikkiKit/Services/RestartService.swift` (extend), `Sources/shikki/Commands/RestartCommand.swift` (extend)
- **Tests**: `Tests/ShikkiKitTests/RestartServiceTests.swift` (T-08, T-10, T-11, T-17)
- **BRs**: BR-01, BR-10, BR-13, BR-16
- **Deps**: Wave 1 (RestartService), SetupGuard (exists), EventBus (exists)
- **Gate**: full `swift test` green + manual restart verification

### Wave 4: Daemon Restart Mode ← BLOCKED BY Wave 1 (~150 LOC)
- **Files**: `Sources/ShikkiKit/Services/RestartService.swift` (extend with daemon flow), `Sources/shikki/Commands/RestartCommand.swift` (add --daemon, --all flags)
- **Tests**: `Tests/ShikkiKitTests/RestartServiceTests.swift` (T-21..T-26)
- **BRs**: BR-19, BR-20, BR-21, BR-22, BR-23, BR-24
- **Deps**: Wave 1 (RestartService), DaemonPIDManager (exists), DaemonEventEmitter (exists), LaunchdInstaller (exists)
- **Gate**: `shi restart` with daemon running → daemon relaunches with new binary

**Total estimate**: 5 new files + 2 modified, ~600 LOC + ~500 LOC tests

## @Daimyo Decisions Needed

| # | Question | Default |
|---|----------|---------|
| Q-01 | Should `shi restart` trigger `swift build` if no newer binary? | No (swap only) |
| Q-02 | Should dep upgrades (`brew upgrade`) be opt-in or automatic? | Opt-in (`--upgrade-deps`) |
| Q-03 | Should `--force` skip healthcheck? | No (healthcheck always runs) |
| Q-04 | Rollback binary: full copy or hardlink? | Full copy (portable) |
| Q-05 | Emit NATS `shikki.restart` event for multi-node? | Yes (future-proof) |

## @shi Mini-Challenge

1. **@Ronin**: What if `execv()` succeeds but the new binary hangs during Phase 2? No watchdog covers this gap.
2. **@Katana**: Should `binary.sha256` also store the build timestamp and git commit hash for audit?
3. **@Kenshi**: How does this interact with `shi ship` — should shipping auto-restart after binary install?
4. **@Sensei**: Daemon restart via SIGTERM + launchd relaunch introduces a brief downtime window (~1-2s). NATS connections from workers will reconnect, but in-flight dispatch tasks may fail. Should we drain workers before daemon restart?
5. **@Ronin**: If launchd/systemd fails to relaunch after SIGTERM (misconfigured plist), the daemon is dead with no recovery. Should `shi restart --daemon` verify relaunch within 5s and rollback if not?
