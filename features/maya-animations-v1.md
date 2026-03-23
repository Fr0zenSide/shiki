# Maya Animations v1 — TPDD Spec

> Status: PLAN — tests first, implementation by /autopilot
> Date: 2026-03-21
> Scope: 5 reusable animation components for MayaFit

## Architecture Context

**Base path**: `projects/Maya/MayaFit/Core/Abstracts/Presentation/DesignSystem/Components/Commons/`
**Test path**: `projects/Maya/MayaFitTests/Components/Animations/`
**Color system**: `Extensions+Color.swift` — semantic tokens (`.first`, `.second`, `.success`, `.error`)
**Existing patterns**: `LikeView`, `HeartView` (forever animation), `DoubleCircularProgressView` (`.trim()` + `.stroke()`), `InstaGradientRingView` (gradient ring)
**Convention**: `public struct` + `public init` + `PreviewProvider` (legacy pattern, project uses iOS 16+)

---

## 1. AsyncActionButton

**File**: `AsyncActionButton.swift`
**Purpose**: Submit morph — rect to circle to spinner to checkmark. For any async action (save workout, sync data, submit challenge).

### State Machine

```
idle ──[action()]──▶ loading ──[onComplete(.success)]──▶ success ──[0.8s]──▶ idle
                         │
                         └──[onComplete(.failure)]──▶ idle (shake)
```

### S3 Spec

```
When the button is in idle state
Then it displays the text label with full-width rounded rect

When the user taps the button
Then the rect morphs to a circle with spring animation
And the text fades out
And a trim spinner appears rotating continuously

When the async action succeeds
Then the spinner fades out
And a checkmark scales in with spring(response: 0.4, dampingFraction: 0.6)
And after 0.8 seconds it morphs back to idle

When the async action fails
Then the button shakes horizontally (3 oscillations, 6pt amplitude)
And returns to idle state
```

### Implementation Notes

- State: `enum ButtonPhase: Equatable { case idle, loading, success }`
- Shape morph: animate `cornerRadius` from 12 to height/2 + `frame(width:)` from full to height
- Spinner: `Circle().trim(from: 0, to: 0.7).rotationEffect()` with `Animation.linear(duration: 0.8).repeatForever(autoreverses: false)`
- Checkmark: `Image(systemName: "checkmark")` with `.scaleEffect` + `.transition(.scale.combined(with: .opacity))`
- Accept `action: () async throws -> Void` as init parameter
- Colors: `.first` background in idle, `.success` background on success

### Dependencies

- `Extensions+Color.swift` (`.first`, `.success`)
- No external dependencies

### Preview

```swift
#Preview("AsyncActionButton — All States") {
    VStack(spacing: 24) {
        AsyncActionButton(label: "Save Workout") {
            try await Task.sleep(for: .seconds(2))
        }
        AsyncActionButton(label: "Sync Data") {
            try await Task.sleep(for: .seconds(1))
            throw CancellationError()
        }
    }
    .padding()
}
```

---

## 2. WorkoutCompletionCelebration

**File**: `WorkoutCompletionCelebration.swift`
**Purpose**: Multi-phase celebration overlay for workout completion, PR achieved.

### S3 Spec

```
When the celebration triggers
Then the content shrinks to 0.8 scale with spring

When the shrink completes
Then it bounces to 1.1 scale with spring(response: 0.3, dampingFraction: 0.5)

When the bounce peaks
Then particle burst emits 12 particles in radial distribution
And particles have randomized offsets (distance: 40-100pt, angle: 0-360)
And each particle is a random SF Symbol from ["star.fill", "heart.fill", "flame.fill"]

When 2 seconds elapse after burst
Then all particles fade to opacity 0 with easeOut(duration: 0.6)
And content returns to scale 1.0
```

### Implementation Notes

- Pattern: extend the `LikeView`/`HeartView` approach — overlay modifier, not a standalone view
- API: `.workoutCelebration(isPresented: Binding<Bool>)`  ViewModifier
- Particles: `ForEach(0..<12)` with randomized `.offset(x:y:)` + `.opacity` + `.rotationEffect`
- Phase sequencing: use `Task` + `withAnimation` blocks, or `PhaseAnimator` if targeting iOS 17+
- Colors: particles use `.first`, `.second`, `.pink`

### Dependencies

- `LikeView.swift` (pattern reference only, no code dependency)
- SF Symbols 4+

### Preview

```swift
#Preview("WorkoutCompletionCelebration") {
    Text("Workout Complete!")
        .font(.title)
        .workoutCelebration(isPresented: .constant(true))
}
```

---

## 3. ProgressWaveFill

**File**: `ProgressWaveFill.swift`
**Purpose**: Sine wave progress fill for calories, hydration, daily goal trackers.

### S3 Spec

```
When progress is 0.0
Then the view shows an empty container with no fill

When progress is 1.0
Then the view is fully filled

When progress is between 0.0 and 1.0
Then the fill level reflects the progress value
And a sine wave animates at the fill boundary
And the wave offset animates continuously (linear, 2s period)

When the progress value changes
Then the fill level animates to the new value with easeInOut(duration: 0.6)
```

### Implementation Notes

- Custom `Shape` conforming to `Animatable` for wave path
- `animatableData`: wave offset (continuous) — use `TimelineView(.animation)` or `withAnimation(.linear(duration: 2).repeatForever(autoreverses: false))`
- Wave function: `sin((x / wavelength) + offset) * amplitude` where amplitude = 8pt, wavelength = width / 2
- Fill: `Rectangle` clipped by wave shape, `progress` drives vertical position
- Gradient: `LinearGradient` from `.first` (bottom) to `.second` (top) inside fill

### Dependencies

- `Extensions+Color.swift` (`.first`, `.second`)

### Preview

```swift
#Preview("ProgressWaveFill") {
    VStack(spacing: 20) {
        ProgressWaveFill(progress: 0.0)
            .frame(width: 80, height: 120)
        ProgressWaveFill(progress: 0.5)
            .frame(width: 80, height: 120)
        ProgressWaveFill(progress: 1.0)
            .frame(width: 80, height: 120)
    }
}
```

---

## 4. SyncIndicator

**File**: `SyncIndicator.swift`
**Purpose**: Circle trim loader for GPS acquisition, data sync, HealthKit fetch.

### S3 Spec

```
When state is syncing
Then a circle trim(from: 0, to: 0.7) rotates continuously
And rotation uses linear(duration: 0.8).repeatForever(autoreverses: false)

When state transitions to connected
Then rotation stops
And the circle pulses (scale 1.0 -> 1.2 -> 1.0) once with spring
And color transitions to .success

When state is idle
Then the indicator is hidden with opacity transition
```

### Implementation Notes

- State: `enum SyncPhase { case idle, syncing, connected }`
- Builds on `DoubleCircularProgressView` trim pattern but simplified (single circle, thinner stroke)
- Stroke: `lineWidth: 3`, `.round` lineCap
- Colors: `.second` during syncing, `.success` on connected
- Accessibility: set `.accessibilityLabel("Syncing")` / `"Connected"` per state

### Dependencies

- `Extensions+Color.swift` (`.second`, `.success`)
- Pattern reference: `DoubleCircularProgressView.swift`

### Preview

```swift
#Preview("SyncIndicator — States") {
    HStack(spacing: 32) {
        SyncIndicator(phase: .syncing)
            .frame(width: 32, height: 32)
        SyncIndicator(phase: .connected)
            .frame(width: 32, height: 32)
        SyncIndicator(phase: .idle)
            .frame(width: 32, height: 32)
    }
}
```

---

## 5. StreakMilestone

**File**: `StreakMilestone.swift`
**Purpose**: Infinity loop celebration for streak achievements (7-day, 30-day, 100-day).

### S3 Spec

```
When the milestone triggers
Then an infinity shape draws itself using trim(from: 0, to:) animating 0 to 1
And the draw animation uses easeInOut(duration: 1.2)

When the infinity shape completes drawing
Then 8 particles burst from the loop intersection point
And particles fade after 1.5 seconds

When the counter is visible
Then the streak count displays centered in the infinity loop
And the count uses a monospacedDigit font
```

### Implementation Notes

- Custom `InfinityShape: Shape` — parametric figure-eight path using `addCurve(to:control1:control2:)`
- `.trim(from: 0, to: drawProgress)` animated from 0 to 1
- Stroke: `lineWidth: 4`, `.round` lineCap, color `.first`
- Particles: same pattern as `WorkoutCompletionCelebration` but 8 particles, smaller radius (30-60pt)
- Counter: `Text("\(streakCount)")` with `.font(.system(.title2, design: .rounded).monospacedDigit())`

### Dependencies

- `Extensions+Color.swift` (`.first`)
- Reuse particle logic from `WorkoutCompletionCelebration` (extract shared `ParticleBurst` if both land)

### Preview

```swift
#Preview("StreakMilestone") {
    VStack(spacing: 32) {
        StreakMilestone(streakCount: 7, isPresented: .constant(true))
            .frame(width: 120, height: 60)
        StreakMilestone(streakCount: 30, isPresented: .constant(true))
            .frame(width: 120, height: 60)
        StreakMilestone(streakCount: 100, isPresented: .constant(true))
            .frame(width: 120, height: 60)
    }
}
```

---

## TPDD Test Signatures

All tests use Swift Testing (`import Testing`). Test file per component.

### `AsyncActionButtonTests.swift`

```swift
import Testing
@testable import MayaFit

@Suite("AsyncActionButton")
struct AsyncActionButtonTests {

    @Test("idle state shows text label")
    func idleStateShowsTextLabel() { }

    @Test("loading state shows spinner")
    func loadingStateShowsSpinner() { }

    @Test("success state shows checkmark")
    func successStateShowsCheckmark() { }

    @Test("state transitions follow idle-loading-success-idle sequence")
    func stateTransitionsFollowSequence() { }

    @Test("failure returns to idle with shake")
    func failureReturnsToIdleWithShake() { }

    @Test("button is disabled during loading")
    func buttonIsDisabledDuringLoading() { }
}
```

### `WorkoutCompletionCelebrationTests.swift`

```swift
import Testing
@testable import MayaFit

@Suite("WorkoutCompletionCelebration")
struct WorkoutCompletionCelebrationTests {

    @Test("celebration triggers particle burst with 12 particles")
    func celebrationTriggersParticleBurst() { }

    @Test("particles fade to zero opacity after 2 seconds")
    func particlesFadeAfterTwoSeconds() { }

    @Test("celebration resets isPresented to false on completion")
    func celebrationResetsOnCompletion() { }

    @Test("scale sequence follows shrink-bounce-settle pattern")
    func scaleSequenceFollowsPattern() { }
}
```

### `ProgressWaveFillTests.swift`

```swift
import Testing
@testable import MayaFit

@Suite("ProgressWaveFill")
struct ProgressWaveFillTests {

    @Test("progress 0 shows empty container")
    func progressZeroShowsEmpty() { }

    @Test("progress 1 shows full fill")
    func progressOneShowsFull() { }

    @Test("wave animates continuously when visible")
    func waveAnimatesContinuously() { }

    @Test("progress clamps to 0...1 range")
    func progressClampsToRange() { }

    @Test("wave shape path generates valid sine curve")
    func waveShapePathGeneratesValidSineCurve() { }
}
```

### `SyncIndicatorTests.swift`

```swift
import Testing
@testable import MayaFit

@Suite("SyncIndicator")
struct SyncIndicatorTests {

    @Test("syncing state shows rotating trim circle")
    func syncingStateShowsRotatingTrim() { }

    @Test("connected state pulses once then settles")
    func connectedStatePulses() { }

    @Test("idle state hides indicator")
    func idleStateHidesIndicator() { }

    @Test("accessibility labels match sync phase")
    func accessibilityLabelsMatchPhase() { }
}
```

### `StreakMilestoneTests.swift`

```swift
import Testing
@testable import MayaFit

@Suite("StreakMilestone")
struct StreakMilestoneTests {

    @Test("infinity shape draws correctly with valid path")
    func infinityShapeDrawsCorrectly() { }

    @Test("counter displays streak count in center")
    func counterDisplaysStreakCount() { }

    @Test("trim animates from 0 to 1 on presentation")
    func trimAnimatesOnPresentation() { }

    @Test("particles burst on draw completion")
    func particlesBurstOnDrawCompletion() { }
}
```

---

## File Manifest

| # | Component | Source File | Test File |
|---|-----------|-------------|-----------|
| 1 | AsyncActionButton | `Commons/AsyncActionButton.swift` | `Animations/AsyncActionButtonTests.swift` |
| 2 | WorkoutCompletionCelebration | `Commons/WorkoutCompletionCelebration.swift` | `Animations/WorkoutCompletionCelebrationTests.swift` |
| 3 | ProgressWaveFill | `Commons/ProgressWaveFill.swift` | `Animations/ProgressWaveFillTests.swift` |
| 4 | SyncIndicator | `Commons/SyncIndicator.swift` | `Animations/SyncIndicatorTests.swift` |
| 5 | StreakMilestone | `Commons/StreakMilestone.swift` | `Animations/StreakMilestoneTests.swift` |

**Total**: 5 source files, 5 test files, 23 test cases

## Shared Extraction (conditional)

If both `WorkoutCompletionCelebration` and `StreakMilestone` land in the same PR, extract:
- `ParticleBurstModifier.swift` — shared particle burst ViewModifier
- Parameters: `particleCount`, `symbols`, `radiusRange`, `fadeDuration`

## Implementation Order

1. **AsyncActionButton** — most broadly useful, no dependencies on other new components
2. **SyncIndicator** — small scope, builds on existing `DoubleCircularProgressView` pattern
3. **ProgressWaveFill** — requires custom `Shape` + `Animatable`, medium complexity
4. **WorkoutCompletionCelebration** — particle system, may share with #5
5. **StreakMilestone** — custom `InfinityShape` + particles, highest complexity

## Notes for /autopilot

- Write tests FIRST (TPDD). The test signatures above are the contract.
- Use `@MainActor` on all view-related test suites.
- For snapshot testing, use `swift-snapshot-testing` (already in Maya's dependencies).
- Follow existing Maya conventions: `public struct`, `public init`, `PreviewProvider`.
- All animations must respect `UIAccessibility.isReduceMotionEnabled` — fall back to instant transitions.
- Target iOS 16+ (no `PhaseAnimator` unless we bump to iOS 17).
