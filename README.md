# 四季 Shiki — Professional Operating System for Builders

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![v0.2.0](https://img.shields.io/badge/version-0.2.0-green.svg)]()
[![Swift](https://img.shields.io/badge/Built%20with-Swift-orange.svg)]()

> One command to launch your multi-project workspace. AI-augmented development with persistent memory, quality gates, and a team of specialized agents.

Shiki gives your AI coding agent a team, a memory, and a process — across every project. Your agent remembers decisions, follows TDD, reviews its own work through specialized personas, and all of this carries over between sessions and projects.

## Quick Start

```bash
# Install
git clone https://github.com/Fr0zenSide/shiki.git
cd shiki && cd tools/shiki-ctl && swift build
ln -sf $(pwd)/.build/debug/shiki-ctl ~/.local/bin/shiki

# Launch
shiki start
```

That's it. Shiki detects your environment, starts Docker, boots the backend, shows your dashboard, and drops you into tmux.

```
Shiki — Smart Startup [shiki]

[1/6] Environment
  ✓ Docker daemon
  ✓ Colima VM
  ✓ Backend (localhost:3900)
  ✓ LM Studio (127.0.0.1:1234)
...
╔══════════════════════════════════════════════════════════════╗
║  SHIKI v0.2.0                                ● System Ready ║
╠═════════════════════════╦════════════════════════════════════╣
║  Last Session           ║  Upcoming                          ║
║  ✓ maya: 3 tasks done   ║  → maya: 5 pending                 ║
║  ✓ wabisabi: 2 done     ║  → flsh: 2 pending                 ║
╠═════════════════════════╩════════════════════════════════════╣
║  Session Stats: +127 / -43 lines (maya)  ≈ mature            ║
║  Weekly: +93,706 / -15,906 lines across 4 projects           ║
╠══════════════════════════════════════════════════════════════╣
║  4 T1 decisions pending · 0 stale · $0 spent today           ║
╚══════════════════════════════════════════════════════════════╝
```

## Features

### CLI Commands

| Command | What it does |
|---------|-------------|
| `shiki start` | Smart startup — detects env, boots Docker, shows dashboard, auto-attaches tmux |
| `shiki stop` | Stop with confirmation (shows active task count) |
| `shiki restart` | Restart heartbeat, preserve tmux session |
| `shiki status` | Workspace + company overview with health indicators |
| `shiki board` | Rich board — progress bars, budget, health per company |
| `shiki decide` | Answer pending decisions (multiline input supported) |
| `shiki report` | Daily cross-company digest |
| `shiki history` | Session transcript viewer |

### Development Process

| Command | When | Docs |
|---------|------|------|
| `/quick "fix X"` | Small change (< 3 files) | [quick-flow.md](.claude/skills/shiki-process/quick-flow.md) |
| `/md-feature "X"` | New feature | [feature-pipeline.md](.claude/skills/shiki-process/feature-pipeline.md) |
| `/tdd` | Run tests, fix all failures | [tdd.md](.claude/skills/shiki-process/tdd.md) |
| `/pre-pr` | Before any PR (9 quality gates) | [pre-pr-pipeline.md](.claude/skills/shiki-process/pre-pr-pipeline.md) |
| `/review <PR#>` | Interactive PR review | [pr-review.md](.claude/skills/shiki-process/pr-review.md) |
| `/dispatch` | Parallel implementation | [parallel-dispatch.md](.claude/skills/shiki-process/parallel-dispatch.md) |
| `/ingest <url>` | Import knowledge into memory | — |
| `/radar scan` | Monitor tech stack updates | — |

### Agent Team

Specialized personas that review work through different lenses:

| Agent | Role |
|-------|------|
| **@Sensei** | CTO — architecture, code quality |
| **@Hanami** | Designer — UX, accessibility |
| **@Kintsugi** | Philosophy — design principles |
| **@Ronin** | Reviewer — security, edge cases |
| **@Shogun** | Strategy — market, positioning |
| **@Daimyo** | Founder — final decisions |

### Memory System

Persistent semantic memory powered by vector embeddings (TimescaleDB + pgvector). Your agent's context survives across sessions and projects.

- `/ingest` — import repos, URLs, docs into searchable knowledge base
- `/radar` — monitor GitHub repos for breaking changes and updates
- `/remember` — recall past decisions and context

### Orchestrator

The heartbeat loop manages multiple companies/projects autonomously:

- Dynamic task dispatch based on priority and budget
- Per-company tmux windows (appear/disappear as tasks run)
- ntfy push notifications for pending decisions
- Session transcripts with git stats

## Architecture

```
shiki/
├── tools/shiki-ctl/        ← Swift CLI (shiki binary)
│   ├── Sources/ShikiCtlKit/ ← Services: BackendClient, HeartbeatLoop, SessionStats
│   └── Tests/               ← 38 tests, 8 suites
├── src/backend/             ← Deno REST API + WebSocket
├── src/frontend/            ← Vue 3 dashboard
├── packages/                ← Shared SPM: CoreKit, NetKit, SecurityKit
├── projects/                ← Your projects (each its own git repo)
└── .claude/skills/          ← Process skills, agent definitions
```

| Service | Port | Stack |
|---------|------|-------|
| Backend | 3900 | Deno + postgres.js + Zod |
| Database | 5433 | PostgreSQL 17 + TimescaleDB + pgvector |
| Embeddings | 11435 | Ollama (nomic-embed-text) or LM Studio |
| Frontend | 5174 | Vue 3 + Vite |

## tmux Navigation

```
Tab 1: orchestrator  ← heartbeat loop + startup dashboard
Tab 2: board         ← dynamic task panes (auto-managed)
Tab 3: research      ← 4 panes: INGEST · RADAR · EXPLORE · SCRATCH
```

| Action | Shortcut |
|--------|----------|
| Switch tabs | `Opt + Shift + ←/→` |
| Switch panes | `Opt + ←/↑/↓/→` |
| Zoom pane | `Ctrl-b z` |
| Scroll up | `Ctrl-b [` |
| Detach | `Ctrl-b d` |

Full cheat sheet: [docs/cheatsheet.md](docs/cheatsheet.md)

## Roadmap

- [x] Smart startup with environment detection
- [x] Session productivity stats (+/- lines, maturity indicator)
- [x] Multiline input for decisions
- [x] zsh autocompletion (auto-refreshes on rebuild)
- [x] Dynamic tmux session naming (multi-workspace ready)
- [ ] `shiki wizard` — first-time onboarding
- [ ] `shiki new` — company/project CRUD
- [ ] Multi-workspace support (workspace registry, knowledge isolation)
- [ ] Backup strategy (per-workspace, GitHub Action, ntfy alerts)
- [ ] Collaborator access (auth + knowledge projections)
- [ ] AI provider agnostic orchestration

## License

[AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0) — see [LICENSE](LICENSE) for details.

---

Built with [Claude Code](https://claude.ai/claude-code) · Powered by the @shi team
