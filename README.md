# ACC v3 -- Agency Command Center

ACC v3 is a real-time command center for monitoring and managing AI agent workflows. It provides a unified dashboard for tracking agent sessions, performance metrics, cost accounting, git activity, and semantic memory across multiple projects. Built on a time-series database with vector search, it captures every agent event, chat message, and decision for full observability and post-hoc analysis.

## Architecture

```
+------------------+       +------------------+       +------------------+
|                  |  ws   |                  |  sql  |                  |
|   Vue 3 SPA      +------>+   Deno Backend   +------>+ TimescaleDB/PG17 |
|   :5173          |  rest |   :3800          |       |   :5432          |
|                  +------>+                  |       |                  |
+------------------+       +--------+---------+       +------------------+
                                    |
                                    | http
                                    v
                           +--------+---------+
                           |                  |
                           |   Ollama         |
                           |   :11434         |
                           |  nomic-embed-txt |
                           +------------------+

 Volumes:
   db_data      -> PostgreSQL data
   ollama_data  -> Model weights
```

**Services:**

| Service       | Port  | Description                                      |
|---------------|-------|--------------------------------------------------|
| `db`          | 5432  | PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale |
| `ollama`      | 11434 | Local embedding model server                     |
| `ollama-init` | --    | One-shot: pulls `nomic-embed-text` model         |
| `backend`     | 3800  | Deno REST API + WebSocket server                 |
| `frontend`    | 5173  | Vue 3 + Vite dashboard (placeholder)             |

## Quick Start

```bash
# 1. Clone and enter the project
cd acc-v3

# 2. Create environment file
cp .env.example .env
# Edit .env and set a real POSTGRES_PASSWORD

# 3. Start all services
docker compose up -d

# 4. Wait for health checks to pass
docker compose ps

# 5. Verify
curl http://localhost:3800/health
# {"status":"ok","db":true,"ollama":true}
```

## API Reference

### Health

```bash
curl http://localhost:3800/health
# {"status":"ok","db":true,"ollama":true}
```

### Projects

```bash
# List all projects
curl http://localhost:3800/api/projects
```

### Sessions

```bash
# List all sessions (latest 50)
curl http://localhost:3800/api/sessions

# Filter by project
curl "http://localhost:3800/api/sessions?project_id=<uuid>"
```

### Agent Events

```bash
# Log an agent event
curl -X POST http://localhost:3800/api/agent-update \
  -H "Content-Type: application/json" \
  -d '{
    "agentId": "<uuid>",
    "sessionId": "<uuid>",
    "projectId": "<uuid>",
    "eventType": "task_started",
    "message": "Starting code review",
    "progressPct": 10
  }'
```

### Performance Metrics

```bash
# Log a performance metric
curl -X POST http://localhost:3800/api/stats-update \
  -H "Content-Type: application/json" \
  -d '{
    "agentId": "<uuid>",
    "sessionId": "<uuid>",
    "projectId": "<uuid>",
    "metricType": "api_call",
    "tokensInput": 1500,
    "tokensOutput": 800,
    "durationMs": 2340,
    "costUsd": 0.0042,
    "model": "claude-opus-4-6"
  }'
```

### Chat Messages

```bash
# Store a chat message
curl -X POST http://localhost:3800/api/chat-message \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "<uuid>",
    "projectId": "<uuid>",
    "role": "assistant",
    "content": "I have completed the refactoring task.",
    "tokenCount": 42
  }'
```

### Memories

```bash
# Store a memory (embedding generated automatically)
curl -X POST http://localhost:3800/api/memories \
  -H "Content-Type: application/json" \
  -d '{
    "projectId": "<uuid>",
    "content": "The user prefers functional programming patterns over OOP.",
    "category": "preference",
    "importance": 1.5
  }'

# Semantic search memories
curl -X POST http://localhost:3800/api/memories/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What coding style does the user prefer?",
    "projectId": "<uuid>",
    "limit": 5,
    "threshold": 0.6
  }'
```

### Dashboard Aggregates

```bash
# Performance summary (last 7 days)
curl "http://localhost:3800/api/dashboard/performance?days=7"

# Filter by project
curl "http://localhost:3800/api/dashboard/performance?project_id=<uuid>&days=30"

# Activity feed (last 24 hours)
curl "http://localhost:3800/api/dashboard/activity?hours=24"

# Filter by project
curl "http://localhost:3800/api/dashboard/activity?project_id=<uuid>&hours=48"
```

### WebSocket

Connect to `ws://localhost:3800` for real-time event streaming. Messages sent by one client are broadcast to all other connected clients.

```javascript
const ws = new WebSocket("ws://localhost:3800");
ws.onmessage = (event) => console.log("Received:", event.data);
ws.send(JSON.stringify({ type: "agent_update", data: { ... } }));
```

## Backup & Restore

```bash
# Create a compressed backup
./db/scripts/backup.sh ./backups

# Restore from a backup file
./db/scripts/restore.sh ./backups/acc_20260225_143000.dump

# Manual backup via docker compose
docker compose exec db pg_dump -U acc -d acc --format=custom --compress=9 > backup.dump

# Manual restore
docker compose exec -T db pg_restore -U acc -d acc --clean --if-exists < backup.dump
```

## Tech Stack

| Layer     | Technology                                          |
|-----------|-----------------------------------------------------|
| Database  | PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale |
| Embeddings| Ollama with `nomic-embed-text` (768 dimensions)     |
| Backend   | Deno 2.0 + postgres.js                              |
| Frontend  | Vue 3 + TypeScript + Vite (planned)                 |
| Infra     | Docker Compose                                      |

## Development

### Run backend locally (without Docker)

```bash
# Prerequisites: Deno 2.x, PostgreSQL 17 with TimescaleDB, Ollama

# 1. Start PostgreSQL and Ollama locally
# 2. Apply schema
psql -U acc -d acc -f db/init/01-schema.sql
psql -U acc -d acc -f db/init/02-seed.sql

# 3. Pull the embedding model
ollama pull nomic-embed-text

# 4. Set environment variables
export DATABASE_URL="postgres://acc:your_password@localhost:5432/acc"
export OLLAMA_URL="http://localhost:11434"
export WS_PORT="3800"

# 5. Run with hot reload
cd backend
deno task dev
```

### Environment variables

| Variable         | Default                              | Description                |
|------------------|--------------------------------------|----------------------------|
| `DATABASE_URL`   | `postgres://acc:acc@localhost:5432/acc` | PostgreSQL connection      |
| `OLLAMA_URL`     | `http://localhost:11434`             | Ollama API endpoint        |
| `EMBED_MODEL`    | `nomic-embed-text`                   | Embedding model name       |
| `WS_PORT`        | `3800`                               | Server port                |
| `NODE_ENV`       | `development`                        | Environment mode           |
| `LOG_LEVEL`      | `info`                               | Log verbosity              |

## Memory System

ACC v3 includes a semantic memory system powered by vector embeddings:

1. **Storage**: When a memory is stored via `POST /api/memories`, it is immediately inserted into the `agent_memories` table with a null embedding. The embedding is generated asynchronously by Ollama using the `nomic-embed-text` model (768 dimensions).

2. **Embedding**: The `nomic-embed-text` model converts text into a 768-dimensional vector that captures semantic meaning. Similar concepts produce vectors that are close together in vector space.

3. **Search**: Semantic search via `POST /api/memories/search` works by:
   - Converting the query text into a vector using the same embedding model
   - Computing cosine similarity between the query vector and all stored memory vectors
   - Returning memories above the similarity threshold, ranked by relevance
   - Using the DiskANN index (pgvectorscale) for efficient approximate nearest neighbor search

4. **Use cases**:
   - Store agent learnings and decisions for cross-session recall
   - Build project-specific knowledge bases that agents can query
   - Track user preferences and patterns across interactions
   - Enable agents to "remember" context from previous sessions

5. **Automatic management**:
   - TimescaleDB handles data lifecycle (compression, retention)
   - Continuous aggregates pre-compute dashboard metrics hourly/daily
   - The `importance` field allows prioritizing critical memories in search results

## Contributing

Contributions are welcome. This project is in active development.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Please follow existing code style and include appropriate tests.
