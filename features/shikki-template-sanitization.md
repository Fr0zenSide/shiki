# Feature: Template Path Sanitization
> Created: 2026-03-30 | Status: Phase 5b — Implementation Ready | Owner: @Daimyo

## Context

The `TemplateRegistry.apply()` method takes a `templateId` and a target `path`, then iterates over the template's `TemplateFile` entries and writes each `file.relativePath` to disk. The current implementation blindly joins `path` + `file.relativePath` using `NSString.appendingPathComponent` — no validation is performed on the relative path.

**Current code** (`TemplateRegistry.swift`, line 213):
```swift
let filePath = (path as NSString).appendingPathComponent(file.relativePath)
```

A template installed from `github` source (or a compromised local template) can include a `TemplateFile` with `relativePath: "../../.ssh/authorized_keys"` or `relativePath: "../../../etc/cron.d/backdoor"`. The path traversal escapes the target project directory and writes arbitrary files to the filesystem.

Additionally, the `executable` flag on `TemplateFile` is honored silently — `chmod 755` is applied with no user confirmation. A template could install an executable script at a hidden path.

**Current code**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift` (458 lines)
**Current tests**: `projects/shikki/Tests/ShikkiKitTests/TemplateRegistryTests.swift` (410 lines, 24 tests)

## Problem

Template `apply()` is the only operation that writes to the user's project directory based on external input (templates from GitHub). Without path sanitization, it is a directory traversal vulnerability. Without executable file controls, it is a privilege escalation vector. Both are P0 because the template marketplace is designed to accept community-contributed templates.

## Synthesis

**Goal**: Make `apply()` safe against path traversal, symlink attacks, and unauthorized executable file creation.

**Scope**:
- Reject `relativePath` containing `..` path components
- Validate resolved path stays within target directory after symlink resolution
- Warn on executable permissions; require `--allow-exec` flag
- Ensure `force` flag only controls file overwrite, never bypasses path validation

**Out of scope**:
- Template content scanning (malicious Swift code inside templates — that is a runtime concern)
- Template signature verification (would require a PKI; backlogged)
- Changes to `TemplateFile` struct itself (we validate at `apply()` time, not at definition time)
- Changes to `install()` validation (paths are only dangerous at `apply()` time)

**Success criteria**:
- `apply()` with `../../etc/passwd` relative path throws `RegistryError.pathTraversal`
- `apply()` with symlink-based traversal throws `RegistryError.pathTraversal`
- `apply()` with executable files without `--allow-exec` throws `RegistryError.executableNotAllowed`
- `apply()` with executable files and `--allow-exec` succeeds with warning logged
- `force: true` does NOT bypass any path validation
- All 24 existing tests continue to pass

**Dependencies**: None — pure validation logic added to existing method.

## Business Rules

```
BR-01: apply() MUST reject any relativePath containing ".." as a path component (e.g., "../foo", "a/../../b", "..") — throw RegistryError.pathTraversal
BR-02: After path resolution, the canonical (symlink-resolved) absolute path MUST have the target directory as a prefix — throw RegistryError.pathTraversal if not
BR-03: If any TemplateFile has executable == true, log a warning with the file path
BR-04: If any TemplateFile has executable == true and allowExecutables is false (default), throw RegistryError.executableNotAllowed — require explicit --allow-exec opt-in
BR-05: The force flag ONLY controls whether existing files are overwritten — it MUST NOT bypass path validation (BR-01, BR-02) or executable validation (BR-04)
```

## Test Plan

### Scenario 1: Normal apply — valid paths work correctly
```
Setup:   Template with files: ["Sources/Foo.swift", "Tests/FooTests.swift", "Package.swift"]
         Target: /tmp/my-project/
BR-01 → No ".." in any path — validation passes
BR-02 → All resolved paths start with /tmp/my-project/ — validation passes
Result:  3 files created, returned in created list
Verify:  Files exist at expected paths with correct content
```

### Scenario 2: Path traversal rejected — ".." component
```
Setup:   Template with files: ["../../etc/passwd", "Sources/ok.swift"]
         Target: /tmp/my-project/
BR-01 → "../../etc/passwd" contains ".." → RegistryError.pathTraversal thrown
Result:  Error thrown BEFORE any file is written (including ok.swift)
Verify:  /tmp/my-project/Sources/ok.swift does NOT exist; /etc/passwd unchanged
```

### Scenario 3: Executable warning + rejection without flag
```
Setup:   Template with files: [TemplateFile("setup.sh", content: "#!/bin/bash", executable: true)]
         Target: /tmp/my-project/, allowExecutables: false (default)
BR-03 → Warning logged for setup.sh
BR-04 → executable == true && !allowExecutables → RegistryError.executableNotAllowed thrown
Result:  Error thrown, no files written
Verify:  /tmp/my-project/setup.sh does NOT exist
```

### Scenario 4: Executable accepted with --allow-exec flag
```
Setup:   Template with files: [TemplateFile("setup.sh", content: "#!/bin/bash", executable: true)]
         Target: /tmp/my-project/, allowExecutables: true
BR-03 → Warning logged for setup.sh
BR-04 → allowExecutables == true → proceeds
Result:  setup.sh created with 0o755 permissions
Verify:  File exists, permissions are 755, content matches
```

### Scenario 5: Symlink attack rejected
```
Setup:   Create symlink: /tmp/my-project/escape → /tmp/outside/
         Template with files: ["escape/payload.txt"]
         Target: /tmp/my-project/
BR-01 → No ".." — passes first check
BR-02 → Resolved path: /tmp/outside/payload.txt — does NOT start with /tmp/my-project/ → RegistryError.pathTraversal
Result:  Error thrown, no files written
Verify:  /tmp/outside/payload.txt does NOT exist
```

### Scenario 6: Force flag does not bypass validation
```
Setup:   Template with files: ["../../etc/passwd"]
         Target: /tmp/my-project/, force: true
BR-05 → force == true, but path contains ".." → BR-01 still triggers
Result:  RegistryError.pathTraversal thrown despite force == true
Verify:  No files written
```

### Scenario 7: Multiple traversal patterns rejected
```
Setup:   Test each variant:
         - "a/../../../etc/passwd" (embedded traversal)
         - ".." (bare parent)
         - "a/b/../../.." (multiple levels)
         - "./../../etc" (dot-slash then traversal)
BR-01 → All contain ".." component → all rejected
Result:  RegistryError.pathTraversal for each
```

## Architecture

### Files to Modify

| File | Modification | BRs |
|------|-------------|-----|
| `TemplateRegistry.swift` | Add `RegistryError.pathTraversal(String)` and `RegistryError.executableNotAllowed(String)` cases | BR-01, BR-02, BR-04 |
| `TemplateRegistry.swift` | Add `validateRelativePath(_:targetDir:)` private method | BR-01, BR-02 |
| `TemplateRegistry.swift` | Add `checkExecutableFiles(_:allowExecutables:)` private method | BR-03, BR-04 |
| `TemplateRegistry.swift` | Modify `apply()` signature to add `allowExecutables: Bool = false` parameter | BR-04 |
| `TemplateRegistry.swift` | Insert validation calls at the top of `apply()`, before any file I/O | BR-01, BR-02, BR-03, BR-04, BR-05 |
| `TemplateRegistryTests.swift` | Add 7 new test methods matching scenarios 1-7 | All BRs |

### Key Code Changes

**New error cases** (add to `RegistryError`):
```swift
public enum RegistryError: Error, Sendable, Equatable {
    case templateNotFound(String)
    case templateAlreadyInstalled(String)
    case invalidTemplate(String)
    case installFailed(String)
    case registryCorrupted
    case pathTraversal(String)          // NEW — BR-01, BR-02
    case executableNotAllowed(String)   // NEW — BR-04
}
```

**New `apply()` signature**:
```swift
public func apply(
    templateId: String,
    to path: String,
    force: Bool = false,
    allowExecutables: Bool = false  // NEW — BR-04
) throws -> [String]
```

**Before** (`apply()` body, lines 205-238):
```swift
public func apply(templateId: String, to path: String, force: Bool = false) throws -> [String] {
    let entry = try get(id: templateId)
    let template = entry.template
    var created: [String] = []

    for file in template.files {
        let filePath = (path as NSString).appendingPathComponent(file.relativePath)
        // ... no validation ...
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        if file.executable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: filePath)
        }
        created.append(file.relativePath)
    }
    return created
}
```

**After**:
```swift
public func apply(
    templateId: String,
    to path: String,
    force: Bool = false,
    allowExecutables: Bool = false
) throws -> [String] {
    let entry = try get(id: templateId)
    let template = entry.template

    // BR-04, BR-03: Check executable files BEFORE any I/O
    let execFiles = template.files.filter(\.executable)
    if !execFiles.isEmpty {
        for execFile in execFiles {
            // BR-03: Always warn
            AppLog.warning("Template file has executable permissions: \(execFile.relativePath)")
        }
        if !allowExecutables {
            // BR-04: Reject unless opted in
            let names = execFiles.map(\.relativePath).joined(separator: ", ")
            throw RegistryError.executableNotAllowed(names)
        }
    }

    // BR-01, BR-02: Validate ALL paths BEFORE writing ANY file
    let canonicalTarget = try resolveCanonicalPath(path)
    for file in template.files {
        try validateRelativePath(file.relativePath, targetDir: canonicalTarget)
    }

    // All validations passed — now write files
    var created: [String] = []
    for file in template.files {
        let filePath = (path as NSString).appendingPathComponent(file.relativePath)
        let dir = (filePath as NSString).deletingLastPathComponent

        if !fileManager.fileExists(atPath: dir) {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // BR-05: force only controls overwrite, not validation
        if fileManager.fileExists(atPath: filePath) && !force {
            continue
        }

        let content = substituteVariables(file.content, projectName: URL(fileURLWithPath: path).lastPathComponent)
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        if file.executable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: filePath)
        }

        created.append(file.relativePath)
    }
    return created
}
```

**New validation methods**:
```swift
/// BR-01: Reject paths containing ".." components.
private func validateRelativePath(_ relativePath: String, targetDir: String) throws {
    // Split into components and check for ".."
    let components = relativePath.split(separator: "/").map(String.init)
    if components.contains("..") {
        throw RegistryError.pathTraversal(relativePath)
    }

    // BR-02: Resolve and verify containment
    let joined = (targetDir as NSString).appendingPathComponent(relativePath)
    let resolved = try resolveCanonicalPath(joined)
    guard resolved.hasPrefix(targetDir) else {
        throw RegistryError.pathTraversal(relativePath)
    }
}

/// Resolve symlinks to get canonical path. Falls back to standardized path if file doesn't exist yet.
private func resolveCanonicalPath(_ path: String) throws -> String {
    if fileManager.fileExists(atPath: path) {
        // Resolve symlinks for existing paths
        return (path as NSString).resolvingSymlinksInPath
    }
    // For non-existent paths, resolve the deepest existing ancestor
    var current = path
    while !fileManager.fileExists(atPath: current) {
        let parent = (current as NSString).deletingLastPathComponent
        if parent == current { break } // reached root
        current = parent
    }
    let resolvedBase = (current as NSString).resolvingSymlinksInPath
    let remainder = String(path.dropFirst(current.count))
    return resolvedBase + remainder
}
```

## Execution Plan

### Task 1: Add new error cases to RegistryError
- **Files**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
- **Implement**: Add `pathTraversal(String)` and `executableNotAllowed(String)` to the `RegistryError` enum.
- **Verify**: `swift build` — no compile errors; existing tests still pass (enum gains cases but is never exhaustively matched in tests).
- **BRs**: BR-01, BR-02, BR-04
- **Time**: ~1 min

### Task 2: Add path validation method
- **Files**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
- **Implement**: Add `validateRelativePath(_:targetDir:)` and `resolveCanonicalPath(_:)` as private methods. The first checks for `..` components and verifies resolved-path containment. The second handles symlink resolution with fallback for non-existent paths.
- **Verify**: Unit tests for `..` rejection and symlink detection.
- **BRs**: BR-01, BR-02
- **Time**: ~8 min

### Task 3: Add executable file validation method
- **Files**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
- **Implement**: Executable check logic at the top of `apply()` — iterate `template.files`, warn for each executable, throw if `!allowExecutables`.
- **Verify**: Unit test — template with `.sh` file and `allowExecutables: false` throws.
- **BRs**: BR-03, BR-04
- **Time**: ~5 min

### Task 4: Modify apply() with new parameter and validation calls
- **Files**: `projects/shikki/Sources/ShikkiKit/Services/TemplateRegistry.swift`
- **Implement**: Add `allowExecutables: Bool = false` parameter. Insert path validation loop and executable check BEFORE the file-writing loop. The `force` flag only controls the `fileManager.fileExists` skip — it never bypasses validation.
- **Verify**: Existing `apply` tests pass (new param has default `false`, existing templates have no executable files). New tests verify force + traversal still throws.
- **BRs**: BR-01, BR-02, BR-03, BR-04, BR-05
- **Time**: ~5 min

### Task 5: Write test scenarios 1-7
- **Files**: `projects/shikki/Tests/ShikkiKitTests/TemplateRegistryTests.swift`
- **Implement**: Add 7 new test methods under a `// MARK: - Path Sanitization` section. Scenario 5 (symlink) creates a real symlink in `/tmp`, validates rejection, and cleans up. Scenario 7 uses parameterized test data for multiple traversal patterns.
- **Verify**: `swift test --filter TemplateRegistryTests` — all 31 tests pass (24 existing + 7 new).
- **BRs**: All
- **Time**: ~15 min

### Task 6: Verify no downstream breakage
- **Files**: None (verification only)
- **Implement**: Search codebase for all call sites of `apply(templateId:to:force:)` and verify they compile with the new optional parameter.
- **Verify**: `swift build` on full project — no errors.
- **BRs**: BR-05 (ensures default behavior preserved)
- **Time**: ~2 min

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 5/5 BRs mapped to tasks (Task 1→BR-01/02/04 types, Task 2→BR-01/02, Task 3→BR-03/04, Task 4→all, Task 5→all tests) |
| Test Coverage | PASS | 7/7 scenarios mapped to Task 5 |
| File Alignment | PASS | 2 files: `TemplateRegistry.swift` (source) + `TemplateRegistryTests.swift` (tests) |
| Task Dependencies | PASS | Task 1 first (error types), Tasks 2-3 next (validation methods), Task 4 (wire up), Task 5 (tests), Task 6 (verify) |
| Task Granularity | PASS | All tasks 1-15 min |
| Testability | PASS | Each task has a verify step; scenarios use real filesystem in /tmp |
| API Compatibility | PASS | `apply()` adds optional `allowExecutables` with default `false` — no breaking change |
| Existing Tests | PASS | All 24 existing tests unaffected (no templates use `executable: true`, new param defaults to `false`) |
| Security Completeness | PASS | Path traversal (BR-01), symlink escape (BR-02), executable injection (BR-03/04), force bypass (BR-05) — all vectors covered |

**Verdict: PASS** — ready for Phase 6.

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-30 | Phase 1-5b | @Daimyo | APPROVED | Spec from security walkthrough |

---

### @shi mini-challenge
1. **@Katana**: The `resolveCanonicalPath` falls back to resolving the deepest existing ancestor for non-existent paths. Could a TOCTOU race (symlink created between validation and write) still bypass BR-02? Should we re-validate after `createDirectory`?
2. **@Ronin**: `RegistryError.pathTraversal` exposes the offending `relativePath` in the error. Could this leak information about the filesystem structure to a malicious template author who receives error feedback? Should we redact it?
3. **@Sensei**: The executable check is all-or-nothing (`allowExecutables` for the entire template). Should we support per-file approval, or is the granularity sufficient for v1 given that templates are a curated unit?
