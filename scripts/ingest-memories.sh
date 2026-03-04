#!/bin/bash
# Shiki — Memory Ingestion Template
# Reads memory content and POSTs to /api/memories
# Customize this script for your project's knowledge base
#
# Usage:
#   ./scripts/ingest-memories.sh <project-id>

set -euo pipefail

API="http://localhost:3900/api/memories"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-id>"
  echo ""
  echo "Get your project ID from the Shiki dashboard or:"
  echo "  curl -s http://localhost:3900/api/projects | python3 -m json.tool"
  exit 1
fi

PROJ_ID="$1"
SESS_ID="a0000001-0000-0000-0000-000000000001"
COORD_ID="b0000001-0000-0000-0000-000000000001"

COUNT=0
FAIL=0

post_memory() {
  local category="$1"
  local importance="$2"
  local content="$3"

  # Escape content for JSON (handle newlines, quotes, backslashes)
  local escaped
  escaped=$(printf '%s' "$content" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

  local body="{\"projectId\":\"$PROJ_ID\",\"sessionId\":\"$SESS_ID\",\"agentId\":\"$COORD_ID\",\"content\":$escaped,\"category\":\"$category\",\"importance\":$importance}"

  local result
  result=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API" -H "Content-Type: application/json" -d "$body" 2>/dev/null)

  if [ "$result" = "200" ]; then
    COUNT=$((COUNT + 1))
    echo "  [$COUNT] $category (imp=$importance) — ${#content} chars"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL ($result) $category — ${content:0:60}..."
  fi
}

echo "=== Shiki Memory Ingestion ==="
echo "Project: $PROJ_ID"
echo ""

# ── Example: Add your project's knowledge here ──
# Uncomment and customize these examples:

# post_memory "architecture" 9 "PROJECT ARCHITECTURE:
# - Language: TypeScript/Swift/Python/etc.
# - Framework: React/SwiftUI/Django/etc.
# - Architecture: Clean Arch/MVC/MVVM/etc.
# - Key paths: src/, tests/, config/"

# post_memory "process" 8 "DEVELOPMENT PROCESS:
# - TDD mandatory
# - Feature branches from develop
# - Squash merge to main for releases"

# post_memory "environment" 7 "ENVIRONMENTS:
# - Dev: localhost:3000
# - Staging: staging.example.com
# - Prod: app.example.com"

echo ""
echo "=== DONE ==="
echo "Inserted: $COUNT memories"
echo "Failed: $FAIL"
echo ""
echo "To add memories, edit this script with your project's knowledge."
echo "See the examples above for guidance."
