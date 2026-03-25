# Subagent-Driven Development (SDD) Protocol

Defines how Phase 6 (Implementation) runs autonomously using fresh subagents per task.
The orchestrator dispatches, tracks, and escalates. It never writes code.

## Overview

SDD dispatches a fresh subagent (via Claude Code's Task tool) for each implementation task from the Phase 5b execution plan. Each subagent receives the feature file path and exactly one task. After implementation, a spec reviewer subagent checks BR compliance, then a code quality reviewer subagent checks standards. The orchestrator tracks progress but does NOT implement.

Why fresh subagents? Context accumulation causes drift. A subagent that implemented Task 3 carries assumptions that corrupt Task 4. Fresh context per task is the entire point of SDD.

## Subagent Roles

| Role | Purpose | Dispatched via |
|------|---------|----------------|
| IMPLEMENTER | Write failing test, implement, make test pass, commit | Task tool (subagent_type=general-purpose) |
| SPEC REVIEWER | Verify implementation satisfies BR-XX rules, detect scope creep | Task tool (subagent_type=general-purpose) |
| CODE QUALITY REVIEWER | Check architecture, concurrency, naming, test quality | Task tool (subagent_type=general-purpose) |
| FINAL REVIEWER | Review entire implementation across all tasks for integration issues | Task tool (subagent_type=general-purpose) |

## Workflow

```
1. Load execution plan (from Phase 5b)
2. For each task in order:
   a. Dispatch IMPLEMENTER
   b. Dispatch SPEC REVIEWER
   c. If CHANGES_REQUIRED -> fix loop (max 3)
   d. Dispatch CODE QUALITY REVIEWER
   e. If Critical items -> fix loop (max 3)
   f. Mark task complete
3. After all tasks: dispatch FINAL REVIEWER
4. Report: all tasks done, ready for Phase 7
```

### Step 2a: Dispatch IMPLEMENTER

Prompt template for the implementer subagent:

```
You are implementing Task {N} of feature "{feature_name}".

Read the feature file: {feature_file_path}
Focus on the Execution Plan > Task {N} section.

Your job:
1. Read the feature file to understand context
2. Write the failing test FIRST (from the test signature in the task)
3. Run the test command — confirm it FAILS (red)
4. Implement the production code described in the task
5. Run the test command — confirm it PASSES (green)
6. Refactor if needed (keep tests green)
7. Commit with message: "feat({feature}): task {N} — {title}"

Files to create/modify: {file_list}
Test to write: {test_signature}
Test command: {test_command}
Expected BR coverage: {br_list}

Do NOT implement anything beyond what this task describes.
Do NOT modify files not listed above unless strictly necessary for compilation.
If you have questions, re-read the feature file — the answer is there.
```

### Step 2b: Dispatch SPEC REVIEWER

Prompt template for the spec reviewer subagent:

```
You are reviewing Task {N} of feature "{feature_name}" for spec compliance.

IMPORTANT: The implementer finished suspiciously quickly. Their report may be
incomplete. Read the actual code.

1. Read the feature file: {feature_file_path}
2. Read the diff: run `git diff HEAD~1`
3. Read the Business Rules section, specifically: {br_list}

Check:
- Does the implementation satisfy every BR-XX rule referenced in this task?
- For each BR, identify the specific code/test that satisfies it
- Was anything implemented that WASN'T requested? (scope creep)
- Were any files modified that weren't in the task's file list?
- Does the test actually verify the business rule, or just verify the code runs?

Verdict: PASS or CHANGES_REQUIRED
If CHANGES_REQUIRED, list specific items:
- What BR is not satisfied and why
- What was added that shouldn't be there
- What test is missing or insufficient
```

### Step 2c: Fix Loop (Spec)

If the spec reviewer returns CHANGES_REQUIRED:

1. Dispatch a new IMPLEMENTER subagent with the original task PLUS the reviewer feedback
2. Re-dispatch the SPEC REVIEWER
3. Maximum 3 loops. If still failing after 3, trigger Three-Failure Escalation (see below)

### Step 2d: Dispatch CODE QUALITY REVIEWER

Prompt template for the code quality reviewer subagent:

```
You are reviewing Task {N} of feature "{feature_name}" for code quality.

1. Read the diff: run `git diff HEAD~1`
2. Read the project conventions from the project adapter (if available)

Check against checklists/code-quality.md and checklists/cto-review.md:
- Architecture compliance (correct layer placement, dependency direction)
- Concurrency safety (no data races, correct isolation patterns)
- Naming conventions (types, functions, files)
- Test quality (meaningful assertions, edge cases, independence)
- No unsafe patterns in production code (per project adapter)
- No debug output in production code

Severity levels:
- Critical: Must fix before proceeding (data race, architecture violation, missing test)
- Important: Should fix (naming, missing doc comment, suboptimal pattern)
- Minor: Note for later (style preference, micro-optimization)

Verdict: PASS or CHANGES_REQUIRED with severity per item
```

### Step 2e: Fix Loop (Quality)

If the code quality reviewer returns Critical items:

1. Dispatch a new IMPLEMENTER subagent with the original task PLUS the Critical items to fix
2. Re-dispatch the CODE QUALITY REVIEWER
3. Important items: log them but proceed
4. Minor items: log them, do not dispatch a fix
5. Maximum 3 loops for Critical fixes. If still failing, trigger Three-Failure Escalation

### Step 3: Dispatch FINAL REVIEWER

After all tasks are complete, dispatch one final review subagent:

```
You are performing a final integration review of feature "{feature_name}".

1. Read the feature file: {feature_file_path}
2. Read the full diff from feature branch start: run `git diff {base_branch}...HEAD`
3. Read the Business Rules section (all BR-XX rules)

Check:
- Cross-task integration: do the pieces work together?
- No conflicting patterns between tasks (e.g., two different error handling approaches)
- Full BR coverage: every BR-XX maps to at least one test
- No duplicate code across task implementations
- DI registrations are complete and consistent
- Router/coordinator wiring is correct (if navigation involved)
- No leftover TODO/FIXME without context

Verdict: PASS or CHANGES_REQUIRED with specific items
If CHANGES_REQUIRED, identify which task(s) need rework and what specifically.
```

## Anti-Rationalization Table

The orchestrator will encounter these thoughts during execution. Each one is wrong.

| Thought | Response |
|---------|----------|
| "This task is trivial, I'll skip the spec review" | Every task gets reviewed. Trivial tasks have trivial reviews. The cost is 30 seconds. The cost of a missed spec violation is a rework cycle. |
| "I can implement 3 tasks at once for efficiency" | One task at a time. Fresh context per task is the entire point. Batching reintroduces the context drift SDD exists to prevent. |
| "The spec reviewer agreed, skip quality review" | Spec and quality are orthogonal. Spec checks intent (does it match BR-XX). Quality checks craft (is it well-built). Both are mandatory. |
| "I already know the fix from the reviewer feedback" | Still dispatch the implementer subagent. You are the orchestrator, not the implementer. Writing code yourself defeats the fresh-context guarantee. |
| "The tests pass, so the implementation is correct" | Tests verify behavior, not spec compliance. A test can pass while testing the wrong thing. The spec reviewer verifies intent. |
| "3 review loops failed, let me try a 4th" | STOP. 3 failures means the approach is wrong, not the execution. Escalate to @Daimyo via Three-Failure Escalation. A 4th attempt with the same architecture will produce a 4th failure. |
| "I'll just do a quick fix directly instead of dispatching" | The orchestrator NEVER writes code. Not one line. Not a "quick" fix. Dispatch or escalate. The moment you write code, you carry context that corrupts future dispatch prompts. |
| "This is the last task, I'll skip the final review" | The final review catches cross-task integration issues that no single-task review can see. It is the most important review, not the most skippable. |
| "The subagent is taking too long, I'll intervene" | Wait. If the subagent is genuinely stuck (no progress after 5 minutes), dispatch a fresh one with the same prompt. Do not "help" by adding context — that defeats isolation. |
| "The reviewer flagged an Important item but I think it's Minor" | You are not the reviewer. Log the item at the severity the reviewer assigned. The reviewer read the code; you read the report. |
| "I'll parallelize the spec and quality reviews" | No. Quality review depends on spec review passing. If spec fails and triggers a fix, the quality review ran on stale code. Sequential is correct. |
| "The feature file is long, I'll summarize it for the subagent" | Give the subagent the full file path. Let it read what it needs. Your summary will omit the one detail that matters for this task. |

## Verification Protocol

Before marking Phase 6 complete, the orchestrator MUST verify all of the following. No exceptions.

### 1. Full Test Suite

Run the project's test command (from project adapter):
```bash
{test_command} 2>&1
```

Capture the FULL output. Parse for exact test count. The count must match or exceed the number of test signatures defined in Phase 4.

### 2. BR Coverage Map

For every BR-XX in the Business Rules section, identify at least one passing test that exercises it. Format:

```
BR-01 -> test_imperfectDays_maxFourPerMonth()        PASS
BR-02 -> test_imperfectDays_streakPauses()            PASS
BR-03 -> test_imperfectDays_resetOnFirstOfMonth()     PASS
```

If any BR-XX has no corresponding passing test, Phase 6 is NOT complete.

### 3. No Unsafe Patterns in Production Code

Check for project-specific unsafe patterns (defined in project adapter). Common checks:
- No force unwraps (`!`) in production code (Swift)
- No `any` type assertions (TypeScript)
- No `eval()` or `exec()` (JavaScript/Python)

### 4. No Debug Output in Production Code

Check for debug statements left in production code (e.g., `print()`, `console.log()`, `debugPrint()`).

### 5. Final Check

If any verification step fails, Phase 6 is NOT complete. Dispatch an implementer subagent to fix the issue, then re-verify.

## Three-Failure Escalation

After 3 consecutive failed fix attempts on the same task (spec or quality review loop):

### 1. STOP

Halt all subagent dispatch immediately. Do not attempt a 4th fix.

### 2. Summarize

Document what was tried:

```markdown
### Escalation: Task {N} — {title}

**Attempts**:
1. {what was tried} -> {why it failed}
2. {what was tried} -> {why it failed}
3. {what was tried} -> {why it failed}

**Pattern**: {what these failures have in common}
**Hypothesis**: {why the approach may be fundamentally wrong}
```

### 3. Present to @Daimyo

Ask the user to decide:

> Task {N} has failed 3 consecutive review cycles. The pattern suggests {hypothesis}.
>
> Options:
> - **(a) Redesign**: Rethink the approach for this task. May require updating Phase 5/5b.
> - **(b) Adversarial review**: Invoke @Ronin to challenge the assumptions. The current approach may be fighting the architecture.
> - **(c) Skip and track**: Mark as tech debt. Create an issue. Continue with remaining tasks.

### 4. Wait

Do NOT proceed until @Daimyo responds. The orchestrator does not have authority to skip a failed task unilaterally.

## Orchestrator State Tracking

The orchestrator maintains a progress table in the feature file's Implementation Log section:

```markdown
### SDD Progress

| Task | Implementer | Spec Review | Quality Review | Status |
|------|-------------|-------------|----------------|--------|
| 1    | DONE        | PASS        | PASS           | COMPLETE |
| 2    | DONE        | PASS (2nd)  | PASS           | COMPLETE |
| 3    | DONE        | PASS        | CHANGES_REQ    | IN PROGRESS |
| 4    | -           | -           | -              | PENDING |

Final Review: PENDING
```

Update this table after each subagent completes. This is the single source of truth for Phase 6 progress.
