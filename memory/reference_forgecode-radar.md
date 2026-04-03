---
name: forgecode Reference
type: reference
description: Competitor/reference analysis of antinomyhq/forgecode — multi-model AI pair programmer in Rust supporting Claude, GPT, Grok, Gemini, Deepseek, and 300+ models
source: https://github.com/antinomyhq/forgecode
discovered: 2026-04-03
relevance: HIGH
---

## What It Is

forgecode is a terminal-native AI pair programmer written in Rust that functions as a unified interface across Claude, GPT, O-series, Grok, Deepseek, Gemini, and 300+ models via a single CLI. Positioned as "AI enabled pair programmer" — not a workflow harness but a model-agnostic coding agent layer. 252 stars today, Rust ecosystem.

## Why It Matters to Shikki

forgecode represents the opposite end of the design spectrum from Shikki:

| Dimension | Shikki | forgecode |
|-----------|--------|-----------|
| Model support | Claude-only (depth) | 300+ models (breadth) |
| Implementation | Shell/MD pipelines | Rust binary |
| Focus | Workflow orchestration | Pair programming UX |
| Distribution | Skills + hooks | Single binary |
| Philosophy | Claude-native depth | Model-agnostic portability |

This contrast is valuable for two reasons:

1. **Calibration**: Clarifies what Shikki is _not_ trying to be. Shikki's value proposition is Claude-specific depth — tight integration with Claude Code's hook system, persona prompts tuned to Anthropic's models, pipelines designed around Claude's capabilities. forgecode's breadth-first approach trades that depth for portability.

2. **User overlap risk**: Shikki users who need to switch models (due to cost, availability, or task type) will reach for forgecode or cc-switch. Shikki should understand this gap.

## Architectural Observations

- **Rust binary**: Zero-dependency distribution — installs as a single executable. Shikki's shell/markdown approach has the opposite tradeoff (readable/hackable but requires Claude Code runtime).
- **300+ model support**: Likely uses an OpenRouter-compatible abstraction layer, not direct API integrations per model.
- **"Pair programmer" framing**: More interactive/conversational than Shikki's pipeline-oriented model. forgecode likely does not have a `/quick → /pre-pr` lifecycle equivalent.
- **Claude as first-class**: Claude is listed first in the supported models, suggesting forgecode may be optimized for Claude's tool use patterns even while supporting others.

## Integration Opportunity

Shikki could position forgecode as a "breadth layer" for users who need multi-model access — Shikki handles Claude-deep workflows, forgecode handles model-switching use cases. A `shiki bridge forgecode` skill could theoretically proxy non-Claude tasks to forgecode while keeping Shikki's orchestration layer.

## Action Items

- [ ] Read forgecode source — assess tool loop implementation and Claude API integration depth
- [ ] Map forgecode's UX primitives (sessions, context, tool approval) vs. Shikki's pipeline primitives
- [ ] Decision needed: should Shikki document a "when to use forgecode vs. Shikki" guide for users?
- [ ] Assess whether forgecode's multi-model abstraction exposes anything Shikki could wrap for non-Claude subtasks in `/dispatch`
