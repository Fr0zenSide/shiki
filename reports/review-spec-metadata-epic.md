# PR Review: Spec Metadata Improvement Epic

**Date**: 2026-03-30
**Reviewer**: @Ronin (adversarial) + @Metsuke (quality)
**Branches**: `feature/spec-meta-w1`, `feature/spec-meta-w2`, `feature/spec-meta-w4`
**Target**: `develop`

---

## Executive Summary

This epic delivers a **structured spec lifecycle management system** for Shikki — parsing YAML frontmatter from feature specs, exposing CLI commands to manage review workflows (list, read, review, validate, progress), and migrating legacy specs to the v2 frontmatter format. The system models spec lifecycle as a state machine (draft -> review -> partial -> validated -> implementing -> shipped -> archived), supports per-reviewer anchor bookmarks, section-level validation, Flsh voice-compatibility blocks, and dependency/tag tracking.

| Metric | Value |
|--------|-------|
| Total new LOC (additions) | ~5,991 across all 3 branches |
| W2 also deletes ~14,493 lines (ShikkiTestRunner removal) | Net W2: -12,364 |
| Source files added | 16 |
| Test files added | 7 |
| Total @Test functions | **80** (W1: 35, W2: 33, W4: 12) |
| Risk level | **MEDIUM** — type name collisions between branches require careful merge order |

---

## Branch 1: Frontmatter Parser (W1)

**Commit**: `e6285e4b feat(spec-meta): Wave 1 — Frontmatter parser, annotation parser, lifecycle model`
**Stats**: 6 files, +1,341 lines

### Source Files

#### 1. `projects/shikki/Sources/ShikkiKit/Services/SpecMetadata.swift` (177 LOC)

**Purpose**: Defines the core data model — `SpecLifecycle` state machine, `ReviewerVerdict`, `ReviewerEntry`, `FlshBlock`, and `SpecMetadata` struct.

**Key decisions**:
- Lifecycle modeled as a `CaseIterable` enum with explicit `validTransitions` computed property returning `Set<SpecLifecycle>`
- `outdated` is a terminal state reachable from any non-outdated state
- All types are `Sendable` and `Equatable` — correct for concurrent use
- Date fields stored as `String` (not `Date`) — pragmatic for YAML round-tripping
- `totalSections` is computed from the markdown body, stored on the model

**@Ronin flags**:
- `SpecLifecycle` uses the name `SpecLifecycle`. W2 defines `SpecLifecycleStatus` for the same concept. **Type name collision at merge time.**
- `ReviewerEntry` vs W2's `SpecReviewer` — same concept, different names, different field types (`[Int]` vs `[Int]?`). Hard merge conflict.
- `FlshBlock.summary` is `String?` here but `String` (non-optional) in W2. Semantic difference.

**@Metsuke flags**:
- Good: all stored properties are `let` (immutable). Clean value types.
- `validTransitions` does not include `review -> draft` (going back to draft after review). W2 does allow `review -> draft`. Divergence.

**Critical excerpt** — the lifecycle state machine:
```swift
public var validTransitions: Set<SpecLifecycle> {
    switch self {
    case .draft:        return [.review, .outdated]
    case .review:       return [.partial, .validated, .outdated]
    // Note: .review does NOT include .draft — no going back
    case .partial:      return [.review, .validated, .outdated]
    case .validated:    return [.implementing, .rejected, .outdated]
    case .implementing: return [.shipped, .outdated]
    case .shipped:      return [.archived, .outdated]
    case .archived:     return [.outdated]
    case .rejected:     return [.outdated]
    case .outdated:     return []
    }
}
```

---

#### 2. `projects/shikki/Sources/ShikkiKit/Services/SpecFrontmatterParser.swift` (410 LOC)

**Purpose**: Hand-rolled YAML frontmatter parser. Extracts metadata from `---` delimited YAML blocks, validates progress format, parses reviewer arrays with nested fields, counts `##` sections in the body.

**Key decisions**:
- **No YAML library dependency** — hand-rolled parser using `String.components(separatedBy:)` and line-by-line state machine. Correct for the subset of YAML used in specs.
- Throws typed `SpecFrontmatterError` with `LocalizedError` conformance
- `title` is required; `status` defaults to `draft` if missing
- Progress validated as `N/M` where `N <= M`
- Reviewer parsing handles nested YAML structures manually (start with `- who:`, consume indented key-value pairs until next entry or top-level key)

**@Ronin flags**:
- **No escaping for YAML special characters**. If a title contains a colon (e.g. `title: "Problem: things break"`), `parseYAMLFields` will split on the first colon, which would truncate it. However, since titles are quoted, the `trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))` stripping happens after the split, so the colon-after-first is lost. Actually, looking more carefully, the value extraction is `String(trimmed[trimmed.index(after: colonIndex)...])`, which takes everything after the first colon — so `Problem: things break` would work. **False alarm, but worth a test.**
- `extractFrontmatter` trims the entire content before checking for `---` prefix. If a file starts with a BOM or whitespace, it still works. Good.
- `parseReviewers` accumulates state across a `for` loop with multiple mutable variables (`currentEntry`, `currentSectionsValidated`, `currentSectionsRework`, `inReviewers`). Complex but functionally correct.
- `parseArrayField` uses a `capturing` boolean that flips when a non-array line is hit. If a `depends-on` block has a blank line between items, capturing stops. **Edge case: blank lines within array blocks are silently swallowed but capture stops.**

**@Metsuke flags**:
- `parse(filePath:)` uses `FileManager.default.fileExists(atPath:)` + `String(contentsOfFile:)`. Race condition if file is deleted between check and read. Should just try reading and catch the error. Minor.
- `countSections` trims whitespace then checks `hasPrefix("## ")` — but also checks `!trimmed.hasPrefix("### ")`. Since `"### "` starts with `"## "`, this is correct to exclude `###`.

**Critical excerpt** — reviewer parsing state machine:
```swift
// New reviewer entry starts with `- who:`
if trimmed.hasPrefix("- who:") {
    // Save previous entry
    if let entry = try buildReviewerEntry(currentEntry, ...) {
        entries.append(entry)
    }
    currentEntry = [:]
    currentSectionsValidated = []
    currentSectionsRework = []
    let value = String(trimmed.dropFirst(6))
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    currentEntry["who"] = value
    continue
}
```

---

#### 3. `projects/shikki/Sources/ShikkiKit/Services/SpecAnnotationParser.swift` (161 LOC)

**Purpose**: Parses inline `<!-- @note @Who date -->` HTML comment annotations from spec markdown bodies. Supports open/applied/resolved statuses and multi-line content.

**Key decisions**:
- Annotations are **HTML comments**, not YAML — parsed from the body, not frontmatter
- Block parsing: consecutive `<!-- -->` lines starting with `<!-- @note @Who -->` form one annotation
- `openNotes(in:)` convenience filter for open-only

**@Ronin flags**:
- Multi-line comments that aren't `<!-- ... -->` per line will break. For example, `<!-- @note @Who\ncontent -->` on two lines won't parse — the first line doesn't end with `-->`. This is by design (annotations use one-line-per-comment format) but undocumented.
- No limit on annotation count — if a malicious file has 10,000 annotations, it will parse them all into memory. Not a realistic concern for spec files.

**@Metsuke flags**:
- Clean, straightforward parser. Good use of early return and index advancement.
- No test for annotation with content that contains `-->` inside the comment text (e.g., `<!-- This --> is tricky -->`). Would break `extractCommentContent`.

---

### W1 Test Files

#### `SpecFrontmatterParserTests.swift` (377 LOC, 18 @Test)

Covers: full frontmatter, minimal frontmatter, all lifecycle states, invalid status, progress format validation (valid, invalid, N>M), reviewer anchors, invalid anchor, section counting, missing frontmatter, unclosed frontmatter, missing title, flsh block, no flsh, inline tags, multiple depends-on, default status.

**@Metsuke flags**:
- Missing: title with special characters (colons, quotes), empty tags array `[]`, reviewer with empty sectionsValidated, progress `0/0`, deeply nested YAML (shouldn't break), file with only `---\n---` (empty frontmatter).

#### `SpecAnnotationParserTests.swift` (153 LOC, 9 @Test)

Covers: single annotation, multiple annotations, open filter, all statuses, default status, multi-line content, no annotations, annotation at EOF.

**@Metsuke flags**:
- Missing: annotation with no content lines, annotation with `pending` date explicitly, malformed comment (no closing `-->`), annotation where `@note` appears in body text (not as comment).

#### `SpecMetadataTests.swift` (63 LOC, 8 @Test)

Covers: lifecycle transitions (draft->review, skip-to-validated, validated->implementing/rejected, any->outdated, outdated terminal, rejected->outdated), reviewer verdict uniqueness, default init.

**@Metsuke flags**:
- Solid coverage of the state machine. Missing: `partial -> review` transition (going back for more review), `implementing -> shipped`, `shipped -> archived`.

---

## Branch 2: CLI Commands (W2)

**Commit**: `4f969f5f feat(spec-meta): Wave 2 — CLI commands for spec lifecycle management`
**Stats**: 89 files changed, +2,129 / -14,493 (includes ShikkiTestRunner deletion + mega merge cleanup)
**Net new spec-meta code**: ~1,730 LOC (excluding deletions and unrelated changes)

### Source Files

#### 1. `projects/shikki/Sources/ShikkiKit/Models/SpecMetadata.swift` (202 LOC)

**Purpose**: Redefines the core data model in `Models/` (not `Services/`). Same concept as W1's `SpecMetadata.swift` but with **different type names and richer API**.

**Key decisions**:
- `SpecLifecycleStatus` (not `SpecLifecycle`) — has a `.marker` property for TUI rendering (SF Symbols as Unicode)
- `SpecReviewer` (not `ReviewerEntry`) — uses `var` (mutable) instead of `let`, has `CodingKeys` for snake_case mapping, `[Int]?` (optional arrays) instead of `[Int]`
- `SpecFlshBlock` (not `FlshBlock`) — `summary` is non-optional `String`
- `SpecMetadata` has `Codable` conformance, `CodingKeys`, computed properties (`progressParsed`, `primaryReviewer`, `latestReviewDate`), and a `filename` field
- **Richer state machine**: `review -> draft` and `implementing -> validated` and `rejected -> draft` transitions exist (not in W1)

**@Ronin flags**:
- **CRITICAL: Type name collision with W1**. W1 defines `SpecMetadata` in `Services/SpecMetadata.swift`. W2 defines `SpecMetadata` in `Models/SpecMetadata.swift`. Both are in the `ShikkiKit` module. **These WILL conflict at compile time if both branches are merged.** W2's version is the richer/production-ready one.
- W1 defines `SpecLifecycle`, W2 defines `SpecLifecycleStatus`. W4 references `SpecLifecycle`. Merge W2 last or rename.
- `SpecLifecycleStatus.marker` uses escaped Unicode sequences like `"\u{10C05B}"` (SF Symbol private use area). These will render as tofu on non-Apple terminals. Acceptable for a macOS-only CLI.
- `var` properties on `SpecReviewer` enable mutation in CLI commands (e.g., `metadata.reviewers[idx].verdict = .validated`). W1 uses `let` which would require creating new instances. W2's approach is more ergonomic for the write path.

**@Metsuke flags**:
- `Codable` conformance is good — enables JSON serialization for ShikiDB later
- `progressParsed` returns `nil` for invalid format instead of throwing — correct for a computed property
- `primaryReviewer` picks first non-pending, falls back to first overall — intuitive

**Critical excerpt** — computed progress parsing:
```swift
public var progressParsed: (reviewed: Int, total: Int)? {
    guard let progress else { return nil }
    let parts = progress.split(separator: "/")
    guard parts.count == 2,
          let reviewed = Int(parts[0]),
          let total = Int(parts[1]) else { return nil }
    return (reviewed, total)
}
```

---

#### 2. `projects/shikki/Sources/ShikkiKit/Services/SpecFrontmatterService.swift` (517 LOC)

**Purpose**: Full-featured frontmatter service — parse, write, update fields, scan directories, serialize to YAML, format for TUI display. Replaces/supersedes W1's `SpecFrontmatterParser`.

**Key decisions**:
- `parse()` returns `SpecMetadata?` (optional, not throwing) — different from W1's throwing API
- Includes **write path**: `updateFrontmatter(in:with:)` and `updateField(in:key:value:)` for in-place YAML mutation
- `scanDirectory()` enumerates `features/*.md`, creates minimal metadata for files without frontmatter
- `serializeToYAML()` and `parseYAML()` form a round-trip pair
- `findAnchorLine()` + `slugifyHeading()` for reviewer bookmark resolution
- Static `formatListEntry()` and `formatProgressSummary()` for TUI rendering

**@Ronin flags**:
- `parseYAML` is a ~120-line hand-rolled parser with mutable state machine (`currentKey`, `currentArray`, `inArray`, `arrayItemDict`). Functionally tested but complex. **One missed state transition could silently drop data.** The round-trip test helps mitigate this.
- `frontmatterRange()` finds the first `\n---` after opening `---`. If the YAML body contains `---` (e.g., in a quoted string), it will terminate too early. Low risk for spec files but worth noting.
- `updateField()` string-replaces lines starting with `key:`. If the key appears in a nested context (e.g., `notes: "some key: value"`), it could match incorrectly. Currently only used for top-level fields, so acceptable.
- `cleanYAMLValue` strips surrounding quotes — correct for the subset used.

**@Metsuke flags**:
- `scanDirectory` creates fallback metadata for files without frontmatter using `extractFirstHeading`. Good degradation behavior.
- `serializeToYAML` writes `anchor: null` for nil anchors — parsed back correctly by `parseYAML` which checks for `"null"` string.
- `slugifyHeading` strips `.,:()'"` but not `-`, `_`, or digits. Adequate for spec headings.

**Critical excerpt** — update frontmatter in place:
```swift
public func updateFrontmatter(in content: String, with metadata: SpecMetadata) -> String {
    let yamlString = serializeToYAML(metadata)
    let newFrontmatter = "---\n\(yamlString)---"

    if let range = frontmatterRange(in: content) {
        var result = content
        result.replaceSubrange(range, with: newFrontmatter)
        return result
    } else {
        return newFrontmatter + "\n\n" + content
    }
}
```

---

#### 3. `projects/shikki/Sources/shikki/Commands/SpecListCommand.swift` (84 LOC)

**Purpose**: `shikki spec list [--status draft]` — lists all specs with status marker, progress, and reviewer info.

**Key decisions**:
- Auto-detects `features/` by walking up from cwd
- Sorts by lifecycle priority (validated first)
- Filter by `--status` flag
- Uses `SpecFrontmatterService.formatListEntry()` for consistent formatting

**@Ronin flags**: None. Clean command with proper error handling and stderr for errors.

---

#### 4. `projects/shikki/Sources/shikki/Commands/SpecReadCommand.swift` (110 LOC)

**Purpose**: `shikki spec read <file> [--reviewer @Daimyo]` — opens spec at reviewer's last anchor position in a tmux window with bat.

**Key decisions**:
- Resolves anchor from reviewer's frontmatter entry
- Opens with `bat --paging=always --highlight-line N` in a tmux new-window
- Falls back to printing path+line if tmux is unavailable

**@Ronin flags**:
- `openInTmux` constructs the bat command as a single string passed to `tmux new-window`. If `specPath` contains spaces or special chars, it will break. Should use array-based argument passing.
- `Process` is launched synchronously with `waitUntilExit()` — blocks the current thread. For tmux this is near-instant, so acceptable.

**Critical excerpt** — potential shell injection:
```swift
let batArgs = lineNumber > 1
    ? "bat --paging=always --highlight-line \(lineNumber) \(specPath)"
    : "bat --paging=always \(specPath)"

process.arguments = [
    "tmux", "new-window", "-n", windowName, batArgs,
]
// batArgs is a single string — tmux will interpret it as a shell command
// If specPath is "/path/with spaces/file.md", this breaks
```

---

#### 5. `projects/shikki/Sources/shikki/Commands/SpecReviewCommand.swift` (134 LOC)

**Purpose**: `shikki spec review <file>` — transitions spec to "review" status, adds/updates reviewer entry with "reading" verdict.

**Key decisions**:
- Validates current status allows transition (must be draft, partial, or review)
- Auto-sets progress to `0/sectionCount` if not set
- Updates `updated` date
- Writes modified frontmatter back to file

**@Ronin flags**:
- `todayString()` creates a new `DateFormatter` on every call. Not a performance concern for CLI, but wasteful.
- Transition guard allows `review -> review` (re-entering review). Intentional — lets a different reviewer start.

---

#### 6. `projects/shikki/Sources/shikki/Commands/SpecValidateCommand.swift` (211 LOC)

**Purpose**: `shikki spec validate <file> [--partial "#section-8" --rework "8,9" --notes "..."]` — sets spec to validated or partial status.

**Key decisions**:
- Full validation: sets all sections as validated, clears anchor and rework
- Partial validation: computes validated = all sections minus rework sections, sets anchor bookmark
- Both modes update reviewer entry and write frontmatter

**@Ronin flags**:
- `applyPartialValidation` computes `allSections = Set(1...sectionCount)`. If `sectionCount` is 0, `1...0` is an empty range (not a crash in Swift). Good.
- `rework` parsing uses `split(separator: ",").compactMap { Int($0) }`. Non-numeric values are silently dropped. Acceptable behavior.
- Guard allows partial validation from `draft` status directly. Semantically odd (partial without having been in review first) but not harmful.

---

#### 7. `projects/shikki/Sources/shikki/Commands/SpecProgressCommand.swift` (74 LOC)

**Purpose**: `shikki spec progress` — shows a dashboard summary with per-status counts and a progress bar.

**@Ronin flags**: None. Clean, stateless display command.

---

#### 8. `projects/shikki/Sources/shikki/Commands/SpecCommand.swift` (modified)

**Purpose**: Hub command registering subcommands: generate, list, read, review, validate, progress. Default: list.

**@Ronin flags**: SpecMigrateCommand (W4) is registered separately as `spec-migrate`, not under `spec`. Intentional — migration is a one-time operation, not a daily workflow. Good separation.

---

### W2 Test Files

#### `Spec/SpecFrontmatterServiceTests.swift` (388 LOC, 18 @Test)

Covers: minimal parse, full parse, no frontmatter, no title, partial reviewer with anchors, section counting (with/empty), anchor resolution (exact, not found, hash prefix), frontmatter update (existing/prepend), full lifecycle transition (draft->review->partial->validated), format list entry (validated/draft), format progress summary, heading slugification, YAML round-trip.

**@Metsuke flags**:
- The round-trip test is excellent — serializes then re-parses and verifies fields match
- Missing: `updateField` test, `scanDirectory` test, file-based `parse(fileAt:)` test, tags with special characters, reviewers with `rework` verdict

#### `Spec/SpecMetadataTests.swift` (119 LOC, 15 @Test)

Covers: all markers non-empty, transition tests (draft->review, review->validated, review->partial, validated->implementing, validated->rejected, outdated terminal, draft !-> shipped, any->outdated), progress parsing (valid, nil, invalid), primary reviewer selection (non-pending, fallback), latest review date.

**@Metsuke flags**:
- Good coverage of the `W2-specific` additions (progressParsed, primaryReviewer, latestReviewDate)
- Missing: `Codable` encoding/decoding round-trip test

---

## Branch 3: Migration Script (W4)

**Commit**: (built on top of W1)
**Stats**: 10 files, +2,521 lines (includes W1's files)
**Net new W4-only**: ~1,180 LOC (SpecMigrationService + SpecMigrateCommand + tests)

### Source Files

#### 1. `projects/shikki/Sources/ShikkiKit/Services/SpecMigrationService.swift` (620 LOC)

**Purpose**: Batch migrates spec files to v2 frontmatter format. Handles both YAML-frontmatter files (adds missing fields) and markdown-style files (converts `> **Status**: draft` to proper YAML). Generates tags from keyword analysis, estimates voice duration, produces detailed migration reports.

**Key decisions**:
- **Two migration paths**: `migrateYAMLFrontmatter` (add missing fields) and `migrateMarkdownStyle` (convert to YAML)
- Dry-run mode computes changes without writing
- Status normalization: maps ~30 aliases (`spec`, `plan`, `wip`, `done`, `deprecated`, `approved`, `cancelled`, `PLAN — tests first`) to valid lifecycle values
- Tag generation: keyword-frequency analysis with domain-specific mappings (20 keyword groups)
- Flsh block generation: extracts first sentence after first `##` heading as summary, estimates duration at 150 WPM
- File-level and batch-level reports with `SpecMigrationFileReport` and `SpecMigrationReport`

**@Ronin flags**:
- **References W1's `SpecLifecycle` type** (not W2's `SpecLifecycleStatus`). This means W4 depends on W1 being merged first and conflicts with W2.
- `generateTags` does substring matching on the entire lowercased body. Tags like `"ai"` will match words like "maintain", "plain", "certain". Prefix/suffix word boundary checking would reduce false positives.
- `generateSummary` extracts first sentence after first `##` heading. If the first paragraph is a list (`- item1`), the strip only handles `- ` and `* ` prefixes. `1. ` numbered lists would pass through.
- `parseInlineMetaField` handles `> **Key**: Value` but only extracts the first key from pipe-separated fields (`Created: 2026-03-23 | Author: @Sensei`). The `Author` and other fields in the same line are lost. Comment says "caller iterates over pipe-split segments separately" but no such iteration exists in `migrateMarkdownStyle`.
- `migrateMarkdownStyle` prepends YAML frontmatter but does NOT remove the original `> **Status**:` blockquote lines. The `metaLineIndices` set is computed but never used to strip those lines. The original body is kept intact, resulting in **duplicate metadata** (YAML frontmatter + original blockquotes).
- `getFileModifiedDate` reads filesystem mtime. In a git repo, mtime reflects the last checkout, not the actual creation date. The fallback to today is pragmatic.

**@Metsuke flags**:
- `migrateYAMLFrontmatter` and `migrateMarkdownStyle` are long methods (~80 and ~70 lines) but well-structured with clear sections
- `normalizeStatus` is thorough with many aliases — good coverage of real-world spec status strings
- `replaceFieldValue` only handles top-level fields (no indentation). Correct for status, which is always top-level.

**Critical excerpt** — unused metaLineIndices (potential bug):
```swift
// In migrateMarkdownStyle:
var metaLineIndices: Set<Int> = []
// ... populated during parsing ...
metaLineIndices.insert(index)  // Computed but never used to filter lines

// Later:
var result = yaml       // YAML frontmatter
result.append(contentsOf: lines)  // Original lines INCLUDING the blockquote metadata
// Result: duplicate metadata in output
```

**Critical excerpt** — tag false-positive risk:
```swift
for keyword in mapping.keywords {
    var searchRange = lowered.startIndex..<lowered.endIndex
    while let range = lowered.range(of: keyword, range: searchRange) {
        score += 1  // "ai" matches "maint-ai-n", "cert-ai-n", etc.
        searchRange = range.upperBound..<lowered.endIndex
    }
}
```

---

#### 2. `projects/shikki/Sources/shikki/Commands/SpecMigrateCommand.swift` (103 LOC)

**Purpose**: `shikki spec-migrate [--dry-run] [--file <path>] [--directory <path>]` CLI command.

**Key decisions**:
- Registered as top-level `spec-migrate` (not under `spec`)
- Supports single-file and batch modes
- Colored output with ANSI escapes

**@Ronin flags**:
- `resolvePath` prepends cwd if not absolute. Does not canonicalize (`..` segments preserved). Minor.

---

#### 3. `projects/shikki/Sources/shikki/Commands/ShikkiCommand.swift` (modified)

**Purpose**: Registers `SpecMigrateCommand` in the top-level command list.

**@Ronin flags**: None. One-line addition.

---

### W4 Test Files

#### `SpecMigrationServiceTests.swift` (456 LOC, 12 @Test)

Covers: (1) adds missing fields to YAML, (2) preserves existing fields, (3) dry-run, (4) section count accuracy, (5) section count zero, (6) duration estimation, (7) status normalization (direct, aliases, case-insensitive, compound, unknown), (8) status normalization in file, (9) markdown-style migration, (10) tag generation, (11) single file migration, (12) multi-file batch.

**@Metsuke flags**:
- Uses `withTempDir` helper with proper cleanup — good test hygiene
- Missing: file that is BOTH up-to-date AND has a non-standard status (should normalize but report no fields added — tests these as separate cases but not combined)
- Missing: markdown-style with pipe-separated fields (`> Created: 2026 | Author: @Sensei`)
- Missing: empty directory test, non-.md files in directory, file permission errors

---

## Cross-Branch Analysis

### Type Name Collisions

| Concept | W1 Name | W2 Name | W4 Uses |
|---------|---------|---------|---------|
| Lifecycle enum | `SpecLifecycle` | `SpecLifecycleStatus` | `SpecLifecycle` (W1) |
| Reviewer struct | `ReviewerEntry` | `SpecReviewer` | N/A |
| Reviewer verdict | `ReviewerVerdict` | `SpecReviewerVerdict` | N/A |
| Flsh block | `FlshBlock` | `SpecFlshBlock` | N/A |
| Metadata struct | `SpecMetadata` | `SpecMetadata` | `SpecMetadata` (W1) |
| Metadata file path | `Services/SpecMetadata.swift` | `Models/SpecMetadata.swift` | `Services/SpecMetadata.swift` |
| Parser | `SpecFrontmatterParser` | `SpecFrontmatterService` | N/A |

**Verdict**: W1 and W2 define the **same `SpecMetadata` struct name** in the same module (`ShikkiKit`). They live in different files (`Services/` vs `Models/`) but Swift compiles the entire module together. **These will produce a duplicate type error.** W4 depends on W1's types.

### Merge Order Dependencies

The correct merge order is:

1. **W1 first** — establishes the base types
2. **W4 second** — depends on W1's `SpecLifecycle` and `SpecMetadata`
3. **W2 last** — must resolve type conflicts by either:
   - Renaming W1's types to match W2's naming convention (preferred — W2 is richer)
   - Or deleting W1's `SpecMetadata.swift` and `SpecFrontmatterParser.swift` (since W2 supersedes them)

**Alternative**: Merge W2 first (since it has the richer model), then rebase W1+W4 to use W2's type names. This is cleaner but requires more rebasing.

### Functional Overlap

- `SpecFrontmatterParser` (W1) and `SpecFrontmatterService` (W2) **both parse YAML frontmatter** with different APIs (throwing vs optional). W2's service also has write/update/scan capabilities. W1's parser should be deleted or consolidated into W2's service.
- `countSections` is implemented in W1's `SpecFrontmatterParser`, W2's `SpecFrontmatterService`, AND W4's `SpecMigrationService`. Triple duplication.
- `findFeaturesDirectory()` is copy-pasted across 5 CLI command files. Should be extracted to a shared utility.

### Transition Graph Disagreement

| Transition | W1 | W2 |
|-----------|----|----|
| `review -> draft` | NO | YES |
| `implementing -> validated` | NO | YES |
| `rejected -> draft` | NO | YES |

W2 allows "going back" transitions that W1 forbids. W2's model is more practical for real workflows. **Use W2's transition graph.**

---

## @Ronin Adversarial Review

### What Could Break?

1. **Merge-time compilation failure**: Duplicate `SpecMetadata` type in ShikkiKit module. Both W1 and W2 define it. This is a **guaranteed build failure** if both are merged without resolution.

2. **W4 references W1 types that W2 renames**: `SpecMigrationService.normalizeStatus()` references `SpecLifecycle(rawValue:)`. If W2's `SpecLifecycleStatus` wins, W4 won't compile.

3. **Markdown-style migration duplicates metadata**: `migrateMarkdownStyle` prepends YAML frontmatter but leaves the original `> **Status**: Draft` blockquote lines in the body. Files end up with both YAML and inline metadata.

4. **Tag false positives**: `generateTags` does substring matching. Short keywords like `"ai"`, `"ui"`, `"db"` match inside longer words. A spec about "maintaining databases" gets tagged `[ai, database, ui]` when only `database` is relevant.

5. **`specPath` with spaces in tmux**: `SpecReadCommand.openInTmux` passes the bat command as a single string. Paths with spaces break silently.

### What's Missing?

1. **No integration test between W1/W2/W4**: No test verifies that `SpecMigrationService` produces output that `SpecFrontmatterService.parse()` can read back. The migration service and the parser are in different branches and have never been tested together.

2. **No `Codable` round-trip test** for W2's model despite having `Codable` conformance.

3. **No concurrent access safety test** for `SpecFrontmatterService.scanDirectory()`. Multiple `shikki spec list` invocations running simultaneously could read partially-written files.

4. **No spec for W3** (what happened to Wave 3?). The naming jumps from W2 to W4.

### Security Concerns

- **Path traversal**: `resolveSpecPath` in CLI commands accepts relative paths and prepends the features directory. Input like `../../.env` would resolve to a path outside features/. However, this only reads/writes the file — it doesn't execute it. Low risk for a local CLI tool.
- **Shell injection via tmux**: `specPath` is interpolated into a string passed to tmux. A filename like `; rm -rf /` would be interpreted by the shell. Again, low risk since spec filenames come from the local filesystem, not user input. But sanitization would be good practice.

### Edge Cases Not Tested

- Spec file with Windows line endings (`\r\n`)
- Spec file with UTF-8 BOM
- Spec file that is only frontmatter (no body)
- Spec file with frontmatter containing `---` inside a YAML string value
- Concurrent writes to the same spec file (two `shikki spec validate` commands racing)
- Very large spec files (>10MB) — no streaming, everything is loaded into memory
- Frontmatter with YAML anchors/aliases (`<<: *default`) — will be silently ignored by hand-rolled parser

---

## @Metsuke Quality Inspection

### Test Coverage vs Source LOC

| Branch | Source LOC | Test LOC | @Test Count | Ratio (test:src) |
|--------|-----------|----------|-------------|-------------------|
| W1 | 748 | 593 | 35 | 0.79:1 |
| W2 | 1,203 | 507 | 33 | 0.42:1 |
| W4 | 723 | 456 | 12 | 0.63:1 |
| **Total** | **2,674** | **1,556** | **80** | **0.58:1** |

W2 has the lowest test:source ratio. The CLI commands (5 files, ~613 LOC) have zero unit tests — only the service and model are tested.

### Missing Test Scenarios

**High priority**:
- Round-trip: `SpecMigrationService` output -> `SpecFrontmatterService.parse()` (integration)
- `Codable` encode/decode for W2's `SpecMetadata`
- `updateField` in `SpecFrontmatterService`
- `scanDirectory` with mixed files (`.md` + `.txt` + directories)

**Medium priority**:
- YAML with Windows line endings
- Title containing colons or quotes
- Anchor with URL-encoded characters
- Tags with spaces or special characters

**Low priority**:
- CLI command error paths (file not found, permission denied)
- Progress bar rendering edge cases (0%, 100%)
- Empty reviewer arrays in serialization

### Code Duplication

| Pattern | Occurrences | Locations |
|---------|-------------|-----------|
| `findFeaturesDirectory()` | 5 | SpecListCommand, SpecProgressCommand, SpecReadCommand, SpecReviewCommand, SpecValidateCommand |
| `writeStdout` / `writeStderr` | 5 | Same 5 commands |
| `resolveSpecPath` | 3 | SpecReadCommand, SpecReviewCommand, SpecValidateCommand |
| `extractTitle` | 2 | SpecReviewCommand, SpecValidateCommand |
| `todayString()` | 2 | SpecReviewCommand, SpecValidateCommand |
| `countSections` | 3 | SpecFrontmatterParser (W1), SpecFrontmatterService (W2), SpecMigrationService (W4) |
| YAML field parsing | 3 | SpecFrontmatterParser (W1), SpecFrontmatterService (W2), SpecMigrationService (W4) |

**Recommendation**: Extract `findFeaturesDirectory`, `writeStdout/writeStderr`, `resolveSpecPath`, `extractTitle`, and `todayString` into a shared `SpecCommandHelpers` or a base protocol extension.

---

## Verdict

### SHIP WITH FIX

The epic delivers real value — the spec lifecycle system, CLI commands, and migration tooling are well-designed and thoroughly tested (80 tests). The code is clean Swift 6 with proper Sendable/Equatable conformance and value types throughout.

**However, three issues MUST be fixed before merging to develop:**

#### Fix 1: Resolve Type Collisions (BLOCKING)

W1 and W2 both define `SpecMetadata` in `ShikkiKit`. Choose one:
- **Option A** (recommended): Delete W1's `Services/SpecMetadata.swift` and `Services/SpecFrontmatterParser.swift`. W2's `Models/SpecMetadata.swift` and `Services/SpecFrontmatterService.swift` supersede them. Rename W2's `SpecLifecycleStatus` to `SpecLifecycle` (shorter name, W4 already uses it). Update W4 to use W2's type names.
- **Option B**: Merge W2 only, drop W1 (W2 contains all of W1's functionality plus more). Rebase W4 onto W2.

#### Fix 2: Fix Markdown Migration Duplicate Metadata (W4)

`migrateMarkdownStyle` computes `metaLineIndices` but never uses them to strip the original blockquote metadata lines. After migration, files have YAML frontmatter AND the original `> **Status**: Draft` lines. Fix: filter out `metaLineIndices` when constructing the output body.

#### Fix 3: Extract Duplicated Helpers

The 5 CLI commands share ~6 identical helper methods. Extract to a shared protocol or utility before merging, or file it as immediate follow-up tech debt.

**Non-blocking notes for post-merge**:
- Add word-boundary checking to tag generation (`\b` regex or split-then-match)
- Quote `specPath` in tmux bat command
- Add `Codable` round-trip tests for W2 model
- Add cross-branch integration test (migration output -> parse)
- Clarify what happened to W3
