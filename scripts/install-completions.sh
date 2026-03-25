#!/usr/bin/env bash
# install-completions.sh — Generate and install zsh completions for shikki
#
# Run after building shikki:
#   bash scripts/install-completions.sh
#
# Called automatically by: shikki start (if completions are stale)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$WORKSPACE/projects/shikki/.build/debug/shikki"
COMPLETIONS_DIR="${HOME}/.zsh/completions"
COMPLETION_FILE="$COMPLETIONS_DIR/_shikki"

if [ ! -f "$BINARY" ]; then
  echo "shikki binary not found at $BINARY — build first"
  exit 1
fi

mkdir -p "$COMPLETIONS_DIR"

# Generate fresh completion script
"$BINARY" --generate-completion-script zsh > "$COMPLETION_FILE"

# Ensure fpath is configured in .zshrc
if ! grep -q 'zsh/completions' ~/.zshrc 2>/dev/null; then
  echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
  echo "Added fpath to ~/.zshrc"
fi

echo "Installed zsh completions for shikki ($(grep -c "'" "$COMPLETION_FILE") entries)"
echo "Run 'exec zsh' to reload, or open a new terminal"
