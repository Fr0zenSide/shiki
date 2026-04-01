---
title: "Shikki Fresh Install — Zero-to-Running in One Command"
status: spec
priority: P0
project: shikki
created: 2026-04-01
authors: "@Daimyo pain point + @Sensei"
epic: epic/fresh-install
---

# Shikki Fresh Install

> `git clone && shikki setup` — that's it. Everything else is automatic.

---

## 1. Problem

Fresh clone of Shikki doesn't work. The README says 3 commands but reality needs 15+ manual steps:

```
What README says:
  git clone https://github.com/Fr0zenSide/shiki.git
  cd shiki/projects/shikki && swift build
  shikki start

What actually happens:
  git clone ...
  cd shiki/projects/shikki && swift build  ← OK
  shikki start                              ← CRASH: tmux not found
  brew install tmux                         ← manual
  shikki start                              ← CRASH: claude not found
  # install Claude Code CLI somehow
  shikki start                              ← CRASH: no backend
  cd ../.. && docker-compose up -d           ← manual
  # wait for backend to be healthy
  shikki start                              ← CRASH: no companies
  # seed companies somehow
  shikki start                              ← finally works (maybe)
```

`shikki init` exists but only generates `.moto` files — it doesn't set up the workspace.
`shikki doctor` checks but doesn't fix.

---

## 2. Solution: `shikki setup`

One command that takes you from fresh clone to running:

```bash
git clone https://github.com/Fr0zenSide/shiki.git
cd shiki
./setup.sh          # OR: swift run shikki setup
```

### What `setup` does:

```
Step 1: Check & Install Dependencies
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ swift    (required — if missing, error with install link)
  ✓ brew     (required on macOS — if missing, install)
  ✓ tmux     (required — brew install tmux)
  ✓ git      (required — should already be there)
  ◇ claude   (optional — show how to install if missing)
  ◇ delta    (optional — brew install git-delta)
  ◇ fzf      (optional — brew install fzf)
  ◇ rg       (optional — brew install ripgrep)
  ◇ bat      (optional — brew install bat)
  ◇ qmd      (optional — link to install)

Step 2: Build Shikki
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  cd projects/shikki && swift build
  ln -sf $(pwd)/.build/debug/shikki ~/.local/bin/shikki
  ln -sf $(pwd)/.build/debug/shikki-test ~/.local/bin/shikki-test

Step 3: Create Workspace Structure
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  mkdir -p .shikki/
  mkdir -p .shikki/test-logs/
  mkdir -p .shikki/plugins/
  mkdir -p .shikki/sessions/
  # .gitignore .shikki/ (already done)

Step 4: Backend (optional — ask user)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  "Do you want to start the ShikiDB backend? [Y/n]"
  If yes:
    - Check Docker/Colima
    - docker-compose up -d
    - Wait for health check
    - Seed default companies
  If no:
    - Skip (Shikki works without backend, just no persistence)

Step 5: Shell Integration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Add to PATH if not already:
    export PATH="$HOME/.local/bin:$PATH"
  Install shell completions:
    shikki --generate-completion-script zsh > ~/.zsh/completions/_shikki

Step 6: First Run
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  shikki doctor  → verify everything
  shikki start   → launch tmux workspace
```

---

## 3. `shikki doctor --fix`

Upgrade doctor from "check only" to "check and fix":

```
shikki doctor
  ✓ git     git 2.44 found
  ✓ tmux    tmux 3.4 found
  ✗ delta   delta not found
  ✓ claude  claude found
  ✓ fzf     fzf 0.48 found
  ✗ bat     bat not found
  ✓ rg      rg 14.1 found
  ✓ disk    81.5 GB free

  2 optional tools missing.
  Run: shikki doctor --fix

shikki doctor --fix
  Installing delta... brew install git-delta ✓
  Installing bat... brew install bat ✓
  All checks passed ✓
```

---

## 4. `setup.sh` Bootstrap Script

For the very first run (before shikki binary exists):

```bash
#!/bin/bash
# setup.sh — run from repo root after git clone
set -e

echo "🔥 Shikki Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Swift
if ! command -v swift &>/dev/null; then
    echo "❌ Swift not found. Install from https://swift.org/install"
    exit 1
fi

# Check/install brew
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install required tools
for tool in tmux; do
    if ! command -v "$tool" &>/dev/null; then
        echo "Installing $tool..."
        brew install "$tool"
    fi
done

# Install optional tools
echo "Installing recommended tools..."
for tool in git-delta fzf ripgrep bat; do
    brew install "$tool" 2>/dev/null || true
done

# Build Shikki
echo "Building Shikki..."
cd projects/shikki && swift build
cd ../..

# Symlink
mkdir -p ~/.local/bin
ln -sf "$(pwd)/projects/shikki/.build/debug/shikki" ~/.local/bin/shikki
ln -sf "$(pwd)/projects/shikki/.build/debug/shikki-test" ~/.local/bin/shikki-test

# Create workspace dirs
mkdir -p .shikki/{test-logs,plugins,sessions}

# PATH check
if ! echo "$PATH" | grep -q ".local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    echo "Added ~/.local/bin to PATH in ~/.zshrc"
fi

# Verify
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
shikki doctor
echo ""
echo "✅ Shikki ready. Run: shikki start"
```

---

## 5. Implementation

### Wave 1: setup.sh bootstrap (P0)
- Create `setup.sh` at repo root
- Install deps, build, symlink, create dirs
- **5 tests** (check script handles missing tools)

### Wave 2: `shikki doctor --fix` (P0)
- Enhance `ShikkiDoctor.swift` with `--fix` flag
- Auto-install missing optional tools via brew
- **8 tests**

### Wave 3: `shikki setup` command (P1)
- Swift command that does what setup.sh does but smarter
- Detects existing setup, skips steps
- Backend setup (Docker check, compose up, health wait, seed)
- **10 tests**

---

## 6. Acceptance Criteria

- [ ] `git clone && cd shiki && ./setup.sh` works on fresh macOS
- [ ] `shikki doctor --fix` installs missing optional tools
- [ ] `shikki start` works after setup without manual steps
- [ ] tmux is installed automatically if missing
- [ ] No manual Docker/backend setup required (optional prompt)
- [ ] PATH is configured automatically
- [ ] Shell completions installed

---

## 7. @shi Mini-Challenge

1. **@Ronin**: setup.sh runs `brew install` — what if user doesn't want Homebrew? Should we support Nix/MacPorts?
2. **@Katana**: The script adds to ~/.zshrc — what if user uses fish/bash? Detect shell first.
3. **@Sensei**: Should `shikki setup` be a Swift command or always a bash script? The chicken-and-egg: you need Swift to build shikki, but shikki is the setup tool.
