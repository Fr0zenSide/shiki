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

## Implementation Plan

### Wave 1: Capture Hook + ShikiDB Events (~100 LOC)
- Claude Code `Stop` hook that parses conversation for Skill tool calls
- Extracts command names (strips args)
- POSTs `command_invoked` events to ShikiDB via MCP
- Script: `~/.claude/hooks/practice-memory-capture.sh`

### Wave 2: Chain Detection (~150 LOC)
- Batch analysis at session end
- Group commands within 60s window
- Detect recurring chains (5+ in 7 days)
- Store `chain_detected` events in ShikiDB

### Wave 3: Weekly Report Integration (~80 LOC)
- Query ShikiDB for command frequency + chains
- Render "Practice Memory" section in `/report` output
- Include alias suggestions when threshold met

### Wave 4: Alias System (~120 LOC)
- `shikki alias <name> '<chain>'` — create custom alias
- Aliases stored in `~/.shikki/aliases.json`
- Built-in aliases: `/🔥` = brainstorm+challenge+team
- `shikki alias list` — show all aliases with usage count

### Wave 5: Remote Telemetry (future, P2)
- Opt-in via `shikki settings telemetry on`
- Aggregated weekly counts to Umami or ShikiDB remote
- k-anonymity: only report if 5+ users share same pattern
- Dashboard at analytics.shikki.dev (future)

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
