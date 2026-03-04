Run the /course-correct workflow for mid-feature scope changes.

Load the shiki-process skill from `.claude/skills/shiki-process/` for full context:
- `course-correct.md` — Course correction protocol
- `feature-pipeline.md` — Feature pipeline phases

## Arguments

- `"<feature>"` — Start course correction on the named feature

## Execution

1. Read `course-correct.md` for the full protocol
2. Load the feature file from `features/<feature>.md`
3. Ask what changed
4. Trace impact through all phases
5. Propose a correction plan for @Daimyo approval
