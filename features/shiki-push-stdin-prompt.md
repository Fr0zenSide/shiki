# shiki push — Stdin Prompt Ingestion

> Phase: Backlog (not started)
> Priority: P2
> Added: 2026-03-18

## Summary

`shiki push` accepts text from stdin or CLI argument and delivers it to the running Shiki orchestrator as a prompt. If the orchestrator isn't running, it appends to a local scratchpad. On startup, Shiki reads the scratchpad, absorbs it as context, and clears it.

## Motivation

Enable Unix-pipe workflows where any tool can feed context into Shiki without coupling. The canonical use case is `flsh read #id --raw | shiki push` — but Shiki never knows about Flsh. It just receives text.

This is **context sharing, not task dispatching.** No queue semantics. The scratchpad is a flat file the user can inspect.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Input modes | stdin + positional arg | `echo "x" \| shiki push` and `shiki push "x"` both work |
| Offline storage | `~/.shiki/inbox.md` | Flat file, inspectable, git-friendly |
| Semantics | Scratchpad (not queue) | Context sharing, not stale task dispatching |
| Startup behavior | Read → absorb → clear | Orchestrator treats inbox as "what happened while I was off" |
| Coupling | Zero | Shiki has no knowledge of the source tool |

## Interface

```bash
# Direct text
shiki push "use libsql for the cache layer"

# Piped from any tool
flsh read #a3f2 --raw | shiki push
echo "rethink the auth flow" | shiki push
cat notes.txt | shiki push

# Multiple notes piped over time (offline)
# → all append to ~/.shiki/inbox.md
# → on next `shiki start`, orchestrator reads and clears
```

## Scratchpad Format (`~/.shiki/inbox.md`)

```markdown
---
pushed: 2026-03-18T14:32:00Z
---
use libsql for the cache layer

---
pushed: 2026-03-18T15:10:00Z
---
rethink the auth flow — the middleware rewrite changes assumptions
```

Simple append-only. Timestamp per entry. Orchestrator reads all, absorbs as context, truncates file.

## Implementation Scope

### Shiki CLI (Swift)
1. New `PushCommand` subcommand
2. Read from stdin (detect pipe) or positional argument
3. If orchestrator tmux session exists → deliver via `tmux send-keys` or socket
4. If not → append to `~/.shiki/inbox.md`
5. Startup: `InboxReader` service reads and clears scratchpad

### Delivery to live orchestrator
- Option A: `tmux send-keys` to orchestrator pane (simple, works now)
- Option B: Unix domain socket (cleaner, future)
- Start with A, migrate to B when event bus lands

## Companion: Flsh `--raw` flag

Flsh needs a small change to enable clean piping:
- `flsh read #id --raw` → outputs body text only, no YAML frontmatter
- Auto-detect: if stdout is not a TTY, strip frontmatter automatically

This is tracked separately in the Flsh backlog — zero dependency on Shiki.

## Input Protocol (two modes)

**Plain text** → treated as prompt/context. Shiki absorbs it as-is.

```bash
echo "use libsql for cache" | shiki push
flsh read #a3f2 --raw | shiki push
```

**JSON with metadata** → structured data. Shiki Core auto-resolves routing based on fields.

```json
{
  "source": "ntfy",
  "action": "approve",
  "context": "permission_request",
  "tool": "Edit",
  "file": "Sources/ShipService.swift"
}
```

Start with ntfy as first structured client (action buttons → JSON → shiki push). Then Flsh (plain text). Then iOS app (both modes). Protocol grows from real usage — same evolutionary path as MCP (simple spec → standard).

## Non-Goals

- Upfront protocol design beyond text + JSON
- Knowing which tool produced the input (source field is optional metadata, not required)
- Interactive confirmation before delivery
