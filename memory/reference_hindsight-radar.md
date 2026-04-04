---
name: vectorize-io/hindsight Reference
type: reference
description: Agent memory system that learns from prior interactions — adaptive retrieval over flat storage
source: https://github.com/vectorize-io/hindsight
first_seen: 2026-04-04
relevance: HIGH
---

## Overview

**vectorize-io/hindsight** — Python, 7,115 total stars, 114 today (2026-04-04). "Hindsight: Agent Memory That Learns."

Built by Vectorize, a vector search/retrieval company. Hindsight is not a static memory store — it improves retrieval quality by learning from how agents actually use the memories it surfaces. The name is intentional: "hindsight" = the memory system gets smarter by observing what was actually useful in retrospect.

## Why It Matters for Shikki

### Shikki's Current Memory Model

Shikki uses flat markdown files in `memory/` directories:
- `memory/radar/` — trending repo radar files (like this one)
- `memory/reference_*.md` — deep-dive reference files
- `memory/features/` — feature specifications
- `memory/context/` — session context

Retrieval is manual: the agent reads files by name or the startup hook loads relevant context by convention.

### What Hindsight Adds

1. **Learned retrieval** — Instead of loading all context or relying on explicit file naming, Hindsight learns which memories are actually useful for which tasks. Over time, "when working on a PR review task, memory X is almost always relevant" becomes encoded in the retrieval weights.

2. **Relevance feedback loop** — The system observes when a surfaced memory was used vs. ignored and updates retrieval accordingly. Shikki's radar files currently have no feedback loop — a reference file created in March might be completely forgotten by April.

3. **Semantic search over flat files** — Hindsight likely provides vector search over Shikki's existing markdown memory files, enabling "what have we seen related to MCP servers?" to return relevant entries from across the radar history.

4. **Cross-session memory** — Shikki's current approach loses context between sessions (beyond what's in CLAUDE.md). Hindsight-style persistent learned memory would let Shikki agents remember "the last 3 times we did a pre-pr, the linter check failed on X pattern" without explicit documentation.

## Architecture Fit

Shikki's `memory/` directory structure is already a natural corpus for Hindsight ingestion. The flat markdown files are clean, structured, and consistently formatted — ideal for vector embedding.

Potential integration:
```
memory/ → Hindsight ingestion → learned retrieval index
→ Startup hook queries Hindsight for session-relevant context
→ Hindsight surfaces top-N relevant memories
→ Agent uses surfaced memories; unused ones get downranked
```

## Questions

- [ ] Does Hindsight support markdown file corpora natively or require structured data?
- [ ] What's the local deployment story — can it run fully offline on macOS?
- [ ] How does it handle Shikki's mixed content types (radar files vs. feature specs vs. reference notes)?
- [ ] What's the learning latency — how many feedback signals before retrieval improves?
- [ ] Does Hindsight expose an MCP server interface? (Would be the ideal integration point)

## Action Items

- [ ] Run Hindsight against Shikki's existing `memory/` directory as a proof-of-concept
- [ ] Evaluate local vs. Vectorize-hosted deployment models
- [ ] Prototype a startup hook that queries Hindsight for session context instead of loading all radar files
- [ ] Assess whether Hindsight's learning model is worth the complexity vs. structured manual tagging
- [ ] Check if Hindsight ships an MCP server interface — instant integration if so
