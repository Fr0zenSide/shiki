# Shiki Research Adoption Plan — Battle-Tested Patterns from OpenRouter, Anthropic Skills, gstack

> Phase: Spec (ready for @Daimyo review)
> Priority: Cross-cutting — feeds into multiple backlog items
> Date: 2026-03-19
> Sources: OpenRouter, Anthropic Skills, Vercel Skills CLI, gstack (garrytan/gstack)

---

## Part 1: gstack Agents vs @shi Team — Head-to-Head Battle

### The Matchups

| gstack Persona | Shiki Equivalent | Who Wins | Why |
|---------------|-----------------|----------|-----|
| CEO/Founder (`/plan-ceo-review`) | @Daimyo (human) | **Shiki** | gstack simulates a CEO. We have the real one. No prompt can replace @Daimyo's judgment. |
| Staff Engineer (`/review`) | @Sensei + @Ronin | **Shiki** | gstack has a 2-pass checklist. We have @Sensei (architecture) + @Ronin (adversarial) — two passes with different intents. Plus our PR Risk Engine scores severity. gstack's review is read-only output; our @Ronin protocol forces 5+ findings minimum. |
| Senior Designer (`/plan-design-review`) | @Hanami | **gstack** | gstack's 80-item checklist specifically catches AI-generated UI slop. @Hanami is empathetic and philosophical but lacks a structured audit. We need to arm @Hanami with a checklist. |
| Designer Who Codes (`/design-review`) | — | **gstack** | We don't have an agent that both audits AND fixes design issues atomically. @Hanami reviews, but doesn't fix. |
| Release Engineer (`/ship`) | — | **gstack** | We have no shipping automation. Manual git flow. This is the single biggest gap. |
| QA Lead (`/qa`, `/browse`) | — | **gstack** | Browser automation is real engineering. We have nothing here. |
| Engineering Manager (`/retro`) | — | **gstack** | Weekly retros with per-person metrics. We track via DB events but don't synthesize into retros. |
| Design Partner (`/design-consultation`) | @Hanami + @Enso | **Shiki** | Our design personas carry accumulated context. gstack's reset per invocation. |
| Debugger (`/debug`) | @Sensei | **Draw** | Both systematic. gstack has a dedicated persona; we use @Sensei who does more. |
| Technical Writer (`/document-release`) | — | **gstack** | We don't have a docs sync agent. Template-generated docs are smart. |
| Market Analyst | @Shogun | **Shiki** | @Shogun has persistent DB context across sessions. gstack has no market persona. |
| Brand/Copy | @Enso + @Tsubaki | **Shiki** | Two specialized personas (brand + copy) vs none in gstack. |
| Philosophy | @Kintsugi | **Shiki** | Unique to our team. No equivalent anywhere. |
| Security | @Katana | **Shiki** | Server-level security expert with weekly audit protocol. gstack has nothing. |
| Adversarial | @Ronin | **Shiki** | Dedicated red team. gstack's review is cooperative only. |

### Scoreboard

| | gstack Wins | Shiki Wins | Draw |
|---|---|---|---|
| **Count** | 4 | 8 | 1 |
| **Gaps** | Design audit, shipping, QA/browser, docs sync | — | — |

**Verdict**: Shiki's team is deeper and smarter in the areas it covers. gstack wins in areas we haven't built yet — shipping automation, design slop detection, QA, and docs sync. These are all solvable without new agents, except one.

---

## Part 2: Design Validation Patterns to Adopt

### Steal Now (feeds existing backlog)

#### 1. Fix-First Review → upgrade `shiki pr`
**What**: Review classifies findings as AUTO-FIX or ASK. Auto-fixes apply immediately. ASK items batch into one @Daimyo prompt.
**Where**: PR Review Engine (P1 backlog)
**Effort**: Medium — add classification to PRReviewParser output, auto-fix via Edit tool for LOW/MEDIUM severity.

#### 2. Scope Drift Detection → upgrade `shiki pr`
**What**: Compare PR description + commit messages against actual diff. Flag additions/removals outside stated scope.
**Where**: PRRiskEngine
**Effort**: Low — diff PR description tokens against changed file paths/functions. Alert on >30% mismatch.

#### 3. Effort-Based Agent Routing → AgentProvider
**What**: Use Claude API `output_config.effort` to right-size agent compute. `low` for triage, `high` for implementation, `max` for architecture.
**Where**: AgentProvider protocol + dispatch
**Effort**: Low — add effort parameter to dispatch config.

#### 4. Model Fallback + Price Routing → AgentProvider (via OpenRouter)
**What**: OpenRouter as backend provider. Automatic fallbacks (Claude → GPT → Gemini). Price-weighted routing for non-critical agents.
**Where**: AgentProvider protocol
**Effort**: Medium — add OpenRouter as a provider backend. Config: `provider: openrouter` with routing preferences.

#### 5. Eval-Driven Skill Iteration → shiki-process
**What**: Anthropic's skill-creator pattern. For each skill: spawn with-skill AND baseline agents, grade assertions, aggregate, iterate.
**Where**: `/pre-pr` quality gate, skill quality
**Effort**: High — need eval framework. But the methodology is clear.

### Steal Next Release

#### 6. `shiki ship` Pipeline
**What**: One command: merge base → run tests → coverage audit → review → version bump → CHANGELOG → bisectable commits → PR.
**Where**: New `ShipCommand` in shiki-ctl
**Effort**: High — but highest-value single feature from gstack. Adapt to git flow (target develop).

#### 7. Session-Aware Cognitive Load
**What**: At 3+ active sessions, adjust prompt verbosity and re-grounding behavior.
**Where**: Orchestrator session manager
**Effort**: Low — count active tmux panes, adjust system prompt prefix.

#### 8. Template-Generated CLAUDE.md
**What**: `.tmpl` files with code-derived placeholders. Build script injects. CI validates freshness.
**Where**: All projects
**Effort**: Medium — create `scripts/gen-claude-md.sh`, template per project.

### Consider for Roadmap

#### 9. Design Slop Detection Checklist
**What**: 80-item audit specifically targeting AI-generated UI patterns. Arm @Hanami with it.
**Where**: `checklists/design-slop-audit.md`
**Effort**: Low — write the checklist. @Hanami already exists.

#### 10. Browser QA for Landing Pages
**What**: `shiki qa <url>` with headless Chromium for OBYW.one/Maya.
**Where**: New tool or integration with Playwright MCP
**Effort**: High — but gstack proved the pattern.

---

## Part 3: Agent Persona Proposals

Based on the gaps analysis, here are **targeted** proposals. Philosophy: only add what we genuinely need. No bloat.

### Proposed: @Kenshi — Release Engineer

**Why**: Shipping is our biggest gap. `shiki ship` needs an agent who understands release engineering — version semantics, changelog generation, bisectable commits, test gating.

**Role**: Release automation specialist. Owns the path from "code is ready" to "PR is merged."

**Expertise**:
- Semantic versioning and changelog generation
- Git flow release process (develop → release/* → main)
- Test gating and coverage thresholds
- Bisectable commit ordering (dependency graph → logical groups)
- PR creation with structured summaries
- Pre-release validation checklists

**Tone**: Methodical, checklist-driven, zero shortcuts. "If the tests didn't pass, it doesn't ship. Period."

**When to invoke**: `shiki ship`, release prep, version bumps, changelog review.

**Justification**: gstack's `/ship` is their most valuable feature. We need the capability, and it deserves a dedicated persona because shipping is a distinct expertise from code review or architecture.

---

### Proposed: @Metsuke — Quality Inspector (Design Validation)

**Why**: @Hanami is empathetic and philosophical — she catches UX problems through intuition. But she doesn't have a structured checklist for AI-generated slop. We need a quality inspector who catches what passes the "looks okay" test.

**Role**: Structured quality auditor for code AND design output. The inspector who finds what cooperative reviewers consider "fine."

**Expertise**:
- AI slop detection in code (unnecessary abstractions, over-engineering, boilerplate patterns)
- AI slop detection in UI (generic gradients, meaningless icons, template layouts, placeholder-quality copy)
- Scope drift measurement (stated intent vs actual changes)
- Consistency verification (naming, spacing, patterns across files)
- Regression detection (did this change break something that worked before?)

**Tone**: Clinical, precise, quantitative. Gives percentages and counts, not feelings. "42% of new components use generic naming patterns. 3 files contain unused imports added by the AI."

**When to invoke**: After @Sensei/@Ronin approve code quality — @Metsuke runs the output quality audit. Also invokable via `shiki review --quality`.

**Protocol**:
1. Run the slop detection checklist (separate file: `checklists/quality-audit.md`)
2. Score output: CLEAN (0-2 findings), ACCEPTABLE (3-5), NEEDS WORK (6+)
3. For each finding: category, file:line, what's wrong, suggested fix
4. Auto-fix trivial findings (unused imports, naming inconsistencies)
5. Report: "X clean, Y acceptable, Z needs work across N files"

**Justification**: @Ronin is adversarial about correctness (will it crash?). @Metsuke is adversarial about quality (is this slop?). Different concern, different expertise.

---

### NOT Proposed (and why)

| Potential Agent | Why Not |
|----------------|---------|
| QA/Browser Agent | Browser automation is a **tool**, not a persona. Use Playwright MCP server or a `shiki qa` command. An agent persona adds nothing — the tool does the work. |
| Documentation Agent | Template-generated docs are a **script**, not a persona. `scripts/gen-claude-md.sh` + CI validation. No agent needed. |
| Retro/Metrics Agent | Weekly retros are a **process** (scheduled `/report`), not a persona. The data comes from DB queries, not expertise. |
| DevOps Agent | @Katana already covers infrastructure security. General DevOps (CI/CD, containers) is @Sensei's domain. No gap. |

---

## Part 4: Summary — What Changes

### Immediate (no new code)
- [ ] Write `checklists/quality-audit.md` — AI slop detection checklist for @Metsuke
- [ ] Write `checklists/design-slop-audit.md` — arm @Hanami with gstack's 80-item pattern
- [ ] Add @Kenshi and @Metsuke to `agents.md`

### Next sprint (code changes)
- [ ] Scope drift detection in PRRiskEngine
- [ ] Fix-first review in PRReviewParser (AUTO-FIX vs ASK classification)
- [ ] Effort-based routing in dispatch (`output_config.effort`)
- [ ] Session-aware cognitive load (3+ sessions → re-grounding)

### Feature spec needed
- [ ] `shiki ship` — full release pipeline (feeds @Kenshi persona)
- [ ] OpenRouter integration in AgentProvider
- [ ] Eval framework for shiki-process skills

### Backlog
- [ ] Template-generated CLAUDE.md
- [ ] Browser QA via Playwright MCP
- [ ] Bisectable commit splitting
