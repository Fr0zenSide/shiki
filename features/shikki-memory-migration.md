# Shikki Memory Migration to ShikiDB + Multi-User Scoping

> **Status**: Spec v1.0 — Phase 1-4 complete
> **Priority**: P0 SECURITY BLOCKER
> **Author**: @Sensei + full @shi team brainstorm
> **Date**: 2026-03-27
> **Blocks**: Any public release, open-source push, or collaborator onboarding

---

## Phase 1: Team Brainstorm

### @Sensei (Architecture)

**1. Data Model: Identity + Scoping**
The current `agent_memories` table has no concept of "who wrote this" or "who can see it". Every memory belongs to a `project_id` — but personal preferences, business strategy, and competitive intelligence don't belong to any project. They belong to a *person* or a *company*. We need three new dimensions:

- **`user_id`** — who created/owns this memory (nullable for legacy/global)
- **`scope`** — enum: `personal | project | company | global`
- **`company_id`** — which company context (OBYW.one, FJ Studio, C-Tech, Games)

This maps cleanly to the existing `projects` table (project scope) while adding user and company layers above it.

**2. MEMORY.md as Query Template**
MEMORY.md should become a *routing file* — not data storage. It tells Claude Code: "when you need X, query @db with these parameters." The file contains no secrets, no strategy, no PII. Just pointers:

```markdown
## How to load context
- Backlog: POST /api/memories/search { category: "backlog", scope: "company", companyId: "<OBYW>" }
- User preferences: POST /api/memories/search { category: "preference", scope: "personal", userId: "<current>" }
- Architecture decisions: POST /api/memories/search { category: "decision", scope: "project", projectId: "<current>" }
```

**3. User Identity Resolution**
Who is the current user? Three options:
- **Machine fingerprint** (hostname + username) — simplest, no auth, works offline. v1 choice.
- **Config file** (`~/.config/shikki/identity.json` with `userId`, `name`, `companies[]`) — v1.1.
- **API key / token** — v2, when multi-machine / remote access exists.

v1 decision: `~/.config/shikki/identity.json` created on first run (`shikki doctor` or `shikki init`). Contains user UUID that maps to a `users` row in @db.

### @Katana (Security)

**1. Git History Cleanup**
The `.claude/projects/` memory directory is git-tracked by Claude Code's own mechanism, but if any of these files have ever been committed to the shiki repo itself (features, docs, or symlinks), they live in git history forever. Tools ranked:

| Tool | Pros | Cons | Verdict |
|------|------|------|---------|
| `git filter-repo` | Fast, Python, actively maintained, handles all edge cases | Rewrites all SHAs | **Winner** |
| BFG Repo Cleaner | Simple CLI, fast | Java dependency, less maintained | Backup option |
| `git filter-branch` | Built-in | Extremely slow, deprecated by Git project | Never use |

Procedure: `git filter-repo --path-glob '*/memory/*.md' --invert-paths` + force-push + all collaborators re-clone.

**2. Sensitive Content Audit**
Files that MUST be removed from git history:

| Category | Files | Risk Level |
|----------|-------|------------|
| **PII** | `user_identity.md`, `user_profile-extended.md`, `email-signature.md` | CRITICAL |
| **Business strategy** | `project_ial-maya-fundraising.md`, `project_maya-prelaunch-strategy.md`, `project_haiku-conversion-strategy.md` | HIGH |
| **Competitive intel** | `reference_*-radar.md`, `reference_openfang-ideas.md`, `reference_skills-ecosystem-analysis.md` | HIGH |
| **Infrastructure secrets** | `object-storage.md`, `project_backlog-backup-strategy.md` | MEDIUM |
| **Financial context** | `user_profile-extended.md` (salary, financial struggles) | CRITICAL |
| **Outreach/contacts** | `media-strategy.md`, `project_maplibre-security-concern.md` | MEDIUM |
| **All feedback_*.md** | Personal workflow preferences, tool opinions | LOW (but cumulative exposure) |
| **All project_*.md** | Business plans, architecture decisions, vision docs | HIGH |

**Verdict**: Remove ALL `memory/*.md` from git history. Zero exceptions. The directory should never have been tracked.

**3. Access Control in @db**
Row-Level Security (RLS) in PostgreSQL is the right tool:

- `personal` scope: only the owning `user_id` can read/write
- `project` scope: any user with membership in that project's company
- `company` scope: any user in that company
- `global` scope: everyone (generic conventions, tool docs)

RLS policies enforce this at the database level — even if the API has a bug, data doesn't leak. Encryption at rest is PostgreSQL's `pgcrypto` or volume-level encryption (Colima's VM disk). Not a v1 blocker but a v1.1 addition.

### @Shogun (Market Research)

**1. How Others Handle Multi-User Knowledge**
- **Notion**: Workspace = company. Pages have permissions (private, team, public). Guest access for external collaborators. Personal pages are invisible to workspace admins.
- **Linear**: Team-scoped by default. Personal views and filters exist but all issues are team-visible. No private issues.
- **Obsidian**: Local-first, no multi-user. Obsidian Publish is one-way. Teams use git + merge conflicts.
- **Cursor/Claude Code**: Per-machine `.claude/` directory. No multi-user concept at all. This is where we are today.
- **Mem.ai / Mem X**: Personal knowledge base with "shared spaces" for teams. Closest to our target model.

**Takeaway**: The Notion model (workspace + personal pages + guest access) is the proven pattern. We should adopt it: company = workspace, project = team, personal = private pages.

**2. Shared vs Private Boundaries**
The line is simple: *if it helps others do their job, share it. If it's about you or your strategy, keep it private.*

| Shared (company/project) | Private (personal) |
|--------------------------|-------------------|
| Architecture decisions | Financial situation |
| API schemas, DB models | Competitive radar |
| Sprint plans, backlogs | Outreach strategy |
| Bug reports, test results | Personal preferences |
| Convention docs | Contact lists |
| Feature specs | Fundraising plans |
| Agent persona definitions | User identity/PII |

### @Hanami (UX)

**1. `shikki identity` Flow**
First run experience (or triggered by `shikki doctor`):

```
$ shikki init

  Welcome to Shikki.

  Let's set up your identity.

  Name: Jeoffrey Thirot
  Email: contact@obyw.one
  Company: OBYW.one

  Identity saved to ~/.config/shikki/identity.json
  Registered in ShikiDB as user [uuid]

  You can update this anytime with `shikki identity edit`.
```

No passwords in v1. Identity is trust-based (you're on your own machine). v2 adds auth tokens for remote access.

**2. What Faustin Sees vs What @Daimyo Sees**
Both run `shikki status` on the Maya project:

| Element | @Daimyo sees | Faustin sees |
|---------|-------------|-------------|
| Maya backlog | Full backlog | Full backlog |
| Maya architecture decisions | All | All |
| Sprint progress | All | All |
| OBYW.one strategy | Yes (personal) | **No** (different company) |
| Fundraising plans | Yes (personal) | **No** |
| @Daimyo's preferences | Yes | **No** |
| Faustin's preferences | **No** | Yes |
| Shared conventions | Yes | Yes |
| Agent personas (@shi) | Yes (company-level) | Yes (if FJ Studio shares them) |

The key insight: Maya is an **FJ Studio** project. Both @Daimyo and Faustin are members of FJ Studio. They share Maya project knowledge. But @Daimyo's OBYW.one knowledge (WabiSabi, Brainy, Flsh, fundraising) is invisible to Faustin. And Faustin's personal notes are invisible to @Daimyo.

### @Kintsugi (Philosophy)

**Personal knowledge is a private garden. Shared knowledge is a public square. The boundary is respect, not walls.**

The migration should feel like moving from a shared house where everyone's diary is on the kitchen table to a proper home where each person has their own room but the living room is shared. The architecture should encode *trust* — not paranoia. Personal memories are private because they deserve privacy, not because we fear the other person.

When Faustin queries Maya knowledge, he should feel like a full participant, not a guest with restricted access. The scoping should be invisible in the happy path — you only notice it when you try to access something that isn't yours.

### @Ronin (Adversarial)

**1. @db Unreachable — Fallback Strategy**
If ShikiDB is down, Shikki must not become amnesiac. Options:
- **Local cache**: `~/.cache/shikki/memory-snapshot.json` — last-known-good dump of relevant memories, refreshed on every successful @db query. Read-only fallback.
- **Degraded mode banner**: `[!] ShikiDB unreachable — running with cached memory (2h stale)`. Never silently use stale data.
- **Write queue**: If @db is down, buffer new memories to `~/.cache/shikki/write-queue.jsonl`. Replay on reconnect. FIFO, no dedup needed (DB handles idempotency via UUIDs).

**2. Migration Risks**
| Risk | Mitigation |
|------|-----------|
| Miss a sensitive file in migration | Audit script that diffs memory/ contents against @db after migration. Any file not migrated = error. |
| Git rewrite breaks existing branches | Pre-migration: all collaborators merge/push their branches. Post-rewrite: everyone re-clones. Document the cutover. |
| `git filter-repo` removes too much | Dry-run first (`--dry-run`). Backup full repo before rewrite. |
| @db data loss after migration | memory/*.md files archived in a private, non-git location (encrypted zip) for 90 days post-migration. |
| Claude Code can't read @db pointers | Test MEMORY.md pointer format with Claude Code before deleting originals. Verify the search API returns expected results. |

---

## Phase 2: Feature Brief

### Scope

**v1.0 — Migration + Pointer System** (this spec)
- Migration script: read all `memory/*.md`, classify, POST to @db with proper scope/category
- New MEMORY.md format: query pointers only, zero sensitive data
- Git history cleanup: remove all `memory/*.md` from history
- Local cache fallback when @db unreachable
- `shikki doctor` checks: @db reachable, identity configured, memories migrated

**v1.1 — User Identity + Scoping**
- `users` and `companies` tables in @db
- `~/.config/shikki/identity.json` with user UUID
- `shikki identity init/edit/show` commands
- Row-Level Security policies on `agent_memories`
- Memory queries automatically scoped to current user + their companies
- `shikki identity` first-run wizard

**v2.0 — Multi-User ACL + Company Boundaries**
- Company membership management (`shikki company invite/remove`)
- Project-company association
- Auth tokens for remote/multi-machine access
- Encryption at rest for personal-scope memories
- Audit log: who accessed what memory when
- Master/slave sync (company VPS = master, dev machines = slaves)

### Out of Scope
- UI/TUI for browsing memories (use existing `shikki search`)
- Automatic memory creation from conversations (existing system, unchanged)
- Agent persona management (separate spec)
- ShikiMCP changes (consumes @db, not affected by schema changes)

---

## Phase 3: Business Rules

### Rule 1: What Stays in memory/*.md

ONLY generic, non-sensitive conventions that help ANY Claude Code session on this repo:

```
# Allowed in memory/*.md (post-migration)
- SPM package structure conventions
- Branching strategy (git flow description)
- Test conventions (no print, one sim, etc.)
- Agent aliases (@shi, @t, @db, etc.) — names only, not persona details
- Tool preferences (Colima not Docker Desktop, LM Studio URL)
- MEMORY.md itself (as query pointer file)
```

Everything else moves to @db. When in doubt, move it.

### Rule 2: What Moves to @db

ALL of the following categories, with their target scope:

| Category | Scope | Example Files |
|----------|-------|--------------|
| User identity/PII | `personal` | `user_identity.md`, `user_profile-extended.md` |
| User preferences | `personal` | `feedback_*.md` (all 44 files), `user_media-language-preferences.md` |
| Business strategy | `personal` | `project_ial-maya-fundraising.md`, `project_maya-prelaunch-strategy.md` |
| Competitive intel | `personal` | `reference_*-radar.md`, `reference_openfang-ideas.md` |
| Project backlogs | `project` | `maya-backlog.md`, `project_wabisabi-backlog.md` |
| Architecture decisions | `project` | `project_autopilot-reactor-decision.md`, `project_context-optimization-decision.md` |
| Project plans | `project` | `project_shiki-v1-wave-plan.md`, `project_wabisabi-spm-migration-plan.md` |
| Vision docs | `company` | `project_shiki-vision-full-topology.md`, `project_shiki-thesis.md` |
| Infrastructure notes | `company` | `object-storage.md`, `project_backlog-backup-strategy.md` |
| Media/marketing strategy | `company` | `media-strategy.md`, `project_haiku-conversion-strategy.md` |
| Email/outreach | `personal` | `email-signature.md` |
| Agent skills audit | `company` | `project_agent-skills-audit-2026-03.md` |
| Research references | `company` | `reference_qmd-search-engine.md`, `reference_skills-ecosystem-analysis.md` |

### Rule 3: MEMORY.md New Format

Post-migration, MEMORY.md becomes a routing file:

```markdown
# Shikki Memory — Query Pointers

> This file contains NO sensitive data. All knowledge is stored in ShikiDB.
> Claude: use these queries to load context at session start.

## Identity
Search @db: `POST /api/memories/search` with `{ "scope": "personal", "category": "identity" }`

## User Preferences
Search @db: `POST /api/memories/search` with `{ "scope": "personal", "category": "preference" }`

## Current Backlog
Search @db: `POST /api/memories/search` with `{ "scope": "project", "category": "backlog", "projectSlug": "<detected-from-git>" }`

## Architecture Decisions
Search @db: `POST /api/memories/search` with `{ "scope": "project", "category": "decision" }`

## Company Vision
Search @db: `POST /api/memories/search` with `{ "scope": "company", "category": "vision" }`

## Conventions (inline — safe for git)
- Branching: git flow (main <- release/* <- develop <- feature/*)
- All PRs target develop, never main
- SPM packages in packages/, projects in projects/
- Testing: one simulator (latest iOS), no benchmark theater
- Agent aliases: @shi/@t = team, @db = ShikiDB
- Docker: Colima, not Docker Desktop
- LM Studio: http://127.0.0.1:1234
```

### Rule 4: User Identity Model

**v1 (local, trust-based):**

```json
// ~/.config/shikki/identity.json
{
  "userId": "uuid-generated-on-init",
  "name": "Jeoffrey Thirot",
  "email": "contact@obyw.one",
  "companies": [
    { "id": "uuid", "slug": "obyw-one", "name": "OBYW.one", "role": "owner" },
    { "id": "uuid", "slug": "fj-studio", "name": "FJ Studio", "role": "co-founder" }
  ],
  "defaultCompany": "obyw-one",
  "createdAt": "2026-03-27T00:00:00Z"
}
```

**Resolution order**: `identity.json` > `SHIKKI_USER_ID` env var > error ("run `shikki identity init`").

### Rule 5: Data Scoping Levels

| Scope | Visibility | Example | DB Filter |
|-------|-----------|---------|-----------|
| `personal` | Only the owning user | Financial situation, personal radar | `WHERE user_id = $current AND scope = 'personal'` |
| `project` | All users with access to the project | Maya backlog, architecture decisions | `WHERE project_id = $project AND scope = 'project'` |
| `company` | All users in the company | OBYW.one vision, infrastructure notes | `WHERE company_id = $company AND scope = 'company'` |
| `global` | Everyone | Generic conventions, tool docs | `WHERE scope = 'global'` |

**Inheritance**: A query for "all relevant memories" returns: `personal` (mine) + `project` (current project) + `company` (my companies) + `global`.

### Rule 6: Git History Cleanup Procedure

**Prerequisites:**
1. All collaborators push all branches
2. Full repo backup: `tar czf shiki-backup-$(date +%Y%m%d).tar.gz .git/`
3. Migration script has run successfully (all memories in @db)
4. Verification: every memory file has a corresponding @db record

**Execution:**
```bash
# Step 1: Install git-filter-repo
pip3 install git-filter-repo

# Step 2: Dry run — see what would change
git filter-repo --path-glob '*.claude/projects/*/memory/*.md' --invert-paths --dry-run

# Step 3: Also target any memory files that may have been committed to repo root
git filter-repo --path-glob 'memory/*.md' --invert-paths --dry-run

# Step 4: Execute (combines both patterns)
git filter-repo \
  --path-glob '.claude/projects/*/memory/*.md' \
  --path-glob 'memory/*.md' \
  --invert-paths \
  --force

# Step 5: Force push all branches
git push origin --force --all
git push origin --force --tags

# Step 6: All collaborators re-clone
# (document this in a team announcement)
```

**Post-cleanup verification:**
```bash
# Verify no memory files exist in any commit
git log --all --diff-filter=A -- '*.claude/projects/*/memory/*.md' 'memory/*.md'
# Should return empty
```

### Rule 7: Fallback When @db Unreachable

1. **On every successful @db query**: update local cache at `~/.cache/shikki/memory-cache.json`
   - Cache contains: last 100 personal memories, last 50 per active project, all global
   - Cache includes timestamp: `"cachedAt": "2026-03-27T14:00:00Z"`

2. **On @db connection failure**:
   - Read from cache
   - Display banner: `[!] ShikiDB offline — using cached memory (age: 2h 15m)`
   - Log event to `~/.cache/shikki/write-queue.jsonl` for later sync

3. **On @db reconnection**:
   - Replay write queue (FIFO)
   - Refresh cache
   - Clear banner

4. **Cache staleness threshold**: 24 hours. After 24h without @db, warn: `[!!] Memory cache is 24h+ stale. Some context may be outdated.`

5. **Never fall back to memory/*.md files**. Once migrated, those files are gone. The cache is the only fallback.

### Rule 8: Migration Script Requirements

**Script**: `scripts/migrate-memory-to-db.sh` (or Swift CLI command `shikki migrate memory`)

**Input**: `~/.claude/projects/-Users-jeoffrey-Documents-Workspaces-shiki/memory/*.md`

**Steps per file:**
1. Read file content
2. Parse YAML frontmatter (name, description, type)
3. Classify scope based on filename prefix and content:
   - `user_*` -> `personal`
   - `feedback_*` -> `personal` (user preferences)
   - `project_*` -> determine by content (project/company/personal)
   - `reference_*` -> `company` (shared intel) or `personal` (competitive radar)
   - `media-strategy.md` -> `company`
   - `maya-backlog.md` -> `project` (Maya project)
   - `email-signature.md` -> `personal`
   - `MEMORY.md` -> skip (will be rewritten as pointer file)
4. Determine `category`:
   - Filename-based: `feedback_*` -> `preference`, `project_*-backlog*` -> `backlog`, `reference_*` -> `reference`, `project_*-decision*` -> `decision`, `project_*-plan*` -> `plan`, `project_*-vision*` -> `vision`
5. Determine `project_id` and `company_id`:
   - Maya files -> FJ Studio company, Maya project
   - WabiSabi files -> OBYW.one company, WabiSabi project
   - Shiki/Shikki files -> OBYW.one company, Shikki project
   - Brainy files -> OBYW.one company, Brainy project
   - Generic files -> OBYW.one company, no specific project
6. POST to `/api/memories` with:
   ```json
   {
     "content": "<full file content>",
     "category": "<classified>",
     "projectId": "<uuid or null>",
     "metadata": {
       "scope": "<personal|project|company|global>",
       "userId": "<current user uuid>",
       "companyId": "<uuid or null>",
       "migratedFrom": "memory/<filename>.md",
       "migratedAt": "2026-03-27T...",
       "originalFrontmatter": { "name": "...", "type": "..." }
     }
   }
   ```
7. Log result: `[OK] feedback_testing-strategy.md -> personal/preference (uuid)`
8. After all files: generate verification report

**Verification report:**
```
Migration complete: 95/96 files processed (1 skipped: MEMORY.md)
  personal: 48 memories
  project:  27 memories
  company:  18 memories
  global:    2 memories
Errors: 0
```

**Idempotency**: Check `metadata.migratedFrom` before inserting. Skip if already exists. Safe to re-run.

**Rollback**: Keep original files in `~/.cache/shikki/memory-migration-backup/` (encrypted zip). Delete after 90 days.

---

## Phase 4: Test Plan

### Migration Script Tests

- [ ] **T-MIG-01**: Script reads all `.md` files from memory directory (count matches `ls | wc -l`)
- [ ] **T-MIG-02**: YAML frontmatter is parsed correctly for files that have it
- [ ] **T-MIG-03**: Files without frontmatter are still processed (content-only)
- [ ] **T-MIG-04**: Scope classification matches expected mapping for every file (golden file test)
- [ ] **T-MIG-05**: Category classification matches expected mapping for every file
- [ ] **T-MIG-06**: Project/company association is correct for Maya, WabiSabi, Brainy, Shikki files
- [ ] **T-MIG-07**: POST to @db succeeds for each file (201 response)
- [ ] **T-MIG-08**: Idempotency: running script twice does not create duplicates
- [ ] **T-MIG-09**: Verification report numbers match actual @db record count
- [ ] **T-MIG-10**: Backup archive is created and contains all original files
- [ ] **T-MIG-11**: MEMORY.md is skipped (not migrated)

### MEMORY.md Pointer Tests

- [ ] **T-PTR-01**: New MEMORY.md contains zero PII (grep for known names, emails, amounts)
- [ ] **T-PTR-02**: New MEMORY.md contains zero file paths to sensitive content
- [ ] **T-PTR-03**: Claude Code can parse pointer format and issue correct @db queries
- [ ] **T-PTR-04**: @db queries from pointers return expected results (at least 1 result per category)
- [ ] **T-PTR-05**: Inline conventions section contains only generic, non-sensitive info

### Git History Cleanup Tests

- [ ] **T-GIT-01**: `git log --all --diff-filter=A -- 'memory/*.md'` returns empty after cleanup
- [ ] **T-GIT-02**: `git log --all -S "Jeoffrey Thirot" -- 'memory/*.md'` returns empty
- [ ] **T-GIT-03**: `git log --all -S "contact@obyw.one" -- 'memory/*.md'` returns empty
- [ ] **T-GIT-04**: Current HEAD still compiles / passes existing tests
- [ ] **T-GIT-05**: All branches and tags are preserved (count matches pre-cleanup)
- [ ] **T-GIT-06**: No non-memory files were removed (diff file count pre/post)

### @db Fallback Tests

- [ ] **T-FALL-01**: With @db running: query returns live data, cache is updated
- [ ] **T-FALL-02**: With @db stopped: query returns cached data, banner is displayed
- [ ] **T-FALL-03**: Cache staleness age is displayed correctly
- [ ] **T-FALL-04**: Write queue buffers new memories when @db is down
- [ ] **T-FALL-05**: Write queue replays successfully when @db comes back
- [ ] **T-FALL-06**: 24h+ stale cache shows escalated warning

### Scoping Tests (v1.1)

- [ ] **T-SCOPE-01**: Personal memories visible only to owning user
- [ ] **T-SCOPE-02**: Project memories visible to all users with project access
- [ ] **T-SCOPE-03**: Company memories visible to all company members
- [ ] **T-SCOPE-04**: Global memories visible to all users
- [ ] **T-SCOPE-05**: User A cannot see User B's personal memories via any API path
- [ ] **T-SCOPE-06**: User in Company A cannot see Company B's memories
- [ ] **T-SCOPE-07**: RLS policies enforce scoping even with direct SQL (bypass API)

### Identity Tests (v1.1)

- [ ] **T-ID-01**: `shikki identity init` creates `~/.config/shikki/identity.json`
- [ ] **T-ID-02**: `shikki identity init` registers user in @db `users` table
- [ ] **T-ID-03**: `shikki identity show` displays current identity
- [ ] **T-ID-04**: `shikki identity edit` updates both local file and @db
- [ ] **T-ID-05**: Missing identity.json triggers helpful error with `shikki identity init` suggestion
- [ ] **T-ID-06**: `SHIKKI_USER_ID` env var overrides identity.json (for CI/automation)

### Integration Tests

- [ ] **T-INT-01**: Full flow: migrate -> verify -> cleanup git -> new session loads from @db
- [ ] **T-INT-02**: `shikki doctor` reports: identity OK, @db reachable, memories migrated, git clean
- [ ] **T-INT-03**: `shikki search` returns results from @db (not from memory/*.md files)
- [ ] **T-INT-04**: Context compaction saves to @db with correct scope

---

## DB Schema Changes Required

### Migration 008: Users, Companies, and Memory Scoping

```sql
-- New tables
CREATE TABLE users (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL,
    email      TEXT UNIQUE,
    handle     TEXT UNIQUE NOT NULL,  -- @Daimyo, @Faustin
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
    role       TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (company_id, user_id)
);

CREATE TABLE project_companies (
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    PRIMARY KEY (project_id, company_id)
);

-- Extend agent_memories
ALTER TABLE agent_memories
    ADD COLUMN IF NOT EXISTS user_id    UUID REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id),
    ADD COLUMN IF NOT EXISTS scope      TEXT NOT NULL DEFAULT 'global'
        CHECK (scope IN ('personal', 'project', 'company', 'global'));

CREATE INDEX idx_memories_user    ON agent_memories(user_id);
CREATE INDEX idx_memories_company ON agent_memories(company_id);
CREATE INDEX idx_memories_scope   ON agent_memories(scope);

-- Row-Level Security (v1.1)
-- ALTER TABLE agent_memories ENABLE ROW LEVEL SECURITY;
-- Policies added in migration 009 after identity system is live
```

### Seed Data

```sql
-- Users
INSERT INTO users (id, name, email, handle) VALUES
    ('00000000-0000-0000-0000-000000000001', 'Jeoffrey Thirot', 'contact@obyw.one', 'daimyo');

-- Companies
INSERT INTO companies (id, slug, name) VALUES
    ('00000000-0000-0000-0000-000000000010', 'obyw-one', 'OBYW.one'),
    ('00000000-0000-0000-0000-000000000020', 'fj-studio', 'FJ Studio'),
    ('00000000-0000-0000-0000-000000000030', 'c-tech', 'C-Tech'),
    ('00000000-0000-0000-0000-000000000040', 'games', 'Games');

-- Memberships
INSERT INTO company_members (company_id, user_id, role) VALUES
    ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', 'owner'),
    ('00000000-0000-0000-0000-000000000020', '00000000-0000-0000-0000-000000000001', 'co-founder');

-- Project-Company associations
-- (map existing project UUIDs to companies)
```

---

## Implementation Waves

| Wave | Scope | Deliverables | Estimate |
|------|-------|-------------|----------|
| **Wave 1** | Migration script | `scripts/migrate-memory-to-db.sh`, classification map, verification report | 1 day |
| **Wave 2** | MEMORY.md rewrite | New pointer format, inline conventions only | 0.5 day |
| **Wave 3** | Git cleanup | `git filter-repo` execution, force push, collaborator notification | 0.5 day |
| **Wave 4** | DB schema (008) | Users, companies, scope column, indexes | 0.5 day |
| **Wave 5** | Identity system | `shikki identity init/show/edit`, `identity.json`, doctor checks | 1 day |
| **Wave 6** | Fallback cache | Local cache, write queue, degraded mode banner | 1 day |
| **Wave 7** | RLS policies | Row-level security, scoped queries, access control tests | 1 day |

**Total**: ~5.5 days. Waves 1-3 are v1.0 (migration). Waves 4-5 are v1.1 (identity). Waves 6-7 are v1.1 (resilience + ACL).

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Migration misses a file | Low | High | Automated audit script compares file list vs @db records |
| Git rewrite breaks CI/branches | Medium | High | All branches pushed before rewrite, full backup, re-clone procedure documented |
| Claude Code can't parse pointer format | Low | Medium | Test with real Claude Code session before deleting originals |
| @db down during critical session | Medium | Medium | Local cache + write queue + degraded mode |
| Collaborator doesn't re-clone after rewrite | Medium | Low | Clear announcement + `shikki doctor` warns about diverged history |
| Scope misclassification exposes private data | Low | Critical | Golden file test for every memory file's expected scope |

---

## Decision Log

| Decision | Chosen | Alternatives Considered | Rationale |
|----------|--------|------------------------|-----------|
| Git cleanup tool | `git filter-repo` | BFG, `git filter-branch` | Fastest, maintained, recommended by Git project |
| Identity storage | `~/.config/shikki/identity.json` | Machine fingerprint, env vars | Explicit, portable, user-controlled |
| Scope model | 4 levels (personal/project/company/global) | 2 levels (private/shared), 3 levels (no company) | Matches real topology (4 companies, shared projects) |
| Fallback strategy | Local cache + write queue | Memory files as fallback, no fallback | Cache is fresh enough, files would reintroduce the security problem |
| RLS vs API-level auth | RLS (v1.1) | API middleware only | Defense in depth — DB enforces rules even if API has bugs |
| Migration target | All memory/*.md except MEMORY.md | Selective migration | Clean break. No half-measures with sensitive data. |
