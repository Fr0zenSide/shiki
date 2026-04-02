# Feature: Shikki Plugin/Template Sandbox Security
> Created: 2026-03-30 | Status: Phase 3 — Business Rules | Owner: @Daimyo

## Context

Plugins execute with the same privileges as ShikkiKit itself. `PluginRegistry` discovers plugins from `~/.shikki/plugins/`, validates their manifest structure (checksum, version compatibility, command conflicts), then hands them off for execution. But there is zero filesystem isolation — a plugin's `entryPoint` runs with full access to the user's home directory, environment variables, and ShikkiKit internals.

The `PluginManifest` already has a `CertificationLevel` enum (`uncertified`, `communityReviewed`, `shikkiCertified`, `enterpriseSafe`) but this is metadata-only — nothing enforces it at runtime. A `communityReviewed` plugin could still `rm -rf ~/` or read `~/.aws/credentials`.

Path traversal in template `apply()` is addressed by a separate spec (Spec 2). This spec covers the broader plugin execution model: filesystem sandboxing, secret protection, process isolation, and the additive-only constraint for user project files.

## Inspiration
### Diagnostic (2026-03-30)

Code audit of `PluginManifest.swift` and `PluginRegistry.swift`:

| # | Vulnerability | Source | Severity | Impact |
|---|--------------|--------|:--------:|:------:|
| 1 | Plugin `entryPoint` executes with host process privileges | @Katana | **Critical** | Full filesystem access, credential theft |
| 2 | No scoped data directory per plugin | @Katana | **Critical** | Plugins share global namespace, can read other plugins' data |
| 3 | Plugins can read `.env`, `~/.aws/**`, keychain data | @Katana | **Critical** | Secret exfiltration |
| 4 | No process isolation — plugin crash takes down ShikkiKit | @Sensei | **Blocking** | Single plugin failure = orchestrator death |
| 5 | No env var filtering — child processes inherit `SHIKKI_MESH_TOKEN`, DB credentials | @Katana | High | Mesh auth compromise via malicious plugin |
| 6 | `CertificationLevel.enterpriseSafe` is metadata-only — no runtime enforcement | @Ronin | High | False sense of security |
| 7 | Plugin can delete user project files (not additive-only) | @Ronin | High | Data loss via malicious or buggy plugin |
| 8 | `PluginManifest` has no `declaredPaths` field — no filesystem intent declaration | @Sensei | Medium | Cannot audit what a plugin plans to access |
| 9 | Plugin uninstall has no scoped cleanup — could leave files scattered | @Sensei | Medium | Disk pollution, orphaned state |

### Selected Ideas
All 9 vulnerabilities retained — they form a cohesive sandbox security layer.

## Synthesis

**Goal**: Ensure plugins operate in an isolated sandbox with explicit filesystem boundaries, no secret access, subprocess isolation, and additive-only constraints on user project files.

**Scope**:
- Each plugin gets a scoped data directory: `~/.shikki/plugins/<id>/data/`
- Filesystem access outside scope requires explicit user permission
- Secrets (`.env`, keychain, `~/.aws`, credentials files) are always blocked
- Plugin execution runs in a subprocess (`Process`) with sanitized env vars
- Plugin crash is caught and does not crash ShikkiKit
- Enterprise plugins must have `enterpriseSafe` certification to access project files
- Plugin manifest must declare all filesystem paths it intends to access
- Plugin uninstall removes only the plugin's scoped directory
- Additive-only: plugins cannot delete user project files

**Out of scope**:
- Network isolation (plugins can make HTTP requests — future spec)
- Resource limits (CPU/memory caps — OS-level, deferred)
- Signed plugin binaries (v0.4 — checksum verification already exists)
- Marketplace review pipeline (separate spec)

**Success criteria**:
- Plugin cannot read files outside its scoped directory without user approval
- Plugin cannot read any secret file (`.env`, `~/.aws/*`, keychain)
- Plugin cannot modify ShikkiKit source or binaries
- Plugin crash is logged and isolated — ShikkiKit continues running
- Plugin uninstall leaves zero files outside `~/.shikki/plugins/<id>/`
- Enterprise gate enforced at runtime, not just metadata

**Dependencies**:
- `PluginManifest.swift` (modify — add `declaredPaths`)
- `PluginRegistry.swift` (modify — add sandbox enforcement on execution)
- New `Plugins/PluginSandbox.swift` (sandbox enforcement)
- New `Plugins/PluginRunner.swift` (subprocess execution with isolation)

## Business Rules

```
BR-01: Plugins MUST operate within a scoped directory (~/.shikki/plugins/<id>/data/)
BR-02: Plugins MUST NOT access files outside their scope without explicit user permission
BR-03: Plugins MUST NOT access secrets (.env, keychain, credentials, ~/.aws)
BR-04: Plugins MUST NOT modify ShikkiKit source code or compiled binaries
BR-05: Plugin actions MUST be additive-only — no deletion of user project files
BR-06: Plugin manifest MUST declare all file system paths it accesses (declaredPaths field)
BR-07: Plugin execution MUST run in a subprocess with restricted environment (no inherited env vars with secrets)
BR-08: Enterprise plugins require `enterpriseSafe` certification before accessing any project files
BR-09: Plugin uninstall MUST remove ONLY the plugin's scoped directory
BR-10: Plugin crash MUST NOT crash ShikkiKit (isolation via Process, not in-process)
```

## Test Plan

### Scenario 1: Plugin reads within scoped directory (BR-01, BR-02)
```
GIVEN plugin "acme/analytics" is installed
AND   its scoped directory is ~/.shikki/plugins/acme-analytics/data/
WHEN  the plugin requests to read ~/.shikki/plugins/acme-analytics/data/cache.json
THEN  PluginSandbox allows the read
AND   the file contents are returned to the plugin
```

### Scenario 2: Plugin path traversal blocked (BR-02, BR-03)
```
GIVEN plugin "acme/analytics" with scope ~/.shikki/plugins/acme-analytics/data/
WHEN  the plugin requests to read ../../.env
THEN  PluginSandbox resolves the path to ~/.shikki/plugins/.env (outside scope)
AND   the request is DENIED
AND   a SecurityViolation event is logged with plugin ID + attempted path
AND   no file contents are returned
```

### Scenario 3: Secret file access always blocked (BR-03)
```
GIVEN plugin "acme/analytics" with declaredPaths: ["~/project/"]
AND   user has granted project file access
WHEN  the plugin requests to read ~/project/.env
THEN  PluginSandbox blocks the read (secret file pattern match)
AND   SecurityViolation logged

WHEN  the plugin requests to read ~/.aws/credentials
THEN  PluginSandbox blocks the read (secret directory pattern match)
AND   SecurityViolation logged

WHEN  the plugin requests to read ~/.config/shiki-notify/config
THEN  PluginSandbox blocks the read (credentials pattern match)
AND   SecurityViolation logged
```

### Scenario 4: ShikkiKit source/binary protection (BR-04)
```
GIVEN plugin "acme/analytics"
WHEN  the plugin requests to write to projects/shikki/Sources/ShikkiKit/anything.swift
THEN  PluginSandbox blocks the write
AND   SecurityViolation logged: "Plugin attempted to modify ShikkiKit source"

WHEN  the plugin requests to write to .build/debug/shikki
THEN  PluginSandbox blocks the write
AND   SecurityViolation logged: "Plugin attempted to modify compiled binary"
```

### Scenario 5: Additive-only constraint (BR-05)
```
GIVEN plugin "acme/formatter" with user-granted access to ~/project/src/
WHEN  the plugin requests to CREATE ~/project/src/generated/output.swift
THEN  PluginSandbox allows the write (additive)

WHEN  the plugin requests to DELETE ~/project/src/existing-file.swift
THEN  PluginSandbox blocks the operation
AND   SecurityViolation logged: "Plugin attempted to delete user project file"
AND   the file remains untouched

WHEN  the plugin requests to OVERWRITE ~/project/src/existing-file.swift
THEN  PluginSandbox blocks the operation (overwrite is destructive, not additive)
AND   SecurityViolation logged
```

### Scenario 6: Subprocess isolation with sanitized env (BR-07, BR-10)
```
GIVEN plugin "acme/analytics" with entryPoint "run.sh"
WHEN  PluginRunner launches the plugin
THEN  it spawns a new Process (not in-process execution)
AND   the subprocess does NOT inherit SHIKKI_MESH_TOKEN
AND   the subprocess does NOT inherit DATABASE_URL
AND   the subprocess does NOT inherit AWS_SECRET_ACCESS_KEY
AND   the subprocess inherits only: PATH, HOME, LANG, TERM, PLUGIN_ID, PLUGIN_DATA_DIR

WHEN  the subprocess crashes (exit code != 0)
THEN  PluginRunner catches the failure
AND   logs "Plugin acme/analytics crashed: exit code 1"
AND   ShikkiKit continues running (no process death)
AND   the plugin is marked as .crashed in the registry
```

### Scenario 7: Enterprise certification gate (BR-08)
```
GIVEN plugin "acme/enterprise-scanner" with certification .communityReviewed
WHEN  it requests access to ~/project/src/ (a project file path)
THEN  PluginSandbox blocks: "Enterprise certification required for project file access"

GIVEN plugin "acme/enterprise-scanner" with certification .enterpriseSafe
AND   certification is not expired
WHEN  it requests access to ~/project/src/
THEN  PluginSandbox allows read access (additive-only write still enforced)
```

### Scenario 8: Manifest declares paths (BR-06)
```
GIVEN a plugin manifest with no declaredPaths field
WHEN  PluginManifest.validate() is called
THEN  validation passes (declaredPaths defaults to empty — plugin has scope-only access)

GIVEN a plugin manifest with declaredPaths: ["~/project/src/", "/tmp/shared/"]
WHEN  the plugin requests access to ~/project/src/file.swift
THEN  PluginSandbox checks declaredPaths and allows (if user approved)

WHEN  the plugin requests access to ~/project/docs/file.md
THEN  PluginSandbox blocks: path not in declaredPaths
```

### Scenario 9: Plugin uninstall cleanup (BR-09)
```
GIVEN plugin "acme/analytics" installed at ~/.shikki/plugins/acme-analytics/
AND   its data directory contains: data/cache.json, data/logs/run.log
WHEN  PluginRegistry.uninstall(id: "acme/analytics") is called
THEN  the entire directory ~/.shikki/plugins/acme-analytics/ is removed
AND   no other plugin directories are affected
AND   the plugin is removed from the registry
AND   the command index entries are removed
```

### Scenario 10: Plugin cannot write outside scope without declared paths (BR-01, BR-02)
```
GIVEN plugin "acme/analytics" with declaredPaths: [] (empty)
WHEN  the plugin requests to write to /tmp/exfiltrated-data.json
THEN  PluginSandbox blocks: path outside scope and not in declaredPaths
AND   SecurityViolation logged
```

## Architecture

### Files to Modify

| File | Modification | BRs |
|------|-------------|-----|
| `PluginManifest.swift` | Add `declaredPaths: [String]` field to `PluginManifest` | BR-06 |
| `PluginManifest.swift` | Add `SecurityViolation` type for audit logging | BR-02, BR-03 |
| `PluginRegistry.swift` | Add `uninstall(id:)` that removes scoped directory + deregisters | BR-09 |
| `PluginRegistry.swift` | Add `markCrashed(id:)` for post-crash state tracking | BR-10 |

### Files to Create

| File | Purpose | BRs |
|------|---------|-----|
| `Plugins/PluginSandbox.swift` | Path validation, secret pattern matching, additive-only enforcement, enterprise gate | BR-01 to BR-06, BR-08 |
| `Plugins/PluginRunner.swift` | Subprocess launch with sanitized env, crash isolation, timeout | BR-07, BR-10 |
| `Tests/PluginSandboxTests.swift` | All 10 test scenarios | All BRs |

### New Types

```swift
// PluginSandbox.swift
public struct PluginSandbox: Sendable {
    public let pluginId: PluginID
    public let scopeDirectory: String           // ~/.shikki/plugins/<id>/data/
    public let declaredPaths: [String]          // from manifest
    public let certification: CertificationLevel
    public let userApprovedPaths: Set<String>   // runtime approvals

    /// Validate a file access request.
    public func validateAccess(
        path: String,
        operation: FileOperation
    ) -> AccessDecision

    /// Secret file patterns (always blocked regardless of scope/approval).
    public static let secretPatterns: [String]  // .env, .aws, keychain, etc.

    /// ShikkiKit source patterns (always blocked for writes).
    public static let protectedSourcePatterns: [String]
}

public enum FileOperation: Sendable {
    case read
    case create
    case overwrite
    case delete
}

public enum AccessDecision: Sendable {
    case allowed
    case denied(reason: String)
}

public struct SecurityViolation: Sendable, Codable {
    public let pluginId: PluginID
    public let attemptedPath: String
    public let operation: String
    public let reason: String
    public let timestamp: Date
}
```

```swift
// PluginRunner.swift
public actor PluginRunner {
    /// Allowed env vars for plugin subprocesses.
    /// Everything else is stripped (especially secrets).
    public static let allowedEnvVars: Set<String> = [
        "PATH", "HOME", "LANG", "TERM",
        "PLUGIN_ID", "PLUGIN_DATA_DIR"
    ]

    public init(sandbox: PluginSandbox, manifest: PluginManifest)

    /// Execute the plugin's entryPoint in a sandboxed subprocess.
    /// Returns the exit code and captured stdout/stderr.
    public func execute(
        arguments: [String] = [],
        timeout: Duration = .seconds(300)
    ) async throws -> PluginExecutionResult

    /// Kill a running plugin subprocess.
    public func terminate() async
}

public struct PluginExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let duration: Duration
    public let crashed: Bool
}
```

```swift
// PluginManifest.swift additions
public struct PluginManifest: ... {
    // ... existing fields ...
    public let declaredPaths: [String]  // NEW — filesystem paths this plugin accesses
}
```

### Sandbox Validation Flow

```
Plugin requests file access
         │
         ▼
  ┌─ Is path a secret pattern? ──── YES ──→ DENY (always, no override)
  │        NO
  │        ▼
  ├─ Is path within scope dir? ──── YES ──→ ALLOW (home territory)
  │        NO
  │        ▼
  ├─ Is path in declaredPaths? ──── NO ───→ DENY (undeclared access)
  │        YES
  │        ▼
  ├─ Is path a ShikkiKit source? ── YES ──→ DENY (protected, no override)
  │        NO
  │        ▼
  ├─ Is operation delete/overwrite? ─ YES ─→ DENY (additive-only)
  │        NO (read or create)
  │        ▼
  ├─ Is path a project file? ────── YES ──→ Check certification
  │   │                                       │
  │   │  certification >= .enterpriseSafe ─── YES ──→ ALLOW
  │   │                                       │
  │   │  certification < .enterpriseSafe ──── NO ───→ DENY
  │   │
  │   NO (non-project declared path)
  │        ▼
  └─ Has user approved this path? ── YES ──→ ALLOW
                                     NO ───→ DENY (prompt user)
```

## Execution Plan

### Task 1: Add `declaredPaths` to PluginManifest
- **Files**: Modify `Plugins/PluginManifest.swift`
- **Implement**: Add `declaredPaths: [String]` field with default `[]`. Add to `CodingKeys`. Add `SecurityViolation` struct.
- **Verify**: Existing tests compile. Encode/decode round-trip with new field.
- **BRs**: BR-06
- **Time**: ~5 min

### Task 2: PluginSandbox — path validation engine
- **Files**: Create `Plugins/PluginSandbox.swift`
- **Implement**: `validateAccess()` with the full decision flow: secret patterns, scope check, declaredPaths, ShikkiKit protection, additive-only, enterprise gate. Static `secretPatterns` and `protectedSourcePatterns`.
- **Verify**: Unit tests for each branch of the decision tree
- **BRs**: BR-01, BR-02, BR-03, BR-04, BR-05, BR-06, BR-08
- **Time**: ~15 min

### Task 3: PluginRunner — subprocess isolation
- **Files**: Create `Plugins/PluginRunner.swift`
- **Implement**: `execute()` spawns `Process` with sanitized env (only `allowedEnvVars`), captures stdout/stderr, enforces timeout, catches crash (non-zero exit). Sets `PLUGIN_ID` and `PLUGIN_DATA_DIR` in subprocess env.
- **Verify**: Test with a simple script that echoes env — verify secret vars are absent
- **BRs**: BR-07, BR-10
- **Time**: ~15 min

### Task 4: Uninstall with scoped cleanup
- **Files**: Modify `Plugins/PluginRegistry.swift`
- **Implement**: Add `uninstall(id:)` that calls `deregister()` + removes `~/.shikki/plugins/<id>/` directory. Add `markCrashed(id:)`. Validate that only the plugin's directory is removed (no parent traversal).
- **Verify**: Create temp plugin dir, uninstall, verify only that dir removed
- **BRs**: BR-09, BR-10
- **Time**: ~8 min

### Task 5: PluginSandboxTests — full scenario coverage
- **Files**: Create `Tests/ShikkiKitTests/PluginSandboxTests.swift`
- **Implement**: All 10 scenarios from test plan. Use `@Suite("PluginSandbox")`. Test path traversal, secret blocking, additive-only, enterprise gate, subprocess env sanitization, crash isolation, uninstall cleanup.
- **Verify**: `swift test --filter PluginSandboxTests` — all pass
- **BRs**: All
- **Time**: ~25 min

### Task 6: Wire PluginRunner into PluginRegistry execution path
- **Files**: Modify `Plugins/PluginRegistry.swift`
- **Implement**: Add `execute(pluginId:arguments:)` method that creates `PluginSandbox` + `PluginRunner` for the plugin, runs in subprocess, returns result. Catches crash and calls `markCrashed()`.
- **Verify**: Integration test — register mock plugin, execute, verify sandbox enforced
- **BRs**: BR-01, BR-07, BR-10
- **Time**: ~10 min

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 10/10 BRs mapped to tasks |
| Test Coverage | PASS | 10/10 scenarios mapped to Task 5 |
| File Alignment | PASS | 2 modify + 3 create — all identified |
| Task Dependencies | PASS | Task 1 first (types), 2-3 parallel (sandbox + runner), 4 (registry), 5-6 (tests + wiring) |
| Task Granularity | PASS | All tasks 5-25 min |
| Testability | PASS | All scenarios testable with temp directories and mock scripts |
| Security Review | PASS | Secret patterns hardcoded, env sanitized allowlist, additive-only enforced, enterprise gate runtime-enforced |

**Verdict: PASS** — ready for Phase 6.

## @shi Mini-Challenge

1. **@Ronin**: The additive-only constraint (BR-05) blocks overwrite of existing files. But what about plugins that format or lint code — they NEED to overwrite? Should there be a `declaredWritePaths` with explicit user approval, separate from `declaredPaths`? Or is a "formatter" plugin fundamentally incompatible with additive-only?
2. **@Katana**: `PluginRunner.allowedEnvVars` is a static allowlist. But `PATH` itself could contain directories with secret-reading tools. Should we restrict `PATH` to a minimal set (`/usr/bin:/usr/local/bin`) or is that too restrictive for plugins that depend on user-installed tools (e.g., `ffmpeg`, `python3`)?
3. **@Sensei**: The sandbox validates paths at the ShikkiKit layer. But the subprocess (`Process`) runs a real binary on the OS — it has no kernel-level sandbox. A malicious plugin could ignore the sandbox API and make raw syscalls. Should we use `sandbox-exec` (macOS) / `seccomp` (Linux) for real OS-level containment, or is that overkill for v0.3 where all plugins are local/trusted?

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-30 | Phase 1-5b | @Katana | APPROVED | Code audit + spec in one session |
