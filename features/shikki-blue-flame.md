# Feature: Shikki Blue Flame — The Living Soul of Shikki

> **Type**: `/spec` — visual identity + interactive mascot
> **Priority**: P1 — brand foundation, DX delight, cross-platform identity
> **Status**: Spec (validated by @Daimyo, 2026-03-28)
> **Owner**: @Daimyo
> **Depends on**: ShikkiCore (event bus), ShikkiKit (ShikkiEvent), TUI layer
> **Roadmap**: v1 CLI ASCII → v2 macOS widget → v3 iOS/web

---

## Vision

Shikki needs a face. Not a logo — a soul.

The Blue Flame is Shikki's personification: a pure flame with manga/anime eyes,
no body, no limbs. It lives inside every interface Shikki touches. It flickers
when thinking, blazes when building, dims when sleeping, goes red when something
breaks. It reacts to real events — not decoratively, but as a direct emotional
mirror of the system's state.

This is not a mascot bolted onto marketing. The flame IS Shikki. Every ShikkiEvent
maps to an emotion. Every platform gets the flame at the right fidelity. The same
soul, expressed through ASCII on a tmux status bar or full animation in an iOS
widget.

Inspirations:
- **Dead Cells** (prisoner flame head) — the flame as the entire character
- **Ember Knight** — fluid fire movement, weight and personality without a body
- **Sol** (Guilty Gear) — fire as identity, not decoration
- **Notchi** (macOS notch companion) — reactive to system state, lives in ambient UI
- **GitHub Octocat, Go Gopher, Docker Whale** — mascots that become as recognizable
  as the product itself

---

## Phase 1 — Brainstorm Table

| # | Agent | Idea | Layer | Priority |
|---|-------|------|-------|----------|
| 1 | @Hanami | **Silhouette grammar**: The flame's outline IS the emotion. Narrow + tall = focused. Wide + round = happy. Spiky + jagged = angry. Even at 16px (tmux), silhouette alone communicates mood before eyes render. | Design | P0 |
| 2 | @Hanami | **Eye vocabulary at scale**: Four eye states cover 90% of emotions — open (neutral), narrowed (focus/suspicion), sparkle (delight), closed (sleep/pain). At 16px: single Unicode char. At 32px: 2x2 pixel pair. At 128px: full manga pupils + catchlights. Each eye state must be recognizable at EVERY size. | Design | P0 |
| 3 | @Hanami | **Animation timing taxonomy**: Idle = 2000ms cycle (imperceptible, just alive). Working = 400ms cycle (active but not frantic). Transition = 120ms flash then settle (emotion change is sharp, not gradual — like a person's face reacting). Error = 80ms spike then 600ms hold (alarm then sustained concern). Celebrations = 300ms burst × 3 then return to idle. | Design | P0 |
| 4 | @Kintsugi | **Fire as creation and destruction**: The same flame that lights the way also burns the bad code away. Shikki's flame is not safe or gentle — it's honest. When it goes red for an error, that's not failure — that's the flame refusing to lie. The Blue Flame is truth itself: it shows you what's actually happening, always. | Philosophy | P1 |
| 5 | @Kintsugi | **Wabi-sabi of imperfect frames**: The ASCII flame should NOT be perfectly symmetrical. Real fire is asymmetric. The pixel art should have intentional irregularity — a slightly lopsided flicker, an eye that blinks a frame late. Imperfection IS personality. The flame that's too perfect feels like a loading spinner, not a being. | Philosophy | P1 |
| 6 | @Enso | **Blue flame as ownable color**: The blue flame is rare — most fire iconography uses orange/red. This makes Shikki's flame immediately distinctive in any context. The specific blue: `#4FC3F7` (electric blue, calm clarity) → `#1E88E5` (deep focus) → `#B3E5FC` (pale dawn, sleeping). This is Shikki Blue — not a generic "tech blue" but a precise hue that reads as "controlled, intelligent fire." | Brand | P0 |
| 7 | @Enso | **The flame as a continuous identity thread**: The same character appears on the CLI status bar, the macOS menu bar, the iOS app icon, the shikki.dev landing page, and eventually in the iOS native app chat. Users see the flame in the terminal at 8am, on their phone at lunch, in the browser at 5pm. The flame becomes Pavlovian — seeing it means "Shikki is here, Shikki is working." This is how mascots become icons. | Brand | P1 |
| 8 | @Sensei | **Terminal rendering stack**: Three tiers based on capability detection. Tier 1 (universal): Unicode braille + block characters — works in any terminal, tmux, SSH. Tier 2 (sixel/kitty): actual 32px pixel art rendered inline using Kitty Graphics Protocol or libsixel — iTerm2, Kitty, WezTerm. Tier 3 (TUI pane): dedicated 20-column flame pane with full ASCII art + frame animation at 10fps. Capability auto-detected via `$TERM_PROGRAM`, `$COLORTERM`, and `tput tigetstr`. | Technical | P0 |
| 9 | @Sensei | **Event-to-emotion mapping via ShikkiKernel**: The flame subscribes to the ShikkiKit EventBus. `FlameEmotionResolver` is a pure function: `(EventType, EventScope) → FlameEmotion`. The resolver lives in `ShikkiKit/Renderers/FlameEmotionResolver.swift`. Every ShikkiEvent has a defined emotion mapping. Unknown events default to `idle`. This keeps the flame honest — it can only show emotions that real events triggered. | Technical | P0 |
| 10 | @Shogun | **The dev tool mascot gap**: GitHub has the Octocat. Docker has the Whale. Go has the Gopher. Rust has Ferris. Every beloved dev tool has a mascot. AI coding tools in 2026 have ZERO recognizable mascots — they all use logos (circles, geometric shapes, initials). Shikki's Blue Flame has a first-mover advantage in the AI dev tool space. A well-executed flame mascot is more shareable than any product screenshot. | Market | P1 |

---

## Phase 2 — Feature Brief

### Problem

Shikki is invisible. It runs commands, emits events, processes code — but it has no
face. Users stare at logs and progress bars with no emotional connection to what's
happening. When an error occurs, the terminal prints red text. When a build succeeds,
the terminal prints green text. There's no moment of delight, no sense that something
alive just did something for you.

This also means Shikki has no brand presence. The CLI is just text. The future macOS
app and iOS app have no visual identity anchor. Without a mascot, Shikki is a tool.
With the Blue Flame, Shikki becomes a companion.

### Solution

A flame character that:
1. Lives in the terminal (tmux status bar, dedicated TUI pane, inline in output)
2. Subscribes to the ShikkiKit EventBus and resolves events to emotions in real time
3. Renders at 3 fidelity tiers based on terminal capability
4. Expands to macOS menu bar (v2) and iOS widget/app icon (v3)
5. Has a consistent visual identity: Shikki Blue, anime eyes, silhouette-driven emotion

### Scope by Version

#### v1 — CLI ASCII (this spec)

- `FlameRenderer` protocol with three concrete renderers:
  - `BrailleFlameRenderer` — Unicode braille art, works everywhere
  - `SixelFlameRenderer` — pixel art via sixel/Kitty protocol
  - `PaneFlameRenderer` — dedicated 20-col TUI pane with animation
- `FlameEmotionResolver` — EventType → FlameEmotion mapping
- Integration points:
  - tmux status bar (8-char slot): Unicode flame glyph + color
  - `/board` dashboard: full flame pane (right column)
  - Progress bars: flame reacts to % complete
  - Claude Code thinking bar: flame flickers during LLM calls
  - Error output: flame goes red BEFORE the error text prints
  - Ship pipeline: flame shows each gate's emotion as it passes
- Emotion set: `idle`, `working`, `thinking`, `success`, `error`, `waiting`,
  `angry`, `receiving`
- Colorblind-safe: every emotion has both color AND shape/motion signal

#### v2 — macOS Menu Bar Widget

- SwiftUI `NSStatusItem` with animated `Canvas` view
- 18×18pt flame icon in menu bar — reacts to ShikkiKit events via local IPC
- Click to open mini popover: last 3 events + current emotion label
- Dark/light mode aware: blue deepens in dark mode, lightens in light mode
- Menubar icon states: colored flame glyph (9 states)

#### v3 — iOS App Mascot + Web

- iOS: `FlameView` (SwiftUI) — reusable view component
  - App icon: flame at rest (blue, centered)
  - Notification avatar: emotion-matched flame
  - Widget: animated flame + current session status
  - In-app: large flame in dashboard header, small flame in nav bar
- Web (shikki.dev):
  - Lottie JSON exported from pixel art keyframes
  - Hero animation on landing page: flame awakening from sleep to working
  - Inline SVG for static contexts (docs, README badges)
  - `<flame-widget>` web component for embedding

---

## Phase 3 — Business Requirements

### BR-1: Emotion States

The flame MUST support exactly 9 emotion states. Each state is a complete visual
description (shape, color, eyes, motion, accessory).

| State | Trigger | Shape | Color | Eyes | Motion | Accessory |
|-------|---------|-------|-------|------|--------|-----------|
| `idle` | No active events, session quiet | Small, round, symmetric | `#4FC3F7` (Shikki Blue) | Half-open, droopy | Slow 2s flicker, gentle sway | None |
| `sleeping` | Session end, long inactivity (>15min) | Very small, collapsed | `#1A237E` (deep dim) | Closed, Zs trail | Almost no movement, 4s micro-pulse | `z z z` bubble |
| `working` | Agent dispatched, build running, test executing | Tall, elongated, reaching upward | `#29B6F6` (bright electric blue) | Wide open, focused, determined | Fast 400ms flicker, upward lick | None |
| `thinking` | LLM call in progress, decision pending | Medium, symmetric with sparkle tips | `#81D4FA` (sparkle blue) with `#E1F5FE` tips | Looking up-left, pupils raised | 600ms cycle, sparkle particles float up | `...` trail |
| `success` | shipGatePassed, testRun pass, buildResult success | Wide, full, exuberant | Flash `#66BB6A` (success green), settle to blue | Happy crescents, star catchlights | 300ms burst expansion × 3 then settle | Star/confetti particles |
| `error` | buildResult fail, shipGateFailed, any `.error` event | Spiky, jagged edges, inverted cone | `#EF5350` (alarm red) | Wide, worried, brows furrowed | 80ms sharp spike, 600ms jagged hold | `!` bubble |
| `waiting` | decisionPending, user input required | Gentle pulsing oval, patient | `#4FC3F7` → `#29B6F6` pulse | Soft, patient, slight head-tilt | 1.2s gentle pulse in/out | `...` thought bubble, slow blink |
| `angry` | budgetExhausted, companyStale, repeated failures | Sharp, aggressive, forward-leaning | `#FF7043` (warning orange-red) | Sharp diagonal, angry brows, steam lines | 200ms intense rapid flicker, forward lean | Steam wisps |
| `receiving` | notificationActioned, human event, input arriving | Leans toward source, curious tilt | `#4FC3F7` with `#E3F2FD` leading edge | Wide curious, one raised "eyebrow" line | Leans 15° toward input source, 300ms hold | None |

**BR-1.1**: Every state change MUST complete within one animation cycle before the
new emotion takes over. No abrupt cuts — there is always a 120ms transition frame.

**BR-1.2**: The `sleeping` state MUST only activate after 15 continuous minutes with
no ShikkiEvents. It should NOT activate during a long-running silent task.

**BR-1.3**: The `success` state MUST return to `idle` (not stay on success) after
exactly 3 celebration cycles (900ms total).

---

### BR-2: Color System

The flame uses a precisely defined color vocabulary. These are NOT generic colors —
they are named Shikki palette entries.

| Name | Hex | Usage | Colorblind-safe signal |
|------|-----|-------|----------------------|
| Shikki Blue | `#4FC3F7` | Default idle flame, brand color | Blue — distinct from all error/warning colors |
| Deep Blue | `#29B6F6` | Active working state | Same hue family, darker — readable as "more intense" |
| Dim Blue | `#1A237E` | Sleeping state | Near-black blue — clearly dormant |
| Pale Blue | `#B3E5FC` | Thinking sparkle tips | Light blue — reads as "uncertain, searching" |
| Success Green | `#66BB6A` | Success flash only | Green + star shape — shape carries signal for deuteranopes |
| Error Red | `#EF5350` | Error state | Red + spike shape — shape carries signal for protanopes |
| Warning Orange | `#FF7043` | Angry state | Orange — between red and amber, clearly alarmed |
| White | `#FFFFFF` | Eye catchlights, sparkle particles | Shape-only signal |

**BR-2.1**: EVERY color-coded emotion MUST have a corresponding shape/motion signal
that communicates the same meaning WITHOUT color. Colorblind users must never miss
an emotion purely because they can't distinguish hues.

**BR-2.2**: The colorblind shape signals are:
- `success`: star particles + expanding shape (not just green)
- `error`: spike edges + `!` accessory (not just red)
- `angry`: forward-lean silhouette + steam (not just orange)
- `thinking`: upward-drifting particles + eyes-up (not just pale blue)

**BR-2.3**: In terminal contexts where true color is unavailable (256-color or 8-color
terminals), the renderer MUST fall back to ANSI color approximations:
- Shikki Blue → `\e[94m` (bright blue)
- Error Red → `\e[91m` (bright red)
- Success Green → `\e[92m` (bright green)
- Sleeping → `\e[34m` (dark blue)

---

### BR-3: Animation Timing

All timing values are defined as constants. Renderers MUST use these values — no
hardcoded magic numbers.

```swift
public enum FlameAnimationTiming {
    /// Base flicker cycle for idle state (ms)
    public static let idleCycle: Int = 2000
    /// Base flicker cycle for working state (ms)
    public static let workingCycle: Int = 400
    /// Base flicker cycle for thinking state (ms)
    public static let thinkingCycle: Int = 600
    /// Sharp spike on error entry (ms)
    public static let errorSpike: Int = 80
    /// Hold duration after error spike (ms)
    public static let errorHold: Int = 600
    /// Success burst duration per cycle (ms)
    public static let successBurst: Int = 300
    /// Number of success burst cycles before returning to idle
    public static let successBurstCount: Int = 3
    /// Emotion transition crossfade (ms)
    public static let transitionCrossfade: Int = 120
    /// Waiting state pulse period (ms)
    public static let waitingPulse: Int = 1200
    /// Receiving lean hold duration (ms)
    public static let receivingLean: Int = 300
    /// Inactivity threshold before sleeping (s)
    public static let sleepThreshold: TimeInterval = 900 // 15 minutes
}
```

**BR-3.1**: In terminal contexts, animation MUST be implemented as async frame
sequences. The renderer MUST respect `$NO_COLOR` and `$TERM=dumb` — in these
environments, output a single static glyph with no ANSI escapes.

**BR-3.2**: Animation frame rate MUST NOT exceed 10fps in terminal renderers to
avoid excessive stdout writes. The `PaneFlameRenderer` targets exactly 10fps
(100ms frame interval).

**BR-3.3**: All animation loops MUST be cancellable via Swift structured concurrency
(`Task.cancel()`). No infinite loops without cooperative cancellation checks.

---

### BR-4: Platform Rules

#### BR-4.1: Terminal Capability Detection

The `FlameRendererFactory` detects capability tier at runtime:

```
Priority 1 (best): Kitty Graphics Protocol
  → Detected by: $TERM == "xterm-kitty" OR kitty +icat --detect-support
  → Renderer: SixelFlameRenderer (pixel art mode)

Priority 2: Sixel
  → Detected by: tput -T$TERM cols ≥ 1 && infocmp | grep sixel
  → Renderer: SixelFlameRenderer (sixel mode)

Priority 3: 24-bit true color terminal
  → Detected by: $COLORTERM == "truecolor" OR $COLORTERM == "24bit"
  → Renderer: BrailleFlameRenderer (Unicode, full RGB)

Priority 4: 256-color
  → Detected by: $TERM contains "256color"
  → Renderer: BrailleFlameRenderer (Unicode, 256-color palette)

Priority 5 (fallback): 8-color / dumb terminal
  → Renderer: GlyphFlameRenderer (single emoji/char + ANSI 8-color)
```

#### BR-4.2: tmux Status Bar Integration

The flame occupies an 8-character slot in the tmux status bar (right side):

```
#[fg=colour81]🔥#[fg=colour255] IDLE   ← sleeping: dim blue
#[fg=colour39]🔥#[fg=colour255] WORK   ← working: bright blue
#[fg=colour196]🔥#[fg=colour255] ERR!   ← error: red
#[fg=colour46]🔥#[fg=colour255] DONE   ← success: green
```

The `shikki flame status` subcommand outputs a tmux-formatted status string.
Configured in `~/.config/shikki/tmux.conf`:
```
set -g status-right "#(shikki flame status)"
set -g status-interval 2
```

#### BR-4.3: TUI Pane Dimensions

The `PaneFlameRenderer` renders into a 20×24 character pane.

Flame art frames are stored as `[String]` arrays (each string = one row) in
`ShikkiKit/Resources/Flames/`. Frame files use naming convention:
`flame_<emotion>_<frame_index>.txt`

The pane renderer cycles through frames at 10fps using `AsyncStream`.

#### BR-4.4: macOS Menu Bar (v2)

- Icon size: 18×18pt @2x = 36×36px PNG
- Uses `NSStatusItem` with `NSImage` that swaps per emotion state
- IPC: subscribes to a local UNIX domain socket (`/tmp/shikki-flame.sock`)
  where ShikkiCore pushes emotion change events
- MUST NOT use polling — only event-driven updates

#### BR-4.5: iOS (v3)

- `FlameView: View` is a pure SwiftUI composable
- Uses `Canvas` API for flame drawing (no UIKit dependencies)
- Animation: SwiftUI `withAnimation(.easeInOut(duration:))` matching timing constants
- Widget: `WidgetKit` extension reads emotion from App Group shared `UserDefaults`
- App icon: static blue flame at `idle` state — NO animation (App Store rules)

---

### BR-5: Event-to-Emotion Mapping

`FlameEmotionResolver` is the authoritative mapping. It is a pure function with
no side effects, fully testable.

```swift
public enum FlameEmotion: String, CaseIterable, Sendable {
    case idle, sleeping, working, thinking, success, error, waiting, angry, receiving
}

public struct FlameEmotionResolver {
    public static func resolve(_ event: ShikkiEvent) -> FlameEmotion {
        switch event.type {
        // Active work
        case .codeGenStarted, .codeGenAgentDispatched,
             .shipGateStarted, .testRun, .buildResult:
            return .working

        // LLM / AI thinking
        case .codeGenSpecParsed, .codeGenContractVerified,
             .codeGenPlanCreated, .prRiskAssessed:
            return .thinking

        // Success
        case .shipGatePassed, .shipCompleted, .codeGenPipelineCompleted,
             .codeGenMergeCompleted, .codeGenAgentCompleted, .prVerdictSet:
            return resolveSuccess(event)

        // Failure / Error
        case .shipGateFailed, .codeGenPipelineFailed, .shipAborted:
            return .error

        // Waiting for human
        case .decisionPending:
            return .waiting

        // Human responds / input arrives
        case .decisionAnswered, .decisionUnblocked,
             .notificationActioned, .prFixSpawned:
            return .receiving

        // Orchestration problems
        case .budgetExhausted, .companyStale:
            return .angry

        // Lifecycle end
        case .sessionEnd:
            return .sleeping

        // Lifecycle start
        case .sessionStart, .sessionTransition:
            return .working

        // Heartbeat / quiet
        case .heartbeat, .contextCompaction:
            return .idle

        // PR cache building (background work)
        case .prCacheBuilt:
            return .thinking

        // Notifications sent (not yet actioned)
        case .notificationSent:
            return .waiting

        // Ship started
        case .shipStarted:
            return .working

        // Company dispatched (agents going)
        case .companyDispatched, .companyRelaunched:
            return .working

        // Code changes
        case .codeChange:
            return .working

        // Fix agents working
        case .codeGenFixStarted, .prFixCompleted,
             .codeGenFixCompleted:
            return .thinking

        // CodeGen merge in progress
        case .codeGenMergeStarted:
            return .working

        // Unknown
        case .custom:
            return .idle
        }
    }

    // buildResult can be pass or fail — check payload
    private static func resolveSuccess(_ event: ShikkiEvent) -> FlameEmotion {
        if case .bool(let passed) = event.payload["passed"], !passed {
            return .error
        }
        return .success
    }
}
```

**BR-5.1**: Unknown or unmapped EventTypes MUST resolve to `.idle`, never to
an error or crash.

**BR-5.2**: The resolver MUST be called on every EventBus emission. The flame
state MUST update within one animation cycle (max 400ms) of the event.

**BR-5.3**: Emotion priority (when multiple events arrive simultaneously):
`error` > `angry` > `waiting` > `success` > `working` > `thinking` > `receiving` > `idle` > `sleeping`

---

### BR-6: ASCII Art Specification

#### Braille Flame (20-char wide, 12 lines tall)

The braille flame uses Unicode braille block characters (`U+2800`–`U+28FF`) for
dense pixel simulation. Each frame is 20 braille chars × 12 lines = effective
80×48 pixel resolution.

**Idle frame 0 (reference):**
```
        ⢀⣤⡀
      ⢀⣾⣿⣿⣷⡀
     ⣼⣿⡿⢿⣿⣿⣧
    ⢸⣿⣿⠁ ⠈⣿⣿⡇
    ⣿⣿⣿⡄ ⢠⣿⣿⣿
    ⣿⣿⣿⡇ ⢸⣿⣿⣿
    ⢸⣿⣿⡇ ⢸⣿⣿⡇
     ⠻⣿⣷⣶⣾⣿⠟
        ⠉⠙⠋
```

**Eyes (embedded at rows 4–5):**
- Idle: `⠶` (half-open, two dots wide)
- Working: `◉ ◉` (full open)
- Thinking: `◝ ◜` (looking up)
- Success: `◡ ◡` (happy crescents)
- Error: `◈ ◈` (wide alarmed)
- Sleeping: `— —` (closed lines)
- Waiting: `◎ ◎` (patient, full open)
- Angry: `◤ ◥` (sharp diagonal brows)
- Receiving: `◉ ◎` (one wide, curious tilt)

#### Glyph Flame (tmux / fallback, 1-char)

Single Unicode character + ANSI color per emotion:

```
Idle:      🔵  (or \e[94m▲\e[0m in 8-color)
Working:   🔥  (or \e[96m▲\e[0m)
Thinking:  ✨  (or \e[94m▲\e[0m)
Success:   💚  (or \e[92m★\e[0m)
Error:     ❗  (or \e[91m▲\e[0m)
Waiting:   💤  (or \e[34m▲\e[0m)
Sleeping:  😴  (or \e[34m▽\e[0m)
Angry:     🔴  (or \e[91m▲\e[0m)
Receiving: 👁️  (or \e[96m▶\e[0m)
```

---

### BR-7: Accessibility

**BR-7.1**: All emotion states MUST communicate meaning through at least TWO of:
shape, motion, color, accessory text. No state relies on color alone.

**BR-7.2**: The `$NO_COLOR` environment variable MUST be respected. When set,
all ANSI color codes are suppressed. The flame renders in terminal default color
with shape/glyph signals only.

**BR-7.3**: Motion (`$REDUCE_MOTION` support): When `SHIKKI_REDUCE_MOTION=1` is
set, all animation is replaced with static frames. The correct emotion frame
(frame 0) is shown without cycling.

**BR-7.4**: Screen reader / accessibility mode: When `TERM=dumb` or stdout is
not a TTY, the renderer outputs plain text labels instead of art:
```
[SHIKKI: working]
[SHIKKI: error — buildResult failed]
[SHIKKI: success — shipCompleted]
```

**BR-7.5**: The `shikki flame describe` subcommand outputs a natural language
description of the current emotion for screen reader integration.

---

### BR-8: Architecture

```
ShikkiKit/
  Sources/ShikkiKit/
    ├── Renderers/
    │   ├── FlameEmotion.swift              ← enum + priority ordering
    │   ├── FlameEmotionResolver.swift      ← EventType → FlameEmotion (pure function)
    │   ├── FlameAnimationTiming.swift      ← timing constants
    │   ├── FlameRendererProtocol.swift     ← protocol: render(emotion:) async
    │   ├── BrailleFlameRenderer.swift      ← Unicode braille art renderer
    │   ├── SixelFlameRenderer.swift        ← sixel / Kitty pixel art renderer
    │   ├── PaneFlameRenderer.swift         ← full TUI pane renderer (10fps)
    │   ├── GlyphFlameRenderer.swift        ← single char fallback
    │   └── FlameRendererFactory.swift      ← capability detection → renderer
    ├── Resources/
    │   └── Flames/
    │       ├── flame_idle_0.txt            ← ASCII frame files
    │       ├── flame_idle_1.txt
    │       ├── flame_working_0.txt
    │       └── ... (9 emotions × 4 frames = 36 files)
```

**Integration with EventBus:**

```swift
// In ShikkiCore / ShikkaCommand startup:
let flameRenderer = FlameRendererFactory.make()
Task {
    for await event in EventBus.shared.stream {
        let emotion = FlameEmotionResolver.resolve(event)
        await flameRenderer.transition(to: emotion)
    }
}
```

**CLI subcommand:**

```
shikki flame               → start animated flame in pane mode
shikki flame status        → tmux status string (8-char)
shikki flame describe      → natural language current state
shikki flame demo          → cycle through all 9 emotions (for testing)
shikki flame --emotion=<e> → force a specific emotion (dev/debug)
```

---

## Phase 4 — Test Plan

### T-1: Emotion State Transition Tests

**T-1.1** — All 9 states render without error:
```swift
@Test func allEmotionStatesRender() async throws {
    let renderer = BrailleFlameRenderer()
    for emotion in FlameEmotion.allCases {
        let frame = try await renderer.currentFrame(for: emotion)
        #expect(!frame.isEmpty)
        #expect(frame.contains(where: { !$0.isEmpty }))
    }
}
```

**T-1.2** — Transition crossfade completes within timing budget:
```swift
@Test func emotionTransitionCompletesWithinBudget() async throws {
    let renderer = BrailleFlameRenderer()
    let start = Date()
    await renderer.transition(to: .working)
    await renderer.transition(to: .error)
    let elapsed = Date().timeIntervalSince(start) * 1000
    #expect(elapsed < Double(FlameAnimationTiming.transitionCrossfade) + 50)
}
```

**T-1.3** — Priority ordering: error beats working when simultaneous:
```swift
@Test func emotionPriorityOrderingRespected() {
    #expect(FlameEmotion.error.priority > FlameEmotion.working.priority)
    #expect(FlameEmotion.angry.priority > FlameEmotion.waiting.priority)
    #expect(FlameEmotion.sleeping.priority < FlameEmotion.idle.priority)
}
```

**T-1.4** — Success returns to idle after 3 cycles:
```swift
@Test func successReturnToIdleAfterCycles() async throws {
    let renderer = MockFlameRenderer()
    await renderer.transition(to: .success)
    // Wait for 3 cycles + buffer
    try await Task.sleep(nanoseconds: UInt64(
        (FlameAnimationTiming.successBurst * FlameAnimationTiming.successBurstCount + 100)
        * 1_000_000
    ))
    #expect(renderer.currentEmotion == .idle)
}
```

**T-1.5** — Sleep threshold: sleeping only after 15 minutes inactivity:
```swift
@Test func sleepingRequires15MinuteInactivity() {
    // Inject 14min59s without events → should NOT be sleeping
    // Inject 15min+ without events → should be sleeping
}
```

---

### T-2: Event-to-Emotion Mapping Tests

**T-2.1** — All EventType variants resolve without crash:
```swift
@Test func allEventTypesResolveToEmotion() {
    let knownTypes: [EventType] = [
        .sessionStart, .sessionEnd, .heartbeat, .companyDispatched,
        .decisionPending, .decisionAnswered, .buildResult,
        .shipGatePassed, .shipGateFailed, .shipCompleted
        // ... all cases
    ]
    for eventType in knownTypes {
        let event = ShikkiEvent(
            source: .system, type: eventType, scope: .global
        )
        let emotion = FlameEmotionResolver.resolve(event)
        #expect(FlameEmotion.allCases.contains(emotion))
    }
}
```

**T-2.2** — Critical mappings are correct:
```swift
@Test func criticalEventMappings() {
    let cases: [(EventType, FlameEmotion)] = [
        (.decisionPending, .waiting),
        (.budgetExhausted, .angry),
        (.shipGateFailed, .error),
        (.shipCompleted, .success),
        (.sessionEnd, .sleeping),
        (.heartbeat, .idle),
    ]
    for (eventType, expectedEmotion) in cases {
        let event = ShikkiEvent(source: .system, type: eventType, scope: .global)
        #expect(FlameEmotionResolver.resolve(event) == expectedEmotion)
    }
}
```

**T-2.3** — buildResult with `passed: false` resolves to error:
```swift
@Test func buildResultFailureResolvesToError() {
    let failEvent = ShikkiEvent(
        source: .process(name: "xcodebuild"),
        type: .buildResult,
        scope: .project(slug: "shikki"),
        payload: ["passed": .bool(false)]
    )
    #expect(FlameEmotionResolver.resolve(failEvent) == .error)
}
```

**T-2.4** — Unknown `.custom` events resolve to idle (not crash):
```swift
@Test func customEventResolvesToIdle() {
    let event = ShikkiEvent(
        source: .system, type: .custom("unknown_future_event"), scope: .global
    )
    #expect(FlameEmotionResolver.resolve(event) == .idle)
}
```

---

### T-3: Renderer Size and Fidelity Tests

**T-3.1** — BrailleFlameRenderer output fits in 20×12:
```swift
@Test func brailleRendererFitsIn20x12() async throws {
    let renderer = BrailleFlameRenderer()
    for emotion in FlameEmotion.allCases {
        let frame = try await renderer.currentFrame(for: emotion)
        for row in frame {
            #expect(row.unicodeScalars.count <= 20)
        }
        #expect(frame.count <= 12)
    }
}
```

**T-3.2** — GlyphFlameRenderer outputs exactly 1 character (no ANSI when NO_COLOR):
```swift
@Test func glyphRendererRespectsNoColor() async throws {
    setenv("NO_COLOR", "1", 1)
    defer { unsetenv("NO_COLOR") }
    let renderer = GlyphFlameRenderer()
    let output = try await renderer.render(emotion: .error)
    // Should contain no ANSI escape sequences
    #expect(!output.contains("\u{1B}["))
}
```

**T-3.3** — FlameRendererFactory returns GlyphFlameRenderer for dumb terminal:
```swift
@Test func factoryReturnsFallbackForDumbTerminal() {
    let renderer = FlameRendererFactory.make(termOverride: "dumb")
    #expect(renderer is GlyphFlameRenderer)
}
```

---

### T-4: Color Accuracy Tests

**T-4.1** — Correct ANSI color codes per emotion in 256-color mode:
```swift
@Test func ansiColorCodesMatchSpec() async throws {
    let renderer = BrailleFlameRenderer(colorMode: .ansi256)
    let workingOutput = try await renderer.render(emotion: .working)
    #expect(workingOutput.contains("\u{1B}[96m")) // bright cyan (working blue approx)
    let errorOutput = try await renderer.render(emotion: .error)
    #expect(errorOutput.contains("\u{1B}[91m")) // bright red
}
```

**T-4.2** — True color output uses exact Shikki Blue hex:
```swift
@Test func trueColorUsesShikkiBlue() async throws {
    let renderer = BrailleFlameRenderer(colorMode: .trueColor)
    let idleOutput = try await renderer.render(emotion: .idle)
    // Shikki Blue #4FC3F7 = RGB(79, 195, 247)
    #expect(idleOutput.contains("\u{1B}[38;2;79;195;247m"))
}
```

---

### T-5: Accessibility Tests

**T-5.1** — NO_COLOR suppresses all ANSI codes:
```swift
@Test func noColorSuppressesAllAnsi() async throws {
    setenv("NO_COLOR", "1", 1)
    defer { unsetenv("NO_COLOR") }
    let renderer = BrailleFlameRenderer()
    for emotion in FlameEmotion.allCases {
        let output = try await renderer.render(emotion: emotion)
        #expect(!output.contains("\u{1B}"))
    }
}
```

**T-5.2** — Dumb terminal outputs plain text labels:
```swift
@Test func dumbTerminalOutputsPlainTextLabel() async throws {
    let renderer = GlyphFlameRenderer(mode: .plainText)
    let output = try await renderer.render(emotion: .error)
    #expect(output.contains("[SHIKKI: error"))
}
```

**T-5.3** — SHIKKI_REDUCE_MOTION shows single static frame:
```swift
@Test func reducedMotionShowsSingleFrame() async throws {
    setenv("SHIKKI_REDUCE_MOTION", "1", 1)
    defer { unsetenv("SHIKKI_REDUCE_MOTION") }
    let renderer = PaneFlameRenderer()
    let frames = try await renderer.captureFrames(emotion: .working, duration: 1.0)
    // All frames should be identical when reduce motion is set
    let first = frames.first!
    #expect(frames.allSatisfy { $0 == first })
}
```

---

### T-6: `shikki flame demo` Integration Test

**T-6.1** — Demo cycles through all 9 emotions without hanging:
```swift
@Test func demoCompletesAllEmotions() async throws {
    let demo = FlameDemoRunner()
    let emitted = try await withTimeout(seconds: 30) {
        await demo.runAll()
    }
    #expect(emitted.count == FlameEmotion.allCases.count)
    #expect(Set(emitted) == Set(FlameEmotion.allCases))
}
```

---

## Open Questions

1. **Pixel art source files**: Who creates the 36 reference frames (9 emotions × 4 frames)?
   Option A: @Daimyo hand-crafts ASCII art frames.
   Option B: Commission pixel artist for sprite sheet, then convert to ASCII/sixel.
   Option C: Procedurally generated from shape grammar (BR-1 silhouette rules).
   _Recommendation: Start with Option A for v1 (pure ASCII), Option B for v2/v3._

2. **sixel vs Kitty Graphics Protocol**: sixel has broader terminal support (iTerm2,
   WezTerm, foot). Kitty protocol is faster and cleaner but requires Kitty terminal.
   Decision: implement both, capability-detect at runtime.

3. **Flame in notifications**: For iOS push notifications (v3), the flame image needs
   to be server-side rendered or pre-baked per emotion. Proposed: 9 static PNGs
   (one per emotion) bundled in the iOS app + notification service extension swaps
   based on payload `emotion` key.

4. **Web component packaging**: `<flame-widget>` for shikki.dev — standalone JS bundle
   with Lottie player, or pure CSS animation? Decision deferred to v3.

5. **Animated app icon on iOS**: App Store does NOT allow animated app icons via
   standard submission. Possible via iOS 18 "animated icons" API — monitor for v3.

---

## Deliverables

| # | Deliverable | Version | Owner |
|---|-------------|---------|-------|
| D-1 | `FlameEmotion.swift` + `FlameAnimationTiming.swift` | v1 | @Sensei |
| D-2 | `FlameEmotionResolver.swift` (pure function, 100% coverage) | v1 | @Sensei |
| D-3 | `GlyphFlameRenderer.swift` (tmux status bar) | v1 | @Sensei |
| D-4 | `BrailleFlameRenderer.swift` (Unicode art, 20×12) | v1 | @Sensei |
| D-5 | 36 ASCII frame files in `Resources/Flames/` | v1 | @Daimyo |
| D-6 | `PaneFlameRenderer.swift` (10fps TUI pane) | v1 | @Sensei |
| D-7 | `FlameRendererFactory.swift` (capability detection) | v1 | @Sensei |
| D-8 | `shikki flame` subcommand (status, describe, demo, force) | v1 | @Sensei |
| D-9 | EventBus integration in ShikkiCore startup | v1 | @Sensei |
| D-10 | Full test suite (T-1 through T-6, ≥40 tests) | v1 | @Metsuke |
| D-11 | macOS NSStatusItem menu bar widget | v2 | @Sensei |
| D-12 | SwiftUI `FlameView` + iOS widget | v3 | @Hanami + @Sensei |
| D-13 | Lottie JSON export + web component | v3 | @Enso |

---

> _"The flame that tends your code is the same flame that burns the bad code away.
> It does not lie. It shows you what's happening — always."_
> — @Kintsugi

---

*Spec written: 2026-03-28 | Branch: integration/shikki-v0.3.0-pre*
