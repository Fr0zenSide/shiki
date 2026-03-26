# Feature: Open Source Protection Protocol — LICENSE Respect + Attribution + Anti-Theft

> **Type**: /md-feature
> **Priority**: P1 — ethical foundation, blocks public release
> **Status**: Spec (validated by @Daimyo 2026-03-26)
> **Depends on**: Shikki Knowledge MCP (ingestion pipeline), ShikiDB (metadata storage)
> **Affects**: /ingest, /radar, /research, any agent that reads external code
> **License context**: Shikki is AGPL-3.0 + CLA, owned by OBYW.one SASU

---

## Phase 1: Brainstorm Table

### @Sensei (Architecture) — 3 proposals

| # | Idea | Mechanism | Effort |
|---|------|-----------|--------|
| S1 | **LICENSE Detection Engine** — AST-free file scanner that identifies LICENSE/COPYING/NOTICE files, SPDX headers in source files, and package.json/Cargo.toml/Package.swift license fields. Returns a canonical SPDX identifier (MIT, Apache-2.0, AGPL-3.0-only, etc.) or `UNKNOWN` if ambiguous. Runs as a pure function — no side effects, fully testable. | File glob + regex + SPDX expression parser | M |
| S2 | **Ingestion Gate (MCP Protocol)** — New MCP tool `shikki_ingest_project` wraps the entire ingestion pipeline. Before ANY knowledge is stored, the gate: (1) detects license, (2) checks compatibility matrix against Shikki's AGPL-3.0, (3) requires explicit user confirmation for copyleft/unknown licenses, (4) stamps every DB record with `source_project`, `source_license`, `source_url`. Rejects proprietary/no-license by default. | MCP tool + compatibility matrix + DB schema extension | L |
| S3 | **Attribution Registry** — Dedicated DB table `attribution_registry` tracking every ingested project: name, url, logo_url, license_spdx, contribution_summary, ingested_at, ingested_by (agent/user). Powers the public attribution page. Append-only — entries can be updated but never deleted. This is the proof layer. | New DB table + API + static page generator | M |

### @Katana (Security) — 3 proposals

| # | Idea | Mechanism | Effort |
|---|------|-----------|--------|
| K1 | **Provenance Watermark** — Every piece of knowledge stored in ShikiDB carries a `provenance` JSON field: `{source, license, ingestedAt, ingestedBy, sha256OfLicenseFile}`. The SHA-256 of the original LICENSE file is stored so any tampering (retroactive license change claims) can be detected. This watermark is immutable once written. | DB column + write-once constraint | S |
| K2 | **Audit Trail** — Append-only `license_audit_log` table recording every ingestion decision: project, detected license, compatibility verdict, user override (if any), timestamp. This creates a legal paper trail proving due diligence. Queryable via MCP tool `shikki_license_audit`. | Append-only table + MCP read tool | S |
| K3 | **Propagation Guard** — When Shikki generates code that draws from ingested knowledge, the output carries a comment header listing attributions. If a third party uses Shikki's output, the attribution propagates. For copyleft sources (GPL/AGPL), the guard emits a warning that the output may carry copyleft obligations. | Output post-processor + attribution header template | M |

### @Kintsugi (Philosophy) — 2 proposals

| # | Idea | Mechanism | Effort |
|---|------|-----------|--------|
| P1 | **The Gift Economy Principle** — Open source is a gift. The correct response to a gift is gratitude, not extraction. Shikki's attribution page is not a legal checkbox — it is a public expression of respect. Each entry names what we learned, not just what we took. The contribution_summary field answers: "What did this project teach us?" This transforms compliance into craft. | Cultural framing + contribution_summary field | S |
| P2 | **The Impossible Laundering Rule** — AI tools that consume open-source code and output "original" code are laundering intellectual labor. Shikki takes the opposite stance: every output is traceable to its inspirations. If you cannot name your sources, you did not learn from them — you copied them. The provenance chain is not optional. It is the difference between a student and a plagiarist. | Provenance chain + zero-tolerance for unattributed ingestion | S |

### @Shogun (Market) — 2 proposals

| # | Idea | Mechanism | Effort |
|---|------|-----------|--------|
| M1 | **Market Gap: Nobody Does This** — GitHub Copilot, Cursor, Windsurf, Devin — none of them track license provenance of training data at the individual project level. They rely on bulk "fair use" arguments. Shikki can be the first AI code tool that provides per-project attribution with a public credits page. This is a differentiator that resonates with open-source maintainers — the people who build the ecosystem these tools depend on. | Public attribution page + marketing positioning | S |
| M2 | **Trust Signal for Enterprise** — Companies using AI code tools face legal uncertainty (see Copilot lawsuits). Shikki's license audit trail provides a compliance artifact: "Here is every open-source project we learned from, here is its license, here is our compatibility analysis." This is something legal teams can review. No other tool offers this. It turns an ethical stance into a sales advantage. | Audit export (JSON/PDF) + enterprise compliance report | M |

---

## Phase 2: Feature Brief

### Problem

AI code tools consume open-source projects wholesale — for training, for RAG, for "inspiration" — without tracking where knowledge comes from or what license terms apply. This is:

1. **Disrespectful** — open-source maintainers create freely; the least we owe them is attribution
2. **Legally risky** — ingesting GPL code into a proprietary project creates license contamination
3. **Invisible** — once code passes through an AI, its origins are erased; this is intellectual laundering
4. **Industry-wide** — no AI code tool currently solves this at the individual project level

### Solution

Shikki implements a LICENSE Protection Protocol with three layers:

1. **Detection** — automatic license identification at ingestion time
2. **Gate** — compatibility check before knowledge enters the database
3. **Attribution** — permanent, public, append-only record of every source

### Scope v1

| In scope | Out of scope (future) |
|----------|----------------------|
| LICENSE file detection (file-level) | SPDX header scanning in individual source files |
| SPDX identifier mapping (common licenses) | Multi-license resolution (dual MIT/Apache) |
| Compatibility matrix (AGPL-3.0 host) | Arbitrary host license configuration |
| Attribution registry (DB table) | Public web attribution page (needs landing infra) |
| Ingestion gate (MCP tool) | Output propagation guard (copyleft warnings in generated code) |
| Audit trail (append-only log) | Enterprise compliance PDF export |
| Provenance watermark on DB records | Cross-tool provenance (third-party Shikki users) |

### Architecture

```
                    ┌─────────────────────┐
                    │  /ingest or /radar  │
                    │  (user or agent)    │
                    └─────────┬───────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  LicenseDetector    │
                    │  (pure function)    │
                    │  → SPDX identifier  │
                    └─────────┬───────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  CompatibilityGate  │
                    │  AGPL-3.0 matrix    │
                    │  → allow/warn/block │
                    └─────────┬───────────┘
                              │
                    ┌─────────┼─────────┐
                    │         │         │
                    ▼         ▼         ▼
                 ALLOW      WARN      BLOCK
                   │         │         │
                   │    user confirm   │
                   │    required       reject +
                   │         │         log reason
                   ▼         ▼
          ┌──────────────────────────┐
          │  ShikiDB Ingestion       │
          │  + provenance watermark  │
          │  + attribution registry  │
          │  + audit log entry       │
          └──────────────────────────┘
```

---

## Phase 3: Business Rules

### 3.1 License Detection

**LicenseDetector** scans a project root for license information in priority order:

1. `LICENSE`, `LICENSE.md`, `LICENSE.txt`, `LICENCE`, `COPYING`, `NOTICE`
2. `package.json` → `license` field
3. `Cargo.toml` → `[package] license`
4. `Package.swift` — no standard field; fall back to file detection
5. `pyproject.toml` → `[project] license`
6. `go.mod` — no standard field; fall back to file detection

Detection uses pattern matching against known license texts (top 20 by usage):

| SPDX Identifier | Common Name | Detection Pattern |
|-----------------|-------------|-------------------|
| MIT | MIT License | "Permission is hereby granted, free of charge" |
| Apache-2.0 | Apache License 2.0 | "Apache License" + "Version 2.0" |
| GPL-3.0-only | GNU GPL v3 | "GNU GENERAL PUBLIC LICENSE" + "Version 3" |
| GPL-2.0-only | GNU GPL v2 | "GNU GENERAL PUBLIC LICENSE" + "Version 2" |
| AGPL-3.0-only | GNU AGPL v3 | "GNU AFFERO GENERAL PUBLIC LICENSE" |
| BSD-2-Clause | BSD 2-Clause | "Redistribution and use" + 2 conditions |
| BSD-3-Clause | BSD 3-Clause | "Redistribution and use" + 3 conditions |
| ISC | ISC License | "ISC License" OR "Permission to use, copy, modify" (short form) |
| MPL-2.0 | Mozilla Public 2.0 | "Mozilla Public License Version 2.0" |
| LGPL-3.0-only | GNU LGPL v3 | "GNU LESSER GENERAL PUBLIC LICENSE" + "Version 3" |
| Unlicense | The Unlicense | "This is free and unencumbered software" |
| CC0-1.0 | CC Zero 1.0 | "Creative Commons" + "CC0" |
| BSL-1.0 | Boost Software 1.0 | "Boost Software License" |
| WTFPL | WTFPL | "DO WHAT THE FUCK YOU WANT TO" |
| 0BSD | Zero-Clause BSD | "Permission to use, copy, modify" (zero conditions) |
| PROPRIETARY | Proprietary | "All rights reserved" without OSI-approved grant |
| UNKNOWN | Undetectable | No LICENSE file, no manifest field, no SPDX header |

If detection confidence is below threshold (e.g., truncated file, ambiguous wording), return `UNKNOWN`.

### 3.2 Compatibility Matrix (AGPL-3.0 Host)

Shikki is AGPL-3.0. This matrix defines what can be ingested **as learning material** (not linked/compiled — ingested for knowledge):

| Source License | Verdict | Rationale |
|---------------|---------|-----------|
| MIT | ALLOW | Permissive — attribution required, included in registry |
| Apache-2.0 | ALLOW | Permissive — attribution + NOTICE preservation required |
| BSD-2-Clause | ALLOW | Permissive — attribution required |
| BSD-3-Clause | ALLOW | Permissive — attribution + no-endorsement clause |
| ISC | ALLOW | Permissive — attribution required |
| Unlicense | ALLOW | Public domain equivalent — attribution as courtesy |
| CC0-1.0 | ALLOW | Public domain — attribution as courtesy |
| 0BSD | ALLOW | Permissive — no conditions |
| BSL-1.0 | ALLOW | Permissive — attribution required |
| WTFPL | ALLOW | Permissive — no conditions |
| MPL-2.0 | WARN | Weak copyleft — file-level obligations; safe for learning, risky for direct code reuse |
| LGPL-3.0-only | WARN | Weak copyleft — linking obligations; safe for learning, requires care |
| GPL-2.0-only | WARN | Strong copyleft — learning is likely fair use, but direct code reuse triggers GPL obligations. User must confirm understanding. |
| GPL-3.0-only | WARN | Strong copyleft — same as GPL-2.0 but with patent clause. User must confirm. |
| AGPL-3.0-only | ALLOW | Same license family — compatible. Attribution still required. |
| PROPRIETARY | BLOCK | Cannot ingest proprietary code without explicit license grant. |
| UNKNOWN | BLOCK | Absence of license = all rights reserved under copyright law. Cannot ingest. User may override with `--force-license <SPDX>` if they know the actual license. |

**WARN workflow**: The gate presents the license, its implications, and asks: "This project uses [LICENSE]. Ingesting for learning is likely fair use, but direct code reuse may carry obligations. Proceed?" User must explicitly confirm. The confirmation is logged in the audit trail.

**BLOCK workflow**: Ingestion is refused. The reason is logged. User can override UNKNOWN with `--force-license` if they can verify the license through other means (e.g., author statement, alternate repo).

### 3.3 Attribution Registry

**Table: `attribution_registry`**

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| project_name | TEXT | e.g., "swift-argument-parser" |
| project_url | TEXT | e.g., "https://github.com/apple/swift-argument-parser" |
| logo_url | TEXT (nullable) | Project or org logo URL |
| license_spdx | TEXT | SPDX identifier (e.g., "Apache-2.0") |
| license_sha256 | TEXT | SHA-256 of the LICENSE file content at ingestion time |
| contribution_summary | TEXT | What this project teaches/contributes to Shikki |
| ingested_at | TIMESTAMP | When the project was first ingested |
| ingested_by | TEXT | "user" or agent name (e.g., "@Sensei") |
| updated_at | TIMESTAMP | Last metadata update |
| project_id | UUID (nullable) | FK to ShikiDB projects table |

**Rules**:
- Append-only: rows are never deleted
- `contribution_summary` is **required** — not auto-generated boilerplate but a human-meaningful description of what value this project brought
- One row per project (upsert on `project_url`)
- `license_sha256` locks the license state at ingestion time — if the upstream project changes its license later, we have proof of what it was when we ingested it

### 3.4 Provenance Watermark

Every knowledge record in ShikiDB that originates from an external project carries a `provenance` JSON field:

```json
{
  "source_project": "swift-argument-parser",
  "source_url": "https://github.com/apple/swift-argument-parser",
  "source_license": "Apache-2.0",
  "license_sha256": "a1b2c3d4...",
  "ingested_at": "2026-03-26T14:30:00Z",
  "ingested_by": "user",
  "attribution_id": "uuid-of-registry-entry"
}
```

This field is:
- **Write-once** — set at ingestion, never modified
- **Required** — ingestion without provenance is rejected at the MCP layer
- **Queryable** — `shikki_search` can filter by source_license, source_project

### 3.5 Audit Trail

**Table: `license_audit_log`**

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| timestamp | TIMESTAMP | When the decision was made |
| project_name | TEXT | Project being ingested |
| project_url | TEXT | Source URL |
| detected_license | TEXT | SPDX identifier or UNKNOWN |
| compatibility_verdict | TEXT | ALLOW, WARN, BLOCK |
| user_override | BOOLEAN | Did the user override a WARN/BLOCK? |
| override_reason | TEXT (nullable) | Why the user overrode (free text, required if override=true) |
| agent_id | TEXT | Which agent triggered the ingestion |
| session_id | TEXT (nullable) | Shikki session context |

**Rules**:
- Strictly append-only — no UPDATE, no DELETE
- Every ingestion attempt is logged, including rejected ones
- Queryable via `shikki_license_audit` MCP tool

### 3.6 MCP Protocol

New MCP tools added to Shikki Knowledge MCP:

```
shikki_ingest_project
  - url: string (required) — git URL or local path
  - contribution_summary: string (required) — what this project contributes
  - force_license: string (optional) — SPDX override for UNKNOWN detection
  → Returns: { status: "ingested" | "blocked" | "awaiting_confirmation",
               detected_license: string,
               compatibility: "allow" | "warn" | "block",
               attribution_id: string | null }

shikki_license_check
  - url: string (required) — git URL or local path
  → Returns: { license_spdx: string,
               confidence: float,
               compatibility: "allow" | "warn" | "block",
               rationale: string }

shikki_license_audit
  - project_name: string (optional) — filter by project
  - verdict: string (optional) — filter by ALLOW/WARN/BLOCK
  - since: string (optional) — ISO date filter
  → Returns: audit log entries matching filters

shikki_attribution_list
  → Returns: all attribution registry entries (for rendering credits page)

shikki_attribution_update
  - attribution_id: string (required)
  - contribution_summary: string (optional) — update description
  - logo_url: string (optional) — update logo
  → Returns: updated attribution entry
```

### 3.7 Attribution Page Format

The attribution page (generated as static markdown or HTML) follows this structure:

```
# Shikki — Open Source Credits

Shikki stands on the shoulders of open-source creators. Every project listed
here taught us something. We name them not because the law requires it, but
because respect demands it.

---

## [swift-argument-parser](https://github.com/apple/swift-argument-parser)
**License**: Apache-2.0
**What it taught us**: Declarative CLI argument parsing with property wrappers —
the foundation of Shikki's command architecture.

## [swift-nio](https://github.com/apple/swift-nio)
**License**: Apache-2.0
**What it taught us**: Event-driven networking patterns that influenced our
WebSocket and heartbeat architecture.

...
```

Each entry includes: name (linked), license, and contribution summary. No entry is ever removed.

### 3.8 Third-Party Enforcement

When Shikki is used by third parties (post-open-source release):

1. The AGPL-3.0 license already requires source disclosure for network use
2. The attribution registry is part of the codebase — removing it violates AGPL
3. The CLA ensures OBYW.one can enforce attribution requirements
4. `shikki_ingest_project` is the ONLY sanctioned ingestion path — it enforces provenance. Direct DB writes bypass the gate but lack provenance, making the knowledge unusable by any tool that checks for it.

---

## Phase 4: Test Plan

### 4.1 LicenseDetector Tests

- [ ] Detects MIT from standard LICENSE file
- [ ] Detects Apache-2.0 from LICENSE + NOTICE combination
- [ ] Detects GPL-3.0 from COPYING file
- [ ] Detects AGPL-3.0 from LICENSE file
- [ ] Detects BSD-2-Clause vs BSD-3-Clause correctly
- [ ] Detects license from package.json `license` field
- [ ] Detects license from Cargo.toml `license` field
- [ ] Returns UNKNOWN for missing LICENSE file and no manifest
- [ ] Returns UNKNOWN for truncated/corrupted LICENSE file
- [ ] Returns PROPRIETARY for "All rights reserved" without OSI grant
- [ ] Handles LICENSE.md, LICENSE.txt, LICENCE variants
- [ ] Case-insensitive file matching (license vs LICENSE)

### 4.2 CompatibilityGate Tests

- [ ] ALLOW verdict for MIT, Apache-2.0, BSD-*, ISC, Unlicense, CC0, 0BSD, BSL-1.0, WTFPL, AGPL-3.0
- [ ] WARN verdict for MPL-2.0, LGPL-3.0, GPL-2.0, GPL-3.0
- [ ] BLOCK verdict for PROPRIETARY, UNKNOWN
- [ ] BLOCK override with `--force-license` for UNKNOWN
- [ ] BLOCK cannot be overridden for PROPRIETARY
- [ ] WARN requires user confirmation before proceeding
- [ ] WARN without confirmation does not ingest
- [ ] All verdicts are logged to audit trail regardless of outcome

### 4.3 Attribution Registry Tests

- [ ] New project creates registry entry with all required fields
- [ ] Duplicate project_url upserts (updates metadata, preserves id and ingested_at)
- [ ] contribution_summary is required — empty string rejected
- [ ] license_sha256 is computed correctly from LICENSE file content
- [ ] Registry entries are never deleted (verify no DELETE endpoint/tool)
- [ ] `shikki_attribution_list` returns all entries sorted by ingested_at
- [ ] `shikki_attribution_update` updates only allowed fields (summary, logo)

### 4.4 Provenance Watermark Tests

- [ ] Ingested knowledge records contain provenance JSON
- [ ] Provenance fields match attribution registry entry
- [ ] Provenance is write-once — update attempts are rejected
- [ ] Knowledge without provenance is rejected by MCP ingestion tool
- [ ] `shikki_search` can filter results by source_license
- [ ] `shikki_search` can filter results by source_project

### 4.5 Audit Trail Tests

- [ ] Every ALLOW ingestion creates audit log entry
- [ ] Every WARN ingestion (confirmed or rejected) creates audit log entry
- [ ] Every BLOCK creates audit log entry with reason
- [ ] Override entries require override_reason (non-empty)
- [ ] Audit log is append-only — no UPDATE or DELETE
- [ ] `shikki_license_audit` filters by project, verdict, date range
- [ ] Audit log includes agent_id and session_id context

### 4.6 MCP Integration Tests

- [ ] `shikki_ingest_project` with MIT project → ingested + attributed
- [ ] `shikki_ingest_project` with GPL project → awaiting_confirmation
- [ ] `shikki_ingest_project` with no LICENSE → blocked
- [ ] `shikki_ingest_project` with `force_license` override → ingested if SPDX valid
- [ ] `shikki_license_check` returns correct SPDX + compatibility without ingesting
- [ ] `shikki_attribution_list` returns structured data for page generation
- [ ] End-to-end: ingest → verify provenance → verify registry → verify audit log

### 4.7 Edge Cases

- [ ] Project with multiple LICENSE files (e.g., dual-licensed) — returns first detected, logs ambiguity
- [ ] Project with LICENSE in subdirectory only — uses root, ignores subdirs
- [ ] Empty LICENSE file — returns UNKNOWN
- [ ] Binary LICENSE file — returns UNKNOWN
- [ ] Non-English LICENSE text — returns UNKNOWN (v1 limitation)
- [ ] Git submodule with different license — submodule licenses tracked separately (future)
- [ ] Rate of ingestion — bulk /radar with 50 projects processes sequentially through gate

---

## Implementation Waves

### Wave 1: LicenseDetector + CompatibilityGate (S — 1 day)
- `LicenseDetector.swift` — pure function, ~200 LOC
- `CompatibilityGate.swift` — matrix lookup, ~100 LOC
- ~20 unit tests
- No DB dependency, no MCP — pure logic

### Wave 2: Attribution Registry + Audit Trail (M — 1-2 days)
- DB migration: `attribution_registry` + `license_audit_log` tables
- `AttributionRegistry.swift` — CRUD service
- `LicenseAuditLogger.swift` — append-only writer
- ~15 tests

### Wave 3: MCP Tools + Provenance (M — 1-2 days)
- MCP tool definitions: `shikki_ingest_project`, `shikki_license_check`, `shikki_license_audit`, `shikki_attribution_list`, `shikki_attribution_update`
- Provenance watermark injection into ShikiDB knowledge records
- ~12 integration tests

### Wave 4: Attribution Page Generator (S — half day)
- Markdown/HTML generator from attribution registry
- `shikki credits` CLI command
- ~5 tests

**Total estimate**: ~3-4 days, ~52 tests, ~600 LOC

---

## Design Principles

1. **Respect over compliance** — We attribute because we are grateful, not because we are afraid
2. **Provenance is permanent** — Once recorded, never erased. The chain of inspiration is sacred.
3. **Absence of license = absence of permission** — UNKNOWN is BLOCK, not ALLOW
4. **The gate is mandatory** — No backdoor ingestion path. Every piece of external knowledge passes through the protocol.
5. **Transparency is the product** — The attribution page is not hidden in a footer. It is a feature.
