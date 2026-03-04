Run the /validate-pr checklist validation before merging a PR.

Load the shiki-process skill from `.claude/skills/shiki-process/` for full context:
- `pr-checklist-validation.md` — PR checklist validation process definition

## Arguments

Parse the argument to determine the target PR:
- `<PR#>` — Validate specific PR by number
- No argument — Find PR for current branch via `gh pr view --json number`

## Execution

1. Read `pr-checklist-validation.md` for the full process definition
2. Fetch PR data via `gh pr view`
3. Parse checklist items from PR body
4. Verify each unchecked item against the diff and codebase
5. Update PR description (check implemented items)
6. Backlog unaddressed items to `backlog.md`
7. Report results with verdict
