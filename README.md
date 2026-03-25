# Shiki — AI Orchestration OS for Multi-Project Development

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Pre-1.0](https://img.shields.io/badge/status-pre--1.0-orange.svg)]()
[![Swift](https://img.shields.io/badge/CLI-Swift-orange.svg)]()
[![Ko-fi](https://img.shields.io/badge/Support-Ko--fi-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/Fr0zenSide)

Shiki manages autonomous Claude Code agents across multiple projects with TDD enforcement, budget tracking, quality gates, and persistent memory. One CLI to orchestrate your entire development workspace.

**Status:** Pre-1.0 software built by a solo developer ([OBYW.one](https://obyw.one)). Actively used in production across 4 projects. Breaking changes may occur between releases.

## How It Works

```
    YOU (idea)
        |
   -----+------
   |           |
 Small fix   New feature
 /quick      /md-feature
   |           |
   |    +--- Agent Team ---+
   |    |  @Sensei (arch)  |
   |    |  @Hanami (UX)    |
   |    |  @Ronin (review) |
   |    +------------------+
   |           |
   +-----+-----+
         |
      /pre-pr
    9 quality gates
         |
      /review
   You approve, merge
         |
   Memory persists (vector DB)
   Context carries to next session
```

You bring the idea. Shiki runs the process: the right pipeline kicks in, agent personas review the work, quality gates catch issues before merge, and everything your agent learns is stored in a searchable vector database. Next session, next project — context is preserved.

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (or [Colima](https://github.com/abiosoft/colima))
- [Swift](https://swift.org/install) (5.9+)
- [Claude Code](https://claude.ai/claude-code) (for agent skills)

### Install

```bash
git clone https://github.com/Fr0zenSide/shiki.git
cd shiki/projects/shikki && swift build
ln -sf $(pwd)/.build/debug/shikki ~/.local/bin/shikki
```

### Launch

```bash
shiki start
```

Shiki detects your environment, starts Docker services, boots the backend, shows a startup dashboard, and drops you into a tmux workspace.

```
Shiki — Smart Startup [shiki]

[1/6] Environment
  + Docker daemon
  + Colima VM
  + Backend (localhost:3900)
  + Embeddings (127.0.0.1:1234)
...
+============================================================+
|  SHIKI v0.2.0                             System Ready     |
|------------------------------------------------------------+
|  Last Session           |  Upcoming                        |
|  3 tasks done (maya)    |  5 pending (maya)                |
|  2 done (wabisabi)      |  2 pending (flsh)                |
|------------------------------------------------------------+
|  +127 / -43 lines (maya)  ~mature                          |
|  Weekly: +93,706 / -15,906 across 4 projects               |
|------------------------------------------------------------+
|  4 T1 decisions pending | 0 stale | $0 spent today         |
+============================================================+
```

## What Shiki Does

### CLI Commands

| Command | What it does |
|---------|-------------|
| `shiki start` | Smart startup — env detection, Docker boot, dashboard, tmux |
| `shiki stop` | Graceful stop with active task count |
| `shiki restart` | Restart heartbeat, preserve tmux session |
| `shiki status` | Workspace overview with health indicators |
| `shiki board` | Rich board — progress bars, budget, health per project |
| `shiki decide` | Answer pending decisions (multiline input) |
| `shiki report` | Daily cross-project digest |
| `shiki history` | Session transcript viewer |

### Development Process (Claude Code Skills)

These commands run inside Claude Code sessions. Shiki injects them as agent skills.

| Command | When to use | Pipeline |
|---------|------------|----------|
| `/quick "fix X"` | Small changes (< 3 files) | 4-step: analyze, implement, test, verify |
| `/md-feature "X"` | New features | 8-phase: spec, design, implement, test, review |
| `/tdd` | Run tests, fix all failures | Continuous red-green-refactor |
| `/pre-pr` | Before any PR | 9 quality gates |
| `/review <PR#>` | PR review with 3-agent pre-analysis | Risk triage + security scan |
| `/dispatch` | Large features | Parallel implementation across worktrees |
| `/ingest <url>` | Import knowledge | Extract, chunk, embed, store |
| `/radar scan` | Monitor dependencies | Breaking changes + semver tracking |

### Agent Team

Specialized personas that review work through different lenses during `/pre-pr` and `/review`:

| Agent | Role | Focus |
|-------|------|-------|
| **@Sensei** | CTO | Architecture decisions, code quality, feasibility |
| **@Hanami** | Designer | UX, accessibility, emotional design |
| **@Kintsugi** | Philosophy | Design principles, wabi-sabi aesthetics |
| **@Ronin** | Adversarial reviewer | Security, edge cases, failure modes |
| **@Shogun** | Strategist | Market positioning, competitive analysis |
| **@Katana** | DevOps/Security | Infrastructure hardening, audit, backups |
| **@Daimyo** | Founder | Final authority on decisions |

Agents are defined in `.claude/skills/shiki-process/agents.md`. You can customize them or add your own.

### Memory System

Persistent semantic memory powered by vector embeddings (TimescaleDB + pgvector). Context survives across sessions and projects.

- **Store** — memories get embedded via Ollama (`nomic-embed-text`, 768d) or LM Studio
- **Search** — cosine similarity + DiskANN index for fast retrieval
- **Lifecycle** — TimescaleDB handles compression and retention automatically
- `/ingest` — import repos, URLs, docs into searchable knowledge base
- `/radar` — monitor GitHub repos for breaking changes and updates

### Orchestrator

The heartbeat loop manages multiple projects autonomously:

- Dynamic task dispatch based on priority and budget
- Per-company tmux panes (appear/disappear as tasks run)
- ntfy push notifications for pending decisions (iOS/Apple Watch)
- Session transcripts with git stats and maturity indicators

## Architecture

```
shiki/
+-- projects/shikki/         <-- Swift CLI (the `shikki` binary)
|   +-- Sources/ShikkiKit/    <-- HeartbeatLoop, BackendClient, SessionStats
|   +-- Tests/                 <-- 38 tests, 8 suites
+-- src/backend/              <-- Deno REST API + WebSocket
+-- src/frontend/             <-- Vue 3 dashboard
+-- packages/                 <-- Shared SPM: CoreKit, NetKit, SecurityKit
+-- .claude/
|   +-- skills/shiki-process/ <-- Process skills, agent definitions
|   +-- commands/             <-- Slash commands (/quick, /md-feature, etc.)
+-- projects/                 <-- Your projects (gitignored, each its own repo)
+-- scripts/                  <-- Backup, restore, ingestion utilities
```

### Services

```
+-----------------+       +-----------------+       +--------------------+
|                 |  ws   |                 |  sql  |                    |
|   Vue 3 SPA    +------>|   Deno Backend  +------>| TimescaleDB / PG17 |
|   :5174        |  rest |   :3900         |       |   :5433            |
|                +------>|                 |       |                    |
+-----------------+       +--------+--------+       +--------------------+
                                   |
                                   | http
                                   v
                          +--------+--------+
                          |                 |
                          |  Ollama / LM    |
                          |  Studio :11435  |
                          |  nomic-embed    |
                          +-----------------+
```

| Service | Port | Stack |
|---------|------|-------|
| Backend | 3900 | Deno 2.0 + postgres.js + Zod |
| Database | 5433 | PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale |
| Embeddings | 11435 | Ollama (nomic-embed-text) or LM Studio |
| Frontend | 5174 | Vue 3 + TypeScript + Vite |

### tmux Layout

```
Tab 1: orchestrator  <-- heartbeat loop + startup dashboard
Tab 2: board         <-- dynamic task panes (auto-managed)
Tab 3: research      <-- 4 panes: INGEST / RADAR / EXPLORE / SCRATCH
```

| Action | Shortcut |
|--------|----------|
| Switch tabs | `Opt + Shift + Left/Right` |
| Switch panes | `Opt + Arrow` |
| Zoom pane | `Ctrl-b z` |
| Scroll up | `Ctrl-b [` |
| Detach | `Ctrl-b d` |

## API Reference

### Health

```bash
curl http://localhost:3900/health
```

### Memories (Semantic Search)

```bash
# Store
curl -X POST http://localhost:3900/api/memories \
  -H "Content-Type: application/json" \
  -d '{"projectId":"<uuid>","content":"...","category":"architecture","importance":0.8}'

# Search
curl -X POST http://localhost:3900/api/memories/search \
  -H "Content-Type: application/json" \
  -d '{"query":"How does auth work?","projectId":"<uuid>","limit":5,"threshold":0.3}'
```

### Knowledge Ingestion

```bash
# Ingest chunks from an external source
curl -X POST http://localhost:3900/api/ingest \
  -H "Content-Type: application/json" \
  -d '{"sourceUrl":"https://github.com/org/repo","sourceType":"github","chunks":[{"content":"...","title":"..."}]}'

# List ingested sources
curl http://localhost:3900/api/ingest/sources
```

### Tech Radar

```bash
# Trigger a scan
curl -X POST http://localhost:3900/api/radar/scan

# Get latest digest
curl http://localhost:3900/api/radar/digests/latest
```

### Pipelines (Checkpoint and Resume)

```bash
# Create a pipeline run
curl -X POST http://localhost:3900/api/pipelines \
  -H "Content-Type: application/json" \
  -d '{"pipelineType":"pre-pr","config":{"mode":"standard"}}'

# Resume from a failed run
curl -X POST http://localhost:3900/api/pipelines/<run-id>/resume \
  -H "Content-Type: application/json" -d '{}'
```

### Dashboard

```bash
curl http://localhost:3900/api/dashboard/summary
curl http://localhost:3900/api/dashboard/performance?days=7
curl http://localhost:3900/api/dashboard/activity?hours=24
```

## Backup and Restore

```bash
./scripts/backup-db.sh                # Create timestamped backup
./scripts/restore-db.sh               # Interactive restore
./scripts/ingest-memories.sh <proj-id> # Seed project knowledge
```

## Roadmap

### Done

- [x] Smart startup with environment detection
- [x] Multi-project orchestration with heartbeat loop
- [x] Semantic memory system (vector DB + embeddings)
- [x] Process skills for Swift projects
- [x] Knowledge ingestion pipeline (`/ingest`)
- [x] Tech radar monitoring (`/radar`)
- [x] Pipeline resilience (checkpointing, resume, conditional routing)
- [x] ntfy push notifications (iOS/Apple Watch approval buttons)
- [x] Session productivity stats and maturity indicators
- [x] zsh autocompletion

### In Progress

- [ ] `shiki wizard` — first-time onboarding flow
- [ ] `shiki new` — company/project CRUD
- [ ] Linux support (Ubuntu/Debian — CLI compiles, full testing planned)

### Planned

- [ ] Multi-workspace support (workspace registry, knowledge isolation)
- [ ] Dashboard: agent timeline, memory browser, decision history
- [ ] Language addons: TypeScript, Python, Go, Rust (Swift shipped)
- [ ] MCP server for IDE-native agent invocation
- [ ] AI provider-agnostic orchestration (not locked to Claude)
- [ ] Backup automation (per-workspace, scheduled, ntfy alerts)

### Agent Memory Evolution

| Phase | Description | Status |
|-------|-------------|--------|
| **0** | Static `team/*.md` files loaded into context | Current |
| **1** | Split into per-agent directories with task-type retrieval | Planned |
| **2** | Vector-indexed retrieval — agent spawns with top-K knowledge pack | Planned |
| **3** | Agents read AND write memory — post-task learning extraction | Planned |

## Contributing

Contributions are welcome. Shiki is modular — you can extend it without touching core code.

### Add a Slash Command

Create a markdown file in `.claude/commands/`:

```markdown
# /my-command

Instructions for the agent when this command is invoked...
```

Commands are automatically available as `/my-command` in any Shiki project.

### Add a Language Addon

1. Create a project adapter template in `.claude/skills/shiki-process/`
2. Add language-specific checklist items in `.claude/skills/shiki-process/checklists/`
3. Test with a new project and validate the process runs correctly

### Add an Agent Persona

Edit `.claude/skills/shiki-process/agents.md`. Each agent needs:
- A name and role
- A clear focus area
- Review criteria they apply during `/pre-pr`

### Submit Changes

1. Fork the repository
2. Create a feature branch from `develop`
3. Make your changes
4. Submit a pull request targeting `develop`

## Development

```bash
# Run backend locally (Docker handles DB + embeddings)
cd src/backend && deno task dev

# Build the CLI
cd projects/shikki && swift build

# Run CLI tests
cd projects/shikki && swift test

# Apply schema manually
psql -U shiki -d shiki -f src/db/init/01-schema.sql
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgres://shiki:shiki@localhost:5433/shiki` | PostgreSQL connection |
| `OLLAMA_URL` | `http://localhost:11435` | Embedding model endpoint |
| `EMBED_MODEL` | `nomic-embed-text` | Embedding model name |
| `WS_PORT` | `3900` | Backend server port |
| `NODE_ENV` | `development` | Environment mode |
| `LOG_LEVEL` | `info` | Log verbosity |

## License

[AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0) — see [LICENSE](LICENSE) for details.

---

Built by [OBYW.one](https://obyw.one) with [Claude Code](https://claude.ai/claude-code)
