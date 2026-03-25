#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# shikki-idle.sh — "What's next?" notification via ntfy.sh
#
# Claude Code Stop hook that fires when Claude finishes work
# and is waiting for user input. Sends a push notification
# so you know it's your turn.
#
# Config: ~/.config/shikki-notify/config
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shikki-notify-lib.sh"

CONFIG_DIR="$HOME/.config/shikki-notify"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="$CONFIG_DIR/approval.log"
IDLE_STATE_FILE="$CONFIG_DIR/.last_stop_ts"

# ── Load config ──────────────────────────────────────────────

if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

source "$CONFIG_FILE"

if [[ -z "${NTFY_TOPIC:-}" ]]; then
  exit 0
fi

NTFY_SERVER="${NTFY_SERVER:-http://localhost:2586}"
NTFY_TOKEN="${NTFY_TOKEN:-}"
IDLE_DELAY="${IDLE_DELAY:-120}" # seconds before sending notification

# ── Read hook input from stdin ───────────────────────────────

INPUT=$(cat)

# Extract stop reason
STOP_REASON=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('stop_hook_reason', d.get('reason', 'end_turn')))
" 2>/dev/null || echo "end_turn")

# Only notify on end_turn (Claude finished and is waiting for input)
# Skip for interrupts or errors
if [[ "$STOP_REASON" != "end_turn" ]]; then
  exit 0
fi

# ── Debounce: don't spam notifications ───────────────────────

NOW=$(date +%s)
if [[ -f "$IDLE_STATE_FILE" ]]; then
  LAST_STOP=$(cat "$IDLE_STATE_FILE" 2>/dev/null || echo "0")
  ELAPSED=$((NOW - LAST_STOP))
  if [[ $ELAPSED -lt $IDLE_DELAY ]]; then
    # Too soon since last stop — skip
    exit 0
  fi
fi
echo "$NOW" > "$IDLE_STATE_FILE"

# ── Build workspace context tag (from shared lib) ────────────

WORKSPACE_TAG=$(shikki_workspace_tag)

# ── Send "What's next?" notification ─────────────────────────

AUTH_HEADER=""
if [[ -n "$NTFY_TOKEN" ]]; then
  AUTH_HEADER="Authorization: Bearer $NTFY_TOKEN"
fi

PAYLOAD=$(
  SHIKKI_TOPIC="$NTFY_TOPIC" \
  SHIKKI_TITLE="Shikki${WORKSPACE_TAG}: Your turn 👋" \
  python3 -c '
import json, os
payload = {
    "topic": os.environ["SHIKKI_TOPIC"],
    "title": os.environ["SHIKKI_TITLE"],
    "message": "Claude finished and is waiting for your next instruction.",
    "tags": ["wave"],
    "priority": 3
}
print(json.dumps(payload))
'
)

CURL_ARGS=(-sf -X POST "$NTFY_SERVER" -H "Content-Type: application/json" -d "$PAYLOAD")
if [[ -n "$AUTH_HEADER" ]]; then
  CURL_ARGS+=(-H "$AUTH_HEADER")
fi

curl "${CURL_ARGS[@]}" >/dev/null 2>&1 || true

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | idle-notify | stop | waiting for input" >> "$LOG_FILE" 2>/dev/null || true
