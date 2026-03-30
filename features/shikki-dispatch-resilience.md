# Shikki Dispatch Resilience

> Preventing context explosion, worktree traps, and session death during multi-agent dispatch.

**Status**: spec
**Priority**: P0
**Blocks**: All future multi-wave dispatches
**Author**: @Sensei + @Katana
**Date**: 2026-03-30

---

## Problem Statement

During the v0.3.0-pre dispatch (2026-03-29), the orchestrator session died at the Wave 1 → Wave 2+3 handoff. Three compounding failure modes:

1. **Context Saturation** — 6 parallel agents each return 2-5KB of results into the orchestrator's context window. With status tables, DB events, worktree management, and agent result processing, the orchestrator burns 50%+ of its context on bookkeeping before it can dispatch the next wave.

2. **Worktree CWD Trap** — The orchestrator attempted `git worktree remove` while either itself or an agent process was still CWD'd inside the worktree. Result: `fatal: Unable to read current working directory: No such file or directory`. Unrecoverable.

3. **Compaction in Dead CWD** — After the crash, Claude Code compacted context while CWD was inside a deleted worktree (`agent-aa8b7e81`). The resumed session couldn't access any files, couldn't read specs, couldn't recover.

**Impact**: Wave 0 (536 tests) + Wave 1 (453 tests) delivered, but Waves 2+3 (7 specs) never launched. ~30 minutes of orchestrator time wasted. Manual session restart required.

---

## Root Cause Analysis

### Why context explodes

```
Orchestrator context budget: ~200K tokens (effective, after system prompt + memory)

Per-agent overhead in orchestrator:
  - Agent launch prompt:           ~500 tokens
  - Agent result (when complete):  ~2,000-5,000 tokens
  - Status tracking (tables, DB):  ~300 tokens per update
  - Background task notifications: ~200 tokens each

6 agents × ~4,000 tokens avg = 24,000 tokens just for results
+ 6 launches × 500 = 3,000 tokens
+ Status updates (12+ per wave): 3,600 tokens
+ Wave summary tables: 2,000 tokens
= ~33,000 tokens per wave of overhead

After 2 waves: ~66,000 tokens of bookkeeping
+ Spec reading, user messages, DB events: ~40,000 tokens
= ~106,000 tokens consumed before Wave 2 can launch
```

The orchestrator has no context budget awareness. It accumulates results verbatim, prints status tables after every agent completion, and never summarizes or discards.

### Why worktree cleanup races

```
Timeline:
  T+0:   All 6 agents complete
  T+1:   Orchestrator starts pruning worktrees
  T+2:   Bash runs `git worktree remove` in a loop
  T+2.1: One worktree is the orchestrator's own CWD (or a bg task's)
  T+2.2: fatal: Unable to read current working directory
  T+2.3: Session state corrupted
```

No CWD guard. No check that the current process isn't inside the worktree being removed.

### Why compaction fails to recover

Claude Code's compaction preserves the conversation summary but inherits the CWD from the crashed state. If CWD was a deleted worktree, the resumed session starts in a nonexistent directory with no way to navigate back.

---

## Solution: 4-Layer Dispatch Resilience

### Layer 1: Context Budget Tracking

**Principle**: The orchestrator tracks its own context consumption and acts before hitting limits.

**Implementation in dispatch skill**:

```
DISPATCH_CONTEXT_BUDGET:
  max_agents_per_wave: 4          # down from 6
  result_summary_max: 500 tokens  # summarize, don't dump
  wave_handoff_checkpoint: true   # save state to DB between waves
  compaction_threshold: 75%       # trigger proactive save at 75%
```

**Rules for the dispatch skill**:
1. Each agent result gets a **3-line summary** (branch, test count, status). No verbose output.
2. After each wave completes, **save full state to ShikiDB** before launching next wave.
3. If context is above 75% after a wave, **force compaction** with DB checkpoint first.
4. Maximum 4 agents per wave (not 6). If a wave has 6+ specs, split into sub-waves.

### Layer 2: Worktree Safety Guards

**Principle**: Never remove a worktree you might be standing in.

**Implementation**:

```bash
# BEFORE any worktree removal:
safe_worktree_remove() {
  local wt_path="$1"
  local current_cwd=$(pwd)

  # Guard 1: Never remove if we're inside it
  if [[ "$current_cwd" == "$wt_path"* ]]; then
    cd /Users/jeoffrey/Documents/Workspaces/shiki  # return to repo root
  fi

  # Guard 2: Check no background processes are CWD'd there
  # (lsof is expensive, so just cd to root first as prevention)

  # Guard 3: Always cd to repo root before any worktree operation
  git -C /Users/jeoffrey/Documents/Workspaces/shiki worktree remove "$wt_path" --force 2>/dev/null
}
```

**Add to dispatch skill**:
- Every worktree removal command MUST use absolute path with `-C <repo_root>`
- Every cleanup phase MUST start with `cd <repo_root>`
- Never chain worktree removals in a single bash command without CWD reset

### Layer 3: Wave Checkpoint Protocol

**Principle**: Every wave boundary is a recovery point.

**Between waves**:
1. Save to ShikiDB: `dispatch_wave_checkpoint` event with:
   - Wave number, specs completed, branches, test counts
   - Next wave plan (spec names, branches, dependencies)
   - Current worktree inventory
2. Save locally: `.claude/dispatch-state.json` with same data
3. On session resume: Read checkpoint → skip completed waves → resume from last incomplete

**Checkpoint schema**:
```json
{
  "session_id": "v0.3.0-pre-dispatch",
  "timestamp": "2026-03-29T...",
  "waves_completed": [0, 1],
  "wave_results": {
    "0": { "specs": 6, "tests": 536, "branches": [...] },
    "1": { "specs": 5, "tests": 453, "branches": [...], "failed": ["brainy-vision"] }
  },
  "next_wave": {
    "number": 2,
    "specs": ["s3-spec-syntax", "augmented-tui", "enterprise-safety", "answer-engine"],
    "dependencies_met": true
  },
  "worktrees": []
}
```

### Layer 4: Graceful Degradation

**Principle**: When things go wrong, fail safe — don't fail dead.

1. **Agent timeout**: If an agent hasn't produced a commit in 10 minutes, mark it as stalled (not failed). Retry once, then skip and continue wave.
2. **Rate limit awareness**: If any agent returns a rate limit error, immediately pause all other agents. Wait for reset. Resume.
3. **Partial wave completion**: If 4/6 agents complete but 2 fail, the wave is "partial". Log failures, continue to next wave with dependency check. Don't block everything.
4. **CWD recovery**: Every bash command in the dispatch skill starts with a CWD assertion: `cd /Users/jeoffrey/Documents/Workspaces/shiki && ...`

---

## Implementation Plan

### Phase 1: Dispatch Skill Hardening (immediate)
- Add CWD guards to all worktree operations in dispatch skill
- Add 3-line result summarization rule
- Add max 4 agents per wave rule
- Add checkpoint save between waves

### Phase 2: Checkpoint System
- Create `.claude/dispatch-state.json` schema
- Add ShikiDB `dispatch_wave_checkpoint` event type
- Add resume-from-checkpoint logic to `/retry` skill

### Phase 3: Context Budget (ShikkiCore integration)
- ContextBudgetTracker in ShikkiCore
- Proactive compaction trigger at 75%
- DB-first recovery on session resume

---

## Acceptance Criteria

- [ ] Dispatch of 8+ specs across 2+ waves completes without session death
- [ ] Worktree cleanup never crashes even if CWD is inside a worktree
- [ ] Session resume after compaction recovers dispatch state from DB/checkpoint
- [ ] Each wave result uses <=500 tokens in orchestrator context
- [ ] Rate limit on one agent pauses the batch, doesn't kill the session

---

## @shi Mini-Challenge

1. **@Ronin**: What happens if the checkpoint file itself is corrupted mid-write? Do we need atomic writes?
2. **@Katana**: The CWD guard uses `cd` — but what if the repo root itself is deleted (e.g., during a git clean)?
3. **@Sensei**: Should the context budget be static (4 agents) or dynamic based on spec complexity?
