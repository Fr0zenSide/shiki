# ShikiQA — Visual Quality Assurance for Code & UI

> Extracted from shiki-ctl. The review engine brain + TUI snapshot testing.
> Will become: code review + Swift QC + DSKintsugi storybook + visual diff.

## What's here (from shiki-ctl)

- **PRReviewEngine** — state machine (verdict, navigate, comment input) ← keep, it's solid
- **PRReviewParser** — markdown to structured review ← keep
- **PRReviewState** — persistence (JSON save/load) ← keep
- **PRRiskEngine** — heuristic risk scoring per file ← keep
- **PRCacheBuilder** — git diff → cache files ← keep
- **PRReviewRenderer** — TUI renderer ← REWRITE (buggy: paste, scroll, exit)
- **TerminalSnapshot** — golden file snapshot testing ← keep, extend for CLI QA

## What's coming

- `shiki pr 6 | shiki-qa --web` — pipe review data to web visual QA
- `shiki pr 6 | shiki-qa --swift` — pipe to Swift QC snapshot comparison
- Visual diff: before/after screenshots with delta overlay
- Component library view (DSKintsugi storybook integration)
- CLI/TUI snapshot testing (capture terminal output, compare golden files)

## Status

Extracted, not yet standalone. Needs its own Package.swift and dependency cleanup.
