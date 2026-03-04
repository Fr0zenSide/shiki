Run the /dispatch pipeline for autonomous parallel feature implementation.

Load the shiki-process skill from `.claude/skills/shiki-process/` for full context:
- `parallel-dispatch.md` — Parallel feature dispatch protocol
- `sdd-protocol.md` — SDD protocol for Phase 6
- `feature-pipeline.md` — Feature pipeline phases

## Arguments

Parse the argument to determine the action:
- `"<feature>"` — Dispatch a single feature (must be at Phase 5 or later)
- `all` — Dispatch all features ready for implementation
- `status` — Show status of all dispatched features
- `cancel "<feature>"` — Cancel a running dispatch

## Execution

1. Read `parallel-dispatch.md` for the full dispatch protocol
2. Verify feature is ready (Phase 5b complete, readiness gate passed)
3. Create worktree, launch background agent
4. Track progress, report when PRs are ready
