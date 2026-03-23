# P2 Challenge Review — @shi Team

**Date:** 2026-03-23
**Reviewers:** @Sensei (CTO), @Hanami (UX), @Ronin (adversarial), @Metsuke (quality), @Kintsugi (philosophy)

---

## PR #27: README Overhaul
**Branch:** `feature/readme-overhaul`
**Scope:** 1 file, +317/-87 lines (README.md: 87 lines -> 396 lines)

**Verdict:** SHIP

### FOR (5 arguments)
1. **Open-source readiness** — The old README was a skeleton. This one has Quick Start, Architecture, API Reference, Contributing guide, and Roadmap. Essential for any public repo.
2. **Accurate architecture diagram** — The ASCII service topology (Vue -> Deno -> TimescaleDB -> Ollama) matches the actual docker-compose stack. Not aspirational — real.
3. **CLI command table is honest** — Lists only commands that actually exist (`shiki start/stop/status/board/decide/report/history`), not vapor features.
4. **Agent Memory Evolution roadmap** — The 4-phase table (static -> per-agent -> vector-indexed -> read+write) gives contributors a clear trajectory without overpromising.
5. **Contributing section is practical** — Shows exactly how to add a slash command, language addon, or agent persona. Low barrier to first contribution.

### AGAINST (5 arguments)
1. **@Ronin: tmux layout section is already stale** — The README shows 3 tabs (orchestrator, board, research) but MEMORY.md records a decision to move to ONE window. Shipping a README that contradicts the tmux layout simplification feedback is confusing.
2. **@Ronin: "Pre-1.0" badge + "Actively used in production" is contradictory** — Either it is production software or it is not. This mixed signal erodes trust with potential contributors.
3. **@Metsuke: No mention of the binary rename** — PR #26 (merged) renamed `shiki-ctl` to `shikki`. The README still uses `shiki` as the binary name everywhere. If the rename is the canonical direction, this README ships outdated install instructions.
4. **@Sensei: Port 11435 for Ollama in Architecture table vs. MEMORY.md's 1234 for LM Studio** — The local dev instructions assume Ollama but the actual setup uses LM Studio. New contributors following the README will hit connection errors.
5. **@Kintsugi: The roadmap "Done" list includes features the user hasn't personally validated as complete** — "zsh autocompletion" and "Pipeline resilience" are listed as done. Are they? Shipping a README with unchecked claims damages credibility on day one.

### @Ronin Red Flag
The install instructions have `ln -sf $(pwd)/.build/debug/shiki-ctl ~/.local/bin/shiki` — but the binary was renamed to `shikki` in PR #26. This will produce a broken symlink or point to the wrong binary. **Functional bug in the install guide.**

### Recommendation
SHIP with 2 mandatory fixes before merge:
1. Fix the install instructions to reflect the `shikki` binary name (or decide that `shiki` is the user-facing alias and document that choice)
2. Update the tmux layout section to match the single-window decision, or remove it and link to docs

---

## PR #28: NetKit Import Fix
**Branch:** `feature/wabisabi-coordinator-fix`
**Scope:** 4 files, +4/-4 lines

**Verdict:** SHIP

### FOR (5 arguments)
1. **Minimal blast radius** — 4 one-line changes, all mechanical: `@testable import NetworkKit` -> `@testable import NetKit`. Zero logic change.
2. **Fixes a real build break** — NetworkKit was deprecated and consolidated into NetKit. These test files would fail to compile without this fix.
3. **Includes the Coordinator doc fix** — The comment update from "main queue" to "@MainActor" in Coordinator.swift is accurate and aligns with modern Swift concurrency.
4. **No behavioral change** — Tests import the same code under its new module name. Functionally identical.
5. **Unblocks downstream work** — Any PR touching NetKit tests would hit this import error. Clearing it now prevents friction.

### AGAINST (5 arguments)
1. **@Ronin: Test directory is still named `NetworkKitTests/`** — The imports are fixed but the folder name is still `NetworkKitTests/`. This is cosmetic debt that will confuse anyone browsing the test directory.
2. **@Metsuke: No evidence tests were actually run** — PR description doesn't mention `swift test` passing. For a build-fix PR, proof of compilation is the minimum bar.
3. **@Sensei: Why are there only 3 test files?** — NetKit absorbed the old NetworkKit but only 3 test files exist. Either test coverage is thin or some tests were lost in consolidation. This PR doesn't address that.
4. **@Ronin: The Coordinator.swift change is scope creep** — A PR titled "NetKit Import Fix" should not include unrelated doc changes in CoreKit. It is 1 line but it sets a bad habit.
5. **@Kintsugi: This fix should have been part of the original NetKit consolidation PR** — Shipping a follow-up fix for an incomplete rename suggests the consolidation was merged without running the test suite.

### @Ronin Red Flag
None. This is a low-risk mechanical fix. The test directory rename is cosmetic debt, not a blocker.

### Recommendation
SHIP as-is. The directory rename (`NetworkKitTests/` -> `NetKitTests/`) should be filed as a separate cleanup task but should not block this fix.

---

## PR #29: ShikiCore Dead Code Cleanup
**Branch:** `feature/shikicore-dead-weight-cleanup`
**Scope:** 4 files, +58/-1318 lines (net -1,260 LOC)

**Verdict:** SHIP

### FOR (5 arguments)
1. **Massive deletion with clear rationale** — 1,260 lines removed. PRReviewProgress (243 LOC), PRReviewStateManager (70 LOC), PRReviewProgressTests (312 LOC), and ~600 LOC of TUI rendering gutted from PRCommand. The PR title says "dead weight" and delivers.
2. **Architectural alignment** — The decision to make `shikki pr` a thin JSON pipe (`stdout` for data, `stderr` for diagnostics) is the Unix philosophy. Review state tracking belongs in `shiki-qa`, not the CLI core.
3. **PRCommand went from ~930 to ~220 LOC** — The remaining code does exactly 3 things: resolve refs, build cache, output JSON or ordered diff. Clean single-responsibility.
4. **Deleted code had no external consumers** — PRReviewProgress and PRReviewStateManager were only used by PRCommand subcommands (read, comment, sync) which are also deleted. No orphaned callers.
5. **Removes 6 flags, keeps 3** — The old command had `--json`, `--diff`, `--delta`, `--comments`, `--build`, `--from`. Now it is `--diff`, `--build`, `--from`. Simpler mental model.

### AGAINST (5 arguments)
1. **@Ronin: 312 tests deleted with 0 tests added** — Net test count drops. The remaining PRCommand has no test coverage. The "thin pipe" still has logic (ref resolution, cache building, architecture-layer sorting) that should be tested.
2. **@Metsuke: No migration path documented** — If anyone was using `shikki pr 6 --delta` or `shikki pr 6 --comments`, those flags silently disappeared. No deprecation warning, no changelog entry.
3. **@Sensei: `shiki-qa` does not exist yet** — The PR moves review state tracking to a tool that has not been built. This creates a capability gap: users lose `--delta` and `--comments` with no replacement today.
4. **@Ronin: The `gitRoot` fallback was silently removed** — The old code had a fallback that walked up from the binary's real path to find `.git`. The new code only tries `git rev-parse` then falls back to `cwd`. If the binary is invoked from a non-git directory via symlink, this is a regression.
5. **@Kintsugi: Deleting work you built 2 days ago is a smell** — PR #24 (merged 2026-03-21) added PR review progression. PR #29 (2026-03-23) deletes most of it. Either the original design was wrong, or this cleanup is premature. Two days from ship to delete suggests insufficient upfront design.

### @Ronin Red Flag
The `gitRoot` fallback removal is a silent regression. The `_NSGetExecutablePath` + walk-up-to-.git logic existed for a reason — it handled the case where `shikki` is invoked via `~/.local/bin/shikki` symlink from a non-repo directory. The new code falls through to `cwd`, which may not be the shiki repo. **Test this specific scenario before merging.**

### Recommendation
SHIP with conditions:
1. Verify `shikki pr 6` works when invoked from `~/Downloads/` (symlink + non-repo cwd scenario)
2. Add at least 1 test for the JSON output format of the slimmed PRCommand
3. Add a one-liner to CHANGELOG or commit message noting that `--delta`, `--comments`, `read`, `comment`, `sync` subcommands are removed

---

## PR #55: Maya CoreKit Import Fix
**Repo:** Maya (Fr0zenSide/MayaFit)
**Branch:** `feature/maya-import-fixes`
**Scope:** 8 files changed

**Verdict:** SHIP

### FOR (5 arguments)
1. **Fixes a real architecture test failure** — `test_featureViews_doNotImportCoreKit` was recording 6 violations. This PR brings it to 0. Architecture tests exist for a reason.
2. **Correct DI pattern** — Moving `Container.default.resolve()` from View `init` to Presenter is the right call. Views should receive dependencies, not resolve them. This follows the established pattern in the codebase.
3. **ViewModels gain public visibility** — `ViewModel` classes changed from `internal` to `public`, which is necessary for the Presenter to construct them. This is the correct access control fix.
4. **Removes 6 `import CoreKit` statements** — Clean surgical removal. Each View file no longer depends on the DI container directly.
5. **Consistent pattern across 2 feature domains** — Both Activity (1 screen) and Circles (4 screens) get the same treatment. ProfileScreen and SettingsScreen only needed the import removal (no DI in their inits).

### AGAINST (5 arguments)
1. **@Ronin: `MockCirclesRepository()` as fallback in production code** — `CirclesPresenter.repository` does `(try? Container.default.resolve(...)) ?? MockCirclesRepository()`. If DI fails in production, users silently get mock data. This should crash or show an error, not silently degrade.
2. **@Metsuke: No tests added or updated** — 8 files changed, 0 test files in the diff. The architecture test will pass, but there are no unit tests verifying the new Presenter factory methods actually produce correct ViewModels.
3. **@Sensei: `UserCache.shared.profile?.id ?? ""` in CirclesPresenter** — An empty string profileId is passed to `AllCirclesScreen.ViewModel` if the user is not cached. This is a latent bug — the ViewModel will make API calls with an empty profile ID.
4. **@Ronin: `try?` swallows DI resolution errors** — `let useCase = try? Container.default.resolve(...)` in ActivityPresenter silently returns nil on misconfiguration. The fallback is `Text("Activity module not configured")` — a raw string visible to users. No logging, no crash reporting.
5. **@Kintsugi: The PR creates inconsistency** — Activity uses `if let` with a text fallback. Circles uses `?? MockCirclesRepository()` silent fallback. Two different error handling strategies in the same PR for the same pattern.

### @Ronin Red Flag
The `MockCirclesRepository()` fallback in production Presenter code is a **data integrity risk**. If the DI container is misconfigured after an update, users will see fake/empty circle data with no indication anything is wrong. Mock repositories should never appear in non-debug builds. **At minimum, wrap this in `#if DEBUG`.**

### Recommendation
SHIP with 1 mandatory fix:
1. Replace `?? MockCirclesRepository()` with a `fatalError` or `assertionFailure` + empty-state view — mock data in production is unacceptable

Optional but recommended:
- Unify the error handling pattern: both Activity and Circles should use the same approach (either `fatalError` on DI failure, or graceful empty state with logging)

---

## PR #1: WabiSabi Landing Page
**Repo:** obyw-one (Fr0zenSide/obyw-one)
**Branch:** `feature/wabisabi-landing-ship`
**Scope:** 5 files, +2336/-3 lines

**Verdict:** HOLD

### FOR (5 arguments)
1. **Complete landing page with proper SEO** — OG meta, Twitter cards, JSON-LD structured data, canonical URL, iOS Smart Banner, robots.txt, sitemap.xml. This is thorough.
2. **Caddy config is well-structured** — Static landing on `/`, PocketBase API on `/api/*` and `/_/*`, cache headers for assets. Clean separation of concerns.
3. **Deploy pipeline updated** — Smoke tests now verify both the landing page and the API health endpoint on `wabisabi.obyw.one`.
4. **Dark mode support** — CSS custom properties with `prefers-color-scheme` media queries. Respects user preference without JavaScript toggle dependency.
5. **Self-contained** — Everything in one `index.html` with no build step, no npm, no framework. Deployable as-is.

### AGAINST (5 arguments)
1. **@Ronin: 2,297 lines of inline CSS+HTML in one file** — This is not maintainable. Every edit requires scrolling through a monolith. No component separation, no CSS extraction. The next person to touch this will curse it.
2. **@Metsuke: og-image.jpg and apple-touch-icon.png are referenced but do not exist** — The PR body admits this. Shipping meta tags pointing to 404s means every share on iMessage/Slack/Twitter will show a broken preview. This is worse than having no OG tags at all.
3. **@Ronin: `aggregateRating` with `ratingCount: 1` in JSON-LD** — This is fake structured data. Google penalizes fabricated ratings. With 1 rating at 5 stars, this looks like self-promotion to search crawlers.
4. **@Sensei: Content-Security-Policy allows `unsafe-inline` for styles** — The entire 1,500+ lines of CSS are inline, forcing `unsafe-inline`. This weakens CSP to the point where it provides minimal XSS protection. Extracting CSS to a file would allow removing `unsafe-inline`.
5. **@Hanami: No pricing validation** — The page shows 4 pricing tiers (Free, Growth, Mentor, Lifetime). Are these final? Shipping pricing publicly before the paywall is actually built creates user expectations that may not match reality.

### @Ronin Red Flag
**Missing assets deployed as broken links.** The `og-image.jpg` and `apple-touch-icon.png` are referenced in `<meta>` tags but do not exist in the repo. Every social share will show a broken/default preview. This is a P0 for a landing page whose entire purpose is to convert visitors. **Do not ship without the OG image.**

### Recommendation
HOLD until:
1. `og-image.jpg` (1200x630) is added to the repo — without it, social sharing is broken
2. Remove the `aggregateRating` from JSON-LD — fabricated ratings risk Google penalties
3. `apple-touch-icon.png` (180x180) is added or the `<link>` tag is removed

Ship after those 3 are addressed. The page itself is well-crafted.

---

## Summary Matrix

| PR | Verdict | Top Risk | Condition |
|----|---------|----------|-----------|
| #27 README | **SHIP** | Install instructions reference wrong binary name | Fix `shiki-ctl` -> `shikki` in install, update tmux section |
| #28 NetKit | **SHIP** | Test dir still named `NetworkKitTests/` | None blocking — cosmetic debt |
| #29 Dead Code | **SHIP** | `gitRoot` fallback removal may break symlink invocation | Test symlink scenario, add 1 output test |
| #55 Maya | **SHIP** | `MockCirclesRepository()` as prod fallback = silent bad data | Replace mock fallback with crash/empty-state |
| #1 Landing | **HOLD** | Missing og-image.jpg = broken social sharing on every platform | Add OG image, remove fake rating, add touch icon |

---

*Review completed by @shi team. @Ronin was not gentle. @Metsuke counted the missing tests. @Sensei questioned the architecture. @Hanami noticed the pricing. @Kintsugi asked why we delete what we just built.*
