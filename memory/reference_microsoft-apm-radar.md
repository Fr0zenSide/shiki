---
name: microsoft/apm Reference
type: reference
description: Microsoft's Agent Package Manager — treating AI agents as installable, versioned packages
source: https://github.com/microsoft/apm
first_seen: 2026-04-04
relevance: HIGH
---

## Overview

**microsoft/apm** — Python, 954 total stars, 59 today (2026-04-04). Microsoft's first-party Agent Package Manager. Minimal description: "Agent Package Manager."

This is a signals-over-features watch. The fact that Microsoft has shipped an official `apm` under their org — rather than a research project — suggests they believe agent packaging will become a standard distribution primitive. The name deliberately echoes `npm`/`pip`/`brew` to signal its intended role in the ecosystem.

## Why It Matters for Shikki

### The Paradigm Shift

Current state: agents are embedded in harnesses (Shikki, omo, oh-my-claudecode). They're not separately installable, versioned, or discoverable.

APM's implied future: agents are packages. You `apm install @sensei`, `apm install @hanami`. They have manifests, dependencies, version pinning, registries.

This is the npm moment for the agent layer. If APM or an APM-like standard gains traction, the entire distribution model for Shikki's agent personas changes.

### Direct Shikki Implications

1. **Agent distribution** — Shikki's @Sensei, @Hanami, @Shogun etc. could become APM-installable packages rather than harness-embedded configs. This would allow community agents and easier persona updates.

2. **Skill distribution** — Shikki's skills (md-feature, pre-pr, quick, etc.) could be packaged and installed via APM rather than living in the harness source.

3. **Interoperability** — If APM becomes a standard, Shikki agents would be portable to non-Shikki harnesses. Competitive surface expands, but so does reach.

4. **Dependency management** — APM likely handles agent-to-tool dependencies (which MCP servers an agent requires, which context it needs). This solves a real Shikki friction point: onboarding new agents requires manual setup.

## Key Questions

- [ ] What does APM's package manifest format look like?
- [ ] Does APM support a registry/discovery mechanism?
- [ ] How does APM handle agent authentication and permissions?
- [ ] What's APM's relationship to MCP (do agents declare MCP tool dependencies)?
- [ ] Is APM Python-only or polyglot?

## Action Items

- [ ] Read APM's README and package manifest spec
- [ ] Map Shikki's agent definitions (@Sensei etc.) to APM manifest format as a prototype
- [ ] Assess whether adopting APM as Shikki's distribution primitive is feasible vs. rolling a custom format
- [ ] Track APM's star velocity and community adoption (954 stars today; watch for crossover into thousands)
