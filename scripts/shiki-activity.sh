#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# shiki-activity.sh — Reset idle debounce on user activity
#
# Claude Code UserPromptSubmit hook. When you type a prompt,
# this resets the idle timer so "Your turn" notifications
# won't fire — you're already active.
#
# Config: ~/.config/shiki-notify/config
# ─────────────────────────────────────────────────────────────

IDLE_STATE_FILE="$HOME/.config/shiki-notify/.last_stop_ts"

# Reset debounce: write current timestamp
# shiki-idle.sh will see this as recent activity and skip notification
date +%s > "$IDLE_STATE_FILE" 2>/dev/null || true
