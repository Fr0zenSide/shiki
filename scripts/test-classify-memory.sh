#!/bin/bash
# Tests for classify-memory.sh classification logic
# Validates BR-27 deterministic mapping rules
#
# Usage: ./scripts/test-classify-memory.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFY="$SCRIPT_DIR/classify-memory.sh"
PASS=0
FAIL=0
ERRORS=()

# ── Test helper ────────────────────────────────────────────────────
assert_classification() {
  local test_name="$1"
  local filename="$2"
  local expected_scope="$3"
  local expected_category="$4"
  local expected_project="${5:-}"

  # Create a temp dir with one file
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/$filename"

  local output
  output=$("$CLASSIFY" "$tmpdir" 2>/dev/null | head -1)
  rm -rf "$tmpdir"

  local got_scope got_category got_project
  got_scope=$(echo "$output" | cut -f2)
  got_category=$(echo "$output" | cut -f3)
  got_project=$(echo "$output" | cut -f4)

  local pass=true

  if [ "$got_scope" != "$expected_scope" ]; then
    pass=false
  fi
  if [ "$got_category" != "$expected_category" ]; then
    pass=false
  fi
  if [ -n "$expected_project" ] && [ "$got_project" != "$expected_project" ]; then
    pass=false
  fi

  if [ "$pass" = true ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $test_name — expected scope=$expected_scope category=$expected_category project=${expected_project:-any} got scope=$got_scope category=$got_category project=$got_project")
  fi
}

assert_skip() {
  local test_name="$1"
  local filename="$2"

  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/$filename"

  local output
  output=$("$CLASSIFY" "$tmpdir" 2>/dev/null | head -1)
  rm -rf "$tmpdir"

  local got_scope
  got_scope=$(echo "$output" | cut -f2)

  if [ "$got_scope" = "SKIP" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $test_name — expected SKIP, got: $output")
  fi
}

# ── T-MIG-04/05: Scope + Category classification tests (BR-27) ───

# User identity files → personal + identity
assert_classification "user_identity → personal/identity" \
  "user_identity.md" "personal" "identity"

assert_classification "user_profile-extended → personal/identity" \
  "user_profile-extended.md" "personal" "identity"

assert_classification "user_media-language-preferences → personal/identity" \
  "user_media-language-preferences.md" "personal" "identity"

assert_classification "email-signature → personal/identity" \
  "email-signature.md" "personal" "identity"

# Feedback files → personal + preference (BR-05)
assert_classification "feedback_stop-asking → personal/preference" \
  "feedback_stop-asking-just-do.md" "personal" "preference"

assert_classification "feedback_no-print-in-tests → personal/preference" \
  "feedback_no-print-in-tests.md" "personal" "preference"

assert_classification "feedback_emacs-keybindings → personal/preference" \
  "feedback_emacs-keybindings.md" "personal" "preference"

# Radar references → personal + radar
assert_classification "reference_astrbot-radar → personal/radar" \
  "reference_astrbot-radar.md" "personal" "radar"

assert_classification "reference_gh-trending-radar → personal/radar" \
  "reference_gh-trending-radar-2026-03-25.md" "personal" "radar"

assert_classification "reference_radar-watchlist → personal/radar" \
  "reference_radar-watchlist-2026-03-23.md" "personal" "radar"

assert_classification "reference_text-to-video-radar → personal/radar" \
  "reference_text-to-video-radar.md" "personal" "radar"

# Other references → company + reference
assert_classification "reference_qmd-search-engine → company/reference" \
  "reference_qmd-search-engine.md" "company" "reference"

assert_classification "reference_openfang-ideas → company/reference" \
  "reference_openfang-ideas.md" "company" "reference"

assert_classification "reference_skills-ecosystem → company/reference" \
  "reference_skills-ecosystem-analysis.md" "company" "reference"

# IAL / fundraising / prelaunch → personal + strategy
assert_classification "project_ial-maya-fundraising → personal/strategy" \
  "project_ial-maya-fundraising.md" "personal" "strategy"

assert_classification "project_maya-prelaunch-strategy → personal/strategy" \
  "project_maya-prelaunch-strategy.md" "personal" "strategy"

assert_classification "project_haiku-conversion-strategy → personal/strategy" \
  "project_haiku-conversion-strategy.md" "personal" "strategy"

# Vision docs → company + vision
assert_classification "project_shiki-vision-full-topology → company/vision" \
  "project_shiki-vision-full-topology.md" "company" "vision"

assert_classification "project_shiki-thesis → company/vision" \
  "project_shiki-thesis.md" "company" "vision"

assert_classification "project_branding-domain → company/vision" \
  "project_branding-domain.md" "company" "vision"

# Backlogs → project + backlog
assert_classification "maya-backlog → project/backlog" \
  "maya-backlog.md" "project" "backlog" "bb9e4385-f087-4f65-8251-470f14230c3c"

assert_classification "project_wabisabi-backlog → project/backlog" \
  "project_wabisabi-backlog.md" "project" "backlog"

assert_classification "project_brainy-backlog → project/backlog" \
  "project_brainy-backlog.md" "project" "backlog"

# Decision docs → project + decision
assert_classification "project_autopilot-reactor-decision → project/decision" \
  "project_autopilot-reactor-decision.md" "project" "decision"

assert_classification "project_context-optimization-decision → project/decision" \
  "project_context-optimization-decision.md" "project" "decision"

# Plans → project + plan
assert_classification "project_maya-spm-public-api-plan → project/plan" \
  "project_maya-spm-public-api-plan.md" "project" "plan"

assert_classification "project_wabisabi-spm-migration-plan → project/plan" \
  "project_wabisabi-spm-migration-plan.md" "project" "plan"

assert_classification "project_shiki-full-roadmap-v1 → project/plan" \
  "project_shiki-full-roadmap-v1.md" "project" "plan"

# Ownership → company + infrastructure
assert_classification "project_ownership-structure → company/infrastructure" \
  "project_ownership-structure.md" "company" "infrastructure"

# Media strategy → company + strategy
assert_classification "media-strategy → company/strategy" \
  "media-strategy.md" "company" "strategy"

# Object storage → company + infrastructure
assert_classification "object-storage → company/infrastructure" \
  "object-storage.md" "company" "infrastructure"

# Agent skills audit → company + reference
assert_classification "project_agent-skills-audit → company/reference" \
  "project_agent-skills-audit-2026-03.md" "company" "reference"

# Remaining project_*.md → project + plan
assert_classification "project_tmux-layout-vision → company/vision" \
  "project_tmux-layout-vision.md" "company" "vision"

assert_classification "project_codegen-engine-decisions → project/decision" \
  "project_codegen-engine-decisions.md" "project" "decision"

# MEMORY.md → SKIP
assert_skip "MEMORY.md is skipped" "MEMORY.md"

# ── T-MIG-06: Project association (BR-08) ─────────────────────────
assert_classification "maya file → Maya project" \
  "project_maya-spm-public-api-plan.md" "project" "plan" "bb9e4385-f087-4f65-8251-470f14230c3c"

assert_classification "wabisabi file → WabiSabi project" \
  "project_wabisabi-backlog.md" "project" "backlog" "38172cfa-6081-4e64-8e3c-2798653d349b"

assert_classification "brainy file → Brainy project" \
  "project_brainy-backlog.md" "project" "backlog" "61056227-7790-4749-a2e1-70b4e372da47"

assert_classification "shiki file → Shiki project" \
  "project_shiki-full-roadmap-v1.md" "project" "plan" "80c27043-5282-4814-b79d-5e6d3903cbc9"

assert_classification "flsh file → Flsh project" \
  "project_flsh-revival.md" "project" "plan" "fadaa7d4-7d42-4d3c-a9d6-5388b5e61115"

# ── T-MIG-11: MEMORY.md is skipped ────────────────────────────────
assert_skip "MEMORY.md not migrated" "MEMORY.md"

# ── Report mode test ──────────────────────────────────────────────
TMPDIR_REPORT=$(mktemp -d)
touch "$TMPDIR_REPORT/user_identity.md"
touch "$TMPDIR_REPORT/feedback_test.md"
touch "$TMPDIR_REPORT/MEMORY.md"
touch "$TMPDIR_REPORT/project_test-backlog.md"
touch "$TMPDIR_REPORT/media-strategy.md"

REPORT_OUTPUT=$("$CLASSIFY" "$TMPDIR_REPORT" --report 2>/dev/null)
rm -rf "$TMPDIR_REPORT"

if echo "$REPORT_OUTPUT" | grep -q "Total files:  5"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS+=("FAIL: report total count — expected 5")
fi

if echo "$REPORT_OUTPUT" | grep -q "Skipped:      1"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS+=("FAIL: report skip count — expected 1")
fi

if echo "$REPORT_OUTPUT" | grep -q "Classified:   4"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS+=("FAIL: report classified count — expected 4")
fi

# ── JSON output test ──────────────────────────────────────────────
TMPDIR_JSON=$(mktemp -d)
touch "$TMPDIR_JSON/user_test.md"
touch "$TMPDIR_JSON/feedback_test.md"

JSON_OUTPUT=$("$CLASSIFY" "$TMPDIR_JSON" --json 2>/dev/null)
rm -rf "$TMPDIR_JSON"

if echo "$JSON_OUTPUT" | python3 -m json.tool >/dev/null 2>&1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS+=("FAIL: JSON output is not valid JSON")
fi

JSON_COUNT=$(echo "$JSON_OUTPUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
if [ "$JSON_COUNT" = "2" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS+=("FAIL: JSON output should have 2 entries, got $JSON_COUNT")
fi

# ── Full directory classification count matches file count ────────
FULL_OUTPUT=$("$CLASSIFY" --report 2>/dev/null)
FILE_COUNT=$(ls /Users/jeoffrey/.claude/projects/-Users-jeoffrey-Documents-Workspaces-shiki/memory/*.md 2>/dev/null | wc -l | tr -d ' ')

REPORT_TOTAL=$(echo "$FULL_OUTPUT" | grep "Total files:" | awk '{print $NF}')
if [ "$REPORT_TOTAL" = "$FILE_COUNT" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS+=("FAIL: T-MIG-01 file count mismatch — dir has $FILE_COUNT, report says $REPORT_TOTAL")
fi

# ── Summary ────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))

if [ ${#ERRORS[@]} -gt 0 ]; then
  for err in "${ERRORS[@]}"; do
    echo "$err" >&2
  done
fi

echo ""
echo "=== Classification Tests ==="
echo "Passed: $PASS / $TOTAL"
echo "Failed: $FAIL / $TOTAL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
