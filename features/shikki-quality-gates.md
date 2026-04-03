---
title: ".shikki-quality — Project Quality Standards + PrePRGate Upgrade"
status: spec
priority: P0
project: shikki
created: 2026-04-02
authors: ["@Daimyo"]
tags: [quality, gates, dotfile, stack-aware, periphery]
depends-on: [shikki-dry-enforcement.md, shikki-plugin-sandbox.md]
relates-to: [shikki-setup-swift.md]
epic-branch: —
validated-commit: —
test-run-id: —
---

# Feature: .shikki-quality — Project Quality Standards + PrePRGate Upgrade
> Created: 2026-04-02 | Status: Spec | Owner: @Daimyo

## Context

PrePRGates run four generic checks (CtoReview, SlopScan, TestValidation, LintValidation) with zero knowledge of the project's stack. No dead code detection, no architecture enforcement, no stack-specific tooling. `shi init` detects the stack via `ProjectDetector` but gates never use it. Think `.editorconfig` but for AI-assisted development quality.

## Business Rules

```
BR-01: .shikki-quality MUST be a YAML file at the project root, parsed at gate evaluation time
BR-02: Required fields: stack, test-targets. Optional: architecture, linting, dead-code, gates, tree
BR-03: stack MUST be one of: swift | go | react | python | rust | multi (extensible)
BR-04: test-targets MUST declare tiers: security (default 100), core (80), smoke (50), e2e (30)
BR-05: Gates compose as an ordered list; each gate is a ShipGate conformer
BR-06: Mode MUST be "fail-fast" (stop on first fail) or "collect-all" (run all). Default: collect-all
BR-07: Auto-fix MUST run each linter's --fix in declared order BEFORE gates. Creates up to 2 commits on current branch:
       - Commit 1 (must): `fix(pre-pr): <tool summaries>` — fixes flagged as errors/must-fix
       - Commit 2 (should): `style(pre-pr): <tool summaries>` — fixes flagged as warnings/suggestions
       User can revert either commit independently
BR-08: Each auto-fix commit message body MUST list every change as a bullet point (file:line — what changed)
BR-09: If only one severity level has fixes, only one commit MUST be created (not an empty commit)
BR-10: linting and dead-code MUST be arrays of tool configurations. Each entry has: tool, args (string array), severity
BR-11: Stack-specific gate packs MUST install from marketplace as ShipGate conformers
BR-12: Architecture gate MUST compare modified files' imports against declared layer rules
BR-13: Dead-code gate MUST invoke each declared tool in order. Results merged per tool
BR-14: shi init MUST generate .shikki-quality from ProjectDetector results
BR-15: Missing .shikki-quality MUST degrade gracefully — default four generic gates
```

## .shikki-quality Format

```yaml
stack: swift                          # swift | go | react | python | rust | multi
version: 1
architecture:
  pattern: mvvm-coordinator
  layers: [App, Features, Core, Data, Domain]
  rules: ["Features/* -> Core, Domain", "Core/* -> Domain", "Domain/* -> (none)"]
test-targets: { security: 100, core: 80, smoke: 50, e2e: 30 }
linting:
  - { tool: swiftlint, auto-fix: true, config: .swiftlint.yml }
  - { tool: swiftformat, auto-fix: true, config: .swiftformat }
dead-code:
  - { tool: periphery, args: ["--skip-build", "--index-store-path", ".build"], severity: warn }
  - { tool: unused-imports, args: ["--aggressive"], severity: warn }
gates:
  mode: collect-all                   # collect-all | fail-fast
  active: [test-validation, lint-validation, dead-code, architecture-consistency, dry-check, slop-scan, cto-review]
tree: |
  Sources/
    App/  Features/  Core/  Data/  Domain/
  Tests/
```

## TDDP — Test Summary Table

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01, BR-02 | Core (80%) | Unit | When parsing valid .shikki-quality → QualityConfig returned |
| T-02 | BR-02, BR-03 | Core (80%) | Unit | When stack field missing → missingRequiredField error |
| T-03 | BR-15 | Core (80%) | Unit | When no dotfile → default 4 generic gates |
| T-04 | BR-02 | Core (80%) | Unit | When optional fields missing → defaults applied |
| T-05 | BR-10 | Core (80%) | Unit | When linting is array → each tool parsed in order |
| T-06 | BR-06 | Core (80%) | Unit | When mode is collect-all → all gates run despite failures |
| T-07 | BR-06 | Core (80%) | Unit | When mode is fail-fast → stops on first failure |
| T-08 | BR-13 | Core (80%) | Unit | When dead-code has 2 tools → both invoked, results merged |
| T-09 | BR-13 | Core (80%) | Unit | When dead-code tool has severity=fail → gate fails |
| T-10 | BR-12 | Core (80%) | Unit | When import violates layer rule → warning returned |
| T-11 | BR-12 | Core (80%) | Unit | When no architecture section → gate skips with pass |
| T-12 | BR-07, BR-08 | Core (80%) | Unit | When auto-fix finds errors + warnings → 2 commits created |
| T-13 | BR-09 | Core (80%) | Unit | When auto-fix finds only errors → 1 commit created |
| T-14 | BR-09 | Core (80%) | Unit | When auto-fix finds nothing → no commit, gates run |
| T-15 | BR-05 | Core (80%) | Unit | When gates.active declared → composer builds ordered pipeline |
| T-16 | BR-14 | Smoke (CLI) | Integration | When shi init on Swift project → .shikki-quality generated |
| T-17 | BR-11 | Smoke (CLI) | Integration | When gate-pack plugin installed → gates registered |
| T-18 | BR-01 | E2E | Script | When shi pre-pr runs → full pipeline executes end-to-end |

### S3 Test Scenarios

```
T-01 [BR-01, BR-02, Core 80%]:
When parsing a .shikki-quality file at project root:
  if stack is "swift" and test-targets declares all 4 tiers:
    → returns QualityConfig with stack == .swift
    → testTargets.security == 100, core == 80, smoke == 50, e2e == 30
  if linting is an array of 2 tools:
    → linting[0].tool == "swiftlint", linting[1].tool == "swiftformat"
  if dead-code is an array of 2 tools:
    → deadCode[0].tool == "periphery", deadCode[0].args == ["--skip-build", "--index-store-path", ".build"]

T-02 [BR-02, BR-03, Core 80%]:
When parsing .shikki-quality with no stack field:
  → throws QualityConfigError.missingRequiredField("stack")
When parsing .shikki-quality with stack: "ruby":
  → throws QualityConfigError.invalidStack("ruby")

T-03 [BR-15, Core 80%]:
When project root has no .shikki-quality file:
  → QualityGateComposer.compose() returns [TestValidation, LintValidation, SlopScan, CtoReview]
  → no error thrown

T-04 [BR-02, Core 80%]:
When .shikki-quality has stack and test-targets but no optional fields:
  → gates.mode defaults to "collect-all"
  → linting defaults to empty array
  → dead-code defaults to empty array
  → architecture defaults to nil

T-05 [BR-10, Core 80%]:
When linting contains 2 tool entries:
  → each entry has tool (string), auto-fix (bool), config (optional string)
  → args parsed as string array
  → tools execute in declared order (index 0 first, then index 1)

T-06 [BR-06, Core 80%]:
When gates.mode is "collect-all":
  if LintValidation fails and DeadCode warns:
    → all gates still run
    → result contains both the lint failure and the dead-code warning
  if ArchitectureGate also warns:
    → result contains all 3 findings

T-07 [BR-06, Core 80%]:
When gates.mode is "fail-fast":
  if LintValidation is first in active list and fails:
    → subsequent gates do NOT run
    → result contains only the lint failure

T-08 [BR-13, Core 80%]:
When dead-code declares [{tool: periphery, severity: warn}, {tool: unused-imports, severity: warn}]:
  if periphery finds 1 unused class and unused-imports finds 2 unused imports:
    → periphery runs first, then unused-imports
    → results merged: "periphery: 1 unused declaration; unused-imports: 2 unused imports"
    → overall severity is .warn (max of all tool severities)

T-09 [BR-13, Core 80%]:
When dead-code declares [{tool: periphery, severity: fail}, {tool: unused-imports, severity: warn}]:
  if periphery reports 3 unused declarations:
    → gate returns .fail with count and names from periphery
  if gates.mode is "collect-all":
    → unused-imports still runs, its results appended as .warn

T-10 [BR-12, Core 80%]:
When architecture.rules contains "Features/* -> Core, Domain":
  if Features/LoginVM.swift imports Data/:
    → returns .warn("LoginVM.swift imports Data — violates layer rule: Features/* -> Core, Domain")

T-11 [BR-12, Core 80%]:
When .shikki-quality has no architecture section:
  → ArchitectureGate returns .pass("No architecture rules configured — skipped")

T-12 [BR-07, BR-08, Core 80%]:
When auto-fix pipeline runs with linting: [{tool: swiftlint, auto-fix: true}, {tool: swiftformat, auto-fix: true}]:
  if swiftlint fixes 2 errors (must) and swiftformat fixes 3 style issues (should):
    → swiftlint --fix runs first, then swiftformat
    → commit 1 created on current branch:
      fix(pre-pr): auto-fix 2 errors
        - Sources/Login/LoginVM.swift:12 — force unwrap removed (swiftlint)
        - Sources/Auth/Token.swift:8 — unused import removed (swiftlint)
    → commit 2 created on current branch:
      style(pre-pr): auto-fix 3 suggestions
        - Sources/Login/LoginVM.swift:5 — trailing whitespace (swiftformat)
        - Sources/Auth/Token.swift:1 — import sorting (swiftformat)
        - Sources/Auth/Token.swift:22 — brace style (swiftformat)
    → gates evaluate AFTER both commits

T-13 [BR-09, Core 80%]:
When auto-fix pipeline runs and swiftlint fixes 1 error but 0 warnings:
  → only 1 commit created: fix(pre-pr): auto-fix 1 error
  → no style(pre-pr) commit created

T-14 [BR-09, Core 80%]:
When auto-fix pipeline runs and all tools find nothing to fix:
  → no commit created
  → gates evaluate immediately

T-15 [BR-05, Core 80%]:
When gates.active declares [test-validation, lint-validation, dead-code, architecture-consistency]:
  → QualityGateComposer builds pipeline with exactly those 4 gates in order
  → unknown gate name in list throws QualityConfigError.unknownGate("bad-name")

T-16 [BR-14, Smoke CLI]:
When running shi init on a directory with Package.swift:
  → .shikki-quality created with stack: swift
  → linting: [{tool: swiftlint}] (if swiftlint detected on PATH)
  → dead-code: [{tool: periphery}] (if periphery detected on PATH)
  → test-targets: default tiers

T-17 [BR-11, Smoke CLI]:
When a gate-pack plugin is installed with stack: react providing ESLintGate + BundleSizeGate:
  if both gates listed in gates.active:
    → QualityGateComposer includes both gates in the pipeline
  if only ESLintGate listed:
    → only ESLintGate included, BundleSizeGate ignored

T-18 [BR-01, E2E]:
When running shi pre-pr on a project with .shikki-quality:
  → auto-fix pass runs (commits if needed)
  → each gate in gates.active evaluates
  → final report printed with pass/warn/fail per gate
```

## Wave Dispatch Tree

```
Wave 1: QualityConfig Model + Parser
  ├── QualityConfig.swift (no deps)
  ├── QualityConfigParser.swift (no deps)
  └── Validation + defaults logic
  Input:  .shikki-quality YAML file
  Output: QualityConfig struct (or nil + error)
  Tests:  T-01, T-02, T-03, T-04, T-05
  Gate:   swift test --filter QualityConfig → green
  ║
  ╠══ Wave 2: Stack-Aware Gates ← BLOCKED BY Wave 1
  ║   ├── DeadCodeGate.swift (depends: QualityConfig)
  ║   ├── ArchitectureGate.swift (depends: QualityConfig)
  ║   └── Multi-tool invocation + result merging
  ║   Input:  QualityConfig.deadCode array, architecture rules
  ║   Output: GateResult (.pass/.warn/.fail)
  ║   Tests:  T-08, T-09, T-10, T-11
  ║   Gate:   swift test --filter DeadCode,Architecture → green
  ║   ║
  ║   ╠══ Wave 3: Gate Composer + Auto-Fix ← BLOCKED BY Wave 2
  ║   ║   ├── QualityGateComposer.swift (depends: QualityConfig, all gates)
  ║   ║   ├── AutoFixPass.swift (depends: QualityConfig.linting)
  ║   ║   └── 2-commit severity split logic + git integration
  ║   ║   Input:  QualityConfig, gate registry, git working tree
  ║   ║   Output: auto-fix commits + ordered gate pipeline
  ║   ║   Tests:  T-06, T-07, T-12, T-13, T-14, T-15
  ║   ║   Gate:   swift test --filter GateComposer,AutoFix → green
  ║   ║   ║
  ║   ║   ╚══ Wave 4: CLI + Init + Marketplace ← BLOCKED BY Wave 3
  ║   ║       ├── Wire PrePRGates.swift to use QualityGateComposer
  ║   ║       ├── ProjectInitWizard → generate .shikki-quality
  ║   ║       └── Gate-pack plugin type registration
  ║   ║       Input:  QualityGateComposer, ProjectDetector
  ║   ║       Output: shi pre-pr uses dotfile, shi init generates it
  ║   ║       Tests:  T-16, T-17, T-18
  ║   ║       Gate:   shi pre-pr on shikki project → passes
```

## Implementation Waves

### Wave 1: QualityConfig Model + Parser
**Files:**
- `Sources/ShikkiKit/Extensions/Review/Quality/QualityConfig.swift` — model (stack enum, tool config, tier targets)
- `Sources/ShikkiKit/Extensions/Review/Quality/QualityConfigParser.swift` — YAML parse + validation
- `Tests/ShikkiKitTests/Quality/QualityConfigTests.swift`
**Tests:** T-01, T-02, T-03, T-04, T-05
**BRs:** BR-01, BR-02, BR-03, BR-04, BR-10, BR-15
**Deps:** none
**Gate:** `swift test --filter QualityConfig` green

### Wave 2: Stack-Aware Gates ← BLOCKED BY Wave 1
**Files:**
- `Sources/ShikkiKit/Extensions/Review/Quality/DeadCodeGate.swift` — multi-tool invocation, result merge
- `Sources/ShikkiKit/Extensions/Review/Quality/ArchitectureGate.swift` — import scanning vs layer rules
- `Tests/ShikkiKitTests/Quality/DeadCodeGateTests.swift`
- `Tests/ShikkiKitTests/Quality/ArchitectureGateTests.swift`
**Tests:** T-08, T-09, T-10, T-11
**BRs:** BR-12, BR-13
**Deps:** Wave 1 (QualityConfig)
**Gate:** `swift test --filter DeadCode,Architecture` green

### Wave 3: Gate Composer + Auto-Fix ← BLOCKED BY Wave 2
**Files:**
- `Sources/ShikkiKit/Extensions/Review/Quality/QualityGateComposer.swift` — builds ordered gate pipeline from config
- `Sources/ShikkiKit/Extensions/Review/Quality/AutoFixPass.swift` — runs linters, splits by severity, creates 2 commits
- `Tests/ShikkiKitTests/Quality/QualityGateComposerTests.swift`
- `Tests/ShikkiKitTests/Quality/AutoFixPassTests.swift`
**Tests:** T-06, T-07, T-12, T-13, T-14, T-15
**BRs:** BR-05, BR-06, BR-07, BR-08, BR-09
**Deps:** Wave 2 (all gates exist for registry)
**Gate:** `swift test --filter GateComposer,AutoFix` green

### Wave 4: CLI + Init + Marketplace ← BLOCKED BY Wave 3
**Files:**
- `Sources/ShikkiKit/Services/PrePRGates.swift` — modify to use QualityGateComposer
- `Sources/ShikkiKit/Services/ProjectInitWizard.swift` — modify to generate .shikki-quality
- `Sources/ShikkiKit/Plugins/PluginRunner.swift` — modify to handle gate-pack plugin type
- `Tests/ShikkiKitTests/Quality/QualityIntegrationTests.swift`
**Tests:** T-16, T-17, T-18
**BRs:** BR-11, BR-14
**Deps:** Wave 3 (composer + auto-fix)
**Gate:** `shi pre-pr` on shikki project passes

## Reuse Audit

| Utility | Exists In | Decision |
|---------|-----------|----------|
| ANSI-aware padding | TerminalOutput.pad() | Reuse |
| Process shell-out | ExternalTools.isAvailable() | Reuse pattern |
| Git commit creation | FixEngine.snapshot/rollback | Extract GitOperationsProvider |
| ShipGate protocol | PrePRGates.swift | Extend |
| ProjectDetector | ProjectInitWizard.swift | Reuse |
| YAML parsing | Yams SPM or manual | Evaluate — lightweight manual parser vs Yams dep |

## @shi Mini-Challenge

1. **@Ronin**: Architecture rules are per-edge. How to catch transitive violations (`Domain -> Core`) when the PR only touches `Domain/`?
2. **@Katana**: Auto-fix modifies files before gates. Should the diff be re-computed after auto-fix for architecture gate? (Yes — gates evaluate AFTER commits)
3. **@Sensei**: Periphery requires a full build. Cache results per commit hash to skip re-runs?
