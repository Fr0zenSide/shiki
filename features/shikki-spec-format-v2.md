---
title: "Spec Format v2 — Mandatory BR → TDDP → Waves"
status: implementing
priority: P0
project: shikki
created: 2026-04-02
authors: ["@Daimyo"]
tags: [process, spec, tddp, quality]
---

# Feature: Spec Format v2 — Mandatory BR → TDDP → Waves
> Created: 2026-04-02 | Status: Implementing | Owner: @Daimyo

## Context

Specs have been shipping without TDDP mapping and wave dependency trees. Agents receive specs and don't know what to test first, what blocks what, or what coverage tier applies. This makes dispatch unreliable and review impossible.

Section order matters — it's for reviewing most important data first. BRs define truth, TDDP proves it, Waves execute it.

## Business Rules

```
BR-01: Every spec MUST contain sections in this order: BR → TDDP → Wave Dispatch Tree → Implementation Waves
BR-02: Every BR MUST be numbered BR-01 through BR-N, one line each, clear enforcement verb (MUST/MUST NOT)
BR-03: Every test in TDDP MUST map to at least one BR — orphan tests are rejected
BR-04: Every BR MUST have at least one test in TDDP — untested BRs are rejected
BR-05: TDDP table MUST include columns: Test ID, BR, Tier, Type, Description
BR-06: Coverage tiers are: Security (100%), Core (80%), Smoke (CLI), E2E (scripts)
BR-07: Wave Dispatch Tree MUST show dependencies with ← BLOCKED BY notation
BR-08: Each wave MUST have a Gate condition (test command + success criteria)
BR-09: Implementation Waves MUST list: files (full paths), tests (T-IDs), deps, gate
BR-10: /spec pipeline MUST validate format before saving — reject specs missing mandatory sections
BR-11: Existing specs without TDDP/Waves MUST be upgraded before dispatch
```

## TDDP

| Test | BR | Tier | Type | Description |
|------|-----|------|------|-------------|
| T-01 | BR-01 | Core (80%) | Unit | Spec parser validates section order (BR before TDDP before Waves) |
| T-02 | BR-03 | Core (80%) | Unit | Spec validator rejects test not mapped to any BR |
| T-03 | BR-04 | Core (80%) | Unit | Spec validator rejects BR with no test coverage |
| T-04 | BR-05 | Core (80%) | Unit | TDDP table parser extracts all 5 columns correctly |
| T-05 | BR-07 | Core (80%) | Unit | Wave tree parser detects BLOCKED BY dependencies |
| T-06 | BR-08 | Core (80%) | Unit | Wave without gate condition is rejected |
| T-07 | BR-10 | Smoke (CLI) | Integration | `shi spec validate` rejects spec missing TDDP section |
| T-08 | BR-11 | E2E | Script | Batch upgrade script adds TDDP skeleton to all specs in features/ |

## Wave Dispatch Tree

```
Wave 1: Format Validator
  ├── SpecFormatValidator (no deps)
  ├── TDDPParser (no deps)
  └── WaveTreeParser (no deps)
  Tests: T-01, T-02, T-03, T-04, T-05, T-06
  Gate: swift test --filter SpecFormat → green

Wave 2: CLI Integration ← BLOCKED BY Wave 1
  ├── Wire into shi spec validate (depends: SpecFormatValidator)
  └── Wire into /spec pipeline (depends: SpecFormatValidator)
  Tests: T-07
  Gate: shi spec validate features/shikki-bg-command.md → passes

Wave 3: Batch Upgrade ← BLOCKED BY Wave 1
  ├── Upgrade script for existing specs
  └── Manual review of generated TDDP/Waves
  Tests: T-08
  Gate: all specs in features/ pass shi spec validate
```

## Implementation Waves

### Wave 1: Format Validator
**Files:** `Extensions/Spec/SpecFormatValidator.swift`, `Extensions/Spec/TDDPParser.swift`, `Extensions/Spec/WaveTreeParser.swift`
**Tests:** `Tests/SpecFormatValidatorTests.swift` (T-01 through T-06)
**Deps:** existing SpecFrontmatterParser
**Gate:** `swift test --filter SpecFormat` green

### Wave 2: CLI Integration ← blocked by W1
**Files:** modify `Commands/SpecValidateCommand.swift`
**Tests:** T-07
**Deps:** Wave 1
**Gate:** `shi spec validate` rejects bad spec, passes good spec

### Wave 3: Batch Upgrade ← blocked by W1
**Files:** `scripts/upgrade-specs-format.sh`
**Tests:** T-08
**Deps:** Wave 1 (validator tells us what's missing)
**Gate:** all features/*.md pass validation

## Spec Template

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
---

# Feature: ...

## Context
## Business Rules
## TDDP
| Test | BR | Tier | Type | Description |
|------|-----|------|------|-------------|

## Wave Dispatch Tree
## Implementation Waves
### Wave 1: ...
### Wave 2: ... ← BLOCKED BY Wave 1
## Reuse Audit
## @shi Mini-Challenge
```
