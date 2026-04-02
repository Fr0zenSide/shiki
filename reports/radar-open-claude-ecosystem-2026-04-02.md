# Radar: Open Claude / Claude Code Ecosystem -- Source Leak, Forks, and Open Alternatives

**Date**: 2026-04-02
**Source**: Multiple (see Sources section)
**Category**: AI Tooling / Agent Architecture / Competitive Intelligence
**Verdict**: WATCH -- rich pattern mining, but no direct dependency. Shikki should learn from the leak, not copy.

---

## 1. The Claude Code Source Leak (March 31, 2026)

### What happened
A misconfigured `.npmignore` shipped a 59.8MB JavaScript source map (`.map`) in `@anthropic-ai/claude-code` version 2.1.88 on npm. Security researcher Chaofan Shou discovered it within hours. The source map enabled full reconstruction of ~512,000 lines of unobfuscated TypeScript. Within 24 hours: 84k+ stars, 82k+ forks on GitHub mirrors.

The YouTube video at https://youtu.be/mBHRPeg8zPU is **"Tragic mistake... Anthropic leaks Claude's source code"** by **Fireship**, covering this incident.

### Key architecture revealed

#### Three-layer memory system
1. **MEMORY.md index** -- lightweight pointer file (~150 chars per entry), always in context. Stores locations, not data.
2. **Topic files** -- actual knowledge fetched on-demand, never all loaded simultaneously.
3. **Raw transcripts** -- searched via grep for specific identifiers only when needed.

Strict write discipline: memory updates only after confirmed successful file writes. Agent treats memory as hints, verifies against actual codebases.

#### KAIROS -- autonomous background daemon
Unreleased feature for persistent background operation:
- 15-second blocking budgets per check
- Append-only daily logs
- Exclusive tools: `SendUserFile`, `PushNotification`, `SubscribePR`
- `autoDream` nightly consolidation: orientation -> signal gathering -> consolidation -> pruning
- Three-gate triggers: 24h time gate, 5-session minimum, consolidation lock

#### ULTRAPLAN -- remote planning offload
- Sends complex planning to remote Cloud Container Runtime sessions (up to 30 minutes thinking time on Opus 4.6)
- Results retrieved via `__ULTRAPLAN_TELEPORT_LOCAL__` sentinel values
- Browser-based approval workflow for plan review

#### Tool system
~40 permission-gated tools spanning ~29,000 lines:
- BashTool, FileReadTool, FileWriteTool, FileEditTool
- WebFetchTool, LSPTool, GlobTool, GrepTool
- NotebookReadTool/EditTool, MultiEditTool
- TodoReadTool/WriteTool
- Permission classification: LOW/MEDIUM/HIGH risk
- ML-based "YOLO classifier" for auto-approval

#### Query engine
46,000-line core handling LLM API calls, response streaming, token caching, context management, multi-agent orchestration, and retry logic.

#### Coordinator mode (multi-agent)
One Claude instance spawns and manages parallel worker agents:
- Task distribution via XML notifications
- Shared scratchpad directories for cross-agent knowledge
- Conflict resolution between parallel workers

#### Anti-distillation measures
- Decoy tool injection into system prompts
- Server-side reasoning summarization with cryptographic signing
- "Undercover Mode" preventing internal codename mentions in AI-generated content (codenames: Capybara, Tengu)

#### BUDDY
Tamagotchi-style AI companion with 18 species variants, rarity tiers, and deterministic PRNG seeding. Pure engagement feature.

---

## 2. Claude Code Official (106k stars)

### Architecture stack
- Shell: 47.1% (installation, shell integration)
- Python: 29.2% (core agent logic)
- TypeScript: 17.7% (CLI and tooling)
- 574 commits, 51 contributors, 17k forks

### Key features
- Terminal CLI + IDE integration (VS Code) + GitHub integration (@claude mentions)
- MCP server support for external tool integration
- Plugin system via `.claude/commands` and `.claude-plugin`
- Hooks system for lifecycle events
- Custom slash commands

---

## 3. Open-Source Alternatives Landscape

### OpenCode (opencode-ai/opencode) -- 120k+ stars
- **Language**: Go (Bubble Tea TUI)
- **Storage**: SQLite for session persistence
- **Providers**: 75+ LLM providers (OpenAI, Gemini, Groq, local via Ollama/LM Studio)
- **Context recovery**: Auto-compact at 95% token usage, summarizes conversation, creates new session
- **Tool orchestration**: Shell execution, file operations, LSP integration, permission-gated
- **MCP support**: stdio-based MCP servers for extensibility
- **Agent architecture**: Separate "coder", "task", and "title" agents with distinct model assignments
- **Notable**: Anthropic blocked OpenCode from Claude models in January 2026

### Cline (cline/cline) -- 5M+ developers
- **Language**: TypeScript (VS Code extension + CLI 2.0)
- **Architecture**: Plan/Act mode separation
- **CLI 2.0** (2026): Terminal-first, parallel agents, headless CI/CD, ACP support
- **MCP integration**: Can create new tools and extend capabilities
- **Human-in-the-loop**: Every file edit and terminal command requires approval

### Claurst (Rust port)
- Clean-room Rust reimplementation based on leaked specifications
- Preserves multi-agent orchestration, autoDream memory consolidation
- Exposes tool registry architecture (40+ tools with feature gates)
- Documents permission modes: default/auto/bypass/yolo

### Openwork (different-ai/openwork)
- Open-source alternative to Claude Cowork (team collaboration)
- Built on top of OpenCode

---

## 4. Relevance to Shikki

### Patterns to steal

| Source | Pattern | Shikki application |
|---|---|---|
| Claude Code | Three-layer memory (index -> topic files -> raw search) | Shikki already does this (MEMORY.md -> topic files -> ShikiDB search). Validated. |
| Claude Code | KAIROS daemon with autoDream consolidation | Direct inspiration for shid. 4-phase consolidation (orient/gather/consolidate/prune) maps to context compaction. Three-gate trigger prevents runaway consolidation. |
| Claude Code | ULTRAPLAN remote offload | Maps to shid dispatching heavy planning to cloud Opus instances. Sentinel-based result injection is a clean pattern. |
| Claude Code | Permission risk classification (LOW/MEDIUM/HIGH) | ShikiCore's permission system should classify tool risks, not just binary allow/deny. ML-based auto-approval is the endgame for the ntfy pain point. |
| Claude Code | Coordinator mode (parallel workers + shared scratchpad) | Validates Shikki's dispatch model. Shared scratchpad directory pattern is simpler than current agent communication. |
| OpenCode | SQLite session persistence + auto-compact at 95% | Shikki already uses SQLite (test-history.sqlite). Apply same pattern to agent sessions. |
| OpenCode | Multi-agent model assignment (coder/task/title) | Maps to AgentProvider with role-specific model selection. Smaller models for titles, larger for code. |
| Cline | Plan/Act mode separation | Shikki's Plan Mode dispatch protocol is the same pattern. Validated. |
| Cline | Parallel agents in CLI 2.0 | Validates dispatch parallel execution model. |

### What Shikki already has that competitors lack
- **Event bus architecture** -- none of the competitors have an observable event stream
- **Spec-driven development** -- no competitor enforces /spec before implementation
- **ShikiDB knowledge persistence** -- Claude Code's MEMORY.md is a weaker version of what ShikiDB provides
- **Attribution tracking** -- no competitor tracks AI authorship at the commit level
- **Pre-PR quality gates** -- no competitor has structured pre-merge validation

### What Shikki is missing
1. **Background daemon (KAIROS equivalent)** -- shid exists conceptually but not as a persistent process with autoDream
2. **Risk-classified permissions** -- current permission model is binary, not tiered
3. **Remote planning offload** -- no equivalent to ULTRAPLAN for heavy planning tasks

---

## 5. Supply Chain Security Note

The Claude Code leak also exposed a supply chain attack window: between 00:21 and 03:29 UTC on March 31, a trojanized HTTP client was reportedly injected into affected npm packages. This reinforces Shikki's decision to avoid npm/Node.js dependencies and compile Swift-native binaries.

---

## 6. Action Items (max 3)

1. **[P1] Implement autoDream consolidation in shid** -- 4-phase memory consolidation (orientation, signal gathering, consolidation, pruning) with three-gate triggers (time gate, session minimum, consolidation lock). This is the missing piece between "context compaction saves to DB" and "context compaction produces higher-quality knowledge." The Claude Code leak validated this is production-worthy at Anthropic's scale.

2. **[P1] Add risk-tiered permission classification** -- classify all ShikiCore tool calls as LOW (read-only, grep, glob), MEDIUM (file edit, git commit), HIGH (bash execution, push, deploy). Auto-approve LOW, prompt for MEDIUM, always confirm HIGH. This is the evolution of the ntfy approval system and directly addresses the top user pain point (returning to terminal to approve).

3. **[P2] Evaluate ULTRAPLAN-style remote offload for heavy planning** -- when shid encounters a planning task that exceeds local context (spec generation, architecture review), dispatch to a cloud instance with extended thinking time and retrieve results via sentinel. This requires AgentProvider cloud backend support, so it's post-v1.

---

## 7. Verdict: WATCH

The Claude Code source leak is the most significant competitive intelligence event of 2026 for AI coding tools. The three-layer memory, KAIROS daemon, and ULTRAPLAN patterns validate several Shikki architectural choices and provide concrete implementation details for shid.

However, there is no code to adopt -- the leaked source is proprietary TypeScript, and Shikki is Swift-native. The value is purely in pattern mining:

- **Memory architecture**: Shikki is ahead (ShikiDB > MEMORY.md)
- **Daemon model**: Claude Code is ahead (KAIROS has concrete implementation, shid is still conceptual)
- **Permission model**: Claude Code is ahead (risk tiers + ML auto-approval vs binary allow/deny)
- **Multi-agent**: Roughly equivalent (Coordinator mode ~ dispatch)
- **Supply chain**: Shikki is ahead (Swift-native, no npm dependency chain)

OpenCode and Cline validate the market for open-source terminal AI agents but offer no architectural innovation beyond what Shikki already has or has planned.

---

**Sources**:
- [Claude Code GitHub](https://github.com/anthropics/claude-code) (106k stars)
- [OpenCode GitHub](https://github.com/opencode-ai/opencode) (120k+ stars)
- [Cline GitHub](https://github.com/cline/cline)
- [Claurst -- Rust port with architecture analysis](https://github.com/Kuberwastaken/claurst)
- [Claude Code leak -- The Hacker News](https://thehackernews.com/2026/04/claude-code-tleaked-via-npm-packaging.html)
- [Claude Code leak -- VentureBeat](https://venturebeat.com/technology/claude-codes-source-code-appears-to-have-leaked-heres-what-we-know/)
- [Claude Code leak analysis -- DEV Community](https://dev.to/varshithvhegde/the-great-claude-code-leak-of-2026-accident-incompetence-or-the-best-pr-stunt-in-ai-history-3igm)
- [Fireship video: "Tragic mistake... Anthropic leaks Claude's source code"](https://youtu.be/mBHRPeg8zPU)
- [DigitalOcean -- Claude Code alternatives 2026](https://www.digitalocean.com/resources/articles/claude-code-alternatives)
- [Cline CLI 2.0 announcement](https://x.com/cline/status/2022341254965772367)
