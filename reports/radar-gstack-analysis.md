# Radar: gstack (garrytan/gstack) — Competitive Analysis

**Date**: 2026-03-18
**Author**: Shiki Intelligence (automated deep-dive)
**Repo**: https://github.com/garrytan/gstack
**Stars**: ~23,800 (7 days old — fastest-growing dev tool on GitHub in 2026)
**License**: MIT
**Language**: TypeScript (Bun runtime)
**Version**: 0.3.3

---

## What Is gstack?

gstack is an open-source "software factory" by Garry Tan (Y Combinator President & CEO), released 2026-03-11. It turns Claude Code into a structured virtual engineering team via 15 Markdown-based slash commands. Each command embodies a specialist persona (CEO, Staff Engineer, QA Lead, Release Engineer, etc.) with opinionated review checklists and workflows.

The headline feature beyond prompts is `/browse` — a persistent headless Chromium daemon (Playwright + Bun) that gives Claude Code "eyes" via sub-second HTTP commands. This is real compiled software, not just prompt files.

**Productivity claim**: Tan reports 10,000+ LOC and 100 PRs/week over 50 days using this setup.

---

## Who Is Garry Tan?

- President & CEO of Y Combinator (since 2023)
- Former YC partner, co-founded Initialized Capital
- Former designer/engineer at Palantir
- Massive distribution: 500K+ Twitter followers, direct access to every YC batch
- This matters: gstack will be the default recommendation for every YC startup using Claude Code

---

## Architecture Deep-Dive

### Three-Layer Stack

```
Claude Code (tool calls)
    ↓
CLI (compiled Bun binary, ~58MB)
    ↓ HTTP POST (localhost, Bearer token auth)
Server (Bun.serve → Chromium via CDP)
```

### Key Technical Decisions

| Decision | Detail |
|----------|--------|
| Runtime | Bun (compiled binaries, native SQLite, native TS) |
| Browser | Persistent Chromium daemon, auto-start/auto-stop (30min idle) |
| Latency | ~3s cold start, 100-200ms subsequent commands |
| Port | Random 10000-60000 (supports 10 concurrent workspaces) |
| Security | localhost-only, Bearer token (UUID), macOS Keychain for cookies |
| State | `~/.gstack/browse.json` (atomic write, 0o600 perms) |
| Protocol | Plain HTTP (no WebSocket, no MCP — intentional) |
| Logging | 3 ring buffers × 50K entries, async disk flush every 1s |
| Element refs | ARIA accessibility tree → `@e1, @e2` refs → Playwright Locators (no DOM mutation) |
| Cookie import | Reads Chromium SQLite DB → PBKDF2+AES decrypt in-memory → Playwright context |
| Tests | 3-tier: static validation (free), E2E via `claude -p` (~$3.85), LLM-as-judge (~$0.15) |
| Version sync | Git rev-parse → auto-restart server on binary mismatch |

### Skill System

Each skill is a directory with `SKILL.md` (generated) and `SKILL.md.tmpl` (human-authored). A build script (`gen-skill-docs.ts`) injects code-derived metadata into placeholders, keeping docs truthful. CI validates freshness via `--dry-run + git diff`.

**Preamble system**: Every skill starts with update check, session tracking (3+ sessions → "ELI16 mode"), optional contributor logging, and standardized AskUserQuestion format.

### 41 Browser Commands

- **13 READ**: text, html, links, forms, accessibility, js, eval, css, attrs, console, network, cookies, storage
- **17 WRITE**: goto, click, fill, select, hover, type, press, scroll, wait, viewport, cookie-import, etc.
- **11 META**: snapshot, screenshot, tabs, chain, diff, responsive, pdf, etc.

---

## The 15 Slash Commands

| Command | Role | What It Does |
|---------|------|-------------|
| `/plan-ceo-review` | CEO/Founder | 10-star product taste review, scope modes (expand/hold/reduce), mandatory ASCII diagrams |
| `/plan-eng-review` | Engineering Manager | Architecture lock, edge-case analysis, dependency mapping |
| `/plan-design-review` | Senior Designer | 80-item design audit, catches AI-generated UI patterns |
| `/design-consultation` | Design Partner | Builds design systems, mockups, creates DESIGN.md |
| `/design-review` | Designer Who Codes | Audits AND fixes design issues atomically |
| `/review` | Staff Engineer | 2-pass checklist (critical + informational), fix-first (auto-fix or ask), scope drift detection |
| `/ship` | Release Engineer | Full pipeline: merge, test bootstrap, coverage audit, review, version bump, CHANGELOG, bisectable commits, PR |
| `/browse` | QA Engineer | Persistent Chromium, 41 commands, @ref element addressing |
| `/qa` | QA Lead | Browser-based testing, bug finding, regression test generation |
| `/qa-only` | QA Reporter | Bug reporting without code modifications |
| `/setup-browser-cookies` | Session Manager | Imports authenticated browser sessions from local browsers |
| `/retro` | Engineering Manager | Weekly retrospectives with per-person metrics |
| `/office-hours` | YC Office Hours | Startup/builder brainstorming |
| `/debug` | Debugger | Systematic root-cause investigation |
| `/document-release` | Technical Writer | Synchronizes READMEs, architecture docs, contributor guides |

---

## Architecture Comparison: gstack vs Shiki

| Dimension | gstack | Shiki |
|-----------|--------|-------|
| **Core paradigm** | Prompt-based skill system (Markdown personas) | Event-driven orchestrator (Swift binary + ShikiEvent protocol) |
| **Language** | TypeScript/Bun | Swift (NIO), with Deno backend |
| **Agent orchestration** | Persona-per-command (stateless) | Event Router + Session Lifecycle + multi-company budget tracking |
| **Multi-project** | Conductor (10 concurrent workspaces via worktrees) | Multi-company with budget allocation, workspace isolation |
| **Event system** | None — each slash command is fire-and-forget | ShikiEvent + InProcessEventBus (typed, observable) |
| **State persistence** | `~/.gstack/browse.json` (browser only) | Shiki DB (PocketBase), session events, context compaction |
| **TUI** | None (outputs to Claude Code terminal) | Observatory + Command Palette (planned) |
| **Review tools** | `/review` with 2-pass checklist + auto-fix | PR Review TUI + Risk Engine + qmd semantic search |
| **Browser automation** | Persistent Chromium daemon, 41 commands, @ref system | None (not in scope) |
| **QA/Visual testing** | `/qa` with real browser, screenshot, responsive testing | None (not in scope) |
| **Design review** | `/plan-design-review` (80-item audit) + `/design-review` (fix) | None (agent personas like @Hanami fill this role conversationally) |
| **Shipping pipeline** | `/ship` — full automated merge→test→review→PR | Manual (git flow + PR workflow) |
| **Test framework** | 3-tier (static + E2E + LLM judge) | S3 Spec Syntax + TPDD |
| **Session tracking** | File-touch based (`~/.gstack/sessions/$PPID`) | Shiki DB events (context_session_start/end/compaction) |
| **Notification** | None | ntfy.sh → iPhone/Watch push with approve/deny |
| **Documentation** | Template-generated SKILL.md (code-truthful) | Manual (CLAUDE.md, feature specs) |
| **Distribution** | MIT, 23K+ stars, YC network | AGPL-3.0, private, single-user |
| **Target user** | Technical founders, first-time Claude Code users | Power user (you), multi-project orchestration |
| **Philosophy** | "Completeness is cheap" — boil the lake | "Attention zones" — show everything, never filter |

---

## What gstack Does That Shiki Doesn't

### 1. Browser Automation (Critical Gap)
The persistent Chromium daemon is genuinely impressive engineering. Sub-second commands, @ref element addressing via ARIA tree, cookie import from local browsers, responsive testing, screenshot/PDF capture. This is not "just prompts" — it's a compiled binary with real architecture.

**Relevance to Shiki**: Low for orchestration, but high if Shiki ever needs QA/visual verification for web projects (Maya landing pages, OBYW.one).

### 2. One-Command Shipping (`/ship`)
The full pipeline from merge → test bootstrap → coverage audit → review → version bump → CHANGELOG → bisectable commits → PR is impressive automation. It collapses an entire release engineering workflow into one command.

**Relevance to Shiki**: High. Shiki's shipping is still manual git flow. A `shiki ship` command that does even half of this would save significant time.

### 3. Design Review System
The 80-item design audit specifically catches AI-generated UI patterns ("slop detection"). The `/design-review` command both audits AND fixes atomically.

**Relevance to Shiki**: Medium. @Hanami fills this role conversationally, but a structured checklist-based approach with auto-fix would be more reliable.

### 4. Scope Drift Detection
`/review` compares stated intent (TODOS.md, PR description, commits) against actual file changes. Flags scope creep automatically.

**Relevance to Shiki**: High. This is a common problem in long agent sessions.

### 5. Template-Generated Docs (Code-Truthful)
SKILL.md files are generated from `.tmpl` templates with code-derived placeholders. CI validates freshness. Documentation literally cannot drift from code.

**Relevance to Shiki**: Medium. Shiki's CLAUDE.md is manually maintained. Template generation would prevent staleness.

### 6. Session Counting → "ELI16 Mode"
At 3+ concurrent sessions, all skills switch to a mode that re-grounds context on every question, acknowledging the user is juggling multiple windows.

**Relevance to Shiki**: High. Shiki already manages multi-session via tmux. Adding cognitive-load awareness is smart.

### 7. Contributor Mode / Field Reports
When enabled, agents file casual field reports to `~/.gstack/contributor-logs/` when gstack itself misbehaves. Crowdsourced improvement data.

**Relevance to Shiki**: Low (single-user), but the pattern of self-reporting tool failures is good.

---

## What Shiki Does That gstack Doesn't

### 1. True Orchestration Layer
Shiki is an orchestrator with event routing, session lifecycle, and multi-project budget tracking. gstack is a collection of independent skills with no shared state or coordination between them. Each `/command` is stateless and fire-and-forget.

### 2. Event Architecture
ShikiEvent protocol + InProcessEventBus provides typed, observable event streams. gstack has zero event system — skills don't communicate with each other.

### 3. Multi-Project / Multi-Company Management
Shiki manages WabiSabi, Maya, Brainy, DSKintsugi, Research Lab — each with distinct contexts, branches, and concerns. gstack operates on one repo at a time.

### 4. Persistent Knowledge Layer
Shiki DB stores session events, context compaction, project memory, and cross-session state. gstack's only persistence is browser state and file-touch session tracking.

### 5. Push Notification System
ntfy.sh integration with iPhone/Watch approve/deny actions. gstack has nothing — you stare at the terminal.

### 6. Agent Personas with Domain Knowledge
@Sensei (CTO), @Hanami (UX), @Kintsugi (philosophy), @Enso (brand), @Tsubaki (copy), @Shogun (market) — each carries accumulated context. gstack's personas are reset on every invocation.

### 7. PR Review with Risk Engine + Semantic Search
Shiki's PR review pipeline includes risk triage, qmd semantic search, delta/fzf, and AI fix agents. gstack's `/review` is a structured checklist (excellent, but no risk scoring or semantic search).

### 8. Native Binary Architecture
Swift/NIO compiled binary with SystemD services in production. gstack is Bun/TS — faster to iterate, but not in the same performance class.

### 9. tmux-Based Session Management
Physical pane management, session numbers, 4h retention, research workflows. gstack delegates this entirely to Conductor (Claude's built-in worktree manager).

### 10. Context Optimization
Proactive compaction, DB-first context recovery, priority-tiered snapshots. gstack's context management is limited to the ELI16 session-count heuristic.

---

## Ideas Worth Stealing

### Priority 1 — Adopt Now

**1. `/ship` pipeline as `shiki ship`**
Create a `shiki ship` command that automates: merge base, run tests, coverage audit, pre-landing review, version bump, CHANGELOG generation, bisectable commit splitting, and PR creation. This is the single highest-value feature gstack offers. Adapt to git flow (target develop, not main).

**2. Scope drift detection in PR review**
Add to `shiki pr` review: compare TODOS/PR description/commit messages against actual diff. Flag additions/removals that weren't in stated scope. Simple to implement, high value.

**3. Fix-first review pattern**
gstack's review classifies findings as AUTO-FIX or ASK, then applies auto-fixes immediately and batches ASK items into one user prompt. Adopt this for Shiki's PR review engine — currently our review is read-only output.

### Priority 2 — Plan for Next Release

**4. Template-generated documentation**
Create `.tmpl` files for CLAUDE.md and SKILL.md equivalents. Build script injects code-derived sections. CI validates freshness. Prevents doc drift.

**5. Session-aware cognitive load adjustment**
When Shiki detects 3+ active agent sessions, adjust prompt verbosity and re-grounding behavior. Simple file-touch counting, high impact on multi-session clarity.

**6. Design slop detection checklist**
Formalize @Hanami's design review into a structured checklist. gstack's 80-item audit specifically targets AI-generated UI patterns. Create `shiki review --design` flag.

### Priority 3 — Consider for Roadmap

**7. Browser automation for landing page QA**
Not core to Shiki's orchestration mission, but for OBYW.one/Maya landing pages, having a `shiki qa <url>` that spins up a headless browser and runs visual regression would be valuable. Could be a separate tool that integrates with Shiki's event bus.

**8. Bisectable commit splitting**
gstack's `/ship` automatically groups changes into logical, independently-valid commits ordered by dependency. This is excellent git hygiene automation.

**9. Test bootstrap detection**
Auto-detect project runtime, install testing framework if missing, generate initial tests. Useful when starting new packages.

---

## Competitive Assessment

### Is This a Direct Competitor?

**No.** gstack and Shiki operate at different layers:

- **gstack** = Claude Code skill pack (prompts + browser tool). It enhances a single Claude Code session with structured workflows. It has no orchestration, no multi-project management, no persistent state beyond browser sessions.

- **Shiki** = Platform orchestrator. It manages multiple projects, agents, sessions, events, and system-level concerns (tmux, notifications, deployment).

They are **complementary, not competing**. You could theoretically use gstack skills inside Shiki-managed sessions.

### gstack's Moat

1. **Distribution**: 23K stars in 7 days. YC network = every batch company will try it. MIT license = zero friction.
2. **Garry Tan's brand**: "The YC president ships 10K LOC/week with this" is an unbeatable marketing message.
3. **Browser automation**: The Chromium daemon is real engineering. Not trivially replicable.
4. **Community momentum**: Hiring full-time developers to harden it. Open contributor pipeline.

### Shiki's Moat

1. **Deep orchestration**: Event bus, session lifecycle, multi-project budget — gstack has none of this.
2. **Native performance**: Swift/NIO compiled binary vs Bun/TS. Different performance class.
3. **Persistent knowledge**: Shiki DB as long-term brain vs gstack's stateless skills.
4. **Opinionated workflow**: git flow, PR review with risk scoring, tmux layout management — integrated system vs collection of tools.
5. **Single-user focus**: No community overhead. Every feature serves one power user's actual workflow.

### Target User Comparison

| | gstack | Shiki |
|---|--------|-------|
| Primary | Technical CEO/founder who wants to ship faster | Power developer managing multiple complex projects |
| Secondary | First-time Claude Code users wanting structure | N/A (single-user tool) |
| Skill level | Any (opinionated defaults help beginners) | Expert (assumes deep system knowledge) |
| Scale | One repo at a time | Multi-project, multi-company |

### Threat Level: **Low-Medium**

gstack won't replace Shiki's orchestration layer, but it will:
1. Set expectations for what "Claude Code workflows" look like (prompt-based, persona-driven)
2. Normalize the pattern of role-based AI development
3. Potentially attract the same "AI-augmented developer" mindset

The real risk is **mindshare**: if every YC startup uses gstack, the "skill-pack" paradigm becomes the default mental model for AI dev tools, making Shiki's deeper orchestration approach harder to explain.

---

## Key Takeaways

1. **gstack is 80% prompts, 20% real engineering** — but that 20% (browser daemon) is genuinely good.
2. **The `/ship` pipeline is the most valuable pattern to adopt** — it collapses release engineering into one command.
3. **Fix-first review and scope drift detection are low-hanging fruit** for Shiki's PR review engine.
4. **Not a competitor at the orchestration layer** — but a massive distribution play that sets industry norms.
5. **The browser automation is irrelevant to Shiki's core** — but nice-to-have for landing page QA.
6. **Template-generated docs are a smart pattern** worth adopting to prevent CLAUDE.md drift.

---

## Sources

- [garrytan/gstack — GitHub](https://github.com/garrytan/gstack)
- [gstack: Garry Tan's Claude Code Skill Setup — SitePoint](https://www.sitepoint.com/gstack-garry-tan-claude-code/)
- [Y Combinator CEO's GStack Explodes with 20K Stars — BEAMSTART](https://beamstart.com/news/why-garry-tans-claude-code-17737808027728)
- [A CTO Called It "God Mode" — DEV Community](https://dev.to/createitv/a-cto-called-it-god-mode-garry-tan-just-open-sourced-how-he-ships-10000-lines-of-code-per-week-1ck7)
- [Why Garry Tan's Claude Code setup has gotten so much love, and hate — TechCrunch](https://techcrunch.com/2026/03/17/why-garry-tans-claude-code-setup-has-gotten-so-much-love-and-hate/)
- [Garry Tan's gstack: Running Claude Like an Engineering Team — Medium](https://agentnativedev.medium.com/garry-tans-gstack-running-claude-like-an-engineering-team-392f1bd38085)
- [GStack — Product Hunt](https://www.producthunt.com/products/gstack)
- [Garry Tan's gstack Uses the Same Play — TurboDocx](https://www.turbodocx.com/blog/garry-tan-gstack)
