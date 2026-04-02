---
name: tmux checkpoint recovery
description: Auto-save tmux layout on Claude Code Stop events for crash recovery — never lose window layout again
type: feedback
---

Always have a tmux layout checkpoint available for crash recovery.

**Why:** On 2026-04-02, a `[server exited unexpectedly]` crash lost the entire 10-window tmux layout. ShikiDB had no session state saved. The user had to reconstruct from a screenshot.

**How to apply:**
- `scripts/tmux-checkpoint.sh shiki save` — save current layout (runs automatically on every Stop hook)
- `scripts/tmux-checkpoint.sh shiki restore` — restore layout after crash
- `scripts/tmux-checkpoint.sh shiki status` — show last checkpoint
- Checkpoint at `~/.shikki/tmux-checkpoint.json`, history rotates last 5 at `~/.shikki/tmux-checkpoint-history/`
- After context compaction, avoid sending massive multi-topic messages — break into focused questions
- The Stop hook at `~/.claude/hooks/tmux-checkpoint-on-stop.sh` fires automatically
