# 四季 Shiki — Dev OS Workspace

Shiki is a workspace platform for AI-assisted development. It provides shared process skills, agent personas, semantic memory, and real-time observability across all your projects.

Your projects live inside Shiki. Each project is its own git repo with its own Claude configuration. Shiki provides the shared infrastructure: the dashboard, the API, the memory system, and the process skills that make your AI agents more effective.

## Architecture

```
shiki/                         <- workspace root (this repo)
+-- .claude/
|   +-- skills/shiki-process/  <- shared process skills
|   +-- commands/              <- slash commands (/quick, /md-feature, /pre-pr...)
+-- src/
|   +-- backend/               <- Deno REST API + WebSocket
|   +-- frontend/              <- Vue 3 dashboard
|   +-- db/                    <- PostgreSQL schema + migrations
+-- scripts/                   <- backup, restore, ingestion
+-- projects/                  <- GITIGNORED — each is its own git repo
+-- features/                  <- Shiki's own feature tracking
+-- shiki                      <- CLI script
```

```
+------------------+       +------------------+       +------------------+
|                  |  ws   |                  |  sql  |                  |
|   Vue 3 SPA      +------>+   Deno Backend   +------>+ TimescaleDB/PG17 |
|   :5174          |  rest |   :3900          |       |   :5433          |
|                  +------>+                  |       |                  |
+------------------+       +--------+---------+       +------------------+
                                    |
                                    | http
                                    v
                           +--------+---------+
                           |                  |
                           |   Ollama         |
                           |   :11435         |
                           |  nomic-embed-txt |
                           +------------------+
```

**Services:**

| Service       | Port  | Description                                      |
|---------------|-------|--------------------------------------------------|
| `db`          | 5433  | PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale |
| `ollama`      | 11435 | Local embedding model server                     |
| `ollama-init` | --    | One-shot: pulls `nomic-embed-text` model         |
| `backend`     | 3900  | Deno REST API + WebSocket server                 |
| `frontend`    | 5174  | Vue 3 + Vite dashboard                           |

## Quick Start

```bash
# 1. Clone the workspace
git clone https://github.com/Fr0zenSide/shiki.git
cd shiki

# 2. Initialize (starts Docker, backend, frontend)
./shiki init

# 3. Create a project
./shiki new my-app

# 4. Start working
cd projects/my-app && claude
```

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

## Process Skills

Shiki ships with a complete development process system:

- `/quick` — 4-step pipeline for small changes (< 3 files)
- `/md-feature` — 8-phase pipeline for new features
- `/pre-pr` — 9-gate quality pipeline with multi-agent review
- `/review` — Interactive PR review
- `/dispatch` — Autonomous parallel feature implementation
- `/validate-pr` — Checklist validation before merge
- `/pre-release-scan` — AI marker scan before release

### Agent Personas

| Agent | Role | Focus |
|-------|------|-------|
| @Sensei | CTO | Architecture, code quality, feasibility |
| @Hanami | Designer | UX, accessibility, emotional design |
| @Kintsugi | Philosophy | Design philosophy, imperfection as beauty |
| @Enso | Brand | Voice, tone consistency, mindfulness |
| @Tsubaki | Copy | Conversion copy, storytelling, SEO |
| @Shogun | Strategy | Market positioning, competitive analysis |
| @Ronin | Reviewer | Adversarial review, security, edge cases |
| @Daimyo | Founder | Final authority on decisions |

## Project Adapter

Each project gets a `project-adapter.md` that configures the process skills for its tech stack:

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

| Layer     | Technology                                          |
|-----------|-----------------------------------------------------|
| Database  | PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale |
| Embeddings| Ollama with `nomic-embed-text` (768 dimensions)     |
| Backend   | Deno 2.0 + postgres.js + Zod                       |
| Frontend  | Vue 3 + TypeScript + Vite                           |
| Infra     | Docker Compose                                      |

## Memory System

Shiki includes a semantic memory system powered by vector embeddings:

1. **Storage**: Memories stored via `POST /api/memories` get embedded by Ollama using `nomic-embed-text` (768 dimensions)
2. **Search**: `POST /api/memories/search` converts queries to vectors and finds similar memories via cosine similarity + DiskANN index
3. **Use cases**: Cross-session recall, project knowledge bases, user preferences, decision tracking
4. **Lifecycle**: TimescaleDB handles compression and retention automatically

## Development

```bash
# Run backend locally (without Docker for DB/Ollama)
cd src/backend && deno task dev

# Apply schema manually
psql -U acc -d acc -f src/db/init/01-schema.sql
```

| Variable         | Default                              | Description                |
|------------------|--------------------------------------|----------------------------|
| `DATABASE_URL`   | `postgres://acc:acc@localhost:5433/acc` | PostgreSQL connection      |
| `OLLAMA_URL`     | `http://localhost:11435`             | Ollama API endpoint        |
| `EMBED_MODEL`    | `nomic-embed-text`                   | Embedding model name       |
| `WS_PORT`        | `3900`                               | Server port                |
| `NODE_ENV`       | `development`                        | Environment mode           |
| `LOG_LEVEL`      | `info`                               | Log verbosity              |

## Contributing

Contributions are welcome. This project is in active development.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request
