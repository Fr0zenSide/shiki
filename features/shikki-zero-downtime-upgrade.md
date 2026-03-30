---
title: "Shikki Zero-Downtime Upgrade — Blue/Green Node Handoff Protocol"
status: spec
priority: P0
project: shikki
created: 2026-03-30
authors: "@shi full team + @Daimyo"
depends-on:
  - shikki-distributed-orchestration.md (NATS + chat node separation)
  - spec-report-logger-nats.md (NATS foundation)
  - shikki-native-scheduler.md (ShikkiKernel)
relates-to:
  - shikki-dispatch-resilience.md (context explosion — this solves it permanently)
---

# Shikki Zero-Downtime Upgrade

> You never restart Shikki. You replace it while it's still breathing.

---

## 1. Problem

Today, upgrading Shikki means:

```
1. User builds new binary (swift build)
2. User runs `shikki restart`
3. Old process dies immediately
4. New process starts cold
5. All in-flight context is lost
6. Claude Code session may crash (CWD trap, compaction in dead state)
7. User manually re-discovers state with /retry
```

This is a **hard cut** — the system goes from running to dead to cold-starting. During the gap:
- Running agents lose their coordinator
- Event bus has no subscriber
- Pending decisions queue up with no processor
- The user's Claude Code session (if it IS the orchestrator) loses context

**The real problem**: The orchestrator IS a Claude Code session. You can't restart a conversation mid-thought. You can't hot-swap a context window. Every restart is a mini-death.

### What we want

```
1. User builds new binary
2. User says "upgrade" (or it's automatic)
3. New node boots alongside old node
4. Old node saves state to DB + enters watcher mode
5. New node hydrates from DB (optimized context, not raw dump)
6. New node subscribes to NATS, takes over coordination
7. Old node confirms handoff, dies gracefully
8. Zero gap. Zero lost events. Zero lost context.
```

This is **blue/green deployment for an AI orchestrator**.

---

## 2. Architecture: The Handoff Protocol

### Lifecycle States

```
             ┌──────────┐
             │  BUILD    │  swift build produces new binary
             └─────┬─────┘
                   │
             ┌─────▼─────┐
             │  SPAWN     │  new node process starts
             └─────┬─────┘
                   │
             ┌─────▼─────┐
             │  HYDRATE   │  new node reads state from DB
             └─────┬─────┘
                   │
             ┌─────▼─────┐
             │  SHADOW    │  new node subscribes to NATS, observes
             └─────┬─────┘         (old node still primary)
                   │
             ┌─────▼─────┐
             │  VERIFY    │  new node confirms it can handle traffic
             └─────┬─────┘
                   │
             ┌─────▼─────┐
             │  PROMOTE   │  new node becomes primary
             └─────┬─────┘         (old node enters DRAIN)
                   │
             ┌─────▼─────┐
             │  DRAIN     │  old node finishes in-flight work
             └─────┬─────┘
                   │
             ┌─────▼─────┐
             │  RETIRE    │  old node saves final state, exits
             └──────────┘
```

### Two-Node Overlap Window

```
Timeline:
────────────────────────────────────────────────────────
  OLD NODE    [████████████████████░░░░░]  ← primary → watcher → die
  NEW NODE              [░░░░░████████████████]  ← shadow → primary
                        ↑                ↑
                     SPAWN            PROMOTE
────────────────────────────────────────────────────────
                   overlap window
                   (both alive, no gap)
```

During the overlap window:
- **Old node** = still handling events, still coordinating agents
- **New node** = hydrating from DB, subscribing to NATS, building its picture
- At PROMOTE: atomic switchover via NATS `shikki.node.primary` claim

---

## 3. The Handoff Protocol (NATS subjects)

### Node Identity

Every node has a unique identity:

```json
{
  "node_id": "shikki-main-20260330-v0.3.1",
  "binary_version": "0.3.1-build.47",
  "binary_hash": "sha256:abc123...",
  "started_at": "2026-03-30T12:00:00Z",
  "role": "primary",          // primary | shadow | watcher | draining
  "pid": 12345
}
```

### NATS Subjects

```
shikki.node.announce              # heartbeat with role + version
shikki.node.primary               # claim: "I am the primary" (first wins)
shikki.node.upgrade.request       # "new binary ready, requesting upgrade"
shikki.node.upgrade.ack           # old primary acknowledges, enters drain prep
shikki.node.state.snapshot        # old node publishes optimized state snapshot
shikki.node.handoff.ready         # new node confirms hydration complete
shikki.node.handoff.execute       # atomic role swap
shikki.node.retire                # old node announces graceful exit
```

### Protocol Sequence

```
Step 1: UPGRADE REQUEST
  New binary → NATS: shikki.node.upgrade.request {
    new_version: "0.3.1-build.47",
    new_binary_path: "/path/to/.build/debug/shikki",
    requested_by: "user" | "auto" | "ci"
  }

Step 2: STATE SAVE (old node)
  Old node receives request → saves to DB:
  - Current dispatch state (waves, agents, progress)
  - Active subscriptions (which NATS subjects it's watching)
  - Pending decisions queue
  - Agent status map
  - Session metadata

  Old node → NATS: shikki.node.upgrade.ack {
    state_snapshot_id: "snap-20260330-120000",
    state_size_tokens: 4500,
    optimized_context_id: "ctx-20260330-120000"
  }

Step 3: HYDRATE (new node)
  New node reads from DB:
  - NOT the raw conversation history (that's the old context window)
  - The OPTIMIZED state: dispatch status, agent map, pending work
  - Sized to fit within the new node's context budget

  New node → NATS: shikki.node.handoff.ready {
    hydrated_from: "snap-20260330-120000",
    context_used_pct: 15,
    capabilities: ["dispatch", "schedule", "monitor", "recover"]
  }

Step 4: SHADOW (new node observes)
  New node subscribes to all NATS subjects
  Old node continues as primary
  New node builds real-time picture from events
  Duration: 5-30 seconds (configurable, or until caught up)

Step 5: PROMOTE (atomic swap)
  New node → NATS: shikki.node.handoff.execute {
    claiming: "primary",
    replacing: "shikki-main-20260330-v0.3.0"
  }

  Old node receives → enters DRAIN mode
  Old node stops accepting new work
  Old node finishes in-flight operations

Step 6: DRAIN + RETIRE (old node)
  Old node waits for in-flight work (max 60s timeout)
  Old node → DB: final state save
  Old node → NATS: shikki.node.retire {
    final_state_id: "snap-final-20260330-120030",
    in_flight_transferred: 3,
    clean_exit: true
  }
  Old node process exits (SIGTERM self)
```

---

## 4. Optimized Context Hydration

### The key insight: don't transfer the conversation, transfer the knowledge

The old node might have 200K tokens of conversation history. The new node doesn't need any of it. It needs:

```
OPTIMIZED STATE (~2-5K tokens):
  dispatch:
    current_wave: 3
    completed: [0, 1, 2]
    in_progress: [{ spec: "community-flywheel", agent_id: "w3-1", branch: "feature/..." }]
    pending: []

  agents:
    active: 1
    stalled: 0
    last_completion: { spec: "moto-dns", tests: 45, branch: "feature/moto-dns-v2" }

  decisions:
    pending: 0
    last_answered: "2026-03-30T11:45:00Z"

  session:
    started: "2026-03-30T06:00:00Z"
    total_specs_delivered: 19
    total_tests: 1421

  user_context:
    last_topic: "distributed orchestration brainstorm"
    mood: "productive, building momentum"
    preferences_applied: ["no-ask-just-do", "auto-save-specs", "push-before-review"]
```

This is **3K tokens** vs the old node's 200K. The new node starts with a clean, dense understanding — no accumulated cruft, no stale status tables, no repeated error logs.

### DB Schema for State Snapshots

```sql
CREATE TABLE node_snapshots (
  id TEXT PRIMARY KEY,
  node_id TEXT NOT NULL,
  binary_version TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Optimized state (what the new node needs)
  dispatch_state JSONB NOT NULL,
  agent_map JSONB NOT NULL,
  pending_decisions JSONB DEFAULT '[]',
  session_metadata JSONB NOT NULL,
  user_context JSONB NOT NULL,

  -- Raw state (for debugging, not for hydration)
  raw_event_count INTEGER,
  conversation_token_estimate INTEGER,

  -- Lifecycle
  type TEXT CHECK (type IN ('upgrade', 'checkpoint', 'crash_recovery')),
  consumed_by TEXT,  -- node_id that consumed this snapshot
  consumed_at TIMESTAMPTZ
);
```

---

## 5. Chat Node vs Main Node

### Today's problem

The Claude Code chat IS the orchestrator. Restarting it means:
- Kill the conversation (context lost)
- Kill the coordinator (agents orphaned)
- Kill the UI (user blind)

### Tomorrow's separation (from distributed-orchestration spec)

```
Main Node (ShikkiKernel)     Chat Node (Claude Code)
─────────────────────────    ─────────────────────────
Swift binary                 Claude conversation
No context window            200K context window
Stateless (reads DB)         Disposable (reads DB on resume)
Coordinates agents           Human interface
Handles upgrades             Can die anytime safely
```

When the **main node** upgrades: blue/green handoff (this spec).
When the **chat node** upgrades: nothing. It's just a viewer. Open a new chat, it hydrates from DB. The old chat can die — no loss.

### Transition Period (before full NATS)

Until NATS is live, we can still do a simplified version:

```
1. Old Claude session saves state to DB (shikki save-state)
2. User builds new binary (swift build)
3. User starts new Claude session
4. New session runs: shikki load-state → gets optimized context from DB
5. New session continues where old one left off
```

This is **manual blue/green** — no NATS, no automatic overlap, but same principle: state in DB, not in conversation.

---

## 6. Auto-Upgrade (CI/CD for the orchestrator)

### Future: `shikki upgrade` command

```bash
$ shikki upgrade

Shikki Upgrade
────────────────────────────────────────────────────
Current: v0.3.0-build.45 (running, pid 12345)
Available: v0.3.1-build.47 (built 2 min ago)
────────────────────────────────────────────────────

Phase 1/6: Saving state...          ✓ snap-20260330-120000
Phase 2/6: Spawning new node...     ✓ pid 12346
Phase 3/6: Hydrating...             ✓ 2.8K tokens (1.4% context)
Phase 4/6: Shadow (10s)...          ✓ caught up (47 events)
Phase 5/6: Promoting...             ✓ new node is primary
Phase 6/6: Draining old node...     ✓ clean exit

Upgrade complete: v0.3.0 → v0.3.1
Total downtime: 0ms
────────────────────────────────────────────────────
```

### Auto-trigger scenarios

```swift
enum UpgradeTrigger {
    case userCommand          // `shikki upgrade`
    case binaryChanged        // file watcher on .build/debug/shikki
    case scheduledWindow      // cron: upgrade at 3am if new build available
    case healthDegraded       // crash count > 3 → try new binary
}
```

---

## 7. Crash Recovery (unplanned "upgrade")

When a node crashes (no graceful drain):

```
1. Watchdog (launchd/systemd) detects process death
2. Watchdog restarts shikki binary (same or new version)
3. New node boots → checks DB for latest snapshot
4. If snapshot exists and is < 5 min old: hydrate from it
5. If snapshot is stale: full recovery scan (git worktrees, NATS replay, DB events)
6. New node publishes: shikki.node.announce { role: "primary", recovered: true }
7. Agents that were running see new primary → resume heartbeats
```

This is the **crash version** of blue/green — there's no overlap window because the old node died unexpectedly. But the recovery is fast because state is in DB, not in a dead conversation.

---

## 8. Implementation Waves

### Wave 1: Manual Handoff (no NATS required)
- `shikki save-state` → serialize dispatch/agent/session state to DB
- `shikki load-state` → hydrate new session from DB snapshot
- Optimized context builder (compress 200K → 3K tokens)
- `node_snapshots` table in ShikiDB
- **20 tests** estimated

### Wave 2: Automatic Handoff (requires NATS)
- Node identity + heartbeat on NATS
- Upgrade request/ack protocol
- Shadow mode (subscribe + observe)
- Atomic promote (NATS claim)
- Drain + retire lifecycle
- **30 tests** estimated

### Wave 3: `shikki upgrade` Command
- Binary version detection (hash comparison)
- File watcher for `.build/debug/shikki`
- 6-phase upgrade UX (TUI rendering)
- Auto-trigger on binary change
- **15 tests** estimated

### Wave 4: Crash Recovery
- Watchdog integration (launchd plist / systemd unit)
- Stale snapshot detection
- Full recovery scan (worktrees + NATS replay + DB)
- Health-degraded auto-upgrade
- **20 tests** estimated

---

## 9. Acceptance Criteria

- [ ] `shikki upgrade` completes with 0ms downtime (no event gap)
- [ ] New node hydrates from DB in < 5 seconds
- [ ] Optimized context is < 5K tokens (vs 200K raw conversation)
- [ ] Old node drains in-flight work before dying (max 60s)
- [ ] Crash recovery restores to last snapshot in < 10 seconds
- [ ] Running agents survive the upgrade (heartbeat to new primary)
- [ ] No manual `/retry` needed after upgrade
- [ ] `shikki status` shows upgrade progress in real-time

---

## 10. @shi Mini-Challenge

1. **@Ronin**: During the shadow phase, both nodes receive NATS events. What if the new node acts on an event before promote? Race condition? Should shadow mode be read-only?
2. **@Katana**: The optimized context includes `user_context.mood`. Can this be gamed or leaked? Should it be excluded from DB snapshots?
3. **@Sensei**: Wave 1 (manual handoff) works without NATS. Should we ship Wave 1 immediately as a stopgap, even before the NATS foundation is built?
4. **@Hanami**: The 6-phase upgrade UX — should it be silent by default (just a status line change) or always show the full phase progression?
5. **@Kintsugi**: "You never restart Shikki. You replace it while it's still breathing." — Is this continuity of self, or is each node a new being carrying the memories of its predecessor? What does identity mean for an AI system that transfers state but not consciousness?
