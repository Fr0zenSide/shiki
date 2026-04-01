---
name: Peekaboo Reference
type: reference
description: macOS Swift CLI + optional MCP server for AI agent screenshot capture — directly usable Shikki MCP tool
source: https://github.com/steipete/Peekaboo
discovered: 2026-04-01
relevance: HIGH
---

## What It Is

`Peekaboo` by steipete is a macOS CLI and optional MCP server that enables AI agents to capture screenshots of applications or the entire screen. Written in Swift, native macOS. Trended at 13 stars today (2026-04-01) in Swift trending.

Note: This is from the same author as `steipete/mcporter` (already HIGH-rated, 03-31), who has established a pattern of building high-quality Swift MCP tooling for Claude Code.

## Why It Matters to Shikki

Shikki's agents currently operate blind — they cannot see the visual state of applications. Peekaboo provides the missing visual input primitive:

- **MCP server mode** — drops directly into Shikki's MCP tool set; agents can call `peekaboo_screenshot` as a tool
- **CLI mode** — usable in Shikki skill pipelines via Bash for specific screenshot capture steps
- **App-targeted capture** — can capture a specific app window, not just the full screen

This directly enables new Shikki capabilities:
- Visual verification steps in `/pre-pr` (screenshot UI diff)
- Visual agent context in `/dispatch` runs (agents see the current app state)
- Screenshot-based documentation generation

## Integration Pattern

```
# As MCP server (add to Shikki's MCP config):
{
  "mcpServers": {
    "peekaboo": {
      "command": "peekaboo",
      "args": ["mcp"]
    }
  }
}

# As CLI in a skill:
SCREENSHOT=$(peekaboo capture --app "Xcode" --output /tmp/screen.png)
```

## Relationship to steipete/mcporter

mcporter wraps MCP servers as typed TS APIs. Peekaboo is an MCP server. These two tools compose naturally:
- Use Peekaboo as the MCP server
- Use mcporter to wrap Peekaboo's screenshot tool as a typed TS function callable from Shikki's TypeScript skill layer

## Action Items

- [ ] Install Peekaboo on macOS development machine and test screenshot capture CLI
- [ ] Configure as MCP server in a test Shikki session; verify `peekaboo_screenshot` tool is callable by Claude
- [ ] Design a visual verification step for `/pre-pr` that uses Peekaboo to capture UI state
- [ ] Evaluate composing with mcporter for typed TS screenshot function (see `reference_mcporter-radar.md`)
