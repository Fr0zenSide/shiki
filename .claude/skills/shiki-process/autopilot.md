# Autopilot — `/autopilot`

Batch multiple backlog items through the full pipeline: plan → decide → build → quality gate → review package. You interact only at decision gates — everything else is autonomous.

## Usage

```
/autopilot BL-003 BL-005 BL-001
/autopilot BL-003                     # Single item works too
/autopilot BL-003 BL-005 --yolo       # Skip Tier 3 questions, use sensible defaults
```

**Arguments**: Backlog item IDs (from `memory/backlog.md`) or free-text feature descriptions in quotes.

## Prerequisites

- ShikiMCP tools available (verify with `shiki_health` MCP tool)
- Clean git state on `develop` (or target branch)
- Backlog items have at least a title and description

## Pipeline Overview

```
/autopilot BL-003 BL-005 BL-001
       │
       ▼
  WAVE 0: PLANNING (autonomous)
  → Parallel subagents draft plans per feature
  → Output: scope, BRs, test plan, architecture, execution plan, blocking questions
       │
       ▼
  WAVE 1: DECISIONS (interactive — Tier 1 blocking questions)
  → All features' critical questions in one batch
  → Architecture, scope, data model decisions
       │
       ▼
  WAVE 1b: REFINEMENT (interactive — Tier 2 + plan approval)
  → Important questions + refined plan presentation
  → "Here's the final plan for all N features. LGTM?"
       │
       ▼
  CONFIDENCE GATE (autonomous)
  → File conflict analysis across features
  → Determines parallel vs sequential dispatch
  → Max 3 concurrent worktrees
       │
       ▼
  WAVE 2: BUILD (autonomous)
  → Dispatch to isolated worktrees
  → SDD protocol: TDD per task, auto-commit
  → Progress tracked in shiki DB
       │
       ▼
  WAVE 3: QUALITY (autonomous)
  → Pre-PR gates + @shi team review per feature
  → Auto-fix critical issues
  → Generate review package MD per feature
       │
       ▼
  WAVE 4: PRESENT (interactive)
  → Summary table: Feature | Status | Issues | PR
  → Per feature: "Review now or later?"
  → Now = interactive /review session
  → Later = MD file ready for async review
```

---

## Wave 0: Planning (Autonomous)

### What happens

For each backlog item, launch a **parallel subagent** (one per feature) that drafts:

1. **Scope summary** — what the feature does, boundaries, out-of-scope
2. **Business Rules** — BR-01, BR-02, ... (state machine, validation, lifecycle, edge cases)
3. **Test Plan** — test signatures derived from each BR, grouped by unit/integration/snapshot
4. **Architecture** — files to create/modify, protocols, DI registration, data flow
5. **Execution Plan** — atomic 2-5 min tasks, file paths, test-first, BR refs
6. **Blocking Questions** — decisions the subagent cannot make, tagged by tier

### Subagent prompt template

Each planning subagent receives:
- The backlog item description (from `memory/backlog.md`)
- The project adapter (tech stack, conventions)
- Access to read the codebase (existing files, patterns)
- Instruction: "Draft a complete feature plan. For every decision you can't make, add it to the questions list with a tier tag."

### Question tiers

| Tier | Tag | Description | Example |
|------|-----|-------------|---------|
| **T1** | `[BLOCKING]` | Cannot proceed without answer. Architecture, data model, scope. | "Where does the haiku appear? Full-screen overlay or inline card?" |
| **T2** | `[IMPORTANT]` | Affects implementation but has a reasonable default. | "Should haiku rotation be deterministic (date-based) or random?" |
| **T3** | `[DEFAULT-OK]` | Cosmetic or minor. Subagent picks a default, user overrides in review. | "Animation duration: 0.3s or 0.5s?" |

### Output per feature

Saved to `features/<name>.md` (draft state):

```markdown
---
status: draft
autopilot: true
blocking_questions: N
---
# Feature: <name>
## Scope
## Business Rules
## Test Plan
## Architecture
## Execution Plan
## Blocking Questions
### Tier 1 (Blocking)
### Tier 2 (Important)
### Tier 3 (Defaults chosen)
```

---

## Wave 1: Decisions

Wave 1 behavior depends on whether autopilot is running in **company mode** (orchestrator-managed) or **interactive mode** (user-driven).

### Detecting Company Mode

Check for the `SHIKI_COMPANY_ID` environment variable. If set, this autopilot session is managed by the orchestrator.

### Interactive Mode (default — no SHIKI_COMPANY_ID)

Present ALL Tier 1 questions across ALL features in a single batch:

```markdown
## Decisions needed — Tier 1 (Blocking)

### BL-003: Daily Haiku
1. Where does the haiku appear? Options: (a) Full-screen on first open (b) Card in Today tab (c) Splash→home transition
2. Content source: (a) Bundled seed data only (b) Backend-fetched (c) Hybrid (bundled + sync)
3. ...

### BL-005: NetworkError Leakage
1. Should UseCases define their own error enum or use a shared `DomainError`?
2. ...

---
Answer format: "BL-003: 1a, 2c, 3..." or discuss any question.
```

#### Rules

- Present questions numbered per feature
- Provide options with short labels (a/b/c) when possible
- Include the subagent's recommendation with rationale for each
- Accept batch answers: "BL-003: 1a 2c 3b, BL-005: 1a"
- If user wants to discuss a question, discuss it, then continue

#### After answers

Feed answers back to planning subagents → they refine the plan with decisions applied.

### Company Mode (SHIKI_COMPANY_ID is set)

Instead of presenting questions interactively, write them to the **decision queue** in Shiki DB. This allows the orchestrator to batch decisions across companies and notify the user via push.

#### For each T1 question:

1. **Create decision in queue**: Use the `shiki_save_event` MCP tool with:
   ```json
   {
     "type": "decision_queued",
     "scope": "orchestrator",
     "data": {
       "companyId": "$SHIKI_COMPANY_ID",
       "taskId": "<current-task-uuid>",
       "tier": 1,
       "question": "Where does the haiku appear?",
       "options": {
         "a": {"label": "Full-screen overlay", "recommended": true, "rationale": "Minimal coordinator changes"},
         "b": {"label": "Card in Today tab", "rationale": "Requires new card component"},
         "c": {"label": "Splash transition", "rationale": "Most complex, best UX"}
       },
       "context": "Affects coordinator flow and whether we need a new screen vs card."
     }
   }
   ```

2. **Block the task**: Use the `shiki_save_event` MCP tool with:
   ```json
   {
     "type": "task_blocked",
     "scope": "orchestrator",
     "data": { "taskId": "<task-id>", "status": "blocked", "blockingQuestionIds": ["<decision-id-1>", "<decision-id-2>"] }
   }
   ```

#### T2/T3 handling in company mode:

- **T2 with `--yolo`**: auto-answer with default, log to decision queue with `answered=true`
- **T2 without `--yolo`**: write to decision queue like T1
- **T3**: always auto-answer with subagent's default choice (don't queue)

#### After writing decisions:

1. **Do NOT block the session** — move to the next non-blocked task in the queue
2. **Poll for answers** every 30 seconds: Use the `shiki_search` MCP tool with: `{ query: "unanswered decisions company $SHIKI_COMPANY_ID", projectIds: [] }`
3. When a previously-blocking decision is answered, the API auto-unblocks the task
4. On next poll/claim cycle, the task becomes available again
5. Resume from the last pipeline checkpoint

#### If all tasks are blocked:

Enter a poll-only loop (30s interval). When any decision is answered and a task unblocks, resume normal operation. If idle for > 10 minutes with all tasks blocked, POST `company_idle` and exit — the orchestrator will relaunch when decisions arrive.

---

## Wave 1b: Refinement (Interactive)

### Presentation format

1. Show any remaining **Tier 2** questions (same batch format)
2. Present the **refined plan summary** per feature:

```markdown
## Final Plans — Review & Approve

### BL-003: Daily Haiku
- **Scope**: Daily haiku on app open, full-screen overlay, bundled seed data
- **Files**: 8 new (model, repo, view, VM, coordinator, DI, tests, seed data)
- **BRs**: 6 rules
- **Tests**: 14 unit + 6 snapshot
- **Tasks**: 7 atomic tasks (~35 min estimated)

### BL-005: NetworkError Leakage
- **Scope**: 3 VMs + 3 UseCases refactored
- **Files**: 6 modified
- **BRs**: 3 rules
- **Tests**: 9 unit
- **Tasks**: 4 atomic tasks (~15 min estimated)

### BL-001: Settings Debug Extraction
- **Scope**: Extract #if DEBUG to extension file
- **Files**: 2 modified (1 source, 1 new extension)
- **BRs**: 2 rules
- **Tests**: 3 unit
- **Tasks**: 2 atomic tasks (~8 min estimated)

---
Reply: "LGTM" to proceed, or "BL-003: change X" to adjust.
```

### After approval

Proceed to Confidence Gate.

---

## Confidence Gate (Autonomous)

### File conflict analysis

For each pair of features, check if their execution plans touch the same files:

```
BL-003 ∩ BL-005 = {} → parallel OK
BL-003 ∩ BL-001 = {} → parallel OK
BL-005 ∩ BL-001 = {} → parallel OK
```

### Rules

- **No overlap** → dispatch all in parallel (max 3 concurrent)
- **Overlap exists** → dispatch conflicting features sequentially, non-conflicting in parallel
- **Same file modified by 2+ features** → sequential only, ordered by dependency

### Output

```markdown
## Dispatch Plan
- Batch 1 (parallel): BL-003, BL-005, BL-001
- Estimated total time: ~40 min
- Worktrees: /tmp/wt-daily-haiku, /tmp/wt-network-error-fix, /tmp/wt-settings-debug
```

Proceed automatically — no user confirmation needed.

---

## Wave 2: Build (Autonomous)

### Per feature

1. **Create worktree**: `git worktree add /tmp/wt-<feature> -b story/<feature> develop`
2. **Launch background agent** with:
   - The approved feature plan (`features/<name>.md`)
   - SDD protocol instructions
   - Project adapter (conventions, test commands)
3. **SDD execution**: For each task in execution plan:
   - Write failing test first (RED)
   - Implement minimum code to pass (GREEN)
   - Refactor if needed (REFACTOR)
   - Commit with conventional commit message
4. **Run Definition of Done checklist**
5. **Report completion** to main agent

### Progress tracking

Record to shiki DB: Use the `shiki_save_event` MCP tool with:
```json
{
  "type": "autopilot_task_complete",
  "scope": "<project-slug>",
  "data": {
    "feature": "BL-003",
    "task": "3/7",
    "branch": "story/daily-haiku",
    "worktree": "/tmp/wt-daily-haiku",
    "status": "green"
  }
}
```

### Failure handling

- Test fails after 3 attempts on same task → mark task as blocked, continue with independent tasks, escalate blocked task at Wave 4
- Build fails → check error, fix if obvious, escalate if not

---

## Wave 3: Quality (Autonomous)

### Per completed feature

Run a **single quality pass** that produces both pre-pr results and review package:

#### Step 1: Pre-PR Gates (subset)

- **Gate 1a**: Spec review — map every BR to implementation evidence
- **Gate 1b**: Quality review — @Sensei (CTO), @tech-expert (code quality), @Hanami (if UI)
- **Gate 3**: Test coverage — run full test suite, check coverage
- **Gate 8**: AI slop scan (if release-bound)

#### Step 2: Auto-fix

- Fix all Critical and Important findings automatically
- Re-run affected tests after fixes
- If fix fails after 3 attempts → add to escalation table

#### Step 3: Generate review package

Save to `reviews/<feature>-review.md`:

```markdown
# Review Package: <Feature Name>

## Summary
- **Branch**: story/<feature>
- **PR**: #N (link)
- **Files changed**: N
- **Tests added**: N (N passing, N failing)
- **Coverage delta**: +N%

## @shi Team Analysis

### @Sensei (CTO)
- [findings with severity]

### @tech-expert (Code Quality)
- [findings with severity]

### @Hanami (UX) — if applicable
- [findings with severity]

## Issues Table

| # | Severity | File | Line | Finding | Status |
|---|----------|------|------|---------|--------|
| 1 | Critical | ... | ... | ... | Fixed ✓ |
| 2 | Important | ... | ... | ... | Fixed ✓ |
| 3 | Minor | ... | ... | ... | Open |

## Paginated Code Review

### File 1: `Path/To/File.swift`
```diff
[diff content]
```
**Findings**: #1 (Fixed), #3 (Open — minor naming)

### File 2: ...
[continues for all changed files, ordered by architecture layer]

## Approval Checklist
- [ ] All Critical issues resolved
- [ ] All Important issues resolved
- [ ] Test suite green
- [ ] No AI markers in code
- [ ] Architecture aligns with plan
```

#### Step 4: Create PR

```bash
gh pr create --title "<type>(<scope>): <description>" \
  --body "$(cat reviews/<feature>-review.md | head -50)..." \
  --base develop
```

---

## Wave 4: Present (Interactive)

### Summary table

```markdown
## Autopilot Results

| Feature | Status | Issues | Fixed | Open | PR | Review |
|---------|--------|--------|-------|------|----|--------|
| BL-003: Daily Haiku | ✓ Built | 5 | 4 | 1 minor | #35 | [review](reviews/daily-haiku-review.md) |
| BL-005: NetworkError | ✓ Built | 3 | 3 | 0 | #36 | [review](reviews/network-error-review.md) |
| BL-001: Settings Debug | ✓ Built | 1 | 1 | 0 | #37 | [review](reviews/settings-debug-review.md) |

### Blocked items (if any)
| Feature | Task | Reason | Suggested action |
|---------|------|--------|-----------------|
| — | — | — | — |
```

### Per feature prompt

For each feature:

```
BL-003 (Daily Haiku) — PR #35 ready.
1 minor open issue (naming convention in HaikuRepository).

Options:
  (a) Review now — interactive /review session
  (b) Review later — full review package at reviews/daily-haiku-review.md
  (c) Auto-approve — merge if all Critical/Important are fixed (minor issues tracked)
```

### Rules

- Always show the summary table first
- Present options per feature, accept batch: "a, b, c" or "all b" (defer all)
- If user picks (a), launch interactive `/review` session for that PR
- If user picks (b), confirm the MD path and move to next feature
- If user picks (c), merge and clean up worktree
- After all features handled, clean up: remove worktrees, update backlog status

---

## Context Tracking

Record autopilot events to shiki DB throughout:

| Event | When |
|-------|------|
| `autopilot_started` | Wave 0 start — features list, branch |
| `autopilot_planning_done` | Wave 0 end — questions count per tier |
| `autopilot_decisions_done` | Wave 1/1b end — answers recorded |
| `autopilot_build_started` | Wave 2 start — worktrees, parallel/sequential |
| `autopilot_task_complete` | Each SDD task completion |
| `autopilot_quality_done` | Wave 3 end — issues found/fixed per feature |
| `autopilot_completed` | Wave 4 end — PRs created, user decisions |

---

## Flags

| Flag | Effect |
|------|--------|
| `--yolo` | Skip Tier 2/3 questions (use defaults), auto-proceed through passing gates |
| `--sequential` | Force sequential dispatch even if no file conflicts |
| `--skip-review` | Skip Wave 4 presentation, auto-create PRs but don't prompt for review |
| `--dry-run` | Run Wave 0 only, show plans and questions, don't implement |

---

## Error Recovery

| Scenario | Action |
|----------|--------|
| Subagent crashes during Wave 2 | Check worktree state, resume from last commit |
| Test suite fails completely | Check if it's a build error, fix, retry once, then escalate |
| File conflict detected mid-build | Pause conflicting feature, merge first one, rebase second |
| Shiki DB down | Continue without tracking, log events locally |
| Context compaction during autopilot | Save state to shiki DB, resume from last wave |

---

## Anti-Rationalization

| Temptation | Why it's wrong |
|-----------|---------------|
| "Skip Wave 0, I already know the plan" | Wave 0 catches gaps you haven't thought about. 5 min of planning saves 30 min of rework. |
| "Skip Confidence Gate, they obviously don't conflict" | File conflicts are subtle (shared DI files, shared test helpers). 10 sec check prevents merge hell. |
| "Skip quality pass, I'll review it myself" | @shi team catches things you won't see in a diff. The review MD is free — it costs nothing to generate. |
| "Auto-approve all, they're small changes" | Small changes break things too. At minimum, scan the issues table. |
