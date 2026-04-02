---
title: "Compiled Swift First-Run Setup Wizard"
status: spec
priority: P0
project: shikki
created: 2026-04-02
authors: "@Daimyo vision"
tags: [setup, ux, platform]
---

# Feature: Compiled Swift First-Run Setup Wizard
> Created: 2026-04-02 | Status: Spec | Owner: @Daimyo

## Context

The current `setup.sh` (193 lines) is a bash script that installs dependencies, builds shikki, creates directories, symlinks the binary, and runs `shikki doctor`. It works — but only on macOS with Homebrew, has zero automated tests, no error recovery, and dumps a wall of sequential output with no user control.

**Current code**: `setup.sh` (repo root, 193 lines)

**What `setup.sh` does today**:
1. Checks Swift is installed
2. Checks/installs Homebrew (macOS-only, hardcoded)
3. Installs required tools: `tmux`
4. Installs optional tools: `delta`, `fzf`, `ripgrep`, `bat` (no user choice — installs all)
5. Builds `shikki` + `shikki-test`
6. Symlinks to `~/.local/bin/`
7. Creates `.shikki/` workspace directories
8. Ensures `~/.local/bin` is on PATH
9. Runs `shikki doctor`

**Problems**:
- macOS-only: Homebrew install is hardcoded, no `apt` support for Linux
- No tests: zero test coverage on any step
- No user experience: no splash, no progressive disclosure, no choice on optional deps
- No error recovery: `set -euo pipefail` means any failure aborts completely with no resume
- No state persistence: if step 7 fails, re-running starts from step 1 again
- No background work: each check runs sequentially even though dependency lookups are independent
- Hardcoded paths: `~/.local/bin`, `/opt/homebrew/bin/brew` baked into the script

## Problem

The setup experience is the user's first impression of Shikki. Today it is a fragile, macOS-only bash script with no tests, no error recovery, and no polish. As Shikki targets Linux (Ubuntu 22.04+) alongside macOS, the bash script becomes a maintenance liability. A compiled Swift setup wizard provides: cross-platform support via `#if os()`, full test coverage via Swift Testing, persistent state for resume/retry, and a polished first-run experience with animated splash + background pre-loading.

## Synthesis

**Goal**: Replace `setup.sh` with a compiled Swift first-run wizard that auto-triggers on first launch, works on macOS and Linux, persists progress for resume, and provides a beautiful terminal experience.

**Scope**:
- `SetupState` model: first-run detection, step persistence, JSON serialization
- `DependencyChecker`: platform-aware tool discovery via `which`, install commands via `brew`/`apt`
- `SetupWizard`: orchestrator that drives the multi-step flow with background pre-loading
- `OptionalDependency` model: name, description, weight display, install command per platform
- ASCII splash screen with Blue Flame logo, overlapped with background dependency checks
- `shikki setup` CLI command with `--retry` and `--force` flags
- Post-install verification: actually invoke each tool, not just check file existence
- Error recovery: clear messages, manual fix commands, idempotent steps

**Out of scope**:
- Removing `setup.sh` (keep as fallback until Swift setup is battle-tested)
- Build step (`swift build` of shikki itself — that is a bootstrap chicken-and-egg; the setup binary must already be compiled)
- Symlink creation (handled by the existing build/install pipeline)
- Network-dependent features beyond package manager installs
- GUI or web-based setup (terminal-only)

**Success criteria**:
- `shikki` on first run (no `~/.shikki/setup.json`) triggers the setup wizard automatically
- Setup completes successfully on macOS (Homebrew) and Ubuntu 22.04+ (apt)
- All required dependency failures block with actionable fix instructions
- `shikki setup --retry` resumes from last successful step
- `shikki setup --force` reruns everything from scratch
- Splash screen animation overlaps with background dependency checking (no wasted wall-clock time)
- Every step is idempotent — safe to re-run any number of times
- All setup logic has unit tests (SetupState, DependencyChecker, OptionalDependency, verification)
- Setup works offline (skips optional deps, uses cached required deps)

**Dependencies**:
- ShikkiKit (for AppLog, shell execution utilities)
- Swift 5.9+ (for `#if os()` conditional compilation)

## Business Rules

```
BR-01: First-run detection MUST use SetupState.isFirstRun (parsed from ~/.shikki/setup.json), not raw file existence checks
BR-02: Splash screen animation MUST overlap with background dependency checking — begin async checks before splash finishes (~3 seconds)
BR-03: Required dependency failure (git, tmux, swift, sqlite3) MUST block setup with a clear error message and platform-specific manual fix command
BR-04: Optional dependency prompts MUST show download size estimate before asking the user to install
BR-05: Every install step MUST be idempotent — re-running a completed step is a no-op that succeeds
BR-06: Setup MUST work without network — skip optional dependency installs, proceed with already-installed required deps
BR-07: Platform detection MUST use Swift #if os(macOS) / #if os(Linux), not shell uname or runtime checks
BR-08: All dependency paths MUST be resolved via Process("which", toolName), not hardcoded filesystem paths
BR-09: Setup progress MUST be persisted to ~/.shikki/setup.json after each completed step — crash at step N means retry resumes at step N
BR-10: Post-install verification MUST actually run each tool (e.g., git --version, tmux -V) and parse output, not just check file existence
```

## Test Plan

### Scenario 1: First run detected — no setup.json exists
```
Setup:   FileManager reports ~/.shikki/setup.json does not exist
BR-01 → SetupState.load() returns state with isFirstRun == true, completedSteps == []
Result:  SetupState.isFirstRun == true
Verify:  No file I/O beyond the existence check
```

### Scenario 2: Subsequent run — setup.json exists with all steps completed
```
Setup:   ~/.shikki/setup.json contains {"completedSteps":["splash","requiredDeps","optionalDeps","verification","directories"],"version":"0.3.0"}
BR-01 → SetupState.load() returns state with isFirstRun == false
Result:  SetupState.isFirstRun == false, completedSteps.count == 5
Verify:  Setup wizard does NOT trigger automatically
```

### Scenario 3: DependencyChecker finds all required tools installed
```
Setup:   MockShellExecutor returns success for which git, which tmux, which swift, which sqlite3
BR-08 → Each tool resolved via which, not hardcoded path
Result:  DependencyChecker.checkRequired() returns [.git: .installed("/usr/bin/git"), .tmux: .installed("/opt/homebrew/bin/tmux"), ...]
Verify:  All 4 required deps report .installed with resolved path
```

### Scenario 4: DependencyChecker reports missing required tool with platform-specific install command
```
Setup:   MockShellExecutor returns failure for which tmux (exit code 1)
BR-03 → tmux reported as .missing with install command
BR-07 → On macOS: installCommand == "brew install tmux"; on Linux: installCommand == "sudo apt install -y tmux"
Result:  DependencyChecker.checkRequired() returns [.tmux: .missing(installCommand: "brew install tmux")]
Verify:  Install command matches current platform
```

### Scenario 5: OptionalDependency model provides correct metadata
```
Setup:   OptionalDependency.allCases enumerated
BR-04 → Each dependency has non-empty description AND non-zero weight string
Result:  OptionalDependency.delta.description == "Better diffs in terminal"
         OptionalDependency.delta.estimatedSize == "~5MB"
         OptionalDependency.delta.installCommand(for: .macOS) == "brew install git-delta"
         OptionalDependency.delta.installCommand(for: .linux) == "sudo apt install -y git-delta"
Verify:  All 5 optional deps have description, size, and per-platform install commands
```

### Scenario 6: SetupWizard runs steps in correct order with background pre-loading
```
Setup:   MockDependencyChecker, MockSplashRenderer, MockPromptHandler
BR-02 → Splash animation starts; background checks begin concurrently
         Splash completes after ~3s; dependency results already available
Result:  Step execution order: [splash+backgroundCheck, showRequiredStatus, promptOptional, install, verify, directories, persist]
Verify:  Background check completes before or during splash (not after)
```

### Scenario 7: Setup state persists progress after each step
```
Setup:   SetupState starts with completedSteps == []
         Step "requiredDeps" completes successfully
BR-09 → setup.json written with completedSteps: ["splash", "requiredDeps"]
         Simulate crash (do not call subsequent steps)
         Re-load SetupState from disk
Result:  SetupState.completedSteps == ["splash", "requiredDeps"]
Verify:  JSON file on disk matches in-memory state after each step
```

### Scenario 8: --retry resumes from last successful step
```
Setup:   setup.json contains completedSteps: ["splash", "requiredDeps"] (crashed during optionalDeps)
BR-09 → SetupState.load() finds 2 completed steps
Result:  SetupWizard.run(mode: .retry) skips splash and requiredDeps, starts at optionalDeps
Verify:  MockSplashRenderer.renderCount == 0; MockDependencyChecker.checkRequiredCount == 0
```

### Scenario 9: --force reruns everything from scratch
```
Setup:   setup.json contains completedSteps: ["splash", "requiredDeps", "optionalDeps", "verification", "directories"]
BR-05 → Each step is idempotent, safe to re-run
Result:  SetupWizard.run(mode: .force) deletes existing state, runs all steps from scratch
Verify:  MockSplashRenderer.renderCount == 1; all steps executed; new setup.json written
```

### Scenario 10: Post-install verification catches broken install
```
Setup:   MockShellExecutor returns success for which git but git --version returns exit code 127
BR-10 → Verification runs actual tool invocation, not just which check
Result:  VerificationResult.git == .broken(error: "git found at /usr/bin/git but --version failed (exit 127)")
Verify:  Verification distinguishes .installed + .working from .installed + .broken
```

### Scenario 11: Setup works offline — skips optional deps
```
Setup:   MockNetworkChecker.isOnline == false; all required deps already installed
BR-06 → Optional dependency prompt is skipped with message "Offline — skipping optional tools"
BR-03 → Required deps verified from local cache (already installed)
Result:  Setup completes successfully without network; optional deps section shows "skipped (offline)"
Verify:  No brew/apt install commands executed
```

### Scenario 12: Required dependency failure blocks setup
```
Setup:   MockShellExecutor returns failure for which swift (not installed)
BR-03 → Setup blocked with error: "Swift is required but not installed"
         Platform-specific fix shown: macOS → "Install from https://swift.org/install or via Xcode"
         Linux → "sudo apt install -y swift" or "https://swift.org/install"
Result:  SetupWizard.run() throws SetupError.requiredDependencyMissing(.swift, fixCommand: "...")
Verify:  No subsequent steps executed; setup.json NOT written (setup did not start)
```

## Architecture

### New Files

| File | Purpose | BRs |
|------|---------|-----|
| `Sources/ShikkiKit/Setup/SetupState.swift` | First-run detection, step persistence, JSON Codable | BR-01, BR-09 |
| `Sources/ShikkiKit/Setup/DependencyChecker.swift` | Platform-aware tool discovery via `which`, install command generation | BR-03, BR-07, BR-08 |
| `Sources/ShikkiKit/Setup/OptionalDependency.swift` | Enum of optional tools with description, weight, per-platform install | BR-04 |
| `Sources/ShikkiKit/Setup/SetupWizard.swift` | Orchestrator: splash, checks, prompts, installs, verification, persistence | BR-02, BR-05, BR-06 |
| `Sources/ShikkiKit/Setup/SetupVerifier.swift` | Post-install verification — runs each tool and parses output | BR-10 |
| `Sources/ShikkiKit/Setup/SplashRenderer.swift` | ASCII splash screen with Blue Flame logo + version | BR-02 |
| `Tests/ShikkiKitTests/Setup/SetupStateTests.swift` | Tests for scenarios 1, 2, 7, 8, 9 | BR-01, BR-09 |
| `Tests/ShikkiKitTests/Setup/DependencyCheckerTests.swift` | Tests for scenarios 3, 4, 11, 12 | BR-03, BR-07, BR-08 |
| `Tests/ShikkiKitTests/Setup/OptionalDependencyTests.swift` | Tests for scenario 5 | BR-04 |
| `Tests/ShikkiKitTests/Setup/SetupWizardTests.swift` | Tests for scenarios 6, 8, 9 | BR-02, BR-05, BR-06 |
| `Tests/ShikkiKitTests/Setup/SetupVerifierTests.swift` | Tests for scenario 10 | BR-10 |

### Key Types

**SetupState** (`SetupState.swift`):
```swift
public struct SetupState: Codable, Sendable {
    public enum Step: String, Codable, CaseIterable, Sendable {
        case splash
        case requiredDeps
        case optionalDeps
        case install
        case verification
        case directories
    }

    public var completedSteps: [Step]
    public var version: String
    public var startedAt: Date?
    public var completedAt: Date?

    public var isFirstRun: Bool { completedSteps.isEmpty }
    public var isComplete: Bool { completedSteps.count == Step.allCases.count }

    public static let path = "\(NSHomeDirectory())/.shikki/setup.json"

    public static func load() -> SetupState { /* read from disk or return empty */ }
    public func save() throws { /* write JSON to disk */ }
    public mutating func markCompleted(_ step: Step) { /* append + save */ }
}
```

**DependencyChecker** (`DependencyChecker.swift`):
```swift
public struct DependencyChecker: Sendable {
    public enum Platform: Sendable {
        case macOS
        case linux

        public static var current: Platform {
            #if os(macOS)
            return .macOS
            #elseif os(Linux)
            return .linux
            #endif
        }
    }

    public enum RequiredTool: String, CaseIterable, Sendable {
        case git, tmux, swift, sqlite3
    }

    public enum ToolStatus: Sendable {
        case installed(path: String)
        case missing(installCommand: String)
    }

    private let shellExecutor: ShellExecuting

    public func checkRequired() async -> [RequiredTool: ToolStatus] { /* which per tool */ }
    public func checkOptional() async -> [OptionalDependency: ToolStatus] { /* which per tool */ }

    func installCommand(for tool: RequiredTool, platform: Platform) -> String {
        switch (tool, platform) {
        case (.git, .macOS):    return "brew install git"
        case (.git, .linux):    return "sudo apt install -y git"
        case (.tmux, .macOS):   return "brew install tmux"
        case (.tmux, .linux):   return "sudo apt install -y tmux"
        case (.swift, .macOS):  return "Install from https://swift.org/install or via Xcode"
        case (.swift, .linux):  return "See https://swift.org/install for Linux packages"
        case (.sqlite3, .macOS): return "brew install sqlite3"
        case (.sqlite3, .linux): return "sudo apt install -y sqlite3"
        }
    }
}
```

**OptionalDependency** (`OptionalDependency.swift`):
```swift
public enum OptionalDependency: String, CaseIterable, Codable, Sendable {
    case delta
    case bat
    case ytDlp
    case ffmpeg
    case gh

    public var binaryName: String { /* delta, bat, yt-dlp, ffmpeg, gh */ }
    public var description: String { /* human-readable purpose */ }
    public var estimatedSize: String { /* ~5MB, ~3MB, ~15MB, ~80MB, ~20MB */ }

    public func installCommand(for platform: DependencyChecker.Platform) -> String { /* per-platform */ }
}
```

**SetupWizard** (`SetupWizard.swift`):
```swift
public final class SetupWizard: Sendable {
    public enum Mode: Sendable {
        case firstRun    // triggered automatically
        case retry       // --retry: resume from last step
        case force       // --force: redo everything
    }

    private let checker: DependencyChecker
    private let verifier: SetupVerifier
    private let splash: SplashRenderer
    private let promptHandler: PromptHandling

    public func run(mode: Mode) async throws {
        var state = mode == .force ? SetupState() : SetupState.load()

        // Step 1: Splash + background pre-load (BR-02)
        if !state.completedSteps.contains(.splash) {
            async let depResults = checker.checkRequired()
            async let optResults = checker.checkOptional()
            splash.render()  // ~3 seconds, blocks display
            let required = await depResults
            let optional = await optResults
            state.markCompleted(.splash)
            // ... use cached results for next steps
        }

        // Step 2: Required deps (BR-03)
        // Step 3: Optional deps prompt (BR-04)
        // Step 4: Install (BR-05, BR-06)
        // Step 5: Verify (BR-10)
        // Step 6: Create directories + persist (BR-09)
    }
}
```

**SetupVerifier** (`SetupVerifier.swift`):
```swift
public struct SetupVerifier: Sendable {
    public enum VerificationStatus: Sendable {
        case working(version: String)
        case broken(error: String)
    }

    private let shellExecutor: ShellExecuting

    public func verify(_ tool: DependencyChecker.RequiredTool) async -> VerificationStatus {
        // Actually run: git --version, tmux -V, swift --version, sqlite3 --version
        // Parse output for version string
        // Return .broken if exit code != 0
    }
}
```

### Protocols for Testability

```swift
/// Shell command execution — mockable for tests
public protocol ShellExecuting: Sendable {
    func run(_ command: String, arguments: [String]) async throws -> ShellResult
}

/// User prompts — mockable for tests
public protocol PromptHandling: Sendable {
    func ask(_ question: String, options: [String]) async -> String
    func confirm(_ question: String) async -> Bool
}

/// Splash rendering — mockable for tests
public protocol SplashRendering: Sendable {
    func render()
}
```

### Directory Structure

```
~/.shikki/
  setup.json          # SetupState — persisted after each step
  plugins/
  sessions/
  test-logs/
```

### CLI Integration

The `shikki setup` command will be added to the existing CLI argument parser:

```
shikki setup            # Run setup (auto-detects first-run vs re-run)
shikki setup --retry    # Resume from last successful step
shikki setup --force    # Redo everything from scratch
shikki setup --status   # Show current setup state without running anything
```

First-run auto-trigger: in the main entry point, before any other command processing:
```swift
let state = SetupState.load()
if state.isFirstRun {
    try await SetupWizard(/* ... */).run(mode: .firstRun)
}
```

## TDDP

```
 1. Test: SetupState detects first run when no setup.json exists                → RED
 2. Impl: SetupState.isFirstRun check                                           → GREEN
 3. Test: SetupState detects completed run from existing setup.json              → RED
 4. Impl: SetupState.load() JSON deserialization                                 → GREEN
 5. Test: DependencyChecker finds installed tools via which                      → RED
 6. Impl: DependencyChecker with ShellExecuting.run("which", [toolName])        → GREEN
 7. Test: DependencyChecker reports missing tools with platform install commands → RED
 8. Impl: Platform-specific install commands (brew/apt)                          → GREEN
 9. Test: OptionalDependency shows correct weight and description                → RED
10. Impl: OptionalDependency model with size estimates                           → GREEN
11. Test: SetupWizard runs steps in correct order                                → RED
12. Impl: SetupWizard orchestrator                                               → GREEN
13. Test: SetupWizard overlaps splash with background dependency check           → RED
14. Impl: async let pattern for concurrent splash + checks                       → GREEN
15. Test: SetupState persists progress after each step                           → RED
16. Impl: SetupState JSON serialization with step tracking                       → GREEN
17. Test: --retry resumes from last successful step                              → RED
18. Impl: Resume logic reading from SetupState.completedSteps                    → GREEN
19. Test: --force reruns everything from scratch                                 → RED
20. Impl: Force mode clears state before running                                 → GREEN
21. Test: Post-install verification catches broken installs                      → RED
22. Impl: SetupVerifier with actual tool invocation                              → GREEN
23. Test: Setup works offline — skips optional deps                              → RED
24. Impl: Network check gating optional installs                                 → GREEN
25. Test: Required dependency failure blocks setup with fix instructions         → RED
26. Impl: SetupError.requiredDependencyMissing with platform-aware message       → GREEN
```

## Implementation Waves

### Wave 1: SetupState + DependencyChecker + platform detection (P0)
- **Files**: `SetupState.swift`, `DependencyChecker.swift`, `SetupStateTests.swift`, `DependencyCheckerTests.swift`
- **BRs**: BR-01, BR-03, BR-07, BR-08, BR-09
- **TDDP**: Steps 1-8
- **Deliverable**: Can detect first run, check deps, generate platform-specific install commands
- **Tests**: ~10 tests

### Wave 2: SetupWizard orchestrator + splash screen overlap (P0)
- **Files**: `SetupWizard.swift`, `SplashRenderer.swift`, `SetupWizardTests.swift`
- **BRs**: BR-02, BR-05, BR-06
- **TDDP**: Steps 11-14
- **Deliverable**: Full setup flow with background pre-loading during splash
- **Tests**: ~6 tests

### Wave 3: Optional dependency prompts with weights (P1)
- **Files**: `OptionalDependency.swift`, `OptionalDependencyTests.swift`
- **BRs**: BR-04
- **TDDP**: Steps 9-10
- **Deliverable**: Interactive [all / select / skip] prompt with per-tool size display
- **Tests**: ~5 tests

### Wave 4: Post-install verification + error recovery (P1)
- **Files**: `SetupVerifier.swift`, `SetupVerifierTests.swift`
- **BRs**: BR-10, BR-03
- **TDDP**: Steps 21-26
- **Deliverable**: Verification that actually runs tools, offline fallback, clear error messages
- **Tests**: ~6 tests

### Wave 5: `shikki setup` CLI command with --retry/--force flags (P1)
- **Files**: CLI argument parser integration, `SetupCommand.swift`
- **BRs**: BR-09 (retry), BR-05 (force/idempotent)
- **TDDP**: Steps 15-20
- **Deliverable**: `shikki setup`, `shikki setup --retry`, `shikki setup --force`, `shikki setup --status`
- **Tests**: ~4 tests

**Total estimated tests**: ~31

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 10/10 BRs mapped to waves (Wave 1→BR-01,03,07,08,09; Wave 2→BR-02,05,06; Wave 3→BR-04; Wave 4→BR-10,03; Wave 5→BR-09,05) |
| Test Coverage | PASS | 12/12 scenarios mapped to test files across 5 test suites |
| File Alignment | PASS | 6 source files + 5 test files, all in Setup/ subdirectory |
| Task Dependencies | PASS | Wave 1 first (models), Wave 2 (orchestrator), Waves 3-5 independent |
| TDDP Coverage | PASS | 26 RED/GREEN cycles covering all business rules |
| Testability | PASS | 3 protocols (ShellExecuting, PromptHandling, SplashRendering) for full mock injection |
| API Compatibility | PASS | New module — no existing APIs modified |
| Existing Tests | PASS | No existing tests affected — entirely new code |
| Platform Coverage | PASS | #if os(macOS) / #if os(Linux) throughout; no shell uname |

**Verdict: PASS** — ready for implementation.

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-04-02 | Spec | @Daimyo | DRAFTED | Replaces bash setup.sh with compiled Swift wizard |

---

### @shi mini-challenge
1. **@Ronin**: What if the user's brew/apt is broken or missing entirely? Should we detect package manager health first (e.g., `brew doctor` / `apt --version`) before attempting installs? A broken package manager would cascade-fail every install step with cryptic errors.
2. **@Hanami**: The splash screen + background loading is a classic loading screen trick. What if the user's terminal does not support ANSI escape codes? Should we detect `TERM` / `NO_COLOR` and fall back to plain text progress? Also: what is the minimum terminal width for the ASCII logo to render correctly?
3. **@Sensei**: Should we support `nix` as a third package manager? It would give reproducible builds across both platforms with a single `flake.nix`. Trade-off: adds complexity to DependencyChecker but eliminates platform-specific install command divergence entirely.
