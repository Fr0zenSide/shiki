# Feature: Autopilot v2 — Dependency Tree + Test Plan Driven Development

> **Type**: /md-feature
> **Priority**: P1 — improves /dispatch and /md-feature pipelines
> **Status**: Spec (validated by @Daimyo + @Shi team 2026-03-18)
> **Depends on**: Worktree system (existing), /md-feature pipeline (existing)

---

## 1. Problem

### 1A. No Dependency Visibility
When `/dispatch` or `/autopilot` plans multi-wave work, it creates worktrees and branches but:
- User doesn't see the full dependency tree before execution starts
- Can't edit the plan (reorder waves, change branch targets)
- After execution, must manually figure out PR chain for review
- What we did manually today (rebase PR #6 onto PR #5) should be automatic

### 1B. No Test Strategy in Plans
Current plans list deliverables and files but don't specify:
- Which tests will be written first (TDD)
- What concerns/edge cases should be covered
- What the test plan looks like before code exists
- User can't add test scenarios before execution

## 2. Solution

### 2A. Dependency Tree Visualization

Before execution, show an interactive tree:

```
DEPENDENCY TREE — /dispatch v3-orchestrator
══════════════════════════════════════════════

  develop (fdec592) ─── base branch
    │
    ├─► Wave 1: feature/v3-wave1-sessions
    │   ├─ SessionLifecycle.swift (8 tests)
    │   ├─ SessionJournal.swift (6 tests)
    │   └─ SessionRegistry.swift (11 tests)
    │
    ├─► Wave 2: feature/v3-wave2-events (depends on W1)
    │   ├─ ShikiEvent.swift (4 tests)
    │   ├─ EventBus.swift (7 tests)
    │   └─ SpecDocument.swift (8 tests)
    │
    └─► Wave 3: feature/v3-wave3-personas (depends on W2)
        ├─ AgentPersona.swift (10 tests)
        └─ Watchdog.swift (10 tests)

  ► = pending  ● = in progress  ✓ = done  ✗ = failed

  Final branch: feature/v3-wave3-personas
  Position here = full project with all waves

  [e] edit  [Enter] approve + start  [r] reorder  [q] cancel
```

**Edit mode** allows:
- Reorder waves (drag up/down)
- Remove a wave (mark as deferred)
- Change branch names
- Change base branch per wave
- Add notes per wave

**During execution**:
- Tree updates live (► → ● → ✓ or ✗)
- Failed wave shows error, options: retry / skip / abort

**After execution**:
- Tree becomes the PR review plan
- Each wave = one PR targeting its parent
- User can merge bottom-up or review top-down

### 2B. Test Plan Driven Development (TPDD)

Every plan gets a `## Test Strategy` section. This is the contract between user and agent — what will be verified.

```markdown
## Test Strategy

### Concerns (user can edit before execution)
- [ ] What if journal file is locked by another process?
- [ ] Does 5-minute staleness threshold work on slow CI?
- [ ] Can two registries write to same journal concurrently?

### Test Scenarios (agent proposes, user approves)

#### SessionLifecycle (8 tests)
- `validTransitionSpawningToWorking` — happy path
- `invalidTransitionDoneToWorking` — terminal state enforcement
- `attentionZonePrOpenIsReview` — zone mapping
- `attentionZoneApprovedIsMerge` — zone mapping
- `budgetPauseTrigger` — budget gate
- `zfcReconcileTmuxDead` — ZFC principle
- `zfcReconcileTmuxAlive` — no false positive
- `transitionHistoryRecorded` — audit trail

#### SessionJournal (6 tests)
- `appendWritesJsonlLine` — basic append
- `loadReturnsOrderedList` — read back
- `pruneRemovesOldFiles` — cleanup
- `pruneKeepsRecentFiles` — no false prune
- `emptyJournalReturnsEmpty` — edge case
- `coalescedDebounce` — write optimization

### Edge Cases (from concerns)
- `journalWithLockedFile` — throws, doesn't corrupt
- `concurrentRegistryWrites` — actor isolation prevents race

### Coverage Target
- Changed files: 100% of public API
- Critical paths: 100% of state transitions
- Edge cases: all concerns addressed
```

**The flow**:
1. Agent generates test plan as part of `/md-feature` Phase 3
2. User sees test plan in the dependency tree (per wave)
3. User can ADD concerns (`[e]` to edit)
4. User approves → agent writes tests FIRST (TDD)
5. Tests become the verification surface for review

**Integration with SpecDocument** (already built):
- `SpecDocument.requirements` → maps to test scenarios
- `SpecDocument.phases` → maps to waves in dependency tree
- `SpecDocument.decisions` → captured during execution
- NEW: `SpecDocument.testPlan` → the TPDD section

### 2C. Optional Review Mode

After all waves complete:

```
ALL WAVES COMPLETE — 3/3 green
══════════════════════════════

  ✓ Wave 1: 31 tests passing
  ✓ Wave 2: 22 tests passing
  ✓ Wave 3: 20 tests passing

  Total: 73 tests, 0 failures

  What next?
  1. Review all PRs (/review queue)     ← recommended
  2. Merge to develop (--yolo)
  3. Review later (PRs stay open)

  [1/2/3]
```

**--yolo mode**: skip review, auto-merge all waves bottom-up. Tests are the quality gate.
**Default**: prompt for review. Show that review is available and recommended.
**Never hide**: always show test count + pass status regardless of mode.

---

## 3. Implementation

### Phase A: Dependency Tree Data Model (~100 LOC, ~5 tests)
- `DependencyTree` struct — waves with parent links
- `WaveNode` — name, branch, base, files, test count, status
- Serializable (save/load for resume)

### Phase B: Tree Visualization TUI (~150 LOC, ~4 tests)
- Render tree with status indicators
- Edit mode: reorder, remove, rename
- Progress update during execution

### Phase C: TPDD in SpecDocument (~100 LOC, ~4 tests)
- `TestPlan` struct added to SpecDocument
- `TestScenario` — name, description, edge case flag
- `Concern` — user-added question with optional test mapping
- Render in plan output

### Phase D: Execution Engine (~200 LOC, ~6 tests)
- Walk dependency tree, create worktrees per wave
- Execute TDD per wave (tests first, then implementation)
- Update tree status live
- Handle failures (retry/skip/abort)

### Phase E: Post-Execution Flow (~50 LOC)
- Show completion summary
- Review/merge/defer options
- PR creation with dependency chain

**Total**: ~600 LOC, ~19 tests

---

## 4. @Shi Team Verdict on TPDD

### @Sensei
TPDD is TDD with a planning layer. The test plan is the spec's executable equivalent. When tests pass, the spec is implemented. When tests fail, the gap is visible. **Approved — this is how we should have always worked.**

### @Hanami
The edit-before-execute UX is critical. Users who add concerns feel ownership of the quality. Users who don't edit still get the agent's test plan as a baseline. **Both paths produce good outcomes.**

### @Kintsugi
"The specification driven by tests" — you're not replacing review. You're making review faster. A reviewer who sees a test plan with all concerns addressed spends 5 minutes instead of 30. The test plan IS the review prep. **The test plan and the review are two sides of the same coin.**
