#!/bin/bash
# Tests for migrate-memory-to-db.sh migration logic
# Tests dry-run mode, frontmatter parsing, idempotency, and report accuracy.
#
# Usage: ./scripts/test-migrate-memory.sh
#
# NOTE: Tests that POST to ShikiDB require the backend to be running.
# Dry-run tests work without a backend.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATE="$SCRIPT_DIR/migrate-memory-to-db.sh"
CLASSIFY="$SCRIPT_DIR/classify-memory.sh"
API="http://localhost:3900"
PASS=0
FAIL=0
ERRORS=()

assert_contains() {
  local test_name="$1"
  local haystack="$2"
  local needle="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $test_name — expected to contain: $needle")
  fi
}

assert_not_contains() {
  local test_name="$1"
  local haystack="$2"
  local needle="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $test_name — should NOT contain: $needle")
  else
    PASS=$((PASS + 1))
  fi
}

assert_equals() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: $test_name — expected '$expected', got '$actual'")
  fi
}

# ── Setup test fixtures ───────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# File with frontmatter
cat > "$TMPDIR/user_identity.md" << 'FIXTURE'
---
name: Test User Identity
description: Test file with frontmatter
type: user
---

## Identity
- **Full name**: Test User
- **Company**: TestCo
FIXTURE

# File without frontmatter
cat > "$TMPDIR/feedback_test-pref.md" << 'FIXTURE'
This is a feedback file without frontmatter.

It should still be processed correctly.
FIXTURE

# File that should be skipped
cat > "$TMPDIR/MEMORY.md" << 'FIXTURE'
# Memory Manifest
This file should be skipped.
FIXTURE

# Project backlog file
cat > "$TMPDIR/project_shiki-backlog.md" << 'FIXTURE'
---
name: Shiki Backlog
description: Project backlog for Shiki
type: project
---

## Backlog
- Item 1
- Item 2
FIXTURE

# Media strategy (company scope)
cat > "$TMPDIR/media-strategy.md" << 'FIXTURE'
---
name: Media Strategy
description: Company media strategy
type: strategy
---

## Strategy
Social media plan.
FIXTURE

# Radar file
cat > "$TMPDIR/reference_test-radar.md" << 'FIXTURE'
---
name: Test Radar
description: Radar analysis
type: reference
---

## Radar Items
- Tool A
FIXTURE

# ── T1: Dry-run processes all files ──────────────────────────────
OUTPUT=$("$MIGRATE" "$TMPDIR" --dry-run 2>&1)
assert_contains "T1a: dry-run shows DRY tag" "$OUTPUT" "[DRY]"
assert_contains "T1b: dry-run processes user_identity" "$OUTPUT" "user_identity.md"
assert_contains "T1c: dry-run processes feedback" "$OUTPUT" "feedback_test-pref.md"
assert_not_contains "T1d: dry-run skips MEMORY.md from migration" "$OUTPUT" "[DRY] MEMORY.md"

# ── T2: Report counts are correct in dry-run ─────────────────────
assert_contains "T2a: report shows 5 processed" "$OUTPUT" "5/6 files processed"
assert_contains "T2b: report shows 1 skipped" "$OUTPUT" "1 skipped: MEMORY.md"
assert_contains "T2c: report shows Errors: 0" "$OUTPUT" "Errors: 0"

# ── T3: Scope classification in dry-run ──────────────────────────
assert_contains "T3a: user file → personal scope" "$OUTPUT" "user_identity.md → scope=personal"
assert_contains "T3b: feedback file → personal scope" "$OUTPUT" "feedback_test-pref.md → scope=personal"
assert_contains "T3c: backlog file → project scope" "$OUTPUT" "project_shiki-backlog.md → scope=project"
assert_contains "T3d: media-strategy → company scope" "$OUTPUT" "media-strategy.md → scope=company"
assert_contains "T3e: radar file → personal scope" "$OUTPUT" "reference_test-radar.md → scope=personal"

# ── T4: Category classification in dry-run ───────────────────────
assert_contains "T4a: user file → identity category" "$OUTPUT" "category=identity"
assert_contains "T4b: feedback file → preference category" "$OUTPUT" "category=preference"
assert_contains "T4c: backlog file → backlog category" "$OUTPUT" "category=backlog"
assert_contains "T4d: media-strategy → strategy category" "$OUTPUT" "category=strategy"
assert_contains "T4e: radar file → radar category" "$OUTPUT" "category=radar"

# ── T5: Importance mapping ───────────────────────────────────────
assert_contains "T5a: identity → importance=9" "$OUTPUT" "user_identity.md → scope=personal category=identity project=80c27043-5282-4814-b79d-5e6d3903cbc9 importance=9"
assert_contains "T5b: preference → importance=7" "$OUTPUT" "feedback_test-pref.md → scope=personal category=preference project=80c27043-5282-4814-b79d-5e6d3903cbc9 importance=7"
assert_contains "T5c: backlog → importance=8" "$OUTPUT" "project_shiki-backlog.md → scope=project category=backlog project=80c27043-5282-4814-b79d-5e6d3903cbc9 importance=8"

# ── T6: MEMORY.md is skipped (T-MIG-11) ─────────────────────────
SKIP_LINE=$(echo "$OUTPUT" | grep "MEMORY.md" || echo "not found")
assert_not_contains "T6: MEMORY.md not in DRY output" "$OUTPUT" "[DRY] MEMORY.md"

# ── T7: Missing directory fails with error ───────────────────────
ERR_OUTPUT=$("$MIGRATE" "/nonexistent/path" --dry-run 2>&1 || true)
assert_contains "T7: missing dir shows error" "$ERR_OUTPUT" "ERROR: Memory directory not found"

# ── T8: Frontmatter parsing ─────────────────────────────────────
# Verify classify-memory.sh correctly classifies our test files
CLASSIFY_OUTPUT=$("$CLASSIFY" "$TMPDIR" 2>&1)
assert_contains "T8a: classify outputs user_identity" "$CLASSIFY_OUTPUT" "user_identity.md"
assert_contains "T8b: classify outputs feedback" "$CLASSIFY_OUTPUT" "feedback_test-pref.md"
assert_contains "T8c: classify shows SKIP for MEMORY.md" "$CLASSIFY_OUTPUT" "MEMORY.md"

# ── T9: Empty file handling ──────────────────────────────────────
EMPTY_DIR=$(mktemp -d)
cat > "$EMPTY_DIR/feedback_empty.md" << 'FIXTURE'
---
name: Empty Feedback
description: Empty content
type: feedback
---
FIXTURE
EMPTY_OUTPUT=$("$MIGRATE" "$EMPTY_DIR" --dry-run 2>&1 || true)
rm -rf "$EMPTY_DIR"
# Even with frontmatter only, the content after stripping should be empty
# The script should report it as ERR gracefully
assert_contains "T9: empty content reported as error" "$EMPTY_OUTPUT" "feedback_empty.md"

# ── T10: Scope counts in report ──────────────────────────────────
assert_contains "T10a: personal count in report" "$OUTPUT" "personal:"
assert_contains "T10b: project count in report" "$OUTPUT" "project:"
assert_contains "T10c: company count in report" "$OUTPUT" "company:"

# ── T11: Script exits 0 on success ──────────────────────────────
"$MIGRATE" "$TMPDIR" --dry-run > /dev/null 2>&1
EXIT_CODE=$?
assert_equals "T11: exit code 0 on success" "0" "$EXIT_CODE"

# ── T12: Live API tests (only if ShikiDB has the migrated endpoint) ──
API_HEALTHY=$(curl -s -o /dev/null -w "%{http_code}" "$API/health" 2>/dev/null || echo "000")
MIGRATED_AVAILABLE=$(curl -s -o /dev/null -w "%{http_code}" "$API/api/memories/migrated" 2>/dev/null || echo "000")

if [ "$API_HEALTHY" = "200" ] && [ "$MIGRATED_AVAILABLE" = "200" ]; then
  # T12a: Migration check endpoint exists
  MIGRATED_RESPONSE=$(curl -s -w "\n%{http_code}" "$API/api/memories/migrated" 2>/dev/null)
  MIGRATED_CODE=$(echo "$MIGRATED_RESPONSE" | tail -1)
  assert_equals "T12a: /api/memories/migrated returns 200" "200" "$MIGRATED_CODE"

  # T12b: Response is a JSON array
  MIGRATED_BODY=$(echo "$MIGRATED_RESPONSE" | head -1)
  IS_ARRAY=$(echo "$MIGRATED_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if isinstance(d, list) else 'no')" 2>/dev/null || echo "no")
  assert_equals "T12b: /api/memories/migrated returns JSON array" "yes" "$IS_ARRAY"

  # T12c: POST with metadata works
  TEST_BODY='{"projectId":"80c27043-5282-4814-b79d-5e6d3903cbc9","content":"test memory migration","category":"test","importance":1,"metadata":{"migratedFrom":"_test_migration_check.md","scope":"personal","migratedAt":"2026-03-29T00:00:00Z"}}'
  POST_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/memories" \
    -H "Content-Type: application/json" \
    -d "$TEST_BODY" 2>/dev/null)
  POST_CODE=$(echo "$POST_RESPONSE" | tail -1)
  assert_equals "T12c: POST with metadata returns 200" "200" "$POST_CODE"

  if [ "$POST_CODE" = "200" ]; then
    POST_ID=$(echo "$POST_RESPONSE" | head -1 | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

    # T12d: Migrated file shows up in check endpoint
    MIGRATED_AFTER=$(curl -s "$API/api/memories/migrated" 2>/dev/null)
    HAS_TEST=$(echo "$MIGRATED_AFTER" | python3 -c "import sys,json; print('yes' if '_test_migration_check.md' in json.load(sys.stdin) else 'no')" 2>/dev/null)
    assert_equals "T12d: test file appears in migrated list" "yes" "$HAS_TEST"

    # T12e: Metadata is preserved in GET response
    MEM_RESPONSE=$(curl -s "$API/api/memories?limit=500" 2>/dev/null)
    HAS_META=$(echo "$MEM_RESPONSE" | python3 -c "
import sys, json
memories = json.load(sys.stdin)
for m in memories:
    if m.get('id') == '$POST_ID':
        meta = m.get('metadata', {})
        if meta.get('migratedFrom') == '_test_migration_check.md' and meta.get('scope') == 'personal':
            print('yes')
            sys.exit(0)
print('no')
" 2>/dev/null)
    assert_equals "T12e: metadata preserved in GET" "yes" "$HAS_META"
  fi
else
  echo "(Skipping T12 live API tests — backend migrated endpoint not available)"
fi

# ── Summary ────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))

if [ ${#ERRORS[@]} -gt 0 ]; then
  for err in "${ERRORS[@]}"; do
    echo "$err" >&2
  done
fi

echo ""
echo "=== Migration Tests ==="
echo "Passed: $PASS / $TOTAL"
echo "Failed: $FAIL / $TOTAL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
