Resume failed pipeline executions or scan stuck sub-agents.

## Arguments

Parse the argument `$ARGUMENTS` to determine the action:
- No argument — Find the most recent failed pipeline run and offer to resume
- `<run-id>` — Resume a specific pipeline run by ID
- `status` — Show recent pipeline runs with their status
- `all` — Scan both failed pipelines AND stuck sub-agents
- `--from <phase>` — Override resume point (restart from specific phase)

## Execution

### Step 1: Check for failed pipelines

Query the Shiki backend for recent failed runs:
```bash
curl -s http://localhost:3900/api/pipelines?status=failed&limit=5
```

If the backend is unreachable, skip to **Legacy Fallback** below.

### Step 2: Show failed run details

For each failed run, display:
- Pipeline type, project, started_at
- Last completed phase and failed phase
- Error message
- Checkpoint count (phases completed before failure)

To get full details:
```bash
curl -s http://localhost:3900/api/pipelines/<run-id>
curl -s http://localhost:3900/api/pipelines/<run-id>/checkpoints
```

### Step 3: Evaluate routing rules

Check if there's an auto-recovery rule for the failed phase:
```bash
curl -s -X POST http://localhost:3900/api/pipelines/<run-id>/route \
  -H "Content-Type: application/json" \
  -d '{"failedPhase":"<phase>"}'
```

Possible actions:
- **auto_fix** — Attempt to fix the issue that caused the failure, then retry the phase
- **retry_phase** — Simply re-run the failed phase with the same state
- **escalate** — Stop and ask @Daimyo what to do (max retries exhausted or task too complex)

Show the recommended action and ask user to confirm.

### Step 4: Resume the pipeline

```bash
curl -s -X POST http://localhost:3900/api/pipelines/<run-id>/resume \
  -H "Content-Type: application/json" \
  -d '{"fromPhase":"<phase>","stateOverrides":{}}'
```

The response includes:
- `newRunId` — The new pipeline run (linked to the failed one via `resumed_from`)
- `resumeFromPhase` — Which phase to start from
- `resumeFromIndex` — Phase index for skip logic
- `state` — Accumulated state from all successful phases

Then load the appropriate pipeline command (`/quick`, `/md-feature`, `/pre-pr`, etc.) and execute from the resume phase, skipping all phases with index < `resumeFromIndex`.

### Step 5: Continue checkpointing

The resumed pipeline continues checkpointing as normal. If it fails again, `/retry` can resume again (the system tracks retries across the chain).

## Status View

When invoked with `status`:
```bash
curl -s http://localhost:3900/api/pipelines?limit=10
```

Display as a table:
```
| Run ID (short) | Type       | Status    | Phase              | Started     |
|----------------|------------|-----------|--------------------|-------------|
| a1b2c3d4       | pre-pr     | failed    | gate_3_test        | 2 hours ago |
| e5f6g7h8       | md-feature | completed | phase_7_quality    | yesterday   |
| i9j0k1l2       | quick      | running   | step_2_impl        | 5 min ago   |
```

## Legacy Fallback

If no pipeline runs are found or backend is unreachable, fall back to scanning sub-agents:

Scan all running sub-agents and background processes.
Check for any that are:
- Stuck (no progress for extended time)
- Waiting for permission
- Hit a network error
- Require user attention

For each stuck/failed process:
1. Diagnose the issue
2. If recoverable: relaunch automatically
3. If not recoverable: report to user with the error and ask what to do

Use the TaskList tool to check task statuses, and check background shells.
