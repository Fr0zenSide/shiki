#!/usr/bin/env bash
# board-watch.sh — tmux pane companion for Claude Code agent monitoring
# Usage: bash board-watch.sh
# Alias: alias board-watch='tmux split-window -v -l 8 "bash /Users/jeoffrey/Documents/Workspaces/shiki/scripts/board-watch.sh"'

set -euo pipefail

INTERVAL="${BOARD_INTERVAL:-10}"
WORKTREE_DIR="/tmp/wt-*"
TASK_DIR="/private/tmp/claude-501/-Users-jeoffrey-Documents-Workspaces-shiki/tasks"
SPINNER_FRAMES=(⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷)
FRAME=0

# Colors
RST='\033[0m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'

cleanup() { printf '\033[?25h'; exit 0; }
trap cleanup SIGINT SIGTERM

# Hide cursor
printf '\033[?25l'

age_str() {
  local secs=$1
  if (( secs < 60 )); then echo "${secs}s"
  elif (( secs < 3600 )); then echo "$(( secs / 60 ))m"
  elif (( secs < 86400 )); then echo "$(( secs / 3600 ))h"
  else echo "$(( secs / 86400 ))d"; fi
}

while true; do
  clear
  NOW=$(date +%s)
  FRAME=$(( (FRAME + 1) % 8 ))
  SPIN="${SPINNER_FRAMES[$FRAME]}"

  # Header
  printf "${DIM}── ${RST}${BOLD}Board Watch${RST} ${DIM}── %s ──${RST}\n" "$(date +%H:%M:%S)"

  WT_COUNT=0
  RUNNING=0
  DONE=0
  FAILED=0

  # --- Worktrees ---
  for wt in $WORKTREE_DIR; do
    [ -d "$wt" ] || continue
    WT_COUNT=$(( WT_COUNT + 1 ))
    name="${wt##*/wt-}"
    branch=""
    if [ -d "$wt/.git" ] || [ -f "$wt/.git" ]; then
      branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
      last_epoch=$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo "$NOW")
      age=$(age_str $(( NOW - last_epoch )))
    else
      branch="?"
      age="?"
    fi
    printf " ${DIM}wt${RST} %-18s ${DIM}%s${RST} ${DIM}(%s)${RST}\n" "$name" "$branch" "$age"
  done

  # --- Tasks (running + recent < 1h only) ---
  MAX_AGE="${BOARD_MAX_AGE:-3600}"
  if [ -d "$TASK_DIR" ]; then
    for f in "$TASK_DIR"/*.output; do
      [ -f "$f" ] || continue
      fname="${f##*/}"
      fname="${fname%.output}"
      mod_epoch=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo "$NOW")
      stale=$(( NOW - mod_epoch ))
      # If modified within last 30s, consider running
      if (( stale < 30 )); then
        RUNNING=$(( RUNNING + 1 ))
        printf " ${YELLOW}${SPIN}${RST} %-28s ${YELLOW}running${RST}\n" "$fname"
      elif (( stale < MAX_AGE )); then
        # Only show completed tasks younger than MAX_AGE
        tail_line=$(tail -1 "$f" 2>/dev/null || echo "")
        if echo "$tail_line" | grep -qiE 'error|fail|panic|abort'; then
          FAILED=$(( FAILED + 1 ))
          printf " ${RED}✗${RST} %-28s ${RED}failed${RST} ${DIM}(%s)${RST}\n" "$fname" "$(age_str $stale)"
        else
          DONE=$(( DONE + 1 ))
          printf " ${GREEN}✓${RST} %-28s ${GREEN}done${RST} ${DIM}(%s)${RST}\n" "$fname" "$(age_str $stale)"
        fi
      fi
      # Older tasks silently counted for summary
    done
  fi

  # --- Companies (from Shiki DB) ---
  CO_COUNT=0
  CO_JSON=$(curl -sf http://localhost:3900/api/orchestrator/status 2>/dev/null || echo "")
  if [ -n "$CO_JSON" ] && command -v python3 &>/dev/null; then
    CO_LINES=$(echo "$CO_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ov = d.get('overview', {})
    companies = d.get('activeCompanies', [])
    stale = d.get('staleCompanies', [])
    stale_ids = {s['id'] for s in stale}
    locks = d.get('packageLocks', [])
    pending_dec = int(ov.get('t1_pending_decisions', 0))
    if companies:
        for c in companies:
            slug = c.get('slug', '?')
            budget = json.loads(c['budget']) if isinstance(c.get('budget'), str) else c.get('budget', {})
            spent = budget.get('spent_today_usd', 0)
            daily = budget.get('daily_usd', 0)
            pct = int(spent / daily * 100) if daily > 0 else 0
            hb = c.get('last_heartbeat_at')
            hb_str = 'never' if not hb else 'ok'
            if c['id'] in stale_ids:
                hb_str = 'STALE'
            status = c.get('status', '?')
            print(f'{slug}|{status}|{hb_str}|\${spent:.2f}/\${daily:.0f} ({pct}%)')
    if pending_dec > 0:
        print(f'DECISIONS|{pending_dec} T1 pending||')
    for lk in locks:
        print(f'LOCK|{lk.get(\"package_name\",\"?\")}|{lk.get(\"company_slug\",\"?\")}|')
except: pass
" 2>/dev/null)
    if [ -n "$CO_LINES" ]; then
      printf "${DIM}── ${RST}${BOLD}Companies${RST} ${DIM}──${RST}\n"
      while IFS='|' read -r slug status hb budget; do
        if [ "$slug" = "DECISIONS" ]; then
          printf " ${RED}!${RST} ${RED}%s${RST}\n" "$status"
        elif [ "$slug" = "LOCK" ]; then
          printf " ${YELLOW}⚿${RST} %-12s ${DIM}locked by %s${RST}\n" "$status" "$hb"
        else
          CO_COUNT=$(( CO_COUNT + 1 ))
          if [ "$hb" = "STALE" ]; then
            printf " ${RED}✗${RST} %-12s ${RED}stale${RST}  ${DIM}%s${RST}\n" "$slug" "$budget"
          elif [ "$status" = "paused" ]; then
            printf " ${YELLOW}⏸${RST} %-12s ${YELLOW}paused${RST} ${DIM}%s${RST}\n" "$slug" "$budget"
          else
            printf " ${GREEN}●${RST} %-12s ${GREEN}%s${RST}    ${DIM}%s${RST}\n" "$slug" "$hb" "$budget"
          fi
        fi
      done <<< "$CO_LINES"
    fi
  fi

  # --- Summary ---
  TASK_TOTAL=$(( RUNNING + DONE + FAILED ))
  if (( WT_COUNT == 0 && TASK_TOTAL == 0 && CO_COUNT == 0 )); then
    printf " ${DIM}no worktrees, tasks, or companies${RST}\n"
  fi
  SUMMARY="${WT_COUNT} worktree"
  (( WT_COUNT != 1 )) && SUMMARY+="s"
  SUMMARY+=" | ${RUNNING} running | ${DONE} done"
  (( FAILED > 0 )) && SUMMARY+=" | ${FAILED} failed"
  (( CO_COUNT > 0 )) && SUMMARY+=" | ${CO_COUNT} companies"
  printf "${DIM}── %s ──${RST}\n" "$SUMMARY"

  sleep "$INTERVAL"
done
