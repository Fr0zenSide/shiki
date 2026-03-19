#!/usr/bin/env bash
# orchestrate.sh — Launch the Shiki system: board layout + orchestrator
#
# v2: Dynamic dispatch. The board tab starts empty — HeartbeatLoop fills it
# dynamically as tasks are dispatched. No fixed panes per company.
#
# What it does:
#   1. Creates the tmux layout if not running (orchestrator + empty board + research)
#   2. Builds shiki-ctl (if needed)
#   3. Starts the heartbeat loop in the orchestrator tab
#
# Usage:
#   bash scripts/orchestrate.sh
#
# To start from scratch (fresh DB):
#   docker compose up -d
#   bash scripts/seed-companies.sh
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

# ── Create tmux layout if session doesn't exist ──────────────────

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "${GREEN}Creating Shiki Board layout...${RST}"

  # Tab 1: orchestrator
  tmux new-session -d -s "$SESSION" -n "orchestrator" -c "$WORKSPACE"

  # Tab 2: board (starts empty — HeartbeatLoop fills it dynamically)
  tmux new-window -t "$SESSION" -n "board" -c "$WORKSPACE"
  BOARD_WID=$(tmux list-windows -t "$SESSION" -F "#{window_id} #{window_name}" | grep board | awk '{print $1}')
  tmux set-option -w -t "$BOARD_WID" pane-border-status top
  tmux set-option -w -t "$BOARD_WID" pane-border-format " #{pane_title} "
  BOARD_PANE=$(tmux list-panes -t "$BOARD_WID" -F "#{pane_id}" | head -1)
  tmux select-pane -t "$BOARD_PANE" -T "DISPATCHER (waiting for tasks...)"

  # Tab 3: research (4 panes)
  RESEARCH_DIR="$WORKSPACE/projects/research"
  tmux new-window -t "$SESSION" -n "research" -c "$RESEARCH_DIR"
  RESEARCH_WID=$(tmux list-windows -t "$SESSION" -F "#{window_id} #{window_name}" | grep research | awk '{print $1}')
  tmux split-window -v -t "$RESEARCH_WID" -c "$RESEARCH_DIR"
  tmux split-window -v -t "$RESEARCH_WID" -c "$RESEARCH_DIR"
  tmux split-window -v -t "$RESEARCH_WID" -c "$RESEARCH_DIR"
  tmux select-layout -t "$RESEARCH_WID" tiled
  tmux set-option -w -t "$RESEARCH_WID" pane-border-status top
  tmux set-option -w -t "$RESEARCH_WID" pane-border-format " #{pane_title} "
  RESEARCH_PANES=($(tmux list-panes -t "$RESEARCH_WID" -F "#{pane_id}"))
  tmux select-pane -t "${RESEARCH_PANES[0]}" -T "INGEST"
  tmux select-pane -t "${RESEARCH_PANES[1]}" -T "RADAR"
  tmux select-pane -t "${RESEARCH_PANES[2]}" -T "EXPLORE"
  tmux select-pane -t "${RESEARCH_PANES[3]}" -T "SCRATCH"
fi

# ── Start orchestrator in tab 1 ─────────────────────────────────

echo -e "${GREEN}Starting orchestrator...${RST}"

ORCH_WID=$(tmux list-windows -t "$SESSION" -F "#{window_id} #{window_name}" | grep orchestrator | awk '{print $1}')
ORCH_PANE=$(tmux list-panes -t "$ORCH_WID" -F "#{pane_id}" | head -1)

# Check if something is already running
orch_cmd=$(tmux display-message -t "$ORCH_PANE" -p "#{pane_current_command}")
if [ "$orch_cmd" = "zsh" ] || [ "$orch_cmd" = "bash" ]; then
  tmux send-keys -t "$ORCH_PANE" "$SHIKI_CTL_BIN start --workspace $WORKSPACE" C-m
fi

# ── Select orchestrator tab ──────────────────────────────────────

tmux select-window -t "$SESSION:orchestrator"

echo
echo -e "${GREEN}Shiki system running!${RST}"
echo -e "${DIM}  Tab 1: orchestrator  → heartbeat loop (dispatches tasks dynamically)${RST}"
echo -e "${DIM}  Tab 2: board         → task sessions (appear as dispatched)${RST}"
echo -e "${DIM}  Tab 3: research      → ingest/radar/explore${RST}"
echo
echo -e "${DIM}Attach with: tmux attach -t $SESSION${RST}"
echo -e "${DIM}Navigate: Opt+Shift+←/→ (tabs) · Opt+←/↑/↓/→ (panes) · Ctrl-b+z (zoom)${RST}"

# Attach if not already in tmux
if [ -z "${TMUX:-}" ]; then
  tmux attach-session -t "$SESSION"
fi
