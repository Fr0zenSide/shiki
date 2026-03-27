# Feature: Memory Migration + Multi-User Scoping

> Created: 2026-03-27 | Status: Phase 1-4 | Owner: @Daimyo | Priority: P0

## Context

Memory files (`.claude/projects/.../memory/*.md`) contain competitive intelligence, business strategy, fundraising plans, personal identity (PII), account details, infrastructure secrets, and financial context — all git-tracked and visible to anyone who clones the repo. This is a P0 blocker before any open-source release or collaborator onboarding.

Three problems to solve:

1. **Security**: Move all strategic/private content from `memory/*.md` to @db. No sensitive data in git.
2. **Multi-user identity**: Faustin (Maya co-founder) sees shared Maya project data, not @Daimyo's personal radar, fundraising plans, or OBYW.one strategy.
3. **Git history cleanup**: `git filter-repo` to scrub sensitive data from ALL commits, not just HEAD.

---

## Phase 1: Inspiration

### Brainstorm Table — 10 Ideas from the @shi Team

| # | Agent | Idea | Signal |
|---|-------|------|--------|
| 1 | **@Sensei** | **Data Model: Identity + Scoping** — Current `agent_memories` has no `user_id` or `scope`. Add three dimensions: `user_id` (who owns this), `scope` (enum: personal/project/company/global), `company_id` (which org). Maps cleanly to existing `projects` table while adding layers above it. | Architecture |
| 2 | **@Sensei** | **MEMORY.md as Query Template** — File becomes a routing manifest, not storage. Every line is a `POST /api/memories/search` pointer with scope and category params. Zero secrets. Claude reads the manifest, fires queries, loads context. | Architecture |
| 3 | **@Sensei** | **Migration Script in Shikki CLI** — `shikki migrate memory` reads every `memory/*.md`, classifies scope/category by filename prefix + content heuristics, POSTs to @db, logs results, generates verification report. Idempotent (skip if `migratedFrom` already exists in metadata). | Architecture |
| 4 | **@Katana** | **git filter-repo (not BFG, not filter-branch)** — `git filter-repo --path-glob '*/memory/*.md' --invert-paths`. Faster than BFG (Python, not Java), actively maintained, handles all edge cases. Git project itself recommends it over `filter-branch`. Requires force-push to all branches + all collaborators re-clone. | Security |
| 5 | **@Katana** | **Zero Exceptions Policy** — Remove ALL `memory/*.md` from git history. Not just the obviously sensitive ones. The cumulative exposure of 44 `feedback_*.md` + 50+ `project_*.md` is the risk, not any single file. One audit regex: `git log --all -S "<known PII>" -- '*/memory/*.md'`. | Security |
| 6 | **@Katana** | **Row-Level Security (RLS) in PostgreSQL** — RLS policies enforce scoping at DB level: `personal` scope only readable by owning `user_id`, `project` scope by project members, `company` scope by company members. Defense in depth — even a buggy API endpoint can't leak personal data. Pgcrypto for at-rest encryption of personal-scope rows (v1.1). | Security |
| 7 | **@Shogun** | **Notion/Linear Multi-User Model** — Notion: workspace = company, pages have private/team/public access, guest access for external collaborators. Linear: team-scoped by default, personal views exist but all issues are team-visible. Mem.ai: personal knowledge base + shared spaces. Takeaway: adopt the Notion model — company = workspace, project = team, personal = private pages. | Market |
| 8 | **@Hanami** | **`shikki identity init` First-Run Wizard** — Name, email, company on first run (or `shikki doctor`). Saves `~/.config/shikki/identity.json` with UUID that maps to a `users` row in @db. No passwords in v1 (trust-based, same machine). v2 adds API tokens for remote/multi-machine. UX principle: identity setup is a one-time 30-second flow, invisible after that. | UX |
| 9 | **@Kintsugi** | **Private Garden vs Public Square** — Personal knowledge is a private garden. Shared knowledge is a public square. The boundary is respect, not paranoia. Faustin, when querying Maya, should feel like a full participant — not a guest with restricted access. The scoping should be invisible in the happy path. You only notice it when you try to access something that isn't yours. | Philosophy |
| 10 | **@Ronin** | **Fallback When @db Down + Migration Risks** — Never go amnesiac. Local cache at `~/.cache/shikki/memory-cache.json` (last-known-good dump). Write queue at `~/.cache/shikki/write-queue.jsonl` for buffered writes during downtime, replayed on reconnect. Migration risks: missed files (automated audit diff), force-push breaking branches (all branches pushed pre-rewrite), Claude can't parse pointer format (test before deleting originals), @db data loss post-migration (backup archive kept 90 days). | Adversarial |

---

## Phase 2: Synthesis

### Feature Brief

**Goal**: Migrate all strategic data from `memory/*.md` to ShikiDB. MEMORY.md becomes a set of query pointers with zero sensitive content. Multi-user scoping ensures Faustin can only see Maya project data, not @Daimyo's personal context. Git history is scrubbed clean.

**Scope v1.0 — Migration + Pointer System** (this spec):
- Migration script: read all `memory/*.md`, classify, POST to @db with proper scope/category
- New MEMORY.md format: query pointers only, zero sensitive data, inline safe conventions
- Git history cleanup: `git filter-repo` removes all `memory/*.md` from all commits
- Local cache fallback + write queue when @db unreachable
- `shikki doctor` checks: @db reachable, identity configured, memories migrated, git clean

**Scope v1.1 — User Identity + Scoping**:
- `users` and `companies` tables in @db
- `~/.config/shikki/identity.json` with user UUID
- `shikki identity init/edit/show` commands
- Row-Level Security policies on `agent_memories` (personal scope = owner-only)
- Memory queries automatically scoped to current user + their companies
- `shikki identity` first-run wizard via `shikki doctor`

**Scope v2.0 — Multi-User ACL + Company Boundaries**:
- Company membership management (`shikki company invite/remove`)
- Project-company association table
- Auth tokens for remote/multi-machine access
- Pgcrypto encryption at rest for personal-scope rows
- Audit log: who accessed what memory when
- Master/replica sync (company VPS = source of truth, dev machines = replicas)

**Out of Scope**:
- TUI for browsing memories (use existing `shikki search`)
- Automatic memory creation from conversations (unchanged)
- Agent persona management (separate spec: `shikki-agent-persona-management.md`)
- ShikiMCP changes (consumes @db, unaffected by schema additions)

**Success criteria**:
- `git log --all -S "<any PII>" -- '*/memory/*.md'` returns empty
- `grep -r "fundraising\|salary\|contact@obyw.one" .git/` returns empty
- Faustin can query Maya backlog, architecture decisions, sprint state — but cannot see OBYW.one strategy, @Daimyo's competitive radar, or personal preferences
- `shikki doctor` reports: identity OK, @db reachable, memories migrated (N/N), git history clean

---

## Phase 3: Business Rules

### Category A: What Stays in memory/*.md (BRs 01-05)

**BR-01**: `memory/*.md` files (post-migration) MUST contain ONLY generic, non-sensitive conventions that help any Claude Code session on this repo. No PII, no strategy, no business plans, no account details.

**BR-02**: Allowed content in `memory/*.md` post-migration: SPM package structure conventions, branching strategy (git flow description), test conventions (no print, one sim), agent aliases by name only (no persona content), tool preferences (Colima not Docker Desktop, LM Studio URL), and the MEMORY.md pointer manifest itself. When in doubt, move it to @db.

**BR-03**: `MEMORY.md` post-migration MUST fit in under 50 lines. It is a routing manifest, not a knowledge base. Any drift above 50 lines is a signal that sensitive content has crept back in.

**BR-04**: Inline conventions in MEMORY.md MUST pass the "anyone who clones this repo" test. If you would not publish it as a README, it does not belong in MEMORY.md. Branching strategy: safe. Infrastructure passwords: not safe. Agent alias names: safe. Competitive radar: not safe.

**BR-05**: `feedback_*.md` files (all 44+) MUST NOT remain in `memory/` post-migration. These files contain personal workflow preferences, tool opinions, and behavioral instructions that are private context — not generic conventions. They move to @db as `personal` scope `preference` category.

---

### Category B: What Moves to @db (BRs 06-10)

**BR-06**: ALL of the following file categories MUST be migrated to @db before git history cleanup:

| Category | Target Scope | Example Files |
|----------|-------------|---------------|
| User identity / PII | `personal` | `user_identity.md`, `user_profile-extended.md`, `email-signature.md` |
| User preferences / behavioral | `personal` | `feedback_*.md` (all), `user_media-language-preferences.md` |
| Business strategy | `personal` | `project_ial-maya-fundraising.md`, `project_haiku-conversion-strategy.md` |
| Competitive / market intel | `personal` | `reference_*-radar.md`, `reference_openfang-ideas.md`, `reference_skills-ecosystem-analysis.md` |
| Project backlogs | `project` | `maya-backlog.md`, `project_wabisabi-backlog.md` |
| Architecture decisions | `project` | `project_autopilot-reactor-decision.md`, `project_context-optimization-decision.md` |
| Project migration plans | `project` | `project_maya-spm-public-api-plan.md`, `project_wabisabi-spm-migration-plan.md` |
| Company vision docs | `company` | `project_shiki-vision-full-topology.md`, `project_shiki-thesis.md` |
| Infrastructure notes | `company` | `object-storage.md`, `project_backlog-backup-strategy.md` |
| Media / marketing strategy | `company` | `media-strategy.md`, `project_maya-prelaunch-strategy.md` |
| Research references | `company` | `reference_qmd-search-engine.md`, `reference_wizard-gamification-inspiration.md` |
| Agent skills audit | `company` | `project_agent-skills-audit-2026-03.md` |

**BR-07**: The `metadata` field of every migrated memory MUST include: `scope`, `userId` (of migrating user), `companyId` (if applicable), `migratedFrom` (original filename), `migratedAt` (ISO timestamp), and `originalFrontmatter` (parsed YAML if present).

**BR-08**: Project association MUST follow this mapping: Maya files → FJ Studio company + Maya project. WabiSabi files → OBYW.one company + WabiSabi project. Shiki/Shikki files → OBYW.one company + Shikki project. Brainy files → OBYW.one company + Brainy project. Generic files → OBYW.one company, `projectId: null`.

**BR-09**: The migration script MUST be idempotent. Before inserting, check `metadata.migratedFrom` for the filename. If a record already exists, skip and log `[SKIP]`. Safe to re-run after partial failure.

**BR-10**: After migration, original files MUST be archived to `~/.cache/shikki/memory-migration-backup/` as an encrypted zip (using `zip -e` minimum, gpg preferred). Archive MUST be retained for 90 days minimum, then deleted. The archive MUST NOT be committed to git under any circumstances.

---

### Category C: New MEMORY.md Format — Query Pointers (BRs 11-13)

**BR-11**: Post-migration MEMORY.md MUST follow this exact structure:

```markdown
# Shikki Memory — Query Pointers

> This file contains NO sensitive data. All knowledge is stored in ShikiDB.
> Claude: use these queries to load context at session start.

## How to Load Context

### Personal preferences
POST /api/memories/search { "scope": "personal", "category": "preference", "userId": "<from identity.json>" }

### Current project backlog
POST /api/memories/search { "scope": "project", "category": "backlog", "projectSlug": "<detected-from-git>" }

### Architecture decisions
POST /api/memories/search { "scope": "project", "category": "decision" }

### Company vision
POST /api/memories/search { "scope": "company", "category": "vision" }

### Infrastructure & conventions
POST /api/memories/search { "scope": "company", "category": "infrastructure" }

## Conventions (safe for git — generic only)

- Branching: git flow (main ← release/* ← develop ← feature/*)
- All PRs target develop, never main
- SPM packages in packages/, projects in projects/
- Testing: one simulator (latest iOS), no benchmark theater, no print() in tests
- Docker: Colima (not Docker Desktop)
- LM Studio: http://127.0.0.1:1234
- Agent aliases: @shi / @t = full team, @db = ShikiDB
```

**BR-12**: The `## Conventions` section MUST be audited against a PII/strategy checklist before any commit. Checklist items: no names, no emails, no URLs with auth tokens, no financial figures, no company-specific strategy, no competitor names, no account IDs or UUIDs. Branching strategy, tool names, and test conventions are always safe.

**BR-13**: Claude Code MUST be tested against the new MEMORY.md format in a real session before the git cleanup step. The test confirms: (a) Claude can parse the pointer format, (b) Claude issues correct @db queries, (c) results include expected context from the migrated memories, (d) session behaves identically to pre-migration.

---

### Category D: User Identity Model (BRs 14-16)

**BR-14**: User identity in v1 MUST be stored in `~/.config/shikki/identity.json` with the following schema:

```json
{
  "userId": "<uuid-generated-on-init>",
  "name": "Jeoffrey Thirot",
  "handle": "daimyo",
  "email": "contact@obyw.one",
  "companies": [
    { "id": "<uuid>", "slug": "obyw-one", "name": "OBYW.one", "role": "owner" },
    { "id": "<uuid>", "slug": "fj-studio", "name": "FJ Studio", "role": "co-founder" }
  ],
  "defaultCompany": "obyw-one",
  "createdAt": "2026-03-27T00:00:00Z"
}
```

**BR-15**: Identity resolution order MUST be: `~/.config/shikki/identity.json` → `SHIKKI_USER_ID` env var → error with actionable message `"Identity not configured. Run: shikki identity init"`. Never silently fall back to anonymous or use machine fingerprint. Machine fingerprint is not reliable across reinstalls.

**BR-16**: `shikki identity init` MUST be a conversational wizard (not a long flags command): prompt name, email, handle, default company — one field at a time. Show confirmation before writing. Register user in @db `users` table. The entire flow MUST complete in under 30 seconds for a new user. The command is idempotent: if identity.json already exists, show current identity and prompt to edit instead.

---

### Category E: Data Scoping Levels (BRs 17-20)

**BR-17**: Four and only four scope levels. No intermediate levels. No custom scopes per team. The four are:

| Scope | Visibility | SQL Filter |
|-------|-----------|-----------|
| `personal` | Only the owning `user_id` | `WHERE user_id = $current AND scope = 'personal'` |
| `project` | All users with access to the project | `WHERE project_id = $pid AND scope = 'project'` |
| `company` | All users in the company | `WHERE company_id = $cid AND scope = 'company'` |
| `global` | All authenticated users | `WHERE scope = 'global'` |

**BR-18**: A "load all relevant context" query MUST return the union of: all `personal` memories owned by the current user + all `project` memories for the current project + all `company` memories for all companies the user belongs to + all `global` memories. No other memories. This union is computed server-side in a single query with a CTE, not multiple round-trips.

**BR-19**: Project membership is derived from company membership. A user who belongs to a company can access all projects associated with that company (`project_companies` join table). No per-project membership list in v1. Finer-grained project ACL is a v2 feature.

**BR-20**: Scope downgrade is forbidden. A memory created as `personal` cannot be changed to `project` or `company` without explicit user action (`shikki memory share <id> --scope project`). Scope upgrades are allowed (project → company → global) with confirmation. This prevents accidental data exposure from scope widening bugs.

---

### Category F: Git History Cleanup (BRs 21-23)

**BR-21**: Git history cleanup MUST use `git filter-repo`. `git filter-branch` is deprecated and ~50x slower. BFG Repo Cleaner requires Java and is less maintained. The command MUST target both potential locations:

```bash
git filter-repo \
  --path-glob '.claude/projects/*/memory/*.md' \
  --path-glob 'memory/*.md' \
  --invert-paths \
  --force
```

A dry run (`--dry-run`) MUST be executed and reviewed before the real run. A full repo backup (`tar czf shiki-backup-$(date +%Y%m%d).tar.gz .git/`) MUST be created before the real run.

**BR-22**: The following PII patterns MUST be verified as absent from git history after cleanup, using `git log --all -S "<pattern>"`:
- Known names (Jeoffrey Thirot, Faustin)
- Known emails (contact@obyw.one, any personal email)
- Financial figures (salary amounts, runway figures)
- Fundraising terms ("raise", "cap table", "valuation") in memory file paths
- API keys or tokens present in any memory file

Verification MUST be automated in a shell script that returns non-zero on any match.

**BR-23**: Force-push protocol: (1) all collaborators push all branches before rewrite, (2) execute filter-repo, (3) `git push origin --force --all && git push origin --force --tags`, (4) notify all collaborators: "SHA history has changed, you MUST re-clone — do not push from your old clone or you will reintroduce the history." (5) `shikki doctor` warns any user whose local clone still has the old SHAs.

---

### Category G: Fallback When @db Unreachable (BRs 24-25)

**BR-24**: When @db is unreachable, Shikki MUST NOT become amnesiac. The fallback stack in order:
1. `~/.cache/shikki/memory-cache.json` — refreshed on every successful @db query. Contains: last 100 personal memories, last 50 per active project, all global.
2. Display degraded-mode banner: `[!] ShikiDB offline — using cached memory (age: Xh Ym)`.
3. Buffer new writes to `~/.cache/shikki/write-queue.jsonl` (FIFO). Replay on reconnect.
4. After 24h+ stale cache: escalate to `[!!] Memory cache is 24h+ stale. Some context may be outdated.`
5. Never fall back to `memory/*.md` files. Once migrated, those files are deleted from the repo. The cache is the only fallback.

**BR-25**: The write queue MUST be replayed automatically on reconnection. Replay MUST be atomic per-item (each item either succeeds or remains in queue). The queue MUST handle @db restart gracefully: no data loss, no duplicates (DB handles idempotency via UUIDs). If any item in the queue is older than 7 days, log a warning and move to `~/.cache/shikki/write-queue-expired.jsonl` for manual review.

---

### Category H: Migration Script Requirements (BRs 26-28)

**BR-26**: The migration script (`shikki migrate memory` or `scripts/migrate-memory-to-db.sh`) MUST process files in this order: (1) read directory listing, (2) skip MEMORY.md, (3) for each remaining file: read content, parse YAML frontmatter if present, classify scope and category by filename prefix + heuristic rules, determine project/company association, POST to @db, log result. Total output: one line per file with status [OK], [SKIP], or [ERR].

**BR-27**: Scope and category classification rules MUST follow this deterministic mapping (no AI classification — reproducible results):

| Filename Pattern | Scope | Category |
|----------------|-------|---------|
| `user_*` | `personal` | `identity` |
| `feedback_*` | `personal` | `preference` |
| `email-signature.md` | `personal` | `identity` |
| `reference_*-radar.md` | `personal` | `radar` |
| `reference_*` (other) | `company` | `reference` |
| `project_*-backlog*` | `project` | `backlog` |
| `project_*-decision*` | `project` | `decision` |
| `project_*-plan*` | `project` | `plan` |
| `project_*-vision*` | `company` | `vision` |
| `project_*-roadmap*` | `project` | `plan` |
| `project_ial-*` | `personal` | `strategy` |
| `project_*-prelaunch*` | `personal` | `strategy` |
| `project_*-fundraising*` | `personal` | `strategy` |
| `project_ownership-structure.md` | `company` | `infrastructure` |
| `media-strategy.md` | `company` | `strategy` |
| `object-storage.md` | `company` | `infrastructure` |
| `maya-backlog.md` | `project` | `backlog` |
| All remaining `project_*.md` | `project` | `plan` |

**BR-28**: After all files are processed, the migration script MUST output a verification report and exit non-zero if any file produced an [ERR]:

```
Migration complete: 95/96 files processed (1 skipped: MEMORY.md)
  personal:  48 memories
  project:   27 memories
  company:   18 memories
  global:     2 memories
Errors: 0

Next steps:
  1. Verify in @db: POST /api/memories/search with each scope — check counts match
  2. Test MEMORY.md pointer format with a real Claude Code session
  3. Run git cleanup: git filter-repo --path-glob '*/memory/*.md' --invert-paths
```

---

## Phase 4: Test Plan

### T-MIG: Migration Script Tests

| ID | Test | BR |
|----|------|----|
| T-MIG-01 | Script reads all `.md` files from memory directory — file count matches `ls \| wc -l` | BR-26 |
| T-MIG-02 | YAML frontmatter parsed correctly for files that have it — name, type, description extracted | BR-07 |
| T-MIG-03 | Files without frontmatter are still processed — content-only, no error | BR-26 |
| T-MIG-04 | Scope classification matches golden file for every memory file (deterministic, no LLM) | BR-27 |
| T-MIG-05 | Category classification matches golden file for every memory file | BR-27 |
| T-MIG-06 | Project/company association is correct for Maya, WabiSabi, Brainy, Shikki files | BR-08 |
| T-MIG-07 | POST to @db succeeds for each file — 201 response, UUID returned in body | BR-26 |
| T-MIG-08 | Idempotency: running script twice does not create duplicates — second run is all [SKIP] | BR-09 |
| T-MIG-09 | Verification report numbers match actual @db record count (query count after migration) | BR-28 |
| T-MIG-10 | Backup archive is created and contains all original files — `unzip -t` passes | BR-10 |
| T-MIG-11 | MEMORY.md is skipped — not migrated, not in backup, only rewritten | BR-26 |
| T-MIG-12 | Script exits non-zero if any file produces [ERR] | BR-28 |
| T-MIG-13 | `metadata.migratedFrom` is set to original filename on every record | BR-07 |

### T-PTR: MEMORY.md Pointer Tests

| ID | Test | BR |
|----|------|----|
| T-PTR-01 | New MEMORY.md is under 50 lines | BR-03 |
| T-PTR-02 | New MEMORY.md contains zero known PII — grep for name, email, financial terms returns empty | BR-11 |
| T-PTR-03 | New MEMORY.md contains zero strategy content — grep for fundraising, valuation, salary returns empty | BR-04 |
| T-PTR-04 | Claude Code parses pointer format and issues correct @db queries in a real session | BR-13 |
| T-PTR-05 | @db queries from pointers return at least 1 result per category | BR-13 |
| T-PTR-06 | Inline conventions section passes the "anyone can see this" checklist (10-item audit) | BR-12 |

### T-GIT: Git History Cleanup Tests

| ID | Test | BR |
|----|------|----|
| T-GIT-01 | `git log --all --diff-filter=A -- '*/memory/*.md'` returns empty after cleanup | BR-21 |
| T-GIT-02 | `git log --all -S "Jeoffrey Thirot"` returns empty (no memory files contain this after cleanup) | BR-22 |
| T-GIT-03 | `git log --all -S "contact@obyw.one"` returns empty | BR-22 |
| T-GIT-04 | Current HEAD still compiles / `swift build` passes | BR-21 |
| T-GIT-05 | All branches and tags are preserved — count matches pre-cleanup | BR-23 |
| T-GIT-06 | No non-memory files were removed — diff file count pre/post | BR-21 |
| T-GIT-07 | Dry run output reviewed and approved before executing real filter-repo | BR-21 |
| T-GIT-08 | Backup tar.gz exists and is readable before filter-repo executes | BR-21 |

### T-FALL: Fallback / Resilience Tests

| ID | Test | BR |
|----|------|----|
| T-FALL-01 | With @db running: query returns live data, cache file is updated with fresh timestamp | BR-24 |
| T-FALL-02 | With @db stopped: query returns cached data, degraded-mode banner displayed | BR-24 |
| T-FALL-03 | Cache staleness age is displayed correctly (matches `cachedAt` delta) | BR-24 |
| T-FALL-04 | Write queue buffers new memories when @db is down — `write-queue.jsonl` grows | BR-25 |
| T-FALL-05 | Write queue replays successfully when @db comes back — items cleared from queue | BR-25 |
| T-FALL-06 | 24h+ stale cache shows escalated `[!!]` warning | BR-24 |
| T-FALL-07 | Queue items older than 7 days moved to `write-queue-expired.jsonl` with warning | BR-25 |

### T-SCOPE: Scoping Tests (v1.1)

| ID | Test | BR |
|----|------|----|
| T-SCOPE-01 | Personal memories visible only to owning `user_id` | BR-17 |
| T-SCOPE-02 | Project memories visible to all users in the company owning the project | BR-19 |
| T-SCOPE-03 | Company memories visible to all company members | BR-17 |
| T-SCOPE-04 | Global memories visible to all authenticated users | BR-17 |
| T-SCOPE-05 | User A cannot see User B's personal memories via any API path — 403 or empty result | BR-17 |
| T-SCOPE-06 | User in Company A (OBYW.one) cannot see Company B's (FJ Studio personal-scope) memories | BR-18 |
| T-SCOPE-07 | RLS policies enforce scoping even with direct SQL access (bypass API layer) | BR-17 |
| T-SCOPE-08 | Scope downgrade rejected — cannot change `personal` to `project` without explicit action | BR-20 |
| T-SCOPE-09 | "Load all relevant context" query returns union of personal + project + company + global | BR-18 |
| T-SCOPE-10 | Faustin querying Maya backlog returns full backlog — all project-scope Maya memories | BR-18 |
| T-SCOPE-11 | Faustin querying context returns zero OBYW.one personal/company memories | BR-17 |

### T-ID: Identity Tests (v1.1)

| ID | Test | BR |
|----|------|----|
| T-ID-01 | `shikki identity init` creates `~/.config/shikki/identity.json` with UUID | BR-14 |
| T-ID-02 | `shikki identity init` registers user in @db `users` table — record verifiable via query | BR-16 |
| T-ID-03 | `shikki identity show` displays current identity — all fields visible | BR-16 |
| T-ID-04 | `shikki identity edit` updates both local file and @db record | BR-16 |
| T-ID-05 | Missing `identity.json` triggers: `"Identity not configured. Run: shikki identity init"` | BR-15 |
| T-ID-06 | `SHIKKI_USER_ID` env var overrides `identity.json` — useful for CI | BR-15 |
| T-ID-07 | `shikki identity init` is idempotent — shows current identity + edit prompt if already exists | BR-16 |
| T-ID-08 | Full init wizard completes in under 30 seconds (measured on first run) | BR-16 |

### T-INT: Integration Tests

| ID | Test | BR |
|----|------|----|
| T-INT-01 | Full flow: `shikki migrate memory` → verify → rewrite MEMORY.md → new session loads from @db | BR-26 |
| T-INT-02 | `shikki doctor` reports: identity OK, @db reachable, memories migrated, git history clean | BR-21 |
| T-INT-03 | `shikki search` returns results from @db — not from deleted memory files | BR-13 |
| T-INT-04 | Context compaction saves to @db with correct scope and user metadata | BR-07 |
| T-INT-05 | Git cleanup does not break `shikki doctor` or any existing `shikki` commands | BR-21 |

---

## DB Schema Changes — Migration 008

```sql
-- New tables: users, companies, memberships, project-company associations

CREATE TABLE users (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL,
    handle     TEXT UNIQUE NOT NULL,  -- @daimyo, @faustin
    email      TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata   JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE companies (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug       TEXT NOT NULL UNIQUE,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata   JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE company_members (
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role       TEXT NOT NULL DEFAULT 'member'
                   CHECK (role IN ('owner', 'co-founder', 'admin', 'member')),
    joined_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (company_id, user_id)
);

CREATE TABLE project_companies (
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    PRIMARY KEY (project_id, company_id)
);

-- Extend agent_memories with scoping columns
ALTER TABLE agent_memories
    ADD COLUMN IF NOT EXISTS user_id    UUID REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id),
    ADD COLUMN IF NOT EXISTS scope      TEXT NOT NULL DEFAULT 'global'
        CHECK (scope IN ('personal', 'project', 'company', 'global'));

CREATE INDEX idx_memories_user_id    ON agent_memories(user_id);
CREATE INDEX idx_memories_company_id ON agent_memories(company_id);
CREATE INDEX idx_memories_scope      ON agent_memories(scope);

-- Row-Level Security (enabled in migration 009 after identity system is live)
-- ALTER TABLE agent_memories ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY memories_personal ON agent_memories
--     FOR ALL USING (scope != 'personal' OR user_id = current_setting('app.current_user_id')::uuid);
```

---

## Implementation Waves

| Wave | Scope | Deliverables | Estimate |
|------|-------|-------------|---------|
| **Wave 1** | Migration script | `shikki migrate memory`, classification golden file, verification report | 1 day |
| **Wave 2** | MEMORY.md rewrite | New pointer format, inline conventions only, PII audit pass | 0.5 day |
| **Wave 3** | Git cleanup | Backup, `git filter-repo` execution, force push, re-clone notice | 0.5 day |
| **Wave 4** | DB schema 008 | Users, companies, memberships, scope column, indexes | 0.5 day |
| **Wave 5** | Identity system | `shikki identity init/show/edit`, `identity.json`, doctor checks | 1 day |
| **Wave 6** | Fallback cache | Local cache, write queue, degraded mode banner, staleness warning | 1 day |
| **Wave 7** | RLS policies | Scoped queries, access control tests, T-SCOPE suite | 1 day |

**Total**: ~5.5 days. Waves 1-3 = v1.0 (migration). Waves 4-7 = v1.1 (identity + scoping).

---

## Risk Register

| Risk | Prob | Impact | Mitigation |
|------|------|--------|-----------|
| Migration misses a file | Low | High | Automated audit: diff directory listing vs @db `migratedFrom` values |
| Git rewrite breaks CI / branches | Medium | High | All branches pushed pre-rewrite, full backup, re-clone procedure documented |
| Claude Code can't parse pointer format | Low | Medium | Test in real session before deleting originals (T-PTR-04) |
| @db down during critical session | Medium | Medium | Local cache + write queue + degraded mode (T-FALL suite) |
| Collaborator pushes from old clone after rewrite | Medium | High | `shikki doctor` warns on SHA divergence; team announcement required |
| Scope misclassification exposes private data | Low | Critical | Golden file test for every memory file's expected scope (T-MIG-04) |
| @db data loss post-migration | Low | Critical | 90-day backup archive of original files (BR-10) |

---

## Decision Log

| Decision | Chosen | Alternatives Considered | Rationale |
|----------|--------|------------------------|----------|
| Git cleanup tool | `git filter-repo` | BFG, `git filter-branch` | Fastest, maintained, Git project recommends it |
| Identity storage | `~/.config/shikki/identity.json` | Machine fingerprint, env vars only | Explicit, portable, user-controlled, extensible to v2 auth tokens |
| Scope model | 4 levels: personal/project/company/global | 2-level (private/shared), 3-level (no company) | Matches real topology: 4 companies, shared projects (Maya = FJ Studio + OBYW.one) |
| Fallback | Local cache + write queue | Memory files as fallback, no fallback | Cache is fresh enough; memory files would reintroduce the security problem |
| RLS | DB-level (v1.1) | API middleware only | Defense in depth — DB enforces rules even if API has bugs |
| Migration scope | ALL memory/*.md | Selective migration | Clean break. No half-measures with sensitive data. |
| Classification | Deterministic filename rules | LLM-based classification | Reproducible, testable, no API cost, works offline |
