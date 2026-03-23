# Feature: SUI Test Video API — Video Capture for SwiftUI Tests

> Created: 2026-03-21 | Status: Spec (Phase 4 — Architecture) | Owner: @Daimyo
> Priority: **P1** — visual QA infrastructure
> Package: `packages/MediaKit/` (new SPM package)
> Depends on: CoreKit, AVFoundation, UIKit

---

## Context

Snapshot testing captures static frames. Animations, transitions, E2E navigation flows, and scroll behaviors are invisible in code review. The only way to visually verify them today is TestFlight distribution followed by manual testing and verbal feedback — a cycle measured in days, not seconds.

SwiftUI animations are a first-class citizen of the design language, but the testing infrastructure treats them as second-class. A view that fades in, bounces, or morphs between states produces the same snapshot as one that does nothing. This gap lets animation regressions ship undetected.

Two approaches were evaluated:

- **Approach A (Hybrid)**: Swift Testing for logic + `XCUIScreenRecording` for capture via `XCTestCase` wrappers
- **Approach B (Custom)**: `UIView.drawHierarchy` + `AVAssetWriter`, zero XCTest dependency, pure Swift API

---

## Problem

1. **Animations are invisible in review.** Snapshot tests capture static states. A broken spring animation, a missing fade, or a janky transition passes every test.
2. **E2E visual verification requires manual effort.** There is no automated way to record a navigation flow (launch -> onboarding -> home) and review it as video.
3. **QA feedback is verbal and imprecise.** "The transition feels off" with no artifact to diff against the previous version.
4. **No CI artifact for visual QA.** Swift Testing and Shiki QA produce screenshots but no video. Reviewers see frames, not motion.
5. **Device matrix coverage is static-only.** Snapshot tests vary by device and color scheme, but animation behavior across screen sizes is untested.

---

## Solution

A `SUIVideoRecorder` API that records SwiftUI view animations as .mp4 files, integrated with Swift Testing and the existing snapshot device matrix pattern.

### Core API

```swift
/// Records SwiftUI view hierarchy to video.
/// Sendable — safe to use across actor boundaries.
public final class SUIVideoRecorder: Sendable {

    /// Device configuration (screen size, scale, safe area).
    public let device: SUIDevice

    /// Color scheme applied to the recorded view.
    public let colorScheme: ColorScheme

    /// Frame rate (default 30fps).
    public let frameRate: Int

    public init(
        device: SUIDevice,
        colorScheme: ColorScheme = .light,
        frameRate: Int = 30
    )

    /// Begin recording. Installs a display link to capture frames.
    public func start(view: some View) async throws

    /// Stop recording and write the video file.
    /// Returns the URL of the written .mp4 file.
    public func stop(output: URL) async throws -> URL

    /// Convenience: record for a fixed duration.
    public func record(
        view: some View,
        duration: Duration,
        output: URL
    ) async throws -> URL
}
```

### Device Matrix

```swift
/// Same pattern as snapshot tests — reuse existing SUIDevice definitions.
public enum SUIDevice: String, CaseIterable, Sendable {
    case iPhone16 = "iPhone 16"
    case iPhoneSE = "iPhone SE"
    case iPadPro13 = "iPad Pro 13"
    // extensible
}
```

### Integration with Swift Testing

```swift
@Test("Card flip animation renders smoothly", .tags(.visual))
func cardFlipAnimation() async throws {
    let recorder = SUIVideoRecorder(device: .iPhone16, colorScheme: .dark)
    try await recorder.start(view: CardView(flipped: false))

    // Trigger animation
    await CardView.flip()
    try await Task.sleep(for: .seconds(1))

    let url = try await recorder.stop(output: .videoArtifact(named: "card-flip"))
    #expect(FileManager.default.fileExists(atPath: url.path()))
}
```

### Matrix Runner

```swift
/// Run a video recording across all device/colorScheme combinations.
public func recordMatrix(
    devices: [SUIDevice] = SUIDevice.allCases,
    colorSchemes: [ColorScheme] = [.light, .dark],
    outputDir: URL,
    body: (SUIVideoRecorder) async throws -> Void
) async throws -> [URL]
```

---

## Business Rules

BR-01: Video recording MUST work in both interactive and headless (CI) simulator modes. The recorder detects the environment and selects the appropriate capture backend (offscreen rendering for headless, display link for interactive).

BR-02: Output format is .mp4 with H.264 encoding. No proprietary container formats. Files must be playable by QuickTime, VLC, and web browsers without transcoding.

BR-03: Device/colorScheme matrix follows the same pattern as snapshot tests. `SUIDevice` defines screen dimensions, scale factor, and safe area insets. Tests enumerate combinations with `recordMatrix`.

BR-04: Video files are stored in `__Videos__/` alongside the test target, mirroring the `__Snapshots__/` convention.

BR-05: Each video file is named `{TestName}-{device}-{colorScheme}.mp4`. Example: `cardFlipAnimation-iPhone16-dark.mp4`. Names are sanitized (spaces replaced with hyphens, lowercased).

BR-06: Duration is controlled by explicit `start()`/`stop()` calls, not by a timer. The caller decides when to stop. The convenience `record(duration:)` method is sugar, not the primary API.

BR-07: Default frame rate is 30fps. Configurable via `SUIVideoRecorder(frameRate:)`. Valid range: 1-60. Values outside range clamp to nearest bound.

BR-08: `SUIVideoRecorder` MUST be `Sendable` (Swift 6 strict concurrency). Internal state is protected by an actor or lock — no data races under concurrent access.

BR-09: The recording API itself has zero dependency on XCTest or XCUITest. It is a standalone library in MediaKit. Test framework integration (Swift Testing helpers, `XCTestCase` extensions) lives in a separate target: `MediaKitTesting`.

BR-10: Integration with Shiki QA: video artifacts are registered in the test report alongside snapshot artifacts. `SUIVideoRecorder` emits a `VideoArtifact` event that the QA pipeline can consume.

BR-11: Maximum recording duration is 120 seconds. Recordings exceeding this limit are automatically stopped with a warning logged. Configurable via `maxDuration` parameter.

BR-12: If `stop()` is called without a prior `start()`, it throws `RecorderError.notRecording`. If `start()` is called while already recording, it throws `RecorderError.alreadyRecording`. No silent state corruption.

BR-13: Failed recordings (simulator crash, disk full, encoding error) MUST clean up partial .mp4 files. No orphaned artifacts in `__Videos__/`.

BR-14: CI mode must not require a GPU. Offscreen rendering via `UIGraphicsImageRenderer` + software compositing. Slower than interactive mode but deterministic.

---

## Architecture

### Approach A — Hybrid (XCUIScreenRecording)

```
Swift Testing (@Test)
    └── XCTestCase wrapper (thin bridge)
          └── XCUIScreenRecording.start()/.stop()
                └── .mp4 output
```

**Pros:**
- Battle-tested Apple API, handles simulator rendering edge cases
- Captures everything the simulator displays (Metal, Core Animation, UIKit)
- Minimal engineering effort for the recording engine itself

**Cons:**
- Tied to XCTest lifecycle — cannot use directly in Swift Testing `@Test` functions
- Apple-locked: API surface may break between Xcode versions without warning
- Cannot customize frame rate, resolution, or encoding parameters
- Requires a running XCUIApplication — heavyweight for unit-level view tests
- Violates BR-09 (no XCTest dependency in recording API)

### Approach B — Custom (UIView.drawHierarchy + AVAssetWriter)

```
SUIVideoRecorder
    ├── UIHostingController(rootView: view)
    │     └── UIView.drawHierarchy(in:afterScreenUpdates:)
    │           └── CGImage per frame
    └── AVAssetWriter + AVAssetWriterInputPixelBufferAdaptor
          └── H.264 .mp4 output
```

**Pros:**
- Zero Apple test framework dependency — pure UIKit + AVFoundation
- Works with any test runner (Swift Testing, XCTest, standalone)
- Full control over frame rate, resolution, encoding quality, pixel format
- Portable: same API works in app code, test code, preview tooling
- Aligns with "own your tools" philosophy — no black-box dependency

**Cons:**
- `UIView.drawHierarchy` may miss some Core Animation layer effects and Metal-rendered content
- CADisplayLink timing in headless mode requires offscreen fallback
- More engineering effort (~800 LOC vs ~200 LOC for Approach A)
- Must handle pixel buffer management, frame timing, encoder lifecycle manually

### Recommendation: Approach B (Custom)

Approach B satisfies all business rules. Approach A violates BR-09 and limits CI usability. The engineering cost is higher but the result is a tool we fully control — no Xcode version roulette, no XCTest coupling, no Apple-locked API surface.

The `UIView.drawHierarchy` gap (missing Metal/CA effects) is acceptable: SwiftUI animations that matter for visual QA (opacity, scale, offset, rotation, matched geometry) are all captured. Metal-heavy custom renderers are out of scope for v1.

### Package Structure

```
packages/MediaKit/
  Package.swift
  Sources/
    MediaKit/
      ├── SUIVideoRecorder.swift       ← core recorder (actor-protected state)
      ├── SUIDevice.swift              ← device definitions (dimensions, scale, safe area)
      ├── FrameCapture.swift           ← UIHostingController + drawHierarchy loop
      ├── VideoWriter.swift            ← AVAssetWriter + pixel buffer adaptor
      ├── VideoArtifact.swift          ← output metadata (path, device, colorScheme, duration)
      ├── RecorderError.swift          ← typed errors
      └── RecorderConfiguration.swift  ← frame rate, max duration, output format
    MediaKitTesting/
      ├── VideoMatrixRunner.swift      ← recordMatrix() across devices/schemes
      ├── URL+VideoArtifact.swift      ← .videoArtifact(named:) convenience
      └── SwiftTestingIntegration.swift ← @Test helpers, artifact registration
  Tests/
    MediaKitTests/
      ├── SUIVideoRecorderTests.swift
      ├── FrameCaptureTests.swift
      ├── VideoWriterTests.swift
      ├── SUIDeviceTests.swift
      └── VideoMatrixRunnerTests.swift
```

### SPM Dependency Graph

```
CoreKit (foundation)
  ↑
MediaKit (video recording engine — UIKit, AVFoundation)
  ↑
MediaKitTesting (test helpers — depends on MediaKit, Swift Testing)
```

MediaKit has no dependency on ShikiKit, ShikiCore, or XCTest. It is a general-purpose video capture library that happens to be designed for test workflows.

---

## @shi Team Challenge

### @Sensei (Architecture)

1. **CI performance**: Each video recording runs a UIHostingController + AVAssetWriter. On CI (Mac Mini, no GPU), expect ~2x realtime for 30fps capture. A 5-second animation takes ~10 seconds to record. With a 6-device matrix, that is ~60 seconds per test. **Mitigation**: parallelize across devices using Swift concurrency (each recorder is independent). Budget 2 parallel recordings per CI core.

2. **Memory pressure**: Each frame is a `CVPixelBuffer` (~8MB at 3x retina). At 30fps, 60 seconds = 1800 frames. Do NOT buffer all frames — write each frame to the AVAssetWriter immediately and release the pixel buffer. Peak memory should be ~50MB regardless of duration.

3. **Package placement**: MediaKit is correct as a standalone package. It should NOT live inside ShikiCore — video recording is orthogonal to the lifecycle engine. If WabiSabi or Maya need video capture in non-test contexts (e.g., onboarding recording), MediaKit serves both.

### @Hanami (Developer UX)

1. **API surface is minimal**: 3 methods (`start`, `stop`, `record`), 1 configuration object, 1 matrix helper. A developer writes their first video test in <5 minutes by copying the example.

2. **Discoverability**: `URL.videoArtifact(named:)` mirrors the snapshot pattern developers already know. No new mental model — just "snapshot but video."

3. **Failure messages must be actionable**: `RecorderError.notRecording` should say "Called stop() without start(). Did you forget to await start(view:)?", not a raw state machine error.

### @Kintsugi (Philosophy)

1. **"Own your tools" alignment**: Approach B builds on UIKit + AVFoundation — Apple frameworks we must use anyway, but no Apple _test_ framework dependency. The recording engine is ours. This is the correct trade-off: use the platform, own the tooling.

2. **Artifact durability**: .mp4 files are universally playable, not tied to any Apple viewer or Xcode version. A video recorded today plays in 10 years. This matters for release archaeology.

3. **The gap is honest**: We cannot capture Metal content. Rather than wrapping XCUIScreenRecording to hide this limitation, we document it. Honest tools build trust.

### @Ronin (Adversarial)

1. **Simulator memory**: iOS simulators on CI have limited memory. Recording a complex view hierarchy (100+ subviews) at 3x scale could OOM the simulator. **Mitigation**: configurable scale factor (default 2x in CI, 3x interactive). Add a memory watchdog that stops recording at 80% memory pressure.

2. **CI timeout risk**: A stuck `drawHierarchy` call (view not laid out, hosting controller not in window) could hang indefinitely. **Mitigation**: per-frame timeout of 1 second. If a frame takes longer than 1s, drop it and log a warning. If 3 consecutive frames timeout, abort the recording.

3. **Disk space**: A 60-second video at 30fps, 1080p, H.264 is ~15MB. A full matrix (3 devices x 2 schemes = 6 files) is ~90MB per test. 20 video tests = 1.8GB. **Mitigation**: CI cleanup step deletes `__Videos__/` between runs. Configurable retention policy. Compression quality parameter (default: medium, ~8MB/60s).

4. **Flaky frame timing**: CADisplayLink in headless mode fires inconsistently. **Mitigation**: in headless/CI mode, do NOT use CADisplayLink. Use a manual timer (`Task.sleep(for: .milliseconds(33))`) and capture synchronously. Deterministic but ~10% slower.

5. **What breaks when Apple changes UIHostingController internals?** The `drawHierarchy` API has been stable since iOS 7. UIHostingController has been stable since iOS 13. Lower risk than XCUIScreenRecording which changes with every Xcode version. But: add a `FrameCapture` protocol so the backend is swappable if Apple breaks something.

---

## Test Plan

### Unit Tests — SUIVideoRecorder

```
BR-01 → test_recorder_headlessMode_capturesFrames()
BR-01 → test_recorder_interactiveMode_capturesFrames()
BR-02 → test_recorder_outputFormat_isMP4H264()
BR-06 → test_recorder_startStop_controlsDuration()
BR-06 → test_recorder_convenienceRecord_stopsAfterDuration()
BR-07 → test_recorder_defaultFrameRate_is30fps()
BR-07 → test_recorder_customFrameRate_respected()
BR-07 → test_recorder_frameRateClamps_toValidRange()
BR-08 → test_recorder_isSendable_compiles()
BR-11 → test_recorder_maxDuration_stopsAutomatically()
BR-12 → test_recorder_stopWithoutStart_throws()
BR-12 → test_recorder_doubleStart_throws()
BR-13 → test_recorder_failedRecording_cleansUpPartialFile()
```

### Unit Tests — VideoWriter

```
BR-02 → test_videoWriter_writesValidMP4()
BR-02 → test_videoWriter_h264Codec_inOutputFile()
BR-07 → test_videoWriter_respectsFrameRate()
BR-13 → test_videoWriter_diskFull_cleansUp()
```

### Unit Tests — FrameCapture

```
BR-01 → test_frameCapture_offscreen_producesPixelBuffers()
BR-14 → test_frameCapture_noGPU_usesSoftwareRenderer()
```

### Unit Tests — Device Matrix

```
BR-03 → test_deviceMatrix_generatesAllCombinations()
BR-03 → test_deviceMatrix_3devices2schemes_produces6files()
BR-05 → test_videoNaming_matchesConvention()
BR-05 → test_videoNaming_sanitizesSpaces()
BR-04 → test_videoOutput_goesToVideosDirectory()
```

### Unit Tests — SUIDevice

```
BR-03 → test_iPhone16_hasCorrectDimensions()
BR-03 → test_iPhoneSE_hasCorrectDimensions()
BR-03 → test_iPadPro13_hasCorrectDimensions()
```

### Integration Tests

```
test_roundTrip_recordAndPlayback_validVideo()
test_matrixRunner_producesAllExpectedFiles()
test_largeAnimation_60seconds_noOOM()
test_concurrentRecordings_doNotInterfere()
test_ciMode_noGPU_producesIdenticalOutput()
```

### Manual Validation

```
- [ ] Record a SwiftUI animation in Xcode test runner, verify .mp4 plays in QuickTime
- [ ] Run video test on CI (GitHub Actions macOS runner), verify artifact uploaded
- [ ] Compare same animation across 3 devices — visual consistency check
- [ ] Dark mode recording renders correctly (no white flash, correct backgrounds)
```

---

## Implementation Waves

### Wave 1: Core Engine (~500 LOC, ~15 tests)

| File | Purpose | Tests |
|------|---------|-------|
| Package.swift | SPM manifest, depends on CoreKit | -- |
| SUIDevice.swift | Device definitions with dimensions, scale, safe area | 3 |
| RecorderConfiguration.swift | Frame rate, max duration, scale factor, output format | 2 |
| RecorderError.swift | Typed error enum | -- |
| FrameCapture.swift | Protocol + UIHostingController/drawHierarchy impl | 3 |
| VideoWriter.swift | AVAssetWriter + pixel buffer adaptor | 4 |
| SUIVideoRecorder.swift | Public API, actor-protected state machine | 3 |

**Deliverable**: `SUIVideoRecorder` can record a single SwiftUI view to .mp4 on a simulator.

### Wave 2: Device Matrix + Naming (~300 LOC, ~10 tests)

| File | Purpose | Tests |
|------|---------|-------|
| VideoArtifact.swift | Output metadata (path, device, scheme, duration) | 2 |
| VideoMatrixRunner.swift | recordMatrix() across devices/schemes | 4 |
| URL+VideoArtifact.swift | .videoArtifact(named:) convenience | 2 |
| Naming logic in SUIVideoRecorder | `{TestName}-{device}-{colorScheme}.mp4` | 2 |

**Deliverable**: `recordMatrix()` produces correctly-named .mp4 files in `__Videos__/` for all device/scheme combinations.

### Wave 3: CI + Headless Mode (~200 LOC, ~8 tests)

| File | Purpose | Tests |
|------|---------|-------|
| OffscreenFrameCapture.swift | Software-only frame capture (no CADisplayLink) | 3 |
| Environment detection | Auto-select capture backend by environment | 2 |
| Memory watchdog | Stop recording at memory pressure threshold | 2 |
| Per-frame timeout | Drop frames exceeding 1s capture time | 1 |

**Deliverable**: Video tests pass on CI macOS runners without GPU. Memory-safe for long recordings.

### Wave 4: Swift Testing Integration (~150 LOC, ~5 tests)

| File | Purpose | Tests |
|------|---------|-------|
| SwiftTestingIntegration.swift | @Test helpers, .tags(.visual) convention | 2 |
| Artifact registration | Hook into test report for Shiki QA consumption | 2 |
| Documentation + examples | Usage guide in package README | 1 |

**Deliverable**: Developers write video tests with `@Test` and artifacts appear in Shiki QA review pipeline.

### Totals

- ~1,150 LOC across 4 waves
- ~38 tests (unit + integration)
- Estimated effort: 3-4 focused sessions

---

## Review History

| Date | Reviewer | Status | Notes |
|------|----------|--------|-------|
| 2026-03-21 | @Daimyo | Spec drafted | Initial spec with both approaches evaluated. Approach B selected. |
| -- | @shi team | Pending | Awaiting team challenge review. |
