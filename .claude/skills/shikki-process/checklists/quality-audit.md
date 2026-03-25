# Quality Audit — @Metsuke Protocol

> Runs AFTER @Sensei/@Ronin approve correctness.
> This audit checks output quality, not correctness.
> Invoke via `shikki review --quality` or `@Metsuke` mention.

## Purpose

@Ronin asks: "Will this crash?" @Metsuke asks: "Is this slop?"

AI-generated code often passes correctness review but exhibits patterns that mark it as machine-generated: over-abstraction, unnecessary boilerplate, generic naming, scope drift, unused scaffolding. This audit catches what cooperative reviewers consider "fine."

---

## 1. Naming Quality (8 items)

- [ ] Variable/function names are specific to the domain (not `data`, `result`, `item`, `value`)
- [ ] No redundant type-in-name (`userArray`, `nameString`, `isActiveBoolean`)
- [ ] Consistent naming convention within the file (not mixing `camelCase` and `snake_case`)
- [ ] Boolean names read as questions (`isVisible`, `hasPermission` — not `visible`, `permission`)
- [ ] No single-letter variables outside loop counters
- [ ] Acronyms follow project convention (consistent `URL`/`Url`/`url`)
- [ ] Test names describe behavior ("renders_error_when_network_fails" not "test1")
- [ ] File names match their primary export/type

## 2. Abstraction Hygiene (8 items)

- [ ] No wrapper types that add nothing (`class UserManager` wrapping a single array)
- [ ] No protocols/interfaces with a single implementation (unless DI-required)
- [ ] No "utils" or "helpers" files (each function belongs somewhere specific)
- [ ] No premature generics (`<T>` on something used with one type)
- [ ] No configuration objects for things that will never be configured
- [ ] No factory/builder patterns for simple construction
- [ ] No dependency injection for leaf functions with no side effects
- [ ] Extension files contain related functionality (not a dumping ground)

## 3. Scope Drift (6 items)

- [ ] Every changed file relates to the stated intent (PR description / commit message)
- [ ] No "while I was here" refactors mixed with feature work
- [ ] No new files that aren't referenced by the feature
- [ ] No formatting-only changes mixed with logic changes
- [ ] Added dependencies are justified by the feature (not speculative)
- [ ] Test changes match code changes (no orphaned tests, no untested new code)

## 4. Dead Weight (6 items)

- [ ] No unused imports
- [ ] No commented-out code (delete it, git remembers)
- [ ] No empty catch/error blocks
- [ ] No TODO/FIXME without a ticket reference
- [ ] No print/console.log left from debugging
- [ ] No unreachable code paths (dead branches after early returns)

## 5. Boilerplate Detection (6 items)

- [ ] No copy-pasted blocks that should be a shared function (3+ similar blocks = extract)
- [ ] No verbose null-checking chains when optionals/guard suffice
- [ ] No manual JSON encoding when Codable/Decodable handles it
- [ ] No explicit type annotations where inference is clear
- [ ] No manual iteration where map/filter/reduce is clearer
- [ ] Error handling isn't boilerplate catch-all (each error type handled specifically)

## 6. Consistency (6 items)

- [ ] Indentation matches project convention (tabs vs spaces, width)
- [ ] Brace style consistent with codebase
- [ ] Import ordering follows project convention
- [ ] Access control consistent (explicit `private`/`internal` where project requires)
- [ ] Error handling pattern matches existing codebase (Result vs throws vs optionals)
- [ ] Logging uses project logger (not raw print/NSLog)

---

## Scoring

Count findings per section. Each finding gets a category:

| Severity | Auto-fixable? | Action |
|----------|--------------|--------|
| **Trivial** | Yes | Fix immediately (unused imports, formatting, naming) |
| **Minor** | No | Flag for author, don't block |
| **Significant** | No | Block — requires rework |

## Verdict

| Score | Verdict |
|-------|---------|
| 0-3 findings | **CLEAN** — ship it |
| 4-8 findings | **ACCEPTABLE** — fix trivials, ship rest |
| 9+ findings | **NEEDS WORK** — rework before merge |

## Report Format

```
@Metsuke Quality Audit — [PR/feature name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Findings: X total (Y trivial, Z minor, W significant)
Auto-fixed: N items

[section]: [finding] — [file:line] — [severity]
...

Verdict: CLEAN / ACCEPTABLE / NEEDS WORK
```
