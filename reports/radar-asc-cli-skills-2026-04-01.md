# Radar: App Store Connect CLI Skills

> Date: 2026-04-01 | Source: [rudrankriyam/app-store-connect-cli-skills](https://github.com/rudrankriyam/app-store-connect-cli-skills) | Stars: 665 | License: MIT

## What Is It

A community-maintained Agent Skills pack for the [App Store Connect CLI](https://github.com/rudrankriyam/App-Store-Connect-CLI) (`asc`). The `asc` CLI itself is a fast Go binary (MIT, 3,600+ commits) that wraps the App Store Connect API for terminal-first iOS/macOS release automation. The skills pack gives Claude Code (or any Agent Skills-compatible agent) structured knowledge to drive `asc` commands without memorizing the API surface.

Install: `npx skills add rudrankriyam/app-store-connect-cli-skills`

## 22 Skills — Full Inventory

| Skill | What It Does | Shikki Relevance |
|-------|-------------|------------------|
| **asc-workflow** | Repo-local `.asc/workflow.json` automation graphs with hooks, conditionals, sub-workflows, dry-run, CI-friendly JSON output | HIGH — maps directly to ShipGate pipeline concept |
| **asc-testflight-orchestration** | Beta groups, testers, build distribution, What to Test notes | HIGH — core of `shikki ship --testflight` |
| **asc-build-lifecycle** | Build processing, latest build resolution, `expire-all` cleanup with retention policies | HIGH — UploadGate + build management |
| **asc-xcode-build** | Archive, export, ExportOptions.plist, version/build number management via `asc xcode version` | HIGH — ArchiveGate + ExportGate |
| **asc-release-flow** | Readiness-first submission: preflight, stage, dry-run, deep API audit. First-time blocker guidance (availability, IAP, subscriptions, Game Center, App Privacy) | HIGH — future App Store submission gate |
| **asc-submission-health** | Pre-submission checklist: encryption compliance, content rights, metadata, screenshots, privacy, digital goods validation | HIGH — QualityGate for submissions |
| **asc-signing-setup** | Bundle IDs, capabilities, certs, profiles, `asc signing sync` (encrypted git-backed, like fastlane match) | MEDIUM — one-time setup, doctor checks |
| **asc-id-resolver** | Resolve IDs for apps, builds, versions, groups, testers by name | MEDIUM — utility for all other skills |
| **asc-metadata-sync** | Pull/push App Store metadata, character limit validation, legacy migration | MEDIUM — ChangelogGate integration |
| **asc-localize-metadata** | LLM-translated App Store listings with locale-aware keywords and char limits | MEDIUM — future multi-language support |
| **asc-whats-new-writer** | Generate release notes from git log or bullet points, localize across metadata locales | MEDIUM — ChangelogGate output |
| **asc-crash-triage** | TestFlight crash reports, beta feedback, performance diagnostics (hangs, disk writes, launches) | MEDIUM — post-ship monitoring |
| **asc-aso-audit** | Offline ASO audit on `./metadata`, keyword gaps via Astro MCP | LOW — post-launch optimization |
| **asc-ppp-pricing** | Territory-specific PPP pricing | LOW — premium tier |
| **asc-subscription-localization** | Bulk-localize subscription display names across all locales | LOW — WabiSabi subscription management |
| **asc-revenuecat-catalog-sync** | Reconcile ASC products with RevenueCat | LOW — if we use RevenueCat |
| **asc-notarization** | macOS Developer ID notarization flow | LOW — no macOS app yet |
| **asc-screenshot-resize** | Screenshot management | LOW — manual for now |
| **asc-shots-pipeline** | Agent-first simulator screenshot automation with AXe + framing | LOW — future automated screenshots |
| **asc-app-create-ui** | Browser automation for creating new ASC app records | LOW — one-time per app |
| **asc-cli-usage** | General `asc` command guidance | LOW — reference |
| **asc-wall-submit** | Submit app to the `asc` Wall of Apps | NONE |

## Integration Analysis: `shikki ship --testflight`

### Direct Mapping to Our Spec

Our existing spec (`features/shikki-ship-testflight.md`) already uses `asc` as the underlying CLI. The skills pack is a perfect overlay:

| Our Gate | ASC Skill | Commands We Need |
|----------|-----------|-----------------|
| ArchiveGate | asc-xcode-build | `asc xcode version bump`, `xcodebuild clean archive`, `xcodebuild -exportArchive` |
| ExportGate | asc-xcode-build | ExportOptions.plist generation, IPA export |
| UploadGate | asc-build-lifecycle | `asc publish testflight --ipa --group --wait` (end-to-end!) |
| DistributeGate | asc-testflight-orchestration | `asc testflight groups`, `asc builds add-groups`, `asc builds test-notes create` |

### Key Discovery: `asc publish testflight` — End-to-End Shortcut

The build-lifecycle skill reveals `asc publish testflight --app --ipa --group --wait` — a single command that uploads + distributes + waits for processing. This could collapse our UploadGate and DistributeGate into one step (with the `--wait` flag handling the processing delay).

### Key Discovery: `asc workflow` — Declarative Pipeline

The workflow skill enables `.asc/workflow.json` with hooks (`before_all`, `after_all`, `error`), conditionals (`if`), sub-workflows, and runtime params. This is essentially a simplified version of our ShipGate pipeline in JSON. We could:
- Export our pipeline as an `.asc/workflow.json` for debugging/standalone use
- Use `asc workflow validate` as a pre-flight check
- Use `asc workflow run --dry-run` for our `--dry-run` flag

### Key Discovery: `asc xcode version` — Build Number Management

Commands like `asc xcode version bump --type build` and `asc builds next-build-number` replace our planned `agvtool` integration with a safer approach that checks remote build numbers before incrementing.

### Key Discovery: `asc signing sync` — Fastlane Match Replacement

`asc signing sync push/pull` with encrypted git-backed storage is exactly what we need for team signing. No fastlane dependency, pure `asc`.

## ShipGate Compatibility Assessment

**Verdict: HIGHLY COMPATIBLE — install and use immediately.**

The skills pack does not conflict with our pipeline architecture. It enhances it:

1. **Our ShipGate = orchestrator** — decides what runs, in what order, with what gates
2. **asc skills = knowledge layer** — the agent knows which `asc` command to use for each gate
3. **asc CLI = executor** — the actual binary that talks to App Store Connect API

The layering is: `shikki ship --testflight` -> ShipGate pipeline -> ASCClient struct -> `asc` CLI -> App Store Connect API

## Action Items

| Priority | Action | Effort |
|----------|--------|--------|
| **P0** | `npx skills add rudrankriyam/app-store-connect-cli-skills` — install the skill pack now | 1 min |
| **P0** | `brew install rudrankriyam/tap/asc` — install the `asc` CLI | 1 min |
| **P1** | Update `shikki-ship-testflight.md` to use `asc publish testflight --wait` instead of separate upload+distribute gates | 30 min |
| **P1** | Replace `agvtool` build number logic with `asc builds next-build-number` + `asc xcode version edit` | 30 min |
| **P1** | Add `asc auth login` to `shikki doctor --signing` pre-check | 15 min |
| **P2** | Evaluate `asc workflow` as export format for our pipeline (ship pipeline -> `.asc/workflow.json`) | 2 hr |
| **P2** | Wire `asc-crash-triage` into post-ship monitoring (ntfy alert on new crashes) | 2 hr |
| **P2** | Wire `asc-release-flow` for future App Store submission gate (`shikki ship --appstore`) | 4 hr |
| **P3** | Evaluate `asc signing sync` to replace manual cert/profile management | 1 hr |
| **P3** | `asc-whats-new-writer` + `asc-localize-metadata` for multi-language release notes | 2 hr |

## Risk Assessment

- **Single maintainer** (Rudrank Riyam) — but MIT license, so we can fork if abandoned
- **`asc` CLI is Go, not Swift** — no SPM integration, shell-out only (which matches our external tools philosophy)
- **Skills format dependency** — uses Agent Skills format (`SKILL.md` frontmatter). Compatible with Claude Code skills. If format evolves, migration is trivial (just markdown files)
- **No code in skills** — every skill is pure SKILL.md (no scripts/). This means the knowledge is portable but there is nothing to execute directly. Our ShipGate wraps the commands.

## Competitive Notes

- The `asc` CLI + skills pack is the most complete open-source fastlane replacement for Apple ecosystem
- 665 stars in 2 months signals strong community interest
- The `asc workflow` feature makes `asc` a credible Xcode Cloud alternative for local builds
- We are NOT the first to think "one command to TestFlight" — but we are the first to integrate it into a full ShipGate pipeline with quality gates, event bus, and agent orchestration
