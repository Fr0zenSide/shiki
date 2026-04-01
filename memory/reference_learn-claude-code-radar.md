---
name: learn-claude-code Reference
type: reference
description: Nano reimplementation of Claude Code's agent harness from 0 to 1 — direct insight into Shikki's harness primitives
source: https://github.com/shareAI-lab/learn-claude-code
discovered: 2026-04-01
relevance: HIGH
---

## What It Is

`learn-claude-code` by shareAI-lab is a TypeScript project described as "Bash is all you need — A nano claude code–like agent harness, built from 0 to 1." Trended at 1,141 stars in a single day (2026-04-01).

## Why It Matters to Shikki

Shikki is itself built on top of the Claude Code agent harness. Understanding the harness internals at a primitive level directly informs:
- Why certain Shikki skills behave the way they do
- Where context window budget actually goes
- How the tool loop is structured (and where to add hooks)
- What "Bash is all you need" implies for Shikki's over-engineered skill surface

This is essentially a reference implementation of Shikki's own foundation layer — studying it can expose assumptions Shikki bakes in that could be simplified.

## Key Primitives to Extract

- **Minimal tool loop** — the core read-eval-act cycle stripped to essentials
- **Context management** — how a nano harness handles the context window without the full Claude Code machinery
- **Bash-first execution model** — why the author claims Bash suffices as the primary tool
- **Agent bootstrapping** — how the agent initializes from zero without a complex session-start hook

## Connection to Shikki Architecture

| learn-claude-code primitive | Shikki equivalent |
|---|---|
| Minimal tool loop | Session-start hook + CLAUDE.md loading |
| Context budget allocation | Memory files in `memory/` |
| Bash tool invocation | Shikki skill execution via Bash tool |
| Agent bootstrap | startup hook in settings.json |

## Action Items

- [ ] Read the core tool loop implementation — compare to how Shikki's session-start hook initializes state
- [ ] Identify simplification opportunities in Shikki's skill surface based on the "Bash is all you need" thesis
- [ ] Extract context budget management approach — evaluate against Shikki's memory file strategy
