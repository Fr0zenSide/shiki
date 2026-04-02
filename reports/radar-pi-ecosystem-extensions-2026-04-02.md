# Radar: pi Ecosystem Extensions & Skills

**Date**: 2026-04-02
**Scope**: 16 repos/packages from the pi coding agent ecosystem
**Purpose**: Competitive intelligence for Shikki plugin/extension architecture

---

## Per-Item Analysis

### 1. pi-skills (badlogic)
Skills collection (brave-search, browser-tools, Gmail/Calendar/Drive CLIs, transcribe, YouTube transcripts). Cross-agent compatible (pi, Claude Code, Codex CLI, Amp, Droid). Each skill is a `SKILL.md` file with `{baseDir}` placeholder.
**Relevance**: HIGH -- validates our skill format. Their cross-agent portability via SKILL.md is ahead of us.
**Steal**: `{baseDir}` placeholder pattern for skill-relative file resolution. Multi-agent compatibility layer (one skill runs on 5 agents).

### 2. oh-my-pi (can1357)
Major fork adding: hash-anchored edits, LSP integration (11 ops, 40+ languages, format-on-write), IPython kernel tool, TTSR (Time Traveling Streamed Rules -- regex-triggered zero-cost rules that inject only when the model writes matching output), subagent system with worktree/fuse isolation, AI-powered conventional commits with hunk-level staging, model roles (default/smol/slow/plan/commit), interactive `/review` with P0-P3 findings.
**Relevance**: HIGH -- most feature-rich competitor agent. TTSR is genuinely novel.
**Steal**: TTSR pattern (zero context-cost rules triggered by output regex). Model roles routing (smol for exploration, slow for planning). Hunk-level commit staging.

### 3. awesome-pi-agent (qualisero)
Curated list of ~60+ extensions, skills, tools, themes, and providers. Includes Discord scraper for automated resource discovery.
**Relevance**: MEDIUM -- ecosystem size indicator. Shows extension surface area we should cover.
**Steal**: Discord scraping for ecosystem discovery automation. Categorization schema (extensions, skills, tools, themes, providers).

### 4. pi-diff-review (badlogic)
Native diff review window using Glimpse + Monaco. Opens review UI with git diff/last commit/all files scopes, fuzzy file search, inline comment drafting. Self-described as "pure slop" proof-of-concept.
**Relevance**: LOW -- our `/review` is more mature. Validates that native GUI review windows are desired.
**Steal**: Nothing actionable; we already have this covered with `shikki review`.

### 5. pi-rewind-hook (badlogic/nicobailon)
Git-ref-based checkpoint system. Creates refs at session start and each turn under `refs/pi-checkpoints/`. `/branch` command lets you rewind files, conversation, or both independently. Keeps last 100 checkpoints.
**Relevance**: MEDIUM -- we lack explicit session-level file checkpointing.
**Steal**: Git refs as lightweight checkpoints (not branches, not stash -- refs under `refs/shikki-checkpoints/`). Independent file vs. conversation rewind.

### 6. agent-tools (badlogic)
Superseded by pi-skills. Was CLI wrappers (brave-search, browser-tools, vscode). Now deprecated.
**Relevance**: LOW -- historical only.
**Steal**: Nothing; confirms skills replaced standalone CLI tools.

### 7. claude-commands (badlogic)
Two-variant todo workflow: `todo-worktree.md` (git worktree isolation) and `todo-branch.md` (current branch). State machine: INIT -> SELECT -> REFINE -> IMPLEMENT -> COMMIT. Agent-guided human-in-the-loop with `task.md` files, `analysis.md` research preservation.
**Relevance**: MEDIUM -- validates our `/spec` + `/quick` pipeline patterns. Their research-preservation step is clean.
**Steal**: `analysis.md` as persistent research artifact alongside task files. Explicit state machine labels in prompt files.

### 8. claude-notify (badlogic)
System notifications when Claude Code needs input. macOS menu bar icon with session count, control center for all sessions, status tracking (working/waiting). Simple npm install + hook.
**Relevance**: HIGH -- direct competitor to our ntfy system.
**Steal**: macOS menu bar session counter with control center. Per-session status tracking (working/waiting). Ours is more powerful (ntfy push to phone + Apple Watch + approve/deny buttons) but theirs has better desktop presence.

### 9. pi-messenger-swarm (monotykamary)
Swarm fork of pi-messenger. File-based multi-agent mesh: named channels (#memory, #heartbeat), session channels with human-friendly names, durable channel posting, task lifecycle (create/claim/progress/done/block), subagent spawning with custom roles/personas. No daemon.
**Relevance**: HIGH -- most complete multi-agent coordination pattern in the ecosystem.
**Steal**: Durable named channels (#memory, #heartbeat) as coordination logs. Task lifecycle state machine. Subagent spawning with role + persona + objective. Channel-scoped archival.

### 10. pi-messenger (nicobailon)
Original multi-agent communication. File reservations, stuck detection, activity feed, themed agent names, crew orchestration (PRD -> dependency graph -> parallel waves -> review). Planner/Worker/Reviewer roles with model routing. Crew skills discovery from 3 locations.
**Relevance**: HIGH -- crew/wave execution is exactly our dispatch pattern. PRD-to-waves validates our approach.
**Steal**: Wave execution with dependency graph (our dispatch already does this). Stuck detection (idle + open task = stuck flag). File reservation enforcement via tool hooks. Three-tier skill discovery (user > extension > project).

### 11. @ifi/oh-pi-ant-colony
Bio-inspired multi-agent: Queen (orchestrator), Scout (lightweight exploration), Worker (execution), Soldier (review). Pheromone-based indirect communication with exponential decay (10min half-life). Adaptive concurrency (cold start -> exploration -> steady state -> overload protection). Worktree isolation per colony. File locking.
**Relevance**: HIGH -- most sophisticated multi-agent architecture. Pheromone/stigmergy is genuinely novel vs our NATS pub/sub.
**Steal**: Adaptive concurrency with CPU/memory pressure feedback. Pheromone decay for stale-info prevention. Scout/Worker/Soldier role separation. Colony resume capability.

### 12. pi-mesh
File-based multi-agent coordination: 5 tools (peers, reserve, release, send, manage). Overlay UI with 3 tabs. File reservations enforced by hooking edit/write tools. Stale agent cleanup via PID checking. Lifecycle hooks module.
**Relevance**: MEDIUM -- simpler than messenger-swarm but cleaner API. File reservation pattern is clean.
**Steal**: PID-based stale agent cleanup. Lifecycle hooks module pattern (`hooksModule` in config). Reservation enforcement via tool-call interception.

### 13. pi-agentic-compaction
Replaces default compaction with agentic approach: mounts conversation as `/conversation.json` in virtual filesystem, lets summarizer model explore with shell tools (jq, grep, head, tail) before producing summary. Uses cheap fast models (gpt-5.4-mini, cerebras). Steerable via `/compact focus on X`.
**Relevance**: HIGH -- our context compaction is a pain point. This approach is smarter than single-pass.
**Steal**: Virtual filesystem mount of conversation for targeted inspection. Steerable compaction via user hints. Cheap-model delegation for compaction (not using the main expensive model). Deterministic modified-files extraction from tool results.

### 14. pi-file-watcher
Aider-style watch mode: monitors source files for `#pi!` comment markers, sends them as prompts. Supports deferred execution (`#pi! @5m`, `#pi! @09:30`). Auto-removes markers on completion. Customizable marker string.
**Relevance**: MEDIUM -- novel IDE-less inline prompting pattern.
**Steal**: Deferred execution with time annotations (`@5m`, `@2h`, `@09:30`). Inline source-code prompting as alternative input channel for `shiki push`.

### 15. pi-lens
Real-time code quality extension: 31 LSP servers, tree-sitter structural analysis, AST pattern matching, auto-install for TS/Python tooling, duplicate detection, complexity metrics. Blockers (type errors, secrets) stop the agent. Warnings go to `/lens-booboo` report. Delta-mode only shows NEW issues.
**Relevance**: HIGH -- this is the pre-PR quality gate we want. Delta-mode is critical.
**Steal**: Delta-mode baseline tracking (only flag new issues, not pre-existing). Blocker vs warning severity split with different enforcement. Auto-install of analysis tooling. Tree-sitter structural patterns (empty catch, eval, deep nesting).

### 16. sitegeist (badlogic)
Chrome/Edge sidebar AI assistant for browser automation, data extraction, form filling. BYOK (Anthropic, OpenAI, GitHub Copilot, Gemini). AGPL-3.0. Built on pi-mono internals.
**Relevance**: LOW -- browser automation, tangential to Shikki's domain.
**Steal**: Nothing directly; confirms pi-mono is being used as an SDK for non-CLI products.

---

## Synthesis

### Replicate as Built-in Features

1. **Agentic compaction** (pi-agentic-compaction) -- our compaction is single-pass. The virtual-filesystem + cheap-model + steerable approach is strictly better. Build into ShikiCore's context management.
2. **Session checkpointing** (pi-rewind-hook) -- git refs under `refs/shikki-checkpoints/` with independent file/conversation rewind. Low-cost safety net for autonomous runs.
3. **Delta-mode quality gate** (pi-lens) -- our PrePRGates should only flag NEW issues introduced by the current branch, not pre-existing debt. Baseline tracking is the missing piece.
4. **TTSR-style lazy rules** (oh-my-pi) -- zero context-cost rules that inject only when the model's output matches a regex. Eliminates the "200-line CLAUDE.md bloat" problem.

### Validates Patterns We Already Have

- **Dispatch waves** -- pi-messenger crew's PRD-to-dependency-graph-to-parallel-waves is exactly our `/dispatch` pipeline. We are on the right track.
- **ntfy notifications** -- claude-notify validates the need; our ntfy + Apple Watch + approve/deny is more powerful but lacks their macOS menu bar presence.
- **Skill/plugin format** -- pi-skills' SKILL.md with frontmatter matches our PluginManifest approach. Cross-agent portability is a differentiator we should add.
- **Todo/spec workflow** -- claude-commands' state machine mirrors our `/spec` + `/quick` flows. Their `analysis.md` artifact is a nice addition.
- **Agent roles** -- pi-messenger's Planner/Worker/Reviewer maps to our @Sensei/@Kenshi/@Metsuke agent aliases.

### Gaps Revealed

1. **File reservation system** -- multiple pi extensions enforce file locks during multi-agent work. Our NATS architecture lacks this. Critical for parallel dispatch safety.
2. **Adaptive concurrency** -- ant-colony scales workers based on CPU/memory pressure. Our dispatch uses static concurrency. We need pressure-aware scaling.
3. **Pheromone/decay communication** -- the ant-colony's indirect communication with time-decay prevents stale coordination data. Our NATS is real-time but has no built-in staleness concept. Relevant for Memory Decay backlog item.
4. **Inline source prompting** -- pi-file-watcher's `#pi!` marker in source files is a novel input channel we haven't considered for `shiki push`.
5. **Desktop presence** -- claude-notify's macOS menu bar with session counter. Our ntfy is mobile-first but has no desktop widget.

### Swarm/Ant/Mesh vs Our NATS Architecture

The pi ecosystem's multi-agent patterns are **all file-based** (JSON files on disk, fs.watch, append-only JSONL feeds). This is their strength (zero dependencies, instant setup) and weakness (single-machine only, no distributed coordination, PID-based cleanup is fragile).

Our NATS architecture is fundamentally more capable:
- **Distributed** -- works across machines/containers, not limited to shared filesystem
- **Pub/sub** -- true event streaming vs file polling
- **Leader election** -- proper coordination vs PID checking
- **Persistence** -- JetStream vs append-only JSONL

However, the pi ecosystem has three patterns we should absorb into our NATS layer:
1. **Named durable channels** (#memory, #heartbeat) as persistent coordination logs -- map to NATS subjects with JetStream retention
2. **Pheromone decay** -- implement as TTL on NATS KV entries for coordination metadata
3. **File reservations** -- implement as NATS KV locks with auto-release on agent disconnect

The file-based approach works surprisingly well for single-machine development. We should consider a "NATS-lite" local mode that uses the same API surface but backs to files for zero-dependency single-dev usage.

---

## Action Items

| Priority | Item | Source | Shikki Target |
|----------|------|--------|---------------|
| P0 | Delta-mode baseline in PrePRGates | pi-lens | `PrePRGates.swift` |
| P1 | Agentic compaction with steerable hints | pi-agentic-compaction | ShikiCore context mgmt |
| P1 | File reservation locks in dispatch | pi-mesh, pi-messenger | NATS KV + dispatch |
| P1 | TTSR-style lazy rule injection | oh-my-pi | Rule engine / CLAUDE.md |
| P2 | Session checkpointing via git refs | pi-rewind-hook | ShikiCore session |
| P2 | Adaptive concurrency with pressure feedback | ant-colony | Dispatch concurrency |
| P2 | Deferred inline prompting (`#shikki!`) | pi-file-watcher | `shiki push` |
| P2 | macOS menu bar session widget | claude-notify | ntfy evolution |
| P3 | Cross-agent skill portability (SKILL.md compat) | pi-skills | Plugin format |
| P3 | Pheromone decay for coordination metadata | ant-colony | NATS KV TTL |
