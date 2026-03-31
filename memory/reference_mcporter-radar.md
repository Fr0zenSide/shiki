---
name: mcporter — MCP-as-TypeScript-API / MCP CLI packager
type: reference
source: https://github.com/steipete/mcporter
discovered: 2026-03-31
relevance: HIGH
---

## What it is

`steipete/mcporter` wraps any MCP (Model Context Protocol) server as a plain TypeScript API — no protocol boilerplate, just typed function calls. It also supports packaging any MCP server as a standalone CLI binary.

## Why it matters to Shikki

Shikki's agent layer relies on MCP servers for tool exposure. mcporter eliminates the friction of hand-writing MCP call stubs by generating a typed TS facade. The dual mode:

1. **Library mode** — `import { myTool } from 'mcporter/my-mcp'` and call it like normal TS
2. **CLI mode** — `npx mcporter package ./my-mcp-server` → distributable CLI

This directly applies to:
- Shikki's skill tools that wrap MCP calls
- Any future Shikki MCP server that should also ship as a CLI (e.g. a `shiki` CLI for external users)
- Type safety on MCP tool arguments without manual interface definitions

## Key patterns to study

- How it generates TypeScript types from MCP server manifests
- How it handles streaming / progress from MCP tools
- CLI packaging pipeline (likely `pkg` or `esbuild` based)

## Action items

- [ ] Test wrapping Shikki's existing MCP server(s) through mcporter
- [ ] Evaluate generated types against current manual MCP stubs
- [ ] Assess CLI packaging for `shiki` distribution
