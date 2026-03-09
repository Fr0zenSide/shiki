#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# shiki-notify-lib.sh — Shared helpers for Shiki notification scripts
# ─────────────────────────────────────────────────────────────

# Build workspace context tag for notification titles
# - Worktree on branch → [WS:branch-name]
# - Different folder than "shiki" → [FolderName]
# - Shiki root → empty string
shiki_workspace_tag() {
  local folder_name
  folder_name=$(basename "$(pwd)")
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null || echo "")

  if [[ "$git_dir" == *"/worktrees/"* ]]; then
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ -n "$branch" ]]; then
      echo "[WS:${branch}]"
    else
      echo "[WS:${folder_name}]"
    fi
  elif [[ "$folder_name" != "shiki" ]]; then
    echo "[${folder_name}]"
  fi
}
