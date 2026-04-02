---
name: openai/codex — Lightweight Terminal Coding Agent (Rust)
type: reference
description: OpenAI's Rust-native terminal coding agent — architectural comparison to Claude Code and Shikki's harness
source: https://github.com/openai/codex
radar_date: 2026-04-02
relevance: HIGH
---

## What It Is

`openai/codex` is OpenAI's terminal-native coding agent written entirely in Rust. It positions itself as a "lightweight coding agent that runs in your terminal" — a direct parallel to Claude Code and therefore a direct architectural reference for everything Shikki wraps.

## Why It Matters to Shikki

Shikki is built on Claude Code's agent harness. Codex is the primary competitor agent in the same terminal-native, agentic-coding-tool category. Understanding how Codex implements its tool loop, permission model, and CLI UX gives Shikki a precise calibration surface:

1. **What Claude Code does that Codex doesn't** — gaps to exploit, Shikki differentiators to emphasize
2. **What Codex does better** — patterns worth porting back into Shikki's harness conventions
3. **Rust as implementation language** — signals performance-first design priorities; relevant if Shikki ever considers native extension tooling

## Key Architecture Signals (from trending context)

- **Rust-native**: Full rewrite in Rust signals a commitment to startup performance and binary distribution — no Node.js runtime dependency, instant cold starts
- **"Lightweight" framing**: Explicit contrast with heavier agentic runtimes; implies minimal dependency surface and fast feedback loops
- **Terminal-first**: Same interaction model as Claude Code — no web UI, no electron wrapper, pure CLI

## Shikki Integration Assessment

| Dimension | Codex | Claude Code + Shikki | Action |
|-----------|-------|---------------------|--------|
| Runtime language | Rust | Shell + Node | Study startup latency approach |
| Distribution | Single binary | Requires Node | Note for Shikki native tooling |
| Agent loop | Unknown | Hook-augmented loop | Audit on release |
| Permission model | Unknown | Tool approval per-call | Compare approaches |
| Multi-model | Via OpenRouter? | Claude only + Shikki routing | Gap |

## Relevance to Active P0/P1 Work

- `/dispatch` parallel agents — understanding Codex's isolation model informs Shikki's worktree dispatch
- Skill portability — `farion1231/cc-switch` already supports both; Shikki skills may need Codex compatibility layer
- Competitive context for Shikki positioning docs

## Action Items

- [ ] Audit Codex README and source for tool loop implementation details
- [ ] Compare permission/approval model to Claude Code's approach
- [ ] Track Codex community adoption signals (skills ecosystem, plugins)
- [ ] Evaluate whether Shikki skill definitions should export Codex-compatible format (see `EveryInc/compound-engineering-plugin` cross-platform pattern)
