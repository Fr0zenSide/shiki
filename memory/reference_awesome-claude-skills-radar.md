---
name: awesome-claude-skills Reference
type: reference
description: Community-curated master list of Claude Skills — gap analysis source for Shikki's skill library
source: https://github.com/ComposioHQ/awesome-claude-skills
discovered: 2026-04-01
relevance: HIGH
---

## What It Is

`awesome-claude-skills` by ComposioHQ is a curated list of awesome Claude Skills, resources, and tools for customizing Claude AI workflows. Trended at 374 stars in a single day (2026-04-01).

## Why It Matters to Shikki

Shikki ships a set of named skills (`/quick`, `/md-feature`, `/dispatch`, `/pre-pr`, `/review`, `/radar`, etc.). The community is now curating a master list of Claude Skills. This repo is both:

1. A **gap-analysis source** — enumerate what skills the community has built and identify patterns Shikki hasn't covered
2. A **discoverability signal** — if `awesome-claude-skills` lists skills similar to Shikki's, it validates the skill model; if it lists entirely different categories, those are blind spots

## Gap Analysis Framework

For each skill category in the list, classify against Shikki:
- `EXISTS` — Shikki has a matching skill
- `PARTIAL` — Shikki covers this partially but incompletely
- `MISSING` — Shikki has no equivalent; evaluate for addition
- `OUT_OF_SCOPE` — not relevant to Shikki's domain

## Connection to Shikki Architecture

Shikki's skill system is defined in `.claude/skills/` and surfaced via `settings.json`. Any new skills identified from this gap analysis should follow the existing skill file format and go through the `/md-feature` pipeline before being added.

## Action Items

- [ ] Read the full awesome-claude-skills README and enumerate all skill categories
- [ ] Run gap analysis against Shikki's current skill inventory
- [ ] For each MISSING skill with MEDIUM+ relevance, open a `/quick` or `/md-feature` ticket
- [ ] Check if ComposioHQ's own Composio integration patterns are relevant to Shikki's agent tool ecosystem
