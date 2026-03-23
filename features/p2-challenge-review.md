# P2 Challenge Review — @shi Team (Updated)

**Date:** 2026-03-23 | **Updated:** 2026-03-23 (post Shikki Flow v1 spec)
**Reviewers:** @Sensei (CTO), @Hanami (UX), @Ronin (adversarial), @Metsuke (quality), @Kintsugi (philosophy)

**Context:** This review is now informed by the **Shikki Flow v1** spec (`features/shikki-flow-v1.md`) — the 12-component pipeline from INPUT to REPORT. All PRs are evaluated against the vision of Shikki as a compiled Swift orchestration OS with ListReviewer-based TUI, `shikki review` as the PR tool, and `shikki ship` as the release gate.

---

## PR #27: README Overhaul
**Branch:** `feature/readme-overhaul`
**Scope:** 1 file, +317/-87 lines (README.md: 87 lines -> 396 lines)

**Verdict:** REWORK

### FOR (5 arguments)
1. **Open-source readiness** — The old README was a skeleton. This one has Quick Start, Architecture, API Reference, Contributing guide, and Roadmap. Essential for any public repo.
2. **Accurate architecture diagram** — The ASCII service topology (Vue -> Deno -> TimescaleDB -> Ollama) matches the actual docker-compose stack. Not aspirational — real.
3. **Contributing section is practical** — Shows exactly how to add a slash command, language addon, or agent persona. Low barrier to first contribution.
4. **Agent Memory Evolution roadmap** — The 4-phase table gives contributors a clear trajectory without overpromising.
5. **Honest about pre-1.0 status** — Doesn't oversell. Sets expectations correctly.

### AGAINST (5 arguments — updated with Shikki Flow context)
1. **@Ronin: The binary is `shikki`, not `shiki-ctl`** — PR #26 renamed the binary. The install instructions create a broken symlink: `ln -sf $(pwd)/.build/debug/shiki-ctl ~/.local/bin/shiki`. **Functional bug.**
2. **@Sensei: The README describes the OLD Shiki, not the Shikki Flow** — The README talks about `shiki start/stop/status/board`. But the Shikki Flow v1 spec defines a 12-component pipeline: `shikki backlog`, `shikki inbox`, `shikki review`, `shikki ship`, `shikki report`, `shikki wizard`. The README should describe the VISION — what Shikki is becoming — not just the current state.
3. **@Ronin: tmux layout section contradicts the single-window decision** — Shows 3 tabs (orchestrator, board, research) but the validated architecture is 1 window with sidebar. The event logger pane concept from the Flow spec isn't mentioned.
4. **@Sensei: Port 11435 for Ollama vs 1234 for LM Studio** — The actual setup uses LM Studio. New contributors following the README will hit connection errors.
5. **@Kintsugi: The roadmap "Done" list includes unvalidated claims** — "zsh autocompletion" and "Pipeline resilience" listed as done. Are they? Shipping unchecked claims damages credibility.

### @Ronin Red Flag
The README describes a different product than what the Shikki Flow v1 spec defines. Shipping this README cements the old mental model. **The README should be the first document that communicates the Shikki Flow vision** — INPUT → BACKLOG → DECIDE → SPEC → RUN → INBOX → REVIEW → SHIP → REPORT.

### Recommendation
**REWORK** — not just fix the binary name. Rewrite the README to reflect the Shikki Flow v1 vision:
1. Opening 3 lines: Shikki is a professional AI orchestration OS — 12-component pipeline from idea to shipped code
2. The Flow diagram (from `shikki-flow-v1.md`) should be front and center
3. CLI commands should list the Flow commands: `shikki backlog`, `shikki inbox`, `shikki review`, `shikki ship`, `shikki report`, `shikki wizard`, `shikki quick`
4. Architecture section should show ShikiCore (compiled Swift engine) + Skills (UI interface) separation
5. Fix the install instructions for the `shikki` binary
6. Remove the stale tmux 3-tab section, replace with single-window + event logger concept

---

## PR #28: NetKit Import Fix
**Branch:** `feature/wabisabi-coordinator-fix`
**Scope:** 4 files, +4/-4 lines

**Verdict:** SHIP

### FOR (5 arguments)
1. **Minimal blast radius** — 4 one-line changes, all mechanical: `@testable import NetworkKit` -> `@testable import NetKit`. Zero logic change.
2. **Fixes a real build break** — NetworkKit was deprecated and consolidated into NetKit. Tests wouldn't compile without this.
3. **Includes the Coordinator doc fix** — "main queue" -> "@MainActor" aligns with modern Swift concurrency.
4. **No behavioral change** — Tests import the same code under its new module name.
5. **Unblocks the NetKit migration** (P1-B Task 3) — BackendClient→NetKit migration needs these imports working first.

### AGAINST (5 arguments)
1. **@Ronin: Test directory still named `NetworkKitTests/`** — Cosmetic debt that will confuse browsing.
2. **@Metsuke: No evidence tests were run** — PR doesn't mention `swift test` results.
3. **@Sensei: Only 3 test files for NetKit** — Coverage may be thin after consolidation.
4. **@Ronin: Coordinator.swift change is scope creep** — 1 line but unrelated to the PR title.
5. **@Kintsugi: Should have been part of original consolidation** — Follow-up fix suggests incomplete rename.

### @Ronin Red Flag
None. Low-risk mechanical fix.

### Recommendation
SHIP as-is. File directory rename as separate cleanup task.

---

## PR #29: ShikiCore Dead Code Cleanup
**Branch:** `feature/shikicore-dead-weight-cleanup`
**Scope:** 4 files, +58/-1318 lines (net -1,260 LOC)

**Verdict:** SHIP (with updated context)

### FOR (5 arguments — updated with Shikki Flow context)
1. **Massive deletion aligns with Shikki Flow** — The Flow spec says `shikki review` replaces the old `shiki pr` TUI. PRReviewProgress, StateManager, and the 930-LOC PRCommand were the old review system. They're dead code in the new architecture.
2. **PRCommand as thin JSON pipe is correct** — In the Shikki Flow, `shikki review <N>` pipes to external diff tools (delta, diffnav). The CLI outputs data, external tools render. Unix philosophy.
3. **-1,260 LOC is velocity** — Less code = faster builds, less cognitive load, fewer bugs. This is the right direction for v1.
4. **The deleted code has a replacement path** — `shikki review` (ListReviewer-based, PR #34 ships the foundation) is the replacement. Not deleting into a void.
5. **Deleted code had no external consumers** — Clean removal, no orphaned callers.

### AGAINST (5 arguments)
1. **@Ronin: 312 tests deleted with 0 added** — Net test count drops. The thin pipe still has untested logic.
2. **@Metsuke: No migration documentation** — `--delta`, `--comments`, `read`, `comment`, `sync` silently gone.
3. **@Sensei: `shikki review` doesn't exist yet** — Capability gap between delete and replacement. But ListReviewer (PR #34) is the foundation, so this gap is temporary.
4. **@Ronin: `gitRoot` fallback removal** — Symlink invocation from non-repo directory may break.
5. **@Kintsugi: 2-day build-to-delete cycle** — Suggests the original PR #24 was premature. But in the Shikki Flow context, it makes sense: the exploration informed the vision, the vision made the old approach obsolete.

### @Ronin Red Flag
`gitRoot` fallback removal is still a real concern. **Test `shikki pr 6` from `~/Downloads/`** before merging.

### Recommendation
SHIP with conditions:
1. Test symlink + non-repo cwd scenario
2. Add 1 test for JSON output format
3. Note removed subcommands in commit message

---

## PR #55: Maya CoreKit Import Fix
**Repo:** Maya (Fr0zenSide/MayaFit)
**Branch:** `feature/maya-import-fixes`
**Scope:** 8 files changed

**Verdict:** SHIP with mandatory fix

### FOR (5 arguments)
1. **Fixes architecture test** — 6 violations → 0. Architecture tests enforce the Shikki principle: Views receive dependencies, they don't resolve them.
2. **Correct DI pattern** — Container resolution in Presenter, not View. Matches the unified SPM architecture plan.
3. **ViewModels gain public visibility** — Correct access control for the Presenter→ViewModel factory pattern.
4. **Clean surgical removal** — 6 `import CoreKit` statements gone, no collateral damage.
5. **Consistent across domains** — Activity and Circles both get the same treatment.

### AGAINST (5 arguments)
1. **@Ronin: `MockCirclesRepository()` in production** — Silent mock data if DI fails. **Unacceptable in the Shikki quality model** — the Shikki Flow has quality gates at every stage. Mock data in production bypasses all gates.
2. **@Metsuke: 0 tests added** — 8 files changed, no test files. The architecture test passes but Presenter factory methods are untested.
3. **@Sensei: `UserCache.shared.profile?.id ?? ""`** — Empty string profileId → API calls with empty ID. Latent bug.
4. **@Ronin: `try?` swallows DI errors** — No logging, no crash reporting on misconfiguration.
5. **@Kintsugi: Inconsistent error handling** — Activity uses `if let` + text fallback. Circles uses `?? Mock`. Two strategies for the same pattern.

### @Ronin Red Flag
`MockCirclesRepository()` in production code is a **data integrity risk**. In the Shikki quality model, this violates the fundamental principle: **no code that pretends to work when it's broken**. The `shikki ship` gate should catch this — but the gate doesn't exist yet, so we catch it here.

### Recommendation
SHIP with **1 mandatory fix**:
1. Replace `?? MockCirclesRepository()` with `fatalError("CirclesRepository not registered")` in release builds, or `#if DEBUG` guard

Optional:
- Unify error handling: both domains should use the same pattern (recommend: `guard let` + `fatalError` in release, graceful fallback in debug)

---

## PR #1: WabiSabi Landing Page
**Repo:** obyw-one (Fr0zenSide/obyw-one)
**Branch:** `feature/wabisabi-landing-ship`
**Scope:** 5 files, +2336/-3 lines

**Verdict:** HOLD

### FOR (5 arguments)
1. **Complete SEO setup** — OG meta, Twitter cards, JSON-LD, canonical URL, iOS Smart Banner, robots.txt, sitemap.xml. Thorough.
2. **Caddy config well-structured** — Static landing + PocketBase API proxy. Clean separation.
3. **Deploy pipeline updated** — Smoke tests for landing + API health.
4. **Dark mode** — CSS custom properties with `prefers-color-scheme`. Respects user preference.
5. **Self-contained** — Single HTML file, no build step. Deployable as-is.

### AGAINST (5 arguments)
1. **@Ronin: 2,297 lines in one file** — Not maintainable. The next edit is pain.
2. **@Metsuke: og-image.jpg and apple-touch-icon.png are 404s** — Every social share shows broken preview. Worse than no OG tags.
3. **@Ronin: `aggregateRating` with `ratingCount: 1`** — Fabricated structured data. Google penalizes this. With the Shikki philosophy of "no code that pretends", fake ratings are antithetical.
4. **@Sensei: CSP `unsafe-inline`** — 1,500+ lines of inline CSS forces weak CSP. Extract CSS to file.
5. **@Hanami: Pricing tiers shown before paywall exists** — Creates expectations that may not match reality. The Shikki Flow says `shikki decide` should validate pricing before shipping.

### @Ronin Red Flag
**Missing assets = broken social sharing.** A landing page that can't be shared on iMessage/Slack/Twitter has failed its primary mission. This is the Shikki equivalent of shipping code that doesn't compile.

### Recommendation
HOLD until:
1. `og-image.jpg` (1200x630) added — design asset needed
2. Remove `aggregateRating` from JSON-LD — no fake data
3. `apple-touch-icon.png` (180x180) added or tag removed
4. Consider: pricing section should be behind a feature flag until paywall v2 ships

---

## Summary Matrix (Updated)

| PR | Verdict | Top Risk | Shikki Flow Alignment | Condition |
|----|---------|----------|----------------------|-----------|
| #27 README | **REWORK** | Describes old Shiki, not Shikki Flow | Must reflect the 12-component vision | Rewrite with Flow diagram, `shikki` commands, ShikiCore architecture |
| #28 NetKit | **SHIP** | Cosmetic directory name | Unblocks P1-B NetKit migration | None blocking |
| #29 Dead Code | **SHIP** | `gitRoot` fallback removal | Aligns with `shikki review` replacing old TUI | Test symlink scenario |
| #55 Maya | **SHIP w/ FIX** | Mock in production | Violates Shikki quality principle | Remove `MockCirclesRepository()` fallback |
| #1 Landing | **HOLD** | Missing OG image + fake rating | Violates "no pretending" philosophy | Add real assets, remove fake data |

### New PRs from Wave 1+2 (not in original review)

| PR | Verdict | Notes |
|----|---------|-------|
| #30 OpenAPI | **SHIP** | Documentation only, 80 endpoints captured. Feeds Swift migration. |
| #31 E2E skip | **SHIP** | ~13 lines, enables `SKIP_E2E=1` for CI and agents. |
| #32 Autopilot template | **SHIP** | PromptTemplateLoader + 11 tests. Hot-reload ready. |
| #33 SessionRegistry | **SHIP** | Registry-first lookup, tmux fallback. 5 tests, 486 total. |
| #34 ListReviewer | **SHIP** | Foundation for `shikki backlog/inbox/decide`. 22 tests. |
| #35 HeartbeatLoop tests | **SHIP w/ FIX** | 14/15 passing. 1 `checkAnsweredDecisions` test needs investigation. |
| kintsugi-ds #8 | **SHIP** | README + CI + CHANGELOG. Tag v0.1.0 after merge. |

---

*Updated review by @shi team with Shikki Flow v1 vision applied. PR #27 downgraded from SHIP to REWORK — the README must communicate the vision, not the legacy. All other verdicts strengthened by the Flow context.*
