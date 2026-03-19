# /md-feature — Feature Creation Pipeline

Structured, repeatable process for taking a feature from idea to shipped code.
Test-first, documentation-driven, quality-gated. 8 phases (1-5, 5b, 6, 7).

## Commands

| Command | Action |
|---------|--------|
| `/md-feature "<name>"` | Start new feature at Phase 1 |
| `/md-feature review "<name>"` | Revisit existing feature |
| `/md-feature status` | List all features and phases |
| `/md-feature next "<name>"` | Advance to next phase |
| `/md-feature next "<name>" --yolo` | Advance with auto-proceed (see YOLO Mode) |

## YOLO Mode

Add `--yolo` to `/md-feature next` to skip confirmations and auto-proceed through phases.

**What YOLO skips**:
- Phase 2 (Synthesis): Uses sensible defaults instead of Q&A (scope = all selected ideas, priority = high)
- Phase 5b readiness gate: Auto-proceeds if no FAIL items (still runs the check)
- Elicitation offers: Auto-skips (see `elicitation.md`)

**What YOLO never skips**:
- Phase 1 brainstorming (ideas need @Daimyo selection)
- Phase 3 @Daimyo approval (business rules need human sign-off)
- Phase 6 test failures (tests must pass, always)
- Phase 7 /pre-pr gates (quality is non-negotiable)

YOLO mode is for experienced features where the user trusts the pipeline and wants speed.

## Pipeline

```
Phase 1:  INSPIRATION      ← @Shogun + @Hanami + @Kintsugi + @Sensei
Phase 2:  SYNTHESIS         ← Orchestrator (Q&A with user)
Phase 3:  BUSINESS RULES    ← @Sensei + @Daimyo approval
Phase 4:  TEST PLAN         ← @testing-expert (adapts to project language)
Phase 5:  ARCHITECTURE      ← @Sensei
Phase 5b: EXECUTION PLAN    ← @Sensei (atomic tasks for SDD)
  ── READINESS GATE ──       must PASS before Phase 6
Phase 6:  IMPLEMENTATION    ← SDD protocol (subagent-driven, see sdd-protocol.md)
Phase 7:  QUALITY GATE      ← /pre-pr pipeline
```

## Phase 1: Inspiration

**Duration**: ~10 min brainstorm
**Agents**: @Shogun (3 ideas), @Hanami (3 ideas), @Kintsugi (2 ideas), @Sensei (2 ideas)

1. Create `features/<name>.md` with template (see below)
1b. Update `README.md` → `## Feature Roadmap` (see `feature-tracking.md`): add new entry with Phase 1 checked
2. Launch 4 parallel sub-agents, each returns ideas
3. Merge into ranked table:

```markdown
| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|---------:|
| 1 | ...  | @Hanami | High       | High   | Strong       | BUILD   |
```

4. @Daimyo picks top 3-5 to carry forward
5. Write to **Inspiration** section

## Phase 2: Synthesis

**Duration**: ~5 min Q&A

1. Present summary of selected ideas
2. Ask 3-5 clarifying questions:
   - Scope boundaries (v1 vs deferred)
   - User expectations and edge cases
   - Integration points with existing features
   - Platform targets (read from project adapter)
   - Priority relative to backlog
3. Synthesize into Feature Brief:
   - **Goal** (1 sentence)
   - **Scope** (bullet list)
   - **Out of scope** (deferred items)
   - **Success criteria**
   - **Dependencies**

## Phase 3: Business Rules

**Duration**: ~15 min
**Agent**: @Sensei drafts, @Daimyo approves

Numbered rules covering:
- State machine (all states and transitions)
- Validation rules (input constraints, error conditions)
- Lifecycle (creation, update, deletion, archival)
- Edge cases (concurrent access, empty states, limits)
- Permissions (who can do what)
- Interactions (how this affects other features)
- Data model (entities, relationships, persistence)

Format:
```
BR-01: A habit can have at most 4 imperfect days per month
BR-02: When imperfect day is declared, streak pauses (not breaks)
BR-03: Imperfect days reset on the 1st of each month
```

## Phase 4: Test Plan

**Duration**: ~15 min

For each BR-XX, define at least 1 test case:
```
BR-01 → test_imperfectDays_maxFourPerMonth()
BR-01 → test_imperfectDays_fifthDeclaration_throws()
```

Group by:
- **Unit tests** — pure logic, no dependencies
- **Integration tests** — with real services/repos
- **Snapshot/UI tests** — UI components (if applicable)

Write test signatures (not implementations) as the plan.

## Phase 5: Architecture

**Duration**: ~10 min
**Agent**: @Sensei

Design:
- Files to create/modify (table with path + purpose)
- Protocols and models (key properties/methods)
- DI registration plan (per project adapter conventions)
- Coordinator/router integration (if navigation)
- Data flow diagram (View → ViewModel → UseCase → Repository → Backend)
- Map each test case to its implementation target

## Phase 5b: Execution Plan

**Duration**: ~10 min
**Agent**: @Sensei

Convert Phase 5 architecture into atomic, executable tasks for SDD. Each task must be self-contained enough for a "zero-context engineer" (a fresh subagent with no prior knowledge of this feature beyond the feature file).

Each task includes:
- Task number and title
- Exact file path(s) to create or modify
- What to implement (specific enough for zero-context)
- Test to write FIRST (from Phase 4 signatures)
- Expected test command and output (red then green)
- Estimated time: 2-5 minutes per task
- BR-XX references (which business rules this task satisfies)

Format:
```
### Task 1: Create FzfSlab struct
- **Files**: `Sources/FzfKit/FzfSlab.swift` (new)
- **Test**: `Tests/FzfKitTests/FzfSlabTests.swift` -> `test_ensure_growsCapacity()`
- **Implement**: Slab struct with i16/i32 arrays, ensure(capacity:) grows without shrinking, reset() zeroes used portions
- **Verify**: `{test_command} --filter FzfSlabTests` -> 1 test passing
- **BRs**: BR-07 (memory pooling)
- **Time**: ~3 min
```

Note: `{test_command}` comes from the project adapter (e.g., `swift test`, `npm test`, `deno test`).

### Implementation Readiness Gate

Run this gate before dispatching any SDD subagents. All items must PASS (or N/A).

| Check | How to verify | PASS criteria |
|-------|--------------|---------------|
| BR Coverage | Every BR-XX maps to at least one task | 100% -- no orphan BRs |
| Test Coverage | Every Phase 4 test signature maps to a task | 100% -- no orphan tests |
| File Alignment | Every file in Phase 5 architecture appears in a task | No files missing from plan |
| Task Dependencies | Tasks ordered so dependencies come first | No circular references, no forward refs |
| DI Registration | New protocols/types have DI registration tasks | Every new type has a registration task |
| Router/Coordinator Routes | New screens have navigation integration tasks | Navigation planned |
| Task Granularity | Each task is 2-5 minutes, single focus | No mega-tasks (>10 min est) |
| Testability | Each task has a clear test command with expected output | Every task has a "Verify" step |

Output format:
```markdown
## Implementation Readiness Gate
| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 8/8 BRs mapped |
| Test Coverage | PASS | 12/12 signatures mapped |
| File Alignment | PASS | 6/6 files covered |
| Task Dependencies | PASS | Linear order, no cycles |
| DI Registration | PASS | 2 new types registered |
| Coordinator Routes | N/A | No new screens |
| Task Granularity | FAIL | Task 4 estimated 15 min -- split it |
| Testability | PASS | All tasks have verify step |

Verdict: FAIL -- split Task 4 before proceeding to Phase 6
```

**Verdict: PASS** (all items pass or N/A) -- proceed to Phase 6.
**Verdict: FAIL** (any item fails) -- fix the execution plan, re-run the gate.

IMPORTANT: Do NOT start Phase 6 with a FAIL verdict. Fix the plan first.

**Output**: Execution Plan section + Readiness Gate result added to the feature file.

## Phase 6: Implementation (SDD)

Phase 6 follows the Subagent-Driven Development protocol defined in `sdd-protocol.md`.

The orchestrator dispatches fresh subagents per the execution plan from Phase 5b. The orchestrator tracks progress and handles escalations. It does NOT write code.

Per-task cycle:
1. Dispatch IMPLEMENTER subagent (TDD: red -> green -> refactor)
2. Dispatch SPEC REVIEWER subagent (BR compliance check)
3. Fix loop if needed (max 3 attempts)
4. Dispatch CODE QUALITY REVIEWER subagent (architecture + standards)
5. Fix loop for Critical items if needed (max 3 attempts)
6. Mark task complete

After all tasks:
7. Dispatch FINAL REVIEWER subagent (cross-task integration check)
8. Run Verification Protocol (test count, BR coverage map, no unsafe patterns)
9. Log progress in Implementation Log section

Before proceeding to Phase 7, run `checklists/definition-of-done.md`. All items must PASS or N/A.

## Phase 7: Quality Gate

Hand off to `/pre-pr`. The feature file path is included in the PR body.

## README Tracking (every phase)

After completing ANY phase, update `README.md` → `## Feature Roadmap`:
1. Check the completed phase in the sub-checklist
2. Update the WIP counter: `(N/M phases)` → `(N+1/M phases)`
3. See `feature-tracking.md` for full format specification

When Phase 7 passes and PR is merged (validated via `/validate-pr`):
1. Check the top-level feature checkbox
2. Remove the WIP sub-checklist

## Feature File Template

```markdown
# Feature: <Name>
> Created: YYYY-MM-DD | Status: Phase 1 — Inspiration | Owner: @Daimyo

## Context
<1-2 sentences: why this feature exists>

## Inspiration
### Brainstorm Results
<10-idea table>
### Selected Ideas
<3-5 approved ideas>

## Synthesis
<Feature brief from Phase 2>

## Business Rules
<BR-XX numbered rules>

## Test Plan
<Test signatures grouped by type>

## Architecture
<Files, protocols, DI, data flow>

## Execution Plan
<Atomic tasks for SDD, from Phase 5b>

## Implementation Log
<Decisions, progress notes, SDD progress table>

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
```

## Shiki Sync

After each phase, sync to Shiki if available: Use the `shiki_save_event` MCP tool with:
```json
{
  "type": "feature_phase_completed",
  "scope": "<project-slug>",
  "data": {
    "content": "<phase summary>",
    "category": "feature",
    "importance": 0.8,
    "metadata": { "sourceFile": "features/<name>.md" }
  }
}
```

Note: `<project-slug>` comes from the project adapter or Shiki workspace registration.

## Information Density Check

Run on the feature file before Phase 7 handoff to ensure the spec is clean and token-efficient.

### Filler patterns to flag

| Category | Examples | Fix |
|----------|----------|-----|
| Hedge phrases | "it might be worth considering", "perhaps we should", "it could potentially" | State directly: "do X" |
| Filler | "as mentioned above", "it should be noted that", "in order to" | Delete or simplify: "to" |
| Redundant qualifiers | "very unique", "completely essential", "absolutely necessary" | Drop the qualifier |
| Passive voice overuse | "it was decided that", "the feature is being implemented" | Use active: "we decided", "@Sensei designed" |
| Vague quantities | "several", "various", "a number of" | Use specific numbers |
| AI slop phrases | "I'd be happy to", "certainly!", "let me help you with that" | Delete entirely |

### Scoring

Count violations across the feature file:
- **0-3**: CLEAN — proceed
- **4-8**: WARNING — suggest edits, proceed after fixes
- **9+**: BLOATED — must trim before Phase 7

### Process

1. Read the entire feature file
2. Scan each section for filler patterns
3. Report density score with specific line references
4. If WARNING or BLOATED: propose edits (show before/after)
5. Apply edits with user approval

## Three-Pass Tracking

Every feature tracks its development pass. The 8-phase pipeline covers Pass 1-2.
Pass 3 (Skin) happens later as a dedicated visual QC sweep before release.

| Pass | Phases | Focus | Quality bar |
|------|--------|-------|-------------|
| **1. Skeleton** | Phase 1-5b | Architecture, navigation, DI, data flow | Compiles, navigates, tests pass |
| **2. Muscle** | Phase 6-7 | Implementation, TDD, /pre-pr gates | Features functional, gates pass |
| **3. Skin** | Post-merge | UI polish, animations, visual QC | Visual QC PASS (per project adapter) |

Pass 3 is NOT part of the feature pipeline — it's a separate pre-release sweep.
Don't mix structural work (Pass 1-2) with polish work (Pass 3).
Move fast on bones, take time on skin.

Between passes: stay creative. Challenge the process itself. Think out of the box.
A competitive advantage comes from doing what others don't — not from following a script.

## Pipeline Checkpointing

If ShikiMCP tools are available (verify with `shiki_health` MCP tool), checkpoint each phase for resume support. If unavailable, skip checkpointing silently — the pipeline works without it.

**On start**: Create a pipeline run: Use the `shiki_save_event` MCP tool with:
```json
{ "type": "pipeline_started", "scope": "md-feature", "data": { "pipelineType": "md-feature", "config": {} } }
```
Store the returned ID as RUN_ID.

**After each phase**: Record a checkpoint: Use the `shiki_save_event` MCP tool with:
```json
{ "type": "pipeline_checkpoint", "scope": "md-feature", "data": { "runId": "<RUN_ID>", "phase": "<phase>", "phaseIndex": "<N>", "status": "completed", "stateAfter": {...} } }
```

**Phase names**: `phase_1_inspiration` (0), `phase_2_synthesis` (1), `phase_3_business_rules` (2), `phase_4_test_plan` (3), `phase_5_architecture` (4), `phase_5b_execution_plan` (5), `phase_5b_readiness_gate` (6), `phase_6_implementation` (7), `phase_7_quality_gate` (8)

**On failure**: Record with `"status":"failed"`, then check routing: Use the `shiki_save_event` MCP tool with:
```json
{ "type": "pipeline_route", "scope": "md-feature", "data": { "runId": "<RUN_ID>", "failedPhase": "<phase>" } }
```

**On completion**: Use the `shiki_save_event` MCP tool with: `{ "type": "pipeline_completed", "scope": "md-feature", "data": { "runId": "<RUN_ID>", "status": "completed" } }`

**On resume** (via `/retry`): Skip phases with index < resumeFromIndex. Use the provided state.

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "Phase 1 brainstorming is unnecessary, the user already knows what they want" | Phase 1 explores angles the user hasn't considered. 4 perspectives > 1. Always run it. |
| "Phase 3 business rules are overkill for a simple feature" | If it's simple, the rules are few. Write them anyway — they prevent scope creep in Phase 6. |
| "Phase 4 test plan is unnecessary for a UI-only change" | UI changes break accessibility, Dynamic Type, dark mode, VoiceOver. Test it. |
| "I can skip Phase 5b and go straight to implementation" | Phase 5b enables SDD. Without atomic tasks, subagents have no clear scope. Always write the plan. |
| "The readiness gate passed mostly, one FAIL is fine" | One FAIL means a subagent will hit a wall. Fix it now (minutes) or debug it later (much longer). No partial passes. |
| "I'll combine Phases 3 and 4 to save time" | Business rules inform tests. Tests don't inform business rules. The order matters. |
| "The feature file is getting too long, I'll skip some sections" | The feature file IS the specification. Every section exists for a reason. Write it completely. |
| "Phase 2 Q&A is unnecessary, I understand the requirements" | You understand YOUR interpretation. Phase 2 verifies the USER's intent. Always ask. |
| "I can implement without waiting for @Daimyo approval on Phase 3" | @Daimyo is the final authority on business rules. No implementation without approval. |
