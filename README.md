# 四季 Shiki — Your Dev Team, Persistent

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-blueviolet)](https://claude.ai/claude-code)

> A workspace that gives your AI coding agent a team, a memory, and a quality process — across every project.

Shiki turns Claude Code from a stateless assistant into a persistent development partner. Your agent remembers decisions, follows your process, and reviews its own work through specialized personas — and all of this carries over from one project to the next.

## How It Works

```
    ┌─────────────────────────────────────────────────┐
    │                  YOU (ideas)                     │
    │                     │                            │
    │        ┌────────────┴────────────┐               │
    │        │                         │               │
    │    Small fix               New feature           │
    │   /quick                  /md-feature            │
    │        │                         │               │
    │        │    ┌──── Agent Team ────┤               │
    │        │    │  @Sensei (arch)    │               │
    │        │    │  @Hanami (UX)      │               │
    │        │    │  @Ronin (security) │               │
    │        │    └────────────────────┘               │
    │        │                         │               │
    │        └──────────┬──────────────┘               │
    │                   │                              │
    │                /pre-pr                            │
    │             9 quality gates                       │
    │                   │                              │
    │                /review                            │
    │            You approve → merge                    │
    │                   │                              │
    │         Memory persists (vector DB)               │
    │         Team grows across projects                │
    └─────────────────────────────────────────────────┘
```

You bring the idea. Shiki handles the process: the right pipeline kicks in, agent personas review the work, quality gates catch issues before merge, and everything your agent learns is stored in a searchable vector database. Next session, next project — context is preserved.

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
| `/quick` | 4-step pipeline for small changes | Bug fixes, tweaks (< 3 files) |
| `/md-feature` | 8-phase pipeline for new features | Anything that adds behavior |
| `/pre-pr` | 9-gate quality pipeline | Before every pull request |
| `/review` | Interactive PR review | Reviewing open PRs |
| `/dispatch` | Autonomous parallel implementation | Large features with independent parts |
| `/validate-pr` | Checklist validation before merge | Final merge check |
| `/pre-release-scan` | AI marker scan | Before App Store / production release |

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
| **@Daimyo** | Founder | Final authority on decisions |

Agents are defined in `.claude/skills/shiki-process/agents.md` — you can customize them or create your own.

### Memory System

Shiki includes a semantic memory system powered by vector embeddings:

- **Store**: Memories saved via the API get embedded by Ollama (`nomic-embed-text`, 768 dimensions)
- **Search**: Queries are converted to vectors and matched via cosine similarity + DiskANN index
- **Use cases**: Cross-session recall, project knowledge bases, decision tracking, user preferences
- **Lifecycle**: TimescaleDB handles compression and retention automatically

Your agent's context doesn't disappear when the session ends.

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
│   ├── frontend/              <- Vue 3 dashboard
│   └── db/                    <- PostgreSQL schema + migrations
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
./shiki status       # Show services + projects
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
