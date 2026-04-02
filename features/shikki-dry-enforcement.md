---
title: "DRY Enforcement for Parallel Agent Dispatch"
status: spec
priority: P1
project: shikki
created: 2026-04-02
authors: "@Daimyo + @Sensei brainstorm"
tags: [quality, enforcement, dispatch]
---

# Feature: DRY Enforcement for Parallel Agent Dispatch
> Created: 2026-04-02 | Status: spec | Owner: @Daimyo

## Context

Shikki dispatches parallel agents to implement features in isolated worktrees. Each agent operates independently with no visibility into what other agents are building simultaneously. This isolation is a strength for merge safety but a weakness for code reuse.

**Observed damage**: During the v0.3.0 consolidation sprint, 6 agents built 6 features in parallel and produced:
- 3x `countSections()` implementations (identical logic, different files)
- 2x YAML frontmatter parsers (one in SpecCommandUtilities, one inline)
- 2x pre-PR gate systems (overlapping gate logic, different names)

This is pure waste — duplicated code means duplicated maintenance, divergent bug fixes, and confused contributors. It must never happen again.

## Problem

Parallel agent dispatch has no mechanism to prevent DRY violations. There is no pre-dispatch audit of existing utilities, no shared manifest telling agents what already exists, and no post-merge gate catching duplicates before they land. The result is an O(n) duplication rate where n is the number of parallel agents — each agent reinvents utilities that already exist or that a sibling agent is building at the same time.

## Synthesis

**Goal**: Three-layer defense against DRY violations in parallel dispatch — prevent at spec time, detect at merge time, scan at maintenance time.

**Scope**:
- Layer 1 (P0): Mandatory "Reuse Audit" section in every spec, validated by `SpecValidateCommand`
- Layer 2 (P1): `DuplicateDetectionGate` in the pre-PR pipeline, warning on duplicate method signatures and copy-paste blocks
- Layer 3 (P2): Full semantic duplicate detector via `shikki doctor --duplicates`, building a method index with body hashes

**Out of scope**:
- Cross-language duplicate detection (Swift-only for now)
- Runtime deduplication or automatic refactoring (detection and warning only)
- Changes to the worktree isolation model (agents remain independent — we add guardrails, not coupling)

**Success criteria**:
- Every spec produced by `/spec` or `/dispatch` contains a "## Reuse Audit" section — specs without it fail validation
- The dispatch system provides each agent with a shared utilities manifest listing all public helper methods in designated utility files
- Pre-PR gate warns (does not fail) when a diff introduces methods with names that already exist elsewhere
- `shikki doctor --duplicates` produces an actionable report listing all functionally-equivalent methods across the codebase
- Zero duplicate utility methods in the next parallel dispatch of 4+ agents

**Dependencies**:
- `SpecValidateCommand` (exists — extend with reuse audit check)
- `ShipGate` protocol (exists — add new `DuplicateDetectionGate` conformer)
- `SlopScanGate` (exists — reference implementation for scan-based gates)
- Moto cache builder (exists — extend for method indexing in Layer 3)

## Business Rules

```
BR-01: Every spec MUST include a "## Reuse Audit" section listing existing utilities checked and reuse decisions made
BR-02: The dispatch system MUST provide each agent with a "shared utilities manifest" listing all public helper methods in designated utility files (SpecCommandUtilities, ShipContext, etc.)
BR-03: Post-merge gate MUST warn on duplicate method signatures across files in the diff
BR-04: `shikki doctor --duplicates` MUST scan all .swift files and report functionally-equivalent methods (same name OR same body hash)
BR-05: Shared utilities MUST live in designated utility files, not scattered across feature modules — the manifest is the source of truth for where utilities belong
BR-06: When consolidating duplicates, prefer the implementation that has tests over the one that does not
```

## Three Layers

### Layer 1: Pre-Dispatch Reuse Audit (P0)

The cheapest defense. Before any TDDP begins, the spec phase must include a structured reuse audit.

**What it does**:
1. Grep the codebase for existing implementations matching the planned feature's patterns
2. Check `SpecCommandUtilities`, `ShipContext` helpers, existing protocols, and designated utility files
3. List all existing utility files and their public methods relevant to the feature
4. Document explicit reuse decisions: "Will reuse X from Y" or "Must create new Z because no equivalent exists"

**Enforcement**:
- `SpecValidateCommand` rejects specs missing the `## Reuse Audit` heading
- The reuse audit must contain at least one item (empty audits fail validation)

**Spec template addition**:
```markdown
## Reuse Audit

| Utility / Pattern | Exists In | Decision |
|---|---|---|
| `countSections()` | `SpecCommandUtilities.swift:42` | Reuse as-is |
| YAML frontmatter parsing | `SpecFrontmatterParser.swift` | Reuse, extend with new fields |
| Similarity scoring | — | Create new in `DuplicateDetector.swift` |
```

**Shared utilities manifest** (auto-generated, passed to each agent at dispatch):
```
# SHARED UTILITIES MANIFEST (auto-generated 2026-04-02)
# Agents: reuse these before creating new utilities.

## SpecCommandUtilities.swift
- countSections(in:) -> Int
- extractFrontmatter(from:) -> [String: String]
- validateHeadings(in:matching:) -> [ValidationError]

## ShipContext.swift
- resolveProjectRoot() -> URL
- gatherSwiftFiles(in:) -> [URL]
- runSwiftBuild(at:) throws

## StringExtensions.swift
- trimmedLines() -> [String]
- slugified() -> String
```

### Layer 2: Post-Merge Quality Gate (P1)

A `DuplicateDetectionGate` conforming to `ShipGate`, running during pre-PR checks.

**What it does**:
1. Parse the diff for newly added methods (functions and methods with `func` keyword)
2. For each new method, search the existing codebase for methods with the same name
3. For each new code block >10 lines, compute a normalized hash and compare against existing blocks
4. Report matches with file paths, line numbers, and similarity percentage

**Behavior**:
- **Warn, not fail** — some duplication is acceptable (module isolation, test helpers, etc.)
- Output format: actionable suggestions in the gate report
- Threshold: flag blocks with >80% similarity after whitespace normalization

**Gate output example**:
```
DuplicateDetectionGate: 2 warnings

  WARNING: func countSections(in:) at CodeGen/NewFeature.swift:87
    → Duplicate of SpecCommandUtilities.countSections(in:) at Commands/Spec/SpecCommandUtilities.swift:42
    → Suggestion: import and reuse existing implementation

  WARNING: Lines 120-145 at CodeGen/NewFeature.swift
    → 92% similar to lines 30-55 at Commands/Ship/ShipContext.swift
    → Suggestion: extract shared logic into a utility
```

### Layer 3: Semantic Duplicate Detector (P2)

A full codebase scan, extending the Moto cache builder's indexing capability.

**What it does**:
1. Parse all `.swift` files and extract method signatures + body content
2. Build an index: method name -> [(file, line, body hash)]
3. Flag methods with the same name in different files
4. Flag methods with the same body hash but different names (renamed duplicates)
5. Produce a structured report grouped by duplication type

**CLI interface**:
```
$ shikki doctor --duplicates

DRY Violation Report — 2026-04-02
==================================

Exact Name Duplicates (3 found):
  countSections(in:)
    → SpecFrontmatterParser.swift:42
    → SpecMigrationService.swift:18
    → TemplateValidator.swift:91

  extractFrontmatter(from:)
    → SpecCommandUtilities.swift:28
    → CodeGenPipeline.swift:156

Body Hash Matches (1 found):
  normalizeWhitespace() [hash: a3f8c1]
    → StringExtensions.swift:12 (as trimAndNormalize)
    → YAMLParser.swift:67 (as cleanInput)

Recommendation: consolidate into designated utility files.
Run `shikki doctor --duplicates --fix` for suggested refactoring plan.
```

**Body hash computation**:
1. Strip all whitespace and comments
2. Normalize variable names to positional placeholders (param0, param1, ...)
3. SHA-256 hash the normalized body
4. Match on hash equality

## Test Plan

### Scenario 1: Spec validation rejects missing Reuse Audit
```
Setup:   Spec markdown without "## Reuse Audit" section
Action:  Run SpecValidateCommand on the spec
Expect:  Validation fails with error "Missing required section: Reuse Audit"
```

### Scenario 2: Spec validation accepts valid Reuse Audit
```
Setup:   Spec markdown with "## Reuse Audit" containing a table with at least one row
Action:  Run SpecValidateCommand on the spec
Expect:  Validation passes
```

### Scenario 3: Shared utilities manifest generation
```
Setup:   Project with SpecCommandUtilities.swift and ShipContext.swift containing public methods
Action:  Generate shared utilities manifest
Expect:  Manifest lists all public func signatures from designated utility files
```

### Scenario 4: DuplicateDetectionGate warns on same-name method
```
Setup:   Diff adds func countSections(in:); codebase already has countSections(in:) in SpecCommandUtilities
Action:  Run DuplicateDetectionGate on the diff
Expect:  Gate returns .warning with message identifying the duplicate and suggesting reuse
```

### Scenario 5: DuplicateDetectionGate warns on similar code blocks
```
Setup:   Diff adds a 15-line block that is 90% similar to an existing block in ShipContext
Action:  Run DuplicateDetectionGate on the diff
Expect:  Gate returns .warning with similarity percentage and file locations
```

### Scenario 6: DuplicateDetectionGate passes clean diff
```
Setup:   Diff adds only new methods with no name or body matches in the codebase
Action:  Run DuplicateDetectionGate on the diff
Expect:  Gate returns .passed with no warnings
```

### Scenario 7: DuplicateDetector finds exact name duplicates
```
Setup:   Two .swift files each containing func countSections(in content: String) -> Int
Action:  Run DuplicateDetector.scan() on both files
Expect:  Report contains one entry under "Exact Name Duplicates" with both file paths
```

### Scenario 8: DuplicateDetector finds body hash duplicates
```
Setup:   File A has func cleanInput() with body X; File B has func normalizeText() with identical logic but different variable names
Action:  Run DuplicateDetector.scan() on both files
Expect:  Report contains one entry under "Body Hash Matches" linking both methods
```

### Scenario 9: DuplicateDetector ignores test files
```
Setup:   Test file and source file both contain func makeTestData() with identical bodies
Action:  Run DuplicateDetector.scan() with default config
Expect:  No duplicate reported (test helpers are excluded from production duplicate scanning)
```

### Scenario 10: Doctor command outputs structured report
```
Setup:   Codebase with known duplicates (name + body hash types)
Action:  Run `shikki doctor --duplicates`
Expect:  CLI output matches expected report format with sections, file paths, and recommendations
```

## TDDP (Test-Driven Development Plan)

```
Wave 1 — Reuse Audit Enforcement (P0)

 1. Test:  SpecValidateCommand rejects spec without "## Reuse Audit" heading        → RED
 2. Impl:  Add reuse audit heading check to SpecValidateCommand                      → GREEN
 3. Test:  SpecValidateCommand rejects empty Reuse Audit (heading but no content)    → RED
 4. Impl:  Check for at least one non-empty line after Reuse Audit heading           → GREEN
 5. Test:  Shared utilities manifest lists public methods from designated files       → RED
 6. Impl:  ManifestGenerator scans designated utility files for public func sigs     → GREEN
 7. Test:  Dispatch system includes manifest in agent context                        → RED
 8. Impl:  DispatchCommand attaches manifest output to each agent's prompt context   → GREEN

Wave 2 — Post-Merge Quality Gate (P1)

 9. Test:  DuplicateDetector finds methods with same name in different files          → RED
10. Impl:  DuplicateDetector scans source files, builds method name index             → GREEN
11. Test:  DuplicateDetector finds methods with same body hash                        → RED
12. Impl:  Body hash computation (strip whitespace, normalize variable names)         → GREEN
13. Test:  DuplicateDetector ignores test file duplicates                             → RED
14. Impl:  File filter excluding *Tests.swift from scan                               → GREEN
15. Test:  DuplicateGate warns on pre-PR when name duplicates detected in diff        → RED
16. Impl:  DuplicateGate as ShipGate conformer, parses diff for new func signatures   → GREEN
17. Test:  DuplicateGate warns on similar code blocks (>80% match, >10 lines)         → RED
18. Impl:  Block similarity scoring with normalized hash comparison                    → GREEN
19. Test:  DuplicateGate passes clean diff with no duplicates                          → RED
20. Impl:  Gate returns .passed when no matches found                                  → GREEN

Wave 3 — Semantic Duplicate Detector + Doctor (P2)

21. Test:  Full codebase scan produces grouped report (name dupes + body hash dupes)   → RED
22. Impl:  DuplicateDetector.fullScan() with structured DuplicateReport output         → GREEN
23. Test:  Variable name normalization produces same hash for renamed-variable methods  → RED
24. Impl:  AST-lite normalizer replacing identifiers with positional placeholders       → GREEN
25. Test:  `shikki doctor --duplicates` CLI outputs formatted report                   → RED
26. Impl:  DoctorCommand subcommand wiring DuplicateDetector.fullScan() to TUI output  → GREEN
27. Test:  Report recommends consolidation target based on test coverage                → RED
28. Impl:  Consolidation advisor checking which duplicate has associated test file       → GREEN
```

## Implementation Waves

| Wave | Priority | Scope | Deliverables |
|------|----------|-------|-------------|
| Wave 1 | P0 | Reuse Audit enforcement | Spec template update, SpecValidateCommand check, ManifestGenerator, dispatch integration |
| Wave 2 | P1 | Post-merge quality gate | DuplicateDetector (name + hash), DuplicateGate (ShipGate conformer), diff parsing |
| Wave 3 | P2 | Full semantic detector | Variable normalization, full codebase scan, `shikki doctor --duplicates` CLI, consolidation advisor |

## @shi Mini-Challenge

1. **@Ronin**: What about intentional duplication for module isolation? Some SPM packages deliberately keep their own copy of a utility to avoid cross-package dependencies. The detector needs an escape hatch — perhaps a `// shikki:allow-duplicate` annotation or a `.shikki-duplicates-ignore` config file listing intentional duplicates by method signature.

2. **@Katana**: Body hash matching with variable name normalization is the hard part. Two methods doing the same thing with different variable names need the same hash. The proposed approach (positional placeholders) handles simple cases, but what about methods that call different-but-equivalent APIs (e.g., `URL(string:)` vs `URL(filePath:)`)? Should we stop at syntactic equivalence and leave semantic equivalence for a future AST-based analysis?

3. **@Sensei**: The shared utilities manifest should be auto-generated from the codebase, not manually curated. Manual curation drifts immediately. The generator scans designated utility files (configured in `.shikki.yml` or hardcoded initially) and extracts public method signatures. The manifest is regenerated at dispatch time, so it is always current. The only manual input is the list of which files count as "designated utility files."
