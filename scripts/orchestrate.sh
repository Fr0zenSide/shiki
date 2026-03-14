#!/usr/bin/env bash
# orchestrate.sh — Launch the Shiki orchestrator tmux layout
# Usage: bash scripts/orchestrate.sh
#
# Creates tmux session "shiki-board" with:
#   - Main pane: orchestrator Claude session
#   - Bottom pane: board-watch.sh (live status monitor)

set -euo pipefail

SESSION="shiki-board"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
BOARD_WATCH="$WORKSPACE/scripts/board-watch.sh"

# Colors
GREEN='\033[32m'
DIM='\033[2m'
RST='\033[0m'

# Check prerequisites
if ! command -v tmux &>/dev/null; then
  echo "Error: tmux is not installed"
  exit 1
fi

if ! curl -sf http://localhost:3900/health >/dev/null 2>&1; then
  echo "Warning: Shiki DB not reachable at localhost:3900"
  echo "Start it with: docker compose up -d"
fi

# Kill existing session if running
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "${DIM}Existing session found. Attaching...${RST}"
  tmux attach-session -t "$SESSION"
  exit 0
fi

echo -e "${GREEN}Launching Shiki Orchestrator${RST}"
echo -e "${DIM}Session: $SESSION${RST}"
echo -e "${DIM}Workspace: $WORKSPACE${RST}"

# Create session with main orchestrator pane
tmux new-session -d -s "$SESSION" -n "orchestrator" -c "$WORKSPACE"

# Set the main pane to launch Claude as orchestrator
tmux send-keys -t "$SESSION:orchestrator" \
  "claude '/orchestrate start'" Enter

# Split bottom pane for board-watch
tmux split-window -t "$SESSION:orchestrator" -v -l 10 -c "$WORKSPACE"
tmux send-keys -t "$SESSION:orchestrator.1" \
  "bash '$BOARD_WATCH'" Enter

# Select the main pane
tmux select-pane -t "$SESSION:orchestrator.0"

# Attach
echo -e "${GREEN}Attaching to $SESSION...${RST}"
tmux attach-session -t "$SESSION"
