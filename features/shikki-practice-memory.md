---
title: "Practice Memory — Usage Analytics + Command Efficiency"
status: draft
priority: P1
project: shikki
created: 2026-04-02
authors: ["@Daimyo"]
tags: [analytics, ux, aliases, telemetry, weekly-report]
relates-to: ["shikki-hot-reload-restart"]
---

# Feature: Practice Memory — Usage Analytics + Command Efficiency
> Created: 2026-04-02 | Status: Spec Draft | Owner: @Daimyo

## Context

Shikki has no visibility into how commands are used. The user discovered they invoke `/🌟🧠🌟@t` (brainstorm+challenge+team) constantly — but there's no shortcut, no alias, no data showing this pattern. Practice Memory captures command usage, detects chains, suggests aliases, and feeds the weekly `/report`.

**Philosophy:** Shikki learns your kata — it watches practice patterns and suggests shortcuts when repetition proves intent. Never tracks *what* you work on, only *how* you work.

## @t Consensus

| Decision | Rationale |
|----------|-----------|
| Hooks capture, ShikiDB stores | Zero new infrastructure — `agent_events` table exists |
| Chain detection is batch (session end) | No real-time state machine, simpler |
| Suggestions at session end, not mid-flow | Don't interrupt the kata |
| Command names only, no args | Privacy by design |
| Remote telemetry default OFF | Opt-in explicit via `shikki settings` |
| "Practice Memory" not "analytics" | Tool-not-master philosophy |

## Business Rules

| BR | Rule |
|----|------|
| BR-01 | Only `Skill` tool invocations are tracked — not Read/Write/Bash/Agent |
| BR-02 | Alias suggestion threshold: 5+ identical chains in 7 days |
| BR-03 | Auto-combine suggestion at 80%+ correlation requires user confirmation — never auto-bind |
| BR-04 | Remote telemetry default OFF, toggle via `shikki settings telemetry on` |
| BR-05 | Chain window: commands within 60s of each other belong to same chain |
| BR-06 | Session boundary: 30min inactivity gap starts new session |
| BR-07 | No command arguments captured — command name + addressed agent only |
| BR-08 | Remote telemetry uses k-anonymity (min 5 users per bucket) |
| BR-09 | Weekly report "Practice Memory" section is max 5 lines |
| BR-10 | Alias suggestions appear only at session end summary, never mid-session |

## TDDP — Test-Driven Development Plan

| Test | BR | Tier | Type | Description |
|------|-----|------|------|-------------|
| T-01 | BR-01 | Core (80%) | Unit | Only Skill tool invocations are captured — Read/Write/Bash/Agent ignored |
| T-02 | BR-07 | Security (100%) | Unit | No command arguments captured — command name + agent only |
| T-03 | BR-05 | Core (80%) | Unit | Commands within 60s belong to same chain; >60s gap starts new chain |
| T-04 | BR-06 | Core (80%) | Unit | 30min inactivity gap starts new session boundary |
| T-05 | BR-02 | Core (80%) | Unit | 5+ identical chains in 7 days triggers alias suggestion |
| T-06 | BR-02 | Core (80%) | Unit | 4 identical chains in 7 days does NOT trigger suggestion |
| T-07 | BR-03 | Core (80%) | Unit | Auto-combine suggestion at 80%+ correlation requires user confirmation |
| T-08 | BR-10 | Core (80%) | Unit | Alias suggestions appear only at session end, never mid-session |
| T-09 | BR-04 | Security (100%) | Unit | Remote telemetry default OFF — no data sent without explicit opt-in |
| T-10 | BR-08 | Security (100%) | Unit | Remote telemetry uses k-anonymity (min 5 users per bucket) |
| T-11 | BR-09 | Smoke (CLI) | Unit | Weekly report "Practice Memory" section is max 5 lines |
| T-12 | BR-01 | Core (80%) | Integration | Stop hook parses conversation and POSTs command_invoked events to ShikiDB |
| T-13 | BR-05 | Core (80%) | Unit | Chain detection groups ["/spec", "/🌟🧠🌟@t"] as a single chain |
| T-14 | BR-09 | Smoke (CLI) | Unit | `shikki alias list` shows all aliases with usage count |

## Wave Dispatch Tree

```
Wave 1: Capture Hook + ShikiDB Events
  ├── practice-memory-capture.sh (Stop hook)
  ├── CommandInvokedEvent model
  └── ShikiDB POST via MCP (command_invoked events)
  Tests: T-01, T-02, T-09, T-12
  Gate: swift test --filter PracticeMemory → all green

Wave 2: Chain Detection ← BLOCKED BY Wave 1
  ├── DetectedChain model
  ├── Chain window logic (60s grouping)
  ├── Session boundary logic (30min gap)
  └── Recurring chain detection (5+ in 7d)
  Tests: T-03, T-04, T-05, T-06, T-07, T-08, T-13
  Gate: swift test --filter Chain → all green

Wave 3: Weekly Report ← BLOCKED BY Wave 2
  ├── ShikiDB query for command frequency + chains
  ├── "Practice Memory" section renderer
  └── Alias suggestion when threshold met
  Tests: T-11
  Gate: swift test --filter PracticeMemory → all green

Wave 4: Alias System ← BLOCKED BY Wave 2
  ├── shikki alias <name> '<chain>' command
  ├── aliases.json persistence
  ├── Built-in aliases (/🔥)
  └── shikki alias list with usage count
  Tests: T-14
  Gate: full swift test green

Wave 5: Remote Telemetry (future, P2) ← BLOCKED BY Wave 1
  ├── Opt-in toggle via shikki settings
  ├── k-anonymity aggregation
  └── Weekly count reporting
  Tests: T-09, T-10
  Gate: security audit + swift test green
```

## Data Model

```swift
// ShikiDB event payload
struct CommandInvokedEvent: Codable, Sendable {
    let command: String        // "/spec", "/quick", "/🔥" — name only, no args
    let agent: String?         // "@t", "@Sensei", nil
    let chainId: String        // groups commands in sequence (UUID)
    let sessionId: String
    let positionInChain: Int
    let timestamp: Date
}

// Chain detection (batch, post-session)
struct DetectedChain: Codable, Sendable {
    let commands: [String]     // ["/🌟🧠🌟@t", "/spec"]
    let frequency: Int         // 15 times this week
    let suggestedAlias: String? // "/🔥"
}
```

## Proposed Aliases (from pattern analysis)

| Pattern | Alias | Emoji | Meaning |
|---------|-------|-------|---------|
| `/🌟🧠🌟@t` | `/🔥` | fire | Brainstorm + challenge + team — forged through repetition |
| `/pre-pr` → `/review` | `/ship-check` | — | Pre-flight quality sequence |
| `/spec` → `/🌟🧠🌟@t` | `/forge` | — | Spec then challenge |
| `/quick` → `/pre-pr` | `/snap` | — | Quick fix then verify |

## Weekly Report Section Mockup

```
## Practice Memory (Apr 1–7)

Commands: /spec ×12  /quick ×8  /review ×6  /pre-pr ×5  /🔥 ×3
Top chain: /🌟🧠🌟@t → 15×  (try: /🔥)
Sessions: 9 avg 42min, 21 cmds/session
Trend: ▁▃▅▇ command diversity ↑ — 3 new commands this week
New alias available: `shikki alias forge 'spec,🌟🧠🌟@t'`
```

## Implementation Waves

### Wave 1: Capture Hook + ShikiDB Events (~100 LOC)
- **Files**: `~/.claude/hooks/practice-memory-capture.sh`, `ShikkiKit/Models/CommandInvokedEvent.swift`
- **Tests**: T-01, T-02, T-09, T-12
- **BRs**: BR-01, BR-04, BR-07
- **Deps**: ShikiDB MCP (exists)
- **Gate**: `swift test --filter PracticeMemory` green

### Wave 2: Chain Detection (~150 LOC) ← BLOCKED BY Wave 1
- **Files**: `ShikkiKit/Services/ChainDetector.swift`, `ShikkiKit/Models/DetectedChain.swift`
- **Tests**: T-03, T-04, T-05, T-06, T-07, T-08, T-13
- **BRs**: BR-02, BR-03, BR-05, BR-06, BR-10
- **Deps**: Wave 1 (CommandInvokedEvent), ShikiDB
- **Gate**: `swift test --filter Chain` green

### Wave 3: Weekly Report Integration (~80 LOC) ← BLOCKED BY Wave 2
- **Files**: `ShikkiKit/Services/PracticeMemoryReporter.swift`
- **Tests**: T-11
- **BRs**: BR-09
- **Deps**: Wave 2 (ChainDetector), Report service (exists)
- **Gate**: `swift test --filter PracticeMemory` green

### Wave 4: Alias System (~120 LOC) ← BLOCKED BY Wave 2
- **Files**: `Commands/AliasCommand.swift`, `~/.shikki/aliases.json`
- **Tests**: T-14
- **BRs**: BR-03 (confirmation gate)
- **Deps**: Wave 2 (DetectedChain)
- **Gate**: full `swift test` green

### Wave 5: Remote Telemetry (future, P2) ← BLOCKED BY Wave 1
- **Files**: `ShikkiKit/Services/TelemetryService.swift`
- **Tests**: T-09, T-10
- **BRs**: BR-04, BR-08
- **Deps**: Wave 1, Umami/ShikiDB remote
- **Gate**: security audit + `swift test` green

**Total estimate:** 4 waves now (~450 LOC), Wave 5 post-release

## Privacy Principles

1. **No args captured** — command names only, never content
2. **Local-first** — ShikiDB on localhost, no remote without explicit opt-in
3. **Aggregated for remote** — weekly counts, never raw sequences
4. **No behavioral fingerprinting** — remote telemetry uses k-anonymity
5. **Suggest, never auto-bind** — aliases require user confirmation
6. **Transparent** — `shikki practice show` dumps raw local data

## @shi Mini-Challenge

1. **@Ronin**: If the `Stop` hook parses the full conversation for Skill calls, it reads the entire chat. Is there a lighter-weight signal (e.g., Claude Code API for tool call history)?
2. **@Metsuke**: 4 metrics only to start. Which 4? Proposed: command frequency, chain frequency, commands-per-session, alias adoption rate.
3. **@Hanami**: The `/🔥` alias is single-emoji — but what if the user fat-fingers it? Should aliases also have text-only equivalents (`/fire`)?
