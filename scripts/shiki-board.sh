#!/usr/bin/env bash
# shiki-board.sh — Launch the Shiki orchestrator tmux layout
#
# v2: Dynamic dispatch. Board tab starts empty — HeartbeatLoop fills it.
#
# Layout:
#   Tab 1 (orchestrator): shiki-ctl heartbeat loop — dispatches tasks dynamically
#   Tab 2 (board):        Dynamic panes — appear/disappear as tasks start/complete
#   Tab 3 (research):     4-pane grid — Ingest, Radar, Explore, Scratch
#
# Navigation:
#   Opt+Shift+←/→   switch tabs
#   Opt+←/↑/↓/→     switch panes within a tab
#   Ctrl-b + z       zoom/unzoom a pane
#
# Usage:
#   bash scripts/shiki-board.sh           # create layout
#   bash scripts/shiki-board.sh --attach  # just attach if session exists

set -euo pipefail

SESSION="shiki-board"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
RESEARCH_DIR="$WORKSPACE/projects/research"

GREEN='\033[32m'
DIM='\033[2m'
RST='\033[0m'

# ── Attach to existing session if running ─────────────────────────

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "${DIM}Session '$SESSION' already running. Attaching...${RST}"
  tmux attach-session -t "$SESSION"
  exit 0
fi

# ── Check prerequisites ──────────────────────────────────────────

if ! command -v tmux &>/dev/null; then
  echo "Error: tmux is not installed"
  exit 1
fi

if ! curl -sf http://localhost:3900/health >/dev/null 2>&1; then
  echo "Warning: Shiki backend not reachable at localhost:3900"
  echo "Start it with: docker compose up -d"
fi

echo -e "${GREEN}Launching Shiki Board${RST}"
echo -e "${DIM}Session:   $SESSION${RST}"
echo -e "${DIM}Workspace: $WORKSPACE${RST}"
echo

# ── Tab 1: Orchestrator ──────────────────────────────────────────

tmux new-session -d -s "$SESSION" -n "orchestrator" -c "$WORKSPACE"

# ── Tab 2: Board (starts empty — dynamic panes) ──────────────────

tmux new-window -t "$SESSION" -n "board" -c "$WORKSPACE"
BOARD_WID=$(tmux list-windows -t "$SESSION" -F "#{window_id} #{window_name}" | grep board | awk '{print $1}')
tmux set-option -w -t "$BOARD_WID" pane-border-status top
tmux set-option -w -t "$BOARD_WID" pane-border-format " #{pane_title} "
BOARD_PANE=$(tmux list-panes -t "$BOARD_WID" -F "#{pane_id}" | head -1)
tmux select-pane -t "$BOARD_PANE" -T "DISPATCHER (waiting for tasks...)"

# ── Tab 3: Research (4 panes in research project) ────────────────

tmux new-window -t "$SESSION" -n "research" -c "$RESEARCH_DIR"

RESEARCH_WID=$(tmux list-windows -t "$SESSION" -F "#{window_id} #{window_name}" | grep research | awk '{print $1}')

tmux split-window -v -t "$RESEARCH_WID" -c "$RESEARCH_DIR"
tmux split-window -v -t "$RESEARCH_WID" -c "$RESEARCH_DIR"
tmux split-window -v -t "$RESEARCH_WID" -c "$RESEARCH_DIR"
tmux select-layout -t "$RESEARCH_WID" tiled

# Label panes
tmux set-option -w -t "$RESEARCH_WID" pane-border-status top
tmux set-option -w -t "$RESEARCH_WID" pane-border-format " #{pane_title} "
RESEARCH_PANES=($(tmux list-panes -t "$RESEARCH_WID" -F "#{pane_id}"))
tmux select-pane -t "${RESEARCH_PANES[0]}" -T "INGEST"
tmux select-pane -t "${RESEARCH_PANES[1]}" -T "RADAR"
tmux select-pane -t "${RESEARCH_PANES[2]}" -T "EXPLORE"
tmux select-pane -t "${RESEARCH_PANES[3]}" -T "SCRATCH"

# ── Select orchestrator tab and attach ───────────────────────────

tmux select-window -t "$SESSION:orchestrator"

echo -e "${GREEN}Shiki Board ready${RST}"
echo -e "${DIM}  Tab 1: orchestrator  (heartbeat loop — dispatches tasks)${RST}"
echo -e "${DIM}  Tab 2: board         (dynamic task sessions)${RST}"
echo -e "${DIM}  Tab 3: research      (ingest/radar/explore)${RST}"
echo

tmux attach-session -t "$SESSION"
