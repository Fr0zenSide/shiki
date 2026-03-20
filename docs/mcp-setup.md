# Shiki — MCP Server Setup

## Overview

Shiki uses [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) servers to give AI assistants access to development tools and documentation. The setup is layered: a **global config** at the shiki root provides shared servers, while each project can add **project-specific servers**.

When you work on any project, your AI assistant automatically has access to **both** the shiki-level MCP servers and the project's own MCP servers.

## Architecture

```
shiki/
├── .mcp.json                  ← Global MCP servers (available to all projects)
└── projects/
    ├── wabisabi/.mcp.json     ← Project-specific (xcode-tools + sosumi)
    ├── Maya/.mcp.json         ← Project-specific (xcode-tools + sosumi)
    └── ...
```

## Global MCP Servers (shiki root)

File: `shiki/.mcp.json`

These servers are available when working from the shiki root or any subdirectory:

| Server | Purpose | Command |
|--------|---------|---------|
| *(none yet)* | — | — |

> Add shared servers here as the team adopts cross-project tools (e.g., a shared database MCP, CI/CD server, etc.)

## Project-Specific MCP Servers

### iOS Projects (wabisabi, Maya)

File: `projects/<name>/.mcp.json`

| Server | Purpose | Command |
|--------|---------|---------|
| **xcode-tools** | Build, test, preview, navigate Xcode projects | `xcrun mcpbridge` (local) |
| **sosumi** | Apple documentation search (AI-friendly markdown) | `npx -y mcp-remote https://sosumi.ai/mcp` (remote) |

```json
{
  "mcpServers": {
    "xcode-tools": {
      "command": "xcrun",
      "args": ["mcpbridge"]
    },
    "sosumi": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://sosumi.ai/mcp"]
    }
  }
}
```

### Other Projects

| Project | Type | MCP | Notes |
|---------|------|-----|-------|
| flsh | Swift Package | — | No Xcode project; add if needed |
| swiftui-qc | Docs/CLI | — | Not an app project |
| brainy | — | — | Add per need |
| ail | — | — | Add per need |
| fzf | — | — | Add per need |
| kintsugi-ds | Design System | — | Add per need |

## How MCP Resolution Works

Claude Code (and compatible tools) resolve `.mcp.json` by walking up the directory tree:

1. Start from the current working directory
2. Load `.mcp.json` if present
3. Walk up to parent directories, merging any `.mcp.json` found
4. Global user config (`~/.claude/.mcp.json`) is also merged

This means when you open a terminal in `shiki/projects/wabisabi/`:
- **wabisabi's** `.mcp.json` is loaded (xcode-tools, sosumi)
- **shiki's** `.mcp.json` is loaded if it exists (global servers)
- Both sets of servers are available simultaneously

## Adding a New MCP Server

### To a single project
Edit `projects/<name>/.mcp.json` and add your server entry.

### To all projects (global)
Edit `shiki/.mcp.json` — it will be available everywhere under shiki.

### Server types
- **Local**: Runs a binary on your machine (e.g., `xcrun mcpbridge`)
- **Remote**: Connects to a hosted service (e.g., `npx -y mcp-remote <url>`)

## Prerequisites

- **xcode-tools**: Xcode installed with `xcrun` in PATH
- **sosumi**: Node.js / npm installed (`npx` available)
