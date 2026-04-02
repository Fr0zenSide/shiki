# Radar: Claude Code Memory + HUD Plugins

**Date**: 2026-04-02
**Analyst**: @Sensei
**Scope**: Competitive intelligence on 3 Claude Code plugins for Shikki memory/observability

---

## 1. claude-mem (44.6k stars)

**Repo**: https://github.com/thedotmack/claude-mem
**Author**: Alex Newman (@thedotmack)
**Language**: TypeScript | **License**: AGPL-3.0 | **Version**: 10.4.1
**Created**: 2025-08-31 | **Last updated**: 2026-04-02

### What It Does

Persistent memory compression system for Claude Code. Automatically captures everything Claude does during sessions (every tool use), compresses observations via Claude Agent SDK, stores in SQLite + ChromaDB, and injects relevant context into future sessions.

### Architecture Deep Dive

**Storage**: SQLite + FTS5 at `~/.claude-mem/claude-mem.db` (WAL mode). Optional ChromaDB for vector/semantic search.

**Schema** (4 core tables):
- `sdk_sessions` -- session lifecycle tracking
- `observations` -- individual tool executions with hierarchical fields (title, subtitle, narrative, text, facts, concepts, type, files_read, files_modified). Types: decision, bugfix, feature, refactor, discovery, change
- `session_summaries` -- AI-generated summaries (request, investigated, learned, completed, next_steps, notes)
- `user_prompts` -- raw user prompts for FTS5 search

All tables have FTS5 virtual table counterparts for full-text search.

**5 Lifecycle Hooks**:
1. SessionStart -- inject context from prior sessions (progressive disclosure index)
2. UserPromptSubmit -- create session record, save raw prompt
3. PostToolUse -- capture tool executions, send to worker for AI compression (fires 100+ times per session)
4. Stop -- generate session summary
5. SessionEnd -- mark session complete

**Worker Service**: Express.js HTTP server on port 37777, managed by Bun. 22 HTTP endpoints. Processes observations asynchronously via Claude Agent SDK. Web viewer UI at localhost:37777 with real-time SSE stream.

**MCP Search**: 4 MCP tools following a 3-layer progressive disclosure workflow:
1. `search` -- compact index with IDs (~50-100 tokens/result)
2. `timeline` -- chronological context around a result
3. `get_observations` -- full details for filtered IDs (~500-1000 tokens/result)
4. `__IMPORTANT` -- teaches Claude the 3-layer pattern

**Progressive Disclosure**: Core philosophy. Session start injects a compact index (~800 tokens for 50 observations) instead of dumping all context (~35k tokens). Agent decides what to fetch. Claims ~10x token savings over traditional RAG.

**Endless Mode (Beta)**: Biomimetic memory for extended sessions. Replaces tool outputs with compressed observations inline. O(N) instead of O(N^2) complexity. Blocking save-hook with 90s timeout. Experimental, not production-validated.

### Patterns to Steal

1. **Progressive disclosure index format**. The compact index with type icons, token cost per observation, and IDs is elegant. ShikiDB search returns full results; we could add a "light mode" that returns index-only with IDs, letting the agent fetch details selectively. Token cost visibility is a smart pattern -- show the agent how much budget each fetch will cost.

2. **3-layer search workflow (search -> timeline -> get_observations)**. The timeline tool is particularly clever -- it gives chronological context around a specific observation, answering "what was happening around that decision?" ShikiDB currently lacks a timeline/neighborhood query.

3. **PostToolUse observation capture**. We do not capture tool-level observations at all. Shikki tracks at the spec/decision/plan level. claude-mem captures at the individual tool execution level, which enables fine-grained "what did Claude actually do?" audit trail. This feeds their observation type taxonomy (decision, bugfix, feature, refactor, discovery).

4. **Observation type taxonomy**. Typed observations (decision, bugfix, feature, refactor, discovery, change) with visual legend for scanning. Our ShikiDB memories are typed but coarser.

5. **Web viewer UI with SSE**. Real-time memory stream visualization. We have tmux status line but no web dashboard for memory.

### What Shikki Already Does Better

1. **Structured memory model**. ShikiDB has first-class contexts, decisions, plans, reports, events -- each with distinct schemas and query paths. claude-mem has one flat `observations` table with a type column. Our model is richer and more queryable.

2. **Multi-project, multi-company**. ShikiDB has `projectIds` and company-level orchestration. claude-mem is per-project by directory name. We handle cross-project knowledge transfer natively.

3. **Decision persistence with rationale**. Our `/decide` pipeline and `shiki_save_decision` produce structured decisions with options, rationale, and stakeholder context. claude-mem decisions are just observation subtypes.

4. **Spec-driven development**. Feature specs with frontmatter, tracking fields, test-run-ids. claude-mem has no concept of feature lifecycle or specification.

5. **Event bus architecture**. ShikiEvent protocol for cross-system observability. claude-mem is a closed loop with no event emission.

6. **No crypto token**. They launched a Solana token ($CMEM). We do not commingle tool quality with token speculation.

7. **Privacy model**. ShikiDB is self-hosted (PocketBase). claude-mem is local SQLite but uses Claude Agent SDK for compression (sends data to Anthropic API). Our memory never leaves the user's infrastructure.

### Verdict: WATCH

claude-mem is the market leader by star count. The progressive disclosure pattern is genuinely good and we should adopt the index format. The 3-layer search workflow is worth studying. But the core architecture (SQLite per-machine, no structured memory model, flat observation types) is simpler than ShikiDB. The AGPL license and Solana token are concerning signals. Their Endless Mode beta is architecturally interesting but unproven.

**Action items**:
- [ ] Add `shiki_search` "light mode" returning index-only with token cost estimates
- [ ] Add timeline/neighborhood query to ShikiDB (observations before/after a given event)
- [ ] Consider progressive disclosure index format for context injection in ShikiMCP

---

## 2. claude-hud (16.3k stars)

**Repo**: https://github.com/jarrodwatts/claude-hud
**Author**: Jarrod Watts (@jarrodwatts)
**Language**: JavaScript/TypeScript | **License**: MIT | **Version**: latest
**Created**: 2026-01-02 | **Last updated**: 2026-04-02

### What It Does

Claude Code plugin that shows real-time session state in the terminal's status line. Context usage, active tools, running agents, todo progress, git status, usage rate limits -- always visible below the input.

### Architecture Deep Dive

**Pure statusline plugin**. Uses Claude Code's native `statusLine` API. No separate window, no tmux, works in any terminal.

**Data flow**:
```
Claude Code -> stdin JSON -> claude-hud -> stdout -> terminal statusline
           -> transcript JSONL (tools, agents, todos)
```

**Key components**:
- `stdin.ts` -- parses Claude Code's stdin JSON for context window data, model info, rate limits
- `transcript.ts` -- parses JSONL transcript file for tool/agent/todo activity, with SHA-256 based caching
- `render/` -- modular line renderers (identity, project, context, usage, tools, agents, todos, memory, environment)
- `config.ts` -- user configuration with presets (Full/Essential/Minimal)

**What it shows**:
- Model name and provider (Opus, Bedrock, API key)
- Project path (1-3 directory levels) + git branch with dirty/ahead-behind/file stats
- Context bar with native token data (not estimated) -- green/yellow/red gradient
- Usage rate limits (5h and 7d bars) from Claude Code stdin
- Tool activity -- which tools are active, counts of completed tools
- Agent tracking -- subagent names, what they're doing, duration
- Todo progress -- task completion tracking
- Session duration, token speed, memory usage (opt-in)
- Config counts (CLAUDE.md, rules, MCPs, hooks)

**Technical details**:
- Updates every ~300ms
- Native context percentage from Claude Code v2.1.6+ (falls back to manual calculation)
- Autocompact buffer estimation with scaled buffer (no buffer at <5% usage, full at >50%)
- Bedrock model ID normalization
- Grapheme-aware width calculation for wide characters (CJK, emoji)
- Transcript cache keyed by SHA-256 of path + mtime/size for performance

**Configuration**: JSON at `~/.claude/plugins/claude-hud/config.json`. 30+ options including colors (256-color + hex support), element order, git display granularity. Three presets.

### Patterns to Steal

1. **Native statusline API usage**. Claude Code has a `statusLine` config that runs a subprocess and displays output. We use tmux status line which requires tmux. The native approach works everywhere.

2. **Context health visualization**. The green-yellow-red context bar with autocompact buffer estimation is something Shikki's tmux status line does not show. Context percentage with token breakdown at 85%+ is operationally useful.

3. **Rate limit visibility**. Showing the 5h and 7d Claude subscriber usage limits directly in the HUD. We don't surface this anywhere.

4. **Transcript parsing for tool/agent activity**. They parse the JSONL transcript file to extract tool calls, subagent spawns, and todo items. This gives "what is Claude doing right now?" visibility without any hooks.

5. **Grapheme-aware width calculation**. Proper handling of CJK characters, emoji, ZWJ sequences for terminal rendering. Our tmux status likely does not handle this.

6. **Configurable element order**. Users can reorder, hide, and customize every HUD element. Our tmux status is more fixed.

### What Shikki Already Does Better

1. **tmux plugin goes deeper**. Our tmux plugin provides session management, pane orchestration, window naming, research workflows. claude-hud is display-only -- it cannot manage sessions, dispatch agents, or control layout.

2. **Agent dispatch visibility**. Shikki's `/board` shows full dispatch state across multiple subagents with wave/file/status tracking. claude-hud shows agent names and duration but no orchestration state.

3. **Integrated with memory system**. Our tmux status can pull context from ShikiDB. claude-hud is standalone display with no memory integration.

4. **Multi-window orchestration**. tmux windows, panes, research workflows, board displays. claude-hud is a single status line.

### Verdict: ADOPT (selective)

claude-hud solves a real problem elegantly -- "what is Claude Code doing right now?" The native statusline approach is cleaner than requiring tmux. We should adopt the context health bar and rate limit visibility patterns. The transcript parsing technique (reading JSONL for tool/agent state) is useful for non-tmux environments.

**Action items**:
- [ ] Add context percentage + health bar to Shikki's tmux status line
- [ ] Surface Claude subscriber rate limits (5h/7d) in Shikki status display
- [ ] Evaluate adding a native Claude Code statusline plugin as alternative to tmux for basic observability
- [ ] Adopt transcript JSONL parsing for tool/agent activity tracking

---

## 3. total-recall (189 stars)

**Repo**: https://github.com/davegoldblatt/total-recall
**Author**: Dave Goldblatt (@davegoldblatt)
**Language**: Shell/Markdown | **License**: none specified | **Version**: -
**Created**: 2026-02-05 | **Last updated**: 2026-04-02

### What It Does

Tiered memory system for Claude Code with write gates, correction propagation, and promotion workflows. All storage is plain markdown files. No database, no external services, no network calls.

### Architecture Deep Dive

**4-tier memory model**:
1. **Counter / Working Memory** (`CLAUDE.local.md`) -- ~1500 words, auto-loaded every session. Only behavior-changing facts.
2. **Registers** (`memory/registers/*.md`) -- structured domain knowledge (people, projects, decisions, preferences, tech-stack, open-loops). Loaded on-demand by domain.
3. **Daily Log** (`memory/daily/YYYY-MM-DD.md`) -- timestamped raw capture. All writes land here FIRST. Append-only.
4. **Archive** (`memory/archive/`) -- completed/superseded items. Searchable, never auto-loaded.

**Three gates controlling flow**:
1. **Write Gate** -- "Does this change future behavior?" Five criteria: behavioral change, commitment, decision with rationale, stable recurring fact, explicit "remember this". If none are true, discard.
2. **Trust Gate** -- Metadata on durable claims: confidence (high/med/low), last_verified date, evidence source. Enables staleness detection.
3. **Correction Gate** -- Human corrections are highest priority. Correction triggers writes to daily log + register + working memory simultaneously. Old claims marked `[superseded: date]` with reason. Never silent overwrite.

**Promotion flow**: Daily log -> (user-controlled promotion via `/recall-promote`) -> Registers -> (distillation) -> Working Memory -> (expiry) -> Archive.

**Key design choice**: All writes go to daily log first. Promotion to permanent storage is a separate, user-controlled step. This prevents the model from prematurely solidifying inferences.

**Entry IDs**: Durable IDs (`^tr` + 10 hex chars) on promoted entries. Sidecar metadata in `memory/.recall/metadata.json` tracking created_at, last_reviewed_at, pinned, snoozed_until, status, tier.

**Maintenance** (`/recall-maintain`): Pressure-based cleanup. Calculates working memory word count, identifies candidates for demotion based on score (word count + age), handles pinning and snoozing. Refuses to run if entries lack IDs or have duplicates.

**Hooks**: Minimal. SessionStart hook reads open-loops + recent daily logs, outputs as context. PreCompact hook writes timestamp marker. Both are simple bash scripts (<50 lines total). No transcript parsing.

**Contradiction protocol**: Never silently overwrite. Old entries marked `[superseded: date]` with reason. Pattern of change preserved. Low confidence contradictions ask user confirmation.

**Privacy**: Everything local. Plain markdown files. No network calls, no telemetry, no external services. Hooks never read conversation transcripts.

### Patterns to Steal

1. **Write Gate as formal protocol**. The 5-criteria write gate is the most disciplined memory quality mechanism of any plugin reviewed. Shikki's MEMORY.md grows unbounded because we have no formal gate. The "will this matter tomorrow?" filter is exactly what prevents context rot.

2. **Daily-log-first with explicit promotion**. All writes land in scratch space. Promotion to permanent memory is a deliberate user action. This is philosophically superior to auto-saving everything (claude-mem) or our current approach of writing directly to MEMORY.md sections. It prevents junk accumulation.

3. **Correction propagation across all tiers**. When a user corrects something, total-recall updates daily log + relevant register + working memory in one shot. It also searches for the old claim everywhere. Our ShikiDB has no correction propagation -- a corrected fact in one memory does not update related memories.

4. **Supersession trail with `[superseded: date]`**. Never delete, always mark and explain. The pattern-of-change itself is information. We do not track memory supersession in ShikiDB.

5. **Pressure-based maintenance with pinning/snoozing**. The maintain command calculates word budget pressure and surfaces candidates for demotion using a score (size * age). Pinning protects important entries. Snoozing defers review. MEMORY.md size limits are enforced proactively, not reactively.

6. **Trust metadata on claims**. Confidence + last_verified + evidence on durable claims. This enables staleness detection ("this was last verified 6 months ago"). Our Memory Decay backlog item (P2) aligns with this but total-recall already ships it.

7. **Domain-based register routing**. Automatic routing based on content: mentions a person -> people.md, mentions a project -> projects.md. Simple but effective. Our MEMORY.md is flat with manual sections.

### What Shikki Already Does Better

1. **Centralized queryable database**. ShikiDB is PostgreSQL-backed, queryable across projects and companies. total-recall is plain files in a single project directory. No cross-project memory. No structured queries.

2. **API-accessible memory**. ShikiMCP provides 15 MCP tools for memory operations. total-recall has no API -- it's markdown files and Claude Code slash commands.

3. **Event tracking and audit trail**. ShikiDB records agent_events, session lifecycle, context compaction events. total-recall only has daily log entries and timestamp markers.

4. **Rich memory types**. ShikiDB has distinct schemas for contexts, decisions, plans, reports, events. total-recall has registers (domain files) with freeform markdown.

5. **Multi-agent orchestration awareness**. Our memory system is designed for multi-agent dispatch where subagents share knowledge. total-recall is single-agent, single-project.

6. **Active maintenance features**. Shikki already has test-run tracking, spec validation, pre-PR gates. total-recall's maintenance is limited to word budget enforcement.

### Verdict: ADOPT (philosophy + patterns)

total-recall is architecturally simple (just markdown files) but philosophically excellent. The write gate, daily-log-first pattern, correction propagation, and pressure-based maintenance are the best memory quality patterns seen in any Claude Code plugin. At 189 stars it's under-appreciated. We should adopt these patterns at the ShikiDB level, not as markdown files but as database-backed quality gates.

**Action items**:
- [ ] Implement write gate for ShikiDB saves -- 5-criteria filter before `shiki_save_context` persists
- [ ] Add correction propagation to ShikiDB -- when a memory is updated, find and mark related superseded memories
- [ ] Add `superseded_by` and `superseded_at` fields to ShikiDB memory schema
- [ ] Implement confidence + last_verified metadata on ShikiDB memories (feeds P2 Memory Decay)
- [ ] Add pressure-based MEMORY.md maintenance to Shikki session workflow
- [ ] Consider daily-log-first pattern for Shikki context saves (stage -> promote workflow)

---

## Cross-Cutting Comparison

| Dimension | claude-mem (44.6k) | claude-hud (16.3k) | total-recall (189) | Shikki |
|---|---|---|---|---|
| **Storage** | SQLite + ChromaDB | None (display only) | Plain markdown files | PostgreSQL (ShikiDB) |
| **Search** | FTS5 + vector hybrid | N/A | grep across markdown | API search + MCP |
| **Context injection** | Progressive disclosure index | N/A | Open loops + daily highlights | Full memory dump |
| **Write quality gate** | None (captures everything) | N/A | 5-criteria write gate | None (manual) |
| **Correction handling** | Not mentioned | N/A | Multi-tier propagation | Not implemented |
| **Multi-project** | Per-directory isolation | N/A | Per-project | Cross-project + company |
| **Observability** | Web viewer + SSE | Native statusline | None | tmux plugin |
| **Privacy** | Local + Anthropic API | Local only | Local only, no network | Self-hosted |
| **Hooks used** | 5 lifecycle hooks | statusLine API | 2 hooks (session-start, pre-compact) | Hooks + MCP + CLI |
| **Agent awareness** | Single agent | Shows subagent status | Single agent | Multi-agent orchestration |

---

## Summary of Steal-Worthy Patterns

### Priority 1 -- Adopt Now

| Pattern | Source | Shikki Action |
|---|---|---|
| Write gate (5 criteria) | total-recall | Gate before `shiki_save_context` |
| Progressive disclosure index | claude-mem | Light mode for `shiki_search` |
| Context health bar | claude-hud | Add to tmux status line |
| Correction propagation | total-recall | Multi-memory update on correction |

### Priority 2 -- Next Sprint

| Pattern | Source | Shikki Action |
|---|---|---|
| Timeline/neighborhood query | claude-mem | ShikiDB "what happened around X?" |
| Rate limit visibility | claude-hud | Surface in status display |
| Confidence + last_verified | total-recall | Memory staleness metadata |
| Supersession trail | total-recall | `superseded_by` field in schema |
| Daily-log-first staging | total-recall | Stage -> promote workflow |

### Priority 3 -- Evaluate

| Pattern | Source | Shikki Action |
|---|---|---|
| Observation type taxonomy | claude-mem | Richer memory type classification |
| Transcript JSONL parsing | claude-hud | Tool/agent activity from transcript |
| Pressure-based maintenance | total-recall | Automated MEMORY.md pruning |
| Native statusline plugin | claude-hud | Alternative to tmux for basic HUD |
| Endless mode (O(N) memory) | claude-mem | Research for long-running sessions |

---

## Final Verdicts

| Project | Stars | Verdict | Rationale |
|---|---|---|---|
| **claude-mem** | 44.6k | **WATCH** | Market leader. Progressive disclosure is great. Core architecture simpler than ShikiDB. AGPL + $CMEM token are yellow flags. |
| **claude-hud** | 16.3k | **ADOPT** (selective) | Clean implementation of a real need. Adopt context bar + rate limit patterns. Evaluate native statusline approach. |
| **total-recall** | 189 | **ADOPT** (philosophy) | Best memory quality patterns. Write gate + correction propagation + maintenance are must-have. Simple impl but excellent design. |
