# Radar: pi-mono Deep Analysis

**Date:** 2026-04-02
**Target:** [badlogic/pi-mono](https://github.com/badlogic/pi-mono) by Mario Zechner
**Stars:** 30,492 | **Forks:** 3,293 | **License:** MIT | **Version:** 0.64.0
**Language:** TypeScript | **~120k LOC** across 7 packages, 156 test files, 88 in coding-agent alone
**Created:** 2025-08-09 | **Last push:** 2026-04-02 (active today)

---

## 1. Architecture Deep-Dive

### 1.1 Monorepo Structure

```
pi-mono/
  packages/
    ai/              -- Unified multi-provider LLM API (OpenAI, Anthropic, Google, Bedrock, 20+ providers)
    agent/           -- Agent runtime: tool calling, state machine, event streaming
    coding-agent/    -- The CLI product: TUI, extensions, sessions, packages
    tui/             -- Terminal UI library with differential rendering
    web-ui/          -- Web components for AI chat interfaces
    mom/             -- Slack bot delegating to pi
    pods/            -- vLLM deployment manager for GPU pods
  scripts/           -- Release, profiling, cost tracking, OSS management
  .pi/               -- Dog-food: pi's own extensions + prompts for developing pi
```

**Key insight:** pi is NOT just a CLI. It is a **4-layer SDK**:
1. `pi-ai` -- provider-agnostic LLM streaming (no agent logic)
2. `pi-agent-core` -- stateful agent loop with tool execution
3. `pi-coding-agent` -- the full product (TUI, extensions, sessions, packages, CLI)
4. `pi-tui` -- standalone terminal UI component library

Each layer is independently usable. You can build a custom agent with `pi-agent-core` without using the coding agent at all. Or embed `pi-ai` in a web app for streaming.

### 1.2 The Core Philosophy

Quoted directly from README:

> "Pi is aggressively extensible so it doesn't have to dictate your workflow."

**What the core ships with:**
- 4 tools: `read`, `write`, `edit`, `bash` (optionally: `grep`, `find`, `ls`)
- Session management (JSONL tree with branching)
- Context compaction
- Multi-provider auth (20+ providers, OAuth + API keys)
- Extension loader

**What the core does NOT ship with:**
- No sub-agents (extension: `subagent/`)
- No plan mode (extension: `plan-mode/`)
- No permission popups (extension: `permission-gate.ts`)
- No MCP (philosophical rejection -- "skills + CLI tools are enough")
- No background bash (use tmux)
- No built-in to-dos (extension: `todo.ts`)

This is radically minimal. Features that Claude Code and Cursor bake in are literally extension examples.

### 1.3 Four Operating Modes

| Mode | Use Case |
|------|----------|
| Interactive (default) | Full TUI with editor, message stream, session tree |
| Print (`-p`) | One-shot: pipe stdin, get answer, exit |
| JSON (`--mode json`) | All events as JSONL for programmatic consumption |
| RPC (`--mode rpc`) | Stdin/stdout JSONL framing for embedding in other processes |

Plus the **SDK mode** for embedding in other TypeScript applications. See [openclaw/openclaw](https://github.com/openclaw/openclaw) for a real-world integration.

---

## 2. Extension System Architecture

### 2.1 Extension = TypeScript Module with Default Export

```typescript
// The simplest possible extension
export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.notify("Hello from extension!", "info");
  });
}
```

The `ExtensionAPI` surface is enormous (1,468 lines in `types.ts`):

**Registration methods (called during load):**
- `pi.on(event, handler)` -- subscribe to 30+ lifecycle events
- `pi.registerTool(def)` -- add LLM-callable tools
- `pi.registerCommand(name, opts)` -- add `/command` slash commands
- `pi.registerShortcut(key, opts)` -- add keyboard shortcuts
- `pi.registerFlag(name, opts)` -- add CLI flags
- `pi.registerMessageRenderer(type, renderer)` -- custom message rendering
- `pi.registerProvider(name, config)` -- add custom LLM providers

**Action methods (called at runtime):**
- `pi.sendMessage()`, `pi.sendUserMessage()` -- inject messages
- `pi.appendEntry()` -- persist custom data in session
- `pi.setSessionName()`, `pi.setLabel()` -- session metadata
- `pi.getActiveTools()`, `pi.setActiveTools()` -- tool management
- `pi.setModel()`, `pi.getThinkingLevel()`, `pi.setThinkingLevel()`
- `pi.exec(command, args)` -- run shell commands
- `pi.events` -- inter-extension event bus

**UI Context (available to event handlers and tools):**
- `ctx.ui.select()`, `ctx.ui.confirm()`, `ctx.ui.input()` -- modal dialogs
- `ctx.ui.notify()` -- notifications
- `ctx.ui.setWidget()` -- above/below editor widgets
- `ctx.ui.setFooter()`, `ctx.ui.setHeader()` -- custom chrome
- `ctx.ui.setEditorComponent()` -- REPLACE the entire editor (see vim example)
- `ctx.ui.custom()` -- full TUI component with keyboard focus
- `ctx.ui.theme` -- theme access for styling

### 2.2 Event System (30+ Events)

**Resource events:** `resources_discover`
**Session events:** `session_start`, `session_directory`, `session_before_switch`, `session_before_fork`, `session_before_compact`, `session_compact`, `session_before_tree`, `session_tree`, `session_shutdown`
**Agent events:** `context`, `before_provider_request`, `before_agent_start`, `agent_start`, `agent_end`
**Turn events:** `turn_start`, `turn_end`
**Message events:** `message_start`, `message_update`, `message_end`
**Tool events:** `tool_call` (can block/modify), `tool_result` (can modify), `tool_execution_start`, `tool_execution_update`, `tool_execution_end`
**Model events:** `model_select`
**User events:** `user_bash` (can intercept shell commands), `input` (can transform user input)

Extensions can **block tool calls** (return `{ block: true, reason }`) or **modify tool results** (return `{ content, details }`). This is the permission gate mechanism -- no built-in popups needed.

### 2.3 Extension Loading (jiti)

Extensions are loaded via [jiti](https://github.com/unjs/jiti), a JIT TypeScript importer:
- TypeScript files are compiled on-the-fly (no build step needed)
- Virtual modules map `@mariozechner/pi-*` imports to bundled packages
- Works in both Node.js and compiled Bun binary
- Extensions can import npm dependencies if they have a `package.json`

**Extension discovery order:**
1. `.pi/extensions/` (project-local)
2. `~/.pi/agent/extensions/` (global)
3. Configured paths from `settings.json`
4. CLI flags: `pi -e ./path.ts`

### 2.4 Inter-Extension Event Bus

Simple Node.js EventEmitter wrapper:

```typescript
// Extension A
pi.events.emit("my:event", { data: "hello" });

// Extension B
pi.events.on("my:event", (data) => { ... });
```

34 lines total. No types, no namespacing enforcement, no persistence.

---

## 3. Pi Packages (Distribution System)

### 3.1 Install Sources

```bash
pi install npm:@foo/bar           # npm (globally)
pi install npm:@foo/bar@1.2.3     # pinned version
pi install git:github.com/u/repo  # git clone
pi install git:...@v1             # pinned tag
pi install https://github.com/... # raw URL
pi install /local/path            # local directory
pi install -l npm:@foo/bar        # project-local install
```

### 3.2 Package Manifest

```json
{
  "name": "my-pi-package",
  "keywords": ["pi-package"],
  "pi": {
    "extensions": ["./extensions"],
    "skills": ["./skills"],
    "prompts": ["./prompts"],
    "themes": ["./themes"]
  }
}
```

Without a manifest, pi auto-discovers from conventional directories.

### 3.3 Package Gallery

Packages tagged with `pi-package` on npm appear on [shittycodingagent.ai/packages](https://shittycodingagent.ai/packages). Supports `video` and `image` fields for previews. This is NOT a curated registry -- it is npm search filtered by keyword.

### 3.4 Package Filtering

Users can selectively enable/disable resources from packages:

```json
{
  "packages": [{
    "source": "npm:my-package",
    "extensions": ["extensions/*.ts", "!extensions/legacy.ts"],
    "skills": [],
    "themes": ["+themes/legacy.json"]
  }]
}
```

---

## 4. Skills System

Skills follow the [Agent Skills standard](https://agentskills.io):
- SKILL.md with frontmatter (`name`, `description`, `license`, etc.)
- Progressive disclosure: only descriptions in system prompt, full content loaded on-demand
- Registered as `/skill:name` commands
- Compatible with Claude Code skills (`~/.claude/skills/`) and OpenAI Codex skills

**Key difference from Shikki commands-as-markdown:** pi skills are an open standard, not a proprietary format. They are discoverable by any agent that implements the Agent Skills spec.

---

## 5. Agent Perspectives

### @Sensei (CTO) -- Architecture Comparison

**1. Extension loading is superior to our plugin subprocess model.**
pi extensions run in-process via jiti. They share the same event loop, can access the TUI directly, modify tool calls in flight, replace the editor, inject context. Our PluginRunner executes plugins as subprocesses -- isolated but fundamentally limited in what they can do. An extension that replaces the editor or injects a widget above it is impossible in our architecture.

**2. The layered SDK is a masterclass in separation of concerns.**
`pi-ai` -> `pi-agent-core` -> `pi-coding-agent` -> extensions. Each layer has a clear boundary. Our ShikkiKit mixes orchestration, persistence, CLI commands, and plugin management in one SPM module. We lack the equivalent of `pi-ai` (we shell out to `claude -p`) and `pi-agent-core` (we have AgentProvider but it is not a standalone runtime).

**3. Their extension dependency resolution is elegant.**
Extensions declare peer dependencies on `@mariozechner/pi-*` with `"*"` range. pi bundles core packages and makes them available via virtual modules. Our plugins need to bundle everything or rely on system-installed tools.

**Challenge:** Their in-process model means a misbehaving extension can crash the entire agent. Our subprocess isolation is safer for enterprise deployments. The question is: does that safety justify the capability gap? For a CLI tool where you trust your extensions, in-process wins. For an enterprise orchestrator managing 50 plugins from unknown authors, subprocesses win.

### @Ronin (Adversarial) -- Security Comparison

**1. pi has NO sandbox by default.**
The README explicitly says: "Pi packages run with full system access. Extensions execute arbitrary code." The sandbox extension (`sandbox/`) is an opt-in example using `@anthropic-ai/sandbox-runtime`, not a built-in. Our PluginSandbox with declaredPaths, certification levels, and scoped directories is more secure by design.

**2. npm distribution is a supply chain attack surface.**
Any npm package with `pi-package` keyword shows up in the gallery. No code review, no signing, no certification tiers. Our planned SHA-256 + GPG + `CertificationLevel` (uncertified/communityReviewed/shikkiCertified/enterpriseSafe) is orders of magnitude more secure.

**3. The event interception model creates privilege escalation risk.**
Any extension can block tool calls, modify tool results, intercept user input, replace the system prompt, or inject messages. There is no capability-based permission system. Extension A cannot restrict what Extension B does. Our plugin manifest with declared capabilities is more defensible.

**Challenge:** Is "light core + extensions" actually better, or does it create **fragmentation**? Today, pi has no plan mode, no sub-agents, no permissions -- those are all community extensions with varying quality. When 5 different plan-mode extensions exist with different APIs, which one becomes the de facto standard? Claude Code's approach of shipping opinionated defaults with no extension system at all avoids this entirely. Shikki's middle ground -- compiled core features with plugin extensions for optional capabilities -- may be the sweet spot.

### @Metsuke (Quality) -- Code Quality Comparison

**1. pi-mono is well-tested but test infrastructure is opaque.**
88 test files in coding-agent alone, using vitest with a faux provider (no real API calls). However, the tests are primarily integration tests via a test harness -- there are no obvious unit test patterns for individual functions. Our 177 ShikkiTestRunner tests + per-service unit tests are more granular.

**2. Extension quality control is nonexistent.**
The 70+ example extensions are well-written because Mario wrote them. But the gallery has no quality gate. Any npm package shows up. No test requirements, no linting standards, no review process. Our planned `communityReviewed` -> `shikkiCertified` pipeline with automated checks is superior.

**3. Code quality standards are strict for the core.**
`AGENTS.md` enforces: no `any` types, no inline imports, no hardcoded keybindings, `npm run check` must pass (biome + tsgo). The `CONTRIBUTING.md` is brutally honest: "You must understand your code. Using AI to write code is fine... What's not fine is submitting agent-generated slop."

**Challenge:** 70+ example extensions is a documentation triumph. Each one is a working, tested example of a specific capability. We have zero extension/plugin examples. When we ship our marketplace, the first 20 plugins need to be as high-quality as pi's examples.

### @Kenshi (Release) -- Distribution Model

**1. npm + git is the right distribution answer.**
`pi install npm:@foo/bar` or `pi install git:github.com/user/repo` covers 99% of use cases. No custom registry infrastructure needed. Our planned GitHub registry + Astro marketplace site is more work for the same result.

**2. Lockstep versioning is bold but practical.**
All 7 packages share the same version number (currently 0.64.0). Every release updates everything. No dependency matrix hell. Our per-package versioning (ShikkiKit 0.3.0, ShikiCore 0.1.0, etc.) will create version compatibility issues.

**3. The oh-my-zsh parallel is real.**
`pi install npm:@foo/pi-tools` is functionally identical to `omz plugin enable foo`. The `pi config` command lets you enable/disable individual resources from packages. This is exactly the oh-my-zsh model with better tooling.

**Challenge:** npm global installs are fragile. Node version managers (nvm, mise, asdf) create isolated npm environments. pi addresses this with `npmCommand` config but it is a footgun for new users. Our compiled Swift binary + `shikki plugins install github:org/repo` avoids this entirely.

### @Kintsugi (Philosophy) -- Everything is an Extension?

**1. pi proves that "light core + extensions" works at scale.**
30k stars, 70+ example extensions, an active community building packages. The philosophy is validated by traction. People WANT to customize their agent.

**2. But the philosophy has a cost: fragmentation.**
No canonical plan mode. No canonical permission system. No canonical sub-agent model. Each user assembles their own Frankenstein from extensions. This is fine for power users who WANT control. It is terrible for teams who need consistency.

**3. Compiled core features provide reliability guarantees.**
When `shikki spec` runs, it always works the same way. There is no "which spec extension did you install?" question. For an orchestrator that manages production workflows, this determinism matters.

**Challenge for @Daimyo:** The user wants light + full versions for ARM boards. This is valid -- but the split should NOT be "core commands vs extension commands." It should be:
- `shi` (compiled binary, ALL commands, minimal memory footprint)
- `shi --headless` (no TUI, no interactive features, pure CLI mode for ARM/CI)
- Extensions as ADDITIVE capabilities (new tools, new integrations, new UI), not REPLACEMENT of core features

The trap is making core features optional. When `shikki review` is an extension, someone WILL ship a broken version and users will blame Shikki.

---

## 6. Head-to-Head Comparison

| Dimension | pi-mono | Shikki |
|-----------|---------|--------|
| **Language** | TypeScript (Node.js / Bun) | Swift (compiled binary) |
| **Stars** | 30,492 | Private |
| **Core philosophy** | Minimal core, everything extensible | Opinionated core, plugins for additions |
| **Extension model** | In-process TypeScript modules (jiti) | Subprocess isolation (PluginRunner) |
| **Extension count** | 70+ examples, npm gallery | 0 shipped, manifest designed |
| **Extension API surface** | ~100 methods, 30+ events, UI control | PluginManifest + execute(args) |
| **Tool registration** | Extensions register tools at load | Compiled tools in ShikkiKit |
| **Distribution** | npm + git + local paths | Planned: GitHub registry |
| **Security** | None by default (opt-in sandbox) | Checksum + certification + subprocess |
| **Provider support** | 20+ built-in | AgentProvider protocol (1 impl) |
| **Session management** | JSONL tree with branching | ShikiDB (PostgreSQL) |
| **Multi-agent** | Extension example (spawns pi instances) | NATS event bus (compiled) |
| **TUI** | Custom pi-tui library | tmux-based workspace |
| **SDK/embedding** | Full SDK + RPC mode | Not available |
| **MCP** | Rejected (skills instead) | ShikiMCP (15 tools) |
| **Skills** | Agent Skills standard (agentskills.io) | Claude Code commands in ~/.claude/ |
| **Themes** | JSON theme files, hot-reload | Not available |
| **Plan mode** | Extension | Not implemented |
| **Permission system** | Extension | settings.json allow/deny |
| **Context compaction** | Built-in + extension override | Built-in |
| **Test count** | 156 test files | 1,500+ tests across packages |
| **License** | MIT | AGPL-3.0 |

---

## 7. What They Have That We Don't (Honest Gaps)

1. **A working extension API.** Our PluginManifest defines what a plugin IS, but not what it can DO at runtime. Pi's ExtensionAPI lets extensions intercept tool calls, modify context, replace UI components, register tools, add commands. Ours can execute a subprocess and return stdout.

2. **An SDK for embedding.** `createAgentSession()` lets any TypeScript app embed a pi agent. We have no equivalent. ShikiCore is an orchestrator, not an embeddable runtime.

3. **20+ LLM provider integrations.** We shell out to `claude -p`. Pi speaks natively to Anthropic, OpenAI, Google, Bedrock, Mistral, Groq, Cerebras, xAI, and 12 more.

4. **A custom TUI library.** `pi-tui` is a standalone terminal UI framework with differential rendering. We delegate UI to tmux and bat.

5. **Session branching.** Pi's session tree lets you navigate to any point and branch. Our sessions are linear.

6. **Real-time extension hot-reload.** `/reload` reloads extensions, skills, prompts, themes without restarting. We require a full restart.

7. **A package gallery.** [shittycodingagent.ai/packages](https://shittycodingagent.ai/packages) exists today. Our marketplace is a spec.

---

## 8. What We Have That They Don't

1. **Compiled binary.** `shikki` is a native Swift binary. pi requires Node.js 20+ (or a Bun binary with limitations). On ARM boards, embedded systems, or CI without Node.js, we win.

2. **NATS event bus for multi-agent coordination.** Pi spawns separate pi instances via tmux or the subagent extension. We have a compiled NATS client with typed events, leader election, and heartbeat verification.

3. **Multi-project orchestration.** CompanyManager, FeatureLifecycle, orchestrator loop. Pi manages one session at a time.

4. **Enterprise security model.** CertificationLevel (uncertified -> enterpriseSafe), checksum verification, subprocess isolation, declaredPaths, PluginSandbox. Pi has none of this.

5. **TDD enforcement.** ShikkiTestRunner, pre-PR quality gates, spec validation, test-run-id tracking. Pi's AGENTS.md says "run tests" but has no automated enforcement.

6. **ShikiDB persistent knowledge.** PostgreSQL-backed memory with search, decisions, plans, events. Pi sessions are local JSONL files with no server-side persistence.

7. **MCP integration.** ShikiMCP with 15 tools for knowledge layer access. Pi explicitly rejects MCP.

8. **Spec-driven development.** Our /spec -> /quick -> /review -> /ship pipeline is a structured methodology. Pi is a general-purpose coding agent with no opinionated workflow.

---

## 9. What To Pick Up (7 Actionable Items)

### AP-1: Rich Plugin API (P0, before release)
**What:** Replace subprocess-only PluginRunner with a protocol-based extension API. Plugins should be able to:
- Register additional CLI commands
- Subscribe to lifecycle events (session_start, before_tool_call, etc.)
- Register custom tools for the agent
- Provide UI widgets (status line, footer info)

**How:** Define a `ShikkiExtension` protocol in ShikkiKit. Load Swift plugins as dynamic libraries (.dylib) or as separate executables communicating via stdin/stdout JSON protocol (preserving subprocess isolation while gaining API richness).

**Why:** Our current PluginManifest + execute(args) is a toy compared to pi's 100-method ExtensionAPI. We cannot compete on extensibility with subprocess-only plugins.

### AP-2: Agent Skills Standard Adoption (P1)
**What:** Adopt the [Agent Skills standard](https://agentskills.io) for our commands/skills format instead of Claude Code's proprietary `~/.claude/commands/` format.

**How:** Support `SKILL.md` with frontmatter discovery alongside our existing commands. Add `--skill` flag to shikki CLI. Implement progressive disclosure (description in system prompt, full content loaded on-demand).

**Why:** Interoperability. Pi, Claude Code, and others are converging on this standard. Our skills should be usable by any compliant agent.

### AP-3: npm + git Package Install (P1)
**What:** Support `shikki install npm:@scope/pkg` and `shikki install git:github.com/user/repo` for plugin distribution.

**How:** Shell out to npm for npm packages, git clone for git packages. Store in `~/.shikki/packages/`. Read `shikki` manifest from package.json (similar to pi's `pi` key).

**Why:** Building a custom GitHub registry is unnecessary work when npm + git covers all distribution needs. The gallery/marketplace can be a static site that indexes npm packages tagged `shikki-plugin`.

### AP-4: Extension Event Bus with Typed Events (P1)
**What:** Expose a typed event bus to plugins, similar to pi's but with Swift type safety.

**How:** Extend our existing ShikiEvent protocol to include plugin-subscribable events. Add `onEvent(_ type: ShikiEventType, handler: @Sendable (ShikiEvent) -> Void)` to the plugin API.

**Why:** Plugins need to react to orchestrator events (spec started, review completed, build failed) to provide value. Our NATS bus already carries these events -- we just need to expose them to plugins.

### AP-5: Session Branching (P2)
**What:** Add session tree branching to ShikiDB sessions. Allow users to navigate to any point and branch.

**How:** Add `parentId` field to session entries in ShikiDB. Implement `/tree` command for navigation. Store branches as linked entries rather than separate sessions.

**Why:** Session branching is a killer feature for iterative development. "Try approach A, if it fails, go back and try approach B" without losing either history.

### AP-6: light + headless Mode (P2)
**What:** Add `shikki --headless` flag for minimal resource usage on ARM/CI.

**How:** Disable TUI components, tmux workspace management, interactive prompts. Pure stdin/stdout CLI mode. Same binary, different runtime behavior.

**Why:** The user wants to run shikki on ARM boards. Rather than a separate binary (`shi-light`), a flag on the same binary avoids distribution complexity.

### AP-7: Extension Examples Gallery (P1)
**What:** Ship 10-15 example extensions/plugins with the first release.

**How:** Create `examples/plugins/` directory with working examples: permission-gate, git-checkpoint, custom-tool, status-widget, notification-hook, custom-provider, plan-mode, session-namer, context-injector, auto-commit.

**Why:** Pi's 70+ examples are its best documentation. Our plugin system will be judged by what people can build with it, and examples are the fastest way to demonstrate capability.

---

## 10. Light vs Full Version Proposal

### Recommendation: Single Binary, Multiple Modes

Do NOT split into `shi` and `shi-full`. Instead:

```
shikki                    -- full interactive mode (default)
shikki --headless         -- no TUI, no tmux, pure CLI (for ARM/CI)
shikki --minimal          -- load only core commands, skip plugin discovery
shikki --no-plugins       -- disable all plugins
shikki -e ./my-plugin.ts  -- load specific extension only
```

**Rationale:**
1. Two binaries = two build pipelines, two update mechanisms, two support surfaces
2. Swift compiles to a single binary that is already small (~15MB)
3. Feature flags at runtime are simpler than compile-time splits
4. oh-my-zsh's model works because zsh is always present -- they add ON TOP. We should do the same.

**If the ARM constraint is truly about binary size:**
- Strip debug symbols (`-s` flag): ~40% size reduction
- Use Swift's upcoming static linking improvements
- Consider: is 15MB actually too large for the target ARM boards?

---

## 11. Challenge to @Daimyo

Pi-mono exposes a fundamental tension in Shikki's architecture: **we designed plugins for enterprise safety but have zero plugin ecosystem to show for it.**

Pi shipped 70+ working extensions, a package gallery, and npm/git distribution -- all with ZERO security. And it has 30k stars. Our CertificationLevel, checksum verification, subprocess isolation, and declaredPaths are theoretically superior but practically irrelevant until we have plugins worth installing.

**The challenge:** Before v1.0, we need to answer this question honestly:

> Is Shikki a **platform** (where third-party extensions are the product) or a **product** (where compiled features are the product and plugins are optional)?

If platform: we need AP-1 (rich plugin API) immediately and should treat our core commands as "official extensions" that happen to be compiled in.

If product: our current architecture is correct -- compiled core, plugins for integrations only. But then stop investing in marketplace infrastructure and invest in making the core features best-in-class.

Pi chose platform. Claude Code chose product. Both work. Trying to be both without committing will leave us with a half-built marketplace AND half-built core features.

My read: Shikki is a **product with platform aspirations**. Ship the product first (compiled, opinionated, reliable), then open the platform (rich API, examples, gallery) once the product has traction. Do not sacrifice core feature reliability for extensibility we do not yet need.

The 7 action items above are ordered accordingly: AP-1 enriches the plugin API (needed for product), AP-7 creates examples (needed for credibility). The marketplace (AP-3) can wait until we have plugins worth distributing.

---

*Radar completed. Full codebase analyzed: 7 packages, ~120k LOC, 156 test files, 70+ extension examples, package manager, gallery, 4 operating modes, SDK embedding.*

*This is the most architecturally mature open-source coding agent. Study it.*
