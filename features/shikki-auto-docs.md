---
title: "Auto-Generated Documentation from Moto Cache"
status: draft
priority: P1
project: shikki
created: 2026-04-02
authors: "@Daimyo + @shi brainstorm"
tags: [docs, moto, automation, pre-commit]
---

# Feature: Auto-Generated Documentation from Moto Cache
> Created: 2026-04-02 | Status: draft | Owner: @Daimyo

## Problem

Documentation rots. The `docs/` directory contains manually written markdown (cheatsheet.md, mcp-setup.md, plugins.md) that drifts from reality after every commit. Nobody updates docs because nobody remembers which docs are affected by a code change. Moto already indexes every protocol, type, method, dependency, and pattern. That index is the ground truth -- if the cache knows the code, the docs should write themselves.

## Architecture

```
git commit
  --> pre-commit hook (hooks/pre-commit-docs.sh)
  --> git diff --cached --name-only
  --> DocGenerator reads .moto-cache/ (manifest.json, api-surface.json, etc.)
  --> maps changed files -> affected doc sections via file-to-section index
  --> regenerates ONLY affected sections into docs/generated/
  --> git add docs/generated/
  --> commit proceeds with updated docs included
```

**Key insight**: partial rebuild. The hook reads git diff, maps changed source files to Moto cache entries, and rebuilds only the affected doc sections. A commit touching `PluginManifest.swift` regenerates the plugin reference but leaves the CLI reference untouched.

### Components

| Component | Location | Role |
|-----------|----------|------|
| `DocGenerator` | `ShikkiKit/Docs/DocGenerator.swift` | Reads Moto cache, applies templates, writes markdown |
| `DocSection` | `ShikkiKit/Docs/DocSection.swift` | Enum of generatable sections + file-to-section mapping |
| `DocTemplate` | `ShikkiKit/Docs/DocTemplate.swift` | Mustache-lite template engine (string interpolation) |
| `pre-commit-docs.sh` | `hooks/pre-commit-docs.sh` | Shell hook: diff -> shikki docs rebuild --changed |
| `DocsCommand` | `Commands/DocsCommand.swift` | CLI: `shikki docs rebuild [--all] [--changed] [--section X]` |

## Business Rules

1. **BR-01**: Generated docs live in `docs/generated/` and MUST have a `<!-- AUTO-GENERATED -->` header. Manual docs stay in `docs/`.
2. **BR-02**: The pre-commit hook MUST complete in under 2 seconds for incremental rebuilds. If it exceeds 2s, skip doc generation and emit a warning (never block the commit).
3. **BR-03**: If `.moto-cache/manifest.json` does not exist or is stale (git hash mismatch), the hook skips generation silently. No crash, no block.
4. **BR-04**: Each generated doc section declares its source files in a footer comment: `<!-- Sources: PluginManifest.swift, PluginRegistry.swift -->`. This is the traceability chain.
5. **BR-05**: `shikki docs rebuild --all` forces a full regeneration regardless of diff. Used in CI and release pipelines.
6. **BR-06**: The file-to-section mapping is derived from Moto cache `module` and `file` fields, not from hardcoded path lists. New files automatically map to the correct section by module membership.
7. **BR-07**: Protocol doc comments (`///`) are extracted as descriptions. Types without doc comments get a placeholder: `*No description available.*`
8. **BR-08**: The CLI reference is generated from ArgumentParser `@Argument`, `@Option`, and `@Flag` declarations via source parsing, not runtime introspection.
9. **BR-09**: Architecture overview uses the dependency graph from `dependencies.json` to render a Mermaid diagram.
10. **BR-10**: `shikki docs coverage` reports the percentage of public types/protocols with doc comments. Target: 80% for core modules, 50% for CLI.

## TDDP — Test-Driven Development Plan

| Test | BR | Tier | Type | Description |
|------|-----|------|------|-------------|
| T-01 | BR-06 | Core (80%) | Unit | Single file change touching one module — only that section regenerated |
| T-02 | BR-03 | Core (80%) | Unit | No `.moto-cache/` directory — hook exits silently, no error |
| T-03 | BR-03 | Core (80%) | Unit | Cache manifest git hash differs from HEAD — hook skips generation |
| T-04 | BR-07 | Core (80%) | Unit | New public type without doc comment — renders `*No description available.*` |
| T-05 | BR-05 | Core (80%) | Unit | `shikki docs rebuild --all` — all 6 sections regenerated, footer comments updated |
| T-06 | BR-10 | Smoke (CLI) | Unit | `shikki docs coverage` on 60% documented project — reports 60%, lists undocumented |
| T-07 | BR-02 | Core (80%) | Integration | Pre-commit hook exceeds 2s timeout — warning emitted, commit proceeds |
| T-08 | BR-08 | Core (80%) | Unit | Protocol with 3 method requirements — API reference lists all 3 signatures |
| T-09 | BR-01 | Core (80%) | Unit | Generated docs have `<!-- AUTO-GENERATED -->` header |
| T-10 | BR-04 | Core (80%) | Unit | Generated doc footer contains `<!-- Sources: ... -->` traceability comment |
| T-11 | BR-09 | Core (80%) | Unit | Architecture overview renders Mermaid diagram from dependencies.json |
| T-12 | BR-02 | Core (80%) | Unit | Incremental rebuild completes under 2s for single-file change |

### S3 Test Scenarios

```
T-01 [BR-06, Core 80%]:
When a single file changes touching one module:
  → file-to-section mapping resolves via Moto cache module field
  → only that module's doc section regenerated
  → other sections untouched (no file write, no timestamp change)

T-02 [BR-03, Core 80%]:
When .moto-cache/ directory does not exist:
  → hook checks for manifest.json
  → file not found, hook exits with code 0
  → no error output, no warning
  → commit proceeds normally

T-03 [BR-03, Core 80%]:
When cache manifest git hash differs from HEAD:
  → manifest.json parsed, gitHash field extracted
  → gitHash != current HEAD commit
  → hook skips generation silently
  → commit proceeds without doc update

T-04 [BR-07, Core 80%]:
When a new public type has no doc comment:
  → type detected in api-surface.json
  → no /// comment found for type
  → rendered with "*No description available.*" placeholder
  → type still appears in generated docs (not skipped)

T-05 [BR-05, Core 80%]:
When running shikki docs rebuild --all:
  → all 6 DocSection cases regenerated
  → each generated file has <!-- AUTO-GENERATED --> header
  → each generated file has <!-- Sources: ... --> footer
  → output written to docs/generated/

T-06 [BR-10, Smoke CLI]:
When running shikki docs coverage on a 60% documented project:
  → public types and protocols counted
  → types with /// doc comments counted
  → "60%" coverage reported
  → undocumented public symbols listed by name

T-07 [BR-02, Core 80%]:
When pre-commit hook exceeds 2s timeout:
  → timeout command kills shikki docs rebuild
  → warning emitted to stderr: "doc generation skipped (timeout or error)"
  → commit proceeds without doc update
  → exit code 0 (never blocks commit)

T-08 [BR-08, Core 80%]:
When a protocol has 3 method requirements:
  → source parsed for protocol declaration
  → all 3 func/var signatures extracted
  → API reference lists each signature with parameter types
  → return types included

T-09 [BR-01, Core 80%]:
When DocGenerator writes a generated doc:
  → first line is "<!-- AUTO-GENERATED -->"
  → file written to docs/generated/ (not docs/)
  → manual docs in docs/ untouched

T-10 [BR-04, Core 80%]:
When DocGenerator renders a section:
  → footer comment appended: <!-- Sources: File1.swift, File2.swift -->
  → source files listed alphabetically
  → sources derived from Moto cache file field for that section

T-11 [BR-09, Core 80%]:
When rendering architecture overview:
  → dependencies.json loaded from Moto cache
  → Mermaid diagram generated with module nodes and edges
  → diagram syntax valid (graph TD / graph LR format)
  → output written to docs/generated/architecture-overview.md

T-12 [BR-02, Core 80%]:
When incremental rebuild runs for a single-file change:
  → total execution time < 2 seconds
  → only affected section rebuilt (not all 6)
  → file I/O limited to one section write
```

## Wave Dispatch Tree

```
Wave 1: DocGenerator Core + CLI
  ├── DocGenerator (reads Moto cache, renders sections)
  ├── DocSection enum + file-to-section mapping
  ├── DocTemplate (per-section render functions)
  └── DocsCommand (shikki docs rebuild --all, --section X)
  Tests: T-01, T-04, T-05, T-08, T-09, T-10
  Gate: swift test --filter Doc → all green

Wave 2: Incremental Rebuild + Pre-Commit Hook ← BLOCKED BY Wave 1
  ├── --changed --files flag on DocsCommand
  ├── pre-commit-docs.sh hook (timeout + guards)
  ├── File-to-section mapping via Moto cache module/file fields
  └── Stale cache detection (git hash mismatch)
  Tests: T-02, T-03, T-07, T-12
  Gate: swift test --filter Doc → all green + hook integration verified

Wave 3: Coverage Report + Mermaid Diagrams ← BLOCKED BY Wave 1
  ├── shikki docs coverage command
  ├── Mermaid dependency graph in architecture-overview.md
  └── CLI reference from ArgumentParser source parsing
  Tests: T-06, T-11
  Gate: full swift test green
```

## Generated vs Manual

| Generated (docs/generated/) | Manual (docs/) |
|------------------------------|----------------|
| api-reference.md | cheatsheet.md |
| cli-reference.md | getting-started.md (future) |
| architecture-overview.md | philosophy.md (future) |
| plugin-reference.md | mcp-setup.md |
| configuration-reference.md | |
| changelog.md (via VersionBumper) | |

**@Kintsugi's rule**: Generated docs answer "what exists?" Manual docs answer "why does it exist and how should I think about it?" Both are necessary. Auto-generation replaces the grind, not the narrative.

## Pre-Commit Hook Design

```bash
#!/usr/bin/env bash
# hooks/pre-commit-docs.sh — partial doc rebuild from staged changes
set -euo pipefail

CACHE_DIR=".moto-cache"
MANIFEST="$CACHE_DIR/manifest.json"

# Guard: skip if no Moto cache
[ -f "$MANIFEST" ] || exit 0

# Guard: skip if shikki binary not available
command -v shikki >/dev/null 2>&1 || exit 0

# Get changed Swift files from staging area
CHANGED=$(git diff --cached --name-only --diff-filter=ACMR -- '*.swift')
[ -z "$CHANGED" ] && exit 0

# Run incremental doc rebuild with 2s timeout
timeout 2 shikki docs rebuild --changed --files "$CHANGED" 2>/dev/null || {
    echo "warning: doc generation skipped (timeout or error)" >&2
    exit 0
}

# Stage any updated generated docs
git add docs/generated/ 2>/dev/null || true
```

**@Ronin's mitigations**: 2s timeout (never blocks commit), manifest git-hash guard (stale cache = skip), only `*.swift` triggers the hook (no circular doc-changes-trigger-hook loop).

## Template System

Templates use simple string interpolation, not a full engine. Each `DocSection` has a `render(from:)` method that takes the relevant Moto cache slice and returns markdown.

```swift
enum DocSection: String, CaseIterable {
    case apiReference       // from api-surface.json + types.json
    case cliReference       // from source parsing of Commands/
    case architectureOverview // from dependencies.json + package.json
    case pluginReference    // from types.json filtered by PluginManifest
    case configReference    // from types.json filtered by AppConfig
    case changelog          // from ChangelogGenerator (existing)
}
```

No Mustache, no Stencil, no external dependency. Each section is a Swift function that builds a string.

## Test Scenarios

| # | Scenario | Expects |
|---|----------|---------|
| T1 | Single file change touching one module | Only that module's doc section regenerated |
| T2 | No `.moto-cache/` directory | Hook exits silently, no error |
| T3 | Cache manifest git hash differs from HEAD | Hook skips generation |
| T4 | New public type added without doc comment | Renders with `*No description available.*` placeholder |
| T5 | `shikki docs rebuild --all` | All 6 sections regenerated, all footer comments updated |
| T6 | `shikki docs coverage` on project with 60% doc comments | Reports 60%, lists undocumented public symbols |
| T7 | Pre-commit hook exceeds 2s timeout | Warning emitted, commit proceeds, no docs staged |
| T8 | Protocol with 3 method requirements | API reference lists all 3 with signatures |

## Implementation Waves

### Wave 1: DocGenerator Core + CLI (P0)
- **Files**: `ShikkiKit/Docs/DocGenerator.swift`, `ShikkiKit/Docs/DocSection.swift`, `ShikkiKit/Docs/DocTemplate.swift`, `Commands/DocsCommand.swift`
- **Tests**: T-01, T-04, T-05, T-08, T-09, T-10
- **BRs**: BR-01, BR-04, BR-05, BR-06, BR-07, BR-08
- **Deps**: MotoCacheReader (exists)
- **Gate**: `swift test --filter Doc` green
- **Deliverable**: `shikki docs rebuild --all` produces 5 generated docs from cache

### Wave 2: Incremental Rebuild + Pre-Commit Hook (P0) ← BLOCKED BY Wave 1
- **Files**: `Commands/DocsCommand.swift` (extend), `hooks/pre-commit-docs.sh`
- **Tests**: T-02, T-03, T-07, T-12
- **BRs**: BR-02, BR-03, BR-06
- **Deps**: Wave 1 (DocGenerator, DocSection)
- **Gate**: `swift test --filter Doc` green + hook integration verified
- **Deliverable**: commits auto-include updated docs for changed files

### Wave 3: Coverage Report + Mermaid Diagrams (P1) ← BLOCKED BY Wave 1
- **Files**: `ShikkiKit/Docs/DocCoverageReporter.swift`, `Commands/DocsCommand.swift` (extend)
- **Tests**: T-06, T-11
- **BRs**: BR-09, BR-10
- **Deps**: Wave 1 (DocGenerator), dependencies.json
- **Gate**: full `swift test` green
- **Deliverable**: coverage metric + visual architecture doc

## @shi Mini-Challenge

1. **@Ronin**: Two parallel agents modify the same module -- do generated docs merge cleanly or conflict in worktrees?
2. **@Sensei**: CLI reference parses ArgumentParser statically. What about dynamically registered plugin commands?
3. **@Metsuke**: How do you test generated docs are *correct*, not just *present*? Snapshot tests against known cache inputs?
