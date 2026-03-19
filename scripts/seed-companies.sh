#!/usr/bin/env bash
# seed-companies.sh — One-shot DB population for orchestrator companies + tasks
# v2: Also populates company_projects join table and sets project_path on tasks
#
# Usage: bash scripts/seed-companies.sh
#
# Prerequisites: Backend running at localhost:3900 with orchestrator tables created

set -euo pipefail

API="http://localhost:3900"
GREEN='\033[32m'
DIM='\033[2m'
YELLOW='\033[33m'
RED='\033[31m'
RST='\033[0m'

# Check backend
if ! curl -sf "$API/health" >/dev/null 2>&1; then
  echo "Error: Backend unreachable at $API"
  echo "Start it with: docker compose up -d"
  exit 1
fi

echo -e "${GREEN}Seeding orchestrator data${RST}"
echo -e "${DIM}Backend: $API${RST}"
echo

# ── Helpers ─────────────────────────────────────────────────────────

json_field() {
  python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))"
}

json_find() {
  local slug="$1"
  python3 -c "
import json, sys
for item in json.load(sys.stdin):
    if item.get('slug') == '$slug':
        print(item['id'])
        sys.exit(0)
print('')
"
}

# ── Step 1: Ensure projects exist ───────────────────────────────────

echo -e "${YELLOW}Step 1: Checking projects...${RST}"

PROJECTS=$(curl -sf "$API/api/projects" 2>/dev/null || echo "[]")

ensure_project() {
  local slug="$1" name="$2"
  local pid
  pid=$(echo "$PROJECTS" | json_find "$slug")

  if [ -n "$pid" ]; then
    echo "  Found project: $slug ($pid)" >&2
    echo "$pid"
    return
  fi

  # Create via docker compose exec (psql). grep extracts just the UUID line.
  pid=$(docker compose exec -T db psql -U shiki -d shiki -tAc \
    "INSERT INTO projects (slug, name) VALUES ('$slug', '$name') ON CONFLICT (slug) DO UPDATE SET name='$name' RETURNING id" 2>/dev/null \
    | grep -E '^[0-9a-f-]{36}$' || echo "")

  if [ -n "$pid" ]; then
    echo "  Created project: $slug ($pid)" >&2
    echo "$pid"
    return
  fi

  echo -e "  ${RED}Failed to create project: $slug${RST}" >&2
  echo ""
}

WABISABI_PID=$(ensure_project "wabisabi" "WabiSabi")
MAYA_PID=$(ensure_project "maya" "Maya")
BRAINY_PID=$(ensure_project "brainy" "Brainy")
KINTSUGI_PID=$(ensure_project "kintsugi-ds" "DSKintsugi")
FLSH_PID=$(ensure_project "flsh" "Flsh")
OBYW_PID=$(ensure_project "obyw-one" "OBYW.one")

# Validate required projects
for pair in "WABISABI_PID:wabisabi" "MAYA_PID:maya" "BRAINY_PID:brainy" "KINTSUGI_PID:kintsugi-ds"; do
  var="${pair%%:*}"; slug="${pair##*:}"
  eval "val=\$$var"
  if [ -z "$val" ]; then
    echo -e "${RED}Error: Missing project '$slug'. Create manually:${RST}"
    echo "  docker compose exec db psql -U shiki -d shiki -c \"INSERT INTO projects (slug, name) VALUES ('$slug', '$slug')\""
    exit 1
  fi
done

echo

# ── Step 2: Create companies ────────────────────────────────────────

echo -e "${YELLOW}Step 2: Creating companies...${RST}"

# Get ALL companies (not just active) to avoid re-creating paused ones
ALL_COMPANIES=$(curl -sf "$API/api/companies" 2>/dev/null || echo "[]")

ensure_company() {
  local slug="$1" name="$2" pid="$3" priority="$4" daily="$5" monthly="$6"
  local hours_start="$7" hours_end="$8" days="$9" config="${10}"

  local existing
  existing=$(echo "$ALL_COMPANIES" | json_find "$slug")

  if [ -n "$existing" ]; then
    echo "  Found company: $slug ($existing)" >&2
    echo "$existing"
    return
  fi

  local result
  result=$(curl -sf -X POST "$API/api/companies" \
    -H "Content-Type: application/json" \
    -d "{
      \"projectId\": \"$pid\",
      \"slug\": \"$slug\",
      \"displayName\": \"$name\",
      \"priority\": $priority,
      \"budget\": {\"daily_usd\": $daily, \"monthly_usd\": $monthly, \"spent_today_usd\": 0},
      \"schedule\": {\"active_hours\": [$hours_start, $hours_end], \"timezone\": \"Europe/Paris\", \"days\": $days},
      \"config\": $config
    }")

  local cid
  cid=$(echo "$result" | json_field "id")
  if [ -n "$cid" ]; then
    echo "  Created company: $slug ($cid)" >&2
    echo "$cid"
  else
    echo -e "  ${RED}Failed to create company: $slug${RST}" >&2
    echo ""
  fi
}

WABISABI_CID=$(ensure_company "wabisabi" "WabiSabi" "$WABISABI_PID" 3 8 200 8 22 "[1,2,3,4,5,6,7]" '{"project_path":"wabisabi","max_concurrent":3}')
MAYA_CID=$(ensure_company "maya" "Maya" "$MAYA_PID" 3 8 200 8 22 "[1,2,3,4,5,6,7]" '{"project_path":"Maya","max_concurrent":3}')
BRAINY_CID=$(ensure_company "brainy" "Brainy" "$BRAINY_PID" 5 5 100 9 20 "[1,2,3,4,5]" '{"project_path":"brainy","max_concurrent":2}')
KINTSUGI_CID=$(ensure_company "kintsugi" "DSKintsugi" "$KINTSUGI_PID" 7 3 80 10 18 "[1,2,3,4,5]" '{"project_path":"kintsugi-ds","max_concurrent":1}')
FLSH_CID=$(ensure_company "flsh" "Flsh" "${FLSH_PID:-$BRAINY_PID}" 4 5 100 8 22 "[1,2,3,4,5,6,7]" '{"project_path":"flsh","max_concurrent":2}')
OBYW_CID=$(ensure_company "obyw-one" "OBYW.one" "${OBYW_PID:-$BRAINY_PID}" 6 3 80 9 20 "[1,2,3,4,5]" '{"project_path":"obyw-one","max_concurrent":1}')

echo

# ── Step 2b: Populate company_projects join table ────────────────────

echo -e "${YELLOW}Step 2b: Populating company_projects...${RST}"

link_project() {
  local cid="$1" pid="$2" role="${3:-member}"
  if [ -z "$cid" ] || [ -z "$pid" ]; then return; fi
  docker compose exec -T db psql -U shiki -d shiki -tAc \
    "INSERT INTO company_projects (company_id, project_id, role)
     VALUES ('$cid', '$pid', '$role')
     ON CONFLICT DO NOTHING" >/dev/null 2>&1
}

# Primary project links (already migrated by 005, but ensure they exist)
link_project "$WABISABI_CID" "$WABISABI_PID" "primary"
link_project "$MAYA_CID" "$MAYA_PID" "primary"
link_project "$BRAINY_CID" "$BRAINY_PID" "primary"
link_project "$KINTSUGI_CID" "$KINTSUGI_PID" "primary"
link_project "$FLSH_CID" "$FLSH_PID" "primary"
link_project "$OBYW_CID" "$OBYW_PID" "primary"

# Cross-project links (companies that work on shared packages)
# WabiSabi and Maya both use CoreKit, NetKit, SecurityKit, DSKintsugi
link_project "$WABISABI_CID" "$KINTSUGI_PID" "member"
link_project "$MAYA_CID" "$KINTSUGI_PID" "member"

echo -e "  ${DIM}Linked companies to projects${RST}"
echo

# ── Step 3: Seed tasks (with project_path) ───────────────────────────

echo -e "${YELLOW}Step 3: Seeding tasks...${RST}"

seed_task() {
  local cid="$1" title="$2" desc="$3" priority="${4:-5}" project_path="${5:-}"

  # Skip if company ID is empty
  if [ -z "$cid" ]; then
    echo "  [SKIP] $title (no company ID)"
    return
  fi

  local jtitle jdesc
  jtitle=$(python3 -c "import json; print(json.dumps('''$title'''))")
  jdesc=$(python3 -c "import json; print(json.dumps('''$desc'''))")

  local path_field=""
  if [ -n "$project_path" ]; then
    path_field=",\"projectPath\": \"$project_path\""
  fi

  curl -sf -X POST "$API/api/task-queue" \
    -H "Content-Type: application/json" \
    -d "{
      \"companyId\": \"$cid\",
      \"title\": $jtitle,
      \"description\": $jdesc,
      \"source\": \"backlog\",
      \"priority\": $priority
      $path_field
    }" >/dev/null 2>&1 && echo "  [$title]" || echo "  [FAIL] $title"
}

echo -e "  ${DIM}WabiSabi tasks:${RST}"
seed_task "$WABISABI_CID" "SPM migration wave 1" "Extract Package.swift, setup targets" 3 "wabisabi"
seed_task "$WABISABI_CID" "SPM migration wave 2" "Move sources to SPM structure" 3 "wabisabi"
seed_task "$WABISABI_CID" "SPM migration wave 3" "Public API boundaries" 4 "wabisabi"
seed_task "$WABISABI_CID" "SPM migration wave 4" "XcodeGen integration" 5 "wabisabi"
seed_task "$WABISABI_CID" "SPM migration wave 5" "Test migration and CI" 6 "wabisabi"
seed_task "$WABISABI_CID" "Landing page fixes" "Dark mode contrast + animation rework" 5 "obyw-one"
seed_task "$WABISABI_CID" "ContainerTests thread safety" "Fix race conditions in DI tests" 4 "wabisabi"

echo -e "  ${DIM}Maya tasks:${RST}"
seed_task "$MAYA_CID" "MayaKit public API wave 1" "Protocol extraction + public modifiers" 2 "Maya"
seed_task "$MAYA_CID" "MayaKit public API wave 2" "Repository + UseCase layer" 3 "Maya"
seed_task "$MAYA_CID" "MayaKit public API wave 3" "ViewModel exposure" 4 "Maya"
seed_task "$MAYA_CID" "MayaKit public API wave 4" "Snapshot test fixes" 5 "Maya"
seed_task "$MAYA_CID" "Geo-discovery feature" "MapLibre integration for club search" 6 "Maya"
seed_task "$MAYA_CID" "Safety system" "Content moderation + reporting" 7 "Maya"
seed_task "$MAYA_CID" "Family accounts" "Parent-child account linking" 8 "Maya"

echo -e "  ${DIM}Brainy tasks:${RST}"
seed_task "$BRAINY_CID" "CLI core architecture" "ArgumentParser + command structure" 3 "brainy"
seed_task "$BRAINY_CID" "libsql local storage" "Feed + article persistence" 4 "brainy"
seed_task "$BRAINY_CID" "AI augmentation layer" "Summary, tags, relevance scoring" 5 "brainy"
seed_task "$BRAINY_CID" "TUI reader" "Terminal UI for article reading" 6 "brainy"
seed_task "$BRAINY_CID" "RSS scraping engine" "Feed discovery + parsing" 4 "brainy"

echo -e "  ${DIM}Kintsugi tasks:${RST}"
seed_task "$KINTSUGI_CID" "DTCG token pipeline" "W3C Design Token Community Group format" 3 "kintsugi-ds"
seed_task "$KINTSUGI_CID" "Multi-theme support" "Light/dark + custom theme engine" 5 "kintsugi-ds"
seed_task "$KINTSUGI_CID" "Cross-platform components" "SwiftUI + Web component parity" 7 "kintsugi-ds"

echo -e "  ${DIM}Flsh tasks:${RST}"
seed_task "$FLSH_CID" "MLX pipeline" "Apple MLX voice processing pipeline" 3 "flsh"
seed_task "$FLSH_CID" "Local whisper integration" "On-device speech-to-text" 4 "flsh"

echo -e "  ${DIM}OBYW tasks:${RST}"
seed_task "$OBYW_CID" "Landing page updates" "Update all landing pages" 5 "obyw-one"
seed_task "$OBYW_CID" "Caddy config refresh" "Update reverse proxy rules" 6 "obyw-one"

echo
echo -e "${GREEN}Done! Seeded 6 companies + tasks with project paths.${RST}"
echo -e "${DIM}Verify with: shiki-ctl status${RST}"
