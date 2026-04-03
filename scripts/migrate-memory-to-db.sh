#!/bin/bash
# Phase 2: Memory Migration to ShikiDB
# Reads classified memory files, parses frontmatter, and POSTs to ShikiDB.
# Idempotent: skips files already migrated (BR-09).
#
# Prerequisites:
#   - ShikiDB running at localhost:3900
#   - classify-memory.sh in same directory
#
# Usage:
#   ./scripts/migrate-memory-to-db.sh [memory-dir] [--dry-run]
#
# BR-26: Process order — read dir, skip MEMORY.md, classify, parse, POST, log.
# BR-27: Deterministic classification via classify-memory.sh.
# BR-28: Verification report at end, exit non-zero on errors.

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFY="$SCRIPT_DIR/classify-memory.sh"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_SLUG=$(echo "$WORKSPACE_ROOT" | tr '/' '-')
DEFAULT_MEMORY_DIR="$HOME/.claude/projects/${PROJECT_SLUG}/memory"
API="http://localhost:3900"

# Project IDs from ShikiDB (must match classify-memory.sh)
PROJECT_SHIKI="80c27043-5282-4814-b79d-5e6d3903cbc9"

# ── Parse arguments ────────────────────────────────────────────────
MEMORY_DIR="${1:-$DEFAULT_MEMORY_DIR}"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      echo "Usage: $0 [memory-dir] [--dry-run]"
      echo ""
      echo "Migrates memory files to ShikiDB."
      echo "  --dry-run  Show what would be done without POSTing"
      exit 0
      ;;
  esac
done

if [[ "$MEMORY_DIR" == --* ]]; then
  MEMORY_DIR="$DEFAULT_MEMORY_DIR"
fi

if [ ! -d "$MEMORY_DIR" ]; then
  echo "ERROR: Memory directory not found: $MEMORY_DIR" >&2
  exit 1
fi

if [ ! -x "$CLASSIFY" ]; then
  echo "ERROR: classify-memory.sh not found or not executable: $CLASSIFY" >&2
  exit 1
fi

# ── Check ShikiDB health ──────────────────────────────────────────
if [ "$DRY_RUN" = false ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/health" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" != "200" ]; then
    echo "ERROR: ShikiDB not reachable at $API (HTTP $HTTP_CODE)" >&2
    exit 1
  fi
fi

# ── Fetch already-migrated filenames for idempotency (BR-09) ──────
MIGRATED_FILES=""
if [ "$DRY_RUN" = false ]; then
  MIGRATED_FILES=$(curl -s "$API/api/memories/migrated" 2>/dev/null || echo "[]")
fi

is_already_migrated() {
  local filename="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "no"
    return
  fi
  if echo "$MIGRATED_FILES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sys.exit(0 if '$filename' in data else 1)
" 2>/dev/null; then
    echo "yes"
  else
    echo "no"
  fi
}

# ── Parse YAML frontmatter (BR-07) ────────────────────────────────
# Extracts name, description, type from --- delimited YAML block
parse_frontmatter() {
  local filepath="$1"
  python3 -c "
import sys

with open('$filepath', 'r') as f:
    lines = f.readlines()

if len(lines) < 2 or lines[0].strip() != '---':
    # No frontmatter
    print('|||')
    sys.exit(0)

end_idx = -1
for i in range(1, len(lines)):
    if lines[i].strip() == '---':
        end_idx = i
        break

if end_idx == -1:
    print('|||')
    sys.exit(0)

fm = {}
for line in lines[1:end_idx]:
    if ':' in line:
        key, val = line.split(':', 1)
        fm[key.strip()] = val.strip()

name = fm.get('name', '')
desc = fm.get('description', '')
ftype = fm.get('type', '')
print(f'{name}|{desc}|{ftype}')
" 2>/dev/null
}

# ── Read file content (strip frontmatter) ─────────────────────────
read_content() {
  local filepath="$1"
  python3 -c "
import sys

with open('$filepath', 'r') as f:
    content = f.read()

# Strip frontmatter if present
if content.startswith('---'):
    parts = content.split('---', 2)
    if len(parts) >= 3:
        content = parts[2].strip()

print(content)
" 2>/dev/null
}

# ── POST memory to ShikiDB ────────────────────────────────────────
post_memory() {
  local project_id="$1"
  local content="$2"
  local category="$3"
  local importance="$4"
  local metadata="$5"

  # Escape content for JSON
  local escaped_content
  escaped_content=$(printf '%s' "$content" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

  local body
  body=$(python3 -c "
import json
body = {
    'projectId': '$project_id',
    'content': json.loads($escaped_content),
    'category': '$category',
    'importance': $importance,
    'metadata': json.loads('$metadata')
}
print(json.dumps(body))
" 2>/dev/null)

  local response http_code
  response=$(curl -s -w "\n%{http_code}" -X POST "$API/api/memories" \
    -H "Content-Type: application/json" \
    -d "$body" 2>/dev/null)

  http_code=$(echo "$response" | tail -1)
  local body_response
  body_response=$(echo "$response" | head -1)

  if [ "$http_code" = "200" ]; then
    local mem_id
    mem_id=$(echo "$body_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','?'))" 2>/dev/null || echo "?")
    echo "$mem_id"
  else
    echo "ERR:$http_code"
  fi
}

# ── Importance mapping based on scope + category ──────────────────
get_importance() {
  local scope="$1"
  local category="$2"

  case "$scope/$category" in
    personal/identity)   echo 9 ;;
    personal/strategy)   echo 8 ;;
    personal/preference) echo 7 ;;
    personal/radar)      echo 5 ;;
    project/backlog)     echo 8 ;;
    project/decision)    echo 9 ;;
    project/plan)        echo 7 ;;
    company/vision)      echo 9 ;;
    company/strategy)    echo 8 ;;
    company/infrastructure) echo 7 ;;
    company/reference)   echo 6 ;;
    *)                   echo 5 ;;
  esac
}

# ── Main migration loop ───────────────────────────────────────────
echo "=== Memory Migration to ShikiDB ==="
echo "Directory: $MEMORY_DIR"
echo "API: $API"
echo "Dry run: $DRY_RUN"
echo ""

COUNT_OK=0
COUNT_SKIP=0
COUNT_ERR=0
COUNT_ALREADY=0
COUNT_PERSONAL=0
COUNT_PROJECT=0
COUNT_COMPANY=0
COUNT_GLOBAL=0

MIGRATION_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ERRORS=()

# Get classification data into a temp file to avoid stdin conflicts
CLASSIFICATION_FILE=$(mktemp)
trap 'rm -f "$CLASSIFICATION_FILE"' EXIT
"$CLASSIFY" "$MEMORY_DIR" > "$CLASSIFICATION_FILE" 2>/dev/null

# Read from file descriptor 3 to avoid python3/curl consuming stdin
while IFS=$'\t' read -r -u 3 filename scope category project_id; do
  # Skip MEMORY.md entries
  if [ "$scope" = "SKIP" ]; then
    COUNT_SKIP=$((COUNT_SKIP + 1))
    continue
  fi

  filepath="$MEMORY_DIR/$filename"
  if [ ! -f "$filepath" ]; then
    echo "  [ERR] $filename — file not found"
    COUNT_ERR=$((COUNT_ERR + 1))
    ERRORS+=("$filename: file not found")
    continue
  fi

  # Check idempotency (BR-09)
  if [ "$(is_already_migrated "$filename")" = "yes" ]; then
    echo "  [SKIP] $filename — already migrated"
    COUNT_ALREADY=$((COUNT_ALREADY + 1))
    continue
  fi

  # Parse frontmatter (BR-07)
  FRONTMATTER=$(parse_frontmatter "$filepath")
  FM_NAME=$(echo "$FRONTMATTER" | cut -d'|' -f1)
  FM_DESC=$(echo "$FRONTMATTER" | cut -d'|' -f2)
  FM_TYPE=$(echo "$FRONTMATTER" | cut -d'|' -f3)

  # Read content (strip frontmatter)
  CONTENT=$(read_content "$filepath")
  if [ -z "$CONTENT" ]; then
    echo "  [ERR] $filename — empty content"
    COUNT_ERR=$((COUNT_ERR + 1))
    ERRORS+=("$filename: empty content")
    continue
  fi

  # Determine project ID — use Shiki as fallback for non-project-specific files
  EFFECTIVE_PROJECT="$project_id"
  if [ "$EFFECTIVE_PROJECT" = "null" ] || [ -z "$EFFECTIVE_PROJECT" ]; then
    EFFECTIVE_PROJECT="$PROJECT_SHIKI"
  fi

  # Build importance
  IMPORTANCE=$(get_importance "$scope" "$category")

  # Build metadata (BR-07) — all values passed as env vars to avoid shell escaping issues
  METADATA=$(SCOPE="$scope" FNAME="$filename" MTS="$MIGRATION_TS" ONAME="$FM_NAME" ODESC="$FM_DESC" OTYPE="$FM_TYPE" \
    python3 -c '
import json, os
meta = {
    "scope": os.environ["SCOPE"],
    "migratedFrom": os.environ["FNAME"],
    "migratedAt": os.environ["MTS"],
    "originalName": os.environ["ONAME"],
    "originalDescription": os.environ["ODESC"],
    "originalType": os.environ["OTYPE"]
}
print(json.dumps(meta))
' 2>/dev/null)

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY] $filename → scope=$scope category=$category project=$EFFECTIVE_PROJECT importance=$IMPORTANCE"
  else
    RESULT=$(post_memory "$EFFECTIVE_PROJECT" "$CONTENT" "$category" "$IMPORTANCE" "$METADATA")

    if [[ "$RESULT" == ERR:* ]]; then
      HTTP_ERR="${RESULT#ERR:}"
      echo "  [ERR] $filename — HTTP $HTTP_ERR"
      COUNT_ERR=$((COUNT_ERR + 1))
      ERRORS+=("$filename: HTTP $HTTP_ERR")
      continue
    fi

    echo "  [OK]  $filename → $RESULT (scope=$scope, category=$category)"
  fi

  COUNT_OK=$((COUNT_OK + 1))

  # Track scope counts
  case "$scope" in
    personal) COUNT_PERSONAL=$((COUNT_PERSONAL + 1)) ;;
    project)  COUNT_PROJECT=$((COUNT_PROJECT + 1)) ;;
    company)  COUNT_COMPANY=$((COUNT_COMPANY + 1)) ;;
    global)   COUNT_GLOBAL=$((COUNT_GLOBAL + 1)) ;;
  esac

done 3< "$CLASSIFICATION_FILE"

# ── Verification report (BR-28) ───────────────────────────────────
TOTAL=$((COUNT_OK + COUNT_SKIP + COUNT_ERR + COUNT_ALREADY))
echo ""
echo "=== Migration Report ==="
echo "Migration complete: $COUNT_OK/$TOTAL files processed ($COUNT_SKIP skipped: MEMORY.md, $COUNT_ALREADY already migrated)"
echo "  personal:   $COUNT_PERSONAL memories"
echo "  project:    $COUNT_PROJECT memories"
echo "  company:    $COUNT_COMPANY memories"
echo "  global:     $COUNT_GLOBAL memories"
echo "Errors: $COUNT_ERR"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "Error details:"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
fi

if [ "$DRY_RUN" = false ] && [ "$COUNT_ERR" -eq 0 ] && [ "$COUNT_OK" -gt 0 ]; then
  echo ""
  echo "Next steps:"
  echo "  1. Verify in @db: curl -s '$API/api/memories/migrated' | python3 -m json.tool"
  echo "  2. Test MEMORY.md pointer format with a real Claude Code session"
  echo "  3. Run git cleanup (separate spec): git filter-repo --path-glob '*/memory/*.md' --invert-paths"
fi

# Exit non-zero on errors (BR-28)
if [ "$COUNT_ERR" -gt 0 ]; then
  exit 1
fi
