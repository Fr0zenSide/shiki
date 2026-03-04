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

Use the TaskList tool to check task statuses, and check background shells via /tasks.
