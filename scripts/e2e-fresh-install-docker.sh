#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# E2E Fresh Install Test (with Docker)
#
# Extended version of e2e-fresh-install.sh that also verifies the
# full Docker stack: database, backend, frontend, and seed data.
#
# Requires: Docker (Colima or Docker Desktop) running.
#
# Gate for release branch creation — must pass before any release.
#
# Usage:
#   ./scripts/e2e-fresh-install-docker.sh
#   ./scripts/e2e-fresh-install-docker.sh --keep   # keep temp dir on failure
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
KEEP_ON_FAIL=false
PASSED=0
FAILED=0
WARNINGS=0
DOCKER_UP=false

# Backend uses deno — no curl in the image. Healthcheck must use deno eval.
BACKEND_URL="http://localhost:3900"
FRONTEND_URL="http://localhost:5174"
HEALTH_TIMEOUT=120  # seconds to wait for services to become healthy

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

# Wait for a URL to respond with HTTP 200
wait_for_url() {
  local url="$1" label="$2" timeout="$3"
  local elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    local status
    status=$(curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [[ "$status" == "200" ]]; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    # Progress dot every 10s
    if (( elapsed % 10 == 0 )); then
      echo "    ... waiting for $label (${elapsed}s / ${timeout}s)"
    fi
  done
  return 1
}

docker_cleanup() {
  if $DOCKER_UP; then
    echo ""
    echo "Cleaning up Docker stack..."
    cd "$TEST_DIR/shiki"
    docker compose down -v --remove-orphans 2>/dev/null || true
  fi
}

cleanup() {
  local exit_code=$?
  docker_cleanup
  if [[ $exit_code -ne 0 ]] && $KEEP_ON_FAIL; then
    echo ""
    echo "Test dir preserved (--keep): $TEST_DIR"
  else
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

# ── Pre-flight: Docker available? ───────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  E2E Fresh Install Test (with Docker)"
echo "  Test dir: $TEST_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Pre-flight: Docker availability"
if ! command -v docker >/dev/null 2>&1; then
  echo ""
  echo "  ❌ Docker not found. This test requires Docker."
  echo "  Run the Docker-free variant instead: ./scripts/e2e-fresh-install.sh"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo ""
  echo "  ❌ Docker daemon not running. Start Colima or Docker Desktop first."
  echo "  Run the Docker-free variant instead: ./scripts/e2e-fresh-install.sh"
  exit 1
fi
step_pass "Docker is available and running"

# ── Step 1: Copy repo ──────────────────────────────────────────

echo ""
echo "Step 1: Copy repo to isolated directory"
cp -R "$REPO_ROOT" "$TEST_DIR/shiki"
cd "$TEST_DIR/shiki"

# Handle worktree → standalone conversion
if [[ -f .git ]] && ! [[ -d .git ]]; then
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
SETUP_JSON="$HOME/.shikki/setup.json"
SETUP_JSON_BAK=""
if [[ -f "$SETUP_JSON" ]]; then
  SETUP_JSON_BAK=$(mktemp)
  cp "$SETUP_JSON" "$SETUP_JSON_BAK"
  rm -f "$SETUP_JSON"
fi

restore_setup_json() {
  if [[ -n "$SETUP_JSON_BAK" ]] && [[ -f "$SETUP_JSON_BAK" ]]; then
    mkdir -p "$(dirname "$SETUP_JSON")"
    mv "$SETUP_JSON_BAK" "$SETUP_JSON"
  fi
}
original_cleanup=$(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//")
trap "$original_cleanup; restore_setup_json" EXIT

step_pass "Build artifacts and state cleaned"

# ── Step 3: Run setup.sh ───────────────────────────────────────

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

# ── Step 4: Verify shikki doctor ───────────────────────────────

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

# ── Step 5: Verify Swift build ─────────────────────────────────

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

# ── Step 6: Run test suite ─────────────────────────────────────

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

# ── Step 7: Verify setup.json ─────────────────────────────────

echo ""
echo "Step 7: Verify setup.json"
if [[ -f "$SETUP_JSON" ]]; then
  step_pass "setup.json exists at $SETUP_JSON"
else
  step_warn "setup.json missing — setup.sh may not create it yet (Phase A)"
fi

# ── Step 8: Verify hook scripts ────────────────────────────────

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

# ── Step 9: Verify directory structure ─────────────────────────

echo ""
echo "Step 9: Verify directory structure"
for dir in scripts src features memory; do
  if [[ -d "$dir" ]]; then
    step_pass "$dir/ directory exists"
  else
    step_fail "$dir/ directory missing"
  fi
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Docker-specific steps (Steps 10-14)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Docker Stack Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 10: Create .env and start Docker stack ─────────────────

echo ""
echo "Step 10: Start Docker stack"

# Create .env from example if it doesn't exist
if [[ ! -f .env ]] && [[ -f .env.example ]]; then
  cp .env.example .env
  # Set a real password for the test run
  sed -i.bak 's/change_me_please_use_a_real_password/e2e_test_password_$(date +%s)/' .env 2>/dev/null || \
    sed -i '' "s/change_me_please_use_a_real_password/e2e_test_password_$(date +%s)/" .env
  rm -f .env.bak
fi

# Apply override if it exists (for LM Studio instead of Ollama)
if [[ -f docker-compose.override.yml ]]; then
  echo "    (using docker-compose.override.yml)"
fi

if docker compose up -d 2>&1; then
  DOCKER_UP=true
  step_pass "docker compose up -d succeeded"
else
  step_fail "docker compose up -d failed"
  # Skip remaining Docker steps
  echo ""
  echo "  Skipping remaining Docker checks (stack failed to start)"
  echo ""
  # Jump to results
  FAILED=$((FAILED + 3))  # Count skipped Docker checks as failures
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Results: $PASSED passed, $FAILED failed, $WARNINGS warnings"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  ❌ E2E Fresh Install (Docker): FAILED"
  exit 1
fi

# ── Step 11: Verify backend healthcheck ─────────────────────────

echo ""
echo "Step 11: Verify backend healthcheck"
echo "    Waiting for backend at $BACKEND_URL/health ..."

if wait_for_url "$BACKEND_URL/health" "backend" "$HEALTH_TIMEOUT"; then
  step_pass "Backend healthcheck passed ($BACKEND_URL/health)"
else
  step_fail "Backend healthcheck failed (timeout after ${HEALTH_TIMEOUT}s)"
  echo "    Docker logs (backend, last 20 lines):"
  docker compose logs backend --tail=20 2>/dev/null || true
fi

# ── Step 12: Verify frontend starts ────────────────────────────

echo ""
echo "Step 12: Verify frontend starts"
echo "    Waiting for frontend at $FRONTEND_URL ..."

if wait_for_url "$FRONTEND_URL" "frontend" "$HEALTH_TIMEOUT"; then
  step_pass "Frontend is reachable ($FRONTEND_URL)"
else
  step_fail "Frontend unreachable (timeout after ${HEALTH_TIMEOUT}s)"
  echo "    Docker logs (frontend, last 20 lines):"
  docker compose logs frontend --tail=20 2>/dev/null || true
fi

# ── Step 13: Verify seed-companies (if script exists) ──────────

echo ""
echo "Step 13: Verify seed-companies"
SEED_SCRIPT=""
for candidate in scripts/seed-companies.sh seed-companies.sh src/db/seed-companies.sh; do
  if [[ -f "$candidate" ]]; then
    SEED_SCRIPT="$candidate"
    break
  fi
done

if [[ -n "$SEED_SCRIPT" ]]; then
  if bash "$SEED_SCRIPT" 2>&1; then
    step_pass "seed-companies completed ($SEED_SCRIPT)"
  else
    step_fail "seed-companies failed ($SEED_SCRIPT)"
  fi
else
  # Try seeding via API if no script exists
  SEED_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST "$BACKEND_URL/api/companies/seed" 2>/dev/null || echo "000")
  if [[ "$SEED_STATUS" == "200" ]] || [[ "$SEED_STATUS" == "201" ]]; then
    step_pass "seed-companies via API ($BACKEND_URL/api/companies/seed)"
  else
    step_warn "No seed-companies script or API endpoint found — skipping"
  fi
fi

# ── Step 14: Verify Docker service health summary ──────────────

echo ""
echo "Step 14: Docker service health summary"
UNHEALTHY=0
while IFS= read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  health=$(echo "$line" | awk '{print $2}')
  if [[ "$health" == "healthy" ]]; then
    step_pass "Service $name: healthy"
  elif [[ "$health" == "running" ]]; then
    step_warn "Service $name: running (no healthcheck defined)"
  else
    step_fail "Service $name: $health"
    ((UNHEALTHY++))
  fi
done < <(docker compose ps --format '{{.Name}} {{.Health}}' 2>/dev/null || docker compose ps 2>/dev/null | tail -n +2 | awk '{print $1, "unknown"}')

if [[ $UNHEALTHY -eq 0 ]]; then
  step_pass "All Docker services healthy"
fi

# ── Results ─────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASSED passed, $FAILED failed, $WARNINGS warnings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -gt 0 ]]; then
  echo ""
  echo "  ❌ E2E Fresh Install (Docker): $FAILED CHECK(S) FAILED"
  echo "  Release branch creation is BLOCKED."
  echo ""
  exit 1
else
  echo ""
  echo "  ✅ E2E Fresh Install (Docker): ALL CHECKS PASSED"
  if [[ $WARNINGS -gt 0 ]]; then
    echo "  ($WARNINGS non-blocking warnings — review before release)"
  fi
  echo ""
  exit 0
fi
