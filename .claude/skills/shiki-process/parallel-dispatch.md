# Parallel Feature Dispatch

Dispatch multiple features to run Phases 5b->6->7 autonomously in parallel.
Each feature gets its own git worktree and background agent.
The orchestrator tracks progress. @Daimyo reviews PRs when ready.

## Commands

| Command | Action |
|---------|--------|
| `/dispatch "<feature>"` | Dispatch one feature for autonomous implementation |
| `/dispatch all` | Dispatch all ready features |
| `/dispatch status` | Show dispatch board |
| `/dispatch cancel "<feature>"` | Cancel a running dispatch |

## Prerequisites

A feature must meet ALL conditions before dispatch:
1. Feature file exists at `features/<feature>.md`
2. Phase 5b (Execution Plan) is complete
3. Implementation Readiness Gate has PASSED
4. Feature file contains all sections through Phase 5b

If prerequisites are not met, report what's missing and refuse to dispatch.

## Dispatch Protocol

### Step 1: Create Worktree

```bash
git worktree add -b story/<feature> .claude/worktrees/<feature>-impl develop
```

- Branch from `develop` (latest stable)
- Worktree in `.claude/worktrees/<feature>-impl/`
- Branch name: `story/<feature>`

### Step 2: Launch Background Agent

Dispatch a background Task agent (run_in_background=true) with this prompt structure:

```
You are implementing feature "<feature>" autonomously using the SDD protocol.

Feature file: features/<feature>.md
Working directory: .claude/worktrees/<feature>-impl/

Your mission:
1. Read the feature file completely
2. Read .claude/skills/shiki-process/sdd-protocol.md
3. Read .claude/skills/shiki-process/verification-protocol.md
4. Execute Phase 6 (SDD) -- dispatch subagents per task in the execution plan
5. After all tasks complete, run the Definition of Done checklist
6. If DoD passes, run /pre-pr to create a PR
7. The PR should target develop

Rules:
- Follow TDD strictly (failing test first)
- Verify before claiming completion (run tests, show output)
- Three-failure escalation: after 3 fails, STOP and report
- Do NOT modify files outside your worktree
- Commit after each completed task
```

### Step 3: Track Progress

Maintain a dispatch board in the conversation:

```markdown
## Dispatch Board
| Feature | Branch | Worktree | Status | Tasks | PR |
|---------|--------|----------|--------|-------|----|
| habit-streaks | story/habit-streaks | .claude/worktrees/habit-streaks-impl | Phase 6: 3/8 tasks | ████░░░░ | -- |
| imperfect-days | story/imperfect-days | .claude/worktrees/imperfect-days-impl | Phase 7: /pre-pr | ████████ | -- |
| weekly-review | story/weekly-review | .claude/worktrees/weekly-review-impl | DONE | ████████ | #45 |
```

### Step 4: Report Completion

When a dispatched agent finishes:
1. Check its output (TaskOutput)
2. Verify PR was created (`gh pr list --head story/<feature>`)
3. Update dispatch board
4. Notify user: "Feature '<feature>' is ready for review: PR #<N>"

## Dispatch All (`/dispatch all`)

1. Scan `features/` for all feature files
2. Filter to features at Phase 5b+ with readiness gate PASSED
3. Show list and ask for confirmation
4. Dispatch each in parallel (Step 1-2 for each)
5. Show dispatch board

## Status (`/dispatch status`)

1. Check all active worktrees: `git worktree list`
2. For each dispatch, check agent status
3. Check for PRs: `gh pr list --json number,title,headRefName`
4. Update and display dispatch board

## Cancel (`/dispatch cancel "<feature>"`)

1. Stop the background agent (TaskStop)
2. Optionally remove the worktree: `git worktree remove .claude/worktrees/<feature>-impl`
3. Update dispatch board

## Constraints

- Maximum 3 concurrent dispatches (context + CPU limit)
- Features MUST NOT have overlapping file changes (check Phase 5 architecture for conflicts)
- If two features modify the same file, dispatch sequentially, not in parallel
- Each dispatch operates in its own worktree -- no cross-contamination

## Conflict Detection

Before dispatching multiple features, check for file overlaps:
1. For each feature, extract the file list from Phase 5 architecture
2. Build a conflict matrix
3. If any file appears in 2+ features: WARN and recommend sequential dispatch for those features

```markdown
## Conflict Check
| File | Features | Action |
|------|----------|--------|
| HabitService.ts | habit-streaks, imperfect-days | CONFLICT -- dispatch sequentially |
| WeeklyReview.ts | weekly-review | OK -- no overlap |
```

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "The feature is almost at Phase 5, I'll dispatch it anyway" | Prerequisites are binary. Phase 5b complete + readiness PASS or no dispatch. |
| "These features might conflict but probably won't" | Check the file lists. "Probably" is not evidence. Run conflict detection. |
| "I'll dispatch 5 features at once for maximum throughput" | Max 3 concurrent. More causes context exhaustion and quality degradation. |
| "The agent can figure out the branch and worktree itself" | Provide exact paths. Ambiguity causes agents to work in wrong directories. |
| "I'll skip the readiness gate, the plan looks fine" | The readiness gate takes 30 seconds. Skipping it costs hours when a subagent hits a wall. |
| "One feature finished, I'll clean up the worktree later" | Clean up immediately. Stale worktrees cause confusion and disk bloat. |
