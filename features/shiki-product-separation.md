# Shiki Product Architecture — Separation of Concerns

> **Type**: Architecture Vision
> **Status**: Active (validated by @Daimyo 2026-03-19)
> **Supersedes**: monolithic shiki-ctl approach
> **Principle**: Linux philosophy — small tools, composable, piped together

---

## 1. The Realization

Shiki tried to be everything: orchestrator + TUI + review tool + dashboard + editor. The TUI review was the proof — built in a day, buggy in every aspect, worse than existing tools. **Linux didn't build its own text editor inside the kernel. It made vim a separate tool.**

## 2. Product Separation

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER WORKFLOW                             │
│  spec → implement → review → validate → ship → repeat           │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │ ShikiCore│  │ ShikiDB  │  │ ShikiQA  │  │ ShikiWS      │   │
│  │          │  │          │  │          │  │ (future)     │   │
│  │ AI       │  │ Knowledge│  │ Visual   │  │ Multi-user   │   │
│  │ Orchestr.│  │ Engine   │  │ QA       │  │ Workspaces   │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │
│       │              │              │               │            │
│  ┌────┴──────────────┴──────────────┴───────────────┴────┐      │
│  │              Unix Pipes + Event Stream                 │      │
│  │   shiki pr 6 | delta                                  │      │
│  │   shiki pr 6 | shiki-qa --web                         │      │
│  │   shiki spec "auth" | shiki-qa --swift                │      │
│  └───────────────────────────────────────────────────────┘      │
│                                                                  │
│  ┌───────────────────────────────────────────────────────┐      │
│  │              EXISTING TOOLS (not ours)                 │      │
│  │   gh · delta · diffnav · fzf · bat · tmux · claude    │      │
│  └───────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

### ShikiCore — The AI Orchestrator (what we keep in shiki-ctl)
- Event bus + event router
- Session lifecycle + registry + journal
- Agent personas + watchdog
- Heartbeat loop + dispatcher
- Recovery manager
- S3 spec syntax parser
- `@who #where /what` grammar
- **Does NOT render UIs. Produces data streams.**

### ShikiDB — The Git of AI Memory (separate product)
- Knowledge persistence (PostgreSQL + vector embeddings)
- MCP server (typed tools, validation, search)
- Decision chain traceability
- Partial replication (enterprise: team-scoped knowledge)
- Backup + encryption (VPS)
- **The memory that makes AI smarter over time**

### ShikiQA — Visual Review Tool (separate product)
- PR review with visual diff (code + screenshots)
- Swift QC for native snapshots
- Storybook/DSKintsugi for component library
- Web mode (--web) and native mode (--swift)
- Delta comparison (before/after screenshots)
- Receives data from ShikiCore via pipe
- `shiki pr 6 | shiki-qa --web`
- **Does NOT manage agents. Receives review data, shows visual results.**

### ShikiWS — Workspace Management (future, enterprise)
- Multi-user scoped access
- Team/project/company hierarchy
- Budget per user
- Onboarding: invite → install → scoped ShikiDB replica
- Admin: manage user scopes, knowledge access
- **The enterprise layer on top of Core + DB**

## 3. The Linux Philosophy Applied

```
LINUX                          SHIKI
─────                          ─────
kernel                    →    ShikiCore (event bus, agents, sessions)
filesystem (ext4, btrfs)  →    ShikiDB (knowledge persistence)
display server (X11, Wayland) → ShikiQA (visual review)
package manager (apt, pacman) → ShikiWS (workspace management)

ls | grep | sort          →    shiki pr 6 | delta
cat file | less           →    shiki log maya | bat
make && make test         →    shiki spec "auth" | shiki-qa --swift
```

**Tools Shiki uses, not builds:**
- `gh` — GitHub CLI (PRs, issues)
- `delta` — syntax-highlighted diff
- `diffnav` — interactive diff navigator
- `fzf` — fuzzy finder (we built one, should use theirs)
- `bat` — cat with syntax highlighting
- `tmux` — terminal multiplexer
- `claude` — AI agent (provider-agnostic)

## 4. Enterprise Scenario — Microsoft Example

```
1. Admin creates ShikiWS instance for Microsoft
2. New employee joins xbox-message team
3. Receives invite → installs ShikiWS
4. Gets: scoped ShikiDB (team knowledge only)
         projects/ui-xbox-message/
         projects/backend-xbox-message/
         $X daily budget
5. Works: shiki spec "message encryption" → implement → review
6. Reviews: shiki pr 42 | shiki-qa --web
           → code review + visual diff + component library
7. Ships: PR with visual evidence attached
8. Teammate reviews: same visual state in their ShikiQA
9. Cycle repeats
```

## 5. What Changes from Current Architecture

| Current (monolithic) | Target (separated) |
|---------------------|-------------------|
| TUI review inside shiki-ctl | ShikiQA as separate binary |
| FuzzyMatcher built-in | Use fzf (external tool) |
| PaletteRenderer in Swift | ShikiCore outputs data, tools render |
| Dashboard in shiki-ctl | ShikiQA or external dashboard |
| All 65 files in one package | Core (~30 files), QA (separate), DB (separate) |

## 6. What Stays in ShikiCore

The innovative part — what no one else has:
- Event stream pipeline (classify/enrich/route/interpret)
- Session lifecycle state machine
- Agent persona system with capability restrictions
- Living specs with S3 natural language syntax
- Knowledge-driven decisions (ShikiDB integration)
- `@who #where /what` intent grammar
- Recovery manager
- Watchdog escalation

## 7. The Workflow Modes

**--yolo mode**: spec → implement → TPDD validates → auto-merge. No human review.
**--review mode**: spec → implement → ShikiQA review → validate → merge. Human reviews.
**--team mode**: spec → implement → ShikiQA review → teammate review → merge. Team process.

All three are valid. The user chooses their quality level. Shiki adapts.
