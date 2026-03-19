# Vision: ShikiOS — AI-Native Platform for Devices

> **Type**: Vision + Market Analysis
> **Status**: Active (validated by market data 2026-03-18)
> **Owner**: Jeoffrey / OBYW.one
> **Updated**: with AR/VR market research

---

## Market Reality (2025-2026 data)

| Metric | Value | Source |
|--------|-------|--------|
| Meta Ray-Ban units (2025) | 7M | Counterpoint |
| Smart glasses market growth | +247% YoY | IDC |
| AI glasses forecast (2026) | 20M units, $5.6B | SAG |
| Total XR market (2029) | 43.1M units | IDC |
| Smart glasses CAGR | 29-32% | Multiple |
| OpenAI device investment | $6.4B (Jony Ive acq.) | Built In |
| Humane AI Pin | DEAD (bricked) | TechRadar |
| Rabbit R1 retention | 5% after 5 months | Android Police |

**Key insight**: devices that succeed offer PURPOSE + AI (Ray-Ban). Devices that fail offer AI alone (Humane, Rabbit).

## The Pattern That Works

```
DON'T:  "Buy our AI device"          → Humane, Rabbit (dead)
DO:     "Buy this [purpose] device"   → Meta Ray-Ban (7M units)
        (that happens to run AI)
```

## ail Product Line (proposed)

### v1: ail Reader (€99)
- Raspberry Pi + e-ink/LCD screen
- WebSocket client for Maya live sessions
- Real-time fitness data display
- Shiki orchestrates the data pipeline
- **What user buys**: "a fitness display"
- **What it actually is**: ShikiOS v0.1 on hardware

### v2: ail Coach (€299)
- Smart glasses form factor (ODM partnership)
- Maya coaching overlay (rep counter, form check, heart rate)
- Shiki agent provides real-time guidance
- **What user buys**: "smart sports glasses"
- **What it actually is**: ShikiOS with AR layer

### v3: ail Studio (€599)
- Dev workstation (mini PC or laptop)
- Full ShikiOS as primary OS
- Observatory TUI = desktop environment
- Command palette = app launcher
- Agent personas = system services
- **What user buys**: "an AI dev machine"
- **What it actually is**: the real ShikiOS

## Architecture Reality Check

What we already built that maps to OS concepts:

| Shiki Component | OS Equivalent | Status |
|----------------|---------------|--------|
| Event Router | System message bus (D-Bus) | BUILT |
| Agent Personas | System services with capabilities | BUILT |
| Session Lifecycle | Process management (systemd) | BUILT |
| Watchdog | System health monitor | BUILT |
| Observatory | Task manager / system monitor | BUILT |
| Command Palette | App launcher (Spotlight) | BUILT |
| Knowledge MCP | Filesystem intelligence | SPEC'D |
| @who #where /what | Shell grammar | SPEC'D |

**Shiki IS the OS. Currently hosted on macOS. The port is the last mile.**

## Competitive Landscape (2026)

| Player | Approach | Investment | Timeline |
|--------|----------|------------|----------|
| Meta | Glasses + Meta AI | $10B+/year (Reality Labs) | Shipping now |
| Apple | Vision Pro → glasses pivot | $3B+ | Late 2026 reveal |
| OpenAI | AI-first device (Jony Ive) | $6.4B | H2 2026 earliest |
| Nothing | AI-native OS | Undisclosed | 2026 |
| Samsung | Android XR glasses | Undisclosed | 2026 |
| Google | Android XR platform | Undisclosed | 2026 |
| **Shiki/ail** | **Open-source AI-native platform** | **€0 (so far)** | **v1: 2026** |

**Our advantage**: open-source + vertical integration (Maya users) + no VC pressure to ship hardware before the AI is ready.

**Our disadvantage**: budget. But ail Reader v1 is a Raspberry Pi — it costs €30 in components.

## Business Structure

```
Jeoffrey Holdings (personal)
  └── OBYW.one
        ├── Shiki (AGPL-3.0, open source)
        │     └── ShikiOS (future, same license)
        └── License revenue from:
              ├── Maya SAS (customer #1, contributor #1)
              ├── Enterprise licenses
              └── Hardware partnerships (ail)

Maya SAS (with Faustin)
  ├── Maya.fit app
  ├── Shiki contributor
  └── ail Reader v1 first customer
```

## Why NOT to do it (honest risks)

1. Hardware requires supply chain, FCC/CE certification, customer support
2. Every dollar spent on hardware is a dollar not spent on Shiki software
3. Meta has $10B/year Reality Labs budget — you have €0
4. The smart glasses market could plateau (Gartner hype cycle trough)
5. Open-source OS has failed before (Ubuntu Phone, Firefox OS, webOS)

## Why TO do it (the counter-counter)

1. Those failures didn't have AI. The game changed.
2. €30 Raspberry Pi != €3,500 Vision Pro. Your v1 cost is near zero.
3. Maya users are a captive audience for fitness hardware.
4. AGPL-3.0 means you can license ShikiOS commercially while keeping it open.
5. Nobody is building open-source AI-native OS. The niche is empty.
6. The dev community WANTS this. Linux devs + AI devs = your contributor base.
