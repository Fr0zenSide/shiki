# Post-Merge Review: 3 Epics on develop

**Date:** 2026-04-01
**Branch:** develop
**Commits:** 395e2681 (spec-meta-fixes) + 48cbea04 (cmd-arch-combined) + e9172205 (creative-studio-plugins)
**Diff range:** 0f8eb38e..e9172205 — +15,346 / -76 lines across 73 files
**Swift LOC (new files):** 5,842 source + 3,792 test = **9,634 total**

---

## Epic 1: Spec Metadata (feature/spec-meta-fixes)

### What it delivers

Unified spec metadata system: YAML frontmatter parser, annotation parser, migration service to upgrade legacy specs from markdown-style metadata to structured YAML, plus six CLI subcommands (`spec list`, `spec read`, `spec review`, `spec validate`, `spec progress`, `spec-migrate`).

### Files + LOC

| File | LOC | Role |
|------|-----|------|
| `ShikkiKit/Models/SpecMetadata.swift` | 207 | Domain model: lifecycle FSM, reviewers, flsh block |
| `ShikkiKit/Services/SpecFrontmatterParser.swift` | 420 | Low-level YAML parser (throwing) |
| `ShikkiKit/Services/SpecAnnotationParser.swift` | 161 | Inline `<!-- @note -->` HTML comment parser |
| `ShikkiKit/Services/SpecFrontmatterService.swift` | 517 | High-level service: parse, write, scan, format |
| `ShikkiKit/Services/SpecMigrationService.swift` | 689 | Batch migration: markdown-style to YAML frontmatter |
| `ShikkiKit/Services/SpecCommandUtilities.swift` | 60 | Shared helpers (find features dir, resolve path) |
| `Commands/SpecListCommand.swift` | 62 | `shikki spec list [--status X]` |
| `Commands/SpecReadCommand.swift` | 84 | `shikki spec read <file>` — open at reviewer anchor |
| `Commands/SpecReviewCommand.swift` | 90 | `shikki spec review <file>` — transition to review |
| `Commands/SpecValidateCommand.swift` | 167 | `shikki spec validate <file> [--partial]` |
| `Commands/SpecProgressCommand.swift` | 52 | `shikki spec progress` — dashboard summary |
| `Commands/SpecMigrateCommand.swift` | 83 | `shikki spec-migrate [--dry-run]` |
| **Total source** | **2,592** | |
| **Tests** | **1,593** | SpecMetadataTests (151) + SpecFrontmatterServiceTests (388) + SpecAnnotationParserTests (153) + SpecFrontmatterParserTests (377) + SpecMigrationServiceTests (524) |

### Key code excerpts

**Lifecycle FSM with valid transitions** (SpecMetadata.swift:38-50):
```swift
public var validTransitions: Set<SpecLifecycleStatus> {
    switch self {
    case .draft:        return [.review, .outdated]
    case .review:       return [.partial, .validated, .draft, .outdated]
    case .partial:      return [.review, .validated, .outdated]
    case .validated:    return [.implementing, .rejected, .outdated]
    case .implementing: return [.shipped, .validated, .outdated]
    case .shipped:      return [.archived, .outdated]
    case .archived:     return [.outdated]
    case .rejected:     return [.draft, .outdated]
    case .outdated:     return []
    }
}
```

**Word boundary matching for tag generation** (SpecMigrationService.swift:570-587):
```swift
private func countWordBoundaryMatches(keyword: String, in text: String, boundaryChars: CharacterSet) -> Int {
    var count = 0
    var searchRange = text.startIndex..<text.endIndex
    while let range = text.range(of: keyword, range: searchRange) {
        let beforeOK = range.lowerBound == text.startIndex ||
            String(text[text.index(before: range.lowerBound)]).rangeOfCharacter(from: boundaryChars) != nil
        let afterOK = range.upperBound == text.endIndex ||
            String(text[range.upperBound]).rangeOfCharacter(from: boundaryChars) != nil
        if beforeOK && afterOK { count += 1 }
        searchRange = range.upperBound..<text.endIndex
    }
    return count
}
```

### @Ronin adversarial review

1. **YAML injection via title/notes fields**: `serializeToYAML` in SpecFrontmatterService (line 344) wraps title in quotes (`"title: \"\(metadata.title)\""`) but does NOT escape embedded quotes in the title. A title containing `"` would produce invalid YAML and corrupt the frontmatter. **Severity: IMPORTANT** -- corrupts file silently on round-trip write.

2. **Path traversal in SpecCommandUtilities.resolveSpecPath**: If a user passes `../../../etc/passwd` it falls through to `"\(directory)/\(input)"` since `contains("/")` matches. However the command then tries to read it as a spec file, which would fail gracefully (no frontmatter found). **Low risk** -- no write operation on arbitrary path.

3. **Annotation parser regex-free but fragile**: `extractCommentContent` requires exact `<!-- ... -->` on a single line. Multi-line HTML comments are silently skipped. Documented behavior but may surprise users.

4. **Migration body stripping heuristic** (SpecMigrationService.swift:283-306): The `> Key: Value` stripping in `migrateMarkdownStyle` uses `afterQuote.count < 100` as a guard, plus a known-keys allowlist. This is cautious -- good. But lines matching `> Status: some long description that happens to be about project status` would get stripped even if it's not metadata.

5. **FileManager in tight loops**: `scanSpecFiles` + `migrateAll` read all .md files sequentially. Fine for ~50 spec files, would need async batching at scale (unlikely near-term).

### @Metsuke quality inspection

1. **DUPLICATE YAML PARSERS**: Three distinct YAML-parsing implementations:
   - `SpecFrontmatterParser.parseYAMLFields()` -- line-by-line simple parser (420 LOC)
   - `SpecFrontmatterService.parseYAML()` -- more complex parser with nested array/dict support (517 LOC)
   - `SpecMigrationService.parseExistingFields()` -- yet another top-level key parser (689 LOC)

   These overlap significantly. `SpecFrontmatterParser` and `SpecFrontmatterService` both parse the same YAML format with different algorithms. **Code smell: duplication across 3 files.** The `SpecFrontmatterParser` is the throwing version (used in tests), while `SpecFrontmatterService` is the optional-returning version (used in CLI). Both co-exist with no delegation between them.

2. **DUPLICATE `countSections`**: Identical `countSections` method appears in 3 files: `SpecFrontmatterParser` (line 399), `SpecFrontmatterService` (line 32), `SpecMigrationService` (line 491). All count `## ` headings. Should be a single shared utility.

3. **Test coverage: GOOD**. 1,593 test lines for 2,592 source lines (61% test-to-source ratio). All critical paths tested: parsing, migration, validation, edge cases. Migration tests include dry-run and markdown-style conversion.

4. **Sendable conformance: CLEAN**. All models and services are `Sendable`. No `@unchecked Sendable`. Parsers are stateless structs.

5. **SpecFrontmatterService.countSections** (line 32-35) uses `$0.hasPrefix("## ")` without the `!trimmed.hasPrefix("### ")` guard that the other two implementations have. Minor inconsistency -- `hasPrefix("## ")` already excludes `### ` since `### ` does not start with `## ` followed by a space. Wait -- actually `### Header` DOES start with `## ` (the first 3 characters are `## `). **BUG**: This counter will double-count `### ` headings as `## ` headings.

### Verdict: SHIP WITH FIX

**Must fix:**
- [ ] `SpecFrontmatterService.countSections` counts `###` as `##` (bug)
- [ ] YAML title serialization does not escape embedded double quotes

**Should fix (next iteration):**
- [ ] Consolidate 3 `countSections` implementations into SpecCommandUtilities
- [ ] Consolidate or delegate between SpecFrontmatterParser and SpecFrontmatterService

---

## Epic 2: Commands Architecture (feature/cmd-arch-combined)

### What it delivers

Compiled Swift entry points for three CLI commands (`review`, `quick`, `fast`) plus pre-PR quality gates. ReviewService with structured findings + verdicts, QuickPipeline with scope detection and TDD enforcement, FastPipeline composing quick+test+pre-pr+ship in one command. LLM is a worker (via ReviewProvider/AgentProviding protocols), Swift is the judge.

### Files + LOC

| File | LOC | Role |
|------|-----|------|
| `ShikkiKit/Services/PrePRGates.swift` | 413 | 4 gate structs + PrePRStatus persistence |
| `ShikkiKit/Services/ReviewProvider.swift` | 86 | Protocol + structured result types |
| `ShikkiKit/Services/ReviewService.swift` | 505 | PR review pipeline + findings parser + persistence |
| `ShikkiKit/Services/QuickPipeline.swift` | 427 | Scope detector + 4-step pipeline + prompt builder |
| `ShikkiKit/Services/FastPipeline.swift` | 218 | Quick + test + pre-pr + ship composition |
| `Commands/ReviewCommand.swift` | 379 | CLI: single/batch/pre-pr review modes |
| `Commands/QuickCommand.swift` | 140 | CLI: quick change with scope warning |
| `Commands/FastCommand.swift` | 210 | CLI: ultimate shortcut command |
| **Total source** | **2,378** | |
| **Tests** | **1,423** | PrePRGateTests (788) + QuickPipelineTests (291) + QuickFastCommandTests (119) + FastPipelineTests (225) |

### Key code excerpts

**ReviewProvider protocol — LLM as worker, Swift as judge** (ReviewProvider.swift:8-16):
```swift
public protocol ReviewProvider: Sendable {
    func runCtoReview(diff: String, featureSpec: String?) async throws -> ReviewResult
    func runSlopScan(sources: [String]) async throws -> SlopScanResult
}
```

**Scope detector with keyword scoring** (QuickPipeline.swift:110-161):
```swift
public func evaluate(_ prompt: String) -> (score: Int, signals: [ScopeSignal]) {
    let lower = prompt.lowercased()
    var signals: [ScopeSignal] = []
    let componentKeywords = ["and", "also", "plus", "both", "all"]
    let componentCount = componentKeywords.filter { lower.contains($0) }.count
    if componentCount >= 2 { signals.append(.multipleComponents) }
    // ... 6 more signal detectors
    return (score: signals.count, signals: signals)
}
```

**ReviewVerdict derivation — deterministic Swift logic** (ReviewService.swift:67-76):
```swift
public static func from(findings: [PRReviewFinding]) -> ReviewVerdict {
    let criticalCount = findings.filter { $0.severity == .critical }.count
    let importantCount = findings.filter { $0.severity == .important }.count
    if criticalCount > 0 { return .changesRequested }
    if importantCount >= 3 { return .changesRequested }
    if importantCount >= 1 { return .needsDiscussion }
    return .approve
}
```

### @Ronin adversarial review

1. **Shell injection in PrePRGates**: `CtoReviewGate.loadFeatureSpec` (line 78) uses `shellEscape` on the path but constructs a glob: `ls .../features/*\(shellEscape(slug))*` -- if `slug` contains shell metacharacters that `shellEscape` doesn't cover, this could be exploited. The `shellEscape` function (defined elsewhere in ShipContext) is the single security boundary. **Medium risk** if `shellEscape` is incomplete.

2. **`SlopScanGate` reads arbitrary files**: Line 123-128 uses `cat` to read source files from the diff list. The file paths come from `git diff --name-only` which should be safe (git-controlled), but the code does path construction with `context.projectRoot.path + "/" + file`. No path traversal check. **Low risk** -- git controls the input.

3. **ClaudeAgentReviewProvider hardcodes model** (ReviewCommand.swift:350): `model: "claude-sonnet-4-20250514"`. This should use a config or environment variable, not a hardcoded string that will go stale. **IMPORTANT** -- violates AI-provider-agnostic principle.

4. **`ReviewCommand.runPrePR` duplicates gate logic**: Lines 149-218 manually implements 4 gates using raw shell commands (`git status --porcelain`, `swift test`, etc.) instead of using the PrePRGates system from PrePRGates.swift. Two parallel pre-PR implementations. **Code smell: architectural inconsistency.**

5. **`FastPipeline.run` hardcodes `testsAllPassed = true`** (line 172): Comment says "Agent already ran tests in quick flow" but this skips actually verifying. If the agent's test run was incomplete or the quick pipeline didn't run tests, this passes silently. **IMPORTANT** -- false safety signal.

6. **Unused variable `reviewOutput`** (QuickPipeline.swift:261): The `reviewOutput` string is assigned but never read after the self-review step. Compiler warning likely.

### @Metsuke quality inspection

1. **Type naming collision handled by PR-prefix**: `ReviewFinding` vs `PRReviewFinding`, `ReviewResult` vs `PRReviewResult`, `ReviewProvider` vs `ReviewAnalysisProvider`. The code has comments explaining the distinction (lines 29-35 of ReviewService.swift). Acceptable workaround but suggests these could be namespaced into modules.

2. **Test coverage: STRONG**. PrePRGateTests at 788 lines is the most thorough test file in the diff. Tests mock the ReviewProvider and ShipContext. QuickPipeline scope detector has edge case tests.

3. **Sendable conformance: CLEAN**. All types marked `Sendable`. Protocols use `any` existential. No `@unchecked`.

4. **ScopeDetector keyword matching is naive**: `lower.contains("and")` matches "understand", "band", "sandcastle". The word-boundary matching technique from Epic 1 is NOT applied here despite solving the exact same problem. **Inconsistency between epics.**

5. **ReviewPersistence uses relative path** (ReviewService.swift:229): `baseDirectory: ".shikki/reviews"` -- this resolves relative to cwd. If cwd changes mid-run (unlikely in a CLI), persistence breaks. The ReviewCommand.reviewBaseDir() walks up to find `.shikki/` which is better, but the default constructor doesn't.

6. **Batch review is sequential** (ReviewService.swift:404-416): Could use `TaskGroup` for parallel batch review. Low priority given batch is typically 3-5 PRs.

### Verdict: SHIP WITH FIX

**Must fix:**
- [ ] `FastPipeline` must not hardcode `testsAllPassed = true` -- verify via actual test run or pass-through from quick result
- [ ] Remove hardcoded `claude-sonnet-4-20250514` model string -- use config/env

**Should fix (next iteration):**
- [ ] Unify `ReviewCommand.runPrePR` with `PrePRGates` system (two parallel implementations)
- [ ] Fix ScopeDetector keyword matching to use word boundaries (like Epic 1 does)
- [ ] Address unused `reviewOutput` variable in QuickPipeline

---

## Epic 3: Creative Studio Plugins (feature/creative-studio-plugins)

### What it delivers

Plugin system foundation: `PluginManifest` with semantic versioning, certification levels, and dependency declarations; thread-safe `PluginRegistry` actor with command-to-plugin indexing and directory discovery; CLI for list/install/uninstall/verify.

### Files + LOC

| File | LOC | Role |
|------|-----|------|
| `ShikkiKit/Plugins/PluginManifest.swift` | 374 | Manifest model + validation + semver + certification |
| `ShikkiKit/Plugins/PluginRegistry.swift` | 235 | Actor registry with discovery + command index |
| `Commands/PluginsCommand.swift` | 263 | CLI: list, install, uninstall, verify subcommands |
| **Total source** | **872** | |
| **Tests** | **776** | PluginManifestTests (452) + PluginRegistryTests (324) |

### Key code excerpts

**Actor-based thread-safe registry** (PluginRegistry.swift:40-49):
```swift
public actor PluginRegistry {
    private let shikkiVersion: SemanticVersion
    private var plugins: [PluginID: PluginManifest] = [:]
    private var commandIndex: [String: PluginID] = [:]
    // ...
}
```

**PluginManifest validation** (PluginManifest.swift:356-363):
```swift
public func validate() throws {
    if id.rawValue.isEmpty { throw ValidationError.emptyID }
    if displayName.isEmpty { throw ValidationError.emptyDisplayName }
    if author.isEmpty { throw ValidationError.emptyAuthor }
    if entryPoint.isEmpty { throw ValidationError.emptyEntryPoint }
    if checksum.isEmpty { throw ValidationError.emptyChecksum }
    if commands.isEmpty { throw ValidationError.noCommands }
}
```

**Certification hierarchy** (PluginManifest.swift:184-204):
```swift
public enum CertificationLevel: String, Codable, Sendable, CaseIterable {
    case uncertified
    case communityReviewed
    case shikkiCertified
    case enterpriseSafe
}
extension CertificationLevel: Comparable { ... }
```

### @Ronin adversarial review

1. **Install copies plugin directory without checksum verification**: `InstallPlugin.run()` (PluginsCommand.swift:116-129) loads the manifest, copies the directory to `~/.shikki/plugins/`, then registers. It never calls `verifyChecksum`. A tampered plugin directory would be installed. **IMPORTANT** -- the verify command exists but is not wired into install flow.

2. **Uninstall path construction mismatch risk**: Install uses `manifest.id.rawValue.replacingOccurrences(of: "/", with: "-")` for the directory name (line 120-121). Uninstall uses `pluginID.replacingOccurrences(of: "/", with: "-")` (line 181). These should match since `pluginID` is the raw string, but if someone passes a variant (e.g., with extra whitespace), the directory won't be found. The uninstall still removes from registry, creating a ghost state.

3. **No signature verification**: `PluginCertification.signature` is stored but never validated. The `verifyChecksum` method (line 371-373) only does string equality, not cryptographic verification. The field exists for future use but could give false security confidence.

4. **Plugin directory structure allows arbitrary file copy**: `fm.copyItem(atPath: source, toPath: destDir)` copies the entire source directory into `~/.shikki/plugins/`. If the plugin directory contains symlinks pointing outside, it could place files anywhere. **Medium risk** in local-path install.

5. **Race condition in PluginsCommand.InstallPlugin**: The method creates a new `PluginRegistry()` instance, loads the manifest, copies files, then registers. If two installs run concurrently, the actor serialization only protects the in-memory registry, not the file system copy.

### @Metsuke quality inspection

1. **Test coverage: EXCELLENT**. 776 test LOC for 872 source LOC (89% ratio). PluginManifestTests covers validation edge cases, JSON round-trips, semver ordering. PluginRegistryTests covers register/unregister/discover/command resolution/conflict detection.

2. **Sendable conformance: EXEMPLARY**. `PluginRegistry` is an `actor` (compiler-enforced). All models are `Sendable`, `Codable`, `Hashable`. `PluginSource` has manual `Codable` for associated values -- clean.

3. **No circular dependencies**: Plugins/ directory depends only on Foundation. Clean module boundary.

4. **`PluginManifest.validate()` does not validate `id` format**: Only checks `isEmpty`. A plugin ID like `../../../etc` would pass validation. Should enforce format (e.g., `org/name` pattern).

5. **`VerifyPlugin` hardcodes version**: Line 257 uses `SemanticVersion(major: 0, minor: 3, patch: 0)` instead of reading from the registry's `shikkiVersion`. Minor inconsistency.

### Verdict: SHIP WITH FIX

**Must fix:**
- [ ] Wire checksum verification into install flow (currently only available as separate command)

**Should fix (next iteration):**
- [ ] Validate plugin ID format (org/name pattern, no path traversal characters)
- [ ] Add symlink check in plugin directory copy
- [ ] Use registry's shikkiVersion in verify command instead of hardcoded value

---

## Cross-Epic Issues

### 1. Duplicate type names

**No compile-time conflicts.** The potentially overlapping names are properly disambiguated:
- `ReviewFinding` (ReviewProvider.swift) vs `PRReviewFinding` (ReviewService.swift) -- different types, explicit PR prefix
- `ReviewResult` (ReviewProvider.swift) vs `PRReviewResult` (ReviewService.swift) -- same pattern
- `ReviewProvider` (protocol, PrePRGates) vs `ReviewAnalysisProvider` (protocol, ReviewService) -- different names

### 2. ShikkiCommand.swift subcommands registration

All 3 epics registered correctly:
- `PluginsCommand.self` -- line 38 (Epic 3)
- `QuickCommand.self` -- line 40 (Epic 2)
- `ReviewCommand.self` -- line 42 (Epic 2)
- `FastCommand.self` -- line 46 (Epic 2)
- `SpecMigrateCommand.self` -- line 55 (Epic 1)

`SpecListCommand`, `SpecReadCommand`, `SpecReviewCommand`, `SpecValidateCommand`, `SpecProgressCommand` are subcommands of `SpecCommand` (not direct ShikkiCommand subcommands). This is correct.

### 3. Compilation warnings

- **`reviewOutput` unused variable** in `QuickPipeline.swift:261` -- compiler will emit a warning. The value is assigned but never consumed after the self-review step.
- **`SpecFrontmatterService.countSections` incorrect filter** -- not a warning, but a bug (see Epic 1).

### 4. Architectural inconsistencies across epics

| Issue | Files | Impact |
|-------|-------|--------|
| 3x `countSections` implementations | SpecFrontmatterParser, SpecFrontmatterService, SpecMigrationService | Maintenance burden, one has a bug |
| 2x YAML parsers | SpecFrontmatterParser, SpecFrontmatterService | ~900 LOC doing the same thing differently |
| 2x pre-PR gate systems | PrePRGates.swift, ReviewCommand.runPrePR() | Drift risk -- fixes in one not applied to other |
| Word boundary matching inconsistency | SpecMigrationService uses it, ScopeDetector does not | ScopeDetector has false positives for "and", "all" |
| Hardcoded model string | ReviewCommand.ClaudeAgentReviewProvider | Violates provider-agnostic principle |

### 5. Shared infrastructure

All three epics properly depend on existing ShikkiKit types:
- `ShipGate` / `ShipContext` / `ShipService` -- used by PrePRGates and FastPipeline
- `AgentProviding` / `ClaudeAgentProvider` -- used by QuickPipeline and FastPipeline (defined in SpecPipeline.swift)
- `EmojiRouter` / `EmojiRenderer` -- used by ShikkiCommand (pre-existing)

---

## Summary Table

| Epic | Source LOC | Test LOC | Test Ratio | New Types | Verdict |
|------|-----------|----------|------------|-----------|---------|
| 1. Spec Metadata | 2,592 | 1,593 | 61% | 12 | SHIP WITH FIX |
| 2. Commands Architecture | 2,378 | 1,423 | 60% | 22 | SHIP WITH FIX |
| 3. Creative Studio Plugins | 872 | 776 | 89% | 14 | SHIP WITH FIX |
| **Combined** | **5,842** | **3,792** | **65%** | **48** | **SHIP WITH FIX** |

## Must-Fix Items (blocking release)

| # | Epic | Issue | File | Line |
|---|------|-------|------|------|
| 1 | E1 | `countSections` counts `###` headings as `##` | SpecFrontmatterService.swift | 33 |
| 2 | E1 | YAML serialization does not escape `"` in title | SpecFrontmatterService.swift | 344 |
| 3 | E2 | `testsAllPassed = true` hardcoded | FastPipeline.swift | 172 |
| 4 | E2 | Hardcoded model `claude-sonnet-4-20250514` | ReviewCommand.swift | 350 |
| 5 | E3 | Install does not verify checksum | PluginsCommand.swift | 116 |

## Should-Fix Items (next iteration)

| # | Epic | Issue |
|---|------|-------|
| 1 | E1 | Consolidate 3x `countSections` into shared utility |
| 2 | E1 | Consolidate or delegate between two YAML parsers |
| 3 | E2 | Unify ReviewCommand.runPrePR with PrePRGates system |
| 4 | E2 | ScopeDetector keyword matching needs word boundaries |
| 5 | E2 | Remove unused `reviewOutput` variable |
| 6 | E3 | Validate plugin ID format (prevent path traversal) |
| 7 | E3 | Add symlink safety check on plugin install |
| 8 | Cross | Standardize word-boundary matching pattern across epics |

---

*Review generated by @Ronin (adversarial) + @Metsuke (quality) on 2026-04-01.*
