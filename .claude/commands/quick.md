Run the /quick pipeline for small, well-understood changes.

Load the shiki-process skill from `.claude/skills/shiki-process/` for full context:
- `quick-flow.md` — Quick Flow process definition
- `checklists/code-quality.md` — @tech-expert checklist (reused)

If a `project-adapter.md` exists, read it for test commands and conventions.

## Arguments

Parse the argument as the change description:
- `"<description>"` — Start Quick Flow with the given description
- `--yolo` — Skip confirmations, auto-proceed through all steps

## Execution

1. Read `quick-flow.md` for the full process definition
2. Read `feature-tracking.md` for README roadmap tracking rules
3. If `project-adapter.md` exists, read it for test/build commands
4. Evaluate scope — if complex, recommend escalation to `/md-feature`
5. Create `features/<name>.md` with mini-spec, add entry to README Feature Roadmap
6. Execute the Quick Flow steps, updating README checklist after each step
7. On completion, offer to commit and create PR
