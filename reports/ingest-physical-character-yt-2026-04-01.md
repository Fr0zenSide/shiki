# Ingest: Physical Character Inspiration — mewtru's Plant Tamagotchi Series

**Date**: 2026-04-01
**Source**: https://youtube.com/shorts/kusHKiR-NXQ (Part 3)
**Creator**: Tru Narla (@mewtru)
**Channel**: https://www.youtube.com/channel/UCJjwbqI73KPVtOqctkblcng

---

## 1. Creator Profile: mewtru (Tru Narla)

- **Who**: Software engineer (previously at Discord, Portland-based), content creator
- **Platforms**: YouTube (long-form + Shorts), TikTok (122.8K followers), Instagram (336K followers), Threads, Bluesky, Twitch
- **Brand tagline**: "I make cute things"
- **Website**: mewtru.com (web projects: Mixtape, FlappyFavi, Wordflow, etc.)
- **Shop**: mewtru-shop.fourthwall.com (merch/donations)
- **Background**: Started streaming code on Twitch in 2020. Featured on Figma Blog ("Behind the Build" Q&A). Software engineer who pivoted into hardware maker content in 2025-2026.

### Why mewtru matters for Shikki

mewtru represents the exact intersection Shikki targets: **software engineer who builds cute physical hardware as a creative outlet**. Their audience (300K+) proves there is a market for "developer makes adorable gadget" content. Their approach is accessible (short-form build logs), aesthetically driven (cute > functional), and merch-adjacent (Fourthwall shop).

---

## 2. The Plant Tamagotchi Series (4 parts)

### Part 1: "I'm making a tamagotchi for my plant!"
- **Date**: 2026-03-12
- **Views**: 384,843 (breakout hit)
- **Duration**: 64s
- **URL**: https://www.youtube.com/watch?v=2oZ54jr4moM

### Part 2: "I'm making a tamagotchi for my plant! Part 2!"
- **Date**: 2026-03-14
- **Views**: 36,202
- **Duration**: 67s
- **URL**: https://www.youtube.com/watch?v=f53gpwbqXVA

### Part 3: "I'm making a tamagotchi for my plant! Part 3!" (the original link)
- **Date**: 2026-03-18
- **Views**: 98,615
- **Duration**: 64s
- **URL**: https://www.youtube.com/watch?v=kusHKiR-NXQ

### Part 4 (Final): "I made a tamagotchi for my plant! (final part)"
- **Date**: 2026-04-01 (today)
- **Views**: 2,438 (just published)
- **Duration**: 67s
- **URL**: https://www.youtube.com/watch?v=IVS2FFVhVU0

### Series pattern
- Part 1 = concept + initial build (highest virality: 385K views)
- Parts 2-3 = progress logs (sustained engagement)
- Final part = reveal (just dropped, will likely surge)
- Total series reach: ~520K+ views across 4 shorts

---

## 3. What Is Being Created

A **plant tamagotchi** — a small device that sits in or near a plant pot, monitors the plant's health (soil moisture, light, temperature), and displays an animated character face whose expressions change based on the plant's condition. The character is happy when the plant is well-cared-for and sad/angry when it needs attention.

### Techniques (inferred from mewtru's hardware series pattern)

mewtru's other recent hardware projects provide strong inference about their build approach:

| Project | Date | Components (inferred) |
|---------|------|-----------------------|
| Digital camera series (3 parts) | 2026-02-12 to 2026-02-14 | ESP32-CAM, small display, 3D-printed enclosure |
| Pocket Kindle | 2026-02-02 | ESP32, e-paper/e-ink display, 3D-printed case |
| MP3 player / Hit Clips (2 parts) | 2026-02-17 to 2026-02-20 | ESP32, small speaker, SD card, 3D-printed shell |
| Cyberdeck | 2026-03-20 | ESP32/RPi, full-color e-paper display, keyboard |
| **Plant tamagotchi (4 parts)** | 2026-03-12 to 2026-04-01 | ESP32, soil moisture sensor, small display, 3D-printed pot-clip/case |

### Consistent mewtru build formula
1. **Microcontroller**: ESP32 (likely ESP32-S3 or XIAO ESP32-S3 Sense)
2. **Display**: Small OLED or TFT (round or rectangular, ~0.96"-1.3")
3. **Enclosure**: 3D-printed custom case (cute aesthetic, rounded, pastel colors)
4. **Power**: USB-C (desk-powered) or small LiPo battery
5. **Sensors**: Project-specific (soil moisture for plant tamagotchi)
6. **Software**: Arduino/MicroPython firmware with animated face graphics
7. **Aesthetic**: Kawaii-influenced, pastel colors, rounded forms, character-driven

### Key observation on the color e-paper short
The short "This full color epaper display is INSANE" (2026-03-17, 207K views) dropped right between plant tamagotchi parts 2 and 3. This strongly suggests the plant tamagotchi may use a **color e-paper display** — a major aesthetic upgrade over standard OLED.

---

## 4. Comparable Projects in the Ecosystem

### Open-source / DIY

| Project | MCU | Display | Sensors | Cost | Difficulty |
|---------|-----|---------|---------|------|------------|
| **FloraCare** (Hackster.io, 2026) | ESP32-S3 | 3.5" color TFT (SPI) | DHT22 + BH1750 + soil moisture | ~$25-40 | Intermediate |
| **TN-24 V2.0** (Hackster.io, 2025) | XIAO ESP32-S3 | 0.96" OLED | MPU6050 (motion) | ~$30-50 | Intermediate |
| **Bopi** (XDA, 2026) | ESP32-S3 | Screen + mic | Microphone + speech | ~$30-60 | Intermediate |
| **Tiny Desktop Pet** (Hackster.io, 2025) | XIAO ESP32-S3 | 0.96" OLED | Touch | ~$15-25 | Beginner+ |
| **Catode32** (XDA, 2026) | ESP32 | SSD1306 OLED | Touch/interaction | ~$10-20 | Beginner |
| **Plantagotchi DIY** (Instructables) | Arduino | TFT | Light + soil | ~$20-30 | Beginner+ |
| **TamaFi** (Hackaday, 2024) | ESP32 | Color TFT LCD | WiFi feeding | ~$25-35 | Intermediate |

### Commercial products

| Product | Price | Display | Sensors | Status |
|---------|-------|---------|---------|--------|
| **Senso** (SoildTech, CES 2026) | TBD (Kickstarter soon) | Pixel character | Soil moisture + temp + light | Pre-launch |
| **Plantagotchi** | $99.99 (was $219) | 49 animated expressions | Soil + light + temp | Shipping (3.37/5 rating) |
| **Lua Smart Planter** | ~$80-100 | 2.4" IPS LCD, 15 emotions | Soil + temp + light | Shipping |
| **PlantBot** | ~$50-80 | Interactive face | Moisture | Shipping |

---

## 5. Shikki Physical Form: Blue Flame Desk Companion

### Concept: "Shikki-chan" Physical Desk Companion

A small 3D-printed character that sits on the developer's desk, USB-powered, displaying Shikki's Blue Flame face. It reacts to real events from the Shikki orchestration system via USB serial or WiFi.

### Design vision

```
    ╭─────────╮
    │  ◉   ◉  │   ← Round color display (eyes/expression)
    │    ◡    │   ← Animated Blue Flame face
    ╰─────────╯
     /  ╲  ╱  \   ← 3D-printed flame-shaped body (translucent blue resin)
    │  ░░░░░░  │   ← Internal RGB LED glow (blue → orange based on state)
    ╰──────────╯
        ║║       ← USB-C base (power + data)
```

### Hardware BOM (estimated)

| Component | Part | Est. Cost |
|-----------|------|-----------|
| MCU | XIAO ESP32-S3 or ESP32-C3 | $7-12 |
| Display | 1.28" round GC9A01 TFT (240x240) | $5-10 |
| LEDs | WS2812B NeoPixel ring (8-12 LEDs) | $3-5 |
| Enclosure | 3D-printed (translucent blue PETG or resin) | $5-15 |
| Power | USB-C (desk-powered, no battery needed) | $0 (built into ESP32) |
| Optional: speaker | Small piezo or PAM8403 + tiny speaker | $2-5 |
| Optional: touch | Capacitive touch pad (built into ESP32 GPIO) | $0 |
| **Total** | | **$22-47** |

### How it comes to life: Event-reactive behavior

The physical Shikki connects to the Shikki orchestration system and reacts to real events:

| ShikiCore Event | Physical Reaction |
|----------------|-------------------|
| `pipeline_started` | Eyes light up, flame glows brighter |
| `test_passed` | Happy face, green LED pulse |
| `test_failed` | Worried face, red flash |
| `deploy_success` | Celebration animation, rainbow LED |
| `agent_dispatched` | Eyes look sideways (watching subagent) |
| `idle` (>5min) | Sleepy face, dim blue glow, slow breathing LED |
| `error` | Alarmed face, rapid red pulse |
| `context_compaction` | Yawn animation |
| `pr_merged` | Party face + victory sound |

### Communication protocol

```
USB Serial (simplest):
  Host (macOS) → ESP32 via USB-C serial
  JSON messages: {"event": "test_passed", "detail": "42/42 green"}

WiFi (advanced):
  ESP32 connects to local WiFi
  WebSocket to ShikiCore event bus
  Same JSON protocol
```

### Firmware architecture

```
main.cpp
├── face_renderer.cpp    // Animated face sprites on round TFT
├── led_controller.cpp   // NeoPixel ring effects (breathing, pulse, rainbow)
├── event_listener.cpp   // USB serial or WiFi WebSocket JSON parser
├── animation_engine.cpp // State machine: idle → happy → worried → sleep
└── sound_player.cpp     // Optional: tiny speaker for chimes
```

### Difficulty assessment

| Aspect | Level | Notes |
|--------|-------|-------|
| 3D modeling | Beginner-Intermediate | Fusion 360 or TinkerCAD, flame shape |
| 3D printing | Beginner | Standard FDM or resin printer |
| Electronics | Beginner | No soldering if using XIAO dev board + dupont wires |
| Firmware | Intermediate | Arduino IDE, GC9A01 display library, NeoPixel library |
| Host integration | Intermediate | Python/Swift script to bridge ShikiCore events → serial |
| **Overall** | **Intermediate maker hobbyist** | 1-2 weekends to build |

---

## 6. Merch Potential: Sellable Physical Shikki

### Tier 1: DIY Kit ($35-50)
- Pre-printed 3D enclosure (translucent blue)
- Pre-soldered XIAO ESP32 + round display breakout
- NeoPixel ring
- USB-C cable
- Instruction card + firmware flash tool (web-based, like ESP Web Tools)
- **Margin**: ~60% at $45 price point

### Tier 2: Assembled Unit ($75-120)
- Fully assembled, plug-and-play
- Pre-flashed firmware with default animations
- Connects to WiFi for ShikiCore events
- Desktop stand with cable management
- **Margin**: ~50% at $95 price point

### Tier 3: Limited Edition ($150-200)
- Resin-printed (higher detail, translucent blue)
- Hand-painted details
- Numbered/signed
- Custom animations
- **Margin**: ~40% at $175 price point

### Production scaling

| Scale | Method | Unit Cost | Lead Time |
|-------|--------|-----------|-----------|
| 1-10 | Home 3D printer + hand assembly | $15-25 | 2-4 hours each |
| 10-50 | JLCPCB custom PCB + JUSTWAY 3D printing | $12-20 | 2-3 weeks |
| 50-200 | Small batch injection molding feasibility study | $8-15 + tooling | 4-6 weeks |
| 200+ | Fourthwall/Shopify fulfillment | Evaluate | TBD |

### Content-to-merch pipeline (the mewtru playbook)

mewtru's exact formula, applied to Shikki:

1. **Short-form build series** (4-6 parts, ~60s each) documenting the build
2. **Breakout Part 1** establishes virality (mewtru hit 385K on Part 1)
3. **Progress parts** sustain engagement
4. **Final reveal** + "want one?" CTA
5. **Fourthwall/Shopify drop** for the kit or assembled unit
6. **Open-source the firmware** on GitHub (community goodwill, contributions)

---

## 7. Related mewtru Content (full channel map)

### Recent Shorts (2026, newest first)

| Date | Title | Views | Duration |
|------|-------|-------|----------|
| 2026-04-01 | I made a tamagotchi for my plant! (final part) | 2.4K | 67s |
| 2026-03-23 | I made a digital camera... but something's wrong with it | 2.3M | 76s |
| 2026-03-20 | I can't believe my cyberdeck runs this | 33K | 101s |
| 2026-03-18 | **I'm making a tamagotchi for my plant! Part 3!** | 98.6K | 64s |
| 2026-03-17 | This full color epaper display is INSANE | 207K | 77s |
| 2026-03-16 | How to make a tiny kindle!! | 125K | 117s |
| 2026-03-14 | I'm making a tamagotchi for my plant! Part 2! | 36K | 67s |
| 2026-03-12 | I'm making a tamagotchi for my plant! | 385K | 64s |
| 2026-03-02 | Day in the life of a software engineer at Google('s friend) | 34K | 44s |
| 2026-02-20 | I'm making an mp3 player! Part 2 | 33K | 43s |
| 2026-02-17 | I'm making an mp3 player (hit clips)!! Part 1 | 20K | 69s |
| 2026-02-14 | I made a digital camera!! Part 3 | 18K | 60s |
| 2026-02-02 | I made myself a pocket kindle | 18K | 25s |

### Long-form Videos

| Date | Title | Views |
|------|-------|-------|
| 2026-01-20 | Nobody cares that you can code. | 17K |
| 2023-03-15 | I hate coding | 79K |
| 2023-01-11 | Can YOU solve this frontend interview question? | 149K |
| 2023-01-04 | Building a design system in Next.js with Tailwind! | 36K |

### Key pattern
The channel pivoted from **coding tutorials** (2023) to **cute hardware maker content** (2025-2026). The hardware pivot brought massive growth — the digital camera short hit 2.3M views. The maker shorts consistently outperform coding content by 10-100x.

---

## 8. Action Items for Shikki

### Immediate (P1)
- [ ] **Prototype Blue Flame desk companion**: Order XIAO ESP32-S3 + GC9A01 round display + NeoPixel ring. Design flame-shaped enclosure in Fusion 360. Weekend project.
- [ ] **Bridge script**: Python/Swift script that reads ShikiCore events and sends JSON over USB serial to the companion device.
- [ ] **Face sprite sheet**: Design Blue Flame expressions (idle, happy, worried, sleepy, celebrating, alarmed) as pixel art or vector → bitmap.

### Near-term (P2)
- [ ] **Build log content series**: Document the build as 4-6 short-form videos (mewtru playbook). This is marketing for both Shikki and any future merch.
- [ ] **Open-source firmware**: GitHub repo with Arduino/PlatformIO project, STL files for enclosure, wiring diagram.
- [ ] **Evaluate merch viability**: Once prototype works, assess DIY kit vs assembled unit pricing.

### Future (P3)
- [ ] **WiFi mode**: ESP32 connects to local network, subscribes to ShikiCore event bus via WebSocket. No USB cable needed.
- [ ] **Multi-companion**: Different characters for different agents (@Sensei, @Ronin, @Katana) — collectible series.
- [ ] **Sound design**: Tiny speaker for event chimes (test pass ding, deploy fanfare, error buzz).

---

## Sources

- [mewtru YouTube channel](https://www.youtube.com/channel/UCJjwbqI73KPVtOqctkblcng)
- [mewtru website](https://mewtru.com/)
- [mewtru shop (Fourthwall)](https://mewtru-shop.fourthwall.com/)
- [mewtru on Bluesky](https://bsky.app/profile/mewtru.com)
- [FloraCare ESP32-S3 Plant Tamagotchi (Hackster.io)](https://www.hackster.io/0Zane/floracare-the-esp32-s3-plant-tamagotchi-7ef325)
- [TN-24 V2.0 Desktop Companion Robot (Hackster.io)](https://www.hackster.io/tech_nickk/tn-24-v2-0-cute-desktop-companion-robot-44a472)
- [Bopi AI Desk Companion (XDA)](https://www.xda-developers.com/this-cute-esp32-project-is-like-a-tamagotchi-that-listens-to-you/)
- [Tiny Desktop Pet (XDA)](https://www.xda-developers.com/esp32-desk-pet/)
- [Senso Plant Sensor / CES 2026 (MacRumors)](https://www.macrumors.com/2026/01/06/senso-plant-sensor-ces-2026/)
- [Plantagotchi AI Smart Planter](https://myplantagotchi.com/products/platagotchi)
- [Senso / Engadget](https://www.engadget.com/home/smart-home/this-tamagotchi-clone-is-designed-to-help-you-keep-your-plants-alive-172000982.html)
- [Lua Smart Planter (Designboom)](https://www.designboom.com/technology/lua-smart-planter-facial-expressions-07-15-2019/)
- [Plantagotchi DIY (Instructables)](https://www.instructables.com/Plantagotchi/)
- [Catode32 Open Source Tamagotchi (XDA)](https://www.xda-developers.com/you-too-can-install-this-cute-open-source-tamagotchi-on-your-esp32/)
- [Figma Blog: Behind the Build with Tru Narla](https://www.figma.com/blog/behind-the-build-a-qanda-with-developer-tru-narla/)
