# Feature: Project Distribution Plan — Radar → Action
> Created: 2026-03-26 | Status: Spec Draft | Owner: @Daimyo

## Context
Mega radar session: 100+ repos analyzed, 52 starred, patterns extracted. This spec distributes discoveries across ALL current and future projects with concrete action items.

## Project Map

### Active Projects (revenue-first)
1. **Shikki** — AI code production engine (Swift CLI)
2. **WabiSabi** — iOS habit app (Swift/SwiftUI)
3. **Maya** — Fitness iOS app (Swift, with Faustin)
4. **Brainy** — RSS AI reader + BrainyTube video player

### Future Projects (post-revenue)
5. **Flsh** — Local voice AI (Superwhisper replacement)
6. **Video Games** — With brother
7. **Private Cloud / Photo Manager** — Self-hosted photos
8. **Trip Planner** — Holiday planning with friends/wife/family
9. **URL Shortener** — Link tracking integrated with Umami analytics
10. **DSKintsugi** — Cross-platform design system

### Infrastructure
11. **ShikiDB** — Knowledge persistence layer
12. **ShikiMCP** — MCP server for knowledge
13. **skills.sh** — Skill marketplace distribution

---

## Distribution by Project

### 1. SHIKKI — Core Engine

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P0** | ShikkiKernel — timer coalescing, speculative execution | @Daimyo + @t brainstorm | Waves 1-4 spec ready, Wave 1+2 in worktree branches |
| **P0** | Native Scheduler — cron in heartbeat | @Sensei | Part of ShikkiKernel |
| **P1** | Study crush (22k) — direct competitor | charmbracelet/crush | MCP integration, session management, multi-model patterns |
| **P1** | Study opencode (130k) — market validation | anomalyco/opencode | Plugin architecture, desktop app, 130k stars = market exists |
| **P1** | OpenAgentsControl — approval gates + pattern control | darrenhinde | MVI (Minimal Viable Info) context loading for agents |
| **P1** | Context7 (50k) — docs as context for LLMs | upstash/context7 | Feed into ShikiMCP as documentation source |
| **P1** | gh-dash — PR TUI reference | dlvhdr/gh-dash | Study for `shikki review` rework TUI |
| **P1** | delta — diff rendering | dandavison/delta | Already in pipeline, multi-env testing backlog |
| **P1** | vhs — terminal recording | charmbracelet/vhs | Adopt for multi-env testing + demos + README |
| **P1** | Nomad — job scheduler patterns | hashicorp/nomad | Allocation model for CompanyManager |
| **P1** | Rudel — session analytics via hooks | obsessiondb/rudel | Reference for ShikiDB event ingestion + Observatory |
| **P1** | PM Skills (8.2k) — marketplace blueprint | phuryn/pm-skills | 65 skills, 8 plugins, chained workflows → skills.sh |
| **P2** | Excalidraw MCP + diagram skill | excalidraw + coleam00 | Agent-generated architecture diagrams in `/spec` |
| **P2** | Penpot MCP — design ops via agents | montevive/penpot-mcp | Agent-driven design for DSKintsugi |
| **P2** | just — command runner | casey/just | Replace Makefile-style build scripts |
| **P2** | tmux-fzf — fuzzy session management | sainnhe/tmux-fzf | Patterns for Shikki tmux TUI |
| **P2** | apprise (16k) — notification aggregator | caronc/apprise | Upgrade ntfy → 100+ notification channels |
| **P2** | Crabwalk — agent monitoring | crabwise-ai/crabwalk | Reference for Observatory real-time dashboard |
| **P2** | Walrus — distributed log streaming (Rust) | nubskr/walrus | Raft consensus patterns for event persistence |
| **P2** | Camofox browser — headless for agents | jo-inc/camofox-browser | Agent web automation/scraping |
| **P2** | Kula — Go VPS monitoring TUI | c0m4r/kula | Reference/tool for VPS (92.134.242.73) monitoring |
| **P2** | Keeper.sh — calendar MCP | ridafkih/keeper.sh | Universal calendar sync for scheduling |
| **P3** | Atomic (Rust) — knowledge base | kenforthewin/atomic | Semantic connections reference for ShikiDB |
| **P3** | Skillhub desktop — skill marketplace client | skillhub-club | Competitive intel for skills.sh distribution |
| **P3** | CollabMD — collaborative markdown | andes90/collabmd | Git-backed docs + Excalidraw/Mermaid for specs |

### 2. WABISABI — iOS Habit App

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P2** | swift-macro-testing | pointfreeco | When adopting Swift macros for DI/codegen |
| **P2** | ichinichi — minimal daily journal | katspaugh | UX inspiration for daily practice patterns |
| **P3** | SwiftUI-Animations | Shubham0812 | Animation recipe reference |

### 3. MAYA — Fitness iOS App

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P1** | workout-tracker (Go, 1.2k) | jovandeginste | Data model reference: activities, routes, GPX, stats |
| **P2** | solidtime (8.3k) — time tracking UI | solidtime-io | UI/UX reference for activity tracking |
| **P2** | ziit — code time tracking | 0pandadev | Session tracking patterns |

### 4. BRAINY — RSS + Video

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P2** | lazycut — video trimming TUI | emin-ozata | Video editing patterns for BrainyTube |

### 5. FLSH — Local Voice AI (post-revenue)

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P0** | Kyutai Moshi — full-duplex voice (9.9k) | kyutai-labs/moshi | Core engine: MLX backend, 200ms latency, Rust production |
| **P0** | Pocket TTS — voice cloning (3.6k) | kyutai-labs/pocket-tts | Voice output with 10s voice cloning |
| **P0** | FluidAudio — Swift CoreML audio SDK | FluidInference | **Swift-native** TTS/STT/VAD on Apple Silicon. Priority integration. |
| **P1** | mattt/chat-ui-swift + AnyLanguageModel | mattt | SwiftUI chat + multi-provider AI abstraction |
| **P1** | Hibiki — Rust real-time speech translation | kyutai-labs/hibiki | Multilingual voice (FR/EN) |
| **P1** | qwen-chat-ios — MLX Swift on iOS | andrisgauracs | On-device LLM patterns for iOS |
| **P2** | LuxTTS — 150x realtime TTS | ysharma3501 | Alternative TTS engine |
| **P2** | Gradium — voice AI APIs | gradium.ai | Cloud fallback for noisy environments |

### 6. VIDEO GAMES (with brother, post-revenue)

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P2** | retroassembly — WASM retro emulator | arianrhodsandlot | WebAssembly + emulation patterns |
| **P2** | ACGC-PC-Port — Animal Crossing decompile | flyngmt | C-level game architecture reference |
| **P3** | freeciv21 — turn-based 4X | longturn | Multiplayer turn-based architecture |

### 7. PRIVATE CLOUD / PHOTO MANAGER (post-revenue)

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P1** | openphotos — Rust E2EE photo manager | openphotos-ca | Architecture target: Rust, E2EE, CLIP+face AI discovery |
| **P1** | foldergram — Instagram-style gallery | foldergram | UX reference: folder-based browsing, Docker |
| **P2** | ministack — free LocalStack replacement | Nahuel990 | AWS emulation for local dev if cloud features needed |

### 8. TRIP PLANNER (post-revenue)

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P1** | trip — self-hosted trip planner (1.3k) | itskovacs/trip | **THE reference.** Minimalist, POI map, self-hosted |

### 9. URL SHORTENER (post-revenue)

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P2** | url-shortener-go — Go + Redis starter | aayush-wiz | Simple Go Fiber reference for Umami integration |

### 10. DSKINTSUGI — Design System

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P1** | Penpot (45k) — open-source Figma alt | penpot/penpot | Self-hosted design tool for token workflow |
| **P1** | Penpot MCP — agent-driven design ops | montevive/penpot-mcp | Shikki agents manipulate design files |
| **P2** | Penpot Figma exporter | penpot | Migration bridge if moving from Figma |
| **P2** | Excalidraw — whiteboarding | excalidraw | Architecture diagrams in specs |
| **P3** | open-pencil — AI-native design editor | open-pencil | AI integration reference for DSKintsugi |

### 11. GITHUB PROFILE / LANDING PAGES

| Priority | Item | Source | Action |
|----------|------|--------|--------|
| **P2** | github-readme-stats (79k) | anuraghazra | Dynamic stats for Fr0zenSide/Shiki GitHub profile |
| **P2** | gitprofile (2.2k) | arifszn | Portfolio page generator for obyw.one |

---

## Immediate Action Items (this week)

1. **Merge ShikkiKernel worktree branches** (Wave 1 + Wave 2) — review + merge to integration
2. **Merge ShikiDB Phase 2-4 spec** — review + merge
3. **Install vhs** (`brew install vhs`) — start recording TUI demos
4. **Deep dive crush** — competitive analysis session vs Shikki
5. **Evaluate AnyLanguageModel** — mattt's Swift multi-provider AI abstraction for AgentProvider
6. **Study pm-skills** marketplace model — blueprint for skills.sh

## Revenue-First Priority Order

```
NOW:     WabiSabi → ship to TestFlight
NOW:     Maya → ship with Faustin
THEN:    Shikki → v0.3.0 release (kernel + scheduler + CodeGen)
THEN:    skills.sh → marketplace launch
POST-$:  Flsh → Kyutai Moshi + FluidAudio
POST-$:  Trip planner → trip reference
POST-$:  Photo manager → openphotos reference
POST-$:  URL shortener → Go + Umami
POST-$:  Video games → with brother
```

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-26 | Spec Draft | @Daimyo | Pending review | 100+ repos analyzed, 52 starred, distributed across 13 projects |
