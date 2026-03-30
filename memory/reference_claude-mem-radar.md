---
name: thedotmack/claude-mem — Radar Reference
type: reference
description: Auto-captures everything Claude does during coding sessions — HIGH relevance for Shikki's memory system
source: https://github.com/thedotmack/claude-mem
detected: 2026-03-29
relevance: HIGH
---

## What It Is

`claude-mem` is a Claude Code plugin that automatically captures all actions, decisions, and artifacts from Claude coding sessions into persistent memory — without manual `/ingest` calls. Trending at 389 stars today, 42,004 total stars (exceptionally high adoption for a plugin).

## Why It Matters to Shikki

42k stars signals this is already widely deployed. Key relevance to Shikki:

- **Auto-capture vs. manual memory** — Shikki currently relies on `/ingest` and explicit memory writes; claude-mem suggests an always-on passive capture model is strongly desired by the community
- **Session → memory pipeline** — the automatic capture pattern could replace or augment Shikki's manual memory writes in `memory/` directories
- **"Everything Claude does"** — captures decisions, not just outputs; this is richer than Shikki's current memory which captures reference docs and radar findings

## Architectural Questions to Investigate

1. What does it capture? (file changes, tool calls, reasoning steps, all of the above?)
2. How is captured data structured and stored? (markdown files, vector DB, JSON?)
3. Does it de-duplicate or compress sessions over time?
4. How does it handle memory retrieval — does it inject into context automatically?
5. Is it a Claude Code hook, an MCP server, or a wrapper?
6. Privacy: can captures be scoped (project-level, global)?

## Shikki Integration Opportunities

- **Replace manual memory writes** in pipelines: if claude-mem can capture pipeline execution traces, Shikki's memory files could become auto-generated rather than manually crafted
- **Upgrade `/ingest`**: could become "ingest from session history" rather than only from external URLs
- **Audit trail**: automatic capture provides a full audit of what happened in each `/md-feature` or `/pre-pr` run — useful for retrospectives and debugging

## Risk Assessment

- 42k stars but no obvious backing org — verify maintenance status before deep adoption
- "Everything" capture may create noise; need filtering/summarization to remain useful at scale
- Check if captures are stored locally or sent to external service

## Recommended Action

Install in a test Shikki session. Compare what it captures to what Shikki's manual memory system records. If complementary, evaluate as a foundation layer for Shikki's auto-memory feature.
