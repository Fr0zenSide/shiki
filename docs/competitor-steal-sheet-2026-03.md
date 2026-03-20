# Competitor Steal Sheet — March 2026

> Synthesized from deep analysis of 5 competitors. Saved to Shiki DB.
> Source session: `869faaa5`

---

## Tier 1: Steal NOW — These change the architecture

| # | What | From | Why | Effort |
|---|------|------|-----|--------|
| 1 | **Living Spec artifact** (`.shiki/specs/{task}.md`) | Augment Intent | Spec = plan + communication + review surface. Survives context resets. Verification checks against spec, not vibes. | Medium |
| 2 | **Attention-zone model** (merge > respond > review > pending > working > done) | Composio | Answers "what needs MY attention?" instead of flat session list. Drives dashboard and TUI design. | Low |
| 3 | **SQLite mail protocol** for inter-agent coordination | Overstory | Typed messages (13 types), broadcast groups, hook injection. Maps to ShikiEvent but with structured inter-agent semantics. | Medium |
| 4 | **Self-review step** before PR | Copilot | Agent reviews its own diff. One extra API call, catches obvious mistakes. Add to `/pre-pr`. | Low |
| 5 | **PostToolUse hook** for zero-latency metadata | Composio | Intercept `gh pr create` output via Claude Code hooks. No polling needed. | Low |

## Tier 2: Steal NEXT — High value, medium effort

| # | What | From | Why | Effort |
|---|------|------|-----|--------|
| 6 | **Agent Persona system** with tool constraints | Augment Intent | investigate/implement/verify/critique. Tool removal IS prompt engineering. Verify agent = read-only = structurally can't drift. | Medium |
| 7 | **Spec-driven Verification loop** | Augment Intent | Separate verify agent checks against spec. Blocks PR until pass. Independent quality gate. | Medium |
| 8 | **Autofix loop** (CI fail → auto-fix → re-run) | Devin | `shiki autofix` monitors CI via `gh run watch`, auto-spawns fix session. Closes TDD loop. | Medium |
| 9 | **Auto-wiki generation** (`shiki wiki`) | Devin | Periodic repo indexing → architecture docs in Shiki DB. Solves context-reset permanently. | Medium |
| 10 | **Recovery manager** | Composio | Scan all sessions, validate runtime alive + workspace exists, auto-recover or escalate. | Medium |
| 11 | **`shiki doctor --fix`** | Composio | Self-diagnostic: PATH, binaries, tmux, stale state, config validity. Auto-repair mode. | Low |
| 12 | **4-tier merge resolution** (clean > auto-resolve > AI-resolve > re-imagine) | Overstory | Escalation strategy for multi-agent merges. Conflict pattern learning. | Medium |

## Tier 3: Steal LATER — Strategic, builds the moat

| # | What | From | Why | Effort |
|---|------|------|-----|--------|
| 13 | **Shiki DB as MCP server** | Augment Intent | Every agent gets project memory, not just orchestrator. Context as a service. | High |
| 14 | **Local codebase embeddings** (LM Studio) | Augment Intent | Poor man's Context Engine. 80% of value at 0% of cost. | High |
| 15 | **Task decomposer with lineage** | Composio | Classify atomic/composite, recursive decompose, sibling awareness. | High |
| 16 | **Agent handoff protocol** | Copilot | Serialize context between specialists for chained workflows (code → review → test). | Medium |
| 17 | **YAML-driven reaction config** | Composio | `ci-failed: { auto: true, action: send-to-agent, retries: 2 }`. Declarative lifecycle. | Medium |
| 18 | **Interactive planning with citations** + auto-proceed timer | Devin | Plan shows exact files/lines. 30s timer defaults to autonomous. | Medium |
| 19 | **Activity classification from JSONL** | Composio | Read Claude Code session files to detect stuck/waiting/finished. | Low |
| 20 | **Progressive watchdog** (warn > nudge > AI triage > terminate) | Overstory | 4-level escalation with decision gate awareness. Better than immediate kill. | Medium |

## Do NOT Steal

| What | From | Why not |
|------|------|---------|
| Cloud-only execution (Devbox VMs) | Devin | Local-first is our advantage |
| macOS-only desktop app | Augment | CLI-first, works everywhere |
| Per-seat pricing | Copilot | Usage-based is structural advantage |
| 4-level agent hierarchy (orchestrator > coordinator > lead > worker) | Overstory | Too much overhead, their own STEELMAN.md admits it |
| Flat file metadata (no DB) | Composio | Won't scale past 100 sessions |
| Unauthenticated dashboard | Composio | Security matters |
| Cloud-hosted Context Engine | Augment | Use local LM Studio + Shiki DB instead |
| Credit metering per task | Augment | Self-hosted, no artificial caps |

## Confirmed Gaps We Own (Nobody Else Has These)

| Gap | Why it matters |
|-----|---------------|
| **Multi-project orchestration** (iOS + backend + landing pages) | Every competitor is single-repo |
| **Shiki DB persistent knowledge graph** | Composio: flat files. Overstory: ephemeral SQLite. Devin: cloud-only replay. |
| **CLI-native Swift binary** | Everyone else: TS/Python/web |
| **Per-project budget control with auto-pause** | Nobody tracks spend per agent/project |
| **Git flow branching** (develop → release → main) | Composio hardcodes `main`. Others ignore branching. |
| **Local-first + offline capable** | Devin/Augment require cloud. Copilot requires GitHub. |
| **Context tracking across compactions** | Shiki DB records session events, survives context resets |
| **Observable event stream architecture** | ShikiEvent protocol. Nobody has a reactive event bus. |

## The One Insight Across All 5

> **"The agent is NOT the product. The orchestration layer is the product."**
> — Confirmed by Augment (BYOA), Composio (4 agent plugins), Overstory (8 runtime adapters), Devin (cloud wrapper), Copilot (model picker).
>
> Every competitor learned the same lesson: the value isn't in the AI model. It's in the coordination, the oversight, the spec, the context, and the human-in-the-loop. That's Shiki.
