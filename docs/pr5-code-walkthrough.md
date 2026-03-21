# PR #5 Code Walkthrough

> Navigate file-by-file. Each section has inline annotations.
> Use editor heading navigation to jump between files.

---

## File 1/12: `ShikiCtl.swift` — Entry Point

```swift
// tools/shiki-ctl/Sources/shiki-ctl/ShikiCtl.swift
@main
struct ShikiCtl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shiki",
        abstract: "Shiki orchestrator — launch, monitor, and control your multi-project system",
        version: "0.2.0",                    // ← bumped from 0.1.0
        subcommands: [
            StartupCommand.self,             // ← was StartCommand, now smart startup
            StopCommand.self,                // ← NEW: confirmation + ghost cleanup
            RestartCommand.self,             // ← NEW: preserves tmux, restarts heartbeat
            AttachCommand.self,              // ← NEW: tmux attach
            StatusCommand.self,              // ← enhanced: workspace + session detection
            BoardCommand.self,
            HistoryCommand.self,
            HeartbeatCommand.self,           // ← was StartCommand internals, now separate
            WakeCommand.self,
            PauseCommand.self,
            DecideCommand.self,              // ← fixed: multiline input
            ReportCommand.self,
        ]
    )
}
```

**What changed**: 12 subcommands (was 8). `StartCommand` split into `StartupCommand` (user-facing) + `HeartbeatCommand` (internal, launched by startup inside tmux).

---

## File 2/12: `ProcessCleanup.swift` — Ghost Process Killer (NEW)

```swift
// tools/shiki-ctl/Sources/ShikiCtlKit/Services/ProcessCleanup.swift

public struct ProcessCleanup: Sendable {

    // ── Single source of truth for reserved windows ──
    public static let reservedWindows: Set<String> = ["orchestrator", "board", "research"]
    // NOTE: CompanyLauncher.reservedWindows and StopCommand.countTaskWindows
    //       now reference this instead of their own copies.

    // ── Step 1: Collect PIDs from tmux panes ──
    public func collectSessionPIDs(session: String) -> [pid_t] {
        // Uses: tmux list-panes -s -t <session> -F "#{window_name} #{pane_pid}"
        // Filters out reserved windows
        // Returns: [pid_t] of task window pane processes
    }

    // ── Step 2: Kill a process tree (SIGTERM → wait → SIGKILL) ──
    public func killProcessTree(pid: pid_t) {
        let children = getChildPIDs(of: pid)  // pgrep -P <pid>
        // Kill children first (depth-first)
        for child in children { kill(child, SIGTERM) }
        kill(pid, SIGTERM)
        usleep(500_000)  // 500ms grace period
        // Force kill survivors
        for child in children { kill(child, SIGKILL) }
        kill(pid, SIGKILL)
    }

    // ── Step 3: Full cleanup orchestration ──
    public func cleanupSession(session: String) -> CleanupResult {
        let taskPIDs = collectSessionPIDs(session: session)
        guard !taskPIDs.isEmpty else { return .init(windowsKilled: 0, orphanPIDsKilled: 0) }

        let taskWindows = listTaskWindows(session: session)

        // Kill task windows one by one (reserved windows survive)
        for windowName in taskWindows {
            tmux kill-window -t <session>:<windowName>
        }

        usleep(200_000)  // 200ms for tmux to propagate SIGHUP

        // Kill any PIDs still alive
        for pid in taskPIDs where kill(pid, 0) == 0 {
            killProcessTree(pid: pid)
        }
        // Returns: CleanupResult { windowsKilled, orphanPIDsKilled }
    }

    // ── Orphan detection (exact binary match) ──
    public func findOrphanedClaudeProcesses() -> [pid_t] {
        // pgrep -x claude (NOT -f, which matches args/paths)
        // Filters out self (myPID) and parent (getppid())
    }
}
```

**Key design**: Value type (`struct`), `Sendable`, no state. Each call is independent. `reservedWindows` is the canonical definition — other files reference it.

---

## File 3/12: `StopCommand.swift` — Graceful Shutdown (REWRITTEN)

```swift
// tools/shiki-ctl/Sources/shiki-ctl/Commands/StopCommand.swift

func run() async throws {
    guard tmuxSessionExists(session) else { return }

    let taskWindows = countTaskWindows(session)  // uses ProcessCleanup.reservedWindows
    print("Stopping Shiki system...")
    if taskWindows > 0 { print("  \(taskWindows) active task window(s) running") }

    if !force {
        // Confirmation prompt
        print("  Confirm kill tmux session? [y/N] ")
        guard readLine()?.lowercased() == "y" else { return }
    }

    // ── THE FIX: cleanup BEFORE killing session ──
    let cleanup = ProcessCleanup()
    let result = cleanup.cleanupSession(session: session)
    // Reports what was killed
    if result.windowsKilled > 0 { print("  Killed \(result.windowsKilled) task window(s)") }
    if result.orphanPIDsKilled > 0 { print("  Killed \(result.orphanPIDsKilled) orphaned process(es)") }

    // Kill tmux session LAST (reserved windows die here)
    tmux kill-session -t <session>
    print("  Stopped Shiki system")
}
```

**Before**: One line (`tmux kill-session`). Ghost processes survived.
**After**: Enumerate → kill tasks → kill orphans → kill session. Nothing survives.

---

## File 4/12: `HeartbeatLoop.swift` — Orchestrator Brain (MODIFIED)

### New state
```swift
public actor HeartbeatLoop {
    private var previousPendingDecisionIds: Set<String> = []  // ← NEW: tracks decisions across cycles
    // sessionLastSeen removed (was dead code, flagged in /pre-pr)
}
```

### New heartbeat cycle order
```swift
func run() async {
    while !Task.isCancelled {
        let pendingDecisions = try await checkDecisions()       // returns [Decision]
        try await checkAnsweredDecisions(currentPending: pendingDecisions)  // ← NEW
        try await checkAndDispatch()
        try await cleanupIdleSessions()
        try await checkStaleCompaniesSmart()                    // ← NEW (replaces disabled checkStaleCompanies)
    }
}
```

### `checkAnsweredDecisions` — Decision Unblock
```swift
func checkAnsweredDecisions(currentPending: [Decision]) async throws {
    let currentPendingIds = Set(currentPending.map(\.id))
    let answeredIds = previousPendingDecisionIds.subtracting(currentPendingIds)
    // answered = decisions that were pending last cycle but aren't anymore

    if !answeredIds.isEmpty {
        let runningSessions = await launcher.listRunningSessions()
        let runningCompanySlugs = Set(runningSessions.compactMap { /* extract slug */ })
        let readyTasks = try await client.getDispatcherQueue()

        for task in readyTasks {
            if !runningCompanySlugs.contains(task.companySlug) {
                logger.info("Company \(task.companySlug) unblocked — checkAndDispatch runs next")
            }
        }
    }
    previousPendingDecisionIds = currentPendingIds
}
```

### `checkStaleCompaniesSmart` — Smart Relaunch
```swift
func checkStaleCompaniesSmart() async throws {
    let stale = try await client.getStaleCompanies()
    let runningSessions = await launcher.listRunningSessions()
    let readyTasks = try await client.getDispatcherQueue()
    let companiesWithTasks = Set(readyTasks.map(\.companySlug))

    for company in stale {
        guard companiesWithTasks.contains(company.slug) else { continue }  // no tasks → skip
        guard !runningSessions.contains(where: { $0.hasPrefix("\(company.slug):") }) else { continue }  // has session → skip
        guard task.spentToday < task.budget.dailyUsd else { continue }  // broke → skip

        // All conditions met → relaunch
        try await launcher.launchTaskSession(...)
    }
}
```

---

## File 5/12: `BackendClient.swift` — curl Migration (MODIFIED)

```swift
// BEFORE: AsyncHTTPClient with connection pool
// let client = HTTPClient(configuration: .init(timeout: .init(connect: .seconds(5))))
// Problem: pool goes stale after Docker restart → hang until timeout

// AFTER: curl subprocess per request
private func curlRequest(method: String, path: String, body: Data? = nil) throws -> Data {
    let process = Process()
    process.arguments = ["curl", "-s", "--max-time", "15", "-X", method, ...]

    if let bodyData = body {
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(bodyData)  // pipe body via stdin
        stdin.fileHandleForWriting.closeFile()
    } else {
        try process.run()
    }
    // Parse response, check for HTTP errors in JSON body
}
```

**Trade-off**: ~10ms overhead per request (process spawn) vs. no stale connection bugs. At 60s heartbeat with ~5 calls/cycle, this is negligible.

---

## File 6/12: `CompanyLauncher.swift` — Dedup Fix (MODIFIED)

```swift
// BEFORE:
private static let reservedWindows: Set<String> = ["orchestrator", "board", "research"]

// AFTER: delegates to single source of truth
private static var reservedWindows: Set<String> { ProcessCleanup.reservedWindows }
```

Only change. 5 lines diff.

---

## File 7/12: `EnvironmentDetector.swift` — Smart Startup Support (NEW)

```swift
public protocol EnvironmentChecking: Sendable {
    func isDockerRunning() async -> Bool
    func isColimaRunning() async -> Bool
    func isBackendHealthy(url: String) async -> Bool
    func isLMStudioRunning(url: String) async -> Bool
    func isTmuxSessionRunning(name: String) async -> Bool
    func binaryExists(at path: String) -> Bool
    func companyCount(backendURL: String) async -> Int
}
```

Protocol + concrete `EnvironmentDetector` (shells out) + `MockEnvironmentChecker` for tests. Clean DI pattern.

---

## File 8/12: `StartupCommand.swift` — Smart Startup (NEW, 502 lines)

Largest file. 6-step flow:
1. Detect environment (Docker, Colima, LM Studio, backend)
2. Bootstrap Docker if needed
3. Check orchestrator data (company count)
4. Detect binary (compiled vs `swift run`)
5. Render status dashboard
6. Create tmux session (3 tabs), launch heartbeat, auto-attach

Uses `EnvironmentDetector` for all checks. Renders with `StartupRenderer`.

---

## File 9/12: `DecideCommand.swift` — Multiline Fix (MODIFIED)

```swift
// NEW: readMultilineInput() at top of file
private func readMultilineInput() -> String {
    var lines: [String] = []
    while let line = readLine(strippingNewline: true) {
        if line.isEmpty && !lines.isEmpty { break }  // empty after content = submit
        if line.isEmpty && lines.isEmpty { break }    // empty with no content = skip
        lines.append(line)
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}
```

**Before**: Each pasted line was a separate answer. Multiline paste answered N questions at once.
**After**: Lines collected until double-enter. Multiline paste works correctly.

---

## File 10/12: `SessionStats.swift` — Git Line Counts (NEW)

Computes `+lines / -lines` between sessions using `git diff --stat`. Stores last session timestamp in `~/.config/shiki/last-session`. Used by `StartupRenderer` for the dashboard.

---

## File 11/12: `StartupRenderer.swift` — Dashboard Display (NEW)

Box-drawing dashboard with:
- Last session / upcoming section
- Per-project git stats with maturity indicator (`≈ mature` when +/- ratio ~1.0)
- Weekly aggregate
- Pending decisions + stale companies + spend

---

## File 12/12: `ProcessCleanupTests.swift` — Test Coverage (NEW)

5 suites, 12 new tests total across 4 test files:

```
Process cleanup on stop (5 tests):
  - collectChildPIDs with nonexistent session → empty
  - killProcessTree with nonexistent PID → no crash
  - cleanupSession with nonexistent session → zero counts
  - reserved windows includes orchestrator/board/research
  - findOrphanedClaudeProcesses returns [pid_t]

Smart stale company relaunch (2 tests):
  - Skip if session exists
  - Skip if budget exhausted

Decision unblock (2 tests):
  - Set diff detects answered decisions
  - Dead session detected for re-dispatch

Session health (3 tests):
  - Stale after 3 minutes
  - Fresh under 3 minutes
  - Unknown session (no heartbeat) ≠ stale
```

---

## Navigation Quick Reference

| Section | File | Lines | Risk |
|---------|------|-------|------|
| [File 1](#file-112-shikictlswift--entry-point) | ShikiCtl.swift | 25 | Low |
| [File 2](#file-212-processcleanupswift--ghost-process-killer-new) | ProcessCleanup.swift | 182 | **High** |
| [File 3](#file-312-stopcommandswift--graceful-shutdown-rewritten) | StopCommand.swift | 106 | **High** |
| [File 4](#file-412-heartbeatloopswift--orchestrator-brain-modified) | HeartbeatLoop.swift | 261 | **High** |
| [File 5](#file-512-backendclientswift--curl-migration-modified) | BackendClient.swift | 195 | Medium |
| [File 6](#file-612-companylauncherswift--dedup-fix-modified) | CompanyLauncher.swift | 254 | Low |
| [File 7](#file-712-environmentdetectorswift--smart-startup-support-new) | EnvironmentDetector.swift | 122 | Low |
| [File 8](#file-812-startupcommandswift--smart-startup-new-502-lines) | StartupCommand.swift | 502 | Medium |
| [File 9](#file-912-decidecommandswift--multiline-fix-modified) | DecideCommand.swift | 116 | Low |
| [File 10](#file-1012-sessionstatsswift--git-line-counts-new) | SessionStats.swift | 221 | Low |
| [File 11](#file-1112-startuprendererswift--dashboard-display-new) | StartupRenderer.swift | 236 | Low |
| [File 12](#file-1212-processcleanuptestsswift--test-coverage-new) | ProcessCleanupTests.swift | 158 | Low |

**Start with High-risk files (2, 3, 4)** — that's where the bugs were fixed.
