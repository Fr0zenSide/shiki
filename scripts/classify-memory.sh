#!/bin/bash
# Phase 1: Memory File Classification
# Scans memory/*.md files and classifies each by scope + category
# per BR-27 deterministic rules. No AI classification — reproducible results.
#
# Usage:
#   ./scripts/classify-memory.sh [memory-dir] [--json] [--report]
#
# Output: TSV lines: filename<TAB>scope<TAB>category<TAB>project
# With --json: JSON array
# With --report: Summary report with counts

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────
DEFAULT_MEMORY_DIR="$HOME/.claude/projects/-Users-jeoffrey-Documents-Workspaces-shiki/memory"

# Project IDs from ShikiDB
PROJECT_SHIKI="80c27043-5282-4814-b79d-5e6d3903cbc9"
PROJECT_MAYA="bb9e4385-f087-4f65-8251-470f14230c3c"
PROJECT_WABISABI="38172cfa-6081-4e64-8e3c-2798653d349b"
PROJECT_BRAINY="61056227-7790-4749-a2e1-70b4e372da47"
PROJECT_FLSH="fadaa7d4-7d42-4d3c-a9d6-5388b5e61115"

# ── Parse arguments ────────────────────────────────────────────────
MEMORY_DIR="${1:-$DEFAULT_MEMORY_DIR}"
OUTPUT_FORMAT="tsv"
SHOW_REPORT=false

for arg in "$@"; do
  case "$arg" in
    --json) OUTPUT_FORMAT="json" ;;
    --report) SHOW_REPORT=true ;;
    --help|-h)
      echo "Usage: $0 [memory-dir] [--json] [--report]"
      echo ""
      echo "Classifies memory files by scope, category, and project."
      echo "Default memory dir: $DEFAULT_MEMORY_DIR"
      exit 0
      ;;
  esac
done

# Strip flags from MEMORY_DIR if passed as first arg
if [[ "$MEMORY_DIR" == --* ]]; then
  MEMORY_DIR="$DEFAULT_MEMORY_DIR"
fi

if [ ! -d "$MEMORY_DIR" ]; then
  echo "ERROR: Memory directory not found: $MEMORY_DIR" >&2
  exit 1
fi

# ── Classification function (BR-27) ───────────────────────────────
# Returns: scope<TAB>category<TAB>projectId
classify_file() {
  local filename="$1"
  local scope=""
  local category=""
  local project_id=""

  case "$filename" in
    # Skip MEMORY.md — it's the manifest, not a memory
    MEMORY.md)
      echo "SKIP"
      return
      ;;

    # User identity / PII → personal + identity
    user_*)
      scope="personal"
      category="identity"
      ;;

    # Email signature → personal + identity
    email-signature.md)
      scope="personal"
      category="identity"
      ;;

    # Feedback files → personal + preference (BR-05)
    feedback_*)
      scope="personal"
      category="preference"
      ;;

    # Radar references → personal + radar
    reference_*radar*.md)
      scope="personal"
      category="radar"
      ;;

    # Other references → company + reference
    reference_*)
      scope="company"
      category="reference"
      ;;

    # IAL / fundraising → personal + strategy
    project_ial-*)
      scope="personal"
      category="strategy"
      ;;

    # Prelaunch strategy → personal + strategy
    project_*-prelaunch*)
      scope="personal"
      category="strategy"
      ;;

    # Fundraising → personal + strategy
    project_*-fundraising*)
      scope="personal"
      category="strategy"
      ;;

    # Haiku conversion strategy → personal + strategy
    project_haiku-conversion-strategy.md)
      scope="personal"
      category="strategy"
      ;;

    # Ownership structure → company + infrastructure
    project_ownership-structure.md)
      scope="company"
      category="infrastructure"
      ;;

    # Vision docs → company + vision
    project_*-vision*)
      scope="company"
      category="vision"
      ;;

    # Thesis → company + vision
    project_shiki-thesis.md)
      scope="company"
      category="vision"
      ;;

    # Backlogs → project + backlog
    project_*-backlog*)
      scope="project"
      category="backlog"
      ;;

    # Decision docs → project + decision
    project_*-decision*)
      scope="project"
      category="decision"
      ;;

    # Plans / migration plans → project + plan
    project_*-plan*)
      scope="project"
      category="plan"
      ;;

    # Roadmaps → project + plan
    project_*-roadmap*)
      scope="project"
      category="plan"
      ;;

    # Maya backlog (standalone) → project + backlog
    maya-backlog.md)
      scope="project"
      category="backlog"
      project_id="$PROJECT_MAYA"
      ;;

    # Media strategy → company + strategy
    media-strategy.md)
      scope="company"
      category="strategy"
      ;;

    # Object storage → company + infrastructure
    object-storage.md)
      scope="company"
      category="infrastructure"
      ;;

    # Agent skills audit → company + reference
    project_agent-skills-audit*)
      scope="company"
      category="reference"
      ;;

    # License decision → company + infrastructure
    project_license-decision.md)
      scope="company"
      category="infrastructure"
      ;;

    # Branding → company + vision
    project_branding-domain.md)
      scope="company"
      category="vision"
      ;;

    # All remaining project_*.md → project + plan (BR-27 fallback)
    project_*.md)
      scope="project"
      category="plan"
      ;;

    # Catch-all for unknown patterns
    *)
      scope="company"
      category="reference"
      ;;
  esac

  # ── Project association (BR-08) ──────────────────────────────
  # Only set if not already determined above
  if [ -z "$project_id" ]; then
    case "$filename" in
      *maya*|*Maya*)
        project_id="$PROJECT_MAYA"
        ;;
      *wabisabi*|*WabiSabi*|*wabi*)
        project_id="$PROJECT_WABISABI"
        ;;
      *brainy*|*Brainy*)
        project_id="$PROJECT_BRAINY"
        ;;
      *flsh*|*Flsh*)
        project_id="$PROJECT_FLSH"
        ;;
      *shiki*|*Shiki*|*shikki*|*Shikki*)
        project_id="$PROJECT_SHIKI"
        ;;
      # Generic files → Shiki project, null project
      *)
        project_id=""
        ;;
    esac
  fi

  echo "${scope}	${category}	${project_id}"
}

# ── Main ───────────────────────────────────────────────────────────
COUNT_PERSONAL=0
COUNT_PROJECT=0
COUNT_COMPANY=0
COUNT_GLOBAL=0
COUNT_SKIP=0
COUNT_TOTAL=0

JSON_ENTRIES=()

while IFS= read -r file; do
  filename=$(basename "$file")
  COUNT_TOTAL=$((COUNT_TOTAL + 1))

  result=$(classify_file "$filename")

  if [ "$result" = "SKIP" ]; then
    COUNT_SKIP=$((COUNT_SKIP + 1))
    if [ "$OUTPUT_FORMAT" = "tsv" ] && [ "$SHOW_REPORT" = false ]; then
      printf "%s\tSKIP\t-\t-\n" "$filename"
    fi
    continue
  fi

  IFS=$'\t' read -r scope category project_id <<< "$result"

  case "$scope" in
    personal) COUNT_PERSONAL=$((COUNT_PERSONAL + 1)) ;;
    project) COUNT_PROJECT=$((COUNT_PROJECT + 1)) ;;
    company) COUNT_COMPANY=$((COUNT_COMPANY + 1)) ;;
    global) COUNT_GLOBAL=$((COUNT_GLOBAL + 1)) ;;
  esac

  if [ "$OUTPUT_FORMAT" = "tsv" ] && [ "$SHOW_REPORT" = false ]; then
    printf "%s\t%s\t%s\t%s\n" "$filename" "$scope" "$category" "${project_id:-null}"
  fi

  if [ "$OUTPUT_FORMAT" = "json" ]; then
    JSON_ENTRIES+=("{\"filename\":\"$filename\",\"scope\":\"$scope\",\"category\":\"$category\",\"projectId\":$([ -n "$project_id" ] && echo "\"$project_id\"" || echo "null")}")
  fi

done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" -type f | sort)

# ── JSON output ────────────────────────────────────────────────────
if [ "$OUTPUT_FORMAT" = "json" ]; then
  echo "["
  for i in "${!JSON_ENTRIES[@]}"; do
    if [ "$i" -lt $((${#JSON_ENTRIES[@]} - 1)) ]; then
      echo "  ${JSON_ENTRIES[$i]},"
    else
      echo "  ${JSON_ENTRIES[$i]}"
    fi
  done
  echo "]"
fi

# ── Report ─────────────────────────────────────────────────────────
if [ "$SHOW_REPORT" = true ]; then
  PROCESSED=$((COUNT_TOTAL - COUNT_SKIP))
  echo "=== Memory Classification Report ==="
  echo "Directory: $MEMORY_DIR"
  echo ""
  echo "Total files:  $COUNT_TOTAL"
  echo "Skipped:      $COUNT_SKIP (MEMORY.md)"
  echo "Classified:   $PROCESSED"
  echo ""
  echo "By scope:"
  echo "  personal:   $COUNT_PERSONAL"
  echo "  project:    $COUNT_PROJECT"
  echo "  company:    $COUNT_COMPANY"
  echo "  global:     $COUNT_GLOBAL"
  echo ""
  echo "Verification: $((COUNT_PERSONAL + COUNT_PROJECT + COUNT_COMPANY + COUNT_GLOBAL)) = $PROCESSED classified"
fi
