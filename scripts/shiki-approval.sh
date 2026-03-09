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
    # Summarize: show command for Bash, file_path for Read/Edit/Write, pattern for Grep/Glob
    cmd = ti.get('command', '')
    fp = ti.get('file_path', '')
    pattern = ti.get('pattern', '')
    if cmd:
        # Truncate long commands
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

# Build workspace context tag for title
# - Worktree on branch → [WS:branch-name]
# - Different folder than "shiki" → [FolderName]
# - Shiki root → no tag
FOLDER_NAME=$(basename "$(pwd)")
WORKSPACE_TAG=""
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
if [[ "$GIT_DIR" == *"/worktrees/"* ]]; then
  # We're in a git worktree — show branch name
  BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  if [[ -n "$BRANCH" ]]; then
    WORKSPACE_TAG="[WS:${BRANCH}]"
  else
    WORKSPACE_TAG="[WS:${FOLDER_NAME}]"
  fi
elif [[ "$FOLDER_NAME" != "shiki" ]]; then
  WORKSPACE_TAG="[${FOLDER_NAME}]"
fi

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

# Build JSON payload via python3 (handles escaping safely)
PUBLISH_PAYLOAD=$(python3 << PYEOF
import json, sys

message = """$MESSAGE"""
payload = {
    "topic": "$NTFY_TOPIC",
    "title": "$TITLE",
    "message": message.strip(),
    "tags": ["robot"],
    "priority": 4,
    "actions": [
        {
            "action": "http",
            "label": "\u2705 Approve",
            "url": "$NTFY_SERVER/$RESPONSE_TOPIC",
            "method": "POST",
            "body": "approve:$REQUEST_ID",
            "clear": True
        },
        {
            "action": "http",
            "label": "\ud83d\udd13 Always Allow",
            "url": "$NTFY_SERVER/$RESPONSE_TOPIC",
            "method": "POST",
            "body": "always_allow:$REQUEST_ID",
            "clear": True
        },
        {
            "action": "http",
            "label": "\ud83d\udeab Deny",
            "url": "$NTFY_SERVER/$RESPONSE_TOPIC",
            "method": "POST",
            "body": "deny:$REQUEST_ID",
            "clear": True
        }
    ]
}
print(json.dumps(payload))
PYEOF
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
DECISION=$(python3 << PYEOF
import urllib.request, json, sys, time

server = "$NTFY_SERVER"
topic = "$RESPONSE_TOPIC"
timeout = int("$NTFY_TIMEOUT")
token = "$NTFY_TOKEN"
since = "$SINCE_TS"
request_id = "$REQUEST_ID"

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
                # Parse "decision:request_id" format
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

# Timeout — no decision
print("")
PYEOF
)

# ── Send confirmation notification ────────────────────────────

send_confirmation() {
  local status="$1" icon="$2" detail="$3"
  local confirm_payload
  confirm_payload=$(python3 << CPYEOF
import json
payload = {
    "topic": "$NTFY_TOPIC",
    "title": "$icon $status: $TOOL_NAME",
    "message": "$detail",
    "tags": ["$([ "$status" = "Denied" ] && echo "x" || echo "white_check_mark")"],
    "priority": 2
}
print(json.dumps(payload))
CPYEOF
)
  curl -sf -X POST "$NTFY_SERVER" \
    -H "Content-Type: application/json" \
    -d "$confirm_payload" >/dev/null 2>&1 || true
}

# ── Return decision to Claude Code ───────────────────────────

case "$DECISION" in
  approve)
    log_approval "approved" "$TOOL_NAME" "$TOOL_INPUT_RAW"
    send_confirmation "Approved" "✅" "$TOOL_NAME — ${TOOL_INPUT_RAW:0:100}"
    echo '{
      "hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": { "behavior": "allow" }
      }
    }'
    ;;
  always_allow)
    log_approval "always-allowed" "$TOOL_NAME" "$TOOL_INPUT_RAW"
    send_confirmation "Always Allowed" "🔓" "$TOOL_NAME will no longer ask"
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
    send_confirmation "Denied" "❌" "$TOOL_NAME — ${TOOL_INPUT_RAW:0:100}"
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
