---
title: "Shikki Zero-to-Running — Complete Fresh Install Pipeline"
status: spec
priority: P0
project: shikki
created: 2026-04-01
authors: "@Daimyo + Faustin diagnostic sessions"
epic: epic/zero-to-running
depends-on:
  - shikki-fresh-install.md (setup.sh + SetupState)
  - shikki-cli-robustness.md (bash script idempotence)
  - fix-backend-docker-healthcheck.md (deno eval healthcheck)
---

# Shikki Zero-to-Running

> From `git clone` to working tmux session with zero manual intervention.

---

## 1. Problem (from Faustin's diagnostic 2026-04-01)

Fresh clone of Shikki fails at multiple points:

```
CRASH 1: shikki-side.sh hook — "No such file or directory"
  → Hook script referenced in settings but doesn't exist on fresh clone

CRASH 2: Backend healthcheck — curl not in Deno image
  → docker compose marks backend unhealthy → frontend won't start

CRASH 3: No session state — checkpoint.json missing
  → Shikki tries to resume but nothing to resume from

CRASH 4: Company seeding — runs before backend is healthy
  → seed-companies.sh fails silently

CRASH 5: EDL/memory directories — expected but not created
  → projects/EDL/memory/ doesn't exist on fresh clone

CRASH 6: Port orphans — re-init crashes on occupied ports
  → AddrInUse: Address already in use (os error 48)
```

---

## 2. The Complete Fix Chain

### Phase A: Pre-Build (setup.sh)
```
1. Check/install: swift, brew, tmux, claude (optional)
2. Install optional: delta, fzf, rg, bat
3. swift build (shikki + shikki-test)
4. Symlink to ~/.local/bin/
5. Create .shikki/ workspace dirs
6. Write setup.json → marks setup complete
```
**Status: IMPLEMENTED** (feature/fresh-install-w1)

### Phase B: Bash Script Robustness
```
1. kill_port() before starting backend/frontend
2. cleanup_stale_pids() on every start
3. is_running() verifies PID + port via lsof
4. Idempotent init with --force
5. Skip healthy docker containers
6. Absolute paths for deno/vite
7. trap EXIT for cleanup
```
**Status: IMPLEMENTED** (feature/fresh-install-w2)

### Phase C: Docker Healthcheck Fix
```
1. Replace curl with deno eval fetch() in docker-compose.yml
```
**Status: SPEC'D** (fix-backend-docker-healthcheck.md) — needs impl

### Phase D: Missing Hook Scripts
```
1. shikki-side.sh — referenced in .claude/settings.local.json but doesn't exist
2. shikki-approval.sh — may reference missing deps
3. shikki-activity.sh — same
4. shikki-idle.sh — same
→ Fix: setup.sh creates all hook scripts OR settings guard checks existence
```
**Status: NEW** — needs impl

### Phase E: Session State Bootstrap
```
1. On first run, create default checkpoint.json
2. Create .shikki/sessions/ with empty state
3. shikki start should NOT try to resume if no session exists
4. Show "First run — starting fresh" instead of crash
```
**Status: NEW** — needs impl

### Phase F: Startup Health Monitor
```
1. shikki heartbeat checks all services on boot
2. If backend unhealthy → auto run: shikki doctor --fix
3. If doctor can't fix → toast notification to user:
   "⚠️ deno-backend unreachable — check docker compose logs backend"
4. Previous session summary on start:
   "Last session: 3 specs shipped, 2 reviews pending"
5. shikki session — show current session state from @db
```
**Status: NEW** — needs impl

### Phase G: E2E Fresh Install Test
```
Isolated test that simulates zero-state:
1. Create temp directory
2. Clone repo (or copy)
3. Run setup.sh
4. Run shikki doctor → all green
5. Run shikki start → tmux session created
6. Run shikki status → shows healthy
7. Run shikki-test --parallel → tests pass
8. Cleanup temp directory

This runs ONLY before release branch creation.
Not part of regular test suite (too slow, needs Docker).
```
**Status: NEW** — needs impl

---

## 3. Auto-Recovery on shikki start

```
shikki start (or any command):

1. Check setup.json exists?
   NO  → run SetupService.bootstrap() → continue
   YES → check version matches binary?
     NO  → run SetupService.bootstrap(upgrade: true) → continue
     YES → continue

2. Check services healthy?
   → shikki doctor (silent, fast check)
   → If issues found:
     FIXABLE → auto run doctor --fix
     NOT FIXABLE → show toast: "⚠️ {component} needs attention"
   → Continue regardless (don't block on optional services)

3. Check previous session?
   EXISTS → show summary: "Last session: ..."
   NONE   → show: "Welcome to Shikki 🔥"

4. Launch tmux workspace
```

---

## 4. shikki session Command

```
shikki session              → current session overview
shikki session --previous   → what happened last time
shikki session --history    → last 10 sessions

Output:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Session: shikki-2026-04-01
  Started: 2026-04-01 06:00
  Duration: 12h 35m

  Specs delivered: 30
  Tests: 1,882 green
  Branches merged: 4 epics → develop

  Pending:
    3 epics ready for merge
    2 specs awaiting review
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 5. Implementation Waves

### Wave 1: Docker healthcheck fix (P0, 5 min)
- Apply deno eval fix to docker-compose.yml
- Verify with docker compose up -d
- **0 tests** (infra config)

### Wave 2: Hook script guards (P0)
- Check hook script exists before registering in settings
- Create stub scripts if missing
- OR: remove hook references from settings.json for fresh clones
- **5 tests**

### Wave 3: Session state bootstrap (P0)
- First-run detection in ShikkiEngine
- Default checkpoint creation
- "Welcome to Shikki" vs "Resuming session" logic
- **8 tests**

### Wave 4: Startup health monitor (P1)
- Auto doctor --fix on unhealthy services
- Toast notification for unfixable issues
- Previous session summary from @db
- **10 tests**

### Wave 5: shikki session command (P1)
- SessionCommand.swift
- Current + previous + history views
- Query ShikiDB for session data
- **8 tests**

### Wave 6: E2E fresh install test (P0)
- Isolated test script (bash + Swift)
- Runs in temp directory
- Full pipeline: clone → setup → doctor → start → test → cleanup
- Gate for release branch creation
- **1 integration test**

---

## 6. Acceptance Criteria

- [ ] `git clone && ./setup.sh && shikki start` works on clean macOS
- [ ] No "file not found" errors from hook scripts
- [ ] Docker healthcheck passes without curl
- [ ] First run shows welcome, not crash
- [ ] shikki doctor --fix resolves missing tools
- [ ] Auto-recovery on startup (setup + health check)
- [ ] shikki session shows meaningful session overview
- [ ] E2E test passes in isolated environment
- [ ] Re-running setup.sh is idempotent (skips completed steps)
- [ ] shikki start after crash recovers cleanly

---

## 7. @shi Mini-Challenge

1. **@Ronin**: The E2E test needs Docker — what if CI doesn't have Docker? Should we have a Docker-free variant that skips backend?
2. **@Katana**: setup.sh installs brew packages — what if the user is on a managed corporate Mac where brew is forbidden?
3. **@Sensei**: Should the session summary query @db on every start? That's a network call. What if DB is down? Cache last summary locally?
