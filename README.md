# 四季 Shiki — Your Dev Team, Persistent

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-blueviolet)](https://claude.ai/claude-code)
[![Ko-fi](https://img.shields.io/badge/Support-Ko--fi-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/Fr0zenSide)

> A workspace that gives your AI coding agent a team, a memory, and a quality process — across every project.

Shiki turns Claude Code from a stateless assistant into a persistent development partner. Your agent remembers decisions, follows your process, and reviews its own work through specialized personas — and all of this carries over from one project to the next.

## How It Works

```
    ┌─────────────────────────────────────────────────┐
    │                  YOU (ideas)                    │
    │                     │                           │
    │        ┌────────────┴────────────┐              │
    │        │                         │              │
    │    Small fix               New feature          │
    │   /quick                  /md-feature           │
    │        │                         │              │
    │        │    ┌──── Agent Team ────┤              │
    │        │    │  @Sensei (arch)    │              │
    │        │    │  @Hanami (UX)      │              │
    │        │    │  @Ronin (security) │              │
    │        │    └────────────────────┘              │
    │        │                         │              │
    │        └──────────┬──────────────┘              │
    │                   │                             │
    │                /pre-pr                          │
    │             9 quality gates                     │
    │                   │                             │
    │                /review                          │
    │            You approve → merge                  │
    │                   │                             │
    │         Memory persists (vector DB)             │
    │         Team grows across projects              │
    └─────────────────────────────────────────────────┘
```

You bring the idea. Shiki handles the process: the right pipeline kicks in, agent personas review the work, quality gates catch issues before merge, and everything your agent learns is stored in a searchable vector database. Next session, next project — context is preserved.

### What's New in v3.1.0

- **Knowledge Ingestion** (`/ingest`) — import external repos, URLs, and docs into your vector knowledge base
- **Tech Radar** (`/radar`) — monitor GitHub repos and dependencies for breaking changes and updates
- **Pipeline Resilience** — LangGraph-inspired checkpointing, resume from failure, and conditional routing
- **Health Check System** — `./shiki status` with full diagnostics, uptime-kuma compatible `--ping` mode

## Quick Start

### The Easy Way (via Claude Code)

```bash
claude "clone https://github.com/Fr0zenSide/shiki and run ./shiki init for me"
```

### Manual Setup

**Prerequisites:** [Docker](https://docs.docker.com/get-docker/), [Deno](https://deno.land), [Node.js](https://nodejs.org)

```bash
# 1. Clone the workspace
git clone https://github.com/Fr0zenSide/shiki.git
cd shiki

# 2. Initialize (starts Docker, backend, frontend)
./shiki init
# Missing dependencies? The CLI detects them and offers to install via Homebrew.

# 3. Create a project
./shiki new my-app

# 4. Start working
cd projects/my-app && claude
```

That's it. Your agent now has access to Shiki's process skills, agent team, and persistent memory.

## What You Get

### Commands

| Command | Description | When to use |
|---------|-------------|-------------|
| `/quick "<desc>"` | 4-step pipeline for small changes | Bug fixes, tweaks (< 3 files) |
| `/md-feature "<name>"` | 8-phase pipeline for new features | Anything that adds behavior |
| `/pre-pr` | 9-gate quality pipeline | Before every pull request |
| `/review <PR#>` | Interactive PR review with 3-agent pre-analysis | Reviewing open PRs |
| `/backlog` | Show next 7 prioritized tasks | Planning what to work on next |
| `/backlog-challenge` | Daimyo decision ballot (8 questions per session) | Prioritizing and unblocking decisions |
| `/backlog-plan` | Continuous planning pipeline (see below) | Autonomous plan-build-merge loop |
| `/dispatch` | Autonomous parallel implementation | Large features with independent parts |
| `/course-correct` | Mid-feature scope change workflow | When requirements shift during implementation |
| `/validate-pr` | Checklist validation before merge | Final merge check |
| `/pre-release-scan` | AI slop scan before production release | Before App Store / production release |
| `/retry` | Resume failed pipelines or stuck agents | When a pipeline fails mid-run or agents are blocked |
| `/ingest` | Import external knowledge into memory | Repos, URLs, docs you want to learn from |
| `/radar` | Monitor tech stack ecosystem | Track dependency updates and breaking changes |

#### `/backlog-plan` — Continuous Planning Pipeline

Scans the backlog, launches parallel planning agents (max 3), surfaces 4 Q/A decisions per batch to @Daimyo, and queues approved specs for implementation in parallel worktrees. Auto-chains: when one feature finishes planning, the next starts.

| Sub-command | Description |
|-------------|-------------|
| `/backlog-plan` | Start pipeline (scan + plan top 3 by priority) |
| `/backlog-plan status` | Show pipeline state (planning / building / queued) |
| `/backlog-plan next` | Force advance to next backlog item |
| `/backlog-plan build` | Skip to implementation for features at Phase 5b+ |

### Agent Team

Every project gets access to specialized agent personas that review work through different lenses:

| Agent | Role | One-liner |
|-------|------|-----------|
| **@Sensei** | CTO | Architecture, code quality, feasibility decisions |
| **@Hanami** | Designer | UX, accessibility, emotional design |
| **@Kintsugi** | Philosophy | Design philosophy, imperfection as beauty |
| **@Enso** | Brand | Voice and tone consistency, mindfulness |
| **@Tsubaki** | Copy | Conversion copy, storytelling, SEO |
| **@Shogun** | Strategy | Market positioning, competitive analysis |
| **@Ronin** | Reviewer | Adversarial review, security, edge cases |
| **@Katana** | DevOps/Security | Linux hardening, weekly audits, breach analysis, backups |
| **@Daimyo** | Founder | Final authority on decisions |

Agents are defined in `.claude/skills/shiki-process/agents.md` — you can customize them or create your own.

### Memory System

Shiki includes a semantic memory system powered by vector embeddings:

- **Store**: Memories saved via the API get embedded by Ollama (`nomic-embed-text`, 768 dimensions)
- **Search**: Queries are converted to vectors and matched via cosine similarity + DiskANN index
- **Use cases**: Cross-session recall, project knowledge bases, decision tracking, user preferences
- **Lifecycle**: TimescaleDB handles compression and retention automatically

Your agent's context doesn't disappear when the session ends.

### Knowledge Ingestion (`/ingest`)

Import external knowledge sources directly into your vector database for cross-session recall:

```bash
# Ingest a GitHub repo's key insights
/ingest https://github.com/org/repo

# Ingest a website
/ingest https://docs.example.com/architecture

# Ingest local documentation
/ingest ./docs/design-decisions.md

# List all ingested sources
/ingest sources

# Re-ingest (updates existing knowledge)
/ingest reingest <source-id>
```

**How it works:**
1. **Extract** — Summarize architecture decisions, identify patterns, extract API contracts
2. **Chunk** — Split into semantic units optimized for retrieval
3. **Embed** — Generate vector embeddings via your local model
4. **Dedup** — Cosine similarity check (threshold 0.92) prevents duplicate knowledge
5. **Categorize** — Auto-tag chunks (architecture, security, testing, API, etc.)
6. **Store** — Persist in the vector database for semantic search

### Tech Radar (`/radar`)

Monitor your technology ecosystem for updates, breaking changes, and competitive intelligence:

```bash
# Add a repo to your watchlist
/radar watch https://github.com/denoland/deno

# Run a scan of all watched repos
/radar scan

# View the latest digest report
/radar show

# Ingest notable findings into memory
/radar ingest

# List watched repos
/radar list
```

The radar scans GitHub for releases and commits, detects semver major bumps and breaking change keywords, and generates grouped digests (breaking > update > error > stable). Notable findings are auto-ingested into your knowledge base.

### Pipeline Resilience

All Shiki pipelines (`/md-feature`, `/pre-pr`, `/quick`) support LangGraph-inspired checkpoint-based resilience:

- **Checkpointing** — Each pipeline phase is recorded as a checkpoint with before/after state
- **Resume from failure** — When a pipeline fails, `/retry` resumes from the last successful checkpoint
- **State accumulation** — JSONB state merges across phases (like LangGraph's TypedDict pattern)
- **Conditional routing** — Routing rules evaluate failures and decide: `auto_fix`, `retry_phase`, or `escalate`
- **Retry budgets** — Max retries tracked across the entire resume chain to prevent infinite loops

```bash
# Pipeline fails at gate 3 → state is preserved
# Later, resume from where it left off:
/retry

# View pipeline run history
/retry status
```

### Health Check System

Monitor your Shiki workspace health via CLI or HTTP:

```bash
# Full interactive status report
./shiki status

# Uptime-kuma compatible (exit 0/1)
./shiki health --ping

# HTTP endpoint for monitoring tools
curl http://localhost:3900/health/full
```

The status report shows: service health, knowledge base stats (memories, sources, categories), pipeline activity, workspace projects, agent roster, and available commands.

### Project Adapter

Each project gets a `project-adapter.md` that configures Shiki's process skills for its tech stack:

```markdown
# Project Adapter

## Tech Stack
- Language: Swift
- Framework: SwiftUI
- Architecture: Clean + MVVM + Coordinator

## Commands
- Test: `swift test`
- Build: `xcodebuild -scheme MyApp`
- Lint: `swiftlint`

## Conventions
- Branching: feature/* from develop
- Naming: camelCase
```

This means `/pre-pr` knows how to run *your* tests, `/quick` uses *your* linter, and agents review against *your* conventions.

## Architecture

```
shiki/                         <- workspace root (this repo)
├── .claude/
│   ├── skills/shiki-process/  <- shared process skills
│   └── commands/              <- slash commands (/quick, /md-feature, /pre-pr...)
├── src/
│   ├── backend/               <- Deno REST API + WebSocket
│   │   └── src/
│   │       ├── routes.ts      <- all HTTP endpoints
│   │       ├── ingest.ts      <- knowledge ingestion pipeline
│   │       ├── radar.ts       <- tech radar scanning engine
│   │       └── pipelines.ts   <- checkpoint & resume engine
│   ├── frontend/              <- Vue 3 dashboard
│   └── db/
│       ├── init/              <- base schema
│       └── migrations/        <- incremental migrations
├── scripts/                   <- backup, restore, ingestion
├── projects/                  <- GITIGNORED — each is its own git repo
├── features/                  <- Shiki's own feature tracking
└── shiki                      <- CLI script
```

```
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
│                  │  ws   │                  │  sql  │                  │
│   Vue 3 SPA      ├──────►│   Deno Backend   ├──────►│ TimescaleDB/PG17 │
│   :5174          │  rest │   :3900          │       │   :5433          │
│                  ├──────►│                  │       │                  │
└──────────────────┘       └────────┬─────────┘       └──────────────────┘
                                    │
                                    │ http
                                    ▼
                           ┌────────┴─────────┐
                           │                  │
                           │   Ollama         │
                           │   :11435         │
                           │  nomic-embed-txt │
                           └──────────────────┘
```

**Services:**

| Service | Port | Description |
|---------|------|-------------|
| `db` | 5433 | PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale |
| `ollama` | 11435 | Local embedding model server |
| `ollama-init` | -- | One-shot: pulls `nomic-embed-text` model |
| `backend` | 3900 | Deno REST API + WebSocket server |
| `frontend` | 5174 | Vue 3 + Vite dashboard |

## Roadmap

### Agent Memory Evolution

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 0** | Static `team/*.md` files loaded into context. Good for < 200 lines/agent. | Current |
| **Phase 1** | Split into `team/<agent>/identity.md` + `patterns.md` + `project-notes/`. File-based retrieval by task type. | Planned |
| **Phase 2** | Vector-indexed retrieval. Agent spawns → Shiki API search → top-K memories as "knowledge pack". | Planned |
| **Phase 3** | Archiver/Retriever protocol. Post-task learning extraction. Agents read AND write memory. | Planned |

### Platform

- [x] CLI with auto-install dependency detection (Homebrew + apt)
- [x] Semantic memory system (vector DB + embeddings)
- [x] Process skills (Swift projects)
- [x] Knowledge ingestion pipeline (`/ingest`)
- [x] Tech radar monitoring (`/radar`)
- [x] Pipeline resilience (checkpointing, resume, routing)
- [x] Health check system (`./shiki status`, uptime-kuma compatible)
- [ ] Linux support (Ubuntu/Debian — CLI ready, full testing planned)
- [ ] Dashboard: agent timeline, memory browser, decision history
- [ ] Language addons: TypeScript, Python, Go, Rust
- [ ] MCP server for IDE-native agent invocation
- [ ] Community marketplace: commands, checklists, language addons

## CLI Reference

```bash
./shiki              # Show status (or guide to init if first run)
./shiki init         # First-time setup
./shiki new <name>   # Create a new project
./shiki start        # Start all services
./shiki stop         # Stop all services
./shiki status       # Full health report (services, memory, pipelines, agents)
./shiki health       # Alias for status
./shiki health --ping  # Uptime-kuma mode (exit 0 = healthy, 1 = unhealthy)
./shiki -h           # Help
```

## API Reference

### Health
```bash
curl http://localhost:3900/health
```

### Projects
```bash
curl http://localhost:3900/api/projects
```

### Memories (semantic search)
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

# Re-ingest a source (updates existing knowledge)
curl -X POST http://localhost:3900/api/ingest/reingest/<source-id>
```

### Tech Radar
```bash
# Trigger a scan of all watched repos
curl -X POST http://localhost:3900/api/radar/scan

# Get latest digest
curl http://localhost:3900/api/radar/digests/latest

# List watchlist
curl http://localhost:3900/api/radar/watchlist
```

### Pipelines (Checkpoint & Resume)
```bash
# Create a pipeline run
curl -X POST http://localhost:3900/api/pipelines \
  -H "Content-Type: application/json" \
  -d '{"pipelineType":"pre-pr","config":{"mode":"standard"}}'

# Add a checkpoint
curl -X POST http://localhost:3900/api/pipelines/<run-id>/checkpoints \
  -H "Content-Type: application/json" \
  -d '{"phase":"gate_1a","phaseIndex":0,"status":"completed","stateAfter":{}}'

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

## Backup & Restore

```bash
./scripts/backup-db.sh                # Create timestamped backup
./scripts/restore-db.sh               # Interactive restore
./scripts/ingest-memories.sh <proj-id> # Seed project knowledge
```

## Tech Stack

| Layer | Technology |
|-------|------------|
| Database | PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale |
| Embeddings | Ollama with `nomic-embed-text` (768 dimensions) |
| Backend | Deno 2.0 + postgres.js + Zod |
| Frontend | Vue 3 + TypeScript + Vite |
| Infra | Docker Compose |

## Development

```bash
# Run backend locally (without Docker for DB/Ollama)
cd src/backend && deno task dev

# Apply schema manually
psql -U shiki -d shiki -f src/db/init/01-schema.sql
```

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgres://shiki:shiki@localhost:5433/shiki` | PostgreSQL connection |
| `OLLAMA_URL` | `http://localhost:11435` | Ollama API endpoint |
| `EMBED_MODEL` | `nomic-embed-text` | Embedding model name |
| `WS_PORT` | `3900` | Server port |
| `NODE_ENV` | `development` | Environment mode |
| `LOG_LEVEL` | `info` | Log verbosity |

## Contributing

Contributions are welcome. Here's how to extend Shiki:

### Add a command

Create a markdown file in `.claude/commands/`:

```markdown
# /my-command

Instructions for the agent when this command is invoked...
```

Commands are automatically available as `/my-command` in any Shiki project.

### Add a language addon

1. Create a project adapter template for your language in `.claude/skills/shiki-process/`
2. Add language-specific checklist items in `.claude/skills/shiki-process/checklists/`
3. Test with `./shiki new test-project` and validate the process runs correctly

### Add an agent persona

Add or edit personas in `.claude/skills/shiki-process/agents.md`. Each agent needs:
- A name and role
- A clear focus area
- Review criteria they apply during `/pre-pr`

### Submit changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

[AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0)
