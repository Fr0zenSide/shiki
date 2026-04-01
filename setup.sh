#!/bin/bash
# setup.sh — Shikki bootstrap. Run from repo root after git clone.
# Usage: ./setup.sh
#
# What it does:
#   1. Checks Swift is installed
#   2. Checks/installs Homebrew
#   3. Installs required tools (tmux)
#   4. Installs optional tools (git-delta, fzf, ripgrep, bat)
#   5. Builds shikki + shikki-test
#   6. Symlinks to ~/.local/bin/
#   7. Creates .shikki/ workspace dirs
#   8. Ensures ~/.local/bin is on PATH
#   9. Runs shikki doctor

set -euo pipefail

# Resolve repo root (directory containing this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Output helpers ---

bold()    { printf '\033[1m%s\033[0m\n' "$*"; }
green()   { printf '\033[32m%s\033[0m\n' "$*"; }
yellow()  { printf '\033[33m%s\033[0m\n' "$*"; }
red()     { printf '\033[31m%s\033[0m\n' "$*"; }
dim()     { printf '\033[2m%s\033[0m\n' "$*"; }
ok()      { printf '  \033[32m\xe2\x9c\x93\033[0m %s\n' "$*"; }
fail()    { printf '  \033[31m\xe2\x9c\x97\033[0m %s\n' "$*"; }
warn()    { printf '  \033[33m!\033[0m %s\n' "$*"; }

# --- Header ---

echo ""
bold "Shikki Setup"
printf '%0.s\xe2\x94\x80' {1..40}
echo ""
echo ""

# --- Step 1: Check Swift ---

bold "Step 1: Checking prerequisites..."

if ! command -v swift &>/dev/null; then
    fail "Swift not found."
    red "  Install from: https://swift.org/install"
    exit 1
fi
ok "swift ($(swift --version 2>&1 | head -1 | sed 's/.*version //' | cut -d' ' -f1))"

# --- Step 2: Check/install Homebrew ---

if ! command -v brew &>/dev/null; then
    echo ""
    bold "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Re-source brew in case it was just installed
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi
ok "brew"

# --- Step 3: Install required tools ---

echo ""
bold "Step 2: Installing required tools..."

install_if_missing() {
    local binary="$1"
    local formula="$2"
    if command -v "$binary" &>/dev/null; then
        ok "$binary"
    else
        printf '  Installing %s... ' "$binary"
        if brew install "$formula" &>/dev/null; then
            printf '\033[32m\xe2\x9c\x93\033[0m\n'
        else
            printf '\033[31mfailed\033[0m\n'
            return 1
        fi
    fi
}

install_if_missing tmux tmux || { fail "tmux is required"; exit 1; }

# --- Step 4: Install optional tools ---

echo ""
bold "Step 3: Installing recommended tools..."

install_if_missing delta git-delta || warn "git-delta — skipped (optional)"
install_if_missing fzf fzf || warn "fzf — skipped (optional)"
install_if_missing rg ripgrep || warn "ripgrep — skipped (optional)"
install_if_missing bat bat || warn "bat — skipped (optional)"

# --- Step 5: Build Shikki ---

echo ""
bold "Step 4: Building shikki..."

cd "$SCRIPT_DIR/projects/shikki"

swift build 2>&1 | tail -5
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    fail "swift build failed"
    exit 1
fi
ok "shikki built"

# Build test runner
swift build --product shikki-test 2>&1 | tail -3
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    warn "shikki-test build failed (non-fatal)"
else
    ok "shikki-test built"
fi

cd "$SCRIPT_DIR"

# --- Step 6: Symlink ---

echo ""
bold "Step 5: Creating symlinks..."

mkdir -p "$HOME/.local/bin"

SHIKKI_BIN="$SCRIPT_DIR/projects/shikki/.build/debug/shikki"
SHIKKI_TEST_BIN="$SCRIPT_DIR/projects/shikki/.build/debug/shikki-test"

if [[ -f "$SHIKKI_BIN" ]]; then
    ln -sf "$SHIKKI_BIN" "$HOME/.local/bin/shikki"
    ok "~/.local/bin/shikki -> $SHIKKI_BIN"
else
    fail "shikki binary not found at $SHIKKI_BIN"
fi

if [[ -f "$SHIKKI_TEST_BIN" ]]; then
    ln -sf "$SHIKKI_TEST_BIN" "$HOME/.local/bin/shikki-test"
    ok "~/.local/bin/shikki-test -> $SHIKKI_TEST_BIN"
else
    warn "shikki-test binary not found (non-fatal)"
fi

# --- Step 7: Workspace directories ---

echo ""
bold "Step 6: Creating workspace directories..."

for dir in .shikki .shikki/test-logs .shikki/plugins .shikki/sessions; do
    mkdir -p "$SCRIPT_DIR/$dir"
done
ok ".shikki/{test-logs,plugins,sessions}"

# --- Step 8: PATH check ---

echo ""
bold "Step 7: Checking PATH..."

if echo "$PATH" | tr ':' '\n' | grep -q "\.local/bin"; then
    ok "~/.local/bin in PATH"
else
    # Detect shell and append to the right rc file
    SHELL_RC="$HOME/.zshrc"
    if [[ "$SHELL" == */bash ]]; then
        SHELL_RC="$HOME/.bashrc"
    elif [[ "$SHELL" == */fish ]]; then
        SHELL_RC="$HOME/.config/fish/config.fish"
    fi

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    ok "Added ~/.local/bin to PATH in $SHELL_RC"
    warn "Run: source $SHELL_RC (or restart your terminal)"
fi

# --- Step 9: Run doctor ---

echo ""
printf '%0.s\xe2\x94\x80' {1..40}
echo ""

if command -v shikki &>/dev/null; then
    shikki doctor
elif [[ -f "$HOME/.local/bin/shikki" ]]; then
    "$HOME/.local/bin/shikki" doctor
else
    warn "Cannot run shikki doctor — binary not on PATH yet"
fi

echo ""
green "Shikki ready. Run: shikki start"
echo ""
