#!/usr/bin/env bash
# worktree-setup.sh — Resolve local SPM dependencies for git worktrees
#
# When a worktree is created at /tmp/wt-foo/, relative paths like
# ../../packages/CoreKit no longer resolve. This script rewrites
# Package.swift to use absolute paths to the real shiki workspace.
#
# Usage:
#   scripts/worktree-setup.sh <worktree-path>
#
# What it does:
# 1. Parses Package.swift for .package(path: "../../...") references
# 2. Resolves each to absolute path in the shiki workspace
# 3. Rewrites Package.swift with absolute paths (worktree-only, not committed)
# 4. Runs swift package resolve to verify
#
# The worktree's Package.swift is a local-only modification — git won't
# track it because worktrees have their own working tree state.

set -euo pipefail

SHIKI_ROOT="/Users/jeoffrey/Documents/Workspaces/shiki"
WORKTREE_PATH="${1:?Usage: worktree-setup.sh <worktree-path>}"

# Resolve to absolute path
WORKTREE_PATH="$(cd "$WORKTREE_PATH" 2>/dev/null && pwd || echo "$WORKTREE_PATH")"

if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree path does not exist: $WORKTREE_PATH"
    exit 1
fi

echo "=== Worktree SPM Setup ==="
echo "Worktree: $WORKTREE_PATH"
echo "Shiki root: $SHIKI_ROOT"

# Parse Package.swift for local path dependencies
PACKAGE_SWIFT="$WORKTREE_PATH/Package.swift"
if [[ ! -f "$PACKAGE_SWIFT" ]]; then
    echo "No Package.swift found in worktree. Nothing to do."
    exit 0
fi

# Check if there are any local path dependencies to fix
if ! grep -q 'path: "\.\.' "$PACKAGE_SWIFT"; then
    echo "No relative parent path dependencies found. Nothing to do."
    exit 0
fi

echo ""
echo "Rewriting relative paths to absolute..."

# Build sed replacements for known patterns:
# ../../packages/<name> -> SHIKI_ROOT/packages/<name>
# ../../projects/<name> -> SHIKI_ROOT/projects/<name>
# ../<name>             -> SHIKI_ROOT/packages/<name>  (for sibling packages)

REWRITE_COUNT=0

# Pattern 1: ../../packages/X
while IFS= read -r match; do
    pkg_name=$(echo "$match" | grep -oE '\.\./\.\./packages/[^"]+')
    real_name="${pkg_name#../../packages/}"
    abs_path="$SHIKI_ROOT/packages/$real_name"
    if [[ -d "$abs_path" ]]; then
        sed -i '' "s|path: \"$pkg_name\"|path: \"$abs_path\"|g" "$PACKAGE_SWIFT"
        echo "  [FIX] $pkg_name -> $abs_path"
        ((REWRITE_COUNT++))
    else
        echo "  [WARN] $pkg_name -> $abs_path (NOT FOUND)"
    fi
done < <(grep -oE 'path: "\.\./\.\./packages/[^"]*"' "$PACKAGE_SWIFT" | sort -u)

# Pattern 2: ../../projects/X
while IFS= read -r match; do
    proj_name=$(echo "$match" | grep -oE '\.\./\.\./projects/[^"]+')
    real_name="${proj_name#../../projects/}"
    abs_path="$SHIKI_ROOT/projects/$real_name"
    if [[ -d "$abs_path" ]]; then
        sed -i '' "s|path: \"$proj_name\"|path: \"$abs_path\"|g" "$PACKAGE_SWIFT"
        echo "  [FIX] $proj_name -> $abs_path"
        ((REWRITE_COUNT++))
    else
        echo "  [WARN] $proj_name -> $abs_path (NOT FOUND)"
    fi
done < <(grep -oE 'path: "\.\./\.\./projects/[^"]*"' "$PACKAGE_SWIFT" | sort -u)

# Pattern 3: ../X (sibling packages)
while IFS= read -r match; do
    sibling=$(echo "$match" | grep -oE '\.\./[^"]+')
    real_name="${sibling#../}"
    abs_path="$SHIKI_ROOT/packages/$real_name"
    if [[ -d "$abs_path" ]]; then
        sed -i '' "s|path: \"$sibling\"|path: \"$abs_path\"|g" "$PACKAGE_SWIFT"
        echo "  [FIX] $sibling -> $abs_path"
        ((REWRITE_COUNT++))
    else
        echo "  [WARN] $sibling -> $abs_path (NOT FOUND)"
    fi
done < <(grep -oE 'path: "\.\./[^.][^"]*"' "$PACKAGE_SWIFT" | sort -u)

echo ""
echo "Rewrote $REWRITE_COUNT path(s) in Package.swift."

# Verify SPM resolution
echo ""
echo "Running swift package resolve..."
cd "$WORKTREE_PATH"
if swift package resolve 2>&1 | tail -10; then
    echo ""
    echo "=== SPM resolution: OK ==="
else
    echo ""
    echo "=== SPM resolution: FAILED ==="
    exit 1
fi
