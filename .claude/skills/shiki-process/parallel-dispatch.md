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

## Worktree Isolation Protocol

**MANDATORY for ALL parallel agent work.** Without isolation, agents share one working directory and clobber each other's git state.

### Why This Exists

When 2+ agents share the same repo directory:
- Agent A runs `git checkout -b story/feature-a` → working tree on branch A
- Agent B runs `git checkout -b story/feature-b` → working tree switches to branch B
- Agent A edits files → changes land on branch B, not A
- Result: mixed commits, lost work, hours of cleanup

**Fix: each agent gets its own worktree (isolated copy of the repo).**

### Worktree Location Rules

| Location | Use case | Notes |
|----------|----------|-------|
| `/tmp/wt-<feature>/` | Agent implementation work | Fast SSD, auto-cleaned on reboot, no symlink issues |
| `.claude/worktrees/<name>/` | Long-lived side projects (epic branches) | Persists across sessions |
| **NEVER** the main repo dir | — | Reserved for orchestrator + manual work |

**Why `/tmp/` over `.claude/worktrees/`:**
- Claude Code's `isolation: "worktree"` Agent parameter fails when CWD is a symlink (e.g. `.wsx/` paths)
- `/tmp/` worktrees are disposable — merge the branch, delete the worktree
- No accumulation of stale directories (reboot cleans them)

### Agent Prompt Rules

Every agent prompt MUST include:

```
## CRITICAL: Working Directory
Your working directory is an ISOLATED git worktree at `/tmp/wt-<feature>`.
Branch: `story/<feature>` (already checked out from develop).
ALL file operations MUST use paths starting with `/tmp/wt-<feature>/`.
Do NOT touch the main repo at <main-repo-path> — that's the orchestrator's worktree.
```

**Never rely on agents to create their own branches.** The orchestrator creates the worktree + branch BEFORE launching the agent.

### Lifecycle

```
CREATE → DISPATCH → MONITOR → REVIEW → MERGE → CLEANUP
```

1. **CREATE**: `git worktree add /tmp/wt-<feature> -b story/<feature> develop`
2. **DISPATCH**: Launch agent with explicit `/tmp/wt-<feature>` path
3. **MONITOR**: Check agent progress, handle blockers
4. **REVIEW**: `/review <PR#>` or manual review
5. **MERGE**: `git merge --no-ff story/<feature>` into develop
6. **CLEANUP**: `git worktree remove /tmp/wt-<feature> && git branch -d story/<feature>`

### Stale Worktree Cleanup

Run periodically (or in `/context`):

```bash
# List all worktrees
git worktree list

# Remove stale agent worktrees (no uncommitted changes)
git worktree remove /tmp/wt-<feature>

# Prune references to deleted worktrees
git worktree prune
```

**Rule**: clean up immediately after PR merge. Stale worktrees cause confusion, disk bloat, and branch lock conflicts.

### Cross-Project Worktrees (Shiki ecosystem)

For projects managed via Shiki (`shiki/projects/<name>/`):
- Agent works in `/tmp/wt-<feature>` (worktree of the sub-project)
- Orchestrator reviews the diff
- On approval: push the branch, create PR targeting the sub-project's `develop`
- The Shiki project clone stays read-only during agent work

---

## Dispatch Protocol

### Step 1: Create Worktree

```bash
git worktree add /tmp/wt-<feature> -b story/<feature> develop
```

- Branch from `develop` (latest stable)
- Worktree in `/tmp/wt-<feature>/`
- Branch name: `story/<feature>`
- Verify: `ls /tmp/wt-<feature>/` shows full repo

### Step 2: Launch Background Agent

Dispatch a background agent (run_in_background=true) with this prompt structure:

```
You are implementing feature "<feature>" autonomously using the SDD protocol.

## CRITICAL: Working Directory
Your working directory is an ISOLATED git worktree at `/tmp/wt-<feature>`.
Branch: `story/<feature>` (already checked out from develop).
ALL file operations MUST use paths starting with `/tmp/wt-<feature>/`.
Do NOT touch the main repo.

Feature file: features/<feature>.md (read-only reference)

Your mission:
1. Read the feature file completely
2. Read .claude/skills/shiki-process/sdd-protocol.md (from main repo, read-only)
3. Read .claude/skills/shiki-process/verification-protocol.md (from main repo, read-only)
4. Execute Phase 6 (SDD) -- implement each task in the execution plan
5. After all tasks complete, run the Definition of Done checklist
6. Commit all changes in your worktree
7. Return summary: files created/modified, tests pass/fail, blockers

Rules:
- Follow TDD strictly (failing test first)
- Verify before claiming completion (run tests, show output)
- Three-failure escalation: after 3 fails, STOP and report
- Do NOT modify files outside your worktree
- Commit after each completed task: cd /tmp/wt-<feature> && git add -A && git commit -m "..."
- Build verify: cd /tmp/wt-<feature> && <build-command>
```

### Step 3: Track Progress

Maintain a dispatch board in the conversation:

```markdown
## Dispatch Board
| Feature | Branch | Worktree | Status | Tasks | PR |
|---------|--------|----------|--------|-------|----|
| habit-streaks | story/habit-streaks | /tmp/wt-habit-streaks | Phase 6: 3/8 tasks | ████░░░░ | -- |
| imperfect-days | story/imperfect-days | /tmp/wt-imperfect-days | Phase 7: /pre-pr | ████████ | -- |
| weekly-review | story/weekly-review | /tmp/wt-weekly-review | DONE | ████████ | #45 |
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
2. Optionally remove the worktree: `git worktree remove /tmp/wt-<feature>`
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
| HabitService.swift | habit-streaks, imperfect-days | CONFLICT -- dispatch sequentially |
| WeeklyReview.swift | weekly-review | OK -- no overlap |
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
