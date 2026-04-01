---
name: oh-my-claudecode Reference
type: reference
description: Teams-first multi-agent orchestration layer for Claude Code — architecture patterns for Shikki's /dispatch pipeline
source: https://github.com/Yeachan-Heo/oh-my-claudecode
discovered: 2026-04-01
relevance: HIGH
---

## What It Is

`oh-my-claudecode` by Yeachan-Heo is a TypeScript framework for teams-first multi-agent orchestration on top of Claude Code. Trended at 1,126 stars in a single day (2026-04-01).

## Why It Matters to Shikki

Shikki's `/dispatch` pipeline coordinates multiple specialized agents (Sensei, Hanami, tech-expert, etc.) in parallel. `oh-my-claudecode` tackles the same coordination problem — orchestrating multiple Claude Code instances toward a shared goal — but from a teams/organizational angle rather than Shikki's persona/role angle.

Key patterns to extract:
- **Role-based agent specialization** — how agents are assigned lanes (code, review, test, deploy)
- **Cross-agent message passing** — how results from one agent are fed as context to the next
- **Conflict resolution** — when two agents produce incompatible outputs, how the orchestrator arbitrates
- **Session lifecycle management** — how team sessions are initialized, paused, and resumed

## Connection to Shikki Architecture

| oh-my-claudecode concept | Shikki equivalent |
|---|---|
| Team session | `/dispatch` run |
| Agent role definition | @Sensei, @Hanami persona files |
| Orchestrator | `dispatch` skill entry point |
| Cross-agent context passing | Memory files in `memory/` |

## Action Items

- [ ] Clone and read the orchestrator entry point — understand message-passing protocol between agents
- [ ] Extract role-definition format — compare to Shikki's persona files
- [ ] Evaluate if their session resumption patterns can improve Shikki's `/retry` skill
