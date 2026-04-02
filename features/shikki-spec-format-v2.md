---
title: "Spec Format v2 — Mandatory BR → TDDP → S3 → Waves"
status: implementing
priority: P0
project: shikki
created: 2026-04-02
authors: ["@Daimyo"]
tags: [process, spec, tddp, s3, quality]
---

# Feature: Spec Format v2 — Mandatory BR → TDDP → S3 → Waves
> Created: 2026-04-02 | Status: Implementing | Owner: @Daimyo

## Context

Specs have been shipping without TDDP mapping, S3 test definitions, and wave dependency trees. Agents can't dispatch from incomplete specs. Section order matters — you review the most important data first.

## Business Rules

```
BR-01: Every spec MUST contain sections in this order: BR → TDDP → S3 Scenarios → Wave Dispatch Tree → Implementation Waves
BR-02: Every BR MUST be numbered BR-01..BR-N, one line, enforcement verb (MUST/MUST NOT)
BR-03: Every test in TDDP MUST map to at least one BR — orphan tests rejected
BR-04: Every BR MUST have at least one test in TDDP — untested BRs rejected
BR-05: TDDP table columns: Test ID | BR | Tier | Type | Scenario (summary)
BR-06: Coverage tiers: Security (100%) | Core (80%) | Smoke (CLI) | E2E (scripts)
BR-07: S3 scenarios MUST use When/Then syntax with if/otherwise/depending on — never plain text
BR-08: Wave Dispatch Tree MUST show: tasks, deps (← BLOCKED BY), tests per wave, gate condition
BR-09: Implementation Waves MUST list: files (full paths), tests (T-IDs), BRs covered, deps, gate
BR-10: /spec pipeline MUST validate format before saving — reject incomplete specs
BR-11: Existing specs MUST be upgraded before dispatch
BR-12: Wave presentation MUST include: input artifacts, output artifacts, parallel opportunities
```

## TDDP — Test Summary Table

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01 | Core (80%) | Unit | When parsing spec → sections in correct order |
| T-02 | BR-03 | Core (80%) | Unit | When test has no BR → rejected |
| T-03 | BR-04 | Core (80%) | Unit | When BR has no test → rejected |
| T-04 | BR-05 | Core (80%) | Unit | When parsing TDDP → all 5 columns extracted |
| T-05 | BR-07 | Core (80%) | Unit | When S3 block missing → spec rejected |
| T-06 | BR-08 | Core (80%) | Unit | When wave has no gate → rejected |
| T-07 | BR-10 | Smoke (CLI) | Integration | When shi spec validate on bad spec → fails |
| T-08 | BR-11 | E2E | Script | When batch upgrade runs → all specs pass validation |
| T-09 | BR-12 | Core (80%) | Unit | When wave missing input/output artifacts → warning |

### S3 Test Scenarios

```
T-01 [BR-01, Core 80%]:
When parsing a spec file:
  if sections are BR → TDDP → S3 → Waves:
    → validation passes
  if TDDP appears before BR:
    → validation fails with "TDDP must follow Business Rules"
  if S3 scenarios missing:
    → validation fails with "S3 test definitions required"

T-02 [BR-03, Core 80%]:
When TDDP contains test T-99 not mapped to any BR:
  → validation fails with "T-99 has no BR mapping — orphan test"

T-03 [BR-04, Core 80%]:
When BR-05 exists but no test references it:
  → validation fails with "BR-05 has no test coverage"

T-04 [BR-05, Core 80%]:
When parsing TDDP table row:
  → Test ID extracted (T-XX format)
  → BR reference extracted (BR-XX)
  → Tier extracted (Security/Core/Smoke/E2E)
  → Type extracted (Unit/Integration/E2E)
  → Scenario summary extracted

T-05 [BR-07, Core 80%]:
When S3 scenario block is plain text (no When/Then):
  → validation fails with "S3 scenarios must use When/Then syntax"

T-06 [BR-08, Core 80%]:
When wave dispatch tree has wave without gate:
  → validation fails with "Wave 2 missing gate condition"

T-07 [BR-10, Smoke CLI]:
When running shi spec validate on spec missing TDDP:
  → exit code 1
  → stderr: "Missing required section: TDDP"

T-08 [BR-11, E2E]:
When batch upgrade script runs on features/:
  → all specs gain TDDP + S3 + Wave sections
  → shi spec validate passes for each

T-09 [BR-12, Core 80%]:
When wave has no input/output artifacts listed:
  → warning emitted (not blocking, but flagged)
```

## Wave Dispatch Tree

```
Wave 1: Format Validator + S3 Parser
  ├── SpecFormatValidator (no deps)
  ├── TDDPParser (no deps)
  ├── S3ScenarioParser (no deps)
  └── WaveTreeParser (no deps)
  Input:  raw .md spec file
  Output: parsed SpecDocument with validated sections
  Tests:  T-01, T-02, T-03, T-04, T-05, T-06, T-09
  Gate:   swift test --filter SpecFormat → green
  ║
  ╠══ Wave 2: CLI Integration ← BLOCKED BY Wave 1
  ║   ├── Wire into shi spec validate
  ║   └── Wire into /spec pipeline (reject on save)
  ║   Input:  SpecFormatValidator
  ║   Output: pass/fail + error messages
  ║   Tests:  T-07
  ║   Gate:   shi spec validate features/shikki-bg-command.md → passes
  ║
  ╚══ Wave 3: Batch Upgrade ← BLOCKED BY Wave 1
      ├── upgrade-specs-s3.sh script
      └── Manual review of generated S3 scenarios
      Input:  all features/*.md without S3 sections
      Output: upgraded specs with S3 + validated
      Tests:  T-08
      Gate:   all features/*.md pass shi spec validate
```

## Implementation Waves

### Wave 1: Format Validator + S3 Parser
**Files:**
- `Extensions/Spec/SpecFormatValidator.swift` — section order + completeness check
- `Extensions/Spec/TDDPParser.swift` — table extraction + BR cross-reference
- `Extensions/Spec/S3ScenarioParser.swift` — When/Then/if/otherwise/depending on parser
- `Extensions/Spec/WaveTreeParser.swift` — tree + BLOCKED BY + gate extraction
**Tests:** `Tests/SpecFormatValidatorTests.swift` (T-01..T-06, T-09)
**BRs:** BR-01..BR-09, BR-12
**Deps:** existing SpecFrontmatterParser
**Gate:** `swift test --filter SpecFormat` green

### Wave 2: CLI Integration ← BLOCKED BY Wave 1
**Files:** modify `Commands/SpecValidateCommand.swift`
**Tests:** T-07
**BRs:** BR-10
**Deps:** Wave 1 (SpecFormatValidator)
**Gate:** `shi spec validate` rejects bad spec, passes good spec

### Wave 3: Batch Upgrade ← BLOCKED BY Wave 1
**Files:** `scripts/upgrade-specs-s3.sh`
**Tests:** T-08
**BRs:** BR-11
**Deps:** Wave 1 (validator identifies gaps)
**Gate:** all `features/*.md` pass `shi spec validate`

## Spec Template — Definitive Reference

Every `/spec` output MUST follow this skeleton:

```markdown
---
title: "..."
status: draft
priority: P0/P1/P2
project: shikki
created: YYYY-MM-DD
authors: [...]
tags: [...]
depends-on: [...]
---

# Feature: ...
> Created: ... | Status: ... | Owner: ...

## Context
<why this feature exists>

## Business Rules
BR-01: ...
BR-02: ...

## TDDP — Test Summary Table
| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01 | Core (80%) | Unit | When X → Y |

### S3 Test Scenarios
T-01 [BR-01, Core 80%]:
When <context>:
  → <assertion>
  if <condition>:
    → <assertion>
  otherwise:
    → <fallback>

## Wave Dispatch Tree
Wave 1: <name>
  ├── <task> (no deps)
  └── <task> (depends: <other>)
  Input:  <what goes in>
  Output: <what comes out>
  Tests:  T-01, T-02
  Gate:   <test command> → green
  ║
  ╚══ Wave 2: <name> ← BLOCKED BY Wave 1
      ...

## Implementation Waves
### Wave 1: <name>
**Files:** ...
**Tests:** T-01..T-XX
**BRs:** BR-01..BR-XX
**Deps:** ...
**Gate:** ...

## Reuse Audit
| Utility | Exists In | Decision |
|---------|-----------|----------|

## @shi Mini-Challenge
1. ...
2. ...
3. ...
```
