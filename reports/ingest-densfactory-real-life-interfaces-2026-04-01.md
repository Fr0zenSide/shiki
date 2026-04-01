# Ingest: Real-Life Interface Inspiration for Blue Flame

> **Date**: 2026-04-01
> **Sources**: ZAUEY (Claire Zau) YouTube, Den's Factory YouTube, @densfactory channel
> **Purpose**: Research techniques for making the Blue Flame character appear "in the real world" for promotional content
> **Related**: `features/shikki-blue-flame.md`, `features/shikki-promo-video-v1.md`

---

## Source 1: ZAUEY (Claire Zau) — "Engineering Disney's Olaf Robot"

- **URL**: https://youtube.com/shorts/zi0xi_UwvBU
- **Channel**: ZAUEY (Claire Zau) — VC partner / tech explainer creator
- **Duration**: 128s | **Views**: 504,593
- **Platforms**: YouTube, TikTok (@zauey, 101K followers), Instagram, Threads

### What the video shows

Claire Zau explains the engineering behind Disney's autonomous Olaf robot (NVIDIA GTC 2026). The format is a direct-to-camera talking head explainer filmed in a home setting with text overlays ("disney's olaf robot engineering") and a handheld mic. The thumbnail shows her at a counter gesturing with her hands.

This specific video does NOT use animated character overlays. It is a classic shorts-format explainer with bold text, fast cuts, and captions.

### Technique analysis

- **Format**: Talking head + text overlay + real footage B-roll
- **Tools likely used**: iPhone camera, CapCut or Premiere Pro for text overlays, standard social media editing workflow
- **No AR/animation blend in this specific video** — the "animated character / real life blend" aspect may come from other videos on her channel or was misidentified

### Relevance to Blue Flame

- **Low direct relevance** for the "character in real life" technique
- **High relevance** for promotional format: a fast-cut, personality-driven explainer about the tech behind Shikki could work well
- The Olaf robot itself is deeply relevant: Disney used reinforcement learning + NVIDIA Kamino simulator to create an autonomous character that walks through real spaces. This is the ultimate "character in real life" at the physical robotics end of the spectrum

### Disney Olaf Robot — Key Technical Details (from the video topic)

| Aspect | Detail |
|--------|--------|
| Size | 35 inches, 33 lbs |
| Challenge | Motor overheating inside foam costume, not balance |
| Solution | RL-trained self-regulation of temperature (adjusts posture + motor load) |
| Training | Kamino GPU-powered simulator, 100K parallel Olafs, trained in 2 days on one RTX 4090 |
| Partners | Walt Disney Imagineering + NVIDIA + Google DeepMind |
| Deployed | Disneyland Paris, World of Frozen, March 29, 2026 |

---

## Source 2: Den's Factory — "Plus qu'une simple lampe..." (More than just a lamp)

- **URL**: https://youtube.com/shorts/_8gXy-_kBFY
- **Channel**: Den's Factory (@densfactory)
- **Duration**: 26s | **Views**: 16,908
- **Language**: French

### What the video shows

A 3D-printed Calcifer-like flame character (from Studio Ghibli's Howl's Moving Castle) sitting on a shelf, glowing from within with warm orange/red LED light. The character has googly-style eyes and a smiling face. The title text "Voila POURQUOI !!" overlays the footage. The flame character is a physical 3D-printed shell housing Den's Factory's custom "Module Effet Flamme 360" PCB inside.

The video also shows a Tintin rocket lamp with the same LED flame module glowing at the base — demonstrating the module's versatility for any 3D-printed character shell.

### Technique analysis

**This is NOT digital compositing. This is a physical product.**

- **Technique**: 3D-printed translucent/semi-opaque character shell + custom LED PCB module inside
- **The PCB**: "Module Effet Flamme 360" — a 24-LED circular PCB with a pre-programmed microcontroller that runs a dynamic (non-repeating) flame animation algorithm
- **Power**: 5V USB, plug and play, no configuration needed
- **Result**: A physical character that glows and flickers like a real flame from within

### The Module Effet Flamme 360 — Specs

| Spec | Value |
|------|-------|
| LEDs | 24 units, 360-degree arrangement |
| Power | 5V DC (USB) |
| Controller | Pre-programmed MCU, dynamic algorithm (no visible loops) |
| PCB | 2-layer professional board |
| Price | ~29 EUR (limited edition, 50 units) |
| State | Fully assembled, tested, ready to integrate |
| Shop | densfactory.com |

### Relevance to Blue Flame — EXTREMELY HIGH

This is the most directly applicable technique for making Shikki's Blue Flame exist in the real world.

**The path is clear:**
1. Design a 3D-printable Blue Flame character shell (translucent blue resin or PETG)
2. Replace the warm orange LEDs with Shikki Blue LEDs (`#4FC3F7`)
3. House the LED module inside the shell
4. The flame glows, flickers, and feels alive — sitting on a desk, shelf, or next to a monitor

**Bonus**: Because it is purely physical, it requires zero post-production VFX. It just films as-is. Point a camera at it, it looks magical.

---

## Source 3: @densfactory Channel — Full Shorts Catalog (10 most recent)

Den's Factory is a French maker/electronics/3D printing YouTube channel. The creator designs custom PCBs, 3D prints enclosures, and documents the process in short-form content.

### Recent Shorts (newest first)

| # | Title | Date | Duration | Views | Topic |
|---|-------|------|----------|-------|-------|
| 1 | Mais POURQUOI... j'ai voulu tester une CNC !! | 2026-03-16 | 54s | 24,077 | CNC router test (ACMER Ascarva 4S) |
| 2 | C'est gratuit et vos batteries dureront bien plus longtemps | 2026-03-03 | 35s | 15,245 | 3D-printed battery holder (Thingiverse) |
| 3 | Plus qu'une simple lampe... | 2026-02-20 | 26s | 16,908 | Flame module in character shells (Calcifer) |
| 4 | Module Effet Flamme 360 | 2026-02-15 | 11s | 3,926 | Raw PCB demo — the flame module itself |
| 5 | A la poubelle et on recommence! | 2026-02-12 | 60s | 643,847 | Failed PCB batch (PCBWay + KiCad plugin) |
| 6 | Webcam no name sur une imprimante 3D ? | 2026-02-06 | 43s | 40,165 | Cheap webcam on a 3D printer |
| 7 | Une TV sur mon imprimante 3D | 2026-01-29 | 57s | 29,961 | Screen upgrade for 3D printer |
| 8 | Zero electronique, et ca rembobine tout seul! | 2026-01-23 | 54s | 51,956 | Mechanical auto-rewind (no electronics) |
| 9 | Le mod Jack Rabbit sur mon ERCF | 2026-01-21 | 32s | 36,872 | Multi-color 3D printing mod |
| 10 | La camera la moins chere d'Aliexpress pour mon imprimante 3D | 2026-01-12 | 21s | 36,292 | Cheap AliExpress camera for 3D printer |

### Channel profile

- **Niche**: French maker — PCB design, 3D printing, electronics integration
- **Tools**: KiCad (PCB design), 3D printers (FDM + resin), PCBWay/JLCPCB fabrication
- **Style**: Fast-cut shorts, workshop setting, direct demonstration, French narration with text overlays
- **Breakout**: The "failed PCB" video hit 643K views — relatable maker content
- **Own products**: Sells custom PCB modules via densfactory.com
- **PCB fabrication partner**: PCBWay

---

## Technique Comparison Matrix

| Technique | Complexity | Cost | VFX Needed | Real-Time | Promo Value |
|-----------|-----------|------|------------|-----------|-------------|
| **3D-printed LED shell** (Den's Factory) | Low | ~50-100 EUR | None | Yes | Very High |
| **AR overlay** (After Effects tracking) | Medium | Software license | Yes (per video) | No | Medium |
| **Motion-tracked 2D composite** | Medium-High | Software license | Yes (per video) | No | Medium |
| **Physical robot** (Disney Olaf) | Extreme | 100K+ | None | Yes | Maximum |
| **Runway Gen-3 / AI overlay** | Low | Subscription | Minimal | No | Low-Medium |
| **VTuber avatar** (Live3D, Animaze) | Medium | Free-Low | Live tracking | Yes | Low for promo |

---

## Recommendations for Blue Flame IRL

### Tier 1 — Physical Flame Lamp (IMMEDIATE, ~2-4 weeks)

**Do this first.** It is the highest-impact, lowest-complexity option.

1. **Design a Blue Flame 3D model** — Based on the Blue Flame spec (`features/shikki-blue-flame.md`), create a 3D-printable shell in the `idle` pose. Translucent blue PETG or resin. 8-12cm tall.
2. **Source blue LEDs** — Either modify the Den's Factory module with blue LEDs, or build a simple NeoPixel ring with a custom firmware that runs the Shikki Blue palette (`#4FC3F7` idle, `#29B6F6` working, etc.)
3. **Print and assemble** — The character sits on a desk, plugged into USB, glowing and flickering
4. **Film it** — Zero VFX needed. Put it next to a monitor running Shikki, next to a coffee cup, in a workshop. It IS the Blue Flame in the real world.

**Potential enhancement**: Wire the LED module to a Raspberry Pi Pico W or ESP32 that subscribes to ShikkiKit events over WebSocket. The physical flame changes color in real time as Shikki works. `idle` = gentle blue pulse. `working` = bright fast flicker. `error` = red spike. `success` = green flash. This makes it a REAL-TIME physical dashboard of Shikki's state.

### Tier 2 — AR Composite for Video Content (2-4 weeks, parallel)

For the promo video (`features/shikki-promo-video-v1.md`), some shots need the flame overlaid on real footage:

1. **After Effects motion tracking** — Track a desk surface or screen edge, composite a 2D animated Blue Flame (Lottie/sprite sheet) onto the tracked point
2. **Unreal Engine 5 MetaHuman/Niagara** — For high-fidelity 3D flame with real-time lighting interaction (shadows, reflections on desk surface)
3. **CapCut AR stickers** — Fastest path for social media clips, lower quality but instant

Recommended pipeline: Animate the Blue Flame sprite sheet in Aseprite (pixel art) or After Effects (vector), export as Lottie JSON, composite onto live footage with AE tracking.

### Tier 3 — IoT-Connected Physical Flame (v2, post-launch)

The Den's Factory approach + ShikkiKit EventBus integration:

1. ESP32 microcontroller inside the flame shell
2. Connects to local WiFi, subscribes to ShikkiKit events via WebSocket
3. Maps the 9 emotion states to LED patterns (same `FlameEmotionResolver` logic, ported to C/MicroPython)
4. The physical flame on your desk IS the Blue Flame — same soul, physical form

This becomes the ultimate developer desk companion and the most shareable promotional content possible: "My AI agent has a physical body that reacts to its emotions in real time."

---

## Action Items

| # | Action | Owner | Priority | Depends on |
|---|--------|-------|----------|------------|
| 1 | Source or design a Blue Flame 3D model (idle pose, 8-12cm, translucent blue) | @Daimyo / external 3D artist | P1 | Blue Flame spec |
| 2 | Order Den's Factory Module Effet Flamme 360 (29 EUR) as reference/prototype | @Daimyo | P1 | None |
| 3 | Prototype blue LED strip/ring with NeoPixel + Arduino/Pico (Shikki Blue palette) | @Daimyo | P1 | Item 1 |
| 4 | Design After Effects composite workflow for promo video shots | @Enso | P2 | Promo video storyboard |
| 5 | Spec ESP32 WebSocket client for ShikkiKit EventBus integration | @Sensei | P3 | ShikkiKit EventBus |
| 6 | Research Calcifer-style 3D print files as starting base for Blue Flame model | @Daimyo | P1 | None |

---

## Key Insight

Den's Factory proves the technique works at scale for social media: a 3D-printed character shell with an LED module inside looks magical on camera with zero post-production. The Calcifer lamp is essentially a proof-of-concept for a physical Blue Flame.

The gap between "Calcifer lamp on a shelf" and "Shikki's Blue Flame reacting to your AI agent in real time" is just an ESP32 and a WebSocket connection. The physical form factor already exists in the maker ecosystem. We just need to make it blue and wire it to ShikkiKit.

---

## Sources

- [ZAUEY YouTube Short — Olaf Robot](https://youtube.com/shorts/zi0xi_UwvBU)
- [Den's Factory YouTube Short — Flame Lamp](https://youtube.com/shorts/_8gXy-_kBFY)
- [Den's Factory — Module Effet Flamme 360 Product Page](https://densfactory.com/en-eur/products/module-effet-flamme-360-serie-limitee-precommande)
- [Disney Olaf Robot at NVIDIA GTC](https://disneyexperiences.com/nvidia-gtc-olaf-robotic-character/)
- [Disney Olaf Robot Technical Details](https://wdwnt.com/2026/03/walt-disney-imagineering-shares-how-robotic-olaf-learned-to-walk-on-a-boat-and-more-using-nvidia-technology/)
- [Calcifer 3D Print Models — MakerWorld](https://makerworld.com/en/more-models/calcifer-3d-print-model-download)
- [Calcifer LED Lamp — Printables](https://www.printables.com/model/1315251-calcifer-led-lamp)
- [AI Video Effects Trends 2026](https://aidailyshot.com/blog/best-ai-video-effects-social-media-virality-2026)
- [After Effects Motion Tracking Guide](https://pixflow.net/blog/motion-tracking-in-after-effects/)
