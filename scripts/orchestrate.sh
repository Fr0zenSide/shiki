#!/usr/bin/env bash
# orchestrate.sh — Fallback layout script (prefer `shiki start` which handles this natively)
#
# Single-window layout: 80% orchestrator (left) + 20% sidebar (right)
# Sidebar: one pane per company + tiny heartbeat at bottom
#
# Usage:
#   bash scripts/orchestrate.sh

set -euo pipefail

SESSION="shiki-board"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
SHIKI_CTL="$WORKSPACE/tools/shiki-ctl"

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

# ── Build shiki-ctl if needed ────────────────────────────────────

if [ ! -f "$SHIKI_CTL/.build/debug/shiki-ctl" ]; then
  echo -e "${YELLOW}Building shiki-ctl...${RST}"
  (cd "$SHIKI_CTL" && swift build 2>&1 | tail -3)
fi

SHIKI_CTL_BIN="$SHIKI_CTL/.build/debug/shiki-ctl"

# ── Prefer shiki start (handles layout natively) ─────────────────

echo -e "${GREEN}Delegating to shiki start...${RST}"
exec "$SHIKI_CTL_BIN" start --workspace "$WORKSPACE"
