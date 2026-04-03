---
name: oh-my-codex (OmX) Reference
type: reference
description: Competitor/reference analysis of Yeachan-Heo/oh-my-codex — hooks, agent teams, HUD framework for OpenAI Codex and multi-model AI coding agents
source: https://github.com/Yeachan-Heo/oh-my-codex
discovered: 2026-04-03
relevance: HIGH
---

## What It Is

oh-my-codex (branded OmX) is a harness framework for OpenAI Codex — doing for Codex exactly what oh-my-claudecode does for Claude Code. It adds hooks, agent teams, HUDs, and extensibility on top of the base Codex CLI. Built in TypeScript. At 12,040 stars on day one of trending, its velocity matches oh-my-claudecode's peak surge.

## Why It Matters to Shikki

Shikki is exactly this product: a harness on top of a Claude Code CLI that adds structure, pipelines, agent personas, and observability. The emergence of OmX confirms that the "harness-on-top-of-agent-CLI" pattern is not Claude-specific — it is the dominant distribution layer across the entire AI coding ecosystem. This has two implications:

1. **Pattern validation**: Shikki's architectural bets (hooks system, agent teams via personas, workflow pipelines) are independently confirmed by a high-velocity project targeting a competing CLI.
2. **Cross-tool pressure**: If OmX gains adoption parity with oh-my-claudecode, users will expect Shikki-equivalent capability on Codex. The multi-model portability question becomes existential: does Shikki remain Claude-only depth, or does it expose a model-agnostic harness layer?

## Key Features (Known)

- **Hooks**: Lifecycle hooks analogous to Shikki's `session-start-hook` and `update-config` skill — pre/post agent action interception
- **Agent Teams**: Multi-agent coordination layer, likely persona-based (analogous to Shikki's @Sensei/@Hanami model)
- **HUDs**: Heads-up display for agent state — terminal overlay showing live agent status, possibly similar to oh-my-claudecode's status bar extensions
- **Extensibility**: Plugin/extension model allowing community contributions (analogous to Shikki's skill library)

## Architectural Gaps Shikki Should Assess

- Does Shikki have an equivalent HUD/ambient status surface? (claude-island and cc-switch address this adjacently)
- Does Shikki's hook system expose the same lifecycle points OmX does?
- Is there a cross-tool compatibility story for Shikki's skills (cf. EveryInc/compound-engineering-plugin's Bun CLI)?

## Action Items

- [ ] Deep-read OmX source to map hook API surface against Shikki's hooks
- [ ] Extract OmX's team coordination model — how are agent roles defined and task-routed?
- [ ] Assess HUD implementation — what data is surfaced and how does it hook into Codex events?
- [ ] Compare OmX plugin lifecycle against Shikki skill lifecycle (invoke, update, retire)
- [ ] Decision needed: Claude-depth-only vs. multi-model harness layer — OmX makes this question urgent
