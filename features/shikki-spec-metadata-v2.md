---
title: "Spec Metadata v2 — Lifecycle Status, Review Anchors, Flsh Compatibility"
status: spec
priority: P1
project: shikki
created: 2026-03-31
authors: "@Sensei + @Daimyo brainstorm"
depends-on:
  - shikki-flow-v1.md (spec lifecycle)
relates-to:
  - flsh (voice-first spec reading/review)
---

# Spec Metadata v2

> A spec file should tell you everything about itself in the first 20 lines.

---

## 1. Problem

Current spec frontmatter is inconsistent:
- Some use `status: spec`, others `status: validated`, others nothing
- No way to know if anyone READ the spec (vs just wrote it)
- No way to bookmark WHERE you stopped reading (resume later)
- No partial validation ("Section 1-7 validated, Section 8 needs rework")
- No Flsh compatibility (voice can't parse arbitrary YAML)
- No progress tracking (who reviewed what, when)

---

## 2. Spec Lifecycle States

```
DRAFT → REVIEW → PARTIAL → VALIDATED → IMPLEMENTING → SHIPPED → ARCHIVED
  │        │        │          │            │            │          │
  │        │        │          │            │            │          └─ no longer active
  │        │        │          │            │            └─ code matches spec
  │        │        │          │            └─ waves dispatched
  │        │        │          └─ @Daimyo approved all sections
  │        │        └─ some sections approved, others need work
  │        └─ someone is reading/reviewing
  └─ just written, nobody looked at it
```

---

## 3. Enhanced Frontmatter

```yaml
---
title: "ShikkiTestRunner — Architecture-Scoped Parallel Test Execution"
status: validated                    # draft | review | partial | validated | implementing | shipped | archived
progress: 14/14                      # sections reviewed / total sections
priority: P0
project: shikki
created: 2026-03-31
updated: 2026-03-31
authors: "@shi full team + @Daimyo"
reviewers:
  - who: "@Daimyo"
    date: 2026-03-31
    verdict: validated
    anchor: null                     # null = reviewed everything
    notes: "Added agent SQLite handoff, !! notation, SUI layer"
  - who: "@Ronin"
    date: null                       # not yet reviewed
    verdict: pending
depends-on:
  - moto-dns-for-code.md
relates-to:
  - shiki-scoped-testing.md
tags: [testing, infrastructure, moto, sqlite]
flsh:
  summary: "Test runner with Moto scoping, SQLite history, parallel execution"
  duration: 8m                       # estimated read-aloud time
  sections: 14                       # for voice navigation "go to section 5"
---
```

### Key Fields

| Field | Type | Purpose |
|-------|------|---------|
| `status` | enum | Lifecycle state |
| `progress` | `N/M` | Sections reviewed vs total |
| `reviewers[]` | array | Who reviewed, when, verdict, where they stopped |
| `reviewers[].anchor` | string? | `#section-8` bookmark for resume. null = complete |
| `reviewers[].verdict` | enum | `pending \| reading \| partial \| validated \| rework` |
| `tags` | string[] | Searchable categories |
| `flsh.summary` | string | One-sentence for voice read (TTS-friendly, no jargon) |
| `flsh.duration` | string | Estimated read-aloud time |
| `flsh.sections` | int | Section count for voice navigation |

---

## 4. Review Anchors

When you stop reading a spec mid-way, save your position:

```yaml
reviewers:
  - who: "@Daimyo"
    date: 2026-03-31
    verdict: reading
    anchor: "#8-tui-output"          # I stopped here, resume later
```

The anchor maps to a markdown heading: `## 8. TUI Output` → `#8-tui-output`.

When you resume: `shikki spec read shikki-test-runner.md` opens at your last anchor. Flsh reads from anchor position: `flsh read shikki-test-runner.md --from anchor`.

### Partial Validation

```yaml
reviewers:
  - who: "@Daimyo"
    date: 2026-03-31
    verdict: partial
    anchor: "#8-tui-output"
    sections_validated: [1, 2, 3, 4, 5, 6, 7]
    sections_rework: [8]             # TUI output needs revision
    notes: "Sections 1-7 approved. Section 8: change | to !!"
```

When all sections are in `sections_validated` and none in `sections_rework`, status auto-promotes to `validated`.

---

## 5. Flsh Compatibility

Flsh (voice AI) needs:
- **summary**: one sentence, no abbreviations, TTS-friendly
- **duration**: so user knows "this is an 8-minute read"
- **sections**: for voice navigation ("skip to section 5", "go back to section 3")

```
flsh read shikki-test-runner.md
  → "ShikkiTestRunner. Test runner with Moto scoping, SQLite history,
     parallel execution. 14 sections, about 8 minutes.
     Section 1: Problem..."

flsh read shikki-test-runner.md --from 8
  → "Section 8: TUI Output. During execution, each scope shows..."

flsh read shikki-test-runner.md --summary
  → "Test runner with Moto scoping, SQLite history, parallel execution.
     Status: validated. Reviewed by Daimyo on March 31st."
```

### Flsh Protocol Update (backlog task)

Flsh's `read` command currently strips frontmatter. Update to:
1. Parse the `flsh:` block for summary/duration/sections
2. Use `summary` for `--summary` flag
3. Use `sections` for `--from N` navigation
4. Use `duration` for "this will take about N minutes"

---

## 6. CLI Integration

```
shikki spec list                    → list all specs with status + progress
shikki spec list --status draft     → filter by lifecycle state
shikki spec read <file>             → open at anchor (or beginning)
shikki spec review <file>           → start review, set status to "review"
shikki spec validate <file>         → set status to "validated", clear anchor
shikki spec validate <file> --partial "#section-8"  → partial validation
shikki spec progress                → show all specs with review progress
```

### Example: `shikki spec list`

```
  􁁛 [validated]     shikki-test-runner.md          14/14  @Daimyo 2026-03-31
  􁁛 [validated]     shikki-distributed-orch.md     11/11  @Daimyo 2026-03-30
  􀢄 [partial]       shiki-mesh-protocol.md          5/8   @Daimyo 2026-03-28
  􀟈 [draft]         shikki-creative-studio.md       0/6   —
  􀟈 [draft]         shiki-os-vision.md              0/4   —
  ◇ [implementing]  shikki-codegen-engine.md        9/9   feature/codegen-engine
  ◆ [shipped]       shiki-observatory.md            7/7   on integration
```

Same markers as test runner: 􁁛 validated, 􀢄 needs work, 􀟈 untouched, ◇ in progress, ◆ done.

---

## 7. Migration

Update all 69 existing spec files:
1. Add `progress: 0/N` (count actual `##` headings)
2. Add `updated:` field
3. Add `tags:` from content analysis
4. Add `flsh:` block with auto-generated summary
5. Normalize `status:` to the lifecycle enum
6. Add `reviewers: []` (empty, to be filled on review)

This can be scripted — parse each `.md`, count headings, generate frontmatter.

---

## 8. Implementation

### Wave 1: Frontmatter Parser
- Parse enhanced YAML frontmatter
- Validate lifecycle states, progress format, anchor format
- `SpecMetadata` model with all fields
- **10 tests**

### Wave 2: CLI Commands
- `shikki spec list/read/review/validate/progress`
- Anchor-based resume
- Status transitions
- **10 tests**

### Wave 3: Flsh Integration (backlog)
- Update Flsh `read` command to parse `flsh:` block
- Voice navigation by section number
- Summary mode
- **5 tests**

### Wave 4: Migration Script
- Scan all 69 specs, add enhanced frontmatter
- Auto-count sections, generate tags
- Preserve existing fields
- **5 tests**

---

## 9. @shi Mini-Challenge

1. **@Ronin**: If two reviewers disagree (one says `validated`, other says `rework`), who wins? Should there be a quorum?
2. **@Hanami**: The `flsh.duration` is estimated. Should it auto-calculate from word count (avg 150 WPM for TTS)?
3. **@Kintsugi**: A spec that's `validated` but never `implementing` — is it a promise unkept or wisdom deferred?
