---
name: oh-my-openagent Reference
type: reference
description: 47k-star agent harness (formerly oh-my-opencode) — the largest harness repo in the ecosystem
source: https://github.com/code-yeongyu/oh-my-openagent
first_seen: 2026-04-04
relevance: HIGH
---

## Overview

**code-yeongyu/oh-my-openagent** (formerly `oh-my-opencode`) — TypeScript agent harness with 47,866 total stars as of 2026-04-04. The "omo" CLI branding. Renamed from `oh-my-opencode` to `oh-my-openagent`, signaling a deliberate pivot from OpenCode-specific tooling to a fully model-agnostic harness.

At nearly 48k stars, this is the highest-starred agent harness in the ecosystem — higher than oh-my-claudecode, higher than oh-my-codex. Its existence reframes the competitive landscape: Shikki is not competing with 3k-star repos, it's operating in a space where the ceiling is 47k+.

## Why It Matters for Shikki

1. **Scale reference** — 47k stars on a harness repo is proof the market exists at significant scale. The architecture choices that drove that growth are worth reverse-engineering.

2. **Naming evolution** — `oh-my-opencode` → `oh-my-openagent` is a deliberate category expansion: "code" → "agent" signals the market is moving from coding-assistant-wrapper to general agent harness. Shikki may want to track whether its own framing leans too hard into "Claude Code harness" rather than "agent harness."

3. **"omo" brand** — Short CLI brand name alongside verbose repo name. Shikki's brand/CLI naming pattern (`shi`/`shiki`) follows the same convention.

4. **Relationship to oh-my-claudecode/oh-my-codex** — The three repos (oh-my-claudecode, oh-my-codex, oh-my-openagent) appear to be partially overlapping projects from different authors, all riding the same harness wave. oh-my-openagent's 47k head start suggests it predates the others and may have seeded the pattern.

## Key Architecture Questions to Investigate

- [ ] What primitives does omo expose that Shikki doesn't (hooks, teams, HUDs, memory)?
- [ ] How does omo handle multi-agent team coordination vs. Shikki's @Sensei/@Hanami model?
- [ ] What's omo's skill/plugin distribution model — how do users install community harness extensions?
- [ ] How does omo's 47k-star growth curve break down (viral moment vs. sustained)?
- [ ] What specific features drove the rename from oh-my-opencode → oh-my-openagent?

## Action Items

- [ ] Clone and audit omo's full command taxonomy
- [ ] Map against Shikki's skill list — identify gaps and redundancies
- [ ] Study omo's team/agent coordination model
- [ ] Evaluate omo's memory/context persistence approach
- [ ] Consider whether Shikki's positioning should explicitly differentiate from omo (Claude-depth vs. model-breadth)
