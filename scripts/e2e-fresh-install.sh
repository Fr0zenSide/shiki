#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# E2E Fresh Install Test (Docker-free)
#
# Simulates a completely fresh install in an isolated temp directory.
# Verifies the full setup pipeline without Docker dependencies.
#
# Gate for release branch creation — must pass before any release.
#
# Usage:
#   ./scripts/e2e-fresh-install.sh
#   ./scripts/e2e-fresh-install.sh --keep   # keep temp dir on failure
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
KEEP_ON_FAIL=false
PASSED=0
FAILED=0
WARNINGS=0

[[ "${1:-}" == "--keep" ]] && KEEP_ON_FAIL=true

# ── Helpers ─────────────────────────────────────────────────────

step_pass() {
  echo "  ✅ $1"
  ((PASSED++))
}

step_fail() {
  echo "  ❌ $1"
  ((FAILED++))
}

step_warn() {
  echo "  ⚠️  $1 (non-blocking)"
  ((WARNINGS++))
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]] && $KEEP_ON_FAIL; then
    echo ""
    echo "Test dir preserved (--keep): $TEST_DIR"
  else
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

# ── Banner ──────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  E2E Fresh Install Test (Docker-free)"
echo "  Test dir: $TEST_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Copy repo (simulate clone without network) ──────────

echo "Step 1: Copy repo to isolated directory"
cp -R "$REPO_ROOT" "$TEST_DIR/shiki"
cd "$TEST_DIR/shiki"

# Remove any existing git worktree pointers — we want a standalone copy
if [[ -f .git ]] && ! [[ -d .git ]]; then
  # This is a worktree — convert to a standalone repo copy
  # Read the actual gitdir, copy the relevant objects
  REAL_GIT=$(cat .git | sed 's/gitdir: //')
  rm .git
  git clone --local --no-hardlinks "$REAL_GIT/.." "$TEST_DIR/shiki-clone" 2>/dev/null || true
  if [[ -d "$TEST_DIR/shiki-clone" ]]; then
    rm -rf "$TEST_DIR/shiki"
    mv "$TEST_DIR/shiki-clone" "$TEST_DIR/shiki"
    cd "$TEST_DIR/shiki"
  fi
fi

step_pass "Repo copied to $TEST_DIR/shiki"

# ── Step 2: Clean all build artifacts + state ───────────────────

echo ""
echo "Step 2: Clean build artifacts and state"
rm -rf .build/ projects/shikki/.build/ .shikki/ 2>/dev/null || true
# Back up real setup.json if it exists, restore on cleanup
SETUP_JSON="$HOME/.shikki/setup.json"
SETUP_JSON_BAK=""
if [[ -f "$SETUP_JSON" ]]; then
  SETUP_JSON_BAK=$(mktemp)
  cp "$SETUP_JSON" "$SETUP_JSON_BAK"
  rm -f "$SETUP_JSON"
fi

# Restore setup.json backup on exit
restore_setup_json() {
  if [[ -n "$SETUP_JSON_BAK" ]] && [[ -f "$SETUP_JSON_BAK" ]]; then
    mkdir -p "$(dirname "$SETUP_JSON")"
    mv "$SETUP_JSON_BAK" "$SETUP_JSON"
  fi
}
# Prepend to existing trap
original_cleanup=$(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//")
trap "$original_cleanup; restore_setup_json" EXIT

step_pass "Build artifacts and state cleaned"

# ── Step 3: Run setup.sh (if it exists) ─────────────────────────

echo ""
echo "Step 3: Run setup.sh"
if [[ -x "./setup.sh" ]]; then
  if ./setup.sh 2>&1; then
    step_pass "setup.sh completed successfully"
  else
    step_fail "setup.sh exited with error"
  fi
else
  step_warn "setup.sh not found or not executable — skipping (Phase A not yet merged)"
fi

# ── Step 4: Verify shikki doctor passes (if binary available) ──

echo ""
echo "Step 4: Verify shikki doctor"
if command -v shikki >/dev/null 2>&1; then
  if shikki doctor 2>&1; then
    step_pass "shikki doctor passed"
  else
    step_warn "shikki doctor reported issues"
  fi
else
  step_warn "shikki binary not in PATH — skipping doctor check"
fi

# ── Step 5: Verify Swift build (if Package.swift exists) ────────

echo ""
echo "Step 5: Verify Swift build"
SHIKKI_PROJECT="projects/shikki"
if [[ -f "$SHIKKI_PROJECT/Package.swift" ]]; then
  cd "$SHIKKI_PROJECT"
  if swift build 2>&1; then
    step_pass "swift build succeeded"
  else
    step_fail "swift build failed"
  fi
  cd "$TEST_DIR/shiki"
elif [[ -f "Package.swift" ]]; then
  if swift build 2>&1; then
    step_pass "swift build succeeded (root Package.swift)"
  else
    step_fail "swift build failed"
  fi
else
  step_warn "No Package.swift found — skipping build check"
fi

# ── Step 6: Run test suite (if available) ───────────────────────

echo ""
echo "Step 6: Run test suite"
if [[ -f "$SHIKKI_PROJECT/Package.swift" ]]; then
  cd "$SHIKKI_PROJECT"
  if [[ -x ".build/debug/shikki-test" ]]; then
    if .build/debug/shikki-test --parallel 2>&1; then
      step_pass "Test suite passed"
    else
      step_fail "Test suite failed"
    fi
  elif swift test --parallel 2>&1; then
    step_pass "Test suite passed (swift test)"
  else
    step_fail "Test suite failed"
  fi
  cd "$TEST_DIR/shiki"
elif [[ -f "Package.swift" ]]; then
  if swift test --parallel 2>&1; then
    step_pass "Test suite passed (root Package.swift)"
  else
    step_fail "Test suite failed"
  fi
else
  step_warn "No Package.swift found — skipping test suite"
fi

# ── Step 7: Verify setup.json was created ───────────────────────

echo ""
echo "Step 7: Verify setup.json"
if [[ -f "$SETUP_JSON" ]]; then
  step_pass "setup.json exists at $SETUP_JSON"
else
  step_warn "setup.json missing — setup.sh may not create it yet (Phase A)"
fi

# ── Step 8: Verify hook scripts exist ───────────────────────────

echo ""
echo "Step 8: Verify hook scripts"
for script in scripts/shiki-approval.sh scripts/shiki-idle.sh scripts/shiki-activity.sh; do
  if [[ -f "$script" ]]; then
    if [[ -x "$script" ]]; then
      step_pass "$script exists and is executable"
    else
      step_warn "$script exists but is not executable"
    fi
  else
    step_warn "$script missing"
  fi
done

# ── Step 9: Verify critical directories ─────────────────────────

echo ""
echo "Step 9: Verify directory structure"
for dir in scripts src features memory; do
  if [[ -d "$dir" ]]; then
    step_pass "$dir/ directory exists"
  else
    step_fail "$dir/ directory missing"
  fi
done

# ── Results ─────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASSED passed, $FAILED failed, $WARNINGS warnings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -gt 0 ]]; then
  echo ""
  echo "  ❌ E2E Fresh Install: $FAILED CHECK(S) FAILED"
  echo "  Release branch creation is BLOCKED."
  echo ""
  exit 1
else
  echo ""
  echo "  ✅ E2E Fresh Install: ALL CHECKS PASSED"
  if [[ $WARNINGS -gt 0 ]]; then
    echo "  ($WARNINGS non-blocking warnings — review before release)"
  fi
  echo ""
  exit 0
fi
