Manage Shiki companies — the orchestration layer over projects.

## Usage

```
/company list                          # List all companies with status
/company create <slug> <project-slug>  # Register a project as a company
/company activate <slug>               # Set company status to active
/company pause <slug>                  # Pause a company (stops task processing)
/company archive <slug>                # Archive a company
/company budget <slug> [daily] [monthly]  # View or set budget caps
/company priority <slug> <0-99>        # Set wake priority (0=highest)
/company status <slug>                 # Detailed status with tasks/decisions
```

## Arguments

Parse `$ARGUMENTS` for subcommand and args.

## Implementation

All operations go through the ShikiMCP tools (native `shiki_*` MCP tools).

### `list`

Use the `shiki_list_companies` MCP tool to fetch all companies.

Display as a table:

```markdown
## Companies

| Slug | Name | Status | Priority | Tasks (P/R/B) | Decisions | Heartbeat |
|------|------|--------|----------|---------------|-----------|-----------|
```

Where P/R/B = pending/running/blocked task counts.

### `create <slug> <project-slug>`

1. Look up project by slug: Use the `shiki_search` MCP tool with: `{ query: "<slug>", projectIds: [] }` or list projects to find matching slug
2. If not found, error with "Project '<slug>' not found. Available: ..."
3. Create company: Use the `shiki_save_event` MCP tool with: `{ type: "company_created", scope: "orchestrator", data: { projectId: "<uuid>", slug: "<slug>", displayName: "<project name>" } }`
4. Confirm: "Company '<slug>' created for project '<name>'"

### `activate <slug>` / `pause <slug>` / `archive <slug>`

1. Find company by slug from list
2. Update status: Use the `shiki_save_event` MCP tool with: `{ type: "company_status_updated", scope: "orchestrator", data: { companyId: "<id>", status: "active" } }`

### `budget <slug> [daily] [monthly]`

- No amounts → show current budget + today's spend
- With amounts → PATCH budget object

### `priority <slug> <0-99>`

PATCH the priority field. Lower = higher priority = wakes first.

### `status <slug>`

Use the `shiki_search` MCP tool with: `{ query: "<slug> company status", projectIds: [] }` to fetch company details.

Display detailed view:

```markdown
## Company: <name> (<slug>)

**Status**: active | **Priority**: 3 | **Heartbeat**: healthy (2m ago)

### Budget
- Daily cap: $5.00 | Spent today: $1.23 (24.6%)
- Monthly cap: $150 | Spent this month: $42.50 (28.3%)

### Task Queue
| # | Title | Status | Priority | Source |
|---|-------|--------|----------|--------|

### Pending Decisions
| Tier | Question | Created |
|------|----------|---------|
```

## Rules

- Always confirm destructive operations (archive) before executing
- Show the result after each operation
- If MCP tools are unavailable, show a clear error: "ShikiMCP tools not available — check MCP server status"
