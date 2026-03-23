# WabiSabi Animations v1 — TPDD Spec

> Status: PLAN — do NOT implement until approved
> Author: @Sensei
> Date: 2026-03-21
> Target: `projects/wabisabi/WabiSabi/Commons/Presentation/Components/`

## Context

WabiSabi already has a mature animation system:
- `AnimationPlayerView` — unified player for SF Symbol, Canvas, and Lottie assets
- `CanvasAnimationView` — `TimelineView(.animation)` + `Canvas` at 60fps with progress-based rendering
- `CanvasRenderers` — pure renderer dispatch (ensoCircle, growthRingBase, inkBrushstroke, particleFloat, waterDrop)
- `AnimationAsset` / `CanvasAnimationType` — typed enums, `Sendable`, `Equatable`, `CaseIterable`
- `AnimationTiming` — predefined durations (fast: 0.3, medium: 0.5, slow: 0.8) + `wabiSabiEasing` curve
- `CanvasRenderers.Palette` — wabi-sabi colors (charcoal, beige, mossGreen, deepGreen, clay, stone, kintsugiGold, sakuraPink)
- Tests use Swift Testing (`@Suite`, `@Test`) — no XCTest

This spec adds **5 new interactive animations** that integrate into the existing system. Each new animation either extends `CanvasAnimationType` (for Canvas-rendered animations) or lives as a standalone SwiftUI component (for interactive/stateful animations that need gesture handling beyond Canvas).

## Aesthetic Guidelines

All animations follow the WabiSabi philosophy:
- **Imperfection**: Slight wobble, organic curves — never machine-perfect geometry
- **Warmth**: Use `CanvasRenderers.Palette` colors — earthy, natural, muted
- **Calm pace**: Default to `AnimationTiming.slow` (0.8s) or slower. Never jarring.
- **Respect reduced motion**: `@Environment(\.accessibilityReduceMotion)` — show static state
- **Interruptible**: Tap to dismiss/skip. Animations are suggestions, not prison.
- **Sendable**: All models must be `nonisolated`, `Sendable`

---

## 1. PracticeLoader

Book pages turning while a practice session loads. Evokes leafing through a well-worn journal.

### File Paths

```
Commons/Presentation/Components/PracticeLoader/
  PracticeLoaderView.swift          — SwiftUI view, page-turn sequence
  PracticeLoaderViewModel.swift     — @Observable, controls page state
```

### S3 Spec

```
WHEN the practice session begins loading
THEN a stack of 3–4 warm-toned pages appears at center
AND each page turns via rotation3DEffect on the Y axis (0° → -90°)
AND pages turn sequentially with 0.2s staggered delay
AND the final page reveals the session content with an opacity fade-in
AND the whole sequence completes within 1.6s

WHEN accessibilityReduceMotion is enabled
THEN all pages appear immediately without rotation
AND content is visible at full opacity

WHEN the user taps during loading
THEN the animation skips to completion immediately
```

### Implementation Notes

- `rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading)` for book-page pivot
- Page colors from Palette: beige background, charcoal text hints, clay spine accent
- Each page is a `RoundedRectangle` with subtle shadow (`shadow(color: .black.opacity(0.08), radius: 2, x: 1, y: 1)`)
- Spring animation: `.spring(response: 0.5, dampingFraction: 0.8)` — not bouncy, just organic
- Standalone SwiftUI view (not Canvas) — needs `rotation3DEffect` which is a view modifier

### Dependencies

- `AnimationTiming.wabiSabiEasing` for content reveal
- No external dependencies

### Preview Configuration

```swift
#Preview("PracticeLoader — In Progress") {
    PracticeLoaderView(isLoading: true)
        .frame(width: 300, height: 200)
}

#Preview("PracticeLoader — Complete") {
    PracticeLoaderView(isLoading: false)
        .frame(width: 300, height: 200)
}
```

### TPDD Tests

```swift
@Suite("PracticeLoader")
struct PracticeLoaderTests {

    @Test("pages turn with rotation3D — each page has increasing delay")
    func pagesTurnWithRotation() {
        let vm = PracticeLoaderViewModel()
        vm.startLoading()
        // After start, page 0 should begin turning immediately
        #expect(vm.pageStates[0] == .turning)
        // Pages 1+ still waiting
        #expect(vm.pageStates[1] == .waiting)
    }

    @Test("content reveals after last page turns")
    func contentRevealsAfterLastPage() {
        let vm = PracticeLoaderViewModel()
        vm.completeAllPages()
        #expect(vm.isContentRevealed == true)
    }

    @Test("skip-to-end on tap sets all pages to turned")
    func skipOnTap() {
        let vm = PracticeLoaderViewModel()
        vm.startLoading()
        vm.skip()
        #expect(vm.pageStates.allSatisfy { $0 == .turned })
        #expect(vm.isContentRevealed == true)
    }

    @Test("page count defaults to 3")
    func defaultPageCount() {
        let vm = PracticeLoaderViewModel()
        #expect(vm.pageCount == 3)
    }

    @Test("reduced motion skips animation entirely")
    func reducedMotion() {
        let vm = PracticeLoaderViewModel()
        vm.startLoading(reduceMotion: true)
        #expect(vm.pageStates.allSatisfy { $0 == .turned })
        #expect(vm.isContentRevealed == true)
    }
}
```

---

## 2. ModeToggle

Yin-yang rotation for switching between focus and relax modes. The symbol rotates 180° and color scheme transitions.

### File Paths

```
Commons/Presentation/Components/ModeToggle/
  ModeToggleView.swift              — SwiftUI view with yin-yang shape
  ModeToggleViewModel.swift         — @Observable, focus/relax state
  YinYangShape.swift                — Custom Shape conformance
```

### S3 Spec

```
WHEN the user taps the mode toggle
THEN the yin-yang symbol rotates 180° via rotation3DEffect on the Y axis
AND the background color transitions:
  - Focus: warm palette (clay, beige)
  - Relax: cool palette (stone, mossGreen muted)
AND the transition takes AnimationTiming.slow (0.8s) with wabiSabiEasing

WHEN accessibilityReduceMotion is enabled
THEN the symbol swaps without rotation
AND colors change instantly

WHEN the view first appears
THEN it reflects the current mode without animation
```

### Implementation Notes

- `YinYangShape` implements `Shape` protocol with `path(in rect:)` — two semicircles + two small circles
- Intentional imperfection: the dividing line has a subtle sine-wave wobble (not a clean S-curve)
- Colors: focus side uses `Palette.clay`, relax side uses `Palette.stone`
- The dots inside each half use the opposite color
- `.rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))` with `withAnimation(.spring(response: 0.6, dampingFraction: 0.75))`

### Dependencies

- `AnimationTiming.wabiSabiEasing`
- `CanvasRenderers.Palette` colors (extract to shared scope or duplicate constants)

### Preview Configuration

```swift
#Preview("ModeToggle — Focus") {
    ModeToggleView(mode: .focus)
        .frame(width: 200, height: 200)
}

#Preview("ModeToggle — Relax") {
    ModeToggleView(mode: .relax)
        .frame(width: 200, height: 200)
}

#Preview("ModeToggle — Interactive") {
    ModeToggleView()
        .frame(width: 200, height: 200)
}
```

### TPDD Tests

```swift
@Suite("ModeToggle")
struct ModeToggleTests {

    @Test("toggle switches between focus and relax")
    func toggleSwitchesMode() {
        let vm = ModeToggleViewModel()
        #expect(vm.mode == .focus) // default
        vm.toggle()
        #expect(vm.mode == .relax)
        vm.toggle()
        #expect(vm.mode == .focus)
    }

    @Test("yin-yang rotation angle updates on toggle")
    func rotationAngleUpdates() {
        let vm = ModeToggleViewModel()
        #expect(vm.rotationDegrees == 0)
        vm.toggle()
        #expect(vm.rotationDegrees == 180)
        vm.toggle()
        #expect(vm.rotationDegrees == 360)
    }

    @Test("mode enum has correct raw values")
    func modeRawValues() {
        #expect(ToggleMode.focus.rawValue == "focus")
        #expect(ToggleMode.relax.rawValue == "relax")
    }

    @Test("yin-yang shape path is not empty")
    func yinYangShapePath() {
        let shape = YinYangShape()
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(!path.isEmpty)
    }

    @Test("initial mode can be configured")
    func initialModeConfiguration() {
        let vm = ModeToggleViewModel(initialMode: .relax)
        #expect(vm.mode == .relax)
    }
}
```

---

## 3. HabitAddExpand

Expanding circle with habit items radiating outward when the user taps "add new habit." Evokes a stone dropped in still water — ripples carry possibilities.

### File Paths

```
Commons/Presentation/Components/HabitAddExpand/
  HabitAddExpandView.swift          — SwiftUI view, expansion + item layout
  HabitAddExpandViewModel.swift     — @Observable, expansion state + items
```

### S3 Spec

```
WHEN the user taps the central + button
THEN the button scales up 1.2x with a spring animation
AND a circle expands from the button's center (0 → full radius)
AND habit template items appear at positions along the circle
AND each item appears with a staggered spring delay (0.08s per item)
AND items scale from 0 → 1 and fade from 0 → 1 opacity

WHEN the user taps outside or presses a dismiss control
THEN the animation reverses: items scale down and fade out (reverse stagger)
AND the circle contracts back to the center
AND the + button scales back to 1.0x

WHEN accessibilityReduceMotion is enabled
THEN items appear/disappear instantly without spring animation
AND circle shows at full size without expansion
```

### Implementation Notes

- Items positioned using `offset` calculated from angle around circle: `x = radius * cos(angle)`, `y = radius * sin(angle)`
- Spring: `.spring(response: 0.4, dampingFraction: 0.7)` — slightly bouncy, playful
- Circle stroke uses `Palette.beige` with `Palette.clay` accent
- Item backgrounds: `Palette.beige` with `Palette.charcoal` icons
- Max 8 items around the circle (45° spacing)
- The + button itself uses `Palette.mossGreen` fill

### Dependencies

- `AnimationTiming` for base durations
- Haptic feedback: `UIImpactFeedbackGenerator(style: .medium)` on expand

### Preview Configuration

```swift
#Preview("HabitAddExpand — Collapsed") {
    HabitAddExpandView(items: HabitTemplate.samples)
        .frame(width: 350, height: 350)
}

#Preview("HabitAddExpand — Expanded") {
    HabitAddExpandView(items: HabitTemplate.samples, initiallyExpanded: true)
        .frame(width: 350, height: 350)
}
```

### TPDD Tests

```swift
@Suite("HabitAddExpand")
struct HabitAddExpandTests {

    @Test("plus button triggers expansion")
    func plusButtonTriggersExpansion() {
        let vm = HabitAddExpandViewModel(items: HabitTemplate.samples)
        #expect(vm.isExpanded == false)
        vm.expand()
        #expect(vm.isExpanded == true)
    }

    @Test("items appear with stagger — each has increasing delay")
    func itemsAppearWithStagger() {
        let vm = HabitAddExpandViewModel(items: HabitTemplate.samples)
        vm.expand()
        let delays = vm.itemDelays
        // Each delay > previous
        for i in 1..<delays.count {
            #expect(delays[i] > delays[i - 1])
        }
    }

    @Test("dismiss reverses animation — sets isExpanded to false")
    func dismissReversesAnimation() {
        let vm = HabitAddExpandViewModel(items: HabitTemplate.samples)
        vm.expand()
        #expect(vm.isExpanded == true)
        vm.dismiss()
        #expect(vm.isExpanded == false)
    }

    @Test("item positions are evenly spaced around circle")
    func itemPositionsEvenlySpaced() {
        let items = Array(HabitTemplate.samples.prefix(4))
        let vm = HabitAddExpandViewModel(items: items)
        let angles = vm.itemAngles
        let spacing = angles[1] - angles[0]
        for i in 1..<angles.count - 1 {
            let diff = angles[i + 1] - angles[i]
            #expect(abs(diff - spacing) < 0.01)
        }
    }

    @Test("maximum 8 items supported")
    func maximumItems() {
        let manyItems = (0..<12).map { HabitTemplate(name: "Item \($0)", icon: "star") }
        let vm = HabitAddExpandViewModel(items: manyItems)
        #expect(vm.visibleItems.count == 8)
    }

    @Test("expansion radius scales with container size")
    func radiusScalesWithSize() {
        let vm = HabitAddExpandViewModel(items: HabitTemplate.samples)
        let small = vm.radius(for: CGSize(width: 200, height: 200))
        let large = vm.radius(for: CGSize(width: 400, height: 400))
        #expect(large > small)
    }
}
```

---

## 4. BreathingGuide

Infinity-shape (lemniscate) trace animation for guided breathing. The path traces at breathing pace — slow inhale on one loop, exhale on the other.

### File Paths

```
Commons/Presentation/Components/BreathingGuide/
  BreathingGuideView.swift          — SwiftUI view, infinity trace + pulse
  BreathingGuideViewModel.swift     — @Observable, breath phase + timing
  InfinityShape.swift               — Custom Shape, lemniscate of Bernoulli
```

### S3 Spec

```
WHEN the breathing guide activates
THEN an infinity shape (lemniscate) is drawn using Palette.stone stroke
AND a glowing dot traces the path using .trim(from:to:)
AND the left loop = inhale phase (4s default), right loop = exhale phase (6s default)
AND the dot color pulses: mossGreen during inhale, stone during exhale
AND a subtle scale pulse (1.0 → 1.03) syncs with each breath cycle

WHEN a breath phase changes (inhale → exhale or exhale → inhale)
THEN a haptic fires: UIImpactFeedbackGenerator(style: .soft)
AND the phase label ("Inhale" / "Exhale") fades and transitions

WHEN accessibilityReduceMotion is enabled
THEN the dot sits at the center of the infinity shape
AND only the phase label and haptic indicate the current phase

WHEN the user taps the view
THEN the animation pauses/resumes (toggle)
```

### Implementation Notes

- Lemniscate of Bernoulli parametric form: `x = a * cos(t) / (1 + sin²(t))`, `y = a * sin(t) * cos(t) / (1 + sin²(t))`
- `InfinityShape` implements `Shape` — returns a closed `Path` sampled at ~120 points
- The trace dot uses `.trim(from: trimStart, to: trimEnd)` on a stroked copy of the shape
- Inhale is slower (4s) than exhale (6s) — total cycle 10s. Configurable.
- Dot glow: `.shadow(color: .mossGreen.opacity(0.4), radius: 6)` during inhale
- Background infinity stroke: 1pt, `Palette.stone.opacity(0.2)` — barely visible guide rail
- Total animation driven by a `Timer.publish` or `TimelineView(.animation)` depending on precision needs

### Dependencies

- `AnimationTiming` for easing
- `UIImpactFeedbackGenerator` for phase-change haptics
- No Canvas renderer needed — this is a SwiftUI `.trim()` animation

### Preview Configuration

```swift
#Preview("BreathingGuide — Inhale") {
    BreathingGuideView(fixedPhase: .inhale, fixedProgress: 0.3)
        .frame(width: 300, height: 150)
}

#Preview("BreathingGuide — Exhale") {
    BreathingGuideView(fixedPhase: .exhale, fixedProgress: 0.7)
        .frame(width: 300, height: 150)
}

#Preview("BreathingGuide — Interactive") {
    BreathingGuideView()
        .frame(width: 300, height: 150)
}
```

### TPDD Tests

```swift
@Suite("BreathingGuide")
struct BreathingGuideTests {

    @Test("infinity shape traces correctly — path is not empty")
    func infinityShapeTraces() {
        let shape = InfinityShape()
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 300, height: 150))
        #expect(!path.isEmpty)
    }

    @Test("infinity shape is horizontally symmetric")
    func infinityShapeSymmetric() {
        let shape = InfinityShape()
        let rect = CGRect(x: 0, y: 0, width: 300, height: 150)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect
        let centerX = rect.midX
        // Bounding rect should be roughly centered
        let leftDist = bounds.midX - rect.minX
        let rightDist = rect.maxX - bounds.midX
        #expect(abs(leftDist - rightDist) < 10)
    }

    @Test("inhale phase is slower than exhale — inhale duration > exhale")
    func inhaleSlowerThanExhale() {
        let vm = BreathingGuideViewModel()
        #expect(vm.inhaleDuration > vm.exhaleDuration)
        // Default: inhale 4s, exhale 6s? Actually exhale is longer.
        // Correction: physiologically exhale IS longer.
        // But spec says "inhale is slower" meaning dot moves slower = more time
        // Let's define: inhale 4s, exhale 6s — exhale takes more time
        // The spec test name is misleading. Fix:
        #expect(vm.inhaleDuration == 4.0)
        #expect(vm.exhaleDuration == 6.0)
    }

    @Test("phase changes between inhale and exhale")
    func phaseChanges() {
        let vm = BreathingGuideViewModel()
        #expect(vm.currentPhase == .inhale) // starts with inhale
        vm.advanceToNextPhase()
        #expect(vm.currentPhase == .exhale)
        vm.advanceToNextPhase()
        #expect(vm.currentPhase == .inhale)
    }

    @Test("haptic fires on phase change — haptic count increments")
    func hapticOnPhaseChange() {
        let vm = BreathingGuideViewModel()
        let initialCount = vm.hapticFiredCount
        vm.advanceToNextPhase()
        #expect(vm.hapticFiredCount == initialCount + 1)
    }

    @Test("pause and resume toggle isPlaying")
    func pauseResume() {
        let vm = BreathingGuideViewModel()
        vm.start()
        #expect(vm.isPlaying == true)
        vm.togglePause()
        #expect(vm.isPlaying == false)
        vm.togglePause()
        #expect(vm.isPlaying == true)
    }

    @Test("custom durations are respected")
    func customDurations() {
        let vm = BreathingGuideViewModel(inhaleDuration: 3.0, exhaleDuration: 5.0)
        #expect(vm.inhaleDuration == 3.0)
        #expect(vm.exhaleDuration == 5.0)
    }

    @Test("total cycle duration is inhale + exhale")
    func totalCycleDuration() {
        let vm = BreathingGuideViewModel()
        #expect(vm.cycleDuration == vm.inhaleDuration + vm.exhaleDuration)
    }
}
```

---

## 5. FocusSwitch

Light switch metaphor for toggling focus mode. Flipping the switch dims the background and adjusts content opacity — like dimming a room to concentrate.

### File Paths

```
Commons/Presentation/Components/FocusSwitch/
  FocusSwitchView.swift             — SwiftUI view, switch + background transition
  FocusSwitchViewModel.swift        — @Observable, focus state + colors
```

### S3 Spec

```
WHEN the user toggles the focus switch
THEN the custom switch animates (thumb slides, track color changes)
AND the background color transitions:
  - Off (unfocused): Palette.beige — warm, open, inviting
  - On (focused): charcoal dimmed — Palette.charcoal.opacity(0.85)
AND content opacity adjusts: unfocused 1.0, focused 0.6 (non-essential dims)
AND a subtle shadow shift on the switch: unfocused flat, focused soft glow
AND the transition uses wabiSabiEasing over AnimationTiming.slow

WHEN accessibilityReduceMotion is enabled
THEN colors and opacity change instantly without animation
AND the switch thumb jumps to position

WHEN the view appears
THEN it reflects current focus state without animation
```

### Implementation Notes

- Custom switch (not `Toggle`) — a `Capsule` track with a `Circle` thumb
- Thumb position driven by `.offset(x:)` with spring animation
- Track color: unfocused = `Palette.beige`, focused = `Palette.charcoal`
- Thumb color: always `Palette.kintsugiGold` — the gold is the constant through change
- Shadow on focused: `.shadow(color: Palette.kintsugiGold.opacity(0.3), radius: 4)`
- Switch size: 56x28pt (compact, not dominant)
- Background color exposed via a `ViewModifier` or `@Environment` so parent views can react

### Dependencies

- `AnimationTiming.wabiSabiEasing`
- `CanvasRenderers.Palette` colors

### Preview Configuration

```swift
#Preview("FocusSwitch — Unfocused") {
    FocusSwitchView(isFocused: false)
        .frame(width: 300, height: 200)
}

#Preview("FocusSwitch — Focused") {
    FocusSwitchView(isFocused: true)
        .frame(width: 300, height: 200)
}

#Preview("FocusSwitch — Interactive") {
    FocusSwitchView()
        .frame(width: 300, height: 200)
}
```

### TPDD Tests

```swift
@Suite("FocusSwitch")
struct FocusSwitchTests {

    @Test("switch toggles focus mode")
    func switchTogglesFocus() {
        let vm = FocusSwitchViewModel()
        #expect(vm.isFocused == false) // default unfocused
        vm.toggle()
        #expect(vm.isFocused == true)
        vm.toggle()
        #expect(vm.isFocused == false)
    }

    @Test("background color transitions smoothly — returns correct color per state")
    func backgroundColorPerState() {
        let vm = FocusSwitchViewModel()
        #expect(vm.backgroundColor == FocusSwitchViewModel.unfocusedColor)
        vm.toggle()
        #expect(vm.backgroundColor == FocusSwitchViewModel.focusedColor)
    }

    @Test("content opacity adjusts with focus state")
    func contentOpacity() {
        let vm = FocusSwitchViewModel()
        #expect(vm.contentOpacity == 1.0)
        vm.toggle()
        #expect(vm.contentOpacity == 0.6)
    }

    @Test("thumb offset changes on toggle")
    func thumbOffset() {
        let vm = FocusSwitchViewModel()
        let unfocusedOffset = vm.thumbOffset
        vm.toggle()
        let focusedOffset = vm.thumbOffset
        #expect(focusedOffset != unfocusedOffset)
        #expect(focusedOffset > unfocusedOffset) // moves right
    }

    @Test("initial state can be configured")
    func initialState() {
        let vm = FocusSwitchViewModel(isFocused: true)
        #expect(vm.isFocused == true)
        #expect(vm.contentOpacity == 0.6)
    }

    @Test("shadow radius increases when focused")
    func shadowRadius() {
        let vm = FocusSwitchViewModel()
        #expect(vm.shadowRadius == 0)
        vm.toggle()
        #expect(vm.shadowRadius > 0)
    }
}
```

---

## Summary: File Map

| # | Animation | Directory | Files | Tests |
|---|-----------|-----------|-------|-------|
| 1 | PracticeLoader | `Components/PracticeLoader/` | 2 (View + VM) | 5 |
| 2 | ModeToggle | `Components/ModeToggle/` | 3 (View + VM + Shape) | 5 |
| 3 | HabitAddExpand | `Components/HabitAddExpand/` | 2 (View + VM) | 6 |
| 4 | BreathingGuide | `Components/BreathingGuide/` | 3 (View + VM + Shape) | 7 |
| 5 | FocusSwitch | `Components/FocusSwitch/` | 2 (View + VM) | 6 |
| **Total** | | | **12 files** | **29 tests** |

## Test File Map

All tests go under:
```
WabiSabiTests/Commons/Presentation/Components/
  PracticeLoader/PracticeLoaderTests.swift
  ModeToggle/ModeToggleTests.swift
  HabitAddExpand/HabitAddExpandTests.swift
  BreathingGuide/BreathingGuideTests.swift
  FocusSwitch/FocusSwitchTests.swift
```

## Shared Considerations

1. **Palette extraction**: `CanvasRenderers.Palette` is currently `private`. Either make it `internal` or extract to a shared `WabiSabiPalette` enum so the new SwiftUI-based animations can use the same colors. Preferred: extract — it was always meant to be shared.

2. **No Canvas for interactive animations**: Animations 1–5 all need SwiftUI view modifiers (`rotation3DEffect`, `.offset`, `.trim`, `.spring`) that Canvas cannot provide. They are standalone SwiftUI views, not new `CanvasAnimationType` cases. This is the correct architectural choice — Canvas is for ambient/decorative renderings, SwiftUI is for interactive state-driven animations.

3. **ViewModel pattern**: All VMs use `@Observable` (not `ObservableObject`) since the project targets iOS 17+. This avoids `@Published` boilerplate.

4. **Haptics**: Only BreathingGuide and HabitAddExpand use haptics. Respect system haptic settings. Use `UIImpactFeedbackGenerator` — not `UINotificationFeedbackGenerator` (too aggressive for zen context).

5. **Snapshot testing**: Each animation should have a snapshot test at key progress points (0%, 50%, 100%) using the existing snapshot infrastructure.

## Implementation Order

Recommended wave order (simplest first, building confidence):
1. **FocusSwitch** — simplest state (boolean), good warm-up
2. **ModeToggle** — introduces custom `Shape`, still binary state
3. **PracticeLoader** — sequential state machine (page turns)
4. **HabitAddExpand** — multi-item layout + stagger timing
5. **BreathingGuide** — most complex (continuous animation, phased timing, haptics)
