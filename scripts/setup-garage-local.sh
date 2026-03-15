#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# setup-garage-local.sh — Bootstrap Garage S3 for local dev
#
# Run after `docker compose up -d` to configure the single-node
# Garage instance with layout, buckets, and an API key.
#
# Usage:
#   ./scripts/setup-garage-local.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/deploy/.env"

# ── Ensure deploy/.env exists ────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "deploy/.env not found — creating from deploy/example.env..."
  cp "${REPO_ROOT}/deploy/example.env" "$ENV_FILE"
  echo ""
  echo "  IMPORTANT: Edit deploy/.env with real secrets before running docker compose."
  echo "  Generate an RPC secret:  openssl rand -hex 32"
  echo ""
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}▸${NC} $1"; }
warn() { echo -e "${YELLOW}▸${NC} $1"; }
err()  { echo -e "${RED}▸${NC} $1" >&2; }
step() { echo -e "${BOLD}═══ $1${NC}"; }

CONTAINER="shiki-garage-1"
GARAGE="docker exec ${CONTAINER} /garage"

# ── Wait for Garage to be healthy ──────────────────────────
step "Waiting for Garage to be healthy..."

retries=30
while [ $retries -gt 0 ]; do
  if docker exec "${CONTAINER}" /garage status &>/dev/null; then
    break
  fi
  retries=$((retries - 1))
  sleep 2
done

if [ $retries -eq 0 ]; then
  err "Garage did not become healthy after 60s"
  err "Check: docker logs ${CONTAINER}"
  exit 1
fi
log "Garage is healthy"

# ── Assign layout (single node) ───────────────────────────
step "Configuring layout..."

NODE_ID=$($GARAGE status 2>/dev/null | grep -oE '^[a-f0-9]+' | head -1)
if [ -z "$NODE_ID" ]; then
  err "Could not determine Garage node ID"
  exit 1
fi

$GARAGE layout assign "$NODE_ID" -z dc1 -c 1G -t local 2>/dev/null || true

# Apply layout (get next version)
LAYOUT_VERSION=$($GARAGE layout show 2>/dev/null | grep -Eo 'version [0-9]+' | grep -Eo '[0-9]+' | tail -1 || echo "1")
$GARAGE layout apply --version "$LAYOUT_VERSION" 2>/dev/null || true

log "Layout applied for node ${NODE_ID:0:8}..."

# ── Create buckets ────────────────────────────────────────
step "Creating buckets..."

for bucket in maya-photos wabisabi-photos; do
  $GARAGE bucket create "$bucket" 2>/dev/null || true
  log "Bucket: ${bucket}"
done

# ── Create API key ────────────────────────────────────────
step "Creating API key..."

EXISTING=$($GARAGE key list 2>/dev/null | grep "dev-local" || true)
if [ -z "$EXISTING" ]; then
  echo ""
  $GARAGE key create dev-local

  # Grant access
  for bucket in maya-photos wabisabi-photos; do
    $GARAGE bucket allow --read --write --key dev-local "$bucket"
  done

  echo ""
  log "API key 'dev-local' created with read/write on both buckets"
  warn "Copy the Access Key ID and Secret Key above into your .env"
else
  log "API key 'dev-local' already exists"
  $GARAGE key info dev-local 2>/dev/null || true
fi

# ── Summary ───────────────────────────────────────────────
echo ""
step "Garage S3 ready for local dev"
echo ""
echo "  S3 endpoint:  http://localhost:3902"
echo "  Admin API:    http://localhost:3903"
echo "  Buckets:      maya-photos, wabisabi-photos"
echo "  Region:       garage"
echo ""
echo "  Test with:"
echo "    aws --endpoint-url http://localhost:3902 s3 ls"
echo ""
