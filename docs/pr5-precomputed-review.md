# PR #5 — Precomputed Review Summary

> Generated: 2026-03-17
> Branch: `feature/cli-core-architecture` -> `develop`
> State: OPEN

---

## 1. PR Overview

**Title:** feat(shiki-ctl): v0.2.0 CLI migration + orchestrator fixes

**Size:** +3,010 / -767 across 28 files (net +2,243 lines — LARGE PR)

**What it does:**
- Migrates the CLI from a 196-line bash wrapper to a native Swift binary with 12 subcommands
- Adds smart startup with 6-step environment detection (Docker, Colima, LM Studio, backend)
- New `ProcessCleanup` service to kill ghost processes before tmux session teardown
- Replaces `AsyncHTTPClient` with `curl` subprocess in `BackendClient` (fixes stale connection pools with Docker networking)
- New commands: `start`, `stop`, `restart`, `attach`, `heartbeat`
- Smart orchestrator features: stale company relaunch, decision-unblock re-dispatch
- Session stats with git diff tracking, workspace auto-detection, zsh autocompletion
- README rewrite from 496 to 165 lines
- Adds 585-line vision/architecture session document

---

## 2. Risk Assessment Per File

### HIGH Risk

| File | +/- | Reason |
|------|-----|--------|
| `Commands/StartupCommand.swift` | +502/0 | Largest new file. Orchestrates Docker, Colima, tmux, backend health checks. Heavy side-effects (`execv`, `Process`, file I/O). Uses `fflush(stdout)` and raw ANSI escape codes. Hardcoded paths (e.g., `~/Documents/Workspaces/shiki`). Force-unwrap on line 130 (`completionDate!`). No test coverage for the command itself (only the renderer is tested). |
| `Services/ProcessCleanup.swift` | +182/0 | Kills processes via `pgrep`/`pkill` shell-outs. Safety-critical: must not kill non-Shiki processes. Tests use mock shell runner — real `pkill` behavior untested. |
| `Services/HeartbeatLoop.swift` | +104/-20 | Orchestrator brain. `checkStaleCompanies()` documented as disabled (line 42 per session doc) — dead code shipped? Decision re-dispatch logic added but unverified in integration. |
| `Commands/RestartCommand.swift` | +115/0 | Sends `Ctrl-C` to tmux panes via `tmux send-keys`. Fragile: depends on pane indices and tmux version behavior. No tests. |
| `Commands/StopCommand.swift` | +106/0 | Process tree teardown. Self-kill risk when run from inside tmux (documented bug #3). No tests. |

### MEDIUM Risk

| File | +/- | Reason |
|------|-----|--------|
| `Services/BackendClient.swift` | +71/-49 | AsyncHTTPClient -> curl subprocess. Intentional tech debt (curl is temp per `feedback_netkit-over-curl.md`). Actor isolation looks correct. Timeout handling via `curl -m`. |
| `Services/StartupRenderer.swift` | +236/0 | Pure rendering (box-drawing, ANSI). Has 78 lines of tests — good coverage for a renderer. Low side-effect risk. |
| `Services/SessionStats.swift` | +221/0 | Git log parsing via shell. Has 69 lines of tests. Protocol-based (`SessionStatsProviding`) — testable. `isMatureStage` heuristic (ratio 0.8-1.2) is arbitrary but harmless. |
| `Services/EnvironmentDetector.swift` | +122/0 | Shell-outs to detect Docker, Colima, LM Studio, backend. Has 51 lines of tests. Protocol-based — testable. |
| `README.md` | +127/-457 | Major rewrite. Lost API reference, contributing guide, and architecture details. Check if that info lives elsewhere or is just gone. |
| `docs/session-2026-03-16-vision-and-architecture.md` | +585/0 | Session reconstruction doc. Contains 4 unfixed bugs (ghost processes, stale companies, self-kill, curl exit 28). Useful as post-mortem reference but large. |
| `Services/NotificationService.swift` | +21/-22 | Minor refactor. Low risk. |

### LOW Risk

| File | +/- | Reason |
|------|-----|--------|
| `Commands/AttachCommand.swift` | +40/0 | Thin wrapper around `tmux attach-session`. Simple. |
| `Commands/DecideCommand.swift` | +25/-3 | Multiline input fix. Small, targeted change. |
| `Commands/HeartbeatCommand.swift` | +9/-4 | Rename from `StartCommand`. Trivial. |
| `Commands/StatusCommand.swift` | +66/-1 | Added workspace + session detection to status output. |
| `ShikiCtl.swift` | +8/-4 | Register new subcommands. Trivial. |
| `Package.swift` | 0/+2 | Removed `AsyncHTTPClient` dependency. Clean. |
| `Package.resolved` | +1/-190 | Dependency tree shrunk massively. Good. |
| `Services/CompanyLauncher.swift` | +4/-1 | Minor tweak. |
| `scripts/shiki` | +40/-5 | Bash wrapper updated for new binary. |
| `scripts/install-completions.sh` | +34/0 | One-shot install script. |
| All test files | +384/0 total | New test suites. Net positive. |
| `CommandParsingTests.swift` | +7/-9 | Updated for renamed commands. |

---

## 3. Key Concerns

### 3.1 — StartupCommand is untestable monolith (HIGH)
`StartupCommand.swift` is 502 lines with direct `Process()` calls, `execv`, raw `print()` with ANSI codes, and filesystem access. The rendering is tested via `StartupRenderer`, but the startup orchestration logic (Docker bootstrap, tmux layout creation, health polling) has zero test coverage. This is the most important code path in the CLI.

**Recommendation:** Extract startup orchestration into a testable service with injected dependencies (like `EnvironmentDetector` and `SessionStats` already are).

### 3.2 — Force-unwrap in StartupCommand (MEDIUM)
Line 130 of `StartupCommand.swift`: `binaryDate > completionDate!` — force-unwrap after a nil check that sets the condition but the unwrap is still unsafe if there's a race. Should use `if let` binding.

### 3.3 — Four known unfixed bugs shipped (HIGH)
The session doc (`docs/session-2026-03-16-vision-and-architecture.md`) explicitly lists 4 unfixed bugs:
1. **Ghost processes** — `shiki stop` leaves orphan Claude/xcodebuild/Simulator processes
2. **Stale companies** — `checkStaleCompanies()` is disabled, no re-dispatch after decisions
3. **Self-kill** — `shiki stop --force && shiki start` from inside tmux kills the caller
4. **curl exit 28** — company sub-agents timeout reaching backend

`ProcessCleanup.swift` was added to address bug #1, but the session doc says the fix was "never implemented" (the service exists but may not be wired into the stop flow).

**Recommendation:** Verify `ProcessCleanup` is actually called in `StopCommand`. If not, this is dead code and bug #1 is still open.

### 3.4 — No tests for StopCommand and RestartCommand (MEDIUM)
Both commands manipulate tmux sessions and send signals to processes. They have no test coverage. `RestartCommand` sends `C-c` to specific tmux panes by index — fragile and version-dependent.

### 3.5 — README lost significant content (LOW-MEDIUM)
The README went from 496 to 165 lines. API reference (memories, pipelines, radar, ingestion endpoints), contributing guide, backup/restore instructions, and detailed architecture diagram are all gone. If this content doesn't exist elsewhere, it's a documentation regression.

---

## 4. Test Coverage Status

| Suite | Tests | Covers |
|-------|-------|--------|
| `ProcessCleanupTests` | 158 lines | ProcessCleanup service (mock shell runner) |
| `StartupRendererTests` | 78 lines | Box-drawing dashboard rendering |
| `SessionStatsTests` | 69 lines | Git stats parsing, maturity indicator |
| `EnvironmentDetectorTests` | 51 lines | Docker/Colima/LM Studio detection |
| `BackendClientConnectionTests` | 28 lines | Curl-based backend client |
| `CommandParsingTests` | 16 lines (updated) | CLI argument parsing |
| **Total new test lines** | **+384** | |
| **Reported suite count** | 13 suites, 52 tests | All green, zero warnings |

### Gaps

| Component | Test Status |
|-----------|-------------|
| `StartupCommand` (502 lines) | **NOT TESTED** — only the renderer is tested |
| `StopCommand` (106 lines) | **NOT TESTED** |
| `RestartCommand` (115 lines) | **NOT TESTED** |
| `AttachCommand` (40 lines) | **NOT TESTED** |
| `HeartbeatLoop` orchestration logic | Partial (existing tests, +104 lines untested) |
| `ProcessCleanup` real behavior | Mocked only — real `pkill`/`pgrep` untested |

**Bottom line:** Services are well-tested (protocol-based, injectable). Commands are not tested at all — they contain the most side-effect-heavy and risk-prone code. The 52/52 green number is real but masks that the riskiest code paths have zero coverage.

---

## Verdict

**Size:** LARGE — 28 files, net +2,243 lines. Could have been split into 2-3 PRs (services + commands + README/docs).

**Quality:** Services layer is solid (protocol-based, tested, actor-isolated). Command layer is a concern (monolithic, untestable, no coverage). Known bugs are documented honestly.

**Ship?** Merge-able with known debt. The 4 unfixed bugs are pre-existing or edge-case. The startup flow works for the happy path. Key follow-up: extract `StartupCommand` orchestration into a testable service and add tests for `StopCommand`/`RestartCommand`.
