Run the /radar tech radar scan to monitor your tech stack's ecosystem.

## Arguments

Parse the argument `$ARGUMENTS` to determine the action:
- No argument — Run a full scan and display the digest
- `watch <owner/repo>` — Add a GitHub repo to the watchlist
- `watch <owner/repo> --relevance "why it matters"` — Add with context
- `unwatch <slug>` — Remove an item from the watchlist
- `list` — Show the current watchlist
- `history` — Show past scan digests with dates
- `show <run-id>` — Re-display a specific past digest
- `ingest [run-id] --project <slug>` — Push notable findings into project memories
- `--since <days>` — Override lookback window (default: 30 days)

## Execution

### For watch/unwatch/list:
Use the ShikiMCP tools:

**List watchlist**: Use the `shiki_search` MCP tool with: `{ query: "radar watchlist", projectIds: [] }`

**Add repo**: Use the `shiki_save_event` MCP tool with:
```json
{ "type": "radar_watch_added", "scope": "radar", "data": { "slug": "owner/repo", "kind": "repo", "name": "RepoName", "sourceUrl": "https://github.com/owner/repo", "relevance": "why it matters", "tags": ["relevant-tag"] } }
```

**Remove**: Use the `shiki_save_event` MCP tool with: `{ "type": "radar_watch_removed", "scope": "radar", "data": { "watchId": "<uuid>" } }`

### For scan (default, no args):
1. Trigger scan: Use the `shiki_save_event` MCP tool with: `{ "type": "radar_scan_triggered", "scope": "radar", "data": { "sinceDays": 30 } }`
2. Wait a few seconds for GitHub API calls to complete
3. Fetch results: Use the `shiki_search` MCP tool with: `{ query: "radar scan <runId>", projectIds: [] }`
4. Fetch digest: Use the `shiki_search` MCP tool with: `{ query: "radar digest latest", projectIds: [] }`
5. Display the markdown digest to the user
6. Ask if user wants to ingest notable findings

### For history:
Use the `shiki_search` MCP tool with: `{ query: "radar scans history", projectIds: [] }`

### For ingest:
1. Resolve project ID from slug: Use the `shiki_search` MCP tool with: `{ query: "<project-slug>", projectIds: [] }`
2. Ingest findings: Use the `shiki_save_event` MCP tool with: `{ "type": "radar_ingest", "scope": "radar", "data": { "scanRunId": "<uuid>", "projectId": "<uuid>" } }`
3. Report how many memories were created

## Digest Display Format

When displaying the digest, render the markdown directly. The backend generates it in this format:

```markdown
## Tech Radar — 2026-03-09
**Scanned 10 items** | 3 updates | 1 breaking changes

### Breaking Changes
- **Deno** v1.x → v2.0 — Major version bump with breaking API changes

### Notable Updates
- **pgvector** 0.7.0 → 0.8.0 — Added HNSW index support
- **Vue.js** 3.4 → 3.5 — New features

### Stable (no changes)
TimescaleDB, Ollama, postgres.js
```

## Tips
- Run monthly or when starting a new project phase
- After viewing the digest, use `/ingest` for anything worth preserving
- Add project-specific repos with `--relevance` so the digest explains why they matter
