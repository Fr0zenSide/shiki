Run the /ingest pipeline to import external knowledge into Shiki's memory.

## Arguments

Parse the argument `$ARGUMENTS` to determine the action:
- `<github-url>` — Clone and analyze a GitHub repository
- `<url>` — Fetch and extract content from a web URL
- `<local-path>` — Read and analyze a local directory or file
- `"<raw text>"` — Ingest raw text directly (quoted)
- `sources [--project <slug>]` — List all ingestion sources for a project
- `status <source-id>` — Check status of a specific ingestion
- `delete <source-id>` — Delete a source and all its memories

## Configuration (optional flags in argument)

- `--project <slug>` — Target project slug (default: auto-detect from cwd or use "shiki")
- `--category <cat>` — Force a category for all chunks
- `--importance <N>` — Set importance 0-10 (default: 1.0)
- `--dry-run` — Show what would be ingested without storing

## Execution

### Step 0: Resolve project ID
Query `GET http://localhost:3900/api/projects` to find the project UUID from the slug.
If no `--project` flag, detect from the current working directory name or default to "shiki".

### For GitHub repos:
1. Clone the repo to `/tmp/shiki-ingest-<name>` (shallow clone, `git clone --depth 1`)
2. Read key files: README, architecture docs, config files, main source files
3. **Skip**: binary files, node_modules, build artifacts, lock files, .git, vendor, dist
4. For each relevant file, **extract structured insights** — do NOT store raw file contents:
   - What does this file/module do?
   - What patterns/conventions does it use?
   - What are the key interfaces/types/exports?
   - What architectural decisions are embedded here?
5. Chunk the extracted insights — aim for self-contained pieces (~1000-1500 chars each)
6. POST all chunks to `http://localhost:3900/api/ingest` as a single batch
7. Clean up the temp clone
8. Report results: inserted, duplicates skipped, total

### For URLs:
1. Fetch the URL content using WebFetch
2. Extract meaningful text (strip HTML boilerplate)
3. Summarize and chunk the useful content
4. POST to the ingest API

### For local paths:
1. Read files matching common source patterns (*.ts, *.swift, *.py, *.md, etc.)
2. Same structured extraction as GitHub repos
3. POST to the ingest API

### For raw text:
1. Chunk if longer than 1500 chars (with 200 char overlap)
2. POST directly to the ingest API

## Smart Extraction Rules

**CRITICAL**: Do NOT ingest raw file contents. Extract structured knowledge:
- Summarize architecture decisions and rationale
- Identify design patterns with concrete examples
- Extract API contracts (endpoints, types, schemas)
- Note configuration conventions and defaults
- Capture error handling strategies
- Document dependency relationships
- Extract README insights (purpose, setup, key concepts)

Each chunk should be a **self-contained piece of knowledge** that an AI agent can use without needing surrounding context. Include enough specificity (file paths, function names) to be actionable.

## API Reference

```bash
# Ingest chunks
curl -X POST http://localhost:3900/api/ingest \
  -H "Content-Type: application/json" \
  -d '{"projectId":"<uuid>","sourceType":"github_repo","sourceUri":"https://github.com/org/repo","displayName":"RepoName","chunks":[{"content":"...","category":"architecture"}]}'

# List sources
curl http://localhost:3900/api/ingest/sources?project_id=<uuid>

# Delete source
curl -X DELETE http://localhost:3900/api/ingest/sources/<source-id>
```

## Response Format

After ingestion, display a summary:

```
Ingested: <repo/url/path>
  Chunks: X inserted, Y duplicates skipped, Z total
  Source ID: <uuid>
  Categories: architecture (3), api (2), testing (1)
```
