---
name: manaflow-ai/cmux
type: reference
description: Ghostty-based macOS terminal multiplexer with vertical tabs and AI coding agent notifications
source: https://github.com/manaflow-ai/cmux
relevance: HIGH — Swift macOS terminal tool purpose-built for AI agent workflows
discovered: 2026-03-28
---

## What It Is

`cmux` is a Swift macOS terminal built on Ghostty's rendering engine, adding vertical tab navigation and a notification system specifically designed for AI coding agents (Claude Code, Codex, etc.). It bridges the gap between a standard terminal emulator and an AI-agent-aware workflow tool.

## Why It Matters to Shikki

- **Designed for the same user**: Targets developers running AI coding agents — exactly Shikki's audience.
- **Agent notification API**: Exposes a system for agents to push status updates into the terminal UI. Shikki could hook into this for pipeline status, quality gate results, and review completions.
- **Vertical tab layout**: A UX pattern optimized for multiple concurrent agent sessions — relevant if Shikki supports parallel pipeline execution.
- **Swift + Ghostty**: Same tech stack affinity as Shikki's Swift components.

## Key Patterns to Study

- How it receives and renders agent notifications (inter-process communication model)
- Vertical tab state management
- Integration points for external tools (protocol, socket, CLI flags)
- How it handles concurrent agent sessions

## Action Items

- [ ] Install and test `cmux` as the default terminal for Shikki development sessions
- [ ] Investigate the notification API — assess whether Shikki pipelines can emit events to it
- [ ] Check if it exposes a Swift package or CLI hook for programmatic notification injection
- [ ] Evaluate as a recommended setup in Shikki's Quick Start guide
