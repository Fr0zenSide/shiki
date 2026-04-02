# Radar: AI Coding Tools Architecture Patterns

**Date**: 2026-04-02
**Scope**: Amp (Sourcegraph), Factory/Droid, Claude Code (Anthropic), OpenCode (Anomaly)
**Purpose**: Extract architecture patterns for Shikki backlog

---

## 1. Amp (Sourcegraph)

**GitHub**: `sourcegraph/amp-contrib`, `sourcegraph/amp-examples-and-guides`, `sourcegraph/amp.nvim`, `sourcegraph/amp-sdk-demo`, `sourcegraph/cra-github`
**Product**: CLI + Web + IDE (Neovim plugin, VS Code via ACP)
**Community repo (ampcode org)**: `ampcode/amp-contrib` (curated skills, tools, MCPs)

### Architecture

- **Single-agent with subagent delegation**. One primary agent that can fork subagents for complex tasks. Not a multi-agent swarm -- more like Claude Code's model.
- **Thread-based persistence**. Threads sync to ampcode.com across devices. `amp threads new|continue|fork|share|compact`. Fork preserves parent context in child thread.
- **Three execution modes**: Interactive (TUI), Execute (`amp -x`), and Piping/Streaming (`stdin | amp`). Execute mode is key for CI/CD integration.
- **SDK**: TypeScript SDK for programmatic access. Supports multi-turn sessions, custom tool registration. Demo shows automated JWT-to-PASETO migration using custom output tools.

### Context Strategy

- **AGENT.md hierarchy**: Root-level, subdirectory-level, and global `~/.config/AGENT.md`. Scoped instructions per directory -- similar to Claude's CLAUDE.md but with explicit hierarchy documentation.
- **Built-in code search agent** (`codebase_search_agent`) -- leverages Sourcegraph's core competency. Semantic code search, not just grep.
- **Thread compaction**: `/compact` command compresses conversation history. Manual trigger, not automatic.
- **Thread forking**: Create new threads from existing ones, preserving full parent context. Elegant branching model for exploration vs. execution.
- **@ mentions**: `@filename` for fuzzy file search in prompts. File references with line ranges (`@file.ts#L10-L20`).

### Toolbox System (Novel)

- **External executable tools**: Any script (JS/Python/Bash) in `$AMP_TOOLBOX` directory becomes an agent tool. Two actions: `describe` (returns tool schema) and `execute` (runs the tool). Simple stdin/stdout protocol.
- This is more flexible than MCP for simple tools -- no server lifecycle, just executables. Similar to Claude Code hooks but for tool registration rather than event interception.

### Code Review Agent (CRA)

- Separate product: GitHub Action or self-hosted webhook service.
- Full repository context (not just diff). Agent can read any file before commenting.
- PR commands: `@amp fill` (auto-describe PR), `@amp review`, `@amp security`.
- Maximum 10 inline comments per review, prioritizing critical issues.

### Key Patterns for Shikki

1. **Thread forking** -- branching conversation context for exploration without polluting main thread
2. **Toolbox protocol** -- `describe`/`execute` on plain executables, no server needed
3. **Three execution modes** -- interactive/execute/pipe covers CLI, CI, and scripting
4. **Code search agent as built-in tool** -- dedicated subagent for semantic search

---

## 2. Factory / Droid

**GitHub**: `Factory-AI/factory` (692 stars), plus ecosystem repos
**Product**: CLI (`droid`) + Web + Slack/Teams + Linear/Jira + Mobile + VS Code + JetBrains + Zed
**Agent**: "Droid" -- claims top performance on Terminal-Bench

### Architecture

- **Single-agent with skill invocation**. Droid decides which skills to use based on task context -- skills are model-invoked, not user-typed commands.
- **SDKs in TypeScript and Python**. Both wrap `droid exec` subprocess via JSON-RPC 2.0. Multi-turn sessions with `createSession()` / `resumeSession()`. Session resumption by ID is a first-class feature.
- **Permission handler API**: Programmatic tool confirmation with `ProceedOnce`, `AllowAlways`, `Deny` outcomes. SDK exposes this as a callback.
- **GitHub Actions**: `droid-action` for `@droid fill|review|security` commands on PRs. Separate `droid-code-review` action for auto-review on non-draft PRs.

### Skills System (Novel)

- **SKILL.md format**: Each skill is a markdown file with YAML frontmatter (`name`, `description`) + instructions body. Extremely lightweight.
- **Discovery locations**: Workspace (`.factory/skills/`) and Personal (`~/.factory/skills/`). Two-tier, checked into git or personal.
- **Model-invoked**: The agent decides when to activate a skill based on task description match. No explicit `/command` needed.
- **Composable**: Skills chain together in larger workflows.
- **Token-efficient**: Lightweight by design -- not bloated system prompts.

### Plugin System

- **Plugin marketplace** via GitHub repos. `droid plugin marketplace add <url>`, `droid plugin install <name>`.
- **Plugin structure**: `.factory-plugin/plugin.json` + `skills/` + `droids/` + `commands/` + `mcp.json` + `hooks.json`. Very similar to Claude Code's plugin structure.
- **Cross-tool compatibility**: Plugins declare compatibility with Agent Skills spec. Work across Droid, Claude Code, Cursor, Codex, Windsurf, Gemini CLI.

### ESLint Plugin (Novel Pattern)

- **Linters as agent directors**. Factory's thesis: custom lint rules steer AI agents toward better code. 145 stars, fully AI-generated codebase.
- Rules enforce file organization (enums in `enums.ts`, types in `types.ts`, constants in `constants.ts`), naming conventions, test colocation, structured logging.
- Key insight: **deterministic constraints (linters) complement probabilistic agents (LLMs)**. The linter catches what the agent misses, and the agent learns from linter feedback.
- Blog posts: "Using Linters to Direct Agents", "Agent Readiness".

### SERA Research (Allen AI collaboration)

- **Soft-Verified Efficient Repository Agents**: Data generation + training pipeline for repository-level coding agents.
- Stage pipeline: generate -> distill_stage_one -> distill_stage_two -> eval -> postprocess.
- Supports specialization to specific codebases (Django, Sympy, personal repos).
- Sharding for parallel data generation across multiple inference servers.

### Key Patterns for Shikki

1. **Model-invoked skills** -- agent selects skills by description match, not user commands
2. **Linters as agent guardrails** -- deterministic rules complementing probabilistic agents
3. **Session resumption by ID** -- reconnect to previous sessions programmatically
4. **Cross-tool plugin compatibility** -- Agent Skills spec as interop standard
5. **SKILL.md format** -- minimal frontmatter + instructions, extremely portable

---

## 3. Claude Code (Anthropic)

**GitHub**: `anthropics/claude-code` (135k+ stars equivalent in ecosystem)
**Product**: CLI + VS Code + JetBrains + GitHub (`@claude` in PRs)

### Architecture

- **Single-agent with subagent delegation**. Primary agent spawns subagents for parallel tasks. Subagents inherit permission settings.
- **Hooks system**: `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop` hooks. Event-driven, can block or modify tool calls.
- **Plugin system**: `.claude-plugin/plugin.json` + commands/ + agents/ + skills/ + hooks/ + `.mcp.json`. Rich ecosystem -- 14+ official plugins covering code review, feature dev, security, git workflows.
- **SDK**: TypeScript `@anthropic-ai/claude-code` package. Subprocesses orchestration.

### Context Strategy

- **CLAUDE.md hierarchy**: Project root + subdirectories + `~/.claude/CLAUDE.md` global.
- **Auto-memory**: `~/.claude/projects/` stores per-project memories that persist across conversations.
- **Tools**: Glob, Grep, Read, Edit, Write, Bash -- purpose-built for each operation. No generic "file" tool.
- **Compaction**: Automatic context summarization when approaching limits.

### Plugin Highlights

- **code-review plugin**: 5 parallel Sonnet agents (CLAUDE.md compliance, bug detection, historical context, PR history, code comments) with confidence-based scoring to filter false positives. Multi-agent review is the most sophisticated of all tools reviewed.
- **hookify plugin**: Meta-tool that analyzes conversation patterns and generates hooks to prevent unwanted behaviors. Self-modifying agent constraints.
- **ralph-wiggum plugin**: Autonomous iteration loops. Agent works on same task repeatedly until completion, intercepting exit attempts to continue. Novel pattern for persistent autonomous work.
- **feature-dev plugin**: 7-phase structured workflow with specialized agents (code-explorer, code-architect, code-reviewer).

### Key Patterns for Shikki

1. **Multi-agent review with confidence scoring** -- parallel specialized reviewers + score-based filtering
2. **Hookify (meta-constraint generation)** -- agent that generates its own behavioral constraints
3. **Autonomous iteration loops** -- ralph-wiggum pattern for persistent work until completion
4. **Purpose-built tools** -- Glob/Grep/Read/Edit vs generic "file" tool improves accuracy

---

## 4. OpenCode (Anomaly)

**GitHub**: `anomalyco/opencode` (135k stars), TypeScript
**Product**: CLI TUI + Desktop App (Electron) + SDK + Slack integration

### Architecture

- **Client/server architecture**. The server runs locally, TUI is just one client. Mobile app can drive the same server remotely. This is the most architecturally distinct approach.
- **Dual agents**: `build` (full-access, default) and `plan` (read-only, denies edits, asks permission for bash). Plus `@general` subagent for complex searches.
- **Event bus + event sourcing**: `SyncEvent` system for session replayability. Events are recorded with sequence IDs, replayed by projectors. Bus events and sync events are unified -- sync events auto-republish as bus events.
- **Effect-TS runtime**: Uses Effect for composition, tracing, error handling, resource management. `Effect.fn` for named/traced effects, `InstanceState` for per-directory state with automatic cleanup.
- **mDNS discovery**: Server announces itself on local network for client discovery.

### Context Strategy

- **LSP integration**: Native Language Server Protocol support for code intelligence. Go (`gopls`) support out of the box, extensible to any LSP-compatible language.
- **Auto-compact**: Automatic summarization at 95% context window usage. Creates new session with summary. Enabled by default.
- **Snapshot system**: File change tracking during sessions.
- **Plugin system**: Codex and GitHub Copilot plugins as auth/provider adapters.

### Session Sync (Novel)

- **Event sourcing for sessions**: Every session mutation is a `SyncEvent` with type, version, aggregate ID, and sequence number. Single-writer model (one device controls, others replay).
- **Projectors**: Handle effects and perform mutations from events. Installed at server startup.
- **Bus integration**: Sync events transparently integrate with the existing `Bus` pub/sub system. `Bus.subscribe(SyncEvent, handler)` works seamlessly.
- **Schema versioning**: Events have version numbers for forward compatibility.

### Package Architecture

18 internal packages: `app`, `console`, `containers`, `desktop-electron`, `desktop`, `docs`, `enterprise`, `extensions`, `function`, `identity`, `opencode` (core), `plugin`, `script`, `sdk`, `slack`, `storybook`, `ui`, `util`, `web`.

Core source modules: `agent`, `bus`, `session`, `sync`, `snapshot`, `plugin`, `skill`, `worktree`, `server`, `mcp`, `lsp`, `permission`, `provider`, `tool`, `cli`, `command`, `config`, `project`, `ide`, `acp`.

### Key Patterns for Shikki

1. **Client/server split** -- server runs locally, multiple clients (TUI, desktop, mobile, Slack)
2. **Event sourcing for session state** -- replayable, syncable, versionable sessions
3. **Dual agents (build/plan)** -- read-only exploration mode vs full-access execution mode
4. **LSP integration** -- leveraging language servers for code intelligence beyond grep
5. **Auto-compact at 95%** -- proactive context management without user intervention

---

## Comparative Analysis

### Agent Architecture

| Tool | Model | Subagents | Multi-agent Review |
|------|-------|-----------|-------------------|
| **Amp** | Single + subagent delegation | Yes, for complex tasks | No (separate CRA product) |
| **Factory/Droid** | Single + model-invoked skills | No explicit subagents | No (single reviewer) |
| **Claude Code** | Single + subagent delegation | Yes, parallel spawning | Yes (5 parallel reviewers) |
| **OpenCode** | Dual (build/plan) + @general | Yes, @general subagent | No |

### Context Strategy

| Tool | Primary Context | Compaction | Persistence |
|------|----------------|------------|-------------|
| **Amp** | AGENT.md + code search agent | Manual `/compact` | Thread sync to cloud |
| **Factory/Droid** | SKILL.md + linter feedback | Not documented | Session resumption by ID |
| **Claude Code** | CLAUDE.md + auto-memory | Automatic | Per-project memory files |
| **OpenCode** | LSP + auto-compact | Automatic at 95% | Event-sourced sessions |

### Autonomy Level

| Tool | Default Autonomy | Permission Model | CI/CD Mode |
|------|-----------------|------------------|------------|
| **Amp** | Interactive with approval | Built-in, no API | `amp -x` execute mode |
| **Factory/Droid** | Interactive with approval | SDK callback API | `droid exec` |
| **Claude Code** | Interactive with approval | settings.json allowlists | `claude -p` |
| **OpenCode** | Interactive, plan mode read-only | Per-agent permissions | `-p` prompt mode |

### Plugin/Extension Model

| Tool | Format | Discovery | Cross-tool |
|------|--------|-----------|------------|
| **Amp** | Toolbox executables + MCP | `$AMP_TOOLBOX` dir | No |
| **Factory/Droid** | SKILL.md + plugin.json | Marketplace repos | Yes (Agent Skills spec) |
| **Claude Code** | plugin.json + commands/agents/skills/hooks | Plugin marketplaces | Partial |
| **OpenCode** | Plugin modules + skills | Built-in + community | No |

---

## Novel Ideas Inventory

### From Amp
- **Thread forking with parent context preservation** -- branch exploration without pollution
- **Toolbox protocol** (describe/execute on executables) -- zero-server tool registration
- **Sourcegraph code search as built-in agent tool** -- semantic, not syntactic, code search

### From Factory/Droid
- **Model-invoked skills** -- agent reads skill descriptions and decides when to activate
- **Linters as agent directors** -- deterministic guardrails for probabilistic agents
- **Session resumption by ID** -- reconnect to exact session state programmatically
- **Cross-tool plugin interop** via Agent Skills spec
- **SERA data pipeline** -- specialization training for repository-specific agents

### From Claude Code
- **Multi-agent review with confidence scoring** -- parallel specialized reviewers
- **Hookify** -- meta-tool that generates behavioral constraints from conversation analysis
- **Ralph-wiggum pattern** -- autonomous iteration loops with exit interception
- **Purpose-built tools** -- specialized tools (Glob vs Grep vs Read) over generic abstractions

### From OpenCode
- **Client/server architecture** -- decouple agent runtime from UI
- **Event sourcing for sessions** -- replayable, syncable, versionable state
- **Dual agents (build/plan)** -- read-only mode for safe exploration
- **LSP integration** -- language server intelligence for code understanding
- **Auto-compact at 95%** -- proactive, not reactive, context management

---

## 5 Actionable Items for Shikki Backlog

### 1. [P1] Client/Server Split -- ShikiCore as Headless Server

**Source**: OpenCode's client/server architecture
**What**: Decouple ShikiCore engine from TUI/CLI frontend. ShikiCore runs as a local server (or systemd service), exposing a typed API. TUI, `shikki` CLI, ntfy actions, and future iOS/macOS clients are all just clients.
**Why**: Enables remote control (mobile app driving local agent), multi-client sessions, and clean separation of concerns. OpenCode proves this works with TUI + Desktop + Slack as clients to one server.
**How**: ShikiCore already has lifecycle FSM and event persistence. Add a local HTTP/WebSocket server layer (or Unix socket). Server announces via mDNS for local discovery. TUI connects as client.
**Relevance to existing backlog**: Aligns with P3 "Native apps" and the ntfy evolution toward `shiki push` as universal input. Makes both achievable.

### 2. [P1] Event-Sourced Session State

**Source**: OpenCode's SyncEvent system
**What**: Make all session mutations event-sourced. Each action (spec created, test run, review posted, fix applied) becomes a versioned event with sequence ID. Projectors handle side effects. Sessions become replayable and syncable.
**Why**: Enables session resumption after crash/compaction (no re-reading everything), audit trails, and future multi-device sync. OpenCode's single-writer model keeps it simple -- no distributed clocks needed.
**How**: Define `ShikiSyncEvent` protocol in ShikiCore. Events: `session.created`, `spec.validated`, `test.completed`, `fix.applied`, `review.posted`. Store in ShikiDB `agent_events` table (already exists). Projectors mutate local state.
**Relevance to existing backlog**: Directly enhances the existing context tracking to DB feedback and the event bus architecture spec. Upgrades from fire-and-forget events to replayable event sourcing.

### 3. [P1] Linter-Driven Agent Guardrails

**Source**: Factory's ESLint plugin philosophy
**What**: Create a SwiftLint/custom linter rule set specifically designed to steer Shikki's agent output. Rules enforce file organization conventions, naming patterns, test colocation, structured logging -- deterministic constraints that complement the probabilistic LLM.
**Why**: Factory's thesis is correct: agents make probabilistic mistakes that deterministic rules catch reliably. The linter provides instant feedback the agent can self-correct on, without consuming another LLM turn. This is cheaper and faster than multi-pass review.
**How**: Define `shikki-lint` rules: spec files must have frontmatter, test files must be colocated, imports must be sorted, no print() in tests (already a feedback item). Run linter as pre-commit hook AND as agent tool (agent can invoke linter to check its own output).
**Relevance to existing backlog**: Strengthens FixEngine hardening (P0), DRY enforcement (P1), and pre-PR quality gates. The linter becomes the "deterministic half" of quality assurance.

### 4. [P2] Model-Invoked Skill Activation

**Source**: Factory/Droid's SKILL.md model-invoked pattern
**What**: Instead of requiring `/spec`, `/quick`, `/review` commands, allow the agent to read skill descriptions and automatically activate the right skill based on the user's natural language request. Skills become suggestions, not commands.
**Why**: Reduces cognitive load -- users describe intent, agent selects workflow. Factory proves this works at scale with their skills system. Combined with Shikki's existing skill registry, this is a natural evolution.
**How**: Each skill's `description` field becomes a semantic match target. When user sends a message, agent evaluates top-3 skill matches by description similarity. If confidence > threshold, activate automatically. If ambiguous, present options. Still allow explicit `/command` as override.
**Relevance to existing backlog**: Enhances the existing skills infrastructure. Does not replace explicit commands -- adds an intelligent routing layer on top.

### 5. [P2] Dual-Mode Agent (Build/Plan)

**Source**: OpenCode's build/plan dual agents
**What**: Add a read-only `plan` mode to Shikki that denies file edits, restricts bash to read-only commands, and focuses on analysis, exploration, and planning. Toggle with a single keypress (Tab in OpenCode).
**Why**: Safe exploration of unfamiliar code or risky refactors without accidentally modifying anything. The read-only constraint forces the agent to think rather than act, producing better plans. Also useful for onboarding -- new team members explore codebase safely.
**How**: Define `AgentMode.build` and `AgentMode.plan` in ShikiCore. Plan mode: tool permissions deny Write/Edit/Bash(write), allow Read/Glob/Grep/Bash(read-only). Build mode: full access (current behavior). Mode persists per session, toggle via `/plan` and `/build` or keypress.
**Relevance to existing backlog**: Complements the existing dispatch/plan mode workflow. Plan mode becomes a first-class agent constraint rather than just a process step.

---

## Patterns NOT Adopted (and Why)

| Pattern | Source | Reason to Skip |
|---------|--------|---------------|
| Cloud thread sync | Amp | Shikki uses ShikiDB for persistence -- no cloud dependency needed |
| Agent Skills cross-tool spec | Factory | Too early for Shikki. Focus on internal quality first. Revisit post-v1.0 |
| Desktop Electron app | OpenCode | Against Shikki's native-binary-only production philosophy |
| Code search subagent | Amp | Requires Sourcegraph infra. BM25 answer engine + moto cache covers this |
| Session ID resumption | Factory | Event sourcing (item 2) provides a better foundation for this |

---

## Sources

- Amp: `sourcegraph/amp-contrib`, `sourcegraph/amp-examples-and-guides`, `sourcegraph/amp.nvim`, `sourcegraph/cra-github`, `sourcegraph/amp-sdk-demo`
- Factory: `Factory-AI/factory`, `Factory-AI/factory-plugins`, `Factory-AI/skills`, `Factory-AI/droid-action`, `Factory-AI/droid-code-review`, `Factory-AI/eslint-plugin`, `Factory-AI/SERA`, `Factory-AI/droid-sdk-typescript`, `Factory-AI/droid-sdk-python`, `Factory-AI/cursed-plugins`
- Claude Code: `anthropics/claude-code` (plugins directory, README)
- OpenCode: `anomalyco/opencode` (packages/opencode core, AGENTS.md, sync README), `opencode-ai/opencode` (archived, now Crush by Charm)
