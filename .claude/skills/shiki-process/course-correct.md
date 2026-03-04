# Course Correction — Mid-Feature Scope Change

Structured process for handling requirement changes, scope shifts, or discovered constraints
after a feature has progressed beyond Phase 2. Traces impact through all phases and rewinds
to the earliest affected point.

## When to use

- A business rule (BR-XX) needs to change after Phase 3
- A new requirement is discovered during implementation
- A technical constraint invalidates the architecture
- User feedback changes the scope or priority
- An external dependency changes (API, backend schema, platform guidelines)

## Protocol

### Step 1: Load Context

1. Read the feature file: `features/<feature>.md`
2. Identify current phase
3. Summarize current state: how many BRs, how many tests, how much is implemented

### Step 2: Capture the Change

Ask @Daimyo:
- "What changed?" (free text description)
- "Is this an addition, modification, or removal?"
- "How urgent is this? (blocking / important / nice-to-have)"

### Step 3: Impact Trace

For each phase, evaluate whether the change affects it:

| Phase | Affected? | Impact |
|-------|-----------|--------|
| Phase 1 (Inspiration) | Rarely | Only if the core concept changed |
| Phase 2 (Synthesis) | Check | Does the scope, success criteria, or dependencies change? |
| Phase 3 (Business Rules) | Check | Which BR-XX rules are added, modified, or removed? |
| Phase 4 (Test Plan) | Check | Which test signatures need adding, modifying, or removing? |
| Phase 5 (Architecture) | Check | Do files, protocols, DI, or data flow change? |
| Phase 5b (Execution Plan) | Check | Which tasks need adding, modifying, or removing? |
| Phase 6 (Implementation) | Check | Which completed tasks need rework? Which pending tasks change? |

Output the trace as a table:

```markdown
## Impact Trace: <change description>
| Phase | Status | Impact |
|-------|--------|--------|
| Phase 3 | AFFECTED | BR-03 modified, BR-09 added |
| Phase 4 | AFFECTED | 2 test signatures added, 1 modified |
| Phase 5 | NOT AFFECTED | Architecture unchanged |
| Phase 5b | AFFECTED | Task 7 modified, Task 10 added |
| Phase 6 | AFFECTED | Tasks 1-6 complete (no rework), Task 7 needs rework |

Earliest affected phase: Phase 3
```

### Step 4: Classify the Change

Based on the impact trace:

| Classification | Criteria | Action |
|----------------|----------|--------|
| **Tweak** | Only Phase 5b/6 affected, <= 2 tasks changed | Apply inline, no rewind |
| **Pivot** | Phase 3-5 affected, BRs change | Rewind to earliest affected phase |
| **Fork** | Core concept changed, or > 50% of work invalidated | Consider creating a new feature instead |

### Step 5: Propose Correction Plan

Present to @Daimyo:

```markdown
## Course Correction Plan: <feature>
**Change**: <description>
**Classification**: Tweak / Pivot / Fork
**Earliest affected phase**: Phase N

### Proposed edits:
- Phase 3: Modify BR-03 (was: "...", now: "..."), Add BR-09 ("...")
- Phase 4: Add test_imperfectDays_newLimit(), Modify test_imperfectDays_maxPerMonth()
- Phase 5b: Modify Task 7 (update limit check), Add Task 10 (new validation)
- Phase 6: Rework Task 7, Tasks 1-6 unchanged

### Impact on timeline:
- Completed work preserved: Tasks 1-6 (no rework)
- Rework needed: Task 7
- New work: Task 10
- Estimated additional effort: 2 tasks

### Options:
(a) Apply corrections and resume from Phase <N>
(b) Apply corrections but re-run readiness gate first
(c) Fork as new feature (keep current implementation, start fresh)
(d) Defer the change (track in backlog, ship current scope)
```

### Step 6: Apply Corrections

Based on @Daimyo's decision:

**(a) Apply and resume**:
1. Edit the feature file: update affected sections (BRs, test plan, architecture, execution plan)
2. Mark the feature as `Phase N — Course Corrected` in the header
3. Add entry to Review History table
4. Resume from the earliest affected phase

**(b) Apply with readiness gate**:
1. Same as (a), but re-run Implementation Readiness Gate before resuming Phase 6

**(c) Fork**:
1. Copy feature file to `features/<feature>-v2.md`
2. Mark original as `Shipped (v1)` or `Paused`
3. Start new feature at Phase 3 with the corrected BRs

**(d) Defer**:
1. Add the change to `backlog.md` as a follow-up item
2. Continue current implementation unchanged
3. Note in feature file: "Deferred: <change description>"

### Step 7: Sync

After corrections are applied:
1. Update the feature file
2. POST summary to Shiki if available:
```bash
POST http://localhost:3900/api/memories
{
  "projectId": "{project_id}",
  "content": "Course correction on <feature>: <classification> — <summary of changes>",
  "category": "feature",
  "importance": 0.8,
  "metadata": { "sourceFile": "features/<feature>.md" }
}
```
3. If in Phase 6, notify any active SDD agents of the change

Note: `{project_id}` comes from the project adapter or Shiki workspace registration.

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "The change is small, I'll just modify the code without updating the feature file" | The feature file is the source of truth. Code without spec is undocumented behavior. Update the file first. |
| "I'll skip the impact trace, I know which phases are affected" | You know what you THINK is affected. The trace catches cascading impacts you'd miss. |
| "Rewinding to Phase 3 is wasteful, the BRs are mostly the same" | Mostly the same = partially wrong. One bad BR corrupts all downstream phases. Rewind. |
| "I'll apply the correction and skip the readiness gate" | The readiness gate takes 30 seconds. Skipping it after a correction is when bugs sneak in. |
| "This is a fork, but I'll just modify the existing feature" | If >50% of work is invalidated, a fork is cleaner. Don't patch a foundation; rebuild it. |
