# Shiki Process Skill

Quality-gated development process for AI-assisted projects.
Defines agent personas, review checklists, feature pipeline, and release gates.
Adapts to any tech stack via the project adapter pattern.

## When to activate

This skill is relevant when:
- The user invokes `/quick`, `/pre-pr`, `/review`, `/md-feature`, `/course-correct`, `/dispatch`, `/pre-release-scan`, or `/retry`
- The user mentions agent names: @Sensei, @Hanami, @Kintsugi, @Enso, @Tsubaki, @Shogun, @Ronin
- The user asks about the development process, quality gates, or review workflows
- Code is being prepared for PR or release

## Project Adapter

Each project has a `project-adapter.md` that configures:
- Tech stack (language, framework, architecture)
- Test/build/lint commands
- Naming conventions
- Which review checklists to activate

See `project-adapter-template.md` for the full template.

## Skill contents

| File | Purpose |
|------|---------|
| `project-adapter-template.md` | Project adapter template — tech stack, commands, conventions |
| `agents.md` | Agent persona definitions — role, expertise, tone, checklist scope |
| `checklists/cto-review.md` | @Sensei code review checklist (architecture, error handling, performance) |
| `checklists/ux-review.md` | @Hanami UX review checklist (accessibility, design, emotional design) |
| `checklists/code-quality.md` | @tech-expert code quality checklist (hygiene, docs, tests) |
| `checklists/definition-of-done.md` | Phase 6 completion checklist — all items PASS before /pre-pr |
| `addons/cto-review-swift.md` | Swift-specific CTO review items (concurrency, actors, Sendable) |
| `addons/code-quality-swift.md` | Swift-specific quality items (Backport pattern, best practices) |
| `pre-pr-pipeline.md` | Full /pre-pr gate definitions and flow |
| `feature-pipeline.md` | 8-phase /md-feature process (1-5, 5b, 6, 7) + density check |
| `sdd-protocol.md` | Subagent-Driven Development protocol for Phase 6 implementation |
| `quick-flow.md` | Lightweight /quick pipeline (4 steps, TDD, scope guard) |
| `pr-review.md` | Interactive /review protocol (queue + dashboard, single PR, batch, auto-fix) |
| `pr-checklist-validation.md` | /validate-pr — verify PR checklist items before merge |
| `feature-tracking.md` | README Feature Roadmap — living checklist of feature progress |
| `ai-slop-scan.md` | Pre-release AI marker scan patterns and exclusions |
| `verification-protocol.md` | Verification-before-completion — hard gate against false "Done!" claims |
| `course-correct.md` | Mid-feature scope change — impact trace, classify, rewind |
| `parallel-dispatch.md` | Parallel feature dispatch — autonomous multi-branch implementation |
| `elicitation.md` | Advanced elicitation — structured deep-thinking methods at phase checkpoints |
| `bootstrap.md` | SessionStart hook injection — compact rules always in context |
| `process-overview.md` | Full process diagram, file structure, portability guide |

## Commands powered by this skill

| Command | What it does |
|---------|-------------|
| `/quick "<description>"` | Lightweight change pipeline (bug fix, tweak, refactor) |
| `/quick "<description>" --yolo` | Quick Flow with no confirmations |
| `/pre-pr` | Full quality gate pipeline -> PR creation |
| `/pre-pr --web` | Simplified pipeline for web projects |
| `/pre-pr --skip-qc` | Skip visual QC gate |
| `/pre-pr --adversarial` | Add Gate 1c adversarial review (@Ronin) |
| `/pre-pr --yolo` | Auto-proceed through passing gates (skip confirmations) |
| `/md-feature "<name>"` | Start feature creation pipeline (8 phases) |
| `/md-feature review "<name>"` | Revisit existing feature |
| `/md-feature status` | List all features and their phases |
| `/md-feature next "<name>" --yolo` | Advance phases with auto-proceed |
| `/review <PR#>` | Interactive review of a specific PR |
| `/review queue` | Show open PRs ranked by priority |
| `/review batch` | Review all open PRs sequentially |
| `/pre-release-scan` | Scan for AI markers before release |
| `/course-correct "<feature>"` | Mid-feature scope change |
| `/dispatch "<feature>"` | Dispatch a feature for autonomous parallel implementation |
| `/dispatch all` | Dispatch all ready features |
| `/dispatch status` | Show dispatch board |
| `/dispatch cancel "<feature>"` | Cancel a running dispatch |
| `/validate-pr <PR#>` | Validate PR checklist items before merge |
| `/retry` | Scan and relaunch stuck sub-agents |

## Philosophy

> "We don't add quality at the end. We start with it."

Business rules first. Tests second. Code third. Review always.
