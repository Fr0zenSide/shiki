# Shiki PR Review Progression

> **Status**: Draft
> **Author**: @Daimyo
> **Date**: 2026-03-21
> **Branch**: `feature/pr-review-progression`
> **Depends on**: `shiki pr` (PRCommand.swift), `/review` skill (pr-review.md)
> **Package**: ShikiCtlKit (shiki-ctl)

---

## Problem

`shiki pr` gives a good first-pass overview of a PR, but has no memory. Every invocation starts from zero. When reviewing a 12-file PR across multiple sessions — or coming back after new commits are pushed — the reviewer has no way to know:

1. Which files they already reviewed
2. What comments they left
3. What changed since their last pass

The `/review` interactive skill tracks state in-session via conversation context, but that state vanishes when the session ends. The `docs/pr5-review-state.json` prototype proves the concept but only tracks section index — no file-level granularity, no delta detection, no comment persistence.

Reviewers waste time re-reading files they already approved, or miss files that changed after their last review.

## Solution

File-level review tracking for `shiki pr`. The reviewer marks files as read, attaches comments, and on subsequent reviews sees only what changed since their last pass. State persists across sessions via file-based JSON and (future) ShikiDB sync.

---

## Key Features

### 1. Review State Tracking

State file lives at `docs/prN-cache/review-state.json` alongside the existing `files.json` and `risk-map.json` cache. Same lifecycle — rebuilt on `--build`, survives across sessions.

Tracks per file:
- Review status (pending / reviewed / commented / changed)
- Timestamp of last review
- Inline comments
- The commit SHA at time of review (for delta detection)

Global state:
- `lastReviewedAt` — timestamp of the most recent `read` action
- `lastReviewedCommit` — PR HEAD SHA at time of last review pass
- `prNumber` — the PR number (sanity check)

### 2. Mark as Read

```
shiki pr 23 read <file>       — mark one file as reviewed
shiki pr 23 read --all        — mark all current files as reviewed
```

Visual indicators in default summary output:

```
── Services & Implementations ──
  [✓] +  42 -   3 ██   Services/StoreKitService.swift
  [→] +  18 -   0 █    Services/PaymentHandler.swift        ← current
  [ ] + 120 -  15 ████ Services/SubscriptionManager.swift
  [✎] +   8 -   2 █    Services/PricingEngine.swift         "silent error on L42"
  [!] +  33 -  10 ██   Services/ReceiptValidator.swift       changed since last review
```

Status legend:
- `[✓]` reviewed — file marked as read, no changes since
- `[→]` current — file being viewed (interactive mode only)
- `[ ]` pending — not yet reviewed
- `[✎]` commented — has an attached comment (reviewed + annotated)
- `[!]` changed — was reviewed, but file changed in new commits since

### 3. Comments

```
shiki pr 23 comment <file> "message"
```

Dual persistence:
1. Stored locally in `review-state.json` (offline-first, fast)
2. Posted to GitHub PR as an inline review comment via `gh api`

Comments display inline in the default summary output, truncated to 40 chars:

```
  [✎] +   8 -   2 █  PricingEngine.swift  "silent error on L42"
```

Full comment text visible via `shiki pr 23 --json | jq '.reviewState.reviewedFiles[] | select(.comment)'`.

### 4. Delta Review (--delta)

```
shiki pr 23 --delta              — summary of only delta files
shiki pr 23 --delta --diff       — diff of only delta files (pipe to delta)
shiki pr 23 --delta --json       — delta files as JSON
```

Delta includes:
- Files NOT yet marked as reviewed (`pending`)
- Files that CHANGED since last review (`changed`)
- Files with open comments (`commented`)

Excludes:
- Files marked `reviewed` that have not changed since

This is the "what do I still need to look at" view.

### 5. Progress Display

Default `shiki pr 23` output gains a progress section after the header:

```
PR #23: Add StoreKit2 subscription tier
feature/storekit → develop │ 8 files │ +220/-45

  Progress: 5/8 reviewed (62%)
  ████████████░░░░░░░░ 5/8
  3 files remaining │ 1 changed since last review

────────────────────────────────────────────────────────
```

Progress renders as:
- Fraction: `N/M reviewed (X%)`
- Bar: filled blocks for reviewed, empty for remaining, 20-char width
- Delta hint: count of files needing attention

When progress is 100% and no files have `changed` status:

```
  Progress: 8/8 reviewed (100%) ✓ — all files reviewed
```

### 6. Delta Detection

On every `shiki pr 23` invocation:

1. Fetch current PR HEAD: `gh pr view 23 --json headRefOid -q .headRefOid`
2. Compare with `lastReviewedCommit` in review-state.json
3. If different:
   a. Get list of files changed between the two commits: `git diff --name-only <lastReviewedCommit>..<currentHead>`
   b. For each file in that diff that was previously `reviewed` or `commented`: reset status to `changed`
   c. Show banner:

```
  ⚠ 3 files changed since your last review (2 new commits)
  Changed: PricingEngine.swift, ReceiptValidator.swift, StoreKitService.swift
```

4. Update `lastReviewedCommit` to current HEAD after any `read` action

---

## Review State Model

```swift
struct PRReviewProgress: Codable {
    let prNumber: Int
    var reviewedFiles: [ReviewedFile]
    var lastReviewedAt: Date?
    var lastReviewedCommit: String  // PR HEAD SHA at time of last review action

    struct ReviewedFile: Codable {
        let path: String
        var status: ReviewStatus
        var reviewedAt: Date?
        var comment: String?
        var reviewedAtCommit: String?  // SHA when this specific file was marked read
    }

    enum ReviewStatus: String, Codable {
        case pending     // [ ]  — not yet reviewed
        case reviewed    // [✓]  — marked as read
        case commented   // [✎]  — has comment attached
        case changed     // [!]  — was reviewed but file changed since
    }
}
```

Location: `tools/shiki-ctl/Sources/ShikiCtlKit/Models/PRReviewProgress.swift`

JSON on disk (`docs/pr23-cache/review-state.json`):

```json
{
  "prNumber": 23,
  "lastReviewedAt": "2026-03-21T14:30:00Z",
  "lastReviewedCommit": "abc1234def5678",
  "reviewedFiles": [
    {
      "path": "Sources/Services/StoreKitService.swift",
      "status": "reviewed",
      "reviewedAt": "2026-03-21T14:28:00Z",
      "reviewedAtCommit": "abc1234def5678"
    },
    {
      "path": "Sources/Services/PricingEngine.swift",
      "status": "commented",
      "reviewedAt": "2026-03-21T14:30:00Z",
      "comment": "Silent error on L42 — needs user surface",
      "reviewedAtCommit": "abc1234def5678"
    },
    {
      "path": "Sources/Services/SubscriptionManager.swift",
      "status": "pending"
    }
  ]
}
```

---

## Business Rules

| ID | Rule |
|----|------|
| BR-01 | Review state persists in `docs/prN-cache/review-state.json`, created on first `read` or `comment` action |
| BR-02 | `read <file>` marks file as `reviewed` with current timestamp and current PR HEAD commit |
| BR-03 | `read --all` marks ALL files as `reviewed` with current timestamp AND current PR HEAD commit (same tracking as BR-02, bulk version) |
| BR-03b | `read --reset` resets ALL files to `pending` — restart review from scratch (fixes misuse of `read --all`, or new reviewer takes over) |
| BR-04 | `--delta` filters output to: `pending` + `changed` + `commented` files only |
| BR-04b | `--comments` shows only files with comments. `--comments --all` includes resolved/closed. Default shows open only. |
| BR-05 | When PR HEAD differs from `lastReviewedCommit`, files in the commit-range diff get status reset to `changed` |
| BR-06 | `changed` status only applies to files previously marked `reviewed` or `commented` — `pending` files stay `pending` |
| BR-07 | Comments are LOCAL FIRST — saved to review-state.json immediately (source of truth). GitHub sync is secondary: queued for retry if gh api fails. When review is complete, if any comments failed to sync to gh, notify the user: "3 comments pending GitHub sync — run `shiki pr N sync` to retry." GitHub is a fallback/backup, not the authority. Future: work without gh entirely (just git on VPS). |
| BR-07b | `shiki pr N sync` pushes all local comments to GitHub. `shiki pr N sync --from-gh` pulls GitHub comments into local state. Local always wins on conflict. |
| BR-08 | Progress bar and count display in default `shiki pr N` output when review state exists |
| BR-09 | File matching for `read` and `comment` uses fuzzy/partial match (basename or path suffix) |
| BR-10 | Review state is per-reviewer (future: keyed by `gh auth status` username, current: single reviewer assumed) |
| BR-11 | `--build` does NOT destroy review state — only rebuilds `files.json`. State survives cache rebuilds. |
| BR-12 | If review-state.json references files no longer in the PR diff (removed by force-push), those entries are pruned on load |

---

## CLI Interface

### New Subcommands

```
shiki pr <N> read <file>           Mark file as reviewed
shiki pr <N> read --all            Mark all files as reviewed
shiki pr <N> comment <file> "msg"  Attach comment to file + post to GitHub
```

### Modified Flags

```
shiki pr <N>                       Default output gains progress bar + status indicators
shiki pr <N> --delta               Show only unreviewed/changed files
shiki pr <N> --delta --diff        Diff of only delta files
shiki pr <N> --delta --json        Delta files as JSON
shiki pr <N> --json                Gains reviewState field in output
```

### ArgumentParser Structure

```swift
struct PRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr",
        abstract: "Smart PR review with persistent progress tracking",
        subcommands: [ReadSubcommand.self, CommentSubcommand.self]
    )

    @Argument(help: "PR number")
    var number: Int

    @Flag(name: .long, help: "Force rebuild PR cache")
    var build: Bool = false

    @Flag(name: .long, help: "Output raw JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Output architecture-ordered diff")
    var diff: Bool = false

    @Flag(name: .long, help: "Show only unreviewed/changed files")
    var delta: Bool = false

    @Option(name: .long, help: "Base branch (default: develop)")
    var base: String = "develop"
}

struct ReadSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "read")

    @OptionGroup var parent: PRCommand.Options

    @Argument(help: "File path (partial match)")
    var file: String?

    @Flag(name: .long, help: "Mark all files as reviewed")
    var all: Bool = false
}

struct CommentSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "comment")

    @OptionGroup var parent: PRCommand.Options

    @Argument(help: "File path (partial match)")
    var file: String

    @Argument(help: "Comment text")
    var message: String
}
```

---

## Integration with /review Skill

The `/review` interactive skill currently tracks review state in conversation context (ephemeral). With this feature:

1. `/review` reads `review-state.json` on startup — resumes where the reviewer left off
2. `/review` `read` / `r` command writes to `review-state.json` (not just in-memory)
3. `/review` `all` command calls `read --all` logic
4. `/review` comments write to both GitHub and `review-state.json`
5. Delta detection runs on `/review` entry — shows banner if new commits arrived

The shared model (`PRReviewProgress`) lives in ShikiCtlKit, accessible to both the CLI and the skill (which reads the file directly).

---

## Auto-Propose Review (Shikki Flow Integration)

When the orchestrator completes a PR (all gates green), it proposes the review command directly:

```
✓ PR #23 ready for review (3 files, +28/-6, all gates green)

  Launch review? (suggested command in dim):
  shiki pr 23 --delta --diff | diffnav
```

The user presses Enter or types their preferred variation. The orchestrator opens a new tmux pane with the review tool. The flow is: build → test → /pre-pr → **propose review** → human reviews → human merges.

This is step 8→9 of the Shikki Flow. The orchestrator sets up the review, the human drives it.

---

## Architecture Notes

- This is a **shiki-ctl feature**, not ShikiCore — it is CLI-level review tooling, not orchestration
- State lives alongside the cache (`docs/prN-cache/`) — same lifecycle, same `.gitignore` pattern
- **Local-first**: review-state.json is the source of truth. GitHub is a sync target, not the authority
- **GitHub-optional**: future versions work without gh, just git on VPS (security: French army/gov can't rely on US platforms)
- **GitHub MCP**: [github/github-mcp-server](https://github.com/github/github-mcp-server) exists — evaluate replacing `Process` + `gh` CLI with MCP tool calls for PR/issue interaction (backlogged)
- File operations use `Foundation.FileManager` (consistent with existing `buildCache()`)
- Retry queue for failed gh syncs — persisted locally, retried on `shiki pr N sync`
- No new dependencies — pure Foundation + ArgumentParser
- Future: ShikiDB stores review progress for cross-machine persistence

---

## TPDD — Test Plan (S3 spec syntax FIRST, then test signatures)

### Spec

```s3
# PR Review Progression

## Model

When a review state is saved to JSON and loaded back:
  → all fields must round-trip without data loss
  → dates must preserve ISO8601 precision

When marking a file as reviewed:
  → status changes to reviewed
  → reviewedAt is set to current timestamp
  → reviewedAtCommit is set to current PR HEAD

When marking all files as reviewed (read --all):
  → ALL files get reviewed status with timestamp + commit (same as individual read)

When resetting review (read --reset):
  → ALL files return to pending status
  → lastReviewedAt and lastReviewedCommit are cleared

When attaching a comment to a file:
  → status changes to commented
  → comment text is stored
  → comment persists in local state (source of truth)

## Delta Detection

When no commits changed since last review:
  → delta shows only pending files
  → reviewed files are excluded

When new commits arrive after last review:
  → files in the new commit diff that were reviewed get status changed
  → files that were pending stay pending (not affected)

When files are removed from PR (force-push):
  → orphan entries are pruned from state on load

## Display

When rendering progress:
  → bar shows correct percentage (reviewed / total)
  → 100% with no changed files shows checkmark

When rendering status indicators:
  → [✓] for reviewed, [ ] for pending, [✎] for commented, [!] for changed

## File Matching

When user provides partial file name:
  → basename match resolves correctly (e.g. "Client" → "ShikiDBClient.swift")

When partial match is ambiguous:
  → error with list of candidates

## Comments Filter

When using --comments:
  → shows only files with open comments

When using --comments --all:
  → shows all comments including resolved

## Concerns

? Will read --all without actually reading create false confidence?
  expect: yes — that's why read --reset exists for re-review
  edge case: @Ronin flagged this — track bulk vs individual reads separately (future)

? What if gh api fails during comment sync?
  expect: comment saves locally (source of truth), gh sync queued for retry
  edge case: user finishes review with 3 unsent comments — notify on completion
```

### Test Signatures

```swift
@Suite("PR Review Progression")
struct PRReviewProgressionTests {

    // -- Model --
    @Test("state file round-trips through JSON correctly")
    func jsonRoundTrip() { }

    @Test("mark file as reviewed persists with timestamp and commit")
    func markFileReviewed() { }

    @Test("read --all marks all files with timestamp and commit")
    func markAllReviewed() { }

    @Test("read --reset clears all review state")
    func resetReview() { }

    @Test("comment attaches to file and sets commented status")
    func commentSetsStatus() { }

    // -- Delta --
    @Test("delta shows only unreviewed files when no commits changed")
    func deltaUnreviewed() { }

    @Test("delta detects files changed since last review via commit comparison")
    func deltaDetectsChanges() { }

    @Test("new commits reset only changed files — pending stays pending")
    func newCommitsResetOnlyReviewed() { }

    @Test("files removed from PR diff are pruned from state on load")
    func prunedRemovedFiles() { }

    // -- Display --
    @Test("progress bar shows correct percentage and fraction")
    func progressBarPercentage() { }

    @Test("status indicators render correctly for each ReviewStatus case")
    func statusIndicators() { }

    @Test("progress shows 100% checkmark when all reviewed and no changes")
    func progressComplete() { }

    // -- File matching --
    @Test("partial file match resolves basename correctly")
    func partialFileMatch() { }

    @Test("ambiguous partial match returns error with candidates")
    func ambiguousMatch() { }

    // -- Comments filter --
    @Test("--comments shows only files with open comments")
    func commentsFilterOpen() { }

    @Test("--comments --all shows all comments including resolved")
    func commentsFilterAll() { }

    // -- Sync --
    @Test("failed gh sync queues comment for retry")
    func syncRetryQueue() { }

    @Test("sync command pushes pending comments to GitHub")
    func syncPushesToGh() { }
}
```

17 tests across 6 categories: model (5), delta (4), display (3), file matching (2), comments filter (2), sync (2).

---

## Implementation Tasks

| Wave | Task | Files | Est. |
|------|------|-------|------|
| 1 | `PRReviewProgress` model + JSON codec + tests | `Models/PRReviewProgress.swift`, tests | ~120 LOC |
| 2 | Review state load/save service | `Services/PRReviewStateManager.swift` | ~80 LOC |
| 3 | `read` subcommand + `--all` flag | `Commands/PRReadCommand.swift` | ~60 LOC |
| 4 | `comment` subcommand + GitHub posting | `Commands/PRCommentCommand.swift` | ~90 LOC |
| 5 | `--delta` flag + commit-range change detection | PRCommand modifications | ~100 LOC |
| 6 | Progress display + status indicators in default output | `renderSmartSummary` modifications | ~80 LOC |
| 7 | `/review` skill integration (update pr-review.md) | pr-review.md | ~30 LOC |

**Total**: ~560 LOC production + ~200 LOC tests

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `gh pr view` fails (no network, no auth) | Graceful degradation: skip delta detection, show cached state only |
| Force-pushed PR invalidates commit SHAs | State load prunes files not in current diff; `lastReviewedCommit` check falls back to full re-review if SHA not in history |
| Large PR with 50+ files makes state file unwieldy | JSON is compact; 50 entries < 10KB. Not a real risk. |
| Multiple reviewers conflict on same state file | BR-10: future multi-reviewer keyed by username. Current: single reviewer, no conflict. |

---

## @shi Team Challenge

**@Sensei (CTO)**: The `PRReviewProgress` model uses optional `reviewedAtCommit` per file. Is per-file commit tracking worth the complexity, or should we rely solely on the global `lastReviewedCommit`? Per-file gives precision (file A reviewed at commit X, file B at commit Y across sessions) but the global approach is simpler and sufficient for "did anything change since my last pass." Argue the tradeoff.

**@Ronin (Adversarial)**: What happens when a reviewer runs `read --all` on a 30-file PR without actually reading any file? The progress bar shows 100% but the review is hollow. Should we track "read via `--all`" differently from individual `read` actions — maybe a `bulk_reviewed` status that renders as `[~]` instead of `[✓]`? Or is that paternalistic design?

**@Metsuke (Quality)**: The comment posting to GitHub happens synchronously during `shiki pr N comment`. If the `gh api` call fails (rate limit, network), should the comment still persist locally and retry later? Or fail loud so the reviewer knows it did not reach GitHub? What is the right failure mode for dual-write?

---

## Review History

| Date | Reviewer | Action |
|------|----------|--------|
| 2026-03-21 | @Daimyo | Initial spec draft |
