---
name: always-further/nono Reference
type: reference
description: Kernel-enforced agent sandbox with atomic rollback and cryptographic audit chain
source: https://github.com/always-further/nono
first_seen: 2026-04-04
relevance: HIGH
---

## Overview

**always-further/nono** — Rust, 1,604 total stars, 53 today (2026-04-04). Full description: "Kernel-enforced agent sandbox. Capability-based isolation with secure key management, atomic rollback, cryptographic immutable audit chain of provenance. Run your agents in a zero-trust environment."

This is the most sophisticated agent isolation primitive seen in the trending radar to date. It operates at the kernel level (not process level, not container level — kernel syscall filtering), provides cryptographic provenance for every agent action, and offers atomic rollback of agent-caused changes.

## Why It Matters for Shikki

### The Safety Gap

Shikki currently relies on:
- Git commits as rollback points
- Claude Code's built-in permission system (approve/deny tool calls)
- Human review gates (pre-pr, validate-pr)

nono addresses a different threat model: **what happens when an autonomous agent does something wrong before a human sees it?** Atomic rollback means the answer is "undo it completely, with a full audit trail."

### Key Primitives

1. **Kernel-enforced capability isolation** — The agent cannot perform operations outside its declared capability set, enforced at syscall level. No process can accidentally or maliciously escape the sandbox.

2. **Atomic rollback** — Agent actions are transactional. If a run fails, all changes (file writes, network calls, subprocess spawns) are reversed atomically. This is stronger than git rollback: it covers non-git-tracked state (temp files, environment changes, network side effects).

3. **Cryptographic audit chain** — Every agent action is hashed and chained, creating an immutable provenance log. Tamper-evident history of what the agent did, when, and in what order.

4. **Zero-trust environment** — Agents are granted the minimum capability set required; everything else is denied by default.

### Shikki Dispatch Relevance

Shikki's dispatch pipeline runs multiple Claude Code agents in parallel, potentially executing file operations, git commands, and shell scripts autonomously. The risk surface for autonomous dispatch is significant:
- Agent writes to wrong files
- Agent executes destructive shell commands
- Parallel agents create conflicting state

nono's atomic rollback + kernel isolation would let Shikki's dispatch pipeline run more autonomously with a hard safety net, reducing the need for human approval gates on every action.

## Architecture Questions

- [ ] Does nono work with Claude Code's tool execution model or does it require custom integration?
- [ ] What's the performance overhead of kernel-level syscall interception?
- [ ] How does atomic rollback handle network side effects (API calls, git push)?
- [ ] Is nono compatible with macOS (or Linux-only via eBPF/seccomp)?
- [ ] What's the capability manifest format — how are permissions declared?

## Relationship to pydantic/monty

nono = kernel-level OS isolation (syscall filtering)
pydantic/monty = language-level Python isolation (semantic sandboxing)

Together: full-stack agent execution safety — monty prevents bad Python logic, nono prevents bad syscalls. Complementary layers, not competing.

## Action Items

- [ ] Test nono with a simple Claude Code tool execution
- [ ] Evaluate macOS compatibility (Shikki is macOS-first)
- [ ] Prototype wrapping Shikki's dispatch runs in nono sandbox
- [ ] Assess atomic rollback behavior on git operations specifically
- [ ] Consider nono as a mandatory wrapper for all Shikki autonomous dispatch executions
