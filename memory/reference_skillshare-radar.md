---
name: runkids/skillshare
type: reference
description: One-command skills sync across all AI CLI tools — Codex, Claude Code, OpenClaw, Gemini CLI
source: https://github.com/runkids/skillshare
relevance: HIGH — directly addresses Shikki's cross-project skills distribution problem
discovered: 2026-03-28
---

## What It Is

`skillshare` is a Go CLI tool that synchronizes skills (slash commands, agent plugins) across all major AI coding CLI tools with a single command. Supports Claude Code, Codex, OpenClaw, and Gemini CLI. Designed for teams to maintain a shared skills library across tools and projects.

## Why It Matters to Shikki

- **Solves Shikki's distribution gap**: Shikki ships skills (`.claude/skills/`) tied to a single workspace. `skillshare` addresses the cross-tool, cross-project propagation problem.
- **Team-sharing primitive**: Aligns with Shikki's team-based model — shared skills owned by the team, not just the individual.
- **Multi-tool compatibility**: Shikki's skills could be distributed to non-Claude-Code users via this layer.
- **Go CLI architecture**: Reference implementation for how skills manifests and sync protocols could work.

## Key Patterns to Study

- Skills manifest format (how tools describe skills for cross-tool compatibility)
- Sync mechanism (git-based? API? local file sync?)
- Conflict resolution when skills differ between tools
- How it handles tool-specific syntax differences in skill definitions

## Action Items

- [ ] Run `/ingest https://github.com/runkids/skillshare` for full architecture notes
- [ ] Map Shikki's current `.claude/skills/` structure against `skillshare`'s manifest format
- [ ] Evaluate whether Shikki should ship a `skillshare`-compatible manifest alongside its native format
- [ ] Consider contributing Shikki's skills library to the `skillshare` ecosystem as a distribution channel
