#!/bin/bash
# Rewrite Co-Authored-By: Claude → Shikki attribution format
# Usage: ./scripts/rewrite-attribution.sh [base-commit]
#
# Rewrites all commits from <base-commit> to HEAD, replacing:
#   Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
# With:
#   Co-Authored-By: Shikki <shikki@obyw.one>
#   Orchestrated-By: shikki/0.3.0-pre
#   Generated-By: claude/opus-4.6 (1M context)
#
# Shikki is the primary contributor (shows on GitHub).
# Claude is credited as the generation tool (secondary).

set -euo pipefail

BASE="${1:-8d6dadaa}"  # default: develop before mega merge
COUNT=$(git rev-list --count "$BASE"..HEAD)

echo "🔥 Shikki Attribution Rewrite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Base:    $BASE"
echo "  HEAD:    $(git rev-parse --short HEAD)"
echo "  Commits: $COUNT"
echo "  Branch:  $(git branch --show-current)"
echo ""
echo "  Before: Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
echo "  After:  Co-Authored-By: Shikki <shikki@obyw.one>"
echo "          Orchestrated-By: shikki/0.3.0-pre"
echo "          Generated-By: claude/opus-4.6 (1M context)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

export FILTER_BRANCH_SQUELCH_WARNING=1

git filter-branch -f --msg-filter '
sed "s/Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>/Co-Authored-By: Shikki <shikki@obyw.one>\nOrchestrated-By: shikki\/0.3.0-pre\nGenerated-By: claude\/opus-4.6 (1M context)/"
' -- "$BASE"..HEAD

echo ""
echo "✅ Done. $COUNT commits rewritten."
echo ""
echo "Verify:"
echo "  git log --oneline -5"
echo "  git log -1 --format='%b' HEAD"
echo ""
echo "Push (force required — history rewritten):"
echo "  git push origin $(git branch --show-current) --force-with-lease"
