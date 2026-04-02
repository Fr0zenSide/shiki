#!/usr/bin/env bash
# tmux-checkpoint.sh — Save/restore tmux layout for crash recovery
# Checkpoint file: ~/.shikki/tmux-checkpoint.json
# Usage: tmux-checkpoint.sh [session] {save|restore|list|status}

set -euo pipefail

CHECKPOINT_DIR="${HOME}/.shikki"
CHECKPOINT_FILE="${CHECKPOINT_DIR}/tmux-checkpoint.json"
CHECKPOINT_HISTORY="${CHECKPOINT_DIR}/tmux-checkpoint-history"
MAX_HISTORY=5
SESSION_NAME="${1:-shiki}"

mkdir -p "$CHECKPOINT_DIR" "$CHECKPOINT_HISTORY"

# --- SAVE ---
save_layout() {
    local session="$1"

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "Session '$session' not found" >&2
        return 1
    fi

    # Dump all tmux state in a single pass, then let Python build JSON
    local windows_raw panes_raw
    windows_raw=$(tmux list-windows -t "$session" -F "#{window_index}||#{window_name}||#{window_layout}||#{window_active}")
    panes_raw=$(tmux list-panes -a -t "$session" -F "#{window_index}||#{pane_index}||#{pane_current_path}||#{pane_current_command}||#{pane_active}||#{pane_width}||#{pane_height}")

    local tmp_file="${CHECKPOINT_FILE}.tmp"

    python3 << 'PYEOF' - "$session" "$tmp_file" "$windows_raw" "$panes_raw"
import json, sys
from datetime import datetime, timezone

_, session, tmp_file, windows_raw, panes_raw = sys.argv

# Parse panes
panes_by_win = {}
for line in panes_raw.strip().split("\n"):
    if not line:
        continue
    parts = line.split("||")
    win_idx = int(parts[0])
    panes_by_win.setdefault(win_idx, []).append({
        "index": int(parts[1]),
        "cwd": parts[2],
        "command": parts[3],
        "active": parts[4] == "1",
        "width": int(parts[5]),
        "height": int(parts[6]),
    })

# Parse windows
windows = []
for line in windows_raw.strip().split("\n"):
    if not line:
        continue
    parts = line.split("||")
    win_idx = int(parts[0])
    windows.append({
        "index": win_idx,
        "name": parts[1],
        "layout": parts[2],
        "active": parts[3] == "1",
        "panes": panes_by_win.get(win_idx, []),
    })

checkpoint = {
    "version": 1,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "session": session,
    "windows": windows,
}

with open(tmp_file, "w") as f:
    json.dump(checkpoint, f, indent=2)

print(f"Saved checkpoint: {len(windows)} windows @ {checkpoint['timestamp']}")
PYEOF

    mv "$tmp_file" "$CHECKPOINT_FILE"

    # Keep history (rotate last N)
    cp "$CHECKPOINT_FILE" "${CHECKPOINT_HISTORY}/checkpoint-$(date +%Y%m%d-%H%M%S).json"
    ls -t "${CHECKPOINT_HISTORY}"/checkpoint-*.json 2>/dev/null | tail -n +$((MAX_HISTORY + 1)) | xargs rm -f 2>/dev/null || true
}

# --- RESTORE ---
restore_layout() {
    local session="$1"
    local checkpoint_file="${2:-$CHECKPOINT_FILE}"

    if [ ! -f "$checkpoint_file" ]; then
        echo "No checkpoint found at $checkpoint_file" >&2
        return 1
    fi

    echo "Restoring from: $checkpoint_file"

    # Get existing window names
    local existing=""
    if tmux has-session -t "$session" 2>/dev/null; then
        existing=$(tmux list-windows -t "$session" -F "#{window_name}" | tr '\n' '|')
    fi

    python3 << 'PYEOF' - "$session" "$checkpoint_file" "$existing"
import json, subprocess, sys, os

_, session, checkpoint_file, existing_str = sys.argv
existing = set(existing_str.strip("|").split("|")) if existing_str else set()

with open(checkpoint_file) as f:
    cp = json.load(f)

print(f"Checkpoint from {cp['timestamp']}: {len(cp['windows'])} windows")

for win in cp["windows"]:
    name = win["name"]
    if name in existing:
        print(f"  Skip {name} (already exists)")
        continue

    cwd = win["panes"][0]["cwd"] if win.get("panes") else os.path.expanduser("~")
    if not os.path.isdir(cwd):
        cwd = os.path.expanduser("~")

    subprocess.run(["tmux", "new-window", "-t", session, "-n", name, "-c", cwd])
    print(f"  Restored window: {name} @ {cwd}")

print("Layout restored.")
PYEOF
}

# --- LIST ---
list_history() {
    if [ ! -d "$CHECKPOINT_HISTORY" ]; then
        echo "No checkpoint history" >&2
        return 1
    fi

    echo "Checkpoint history:"
    for f in $(ls -t "${CHECKPOINT_HISTORY}"/checkpoint-*.json 2>/dev/null); do
        python3 -c "
import json
cp = json.load(open('$f'))
print(f\"  $(basename $f) — {len(cp['windows'])} windows @ {cp['timestamp']}\")
" 2>/dev/null || echo "  $(basename "$f") — (corrupt)"
    done
}

# --- STATUS ---
status() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        python3 -c "
import json
cp = json.load(open('$CHECKPOINT_FILE'))
print(f\"Last checkpoint: {len(cp['windows'])} windows @ {cp['timestamp']}\")
for w in cp['windows']:
    active = ' *' if w.get('active') else ''
    pane_count = len(w.get('panes', []))
    print(f\"  {w['index']}: {w['name']} ({pane_count} panes){active}\")
"
    else
        echo "No checkpoint saved yet"
    fi
}

# --- CLI ---
case "${2:-save}" in
    save)    save_layout "$SESSION_NAME" ;;
    restore) restore_layout "$SESSION_NAME" "${3:-}" ;;
    list)    list_history ;;
    status)  status ;;
    *)       echo "Usage: $0 [session] {save|restore|list|status}" >&2; exit 1 ;;
esac
