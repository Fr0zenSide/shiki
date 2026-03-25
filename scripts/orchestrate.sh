#!/usr/bin/env bash
# orchestrate.sh — Fallback layout script (prefer `shikki start` which handles this natively)
#
# Single-window layout: 80% orchestrator (left) + 20% sidebar (right)
# Sidebar: one pane per company + tiny heartbeat at bottom
#
# Usage:
#   bash scripts/orchestrate.sh

set -euo pipefail

SESSION="shikki-board"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
SHIKKI_DIR="$WORKSPACE/projects/shikki"

GREEN='\033[32m'
DIM='\033[2m'
YELLOW='\033[33m'
RST='\033[0m'

# ── Check prerequisites ──────────────────────────────────────────

if ! command -v tmux &>/dev/null; then
  echo "Error: tmux is not installed"; exit 1
fi

if ! curl -sf http://localhost:3900/health >/dev/null 2>&1; then
  echo "Error: Backend unreachable at localhost:3900"
  echo "Start it with: docker compose up -d"
  exit 1
fi

# ── Build shikki if needed ────────────────────────────────────

if [ ! -f "$SHIKKI_DIR/.build/debug/shikki" ]; then
  echo -e "${YELLOW}Building shikki...${RST}"
  (cd "$SHIKKI_DIR" && swift build 2>&1 | tail -3)
fi

SHIKKI_BIN="$SHIKKI_DIR/.build/debug/shikki"

# ── Prefer shikki start (handles layout natively) ─────────────────

echo -e "${GREEN}Delegating to shikki start...${RST}"
exec "$SHIKKI_BIN" start --workspace "$WORKSPACE"
