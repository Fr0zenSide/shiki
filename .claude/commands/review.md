Run the /review interactive PR review session.

Load the shiki-process skill from `.claude/skills/shiki-process/` for full context:
- `pr-review.md` — Interactive review process definition
- `agents.md` — Agent persona definitions for review
- `checklists/cto-review.md` — @Sensei checklist
- `checklists/ux-review.md` — @Hanami checklist
- `checklists/code-quality.md` — @tech-expert checklist

If a `project-adapter.md` exists, read it for language-specific addon checklists.

## Arguments

Parse the argument to determine the action:
- `<PR#>` — Start interactive review of specific PR
- `queue` — Show all open PRs with priority ranking
- `batch` — Review all open PRs sequentially
- No argument — Show review queue

## Execution

1. Read `pr-review.md` for the full review process
2. Load PR data via `gh` CLI
3. Run pre-analysis with review agents
4. Enter interactive review mode with the user
5. Post review to GitHub when user decides
