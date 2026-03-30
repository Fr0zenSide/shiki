# Radar: Retro Gaming Devices as Tiny Shikki Clients

**Date**: 2026-03-30
**Category**: Hardware / Novelty Clients
**Status**: Research Complete

---

## 1. Playdate (Panic Inc.)

### Hardware Profile
| Spec | Value |
|------|-------|
| Display | 400x240px, 1-bit monochrome (black & white), memory LCD |
| Refresh | 30 FPS default, 50 FPS max |
| CPU | STM32 Cortex-M7 (ARM) |
| RAM | 16 MB |
| Storage | 4 GB flash |
| Connectivity | **WiFi + Bluetooth** |
| Input | D-pad, A/B buttons, menu button, **crank** (rotary encoder) |
| Price | ~$199 USD |
| SDK | Free, macOS/Windows/Linux |

### SDK & Languages
- **Lua** — primary game scripting language, full API access
- **C** — native performance, full SDK access via `playdate->` API struct
- **Embedded Swift** — Apple's `swift-playdate-examples` (453 stars) + **PlaydateKit** (305 stars, CC0 license) provide Swift bindings to C API. Requires nightly Swift 6.0 toolchain. Early but functional.
- **Pulp** — browser-based no-code game editor (not relevant for Shikki)

### Networking Capabilities (CONFIRMED)
The Playdate SDK exposes real networking APIs:

**HTTP (async, callback-based):**
- `playdate.network.http.get(url, headers, callback)` — async GET, callback receives body + status + headers
- `playdate.network.http.post(url, data, headers, callback)` — async POST
- `playdate.network.http.request(method, url, [data], [headers], callback)` — generic HTTP method

**TCP Sockets (raw):**
- `playdate.network.tcp.socket.new()` — create socket
- `socket:connect(host, port, callback)` — async connect
- `socket:send(data)` — transmit data, returns bytes sent
- `socket:receive(numberOfBytes, callback)` — async read
- `socket:close()` — terminate connection

**No WebSocket built-in**, but raw TCP sockets mean a WebSocket handshake could theoretically be implemented in userspace. More practically, HTTP polling or a lightweight custom protocol over TCP would work.

**No NATS client exists** for Playdate. The protocol could be partially implemented over TCP sockets, but the constrained environment (16 MB RAM, no threading model) makes a full NATS client impractical. A simpler approach: HTTP long-poll or periodic GET against a Shikki relay endpoint.

### Blue Flame Mascot in 1-Bit
**Verdict: YES, and it would look fantastic.**

1-bit pixel art has a rich aesthetic tradition. The 400x240 display is generous for pixel art — comparable to early Mac resolutions. Techniques:
- **Floyd-Steinberg dithering** for gradients/shading
- **Stippling patterns** for flame glow effects
- **Animation frames** at 30 FPS for flickering flame
- The **crank** could control flame intensity/animation speed

Libraries: `8x8.me` (120 stars) provides monotone fill patterns. Pixen (935 stars) is a pixel art editor with 1-bit export. The Playdate community has deep expertise in 1-bit art.

### Chat/Messaging Precedent
No known chat or messaging app exists on Playdate. The device is game-focused. However:
- WiFi games exist (leaderboard submissions, score sharing)
- The SDK has all the primitives needed (HTTP + TCP + text rendering + file storage)
- A notification receiver is entirely feasible

### Shikki Client Feasibility

| Capability | Feasible? | Notes |
|-----------|-----------|-------|
| Network connection | YES | WiFi + HTTP + TCP sockets |
| Display text/notifications | YES | Multiple font sizes, text rendering API |
| Simple chat client | YES (limited) | HTTP polling, text input via on-screen keyboard or crank-scroll |
| Blue Flame render | YES | 1-bit dithered pixel art, animated |
| NATS client | NO (too heavy) | Use HTTP relay instead |
| Background notifications | NO | Apps run in foreground only, no background execution |
| Persistent connection | PARTIAL | TCP socket while app is active, no background daemon |

**Architecture for Shikki on Playdate:**
```
Playdate App (Lua or Swift)
  |
  |-- HTTP GET /api/shikki/notifications (periodic poll, every 30-60s)
  |-- HTTP POST /api/shikki/acknowledge (mark as read)
  |-- Display: scrollable notification list
  |-- Crank: scroll through messages
  |-- A button: acknowledge/dismiss
  |-- B button: quick-react (predefined responses)
  |
Shikki Relay API (lightweight HTTP endpoint)
  |
  |-- Bridges to NATS/event bus
  |-- Filters notifications for Playdate client
  |-- Returns JSON payloads (compact, <4KB per batch)
```

**Development effort**: ~2-3 weeks for MVP (Lua), ~4-5 weeks in Swift (toolchain friction).

---

## 2. Analogue Pocket

### Hardware Profile
| Spec | Value |
|------|-------|
| Display | 1600x1440px, 3.5" LCD, 615 PPI, full color |
| FPGA (main) | Intel Cyclone V, 49K logic elements, 3.4 Mbit BRAM |
| FPGA (secondary) | Intel Cyclone 10, 15K logic elements |
| RAM | 2x 16 MB cellular RAM + 32 MB low-latency + 64 MB SDRAM + 256 KB SRAM |
| Storage | microSD card |
| Connectivity | **USB-C only** (charging + data). NO WiFi. NO Bluetooth (only via Dock + external controllers). Link port (Game Boy protocol). |
| Input | D-pad, A/B/X/Y, L/R bumpers, Start/Select |
| Price | ~$249 USD |
| Development | openFPGA platform (Verilog/VHDL) |

### Development Model: openFPGA
This is fundamentally different from the Playdate. There is **no software SDK**. Development means:

1. **Writing Verilog or VHDL** — hardware description languages
2. **Synthesizing FPGA bitstreams** — compiling logic gates
3. **Targeting the Cyclone V FPGA** — 49K logic elements
4. Creating a **core** that implements an entire system (CPU + GPU + I/O)

The `open-fpga/core-template` repository provides JSON configuration scaffolding (`core.json`, `video.json`, `audio.json`, `input.json`) and starter Verilog. The community has built cores for: NES, SNES, Game Boy, Genesis, TurboGrafx-16, Neo Geo, and even a PDP-1.

### Can Custom Software Run?
**Yes, but it means implementing a soft CPU in Verilog**, then writing software for that CPU. This is how the PDP-1 Spacewar! core works — the entire PDP-1 computer is described in Verilog, then the original Spacewar! binary runs on it.

For a Shikki client, you would need to:
1. Implement a soft CPU (e.g., RISC-V) in Verilog
2. Write a framebuffer driver for the 1600x1440 display
3. Write networking... except **there is no network hardware to drive**

### Networking: DEAD END
The Analogue Pocket has **no WiFi, no Bluetooth radio accessible to cores, and no Ethernet**. The only data paths are:
- **USB-C** — for charging and PocketOS firmware updates, not exposed to cores
- **Link port** — Game Boy serial protocol (115 kbps max, requires physical cable + another device)
- **microSD** — file storage only, no network interface

A networking workaround would require:
- A custom cartridge adapter with a WiFi/BLE module on the link port (bespoke hardware)
- Or loading data onto microSD from a computer (sneakernet)

### Blue Flame on Analogue Pocket
**Verdict: Technically stunning but impractical to deliver.**

The 1600x1440 display at 615 PPI is gorgeous — a full-color Blue Flame would be pixel-perfect. But rendering it requires writing a Verilog-based graphics pipeline. The development effort would be enormous for a static image, let alone animation.

### Shikki Client Feasibility

| Capability | Feasible? | Notes |
|-----------|-----------|-------|
| Network connection | **NO** | No WiFi, no BLE, no Ethernet |
| Display text/notifications | EXTREME | Requires Verilog framebuffer + font renderer |
| Simple chat client | **NO** | No network path |
| Blue Flame render | THEORETICAL | Beautiful display but needs FPGA graphics pipeline |
| NATS client | **NO** | No network hardware |
| Development effort | MONTHS+ | FPGA expertise required (Verilog/VHDL) |

**Verdict: NOT VIABLE as a Shikki client.** The Analogue Pocket is a hardware preservation device, not a general-purpose computer. No network connectivity, no software SDK, FPGA-only development in Verilog. The only "Shikki" possibility would be a decorative Blue Flame screensaver core — visually impressive but functionally useless.

---

## 3. Feasibility Matrix

| Criterion | Playdate | Analogue Pocket |
|-----------|----------|-----------------|
| Network connectivity | WiFi (HTTP + TCP) | None |
| Text/notification display | Native API | Verilog framebuffer (months) |
| Chat client | Feasible (HTTP poll) | Impossible (no network) |
| Blue Flame render | 1-bit dithered (charming) | Full color (stunning but impractical) |
| Dev effort (MVP) | 2-3 weeks (Lua) | 3-6 months (Verilog) |
| SDK maturity | Mature (v3.0.3) | Template only |
| Swift option | Yes (PlaydateKit) | No |
| Fun factor | HIGH | Low (pain/reward ratio) |
| Practical value | Medium (novelty notifier) | None |
| **Overall rating** | **GO** | **NO-GO** |

---

## 4. Context: Primary vs. Novelty Platforms

Shikki's primary targets remain:
- **macOS** — TUI + native app (primary development platform)
- **iOS** — companion app, push notifications, Apple Watch
- **Linux** — TUI, server-side, SSH access

A Playdate client would be a **novelty companion** — a desk toy that glows with your Blue Flame and shows agent notifications. It is NOT a primary interface. The value proposition:

1. **Brand expression** — 1-bit Blue Flame pixel art is inherently cool and on-brand
2. **Physical presence** — a desk object that lights up when Shikki has something to say
3. **Crank interaction** — uniquely tactile way to scroll/dismiss notifications
4. **Developer marketing** — "Shikki runs on a Playdate" is a conversation starter
5. **Dogfooding** — proves the Shikki API is truly platform-agnostic

---

## 5. Action Items

### Immediate (P4 — Fun / Brand)
- [ ] **Commission 1-bit Blue Flame sprite sheet** — 32x32 and 64x64 versions, 4-frame flicker animation, Floyd-Steinberg dithered. Could be done in Pixen or Aseprite.
- [ ] **Prototype Playdate notification receiver** — Lua, HTTP GET poll against a mock endpoint, display scrollable text list, crank to scroll. 1-2 day spike.

### Deferred (post-v1)
- [ ] **PlaydateKit Swift client** — if Swift toolchain stabilizes, write the Playdate Shikki client in Swift using PlaydateKit. Aligns with all-Swift strategy.
- [ ] **Shikki Relay API endpoint** — lightweight HTTP endpoint that bridges NATS events to a Playdate-friendly JSON format (compact payloads, <4KB).
- [ ] **Crank-based interaction model** — design UX for crank = scroll, A = acknowledge, B = quick-react, menu = settings.

### Parked
- [ ] ~~Analogue Pocket core~~ — NO-GO. Revisit only if Analogue ships a software SDK or WiFi module.

---

## 6. References

- Playdate SDK docs: https://sdk.play.date/inside-playdate
- Playdate C API: https://sdk.play.date/inside-playdate-with-c
- PlaydateKit (Swift): https://github.com/finnvoor/PlaydateKit (305 stars, CC0)
- Apple Embedded Swift examples: https://github.com/apple/swift-playdate-examples (453 stars)
- openFPGA core template: https://github.com/open-fpga/core-template
- Analogue developer portal: https://www.analogue.co/developer
- 8x8.me fill patterns: https://github.com/8x8.me (1-bit pattern library)
- Playdate dev forum: https://devforum.play.date/
