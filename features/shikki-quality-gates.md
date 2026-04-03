---
title: ".shikki-quality — Project Quality Standards + PrePRGate Upgrade"
status: spec
priority: P0
project: shikki
created: 2026-04-02
authors: "@Daimyo vision"
tags: [quality, gates, dotfile, stack-aware, periphery]
depends-on: [shikki-dry-enforcement.md, shikki-plugin-sandbox.md]
relates-to: [shikki-setup-swift.md]
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
BR-06: Mode: "fail-fast" (stop on first fail) or "collect-all" (run all). Default: collect-all
BR-07: Auto-fix runs linter --fix BEFORE gates. NEVER auto-commits the fixes
BR-08: Stack-specific gate packs install from marketplace as ShipGate conformers
BR-09: Architecture gate compares modified files' imports against declared layer rules
BR-10: Dead-code gate invokes the stack's tool (Periphery/Swift, deadcode/Go, ts-prune/React)
BR-11: shi init MUST generate .shikki-quality from ProjectDetector results
BR-12: Missing .shikki-quality degrades gracefully — default four generic gates
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
linting: { tool: swiftlint, auto-fix: true, config: .swiftlint.yml }
dead-code: { tool: periphery, args: "--skip-build", severity: warn }
gates:
  mode: collect-all                   # collect-all | fail-fast
  active: [test-validation, lint-validation, dead-code, architecture-consistency, dry-check, slop-scan, cto-review]
tree: |
  Sources/
    App/  Features/  Core/  Data/  Domain/
  Tests/
```

## S3 Test Scenarios

### S1: Parse valid .shikki-quality (BR-01, BR-02)
```
GIVEN  .shikki-quality with stack: swift and test-targets
WHEN   QualityConfigParser.parse(at: projectRoot)
THEN   returns QualityConfig with stack == .swift, testTargets.security == 100
```

### S2: Missing required field rejected (BR-02, BR-03)
```
GIVEN  .shikki-quality with no stack field
WHEN   QualityConfigParser.parse(at: projectRoot)
THEN   throws QualityConfigError.missingRequiredField("stack")
```

### S3: Missing dotfile degrades to generic gates (BR-12)
```
GIVEN  project root with no .shikki-quality
WHEN   QualityGateComposer.compose(at: projectRoot)
THEN   returns default [TestValidation, LintValidation, SlopScan, CtoReview]
```

### S4: Collect-all runs all gates (BR-06)
```
GIVEN  gates.mode: collect-all, LintValidation fails, DeadCode warns
WHEN   pipeline evaluates
THEN   all gates run, result contains both the lint failure and the dead-code warning
```

### S5: Fail-fast stops on first failure (BR-06)
```
GIVEN  gates.mode: fail-fast, LintValidation fails
WHEN   pipeline evaluates
THEN   subsequent gates do NOT run, result contains only lint failure
```

### S6: Auto-fix runs before gates, never commits (BR-07)
```
GIVEN  linting.auto-fix: true, linting.tool: swiftlint
WHEN   pipeline starts
THEN   `swiftlint --fix` runs before LintValidationGate, no git commit is created
```

### S7: Periphery dead-code gate detects unused code (BR-10)
```
GIVEN  dead-code.tool: periphery, dead-code.severity: warn, unused class exists
WHEN   DeadCodeGate evaluates
THEN   returns .warn("1 unused declaration: UnusedHelper")
```

### S8: Dead-code gate fails when severity=fail (BR-10)
```
GIVEN  dead-code.severity: fail, Periphery reports 3 unused declarations
WHEN   DeadCodeGate evaluates
THEN   returns .fail with count and names
```

### S9: Architecture gate warns on violation (BR-09)
```
GIVEN  rules: ["Features/* -> Core, Domain"], Features/LoginVM.swift imports Data/
WHEN   ArchitectureGate evaluates
THEN   returns .warn("LoginVM.swift imports Data — violates layer rule")
```

### S10: shi init generates .shikki-quality (BR-11)
```
GIVEN  project root with Package.swift (Swift project)
WHEN   ProjectInitWizard.initialize(at: path)
THEN   .shikki-quality created with stack: swift, periphery, swiftlint, default targets
```

### S11: Marketplace gate pack registers (BR-08)
```
GIVEN  plugin type: gate-pack, stack: react, provides ESLintGate + BundleSizeGate
WHEN   plugin installed and listed in gates.active
THEN   QualityGateComposer includes both gates in the pipeline
```

### S12: Architecture gate skips when no rules (BR-09)
```
GIVEN  .shikki-quality with no architecture section
WHEN   ArchitectureGate evaluates
THEN   returns .pass("No architecture rules configured — skipped")
```

## TDDP

```
Wave 1 — QualityConfig Model + Parser (P0) ─── 8 tests, ~20 min
 1. Test:  Parse valid YAML into QualityConfig                                → RED
 2. Impl:  QualityConfig struct + QualityConfigParser                         → GREEN
 3. Test:  Missing stack throws missingRequiredField                           → RED
 4. Impl:  Validation — stack and test-targets required                       → GREEN
 5. Test:  Missing file returns nil (graceful degradation)                     → RED
 6. Impl:  Parser returns nil when .shikki-quality absent                     → GREEN
 7. Test:  Default values for optional fields                                  → RED
 8. Impl:  Defaults: mode=collect-all, auto-fix=true, severity=warn           → GREEN

Wave 2 — Stack-Aware Gates (P0) ─────────────── 8 tests, ~25 min
 9. Test:  DeadCodeGate invokes periphery, parses output                      → RED
10. Impl:  DeadCodeGate shells to configured tool                             → GREEN
11. Test:  DeadCodeGate .warn vs .fail based on severity                      → RED
12. Impl:  Severity switch in evaluate()                                      → GREEN
13. Test:  ArchitectureGate detects import violations                         → RED
14. Impl:  Parse layer rules, scan imports in changed files                   → GREEN
15. Test:  ArchitectureGate passes when no rules configured                   → RED
16. Impl:  Early return .pass when architecture is nil                        → GREEN

Wave 3 — Gate Composer + Auto-Fix (P0) ──────── 8 tests, ~20 min
17. Test:  Composer returns default gates when no dotfile                      → RED
18. Impl:  Fallback to [TestValidation, Lint, SlopScan, CtoReview]           → GREEN
19. Test:  Composer builds gate list from gates.active                        → RED
20. Impl:  Gate registry maps names to ShipGate instances                     → GREEN
21. Test:  Auto-fix runs --fix before LintValidationGate                      → RED
22. Impl:  AutoFixPass as pre-gate step, no git commit                       → GREEN
23. Test:  Collect-all vs fail-fast mode behavior                             → RED
24. Impl:  Pipeline loop with mode check                                      → GREEN

Wave 4 — Init + Marketplace + Personas (P1) ─── 6 tests, ~15 min
25. Test:  InitWizard generates .shikki-quality for Swift project             → RED
26. Impl:  Add quality config generation to initialize()                      → GREEN
27. Test:  Gate pack plugin registers ShipGate conformers                     → RED
28. Impl:  Plugin type gate-pack auto-registers on install                    → GREEN
29. Test:  PersonaLoader returns @SwiftExpert for stack: swift                → RED
30. Impl:  PersonaLoader reads stack, returns system prompt                   → GREEN
```

## Architecture

**New**: `Services/Quality/QualityConfig.swift` (model), `QualityConfigParser.swift` (YAML parse), `QualityGateComposer.swift` (pipeline builder), `AutoFixPass.swift` (pre-gate fix), `Extensions/Review/DeadCodeGate.swift`, `ArchitectureGate.swift`, `PersonaLoader.swift`
**Modify**: `PrePRGates.swift` (use composer), `ProjectInitWizard.swift` (generate dotfile)

## @shi Mini-Challenge

1. **@Ronin**: Architecture rules are per-edge. How to catch transitive violations (`Domain -> Core`) when the PR only touches `Domain/`?
2. **@Katana**: Auto-fix modifies files before gates. Should the diff be re-computed after auto-fix for architecture gate?
3. **@Sensei**: Periphery requires a full build. Cache results per commit hash to skip re-runs?
