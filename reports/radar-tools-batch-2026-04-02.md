# Radar: Terminal, AI Coding & Dev Tools Batch
**Date**: 2026-04-02
**Scope**: 19 repos/sites across terminal, AI coding, dev utils, hardware, voice

---

## Terminal / TUI

### 1. cmux (manaflow-ai/cmux) -- 12.2k stars, Swift
Ghostty-based macOS terminal with vertical tabs, notification rings for AI agent panes, in-app browser, Claude Code Teams mode, and SSH workspaces. Native Swift/AppKit.
**Relevance**: HIGH | **Project**: shikki
**Insight**: Notification ring + sidebar metadata pattern directly validates our tmux layout vision. cmux solves the "return to terminal to approve" pain point natively -- watch as potential replacement for tmux-based agent orchestration on macOS.

### 2. ghostling (ghostty-org/ghostling) -- 893 stars, C
Minimal terminal emulator in a single C file built on libghostty-vt C API. Uses Raylib for rendering. Demonstrates embeddable terminal emulation with SIMD parsing, Unicode, mouse tracking, Kitty keyboard protocol.
**Relevance**: MEDIUM | **Project**: tegami
**Insight**: libghostty-vt is a zero-dependency embeddable VT library -- could power a terminal widget inside Tegami or any custom TUI without pulling in full Ghostty. Watch for libghostty-vt stabilization.

### 3. babbletui (badlogic/babbletui) -- 7 stars, TypeScript
Minimal TUI library for chat interfaces with two-buffer differential rendering. Components: TextComponent, MarkdownComponent, TextEditor, SingleLineInput. npm package `@mariozechner/babbletui`.
**Relevance**: LOW | **Project**: general
**Insight**: Clean differential rendering architecture. TS-only, not useful for Swift TUI but the two-buffer diff pattern is a good reference for Shikki's Augmented TUI rendering.

### 4. tui / lemmy-tui (badlogic/tui) -- 9 stars, TypeScript
Terminal UI framework with differential rendering, autocomplete, container-based component system. Superset of babbletui with file completion, slash commands, and provider interface.
**Relevance**: LOW | **Project**: general
**Insight**: Autocomplete provider interface pattern (slash commands, file completion) is a good reference for Shikki TUI command palette design.

---

## AI Coding / Agents

### 5. plannotator (backnotprop/plannotator) -- 3.8k stars, TypeScript
Visual plan annotation and code review tool for AI coding agents. Supports Claude Code, OpenCode, Pi, Codex. Features: inline annotations on plans, plan diffs, git diff review, team sharing with E2E encryption, self-hostable.
**Relevance**: HIGH | **Project**: shikki
**Insight**: Plan annotation + visual diff review directly maps to our /review and /spec workflows. The "annotate last message and send structured feedback" pattern could enhance Shikki's review pipeline. Consider as plugin or integration target.

### 6. terminusapp.ai -- commercial
AI-native engineer augmentation consultancy. Embedded AI-augmented engineering teams that ship production code. Services: Build, Automate, AI integrations.
**Relevance**: LOW | **Project**: general
**Insight**: Consulting company, not a tool. No technical takeaway.

### 7. LibreChat (danny-avila/LibreChat) -- 35.2k stars, TypeScript
Self-hosted ChatGPT clone with multi-provider support (Anthropic, OpenAI, Google, Bedrock, etc.), MCP tools, agent marketplace, code interpreter, resumable streams, multi-user auth, web search.
**Relevance**: MEDIUM | **Project**: general
**Insight**: Agent marketplace + resumable streams patterns are mature at 35k stars. Their plugin/agent sharing model (user/group scoping) is worth studying for Shikki plugin marketplace. Web search integration (provider + scraper + reranker) is a good reference for Answer Engine.

### 8. cc-wrap (badlogic/cc-wrap) -- 3 stars, TypeScript
TypeScript API wrapper for Claude Code supporting interactive and non-interactive modes. Includes alternative Claude Code TUI. Early/minimal docs.
**Relevance**: MEDIUM | **Project**: shikki
**Insight**: Programmatic Claude Code control from TS. Related to our `claude -p` dispatch pattern in ShikiAgentClient. Watch for API maturity -- could inform AgentProvider protocol.

### 9. claude-gui (badlogic/claude-gui) -- 5 stars, TypeScript
WebSocket wrapper for Claude Code enabling non-TUI interfaces. Bi-directional WebSocket API with vitest tests.
**Relevance**: MEDIUM | **Project**: shikki
**Insight**: WebSocket bridge for Claude Code is exactly the pattern we need for remote/web-based agent control. Validates our NetKit WebSocket migration path. Could complement ntfy-based approval system.

### 10. claude-bridge (badlogic/claude-bridge) -- 5 stars, empty repo
"Use any model provider with Claude Code." Repository is empty -- placeholder or WIP.
**Relevance**: WATCH | **Project**: shikki
**Insight**: If implemented, this would be an AgentProvider-style model-agnostic bridge. Watch for actual code. Aligns with our AI-provider-agnostic philosophy.

---

## Developer Utils

### 11. jot (badlogic/jot) -- 137 stars, JavaScript
Minimal self-hosted collaborative markdown editor with inline comment threads. Real-time collab, CLI for humans and agents, .md files on disk, API keys + share links. Agent setup modal with copy-paste instructions.
**Relevance**: MEDIUM | **Project**: shikki
**Insight**: "Built for humans and agents" with CLI + HTTP API is the exact dual-interface pattern. Comment thread anchoring to text selections is a good UX pattern for spec review. Could serve as lightweight spec collaboration tool.

### 12. create-app (badlogic/create-app) -- 24 stars, TypeScript
CLI scaffolder for deployable web apps with Caddy + Docker. Templates: static, SPA+API, web lib, node lib. Single-server deploy with auto-SSL.
**Relevance**: LOW | **Project**: general
**Insight**: Caddy + Docker deploy pattern matches our production stack. The `run.sh dev/deploy` convention is clean. Not directly useful since we deploy native binaries, but the template system is a reference for `shikki init`.

### 13. lsp-cli (badlogic/lsp-cli) -- 22 stars, TypeScript
Extract symbol information from codebases using LSP servers. Outputs JSON with types, methods, fields, docs, supertypes. Supports Java, C++, C, C#, Haxe, TypeScript, Dart.
**Relevance**: HIGH | **Project**: shikki
**Insight**: Method-level symbol extraction via LSP is exactly what Moto Cache System needs for method-level indexing (P0 backlog). `--llm` flag for LLM-consumable output. No Swift support yet but the pattern is right -- could feed `shikki doctor --duplicates` and DRY enforcement.

### 14. clipboard (badlogic/clipboard) -- 6 stars, JavaScript
Cross-platform clipboard API (text, image, RTF, files, HTML) via Rust native addon (clipboard-rs + napi-rs). Fork with musl/Alpine support.
**Relevance**: LOW | **Project**: general
**Insight**: Rust-backed Node clipboard. Not relevant to Swift stack.

### 15. hotserve (badlogic/hotserve) -- 3 stars, TypeScript
Minimal hot-reload dev server. Zero config, auto-injects reload script into HTML, multiple path mappings.
**Relevance**: LOW | **Project**: general
**Insight**: Clean minimal tool. No direct relevance.

### 16. husky (typicode/husky) -- 34.9k stars, JavaScript
Git hooks made easy. 2kB, no dependencies, uses `core.hooksPath`. Supports all 13 client-side Git hooks, branch-specific hooks, monorepos.
**Relevance**: MEDIUM | **Project**: shikki
**Insight**: Industry standard for Git hooks (35k stars). Our pre-PR gates and attribution validation currently use custom hooks -- husky's `core.hooksPath` approach is cleaner than `.git/hooks` symlinks. Consider for Node-based projects or as reference for Swift hook runner.

### 17. vouch (mitchellh/vouch) -- 4.1k stars, Nushell
Community trust management system by Mitchell Hashimoto. Explicit vouch/denounce model for open-source contribution gating. GitHub Actions integration, web-of-trust across projects. Used by Ghostty.
**Relevance**: MEDIUM | **Project**: shikki
**Insight**: Trust model for plugin marketplace contributions. When we open Shikki plugins to community, vouch-based contributor gating could prevent AI-slop PRs. The web-of-trust pattern (projects sharing trust lists) is elegant for ecosystem trust.

---

## Hardware / Embedded

### 18. mcugdx (badlogic/mcugdx) -- 18 stars, C
ESP32-S3 game framework with ST7789 display, I2S audio, custom read-only filesystem in flash partition, and desktop emulation for fast iteration. Examples include Doom port, dinosaur game, audio, neopixels, ultrasonic, GPIO, window-opener.
**Relevance**: HIGH | **Project**: tegami
**Insight**: DIRECTLY relevant to Tegami. ESP32-S3 + display + audio + custom FS is exactly the hardware target. Desktop emulation pattern (compile same code for desktop) is critical for dev velocity. Study the display.h / audio.h abstraction layer and the CMake/ESP-IDF integration.

---

## Voice

### 19. yakety (badlogic/yakety) -- 96 stars, C
Cross-platform speech-to-text app using local Whisper models. Global hotkey (FN/Right Ctrl) to record, transcribes locally, auto-pastes into focused app. C + whisper.cpp, macOS 14+ / Windows.
**Relevance**: HIGH | **Project**: flsh
**Insight**: Local Whisper integration in C with hotkey activation is exactly the Flsh voice input pattern. The permission inheritance model (parent process inherits macOS accessibility perms) is a real gotcha we need to handle. Desktop companion for Flsh voice-first architecture.

---

## Priority Summary

| Rating | Count | Items |
|--------|-------|-------|
| HIGH   | 5     | cmux, plannotator, lsp-cli, mcugdx, yakety |
| MEDIUM | 6     | ghostling, LibreChat, cc-wrap, claude-gui, jot, husky, vouch |
| LOW    | 5     | babbletui, tui, terminusapp, create-app, clipboard, hotserve |
| WATCH  | 1     | claude-bridge (empty repo) |
