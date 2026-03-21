# Feature: Shiki Observatory — Session Intelligence & Agent Oversight

> **Type**: /md-feature
> **Priority**: P1 — core DX improvement, blocks effective multi-agent usage
> **Status**: Spec (validated by @Daimyo 2026-03-17)
> **Depends on**: Event Bus (Wave 2A — DONE), Session Foundation (Wave 1 — DONE), Shiki DB (existing)
> **Branch**: `feature/observatory` from `develop`

---

## 1. Problem

The human loses context faster than agents produce it. Today's workflow:

1. Agent works in tmux pane, produces 500+ lines of output
2. User scrolls up to find a key decision buried in noise
3. Copy-pastes a snippet → scroll resets to bottom
4. Loses position, re-scrolls, takes notes manually
5. Can't see what other agents are doing simultaneously
6. When agent asks a question, user must find the pane, read context, respond inline
7. After agent finishes, no structured summary — just raw terminal output
8. No way to trace "why did we end up here?" across sessions

This is the #1 unsolved problem in agent orchestration: **oversight without drowning in output.**

## 2. Solution — Three Layers

### Layer 1: Decision Journal (data capture)
### Layer 2: Agent Report Cards (structured summaries)
### Layer 3: Observatory TUI (interactive visualization)

Each layer builds on the previous. Ship in order.

---

## 3. Layer 1: Decision Journal

### 3.1 New Event Types

Extend `EventType` with strategic moment events:

```swift
// Add to ShikiEvent.swift EventType enum
case decisionMade          // architecture choice, trade-off evaluation
case architectureChoice    // specific technical decision with rationale
case tradeOffEvaluated     // considered X vs Y, chose X because Z
case blockerHit            // something stopped progress
case blockerResolved       // blocker was resolved (how?)
case milestoneReached      // significant progress checkpoint
case redFlag               // something looks wrong, needs attention
case contextSaved          // pre-compaction context snapshot
```

### 3.2 Decision Event Structure

```swift
public struct DecisionEvent: Codable, Sendable {
    public let category: DecisionCategory
    public let question: String       // "Actor or class for registry?"
    public let choice: String         // "Actor"
    public let rationale: String      // "Thread-safe by default, Swift 6 aligned"
    public let alternatives: [String] // ["Class + locks", "Struct + queue"]
    public let impact: DecisionImpact // .architecture | .implementation | .process
}

public enum DecisionCategory: String, Codable, Sendable {
    case architecture      // structural design choice
    case implementation    // how to build something
    case process           // workflow/pipeline decision
    case tradeOff          // explicit X vs Y evaluation
    case scope             // what's in/out of scope
}

public enum DecisionImpact: String, Codable, Sendable {
    case architecture  // affects system structure
    case implementation // affects current task only
    case process       // affects how we work
}
```

### 3.3 Emission Points

Every agent and pipeline emits decision events at key moments:

| Source | When | Event |
|--------|------|-------|
| Plan approval | User approves plan | `decisionMade` with plan summary |
| Gate pass/fail | /pre-pr gate result | `milestoneReached` or `redFlag` |
| Architecture choice | Agent picks approach | `architectureChoice` |
| Blocker | Agent can't proceed | `blockerHit` |
| Blocker resolved | Human/agent unblocks | `blockerResolved` |
| Context compaction | ~75% context window | `contextSaved` |
| Scope change | `/course-correct` | `decisionMade` with scope delta |

### 3.4 DB Persistence

All decision events go to Shiki DB via `ShikiDBEventLogger` (already built). Query patterns:

```
GET /api/data-sync?type=decision_made&date=2026-03-17
GET /api/data-sync?type=red_flag&projectId=<id>
GET /api/data-sync?type=blocker_hit&status=unresolved
```

### 3.5 Decision Chain Traceability

Each decision event carries a `parentDecisionId` field linking to the decision that prompted it:

```
Plan: "build v3 orchestrator" (decision-001)
  └── Architecture: "actor over class for lifecycle" (decision-002, parent: 001)
  └── Scope: "defer Wave 2C hooks" (decision-003, parent: 001)
      └── Rationale: "shell-level, not Swift" (decision-004, parent: 003)
```

This creates a queryable tree: "show me the chain of decisions that led to this result."

---

## 4. Layer 2: Agent Report Cards

### 4.1 Report Structure

When an agent session ends (merged, done, or terminated), generate a structured report:

```swift
public struct AgentReport: Codable, Sendable {
    public let sessionId: String
    public let persona: AgentPersona
    public let companySlug: String
    public let taskTitle: String
    public let duration: TimeInterval

    // Before → After
    public let beforeState: String       // 1-line description of starting state
    public let afterState: String        // 1-line description of ending state

    // Work summary
    public let filesChanged: [String]
    public let testsAdded: Int
    public let testsTotal: Int
    public let testsPassed: Bool

    // Decision history
    public let keyDecisions: [DecisionSummary]

    // Health metrics
    public let contextResets: Int
    public let questionsAsked: Int
    public let blockersHit: Int
    public let watchdogTriggers: Int

    // Red flags
    public let redFlags: [String]

    // Handoff context (if handing off to next persona)
    public let handoffContext: HandoffContext?
}

public struct DecisionSummary: Codable, Sendable {
    public let question: String
    public let choice: String
    public let impact: DecisionImpact
}
```

### 4.2 Report Generation

The report is generated from:
1. **SessionJournal** — checkpoint history for state transitions
2. **EventBus** — filtered events for this session (decisions, milestones, red flags)
3. **Git** — `git diff --stat` for files changed, test count from last `swift test` output
4. **Watchdog** — trigger history for this session

### 4.3 Report Persistence

- Rendered as markdown at `.shiki/reports/{session-id}.md`
- Persisted to Shiki DB as `type: "agent_report"`
- Displayed in Observatory TUI as expandable/collapsible card

### 4.4 Report Rendering

```
┌─ Agent Report: maya:spm-wave3 ────────────────────────────┐
│ Persona: implement │ Duration: 2h 14m │ Company: maya      │
├────────────────────────────────────────────────────────────┤
│ Before: 0 session types, raw tmux queries                  │
│ After:  3 new files, 31 tests, registry integrated         │
├────────────────────────────────────────────────────────────┤
│ Files: +1,060 LOC across 9 files                           │
│ Tests: 31 new (95 total), all green                        │
├────────────────────────────────────────────────────────────┤
│ Key Decisions:                                             │
│  ◆ Actor over class for SessionLifecycle (thread-safe)     │
│  ◆ JSONL over SQLite for journal (append-only, simple)     │
│  ◆ 5min staleness threshold (balances safety/cleanup)      │
├────────────────────────────────────────────────────────────┤
│ Health: 0 context resets │ 0 questions │ 0 blockers        │
│ Red flags: none                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 5. Layer 3: Observatory TUI

### 5.1 Layout

```
┌─ SHIKI OBSERVATORY ──────────────────────────────────────────────────┐
│ ← Timeline  ☐ Decisions  ☐ Questions  ☐ Reports  → Submit           │
├──────────────────────────────────┬───────────────────────────────────┤
│  TIMELINE (left 60%)             │  DETAIL (right 40%)              │
│                                  │                                  │
│  16:30 ◆ Plan: community        │  Community Data Flywheel         │
│           flywheel validated     │  ─────────────────────           │
│  16:00 ◆ E2E tests: 227 green   │  Status: validated               │
│  15:30 ● Fix: shell injection   │  Approved by: @Daimyo            │
│           in ExternalTools       │  Context: competitive moat       │
│  15:00 ◆ Rebase PR#6 onto #5    │                                  │
│  14:00 ● Gate 1b: 3 issues      │  Deliverables:                   │
│           found + fixed          │  □ CommunityAggregator           │
│  11:00 ◆ Wave 1-6 complete      │  □ TelemetryConfig               │
│           171 tests green        │  □ Cloud API                     │
│  10:43 ○ Session started         │                                  │
│                                  │  [e] expand  [Enter] open spec   │
│  ◆ = decision  ● = action        │                                  │
│  ○ = event     ▲ = red flag      │                                  │
├──────────────────────────────────┴───────────────────────────────────┤
│  ↑/↓ navigate · Enter expand · Tab switch panel · q quit            │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.2 Tabs

| Tab | Content | Data source |
|-----|---------|-------------|
| **Timeline** | Chronological key events (decisions, milestones, red flags) | EventBus subscription filtered to strategic events only |
| **Decisions** | All decisions with chain links (expand to see parent→child) | Shiki DB query `type=decision_made` |
| **Questions** | Pending questions from running agents with context + answer input | EventBus `decisionGate` events + `awaitingApproval` sessions |
| **Reports** | Completed agent report cards (expand/collapse) | `.shiki/reports/` + Shiki DB `type=agent_report` |

### 5.3 Questions Tab — Interactive Answer Injection

```
┌─ PENDING QUESTIONS ──────────────────────────────────────────────────┐
│                                                                       │
│  Q1 [maya:spm-wave3] ● awaitingApproval              2 min ago       │
│  ┌─ Context ──────────────────────────────────────────────────────┐  │
│  │ Building SessionRegistry. The spec says "5-minute staleness    │  │
│  │ threshold" but the Composio steal-sheet uses 3 minutes.        │  │
│  └────────────────────────────────────────────────────────────────┘  │
│  "Should I use 5min (spec) or 3min (Composio pattern)?"             │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ > 5min — we're solo, not a team. Longer threshold = fewer     │  │
│  │   false positives. Composio has 10 agents, we have 2.         │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  Q2 [wabisabi:onboard] ● awaitingApproval             8 min ago      │
│  ┌─ Context ──────────────────────────────────────────────────────┐  │
│  │ Implementing coordinator pattern. The existing app uses a      │  │
│  │ custom DI container that conflicts with the new coordinator.   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│  "Refactor DI to support coordinators, or wrap coordinator in..."   │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ > |                                                            │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  Tab to switch questions · Enter to edit · Ctrl-S submit all         │
│  Ctrl-A approve recommended · Ctrl-D dismiss                         │
└──────────────────────────────────────────────────────────────────────┘
```

**Injection mechanism**: answer is POSTed to the decision queue API + an `agentQuestion` event is published to the EventBus. The agent's tmux pane receives the answer via the existing `/decide` flow or a UserPromptSubmit hook injection.

### 5.4 Reports Tab — Expand/Collapse

```
┌─ AGENT REPORTS ──────────────────────────────────────────────────────┐
│                                                                       │
│  ▼ maya:spm-wave3 (implement) — 2h 14m — DONE                       │
│    Before: 0 session types, raw tmux queries                         │
│    After:  3 new files, 31 tests, registry integrated                │
│    ◆ Actor over class (thread-safe)                                  │
│    ◆ JSONL over SQLite (append-only)                                 │
│    Health: 0 resets │ 0 questions │ 0 blockers                       │
│                                                                       │
│  ► wabisabi:onboard (implement) — running — 45m elapsed              │
│    Current: implementing coordinator pattern                          │
│    ▲ 1 question pending (8 min ago)                                  │
│                                                                       │
│  ► flsh:mlx (investigate) — running — 12m elapsed                    │
│    Current: researching MLX pipeline architecture                     │
│                                                                       │
│  ▼ = expanded  ► = collapsed  ▲ = needs attention                    │
│  Enter to expand/collapse · Tab to switch panel                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.5 Priority Heatmap

Each item in every tab has a visual urgency indicator:

```
▲▲ CRITICAL  — red, blinking: agent terminated, data loss risk
▲  HIGH      — red: question pending > 10min, test failure, red flag
●  MEDIUM    — yellow: question pending < 10min, warning
○  LOW       — dim: informational event, completed report
```

Maps directly to `AttentionZone` levels already built in Wave 1.

---

## 6. Implementation Phases

### Phase A: Decision Events (~150 LOC, ~8 tests)
- Add new `EventType` cases to `ShikiEvent.swift`
- `DecisionEvent` struct + `DecisionCategory` + `DecisionImpact`
- `DecisionChain` — parentDecisionId linking
- Emit from HeartbeatLoop, /pre-pr pipeline, plan approval
- Persist to Shiki DB

### Phase B: Agent Report Cards (~200 LOC, ~6 tests)
- `AgentReport` struct with before/after/decisions/health
- `AgentReportGenerator` — builds report from journal + events + git
- Render as markdown to `.shiki/reports/`
- Persist to DB as `agent_report`
- Emit `agent_report_generated` event

### Phase C: Observatory TUI — Timeline + Detail (~300 LOC, ~10 tests)
- `ObservatoryEngine` state machine (like PRReviewEngine)
- Screens: timeline, decisions, questions, reports
- Left/right split pane rendering
- EventBus subscription for live updates
- KeyMode support (emacs/vim/arrows)

### Phase D: Question Injection (~150 LOC, ~5 tests)
- Answer input in Questions tab
- POST to decision queue API
- EventBus publish for agent notification
- Batch submit (Ctrl-S) like `/decide`

### Phase E: Report Rendering + Heatmap (~100 LOC, ~4 tests)
- Expand/collapse report cards
- Priority heatmap overlay
- Agent status indicators (running/done/blocked)

**Total**: ~900 LOC, ~33 tests, 5 phases

---

## 7. Data Flow

```
Agent (tmux pane)
  ↓ emits ShikiEvent (decision, milestone, question, report)
  ↓
EventBus (InProcessEventBus — DONE)
  ├→ ShikiDBEventLogger (persistent — DONE)
  ├→ Observatory TUI (live subscription — NEW)
  └→ ntfy (critical events only — DONE)

Human (Observatory TUI)
  ↓ answers question in Questions tab
  ↓
Decision Queue API (POST /api/decision-queue)
  ↓
Agent receives answer (via heartbeat check or hook injection)
```

---

## 8. What this replaces

| Today (painful) | With Observatory |
|-----------------|-----------------|
| Scroll 500 lines to find a decision | Timeline shows decisions only |
| Copy-paste loses scroll position | Detail panel shows full context |
| Switch tmux panes to check agents | Reports tab shows all agents |
| Find question, read context, respond inline | Questions tab with pre-loaded context |
| "What happened yesterday?" = read git log | Decisions tab with chain traceability |
| "Why did we choose X?" = grep through output | Decision chain: parent → child → child |
| No structured summary after agent finishes | Agent Report Card generated automatically |

---

## 9. Out of Scope

- Web dashboard (TUI-first, web later if needed)
- Real-time tmux pane mirroring (too complex, low value)
- AI-generated summaries of agent output (post-launch, needs community flywheel)
- Multi-user observatory (single user for now)

---

## 10. Critical References

- Event Bus architecture: `features/shiki-event-bus-architecture.md`
- `/decide` TUI pattern: screenshots from 2026-03-15 session (tab navigation + options + submit)
- PRReviewEngine pattern: `ShikiCtlKit/Services/PRReviewEngine.swift` (state machine model)
- Attention zones: `ShikiCtlKit/Services/SessionLifecycle.swift` (heatmap levels)
- Paperclip motion analysis: research project on structured agent observation
