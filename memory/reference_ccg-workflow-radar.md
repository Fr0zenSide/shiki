---
name: fengshao1227/ccg-workflow Reference
type: reference
description: Claude+Codex+Gemini multi-model orchestration system with 28 dev workflow commands
source: https://github.com/fengshao1227/ccg-workflow
first_seen: 2026-04-04
relevance: HIGH
---

## Overview

**fengshao1227/ccg-workflow** — Go, 4,874 total stars, 69 today (2026-04-04). Full description (translated): "Multi-model collaborative dev system — Claude orchestrates + Codex backend + Gemini frontend, 28 commands spanning the full dev workflow, one-click zero-config install."

CCG = Claude + Codex + Gemini. The architecture: **Claude as the orchestrator/planner**, Codex as the backend implementation engine, Gemini as the frontend implementation engine. 28 CLI commands covering the complete software development lifecycle. Go binary, zero-config install.

## Why It Matters for Shikki

### The Architecture Shikki Implicitly Reaches Toward

Shikki's dispatch pipeline conceptually does multi-agent orchestration but within a single model (Claude). CCG makes the multi-model architecture explicit and productionized:

```
CCG: Claude (plan) → Codex (backend) → Gemini (frontend)
Shikki: Claude (all) → Claude (parallel dispatch)
```

The question for Shikki: is single-model depth (Claude-only, maximum context, harness-enhanced) or multi-model breadth (Claude orchestrates, specialized models execute) the better architecture for complex features?

CCG's 4.9k stars suggests the multi-model orchestration model has real user demand.

### The 28-Command Taxonomy

A Chinese-language workflow system that maps 28 distinct commands to the full dev lifecycle is itself a valuable artifact. The fact that it took 28 commands to cover "the full workflow" implies a taxonomy that Shikki's skill set should be mapped against. Shikki likely covers many of these, but the gaps could reveal features worth building.

Categories likely covered (to verify):
- Planning/architecture commands
- Backend implementation commands
- Frontend implementation commands
- Testing commands
- Review/PR commands
- Deploy commands
- Debug/fix commands
- Documentation commands

### Orchestration Pattern Worth Studying

Claude as orchestrator (not implementer) is a specific architectural choice: Claude's reasoning and planning capabilities are used for decomposition and coordination, while execution is delegated to faster/cheaper specialized models. This is the opposite of Shikki's current model where Claude does both.

For Shikki's expensive features (full feature implementation via dispatch), Claude-as-orchestrator-only could dramatically reduce cost and latency.

## Key Questions

- [ ] What are the 28 commands? Map them against Shikki's skill set.
- [ ] How does CCG handle Claude↔Codex↔Gemini context passing? What's the inter-model protocol?
- [ ] What's the orchestration format — is Claude writing structured JSON instructions or natural language to the other models?
- [ ] How does CCG handle failures in sub-model execution (Codex fails, Gemini returns wrong output)?
- [ ] What does "zero-config install" mean — does it bundle model credentials somehow?
- [ ] Is the Claude orchestrator prompt available in the repo?

## Action Items

- [ ] Translate and map the 28-command taxonomy against Shikki's full skill list
- [ ] Study the inter-model context-passing protocol (how Claude talks to Codex and Gemini)
- [ ] Evaluate whether Claude-as-orchestrator-only mode for Shikki's dispatch would be beneficial
- [ ] Identify the 3-5 commands in CCG that Shikki has no equivalent for
- [ ] Consider whether ccg-workflow's architecture is worth adapting vs. extending Shikki's single-model dispatch
