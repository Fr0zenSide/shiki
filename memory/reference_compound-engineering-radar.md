---
name: EveryInc/compound-engineering-plugin — Structured Engineering Workflow Plugin
type: reference
description: 6-phase compound engineering workflow for Claude Code, Codex, and 10+ AI coding tools — with cross-tool compatibility layer
source: https://github.com/EveryInc/compound-engineering-plugin
radar_date: 2026-04-02
relevance: HIGH
---

## What It Is

The Compound Engineering Plugin is a structured workflow plugin for Claude Code (and 10+ other AI coding tools) that implements a 6-phase development cycle. The core philosophical claim: "80% of engineering value is in planning and review, 20% in execution."

## The 6-Phase Workflow

```
/ce:ideate     → Surface improvement ideas from the codebase
/ce:brainstorm → Explore requirements before formal planning
/ce:plan       → Create detailed implementation plans
/ce:work       → Execute plans with task tracking
/ce:review     → Multi-agent code review
/ce:compound   → Document learnings for future reuse
         ↑_________________________________|
         (loop — each cycle compounds knowledge)
```

## Why It Matters to Shikki

### The `/ce:compound` Gap

Shikki has `/md-feature`, `/quick`, `/pre-pr`, `/dispatch`, and `/course-correct` — but **no compound phase**. The `/ce:compound` command codifies learnings from each completed session into reusable patterns. This is the "closing the loop" step that turns one-time problem-solving into accumulated institutional knowledge.

Current Shikki behavior: session ends, learnings are lost unless manually `/ingest`ed.
Compound Engineering behavior: agent automatically extracts patterns, updates skill library.

This is a direct gap to address.

### Cross-Tool Compatibility Layer

The plugin ships a Bun/TypeScript CLI that converts its Claude Code skill format to:
- OpenCode, Codex, Droid, Pi, Gemini CLI
- GitHub Copilot, Kiro, Windsurf, OpenClaw, Qwen Code

This is the most mature cross-tool skill distribution mechanism observed in the radar so far (vs. `runkids/skillshare` from 03-28 which was one-command sync). Worth studying the conversion architecture for Shikki's own cross-tool skill portability story.

### Alignment with Shikki's Pipeline Architecture

| Compound Engineering | Shikki Equivalent | Gap |
|---------------------|-------------------|-----|
| `/ce:brainstorm` | `/quick` clarification phase | Partial overlap |
| `/ce:plan` | `/md-feature` phases 1-4 | Strong overlap |
| `/ce:work` | `/md-feature` phases 5-7 | Strong overlap |
| `/ce:review` | `/pre-pr` multi-agent review | Strong overlap |
| `/ce:compound` | **Nothing** | **GAP — add to Shikki** |
| Cross-tool export | **Nothing** | Potential future work |

## The Compound Pattern — Design Proposal for Shikki

A `/compound` skill or end-of-session hook that:
1. Reads the session's git diff and completed todos
2. Extracts non-obvious patterns, decisions, and solutions
3. Writes them to `memory/patterns/YYYY-MM-DD-<feature>.md`
4. Checks for conflicts with existing patterns (see Skill_Seekers reference)
5. Optionally promotes to a skill if the pattern is reusable

This could run automatically at the end of `/md-feature` or `/dispatch` pipelines.

## Technical Notes

- Built with TypeScript + Bun
- The cross-tool conversion CLI is the most interesting artifact for Shikki's distribution work
- The "compound" philosophy aligns with Shikki's memory system but adds the automation layer

## Action Items

- [ ] Audit `/ce:compound` implementation details — what exactly does it extract and in what format?
- [ ] Design a Shikki `/compound` skill based on this pattern — add to `/md-feature` pipeline as final phase
- [ ] Evaluate cross-tool conversion CLI for Shikki skill portability (Codex, Gemini CLI targets)
- [ ] Compare `/ce:review` multi-agent review approach to Shikki's `/pre-pr` — extract any gap patterns
