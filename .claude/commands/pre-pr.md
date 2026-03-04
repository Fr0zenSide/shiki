Run the /pre-pr quality gate pipeline before creating a PR.

Load the shiki-process skill from `.claude/skills/shiki-process/` for full context:
- `pre-pr-pipeline.md` — gate definitions and flow
- `agents.md` — agent persona definitions
- `checklists/cto-review.md` — @Sensei checklist
- `checklists/ux-review.md` — @Hanami checklist
- `checklists/code-quality.md` — @tech-expert checklist
- `ai-slop-scan.md` — AI marker scan patterns

If a `project-adapter.md` exists, read it for:
- Test/build commands
- Language-specific addon checklists to activate
- Visual QC configuration

## Mode Detection

- `--web` — Web Mode (Gates 1-4 + 9, no visual QC, no @Hanami)
- `--skip-qc` — Skip visual QC gate (Gates 1-4 + 8-9)
- `--adversarial` — Add Gate 1c (@Ronin adversarial review)
- `--yolo` — Auto-proceed through passing gates
- Default — Full mode (all 9 gates)

## Execution

1. Read the skill files above for checklists and flow
2. Run `git diff` to get the changes
3. Execute gates sequentially per `pre-pr-pipeline.md`
4. Stop on failure, report to user, enter fix loop
5. After all gates pass, create PR via `gh pr create`
6. Return the PR URL

Show a summary table after each gate completes.
