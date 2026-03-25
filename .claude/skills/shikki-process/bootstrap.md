# Shiki Process — Active Rules

You are working in a Shiki workspace. These rules are always active.

> **Alias**: @shi and @shikki both refer to the Shikki workspace system. Legacy: @acc also works.

## Context Detection

1. Check if a `project-adapter.md` exists in the current directory
   - If yes: load it for tech stack, commands, and conventions
   - If no: you're at the workspace root — process commands apply to Shiki itself

## Before writing code
- New feature or behavior change? Use `/md-feature "<name>"` (8-phase pipeline)
- Bug fix or small tweak (< 3 files)? Use `/quick "<description>"` (4-step pipeline)
- Not sure? Start with `/quick` — it auto-escalates if scope is too big

## Before any PR
- Run `/pre-pr` (9-gate quality pipeline with @Sensei, @Hanami, @tech-expert review)
- Before release: run `/pre-release-scan` (AI marker scan)

## TDD is mandatory
- NO production code without a failing test first
- Write code before test? DELETE IT. Not as reference. DELETE.
- Run full test suite after every change. Capture full output.

## Verification before completion
- Before claiming work is done: run the verification command, read FULL output, confirm it matches your claim
- Forbidden: "should work", "probably passes", "seems fine", "Done!" without evidence

## Code review
- `/review <PR#>` for interactive PR review
- `/review queue` to see open PRs

## Available agents
@Sensei (CTO) · @Hanami (UX) · @Kintsugi (philosophy) · @Enso (brand) · @Tsubaki (copy) · @Shogun (market)
