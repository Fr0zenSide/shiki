# Code Review: Quality Hardening Commit 708ce530

**Branch**: `fix/quality-hardening-2026-04-02`
**Parent**: `6de8b292` (spec(plugins): marketplace architecture + plugin docs + dashboard radar)
**Reviewers**: @Ronin (adversarial/security) + @Metsuke (quality inspector)
**Date**: 2026-04-02

---

## 1. Commit Summary

**Title**: `fix: quality hardening -- 17 review items + 9 improvements + P0 specs + tmux checkpoint`

**Delta**: +3932 / -133 lines across 29 files

| Category | Files | Lines Added |
|----------|-------|-------------|
| Feature specs (new) | 7 | ~2647 |
| Swift source changes | 12 | ~650 |
| Swift test changes | 1 | ~12 (test fixture updates) |
| Reports (new + updated) | 3 | ~613 |
| Docs (fixes) | 3 | ~22 |
| Shell script (new) | 1 | 176 |

**What changed**:
- 5 must-fix items from post-merge review (countSections bug, YAML escaping, hardcoded values)
- 8 should-fix items (DRY consolidation, word boundary matching, pre-PR gate unification, plugin ID validation, symlink checks, parallel batch review)
- 9 additional improvements (multi-line annotations, shell injection fix, path traversal guards, YAML escape utility)
- 6 P0 specs for release blockers (FixEngine hardening, template sanitization, node security, plugin sandbox, Swift setup, spec tracking fields, DRY enforcement)
- tmux-checkpoint.sh for crash recovery
- Gap audit report (v0.3.0-pre)
- Ingest report (mewtru/physical character inspiration)

---

## 2. @Ronin Findings (Security/Adversarial)

### R-01: YAML Escape Incomplete -- Missing Newline Escape [IMPORTANT]

**File**: `SpecCommandUtilities.swift:71-75`

`escapeYAML()` escapes backslashes and double quotes but does NOT escape newline characters (`\n`). A title or author field containing a literal newline would break YAML parsing when serialized into a double-quoted string. YAML spec requires `\n` to be escaped as `\\n` in double-quoted scalars.

```swift
public static func escapeYAML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        // MISSING: .replacingOccurrences(of: "\n", with: "\\n")
        // MISSING: .replacingOccurrences(of: "\t", with: "\\t")
}
```

**Risk**: Corrupted YAML frontmatter in specs with multi-line metadata values. Low likelihood in practice (titles rarely have newlines) but the function claims to be a general YAML escaper, so it should handle all special characters.

**Fix**: Add newline and tab escaping after backslash escaping.

---

### R-02: XcodeGen project.yml -- YAML Injection via Project Name [IMPORTANT]

**File**: `ProjectInitWizard.swift:259-300`

`generateXcodeGenYml(projectName:)` interpolates `projectName` directly into YAML without any escaping:

```swift
static func generateXcodeGenYml(projectName: String) -> String {
    """
    name: \(projectName)
    ...
    PRODUCT_BUNDLE_IDENTIFIER: one.obyw.\(projectName.lowercased())
    ...
    """
}
```

A project name containing YAML special characters (e.g., `my: project`, `my\nname`, or `my"project`) would produce invalid or attacker-controlled YAML. The `projectName` comes from `detected.name` which is derived from the directory name -- user-controlled input.

**Risk**: Malformed project.yml at worst. In a supply-chain scenario where someone provides a template that triggers `shikki init` in a crafted directory name, it could inject arbitrary YAML keys. LOW real-world risk because `detected.name` is typically a filesystem directory name, but violates defense-in-depth.

**Fix**: Quote `projectName` in the `name:` field (`name: "\(SpecCommandUtilities.escapeYAML(projectName))"`) and sanitize for bundle identifier (strip non-alphanumeric from `projectName.lowercased()`).

---

### R-03: MCP Config Hardcodes External URL [LOW]

**File**: `ProjectInitWizard.swift:243-256`

The `iosMCPConfig` hardcodes `https://sosumi.ai/mcp` as an MCP server via `npx -y mcp-remote`. This is a third-party URL that:
1. Runs arbitrary code via `npx -y` (auto-installs from npm without confirmation)
2. Connects to a third-party MCP endpoint the user may not have approved
3. Is baked into every iOS project scaffold without user consent

**Risk**: Supply-chain risk if `sosumi.ai` is compromised or `mcp-remote` npm package is hijacked. The `npx -y` flag auto-installs without prompting.

**Recommendation**: This should be opt-in, not default. At minimum, add a comment in the generated `.mcp.json` that the user should review external MCP servers. Better: only include `xcode-tools` by default and let the user add `sosumi` manually.

---

### R-04: tmux-checkpoint.sh -- Python Injection in list_history [LOW]

**File**: `scripts/tmux-checkpoint.sh:143-148`

The `list_history` function passes the file path `$f` directly into an inline Python string via shell interpolation:

```bash
python3 -c "
import json
cp = json.load(open('$f'))
print(f\"  $(basename $f) -- {len(cp['windows'])} windows @ {cp['timestamp']}\")
"
```

If a checkpoint filename contained a single quote (unlikely given the `checkpoint-YYYYMMDD-HHMMSS.json` format), it would break the Python `open()` call or allow Python code injection. The filenames are generated by the script itself so this is controlled input, but the pattern is fragile.

**Risk**: Very low -- filenames are self-generated. But the same `$CHECKPOINT_FILE` variable is used in `status()` with the same pattern, and that path comes from a fixed `$HOME` construction.

**Fix**: Pass file paths as arguments to Python rather than interpolating into Python source: `python3 -c "..." "$f"` and use `sys.argv[1]` inside.

---

### R-05: SlopScanGate Path Traversal -- `URL.standardized` Is Not Symlink-Aware [IMPORTANT]

**File**: `PrePRGates.swift:122-128`

The new path traversal check uses `URL.standardized` which resolves `.` and `..` but does NOT resolve symlinks:

```swift
guard !file.contains("..") else { continue }
let fullPath = "\(rootPath)/\(file)"
let resolved = URL(fileURLWithPath: fullPath).standardized.path
guard resolved.hasPrefix(rootPath) else { continue }
```

A git diff could return a path like `Sources/symlink-to-outside/secret.swift` where `symlink-to-outside` is a symlink pointing outside the project root. The `.standardized` path would still start with `rootPath` because it does not resolve symlinks, but `cat` would follow the symlink and read outside the project.

**Risk**: Medium. Requires a malicious symlink already committed in the repo. The `git diff` output is trusted because it comes from git itself, but the subsequent `cat` follows symlinks.

**Fix**: Use `URL(fileURLWithPath: fullPath).resolvingSymlinksInPath().path` instead of `.standardized.path`, or use `realpath()` / `FileManager.default.attributesOfItem` to check for symlinks.

---

### R-06: Plugin Symlink Check Does Not Cover Nested Symlinks [LOW]

**File**: `PluginsCommand.swift:141-150`

The symlink safety check before plugin install iterates the source directory and rejects symlinks:

```swift
if let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
    while let fileURL = enumerator.nextObject() as? URL {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            print("...")
            throw ExitCode(1)
        }
    }
}
```

Good addition. However, the `fm.copyItem(atPath:toPath:)` call on line 153 (after the check) follows symlinks by default on macOS. There is a TOCTOU race where a symlink could be created between the check and the copy. Very unlikely in practice since these are local files, but worth noting.

**Risk**: Very low TOCTOU window. Non-exploitable in normal operation.

---

### R-07: ReviewPersistence resolveBaseDirectory -- Unbounded Traversal [LOW]

**File**: `ReviewService.swift:233-243`

`resolveBaseDirectory()` walks up from `cwd` to `/` looking for `.shikki/`. This is safe but worth noting: if the user runs `shikki` from `/tmp` or their home directory without a `.shikki/` folder anywhere in the path, it falls back to `cwd/.shikki/reviews`. This could create review state in unexpected locations.

**Risk**: Low. Functional rather than security concern. The fallback behavior is clearly documented.

---

## 3. @Metsuke Findings (Quality)

### M-01: Three Specs Missing YAML Frontmatter [IMPORTANT]

Of the 7 new specs:
- `shikki-dry-enforcement.md` -- HAS frontmatter (title, status, priority, project, created, authors, tags)
- `shikki-setup-swift.md` -- HAS frontmatter
- `shikki-spec-tracking-fields.md` -- HAS frontmatter (most complete -- includes depends-on, relates-to)
- **`shikki-fixengine-hardening.md`** -- NO frontmatter (starts with `# Feature:`)
- **`shikki-node-security.md`** -- NO frontmatter
- **`shikki-plugin-sandbox.md`** -- NO frontmatter
- **`shikki-template-sanitization.md`** -- NO frontmatter

The Spec Metadata v2 system requires YAML frontmatter for `SpecFrontmatterParser` to process specs. Four of seven new specs bypass this system entirely. This is inconsistent with the project's own spec standard and the `shikki-spec-metadata-v2.md` spec that was updated in this very commit.

**Fix**: Add frontmatter blocks to all four specs. At minimum: `title`, `status`, `priority`, `project`, `created`.

---

### M-02: countSections -- Different Behavior Between Original and Consolidated [LOW]

**File**: `SpecCommandUtilities.swift:63-67` vs the old `SpecFrontmatterParser.countSections` (removed)

The old `SpecFrontmatterParser.countSections` trimmed whitespace before checking:
```swift
let trimmed = line.trimmingCharacters(in: .whitespaces)
return trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ")
```

The new consolidated version does NOT trim:
```swift
content.components(separatedBy: "\n")
    .filter { $0.hasPrefix("## ") && !$0.hasPrefix("### ") }
    .count
```

This means indented `##` headings (e.g., inside code blocks with leading spaces) would have been counted by the old implementation but are now skipped. This is arguably BETTER behavior (indented headings in markdown are typically inside code blocks and should not count), but it is a subtle behavioral change.

**Risk**: Low. The new behavior is more correct.

---

### M-03: No New Test Cases for Any Code Change [IMPORTANT]

The commit modifies 12 Swift source files and adds significant new logic:
- Plugin ID validation regex (`PluginManifest.swift`)
- Symlink detection on install (`PluginsCommand.swift`)
- Path traversal guard (`PrePRGates.swift`)
- Multi-line comment parsing (`SpecAnnotationParser.swift`)
- YAML escaping utility (`SpecCommandUtilities.swift`)
- Word boundary matching (`QuickPipeline.swift`)
- Parallel batch review (`ReviewService.swift`)
- iOS scaffolding + git hooks (`ProjectInitWizard.swift`)
- Pre-PR gate delegation (`ReviewCommand.swift`)

The only test file changes are fixture updates (`ProjectInitWizardTests.swift` -- adding `.git/hooks` directory to existing test setups). Zero new test cases were added for any of the new logic.

The commit message claims "2096/2096 tests green" but this means existing tests pass -- not that the new code is tested.

**Specific gaps**:
1. `escapeYAML()` -- no tests for backslash escaping, quote escaping, empty strings, or edge cases
2. `containsWord()` -- no tests for word boundary detection (the core reason for the change)
3. Plugin ID validation -- no tests for `..` rejection, `/`-prefix rejection, segment character validation
4. Symlink detection on install -- no test
5. `extractMultilineContent()` and multi-line annotation parsing -- no tests
6. Path traversal guard in `SlopScanGate` -- no test
7. `resolveBaseDirectory()` walk-up logic -- no test
8. Parallel `reviewBatch` -- no test for ordering guarantee or error isolation
9. `scaffoldIOSProject` -- no test for `.mcp.json` content, `project.yml` generation, XcodeGen detection
10. `installGitHooks` -- no test for existing hook detection, content verification

**Severity**: IMPORTANT. This is a quality hardening commit with zero test additions. The TDDP standard says 80% coverage on core logic.

---

### M-04: Batch Review Silently Swallows Errors [IMPORTANT]

**File**: `ReviewService.swift:419-436`

The parallelized batch review catches all errors and returns `nil`:

```swift
group.addTask {
    do {
        return try await self.review(prNumber: number, dryRun: dryRun)
    } catch {
        return nil  // Error silently dropped
    }
}
```

The old sequential version logged the error:
```swift
logger.error("Review failed for PR", metadata: ["pr": "\(number)", "error": "\(error)"])
```

The new parallel version removes the logging entirely. A failing PR review disappears silently from the batch results with no trace.

**Fix**: Re-add the `logger.error` call inside the catch block before returning `nil`.

---

### M-05: Dead `reviewBaseDir` Code Duplication [LOW]

**File**: `ReviewCommand.swift:233-239`

The `reviewBaseDir()` private method in `ReviewCommand` contains the exact same walk-up-to-find-`.shikki/` logic as the new `ReviewPersistence.resolveBaseDirectory()`. This is the same DRY violation that this commit is ostensibly fixing.

```swift
// ReviewCommand.swift:233
private func reviewBaseDir() -> String {
    var dir = FileManager.default.currentDirectoryPath
    while dir != "/" {
        let shikkiDir = "\(dir)/.shikki"
        if FileManager.default.fileExists(atPath: shikkiDir) {
            return "\(shikkiDir)/reviews"
        }
```

This should delegate to `ReviewPersistence` instead of reimplementing the same logic.

---

### M-06: ProjectInitWizard Uses Blocking Process.run() [IMPORTANT]

**File**: `ProjectInitWizard.swift:210-237`

The `scaffoldIOSProject` method uses `Process()` synchronously:

```swift
let whichProcess = Process()
// ...
try? whichProcess.run()
whichProcess.waitUntilExit()  // BLOCKING

let genProcess = Process()
// ...
try? genProcess.run()
genProcess.waitUntilExit()  // BLOCKING
```

In a Sendable struct, calling blocking `waitUntilExit()` can block the caller's thread. This is not an async method so there is no structured concurrency violation, but it can freeze the CLI for the duration of `xcodegen generate` (which can take 5-10 seconds on large projects).

**Risk**: UX issue -- CLI hangs during project init with no feedback. Not a correctness bug.

**Recommendation**: Either make the method async or add a progress indicator.

---

### M-07: iosMCPConfig and gitFlowPreCommitHook Have Leading Indentation [LOW]

**File**: `ProjectInitWizard.swift:243-256, 294-338`

Both static constants use `"""` multiline strings but include leading whitespace from the source indentation:

```swift
static let iosMCPConfig = """
    {
      "mcpServers": {
        ...
```

This produces a `.mcp.json` file with 4 spaces of leading indentation on every line, which is valid JSON but unusual and may confuse linters or users expecting standard formatting.

The `gitFlowPreCommitHook` has the same issue -- leading 4-space indentation on every line of the shell script.

**Fix**: Use `"""` with no indentation, or strip leading whitespace.

---

### M-08: Spec Quality -- Inconsistent Structure Across New Specs [LOW]

The 7 new specs have varying levels of completeness:

| Spec | Frontmatter | BRs | Test Plan | TDDP | Impl Waves | Readiness Gate |
|------|:-----------:|:---:|:---------:|:----:|:----------:|:--------------:|
| shikki-dry-enforcement.md | YES | YES (6) | YES (10) | YES (28) | YES (3) | Partial |
| shikki-fixengine-hardening.md | NO | YES (6) | YES (6) | NO | YES (8 tasks) | YES |
| shikki-node-security.md | NO | YES (10) | YES (8) | NO | YES (9 tasks) | YES |
| shikki-plugin-sandbox.md | NO | YES (10) | YES (10) | NO | YES (6 tasks) | YES |
| shikki-setup-swift.md | YES | YES (10) | YES (12) | YES (26) | YES (5) | YES |
| shikki-spec-tracking-fields.md | YES | YES (10) | NO | YES (18) | YES (5) | NO |
| shikki-template-sanitization.md | NO | YES (5) | YES (7) | NO | YES (6 tasks) | YES |

The specs with frontmatter (dry-enforcement, setup-swift, spec-tracking-fields) follow the project's standard spec template. The four without frontmatter use the older `# Feature:` / `> Created:` format. This inconsistency should be resolved.

---

### M-09: PluginManifest Validation Allows Underscore in ID But pluginDirectoryName Does Not Handle It [LOW]

**File**: `PluginManifest.swift:373` and `PluginsCommand.swift:521`

The validation allows underscores (`_`) in plugin IDs via the character set `CharacterSet(charactersIn: "-._")`:

```swift
let validPattern = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
```

But `pluginDirectoryName` only handles `/`:

```swift
static func pluginDirectoryName(for id: String) -> String {
    id.replacingOccurrences(of: "/", with: "-")
        .trimmingCharacters(in: .whitespaces)
}
```

This is fine -- underscores are valid filesystem characters. But worth noting that dots in org names (e.g., `com.acme/plugin`) produce directory names like `com.acme-plugin`, which is valid but could be confusing.

---

### M-10: Spec Tracking Fields Spec Has No Standalone Test Plan Section [LOW]

**File**: `features/shikki-spec-tracking-fields.md`

Unlike the other specs, `shikki-spec-tracking-fields.md` uses a numbered section structure (1-10) rather than the standard spec template sections. It has a TDDP section but no separate "## Test Plan" with scenario blocks. The TDDP tests are adequate but follow a different format (table vs scenario blocks).

The spec is well-structured overall with good business rules, architecture details, and clear fail-closed semantics. The format inconsistency is cosmetic.

---

## 4. Overall Verdict

**SHIP WITH FIX**

The commit delivers genuine quality improvements: DRY consolidation, security hardening (path traversal guards, plugin ID validation, symlink checks, shell injection removal), and well-structured P0 specs. The code changes are sound and the refactoring decisions are correct.

However, the complete absence of new tests for 12 files of new logic is the primary blocker for an unconditional SHIP. A "quality hardening" commit with zero test additions undermines the claim.

---

## 5. Required Fixes (before merge)

### Must-Fix (3)

| # | Finding | Fix | Effort |
|---|---------|-----|--------|
| 1 | **M-03**: Zero new tests for 12 files of new logic | Add tests for at minimum: `escapeYAML()`, `containsWord()`, Plugin ID validation, multi-line annotation parsing. These are the highest-risk new logic paths. | ~45 min |
| 2 | **M-04**: Batch review silently swallows errors | Re-add `logger.error()` in the catch block of the parallel batch review | ~2 min |
| 3 | **M-01**: 4 of 7 specs missing YAML frontmatter | Add `---` frontmatter blocks to fixengine-hardening, node-security, plugin-sandbox, template-sanitization | ~10 min |

### Should-Fix (5)

| # | Finding | Fix | Effort |
|---|---------|-----|--------|
| 4 | **R-01**: `escapeYAML` missing newline/tab escape | Add `.replacingOccurrences(of: "\n", with: "\\n")` and tab equivalent | ~2 min |
| 5 | **R-02**: XcodeGen YAML injection via project name | Quote and escape `projectName` in YAML output; sanitize for bundle identifier | ~5 min |
| 6 | **R-05**: SlopScanGate uses `.standardized` not `.resolvingSymlinksInPath()` | Replace `URL.standardized` with `URL.resolvingSymlinksInPath()` | ~2 min |
| 7 | **M-05**: `reviewBaseDir()` duplicates `resolveBaseDirectory()` | Delegate to `ReviewPersistence` | ~5 min |
| 8 | **M-07**: Multiline string literals have unwanted leading indentation | Strip indentation from `iosMCPConfig` and `gitFlowPreCommitHook` | ~5 min |

### Nice-to-Have (3)

| # | Finding | Fix |
|---|---------|-----|
| 9 | R-03 | Make `sosumi` MCP server opt-in rather than default |
| 10 | R-04 | Pass file paths as argv to inline Python in tmux-checkpoint.sh |
| 11 | M-06 | Add progress feedback during blocking `xcodegen generate` |

---

*Review generated by @Ronin (adversarial) + @Metsuke (quality) on 2026-04-02.*
*Commit: 708ce530d25c9bfc6ad879c1af1b65d2c4b0e156*
