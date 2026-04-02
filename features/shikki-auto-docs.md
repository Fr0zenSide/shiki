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

### Wave 1: DocGenerator core + CLI (P0)
- `DocGenerator.swift` — reads Moto cache, renders sections
- `DocSection.swift` — enum + file-to-section mapping from module field
- `DocTemplate.swift` — per-section render functions
- `DocsCommand.swift` — `shikki docs rebuild --all`, `--section X`
- Tests: T1, T4, T5, T8
- **Deliverable**: `shikki docs rebuild --all` produces 5 generated docs from cache

### Wave 2: Incremental rebuild + pre-commit hook (P0)
- `--changed --files` flag on DocsCommand
- `pre-commit-docs.sh` hook with timeout + guards
- File-to-section mapping via Moto cache module/file fields
- Tests: T1, T2, T3, T7
- **Deliverable**: commits auto-include updated docs for changed files

### Wave 3: Coverage report + Mermaid diagrams (P1)
- `shikki docs coverage` command
- Mermaid dependency graph in architecture-overview.md
- CLI reference generation from ArgumentParser source parsing
- Tests: T6
- **Deliverable**: coverage metric + visual architecture doc

## @shi Mini-Challenge

1. **@Ronin**: Two parallel agents modify the same module -- do generated docs merge cleanly or conflict in worktrees?
2. **@Sensei**: CLI reference parses ArgumentParser statically. What about dynamically registered plugin commands?
3. **@Metsuke**: How do you test generated docs are *correct*, not just *present*? Snapshot tests against known cache inputs?
