#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# shiki-approval.sh — Remote approval for Claude Code via ntfy.sh
#
# Claude Code PermissionRequest hook that sends push notifications
# to your phone/watch and waits for Approve/Deny response.
#
# Config: ~/.config/shiki-notify/config
# Setup: ./shiki notify setup
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shiki-notify-lib.sh"

CONFIG_DIR="$HOME/.config/shiki-notify"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="$CONFIG_DIR/approval.log"

# ── Load config ──────────────────────────────────────────────

if [[ ! -f "$CONFIG_FILE" ]]; then
  # No config = fall back to CLI prompt (don't block Claude Code)
  echo '{}' # empty output = no decision = fall back to interactive
  exit 0
fi

source "$CONFIG_FILE"

# Required: NTFY_TOPIC
if [[ -z "${NTFY_TOPIC:-}" ]]; then
  echo '{}' && exit 0
fi

NTFY_SERVER="${NTFY_SERVER:-http://localhost:2586}"
NTFY_TIMEOUT="${NTFY_TIMEOUT:-120}"
NTFY_TOKEN="${NTFY_TOKEN:-}"
RESPONSE_TOPIC="${NTFY_TOPIC}-response"

# ── Read hook input from stdin ───────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
TOOL_INPUT_RAW=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
if isinstance(ti, dict):
    cmd = ti.get('command', '')
    fp = ti.get('file_path', '')
    pattern = ti.get('pattern', '')
    if cmd:
        s = cmd[:200] + ('...' if len(cmd) > 200 else '')
        print(s)
    elif fp:
        print(fp)
    elif pattern:
        print(pattern)
    else:
        print(json.dumps(ti)[:200])
else:
    print(str(ti)[:200])
" 2>/dev/null || echo "")

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")

# ── Logging helper ───────────────────────────────────────────

log_approval() {
  local decision="$1" tool="$2" detail="$3"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $decision | $tool | ${detail:0:100}" >> "$LOG_FILE" 2>/dev/null || true
}

# ── Auto-approve rules ──────────────────────────────────────
# Tools that are always safe to auto-approve without notification

AUTO_APPROVE_TOOLS="${AUTO_APPROVE_TOOLS:-}"
if [[ -n "$AUTO_APPROVE_TOOLS" ]]; then
  IFS=',' read -ra SAFE_TOOLS <<< "$AUTO_APPROVE_TOOLS"
  for safe in "${SAFE_TOOLS[@]}"; do
    safe=$(echo "$safe" | xargs) # trim whitespace
    if [[ "$TOOL_NAME" == "$safe" ]]; then
      log_approval "auto-approved" "$TOOL_NAME" "$TOOL_INPUT_RAW"
      echo '{
        "hookSpecificOutput": {
          "hookEventName": "PermissionRequest",
          "decision": { "behavior": "allow" }
        }
      }'
      exit 0
    fi
  done
fi

# ── Build notification ───────────────────────────────────────

# Unique request ID for matching response
REQUEST_ID="req-$(date +%s)-$$"

# Build workspace context tag (from shared lib)
WORKSPACE_TAG=$(shiki_workspace_tag)

# Build contextual title based on tool type
case "$TOOL_NAME" in
  Bash)   TITLE="Shiki${WORKSPACE_TAG}: Run Command" ;;
  Edit)   TITLE="Shiki${WORKSPACE_TAG}: Edit File" ;;
  Write)  TITLE="Shiki${WORKSPACE_TAG}: Create File" ;;
  Read)   TITLE="Shiki${WORKSPACE_TAG}: Read File" ;;
  Grep)   TITLE="Shiki${WORKSPACE_TAG}: Search Code" ;;
  Glob)   TITLE="Shiki${WORKSPACE_TAG}: Find Files" ;;
  Agent)  TITLE="Shiki${WORKSPACE_TAG}: Launch Agent" ;;
  WebFetch) TITLE="Shiki${WORKSPACE_TAG}: Fetch URL" ;;
  WebSearch) TITLE="Shiki${WORKSPACE_TAG}: Web Search" ;;
  *)      TITLE="Shiki${WORKSPACE_TAG}: $TOOL_NAME" ;;
esac

# Build message with tool detail as subtitle
MESSAGE="$TOOL_NAME"
if [[ -n "$TOOL_INPUT_RAW" ]]; then
  MESSAGE="$TOOL_INPUT_RAW"
fi

# Build auth header if token is set
AUTH_HEADER=""
if [[ -n "$NTFY_TOKEN" ]]; then
  AUTH_HEADER="Authorization: Bearer $NTFY_TOKEN"
fi

# ── Send notification with action buttons ────────────────────

# Build JSON payload via python3 using env vars (avoids heredoc injection)
PUBLISH_PAYLOAD=$(
  SHIKI_TOPIC="$NTFY_TOPIC" \
  SHIKI_TITLE="$TITLE" \
  SHIKI_MESSAGE="$MESSAGE" \
  SHIKI_SERVER="$NTFY_SERVER" \
  SHIKI_RESPONSE_TOPIC="$RESPONSE_TOPIC" \
  SHIKI_REQUEST_ID="$REQUEST_ID" \
  python3 -c '
import json, os
e = os.environ
srv = e["SHIKI_SERVER"]
resp_topic = e["SHIKI_RESPONSE_TOPIC"]
req_id = e["SHIKI_REQUEST_ID"]
action_url = f"{srv}/{resp_topic}"
payload = {
    "topic": e["SHIKI_TOPIC"],
    "title": e["SHIKI_TITLE"],
    "message": e["SHIKI_MESSAGE"].strip(),
    "tags": ["robot"],
    "priority": 4,
    "actions": [
        {
            "action": "http",
            "label": "\u2705 Approve",
            "url": action_url,
            "method": "POST",
            "body": f"approve:{req_id}",
            "clear": True
        },
        {
            "action": "http",
            "label": "\U0001f513 Always Allow",
            "url": action_url,
            "method": "POST",
            "body": f"always_allow:{req_id}",
            "clear": True
        },
        {
            "action": "http",
            "label": "\U0001f6ab Deny",
            "url": action_url,
            "method": "POST",
            "body": f"deny:{req_id}",
            "clear": True
        }
    ]
}
print(json.dumps(payload))
'
)

CURL_ARGS=(-sf -X POST "$NTFY_SERVER" -H "Content-Type: application/json" -d "$PUBLISH_PAYLOAD")
if [[ -n "$AUTH_HEADER" ]]; then
  CURL_ARGS+=(-H "$AUTH_HEADER")
fi

curl "${CURL_ARGS[@]}" >/dev/null 2>&1 || {
  # ntfy unreachable — fall back to CLI prompt
  log_approval "ntfy-unreachable" "$TOOL_NAME" "falling back to CLI"
  echo '{}' && exit 0
}

# ── Subscribe to response topic via SSE ──────────────────────

# Use python3 for reliable SSE subscription (handles buffering, timeout, and parsing)
SINCE_TS=$(date +%s)
DECISION=$(
  SHIKI_SERVER="$NTFY_SERVER" \
  SHIKI_RESPONSE_TOPIC="$RESPONSE_TOPIC" \
  SHIKI_TIMEOUT="$NTFY_TIMEOUT" \
  SHIKI_TOKEN="$NTFY_TOKEN" \
  SHIKI_SINCE="$SINCE_TS" \
  SHIKI_REQUEST_ID="$REQUEST_ID" \
  python3 -c '
import urllib.request, json, sys, time, os

server = os.environ["SHIKI_SERVER"]
topic = os.environ["SHIKI_RESPONSE_TOPIC"]
timeout = int(os.environ["SHIKI_TIMEOUT"])
token = os.environ.get("SHIKI_TOKEN", "")
since = os.environ["SHIKI_SINCE"]
request_id = os.environ["SHIKI_REQUEST_ID"]

url = f"{server}/{topic}/json?since={since}"
req = urllib.request.Request(url)
if token:
    req.add_header("Authorization", f"Bearer {token}")

try:
    start = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        while time.time() - start < timeout:
            line = resp.readline().decode("utf-8").strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                if data.get("event") != "message":
                    continue
                raw = data.get("message", "").strip()
                if ":" in raw:
                    decision, txn_id = raw.split(":", 1)
                    decision = decision.lower()
                    if txn_id == request_id and decision in ("approve", "deny", "always_allow"):
                        print(decision)
                        sys.exit(0)
            except (json.JSONDecodeError, ValueError):
                continue
except Exception:
    pass

print("")
'
)

# ── Send single confirmation on first response ───────────────
# One confirmation notification on the main topic so you know
# Claude received your decision. No duplicates: the SSE listener
# already exits after the first valid response.

send_confirmation() {
  local decision_label="$1" icon="$2"
  local tag
  tag=$([ "$decision_label" = "Denied" ] && echo "x" || echo "white_check_mark")
  local confirm_payload
  confirm_payload=$(
    SHIKI_TOPIC="$NTFY_TOPIC" \
    SHIKI_TITLE="$icon $decision_label: $TOOL_NAME" \
    SHIKI_TAG="$tag" \
    python3 -c '
import json, os
payload = {
    "topic": os.environ["SHIKI_TOPIC"],
    "title": os.environ["SHIKI_TITLE"],
    "tags": [os.environ["SHIKI_TAG"]],
    "priority": 1
}
print(json.dumps(payload))
'
  )
  curl -sf -X POST "$NTFY_SERVER" \
    -H "Content-Type: application/json" \
    -d "$confirm_payload" >/dev/null 2>&1 || true
}

# ── Return decision to Claude Code ───────────────────────────

case "$DECISION" in
  approve)
    log_approval "approved" "$TOOL_NAME" "$TOOL_INPUT_RAW"
    send_confirmation "Approved" "✅"
    echo '{
      "hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": { "behavior": "allow" }
      }
    }'
    ;;
  always_allow)
    log_approval "always-allowed" "$TOOL_NAME" "$TOOL_INPUT_RAW"
    send_confirmation "Always Allowed" "🔓"
    # Return allow + add permission rule so this tool won't ask again
    echo "{
      \"hookSpecificOutput\": {
        \"hookEventName\": \"PermissionRequest\",
        \"decision\": { \"behavior\": \"allow\" },
        \"updatedPermissions\": [{\"tool\": \"$TOOL_NAME\", \"permission\": \"allow\"}]
      }
    }"
    ;;
  deny)
    log_approval "denied" "$TOOL_NAME" "$TOOL_INPUT_RAW"
    send_confirmation "Denied" "❌"
    echo '{
      "hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": {
          "behavior": "deny",
          "message": "Denied via Shiki remote approval"
        }
      }
    }'
    ;;
  *)
    # Timeout or no response — fall back to CLI prompt
    log_approval "timeout" "$TOOL_NAME" "no response in ${NTFY_TIMEOUT}s"
    echo '{
      "hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": { "behavior": "ask" }
      }
    }'
    ;;
esac
