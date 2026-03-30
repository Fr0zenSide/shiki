---
name: obra/superpowers — Radar Reference
type: reference
description: Agentic skills framework and software development methodology — HIGH relevance for Shikki skills architecture
source: https://github.com/obra/superpowers
detected: 2026-03-29
relevance: HIGH
---

## What It Is

`obra/superpowers` is an agentic skills framework and software development methodology built around the principle that skills (modular, composable agent capabilities) are the right primitive for AI-assisted development. It is the #2 trending repo across all GitHub languages on 2026-03-29 with 2,292 stars today and 120,923 total.

## Why It Matters to Shikki

This is the closest public analog to Shikki's own skills system. Key overlaps:

- **Skills as primitives** — Shikki's skill files (`.claude/skills/`) are the same core concept; superpowers provides a larger, battle-tested reference implementation
- **Methodology, not just tooling** — the "methodology that works" framing mirrors Shikki's process-first approach (md-feature pipeline, TDD gates, etc.)
- **Shell-based** — the Shell language means it works across any agent backend, similar to Shikki's backend-agnostic skill design
- **120k stars** — massive community adoption means skills in this repo are field-validated

## Architectural Questions to Investigate

1. How are skills structured? (file format, frontmatter, naming convention)
2. Is there a discovery/registry mechanism? How do agents find applicable skills?
3. How does it handle skill composition and chaining?
4. Any dependency or conflict resolution between skills?
5. How does it compare to Shikki's 8-phase md-feature pipeline?

## Recommended Action

Run `/ingest https://github.com/obra/superpowers` and compare the skills catalog against Shikki's. Identify:
- Skills in superpowers not in Shikki → candidates for adoption
- Skills in Shikki not in superpowers → Shikki's differentiators
- Overlapping skills with different implementations → pick the better pattern
