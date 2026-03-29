---
name: Yeachan-Heo/oh-my-claudecode — Radar Reference
type: reference
description: Teams-first multi-agent orchestration for Claude Code — HIGH relevance for Shikki's @agent orchestration layer
source: https://github.com/Yeachan-Heo/oh-my-claudecode
detected: 2026-03-29
relevance: HIGH
---

## What It Is

`oh-my-claudecode` is a TypeScript framework providing teams-first multi-agent orchestration on top of Claude Code. It enables multiple specialized agents to collaborate on a task, similar to how a software team divides work. Trending at 858 stars today, 14,786 total.

## Why It Matters to Shikki

Direct architectural overlap with Shikki's persona system (@Sensei, @Hanami, @Kintsugi, etc.):

- **"Teams-first"** — models agent collaboration as a team dynamic, not just chained prompts; mirrors Shikki's named specialist agents
- **Orchestration on Claude Code** — built on the same substrate Shikki runs on; no impedance mismatch
- **TypeScript** — inspectable, forkable; not a black box
- **Multi-agent coordination** — how agents hand off tasks, share context, and reach consensus is exactly what Shikki's `/pre-pr` pipeline does manually

## Architectural Questions to Investigate

1. How does it define and route tasks to specialized agents?
2. What is the "team" primitive — static roster or dynamic selection?
3. How does context (conversation history, file state) flow between agents?
4. Does it support parallel agent execution or only sequential?
5. How does it handle agent disagreement / conflict resolution?
6. Does it have a concept analogous to Shikki's @Sensei (final arbiter)?

## Shikki Integration Opportunities

- Could `oh-my-claudecode`'s orchestration layer replace or inform Shikki's manual multi-agent pipeline steps in `/pre-pr` and `/md-feature`
- The "teams-first" routing model could formalize how Shikki decides which agent handles which phase (UX → @Hanami, architecture → @Sensei, etc.)
- TypeScript codebase is auditable for Claude Code hook integration patterns

## Recommended Action

Clone and run a test multi-agent task. Map its agent routing model to Shikki's persona roster. Assess adoption vs. inspiration path.
