Run the /md-feature pipeline for structured feature creation.

Load the shiki-process skill from `.claude/skills/shiki-process/` for full context:
- `feature-pipeline.md` — 8-phase process definition and feature file template
- `agents.md` — agent persona definitions for brainstorm and review phases

If a `project-adapter.md` exists, read it for tech stack context.

## Arguments

Parse the argument to determine the action:
- `"<name>"` — Start new feature at Phase 1 (Inspiration)
- `review "<name>"` — Revisit existing feature, present summary, Q&A
- `status` — List all features in `features/` and their current phase
- `next "<name>"` — Advance feature to next phase

## Execution

1. Read `feature-pipeline.md` for the full phase definitions
2. Read `feature-tracking.md` for README roadmap tracking rules
3. Read `agents.md` for persona context when spawning brainstorm agents
4. If `project-adapter.md` exists, read for tech stack and conventions
5. Create or update `features/<name>.md` using the template
6. Execute the current phase per the pipeline definition
7. Update `README.md` -> `## Feature Roadmap` checklist (check completed phase, update WIP counter)
8. After each phase, sync to Shiki API if available (POST to `/api/memories`)
9. At Phase 7, hand off to `/pre-pr`
