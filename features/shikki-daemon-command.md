---
title: "shi daemon — Headless Kernel for Boot-Time Auto-Start"
status: draft
priority: P1
project: shikki
created: 2026-04-03
authors: ["@Daimyo"]
tags: [daemon, kernel, launchd, systemd, boot, headless]
depends-on: []
relates-to: [shikki-kernel-extension-architecture.md, shikki-nats-client-wiring.md]
epic-branch: feature/shi-daemon
validated-commit: —
test-run-id: —
---

# Feature: shi daemon — Headless Kernel for Boot-Time Auto-Start
> Created: 2026-04-03 | Status: Draft | Owner: @Daimyo

## Context

ShikkiKernel is the daemon. It runs inside `shi start` which creates a tmux session, launches panes, shows splash. But `shi start` is interactive — it requires a terminal. To run Shikki at computer boot (macOS LaunchAgent or Linux systemd), we need a headless mode that starts the kernel loop without tmux, without splash, without interactive input. When the user later opens a terminal and runs `shi start`, it should detect the already-running daemon and just attach.

ShikkiKernel already has everything: ManagedService protocol, adaptive tick scheduling, wake-on-event, signal handlers, escalation. The kernel's `run()` method is an infinite async loop. We just need a CLI entry point that calls it without the tmux wrapper.

## Business Rules

```
BR-01: shi daemon MUST start ShikkiKernel in headless mode (no tmux, no splash, no interactive I/O)
BR-02: shi daemon MUST register all core ManagedServices: natsServer, healthMonitor, eventPersister, sessionSupervisor, staleCompanyDetector, taskScheduler
BR-03: shi daemon MUST write a PID file to ~/.shikki/daemon.pid on start
BR-04: shi daemon MUST remove PID file on clean shutdown (SIGTERM/SIGINT)
BR-05: shi daemon MUST log to ~/.shikki/logs/daemon.log with log rotation (max 5 files, 10MB each)
BR-06: shi daemon MUST expose a health endpoint: ~/.shikki/daemon.sock (Unix socket) or NATS ping
BR-07: shi start MUST detect running daemon via PID file check — if alive, skip kernel boot and just create tmux layout
BR-08: shi stop MUST send SIGTERM to daemon PID if running, wait for clean shutdown (max 10s), then SIGKILL
BR-09: shi status MUST show daemon state: running/stopped, PID, uptime, registered services, NATS status
BR-10: shi daemon --install MUST generate and install the platform service file (launchd plist or systemd unit)
BR-11: shi daemon --uninstall MUST remove the service file and stop the daemon
BR-12: On macOS, launchd plist MUST be installed to ~/Library/LaunchAgents/dev.shikki.daemon.plist
BR-13: On Linux, systemd unit MUST be installed to ~/.config/systemd/user/shikki-daemon.service
BR-14: shi daemon MUST handle SIGHUP by reloading config (re-read ~/.shikki/config.yaml) without restart
BR-15: shi daemon MUST emit daemon_started and daemon_stopped events to ShikiDB via data-sync
BR-16: Daemon MUST NOT depend on tmux, Docker, or any interactive tool — pure kernel + NATS
BR-17: shi daemon --foreground MUST run in foreground (default), --background MUST fork and detach
BR-18: shi daemon --mode persistent (default) — full kernel event loop, holds NATS connections, manages all services. This is the primary node.
BR-19: shi daemon --mode scheduled — runs a single tick cycle then exits. Designed for secondary nodes on the same device: launchd/systemd runs it on an interval (e.g., every 30s). No persistent NATS connections — connects, ticks, publishes results, disconnects. Lighter than persistent: no held sockets, no memory between invocations.
BR-20: Scheduled mode MUST connect to the primary daemon's NATS server (not start its own). PID file uses ~/.shikki/daemon-scheduled.pid to avoid conflict with primary.
BR-21: Scheduled mode MUST register only lightweight services (taskScheduler, staleCompanyDetector). Heavy services (natsServer, sessionSupervisor) stay on the primary.
BR-22: shi daemon --install --mode scheduled MUST generate a separate launchd plist / systemd timer that runs shi daemon --mode scheduled every 30s
```

## TDDP — Test Summary Table

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01 | Core (80%) | Unit | When daemon starts → kernel.run() called without tmux |
| T-02 | BR-02 | Core (80%) | Unit | When daemon starts → all 6 core services registered |
| T-03 | BR-03, BR-04 | Core (80%) | Unit | When daemon starts → PID file written, on stop → removed |
| T-04 | BR-05 | Core (80%) | Unit | When daemon logs → writes to daemon.log with rotation |
| T-05 | BR-06 | Core (80%) | Integration | When daemon running → health check responds |
| T-06 | BR-07 | Core (80%) | Unit | When shi start finds daemon PID alive → skips kernel boot |
| T-07 | BR-07 | Core (80%) | Unit | When shi start finds stale PID → removes PID file and boots normally |
| T-08 | BR-08 | Core (80%) | Unit | When shi stop called → sends SIGTERM, waits, daemon exits |
| T-09 | BR-09 | Core (80%) | Unit | When shi status with daemon running → shows PID, uptime, services |
| T-10 | BR-09 | Core (80%) | Unit | When shi status with no daemon → shows "stopped" |
| T-11 | BR-10 | Smoke (CLI) | Integration | When shi daemon --install on macOS → plist created at correct path |
| T-12 | BR-11 | Smoke (CLI) | Integration | When shi daemon --uninstall → plist removed, daemon stopped |
| T-13 | BR-13 | Smoke (CLI) | Integration | When shi daemon --install on Linux → systemd unit created |
| T-14 | BR-14 | Core (80%) | Unit | When SIGHUP received → config reloaded without restart |
| T-15 | BR-15 | Core (80%) | Unit | When daemon starts/stops → events emitted to ShikiDB |
| T-16 | BR-16 | Core (80%) | Unit | When daemon starts → no tmux/Docker dependency |
| T-17 | BR-17 | Smoke (CLI) | Integration | When --background → process forks and parent exits |
| T-18 | BR-18 | Core (80%) | Unit | When --mode persistent → full kernel loop, NATS held |
| T-19 | BR-19 | Core (80%) | Unit | When --mode scheduled → single tick, then exit |
| T-20 | BR-20 | Core (80%) | Unit | When scheduled mode → connects to primary's NATS, no own server |
| T-21 | BR-21 | Core (80%) | Unit | When scheduled mode → only lightweight services registered |
| T-22 | BR-22 | Smoke (CLI) | Integration | When --install --mode scheduled → separate timer/plist created |

### S3 Test Scenarios

```
T-01 [BR-01, Core 80%]:
When shi daemon runs:
  → ShikkiKernel.run() is called
  → no tmux session created
  → no SplashRenderer.render() called
  → stdin is not read (headless)

T-02 [BR-02, Core 80%]:
When daemon starts the kernel:
  → entries contains .natsServer service
  → entries contains .healthMonitor service
  → entries contains .eventPersister service
  → entries contains .sessionSupervisor service
  → entries contains .staleCompanyDetector service
  → entries contains .taskScheduler service

T-03 [BR-03, BR-04, Core 80%]:
When daemon starts:
  → ~/.shikki/daemon.pid created with current process PID
  if PID file already exists with alive PID:
    → daemon exits with error "Daemon already running (PID: XXXX)"
  if PID file exists with dead PID:
    → removes stale PID file and starts normally
When daemon receives SIGTERM:
  → kernel.run() loop exits
  → PID file deleted
  → exit code 0

T-04 [BR-05, Core 80%]:
When daemon logs:
  → writes to ~/.shikki/logs/daemon.log
  → when file exceeds 10MB → rotated to daemon.log.1
  → max 5 rotated files kept (daemon.log.1 through daemon.log.5)
  → oldest deleted when 6th rotation would occur

T-05 [BR-06, Core 80%, Integration]:
When daemon is running:
  if NATS server is managed by daemon:
    → NATSHealthCheck.ping() returns .ok
  → DaemonHealthCheck.check() returns running + uptime + service count

T-06 [BR-07, Core 80%]:
When shi start runs and ~/.shikki/daemon.pid exists:
  if PID is alive (kill -0):
    → skips kernel boot, Docker bootstrap, NATS start
    → creates tmux layout and attaches
    → prints "Daemon already running (PID: XXXX), attaching..."

T-07 [BR-07, Core 80%]:
When shi start runs and ~/.shikki/daemon.pid exists:
  if PID is dead (kill -0 fails):
    → removes stale PID file
    → proceeds with normal startup (kernel + tmux)

T-08 [BR-08, Core 80%]:
When shi stop runs:
  if daemon PID file exists and PID is alive:
    → sends SIGTERM to PID
    → waits up to 10 seconds for process to exit
    if process exits within 10s:
      → prints "Daemon stopped (PID: XXXX)"
    if process still alive after 10s:
      → sends SIGKILL
      → prints "Daemon killed (PID: XXXX)"
  if no PID file:
    → prints "Daemon not running"

T-09 [BR-09, Core 80%]:
When shi status runs and daemon is running:
  → shows "Daemon: running (PID: XXXX)"
  → shows "Uptime: Xh Xm"
  → shows "Services: 6 registered (natsServer, healthMonitor, ...)"
  → shows "NATS: connected / disconnected"

T-10 [BR-09, Core 80%]:
When shi status runs and daemon is not running:
  → shows "Daemon: stopped"

T-11 [BR-10, BR-12, Smoke CLI]:
When shi daemon --install runs on macOS:
  → creates ~/Library/LaunchAgents/dev.shikki.daemon.plist
  → plist contains correct binary path (which shi)
  → plist has RunAtLoad=true, KeepAlive=true
  → plist logs to /tmp/shikki-daemon.log
  → runs launchctl load on the plist

T-12 [BR-11, Smoke CLI]:
When shi daemon --uninstall runs:
  → runs launchctl unload on the plist
  → deletes the plist file
  → sends SIGTERM to daemon if running

T-13 [BR-13, Smoke CLI]:
When shi daemon --install runs on Linux:
  → creates ~/.config/systemd/user/shikki-daemon.service
  → unit has Type=simple, Restart=always
  → runs systemctl --user enable shikki-daemon
  → runs systemctl --user start shikki-daemon

T-14 [BR-14, Core 80%]:
When daemon receives SIGHUP:
  → re-reads ~/.shikki/config.yaml
  → updates TUITheme.active if theme changed
  → logs "Config reloaded"
  → kernel continues running (no restart)

T-15 [BR-15, Core 80%]:
When daemon starts:
  → posts daemon_started event to ShikiDB with PID, hostname, service list
When daemon stops cleanly:
  → posts daemon_stopped event to ShikiDB with uptime duration

T-16 [BR-16, Core 80%]:
When daemon starts:
  → does not call tmux
  → does not check Docker/Colima
  → does not call SplashRenderer
  → only initializes: kernel, NATS server, managed services

T-17 [BR-17, Smoke CLI]:
When shi daemon --background runs:
  → parent process forks
  → parent prints PID and exits immediately
  → child process continues running kernel
  → PID file contains child PID
When shi daemon (default, no flag):
  → runs in foreground (no fork)
  → Ctrl+C sends SIGINT → clean shutdown

T-18 [BR-18, Core 80%]:
When shi daemon --mode persistent (or default, no --mode flag):
  → ShikkiKernel.run() starts infinite adaptive loop
  → NATS connections held open (persistent TCP)
  → all 6 core services registered
  → process stays alive until SIGTERM

T-19 [BR-19, Core 80%]:
When shi daemon --mode scheduled:
  → connects to primary daemon's NATS server (does NOT start its own)
  → registers only lightweight services (taskScheduler, staleCompanyDetector)
  → runs exactly 1 tick cycle (collectDueServices → execute → publish results)
  → disconnects NATS
  → exits with code 0
  → total runtime < 5 seconds

T-20 [BR-20, Core 80%]:
When scheduled mode starts:
  if primary daemon is running (daemon.pid alive):
    → reads NATS URL from primary's NATSConfig
    → connects as client (no nats-server management)
  if primary daemon is NOT running:
    → exits with error "Primary daemon not running — start with: shi daemon"
  → PID file at ~/.shikki/daemon-scheduled.pid (separate from primary)

T-21 [BR-21, Core 80%]:
When scheduled mode registers services:
  → taskScheduler registered (lightweight, reads queue)
  → staleCompanyDetector registered (lightweight, checks timestamps)
  → natsServer NOT registered (managed by primary)
  → sessionSupervisor NOT registered (needs persistent state)
  → healthMonitor NOT registered (primary handles health)
  → eventPersister NOT registered (primary handles persistence)

T-22 [BR-22, Smoke CLI]:
When shi daemon --install --mode scheduled on macOS:
  → creates ~/Library/LaunchAgents/dev.shikki.daemon-scheduled.plist
  → plist has StartInterval=30 (every 30 seconds)
  → plist does NOT have KeepAlive (process exits after each tick)
  → separate from dev.shikki.daemon.plist (primary)
When shi daemon --install --mode scheduled on Linux:
  → creates ~/.config/systemd/user/shikki-daemon-scheduled.timer
  → timer has OnCalendar=*:*:0/30 (every 30 seconds)
  → separate service unit: shikki-daemon-scheduled.service (Type=oneshot)
```

## Wave Dispatch Tree

```
Wave 1: DaemonCommand + PID Management
  ├── DaemonCommand.swift — headless kernel entry point
  ├── DaemonPIDManager.swift — write/read/clean PID file, stale detection
  └── DaemonServiceFactory.swift — creates all 6 ManagedServices for headless mode
  Input:  ShikkiKernel, ManagedService implementations
  Output: shi daemon runs kernel headlessly with PID tracking
  Tests:  T-01, T-02, T-03, T-16
  Gate:   swift test --filter Daemon → green
  ║
  ╠══ Wave 2: Lifecycle Integration ← BLOCKED BY Wave 1
  ║   ├── Update StartupCommand — detect running daemon, skip kernel boot
  ║   ├── DaemonStopCommand.swift — SIGTERM/SIGKILL with timeout
  ║   ├── Update StatusCommand — show daemon state
  ║   └── Log rotation for daemon.log
  ║   Input:  DaemonPIDManager
  ║   Output: shi start/stop/status aware of daemon
  ║   Tests:  T-04, T-06, T-07, T-08, T-09, T-10
  ║   Gate:   shi start with daemon running → attaches without re-booting
  ║   ║
  ║   ╠══ Wave 3: Platform Service Install ← BLOCKED BY Wave 2
  ║   ║   ├── LaunchdInstaller.swift — generate + load plist (macOS)
  ║   ║   ├── SystemdInstaller.swift — generate + enable unit (Linux)
  ║   ║   └── shi daemon --install / --uninstall flags
  ║   ║   Input:  Binary path, platform detection
  ║   ║   Output: Daemon runs at boot automatically
  ║   ║   Tests:  T-11, T-12, T-13
  ║   ║   Gate:   shi daemon --install creates correct service file
  ║   ║
  ║   ╚══ Wave 4: Events + Config Reload ← BLOCKED BY Wave 1
  ║       ├── SIGHUP handler for config reload
  ║       ├── daemon_started/daemon_stopped events to ShikiDB
  ║       └── --background fork mode
  ║       Input:  ShikiDB data-sync, signal handling
  ║       Output: Full daemon lifecycle with observability
  ║       Tests:  T-05, T-14, T-15, T-17
  ║       Gate:   daemon emits events to DB, SIGHUP reloads config
  ║
  ╚══ Wave 5: Scheduled Mode (Secondary Node) ← BLOCKED BY Wave 3
      ├── ScheduledDaemonRunner.swift — single-tick-then-exit mode
      ├── DaemonServiceFactory — lightweight service set for scheduled mode
      ├── LaunchdInstaller — scheduled plist (StartInterval, no KeepAlive)
      └── SystemdInstaller — timer unit (OnCalendar, Type=oneshot)
      Input:  Primary daemon's NATS server, lightweight services
      Output: Secondary node ticks on interval, publishes results, exits
      Tests:  T-18, T-19, T-20, T-21, T-22
      Gate:   shi daemon --mode scheduled runs, ticks once, exits cleanly
```

## Implementation Waves

### Wave 1: DaemonCommand + PID Management
**Files:**
- `Sources/shikki/Commands/DaemonCommand.swift` — `shi daemon` subcommand, calls kernel.run()
- `Sources/ShikkiKit/Kernel/Core/DaemonPIDManager.swift` — PID file read/write/clean, stale detection
- `Sources/ShikkiKit/Kernel/Core/DaemonServiceFactory.swift` — creates ManagedService array for headless mode
- `Tests/ShikkiKitTests/Kernel/DaemonPIDManagerTests.swift`
- `Tests/ShikkiKitTests/Kernel/DaemonServiceFactoryTests.swift`
**Tests:** T-01, T-02, T-03, T-16
**BRs:** BR-01, BR-02, BR-03, BR-04, BR-16
**Deps:** ShikkiKernel (done), ManagedService implementations (done)
**Gate:** `swift test --filter Daemon` green

### Wave 2: Lifecycle Integration ← BLOCKED BY Wave 1
**Files:**
- `Sources/shikki/Commands/StartupCommand.swift` — modify to check daemon PID before boot
- `Sources/shikki/Commands/DaemonStopCommand.swift` — SIGTERM → wait → SIGKILL
- `Sources/shikki/Commands/StatusCommand.swift` — modify to show daemon state
- `Sources/ShikkiKit/Kernel/Core/DaemonLogger.swift` — file logging with rotation
- `Tests/ShikkiKitTests/Kernel/DaemonLifecycleTests.swift`
**Tests:** T-04, T-06, T-07, T-08, T-09, T-10
**BRs:** BR-05, BR-07, BR-08, BR-09
**Deps:** Wave 1 (DaemonPIDManager)
**Gate:** `shi start` detects running daemon

### Wave 3: Platform Service Install ← BLOCKED BY Wave 2
**Files:**
- `Sources/ShikkiKit/Kernel/Core/LaunchdInstaller.swift` — plist generation + launchctl
- `Sources/ShikkiKit/Kernel/Core/SystemdInstaller.swift` — unit generation + systemctl
- `Sources/shikki/Commands/DaemonCommand.swift` — add --install / --uninstall flags
- `Tests/ShikkiKitTests/Kernel/ServiceInstallerTests.swift`
**Tests:** T-11, T-12, T-13
**BRs:** BR-10, BR-11, BR-12, BR-13
**Deps:** Wave 2 (daemon lifecycle complete)
**Gate:** `shi daemon --install` creates correct service file per platform

### Wave 4: Events + Config Reload ← BLOCKED BY Wave 1
**Files:**
- `Sources/ShikkiKit/Kernel/Core/DaemonSignalHandler.swift` — SIGHUP config reload
- `Sources/ShikkiKit/Kernel/Core/DaemonEventEmitter.swift` — daemon_started/stopped to ShikiDB
- `Sources/shikki/Commands/DaemonCommand.swift` — add --background fork mode
- `Tests/ShikkiKitTests/Kernel/DaemonSignalTests.swift`
**Tests:** T-05, T-14, T-15, T-17
**BRs:** BR-06, BR-14, BR-15, BR-17
**Deps:** Wave 1 (daemon running)
**Gate:** SIGHUP reloads config, events in ShikiDB

### Wave 5: Scheduled Mode (Secondary Node) ← BLOCKED BY Wave 3
**Files:**
- `Sources/ShikkiKit/Kernel/Core/ScheduledDaemonRunner.swift` — single-tick runner: connect NATS → tick due services → publish results → disconnect → exit
- `Sources/ShikkiKit/Kernel/Core/DaemonServiceFactory.swift` — modify to accept mode, return lightweight service set for scheduled
- `Sources/ShikkiKit/Kernel/Core/LaunchdInstaller.swift` — modify to generate scheduled plist (StartInterval=30, no KeepAlive)
- `Sources/ShikkiKit/Kernel/Core/SystemdInstaller.swift` — modify to generate timer unit (OnCalendar=*:*:0/30, Type=oneshot)
- `Sources/shikki/Commands/DaemonCommand.swift` — add --mode persistent|scheduled flag
- `Tests/ShikkiKitTests/Kernel/ScheduledDaemonTests.swift`
**Tests:** T-18, T-19, T-20, T-21, T-22
**BRs:** BR-18, BR-19, BR-20, BR-21, BR-22
**Deps:** Wave 3 (platform installers exist to extend)
**Gate:** `shi daemon --mode scheduled` ticks once and exits cleanly

## Reuse Audit

| Utility | Exists In | Decision |
|---------|-----------|----------|
| ShikkiKernel.run() | Kernel/Core/ShikkiKernel.swift | Reuse directly — it's the whole daemon loop |
| ManagedService impls | Kernel/Core/*.swift | Reuse — 6 services already implemented |
| NATSServerManager | NATS/NATSServerManager.swift | Already a ManagedService — register it |
| Signal handling | ShikkiKernel (installSignalHandlers) | Extend for SIGHUP |
| PID file pattern | NATSConfig (PID for nats-server) | Extract pattern to DaemonPIDManager |
| EnvironmentDetector | Kernel/Core/EnvironmentDetector.swift | NOT used — daemon skips env detection |
| SplashRenderer | TUI/SplashRenderer.swift | NOT used — daemon is headless |

## Platform Service Files

### macOS LaunchAgent

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.shikki.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{BINARY_PATH}}</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{{HOME}}/.shikki/logs/daemon.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>{{HOME}}/.shikki/logs/daemon.stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

### Linux systemd User Unit

```ini
[Unit]
Description=Shikki Daemon — AI Development Orchestrator
After=network.target

[Service]
Type=simple
ExecStart={{BINARY_PATH}} daemon
Restart=always
RestartSec=5
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
```

## @t Review

### @Sensei (CTO)
ShikkiKernel.run() IS the daemon — it's already an infinite async loop with signal handling, adaptive sleep, and service management. DaemonCommand is literally: create services, create kernel, call kernel.run(), block until signal. Maybe 50 LOC. The real work is in Wave 2 (lifecycle integration with shi start/stop/status) and Wave 3 (platform installers).

The --background fork mode (BR-17) is tricky in Swift — `posix_spawn` or `Foundation.Process` with self-exec. Consider whether launchd/systemd already handle backgrounding (they do), making --background redundant for installed daemons. Keep it for manual use: `shi daemon --background` for quick testing.

### @Ronin (Adversarial)
- **PID file race**: Two shi daemon starts simultaneously could both write PID files. Use `flock()` or `O_EXCL` on the PID file.
- **Zombie services**: If nats-server crashes inside the daemon, NATSServerManager should restart it (RestartPolicy.always). Verify this path works headlessly.
- **Log rotation under load**: If daemon logs heavily (e.g., during dispatch storm), rotation could block the kernel tick. Use async log flushing.
- **launchctl on Sonoma+**: Apple has been deprecating launchctl subcommands. Test on latest macOS. `launchctl bootstrap gui/$(id -u)` is the new way.

### @Katana (Security)
- PID file at ~/.shikki/daemon.pid — user-writable, no privilege escalation
- Unix socket at ~/.shikki/daemon.sock — file permissions restrict access to user
- LaunchAgent (not LaunchDaemon) — runs as user, not root
- systemd --user — runs as user, not system
- No elevated privileges needed anywhere

### @Kintsugi (Philosophy)
The daemon is invisible infrastructure. When it works, the user doesn't think about it — they open their laptop, type `shi start`, and everything is already warm. NATS is running, health is monitored, events are flowing. The daemon is the foundation that makes "instant-on" possible. Name it `shi daemon` not `shid` — one binary, one name, one identity.
