# Feature: Epic Branching — Scoped Git Flow for Multi-Wave Plans

> Created: 2026-03-19 | Status: Spec Draft | Owner: @Daimyo
> Priority: **P0** — affects every future multi-wave implementation
> Package: `packages/ShikiCore/` (DependencyTree + ShipService integration)

---

## Context

Today's session built 6 waves across 5 branches (`feature/shiki-mcp`, `feature/shiki-ship`, `feature/shiki-core`, `feature/wave2-integration`, `feature/wave2b-orchestration`). Each branch targets `develop` independently. Problems:

1. **No scope boundary** — PRs #7-#11 are 5 separate reviews with no parent grouping
2. **Changelog noise** — `shiki ship` pulls from ALL commits on develop, not just this epic's work
3. **No incremental fix path** — if E2E tests need a fix, it's a new orphan branch, not scoped to the epic
4. **Review fragmentation** — reviewer sees 5 PRs instead of 1 epic diff vs develop

## Solution: Epic Branch as Scope Container

```
develop
  ↑
  epic/shiki-v1-core          ← single review point, single merge, single changelog
    ↑
    ├── feat/shiki-mcp         (Wave 1A — 33 tests)
    ├── feat/shiki-ship        (Wave 1B — 24 tests)
    ├── feat/shiki-core-spm    (Wave 1C — 22 tests)
    ├── feat/wave2-integration (Wave 2A — merges 1A+1B+1C)
    ├── feat/wave2b-orch       (Wave 2B — merges 2A)
    ├── feat/wave3-e2e         (Wave 3 — merges 2B)
    └── fix/improve-e2e        (post-validation fix, targets epic)
```

### Rules

**BR-01**: Every multi-wave plan creates an `epic/<name>` or `story/<name>` branch from `develop`.

**BR-02**: All wave branches (`feat/`, `fix/`, `refactor/`) target the epic branch, never `develop` directly.

**BR-03**: Wave branches merge into the epic via PR. The epic accumulates all wave work.

**BR-04**: When the epic is complete (all waves done + validated), ONE PR is created: `epic/<name>` → `develop`. This is the single review point.

**BR-05**: `shiki ship` scopes changelog to `epic/<name>...HEAD`, not `develop...HEAD`. Only commits within this epic appear in the changelog. Clean, focused release notes.

**BR-06**: Post-validation fixes create `fix/<description>` branches targeting the epic, not develop. The epic stays the scope container until merged.

**BR-07**: `epic/` branches use the same naming as the plan: `epic/shiki-v1-core`, `story/onboarding`, `epic/maya-healthkit`.

**BR-08**: The DependencyTree in ShikiCore tracks wave→branch mappings. Each WaveNode already has `branch` and `baseBranch` fields. For epic flow: Wave 1 branches have `baseBranch: "epic/shiki-v1-core"`. Wave 2+ branches have `baseBranch` pointing to their dependency wave's branch OR the epic.

**BR-09**: `shiki ship --epic` mode: creates the epic→develop PR with aggregated changelog from all wave branches. Groups by wave, not by commit prefix.

**BR-10**: Branch cleanup: after epic merges to develop, all wave branches are deleted (git flow standard). The epic branch is also deleted. History preserved in merge commits.

## Impact on ShikiCore

### DependencyTree Changes

```swift
// WaveNode already has these fields — no struct change needed
public struct WaveNode {
    let branch: String      // "feat/shiki-mcp"
    let baseBranch: String  // "epic/shiki-v1-core" (not "develop")
}

// New: DependencyTree gets epic context
public struct DependencyTree {
    var epicBranch: String   // "epic/shiki-v1-core"
    var targetBranch: String // "develop"
    var waves: [WaveNode]
}
```

### ShipService Changes

```swift
// ChangelogGate scopes to epic, not full tree
// Before: git log develop..HEAD
// After:  git log epic/shiki-v1-core..HEAD (per-wave)
//    or:  git log develop..epic/shiki-v1-core (epic→develop)

// New flag: --epic
// shiki ship --epic → aggregates all wave changelogs into epic PR
```

### FeatureLifecycle Changes

```swift
// Lifecycle now knows its epic context
public actor FeatureLifecycle {
    let epicBranch: String?  // nil for standalone features
    // When shipping: PR targets epicBranch (not develop) if set
}
```

## Git Flow Integration

```
                    develop
                       │
              ┌────────┴────────┐
              │                 │
        epic/shiki-v1     epic/maya-health
              │                 │
    ┌─────┬───┼───┬─────┐     feat/...
    │     │   │   │     │
  feat/ feat/ │ feat/ fix/
  mcp   ship  │ core  e2e
              │
        feat/wave2
```

Each epic is an isolated scope. Multiple epics can run in parallel (different projects). `develop` only receives completed, validated epics.

## @shi Team Challenge

### @Sensei (CTO)
- The DependencyTree already has `branch` + `baseBranch` on WaveNode. Adding `epicBranch` to the tree root is minimal. ShipService's ChangelogGate needs a scope parameter — clean change.
- Risk: merge conflicts between epic and develop if epic lives too long. Mitigation: rebase epic on develop weekly, or before final merge.

### @Hanami (UX)
- Single epic PR is much better for review UX — one diff to read, one approval to give.
- `shiki ship --epic` manifest should show: wave count, total tests, total LOC delta, per-wave breakdown.

### @Kintsugi (Philosophy)
- Aligns with the "ship log, not ship count" principle. Each epic has ONE ship log entry with a meaningful "why", not 5 fragmented ones.
- The epic branch IS the narrative — you can read the git log and see the full story.

### @Shogun (Market)
- Competitor advantage: gstack has `/ship` but no scoped branching. Their changelog is full-tree noise. Ours is focused per-epic.
- Enterprise value: team members see their epic's work isolated from other team activity.

## Implementation Plan

### Task 1: Add epicBranch to DependencyTree
- File: `packages/ShikiCore/Sources/ShikiCore/Planning/DependencyTree.swift`
- Add `epicBranch: String` and `targetBranch: String` properties
- Test: DependencyTree with epic context creates correct wave base branches

### Task 2: Scope ChangelogGate to epic
- File: `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipGate.swift` (ChangelogGate)
- Add `scopeBranch` parameter: `git log <scopeBranch>..HEAD` instead of hardcoded develop
- Test: ChangelogGate with scopeBranch only includes scoped commits

### Task 3: Add --epic flag to ShipCommand
- File: `tools/shiki-ctl/Sources/shiki-ctl/Commands/ShipCommand.swift`
- `--epic` flag: targets epic branch, aggregates wave changelogs
- ShipRenderer: show wave breakdown in preflight manifest
- Test: ShipCommand with --epic produces epic-scoped changelog

### Task 4: Update FeatureLifecycle with epic context
- File: `packages/ShikiCore/Sources/ShikiCore/Lifecycle/FeatureLifecycle.swift`
- Add optional `epicBranch` — when set, PRGate targets epic instead of develop
- Test: FeatureLifecycle with epicBranch routes PR to epic

### Task 5: Branch creation automation in shiki-ctl
- New command or flag: `shiki start --epic "shiki-v1-core"` creates the epic branch
- Waves auto-set their baseBranch to the epic
- `shiki start --wave "1a-mcp" --epic "shiki-v1-core"` creates wave branch from epic

## Success Criteria

1. Multi-wave plans create epic branch, all waves target it
2. `shiki ship` changelog scoped to epic (no full-tree noise)
3. ONE PR for epic→develop review
4. Post-validation fixes target epic, not develop
5. Branch cleanup after merge (wave + epic branches deleted)

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-19 | Spec | @Daimyo | Draft | From session observation — fragmented PRs anti-pattern |
| 2026-03-19 | Review | @Sensei | CONDITIONAL | PRGate blocker, rebase→merge, drop Task 4 |
| 2026-03-19 | Review | @Hanami | CONDITIONAL | Defer Task 5, threshold rule, forbid nesting |
| 2026-03-19 | Review | @Shogun | CONDITIONAL | Lead with scoped changelog, add markdown export |

## Post-Review Corrections

### Critical (must fix before implementation)
1. **PRGate target validation** — add `epic/*` and `story/*` as valid targets (Task 0)
2. **Sync strategy** — "merge develop INTO epic" (not rebase). Rebase on merge-target is destructive.
3. **Drop Task 4** — epicBranch flows through `ShipContext.target`, not FeatureLifecycle
4. **baseBranch rule** — always the epic branch. Wave dependencies tracked in DependencyTree metadata only.
5. **Threshold rule** — 3+ branches or 2+ weeks of work = epic. Otherwise branch from develop directly.
6. **Nested epics** — explicitly forbidden for v1.

### Revised Task List (v1)
1. PRGate: accept `epic/*` and `story/*` targets
2. DependencyTree: add `epicBranch` + `targetBranch` properties
3. ChangelogGate: `scopeBranch` parameter for epic-scoped range
4. ShipCommand: `--epic` flag with scoped changelog + markdown export

### Deferred (v1.1)
- Task 5: `shiki start --epic` automation
- BR-09: Wave-grouped changelog rendering
- External integrations (Jira/Linear/Slack export)
