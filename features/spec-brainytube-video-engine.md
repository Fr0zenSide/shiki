# BrainyTube Video Engine v2 — Implementation Spec

> **Author**: @Sensei
> **Date**: 2026-03-23
> **Status**: Ready for review
> **Target**: BrainyTube macOS app (`projects/brainy/Sources/BrainyTube/`)
> **Platform**: macOS 14+ (Sonoma), Swift 6.0, SwiftUI

---

## Problem Statement

Three production bugs and two feature gaps block daily usability:

1. **Pixelized video in grid mode** — 9 live `AVPlayer` instances competing for GPU decode bandwidth. VP9 codec streams that AVPlayer cannot hardware-decode on macOS (VP9 is software-only for third-party apps). Combined result: pixelated mush at any grid size beyond 1x1.
2. **Arrow keys broken in focused grid** — Menu-level `.keyboardShortcut(.rightArrow)` fires `seekForward` globally, but `GridPlayerView` expanded overlay never receives it. The `NotificationCenter` bridge only wires `SinglePlayerView`, not the expanded `VideoPlayerCell` inside `GridPlayerView`.
3. **Region-locked content** — No proxy or geo-bypass support. Downloads fail silently for region-locked videos.
4. **Quality selector is codec-blind** — Shows "best/1080p/720p" but user cannot see or control which codec gets downloaded. VP9 downloads play fine in single mode but destroy grid performance.
5. **NSFW sidebar pollution** — No hide/block mechanism for recommendation spam titles.

---

## Architecture Overview

```
                         ┌─────────────────────────────────────────┐
                         │            BrainyTubeApp                │
                         │  ┌──────────────────────────────────┐   │
                         │  │         ContentView               │   │
                         │  │  ┌────────┐  ┌────────────────┐  │   │
                         │  │  │Sidebar │  │  Detail Area    │  │   │
                         │  │  │ View   │  │                 │  │   │
                         │  │  │        │  │ SinglePlayer or │  │   │
                         │  │  │ (hide/ │  │ GridPlayer      │  │   │
                         │  │  │  block │  │                 │  │   │
                         │  │  │  menu) │  │  ┌───────────┐  │  │   │
                         │  │  │        │  │  │ Thumbnail │  │  │   │
                         │  │  └────────┘  │  │  Grid     │◄─┼──┼── NEW: cached JPEGs
                         │  │              │  └─────┬─────┘  │  │
                         │  │              │        │tap     │  │
                         │  │              │  ┌─────▼─────┐  │  │
                         │  │              │  │  Single   │  │  │
                         │  │              │  │ AVPlayer  │◄─┼──┼── NEW: AV1/H.264 only
                         │  │              │  └───────────┘  │  │
                         │  │              │                 │  │
                         │  │              │ KeyRouter FSM   │◄─┼── NEW: mode-aware keys
                         │  └──────────────┴─────────────────┘  │
                         └─────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                        Download Pipeline                              │
│                                                                       │
│  URL ──► YTDLPService.download()                                      │
│              │                                                        │
│              ├─► CodecStrategy builds format string                    │
│              │     .native:    -S "vcodec:av01,vcodec:avc1"           │
│              │                 -f "bv*[height<=H]+ba/b"               │
│              │     .universal: -f "bv*[height<=H]+ba/b" (any codec)   │
│              │                                                        │
│              ├─► --proxy {type}://{host}:{port} (if configured)       │
│              ├─► --geo-bypass-country XX (if set)                      │
│              │                                                        │
│              ▼                                                        │
│         Download completes                                            │
│              │                                                        │
│              ├─► ThumbnailExtractor.extract(videoURL, at: 0.1)        │
│              │     AVAssetImageGenerator → {videoId}/thumbnail.jpg    │
│              │                                                        │
│              ▼                                                        │
│         Video model updated (codec, thumbnailPath, videoPath)         │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                   Codec Fallback Chain                                 │
│                                                                       │
│   Download preference: AV1 ──► H.264 ──► (VP9 only if .universal)    │
│                                                                       │
│   Playback:                                                           │
│     .native mode    → AVPlayer (AV1 + H.264 hardware decode)         │
│     .universal mode → try AVPlayer first                              │
│                        if VP9 detected → KSPlayer (software decode)   │
│                        fallback → VLCKit (last resort)                │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                   Key Routing FSM                                      │
│                                                                       │
│   States:                                                             │
│     .grid     ─── arrows: navigate cells, Enter: expand               │
│                   Esc: deselect                                       │
│     .focused  ─── left/right: seek ±5s/±10s (tap=5, hold=10)         │
│                   up/down: volume ±0.1                                │
│                   Space: play/pause, Esc: collapse → .grid            │
│     .single   ─── left/right: seek, up/down: volume                  │
│                   Space: play/pause                                   │
│                                                                       │
│   Transitions:                                                        │
│     .grid ──[Enter/tap]──► .focused                                   │
│     .focused ──[Esc]──► .grid                                         │
│     sidebar mode toggle ──► .single / .grid                           │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 1. Tiered Codec Strategy

### New Types

**File**: `Sources/BrainyTube/Services/CodecStrategy.swift` (NEW — ~60 LOC)

```
enum VideoCodecPreference: String, Codable, CaseIterable {
    case native     // AV1 + H.264 only (AVPlayer hardware decode)
    case universal  // Adds VP9 via KSPlayer
}

struct CodecStrategy {
    static func formatString(
        quality: VideoQuality,
        codec: VideoCodecPreference,
        hasFfmpeg: Bool
    ) -> String

    static func sortString(codec: VideoCodecPreference) -> String?
    // Returns: -S "vcodec:av01,vcodec:avc1" for .native, nil for .universal
}
```

### yt-dlp Flag Combinations

| Mode | Quality | Flags |
|------|---------|-------|
| `.native` | best | `-S "vcodec:av01,vcodec:avc1" -f "bv*+ba/b" --merge-output-format mp4` |
| `.native` | 1080p | `-S "vcodec:av01,vcodec:avc1" -f "bv*[height<=1080]+ba/b" --merge-output-format mp4` |
| `.native` | 720p | `-S "vcodec:av01,vcodec:avc1" -f "bv*[height<=720]+ba/b" --merge-output-format mp4` |
| `.universal` | best | `-f "bv*+ba/b" --merge-output-format mp4` |
| `.universal` | 1080p | `-f "bv*[height<=1080]+ba/b" --merge-output-format mp4` |

The `-S` (sort) flag tells yt-dlp to prefer AV1 first, then H.264, effectively skipping VP9 unless nothing else is available. The `bv*+ba/b` format grabs best video + best audio with merge fallback.

When ffmpeg is absent, drop `--merge-output-format mp4` and use `-f "b"` (pre-merged only).

### Modifications

**File**: `Sources/BrainyCore/Models.swift`
- Add `codec: VideoCodecPreference` field to `VideoQuality` usage (or store on `Video` model as `codecPreference: VideoCodecPreference`)
- Add `detectedCodec: String?` field to `Video` — populated post-download by reading the actual container codec via `AVAsset`
- Modify `ytdlpFormatWithMerge` and `ytdlpFormatNoMerge` — replace current implementation with delegation to `CodecStrategy`

**File**: `Sources/BrainyTube/Services/YTDLPService.swift`
- `download()` method: accept `codecPreference` parameter, build args via `CodecStrategy`
- Post-download: detect actual codec from the downloaded file using `AVAssetTrack.mediaType` + `formatDescriptions`

**File**: `Sources/BrainyTube/Services/VideoLibrary.swift`
- Pass codec preference through to `YTDLPService.download()`
- Store detected codec on `Video` model after download

### KSPlayer Integration (conditional)

**File**: `Package.swift` — add conditional dependency:

```swift
// Only pulled when building with UNIVERSAL_CODEC flag or when user enables VP9
.package(url: "https://github.com/kingslay/KSPlayer.git", from: "2.2.0"),
```

**File**: `Sources/BrainyTube/Services/KSPlayerBridge.swift` (NEW — ~40 LOC)
- Thin wrapper: `KSPlayerView: NSViewRepresentable` that wraps KSPlayer for VP9/AV1 software decode
- Only instantiated when `detectedCodec` is VP9 and preference is `.universal`

**VLCKit**: Not added to SPM initially. Listed as emergency fallback if KSPlayer fails on specific formats. Would require `MobileVLCKit` CocoaPod or manual xcframework — too heavy for v1. Document as v2 escape hatch only.

### LOC Estimate
- `CodecStrategy.swift`: ~60 LOC
- `KSPlayerBridge.swift`: ~40 LOC
- `Models.swift` changes: ~20 LOC
- `YTDLPService.swift` changes: ~30 LOC
- `VideoLibrary.swift` changes: ~15 LOC
- **Total: ~165 LOC**

---

## 2. Grid Thumbnail Architecture

This is the highest-impact fix. Eliminates 9 concurrent AVPlayer instances.

### New Types

**File**: `Sources/BrainyTube/Services/ThumbnailExtractor.swift` (NEW — ~80 LOC)

```
struct ThumbnailExtractor {
    /// Extract a single frame from a video at relative position (0.0–1.0)
    static func extractThumbnail(
        from videoURL: URL,
        at relativePosition: Double = 0.1,
        maxSize: CGSize = CGSize(width: 640, height: 360)
    ) async throws -> NSImage

    /// Save thumbnail as JPEG alongside the video
    static func saveThumbnail(
        _ image: NSImage,
        to directory: URL,
        filename: String = "thumbnail.jpg",
        compressionFactor: Double = 0.85
    ) throws -> URL

    /// Batch extraction for existing library (first launch migration)
    static func extractMissing(
        videos: [Video],
        videosDirectory: URL
    ) async -> [String: URL]  // videoID → thumbnail URL
}
```

Implementation uses `AVAssetImageGenerator`:
- `generateCGImage(at:actualTime:)` for single extraction
- `generateCGImagesAsynchronously(forTimes:)` for batch migration
- Output: JPEG at 640x360 (enough for grid cells, small file size)
- Stored at `{videoId}/thumbnail.jpg` alongside the video file

### Modifications

**File**: `Sources/BrainyTube/Services/VideoLibrary.swift`
- After download completion: call `ThumbnailExtractor.extractThumbnail()`, save result, update `video.thumbnailPath`
- On `init()`: after `reconcileLocalFiles()`, trigger `extractMissingThumbnails()` for videos that have `videoPath` but no `thumbnailPath`
- Add `func extractMissingThumbnails()` — runs in background Task, non-blocking

**File**: `Sources/BrainyTube/Features/Player/Presentation/GridPlayerView.swift` — MAJOR REWRITE
- Grid cells show `ThumbnailCell` (static `Image`) instead of `VideoPlayerCell` (live AVPlayer)
- On tap: set `expandedSlotIndex`, instantiate ONE `PlayerViewModel` + `VideoPlayerCell` for the expanded overlay
- On collapse: destroy the single `PlayerViewModel`, return to thumbnail grid
- Remove all multi-AVPlayer slot assignment logic

**File**: `Sources/BrainyTube/Features/Player/Domain/GridViewModel.swift` — SIMPLIFY
- Remove `PlayerSlot.playerVM` (no more per-slot AVPlayers)
- Add `PlayerSlot.thumbnailImage: NSImage?` (cached in memory)
- Keep single `expandedPlayerVM: PlayerViewModel?` for the focused video
- `assign()` loads thumbnail, not AVPlayer
- `expandSlot()` creates AVPlayer; `collapseExpanded()` destroys it

**File**: `Sources/BrainyTube/Features/Player/Presentation/ThumbnailCell.swift` (NEW — ~50 LOC)
- Simple view: `Image` + video title overlay + duration badge
- Tap gesture triggers expand
- Hover effect (slight scale + border glow)

### Memory Impact
- Before: 9 AVPlayers = ~9 x 50-80 MB decode buffers = 450-720 MB GPU/RAM
- After: 9 JPEG thumbnails (~50 KB each) + 1 AVPlayer = ~80 MB total
- **~85% memory reduction in grid mode**

### LOC Estimate
- `ThumbnailExtractor.swift`: ~80 LOC
- `ThumbnailCell.swift`: ~50 LOC
- `GridPlayerView.swift` rewrite: ~100 LOC (simpler than current 150)
- `GridViewModel.swift` changes: ~60 LOC net (remove player logic, add thumbnail logic)
- `VideoLibrary.swift` changes: ~30 LOC
- **Total: ~320 LOC**

---

## 3. Keyboard Navigation Fix

### Current Problem

`BrainyTubeApp.swift` registers global `.keyboardShortcut(.rightArrow)` on the Playback menu. These fire `NotificationCenter` posts. `SinglePlayerView` listens via `.onReceive`. But `GridPlayerView` has zero keyboard handling — the expanded overlay is invisible to the menu shortcut system because it never subscribes to the notifications.

Additionally, when in grid mode (not expanded), arrow keys should navigate between cells, not seek video.

### New Types

**File**: `Sources/BrainyTube/Services/KeyRouter.swift` (NEW — ~90 LOC)

```
enum InputMode: Equatable {
    case grid(selectedCell: Int?)   // Arrow keys navigate cells
    case focused                    // Arrow keys seek/volume
    case single                     // Arrow keys seek/volume
}

@Observable
@MainActor
final class KeyRouter {
    var mode: InputMode = .single

    /// Returns true if the key was handled
    func handleKey(_ event: NSEvent) -> Bool

    // Grid navigation
    var gridSelectedCell: Int? // highlighted cell index
    var gridColumns: Int       // for arrow math

    // Callbacks
    var onSeek: ((TimeInterval) -> Void)?
    var onVolumeChange: ((Float) -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onGridCellSelect: ((Int) -> Void)?
    var onExpand: ((Int) -> Void)?
    var onCollapse: (() -> Void)?
}
```

### Key Bindings by Mode

| Key | `.grid` | `.focused` | `.single` |
|-----|---------|-----------|-----------|
| Left | Previous cell | Seek -5s | Seek -5s |
| Right | Next cell | Seek +5s | Seek +5s |
| Up | Row up | Volume +0.1 | Volume +0.1 |
| Down | Row down | Volume -0.1 | Volume -0.1 |
| Enter | Expand cell | — | — |
| Escape | Deselect | Collapse → grid | — |
| Space | Play/pause selected | Play/pause | Play/pause |
| Shift+Left | — | Seek -10s | Seek -10s |
| Shift+Right | — | Seek +10s | Seek +10s |

### Modifications

**File**: `Sources/BrainyTube/BrainyTubeApp.swift`
- Remove the current `.keyboardShortcut(.rightArrow)` / `.leftArrow` menu commands (they conflict with grid navigation)
- Keep Space, Cmd+1/2/3/4 speed shortcuts
- Arrow key handling moves to `KeyRouter` which is injected at `ContentView` level

**File**: `Sources/BrainyTube/ContentView.swift`
- Add `KeyRouter` as `@State`, inject into child views
- Use `.onKeyPress` (macOS 14+) or `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` to feed events to `KeyRouter`
- Update `KeyRouter.mode` when `viewMode` changes or grid expand/collapse happens

**File**: `Sources/BrainyTube/Features/Player/Presentation/GridPlayerView.swift`
- Visual highlight on `keyRouter.gridSelectedCell` (blue border on the cell)
- Wire `onExpand`/`onCollapse` callbacks

**File**: `Sources/BrainyTube/Features/Player/Presentation/SinglePlayerView.swift`
- Remove `NotificationCenter` `.onReceive` handlers for seek (handled by `KeyRouter` now)
- Keep `NotificationCenter` for menu-triggered speed changes

**File**: `Sources/BrainyTube/Features/Shell/AppViewModel.swift`
- Sync `KeyRouter.mode` with `viewMode` and `gridVM.expandedSlotIndex`

### LOC Estimate
- `KeyRouter.swift`: ~90 LOC
- `BrainyTubeApp.swift` changes: -15 LOC (remove arrow shortcuts)
- `ContentView.swift` changes: ~30 LOC
- `GridPlayerView.swift` changes: ~25 LOC (highlight + wire)
- `SinglePlayerView.swift` changes: -10 LOC (remove NotificationCenter)
- `AppViewModel.swift` changes: ~10 LOC
- **Total: ~130 LOC**

---

## 4. Geo-bypass Integration

### New Types

**File**: `Sources/BrainyTube/Features/Settings/Domain/ProxyConfig.swift` (NEW — ~50 LOC)

```
enum ProxyType: String, Codable, CaseIterable {
    case none
    case socks5
    case http
    case https
}

struct ProxyConfig: Codable, Equatable {
    var type: ProxyType = .none
    var host: String = ""
    var port: Int = 1080
    var username: String = ""
    var password: String = ""  // Stored in Keychain, not UserDefaults

    var ytdlpArgument: String? // nil when .none
    // Returns: "--proxy socks5://user:pass@host:port"
}

enum GeoBypassCountry: String, Codable, CaseIterable {
    case none = ""
    case us = "US"
    case uk = "GB"
    case jp = "JP"
    case kr = "KR"
    case de = "DE"
    case fr = "FR"
    case ca = "CA"
    case au = "AU"

    var label: String { ... }
}
```

**File**: `Sources/BrainyTube/Features/Settings/Domain/SettingsViewModel.swift` (NEW — ~60 LOC)
- Loads/saves `ProxyConfig` to `UserDefaults` (host/port/type) + Keychain (credentials)
- Loads/saves `VideoCodecPreference`
- Loads/saves `GeoBypassCountry`
- Mullvad detection: check if process "mullvad-daemon" is running via `NSWorkspace`

**File**: `Sources/BrainyTube/Features/Settings/Presentation/SettingsView.swift` (NEW — ~120 LOC)
- Proxy section: type picker, host/port fields, username/password secure fields
- "Detect Mullvad" button — auto-fills `socks5://10.64.0.1:1080`
- Geo-bypass country dropdown
- Codec preference picker (`.native` / `.universal`)
- Video quality default picker

### Modifications

**File**: `Sources/BrainyTube/Services/YTDLPService.swift`
- `download()` accepts optional `ProxyConfig` and `GeoBypassCountry`
- Append `--proxy {value}` when proxy is configured
- Append `--geo-bypass-country XX` when country is set

**File**: `Sources/BrainyTube/Services/VideoLibrary.swift`
- Read proxy/geo settings from `SettingsViewModel` (or pass through from AppViewModel)
- Forward to `YTDLPService.download()`

**File**: `Sources/BrainyTube/BrainyTubeApp.swift`
- Add Settings scene: `Settings { SettingsView() }`

### Keychain Storage

Credentials (proxy username/password) stored via `Security.framework` directly:
- `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate`
- Service: `com.brainy.proxy`
- No SecurityKit dependency (BrainyTube is standalone, no shared packages currently)

### LOC Estimate
- `ProxyConfig.swift`: ~50 LOC
- `SettingsViewModel.swift`: ~60 LOC
- `SettingsView.swift`: ~120 LOC
- `YTDLPService.swift` changes: ~20 LOC
- `VideoLibrary.swift` changes: ~10 LOC
- `BrainyTubeApp.swift` changes: ~5 LOC
- Keychain helpers: ~40 LOC
- **Total: ~305 LOC**

---

## 5. Video Quality Selector Enhancement

### Modifications

**File**: `Sources/BrainyCore/Models.swift`
- Add `VideoFormatInfo` struct: `resolution: String, codec: String, fileSize: Int64?, formatId: String`
- Add to `VideoMetadata`: `availableFormats: [VideoFormatInfo]`

**File**: `Sources/BrainyTube/Services/YTDLPService.swift`
- In `fetchMetadata()`: parse `formats` array from yt-dlp JSON dump
- Extract: resolution, vcodec, filesize_approx for each format
- Filter to video-only streams, deduplicate by resolution+codec
- Build `[VideoFormatInfo]` sorted by height descending

**File**: `Sources/BrainyTube/Features/Player/Presentation/PlayerControlsView.swift`
- Quality menu: replace `VideoQuality.allCases` with actual available formats
- Display: "1080p AV1 (~250 MB)", "1080p H.264 (~180 MB)", "720p VP9 (~90 MB)"
- VP9 entries dimmed/badged when codec preference is `.native`
- Selection triggers re-download with specific format ID

**File**: `Sources/BrainyTube/Features/Library/Presentation/SidebarView.swift`
- Context menu "Re-download as..." shows format-aware options instead of just resolution

### LOC Estimate
- `Models.swift` changes: ~25 LOC
- `YTDLPService.swift` changes: ~40 LOC
- `PlayerControlsView.swift` changes: ~35 LOC
- `SidebarView.swift` changes: ~15 LOC
- **Total: ~115 LOC**

---

## 6. NSFW Content Filter

### New Types

**File**: `Sources/BrainyTube/Features/Library/Domain/ContentFilter.swift` (NEW — ~45 LOC)

```
@Observable
@MainActor
final class ContentFilter {
    var hiddenVideoIDs: Set<String>      // persisted in UserDefaults
    var blockedKeywords: [String]        // persisted in UserDefaults

    func isHidden(_ video: Video) -> Bool
    func hide(_ videoID: String)
    func unhide(_ videoID: String)
    func matchesBlocklist(_ title: String) -> Bool
}
```

### Modifications

**File**: `Sources/BrainyTube/Features/Library/Presentation/SidebarView.swift`
- Filter `viewModel.library.videos` through `ContentFilter` before display
- Context menu: add "Hide" action (swipe left on trackpad, or right-click)
- Bottom toolbar: "Show Hidden (N)" toggle to reveal hidden items (dimmed)

**File**: `Sources/BrainyTube/Features/Settings/Presentation/SettingsView.swift`
- "Content Filter" section: keyword blocklist editor (comma-separated or one per line)
- "Reset Hidden Videos" button

**File**: `Sources/BrainyTube/Features/Shell/AppViewModel.swift`
- Add `contentFilter: ContentFilter` property
- Wire into sidebar filtering

### LOC Estimate
- `ContentFilter.swift`: ~45 LOC
- `SidebarView.swift` changes: ~25 LOC
- `SettingsView.swift` changes: ~30 LOC
- `AppViewModel.swift` changes: ~5 LOC
- **Total: ~105 LOC**

---

## SPM Dependencies

### Package.swift Changes

```swift
// Current dependencies (unchanged)
.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
.package(url: "https://github.com/tursodatabase/libsql-swift.git", from: "0.1.1"),
.package(url: "https://github.com/nmdias/FeedKit.git", from: "10.0.0"),
.package(name: "NetKit", path: "../../packages/NetKit"),

// NEW — conditional, only for .universal codec mode
.package(url: "https://github.com/kingslay/KSPlayer.git", from: "2.2.0"),
```

BrainyTube target gains:
```swift
.executableTarget(
    name: "BrainyTube",
    dependencies: [
        "BrainyCore",
        .product(name: "KSPlayer", package: "KSPlayer", condition: .when(platforms: [.macOS])),
    ],
    path: "Sources/BrainyTube"
),
```

**VLCKit**: NOT added. Emergency fallback only. If needed later, add via xcframework manual embed — VLCKit has no clean SPM support.

**No other new dependencies.** Thumbnail extraction, keychain, proxy config all use Apple frameworks (`AVFoundation`, `Security`, `AppKit`).

---

## Files Summary

### New Files (8)

| File | LOC | Wave |
|------|-----|------|
| `Sources/BrainyTube/Services/CodecStrategy.swift` | ~60 | 1 |
| `Sources/BrainyTube/Services/ThumbnailExtractor.swift` | ~80 | 2 |
| `Sources/BrainyTube/Features/Player/Presentation/ThumbnailCell.swift` | ~50 | 2 |
| `Sources/BrainyTube/Services/KeyRouter.swift` | ~90 | 3 |
| `Sources/BrainyTube/Features/Settings/Domain/ProxyConfig.swift` | ~50 | 4 |
| `Sources/BrainyTube/Features/Settings/Domain/SettingsViewModel.swift` | ~60 | 4 |
| `Sources/BrainyTube/Features/Settings/Presentation/SettingsView.swift` | ~120 | 4 |
| `Sources/BrainyTube/Features/Library/Domain/ContentFilter.swift` | ~45 | 5 |

### Modified Files (10)

| File | Change Size | Wave |
|------|-------------|------|
| `Package.swift` | ~5 LOC | 1 |
| `Sources/BrainyCore/Models.swift` | ~45 LOC | 1, 5 |
| `Sources/BrainyTube/Services/YTDLPService.swift` | ~90 LOC | 1, 4, 5 |
| `Sources/BrainyTube/Services/VideoLibrary.swift` | ~55 LOC | 1, 2, 4 |
| `Sources/BrainyTube/Features/Player/Domain/GridViewModel.swift` | ~60 LOC rewrite | 2 |
| `Sources/BrainyTube/Features/Player/Presentation/GridPlayerView.swift` | ~100 LOC rewrite | 2, 3 |
| `Sources/BrainyTube/BrainyTubeApp.swift` | ~15 LOC | 3, 4 |
| `Sources/BrainyTube/ContentView.swift` | ~30 LOC | 3 |
| `Sources/BrainyTube/Features/Player/Presentation/SinglePlayerView.swift` | ~10 LOC removal | 3 |
| `Sources/BrainyTube/Features/Player/Presentation/PlayerControlsView.swift` | ~35 LOC | 5 |
| `Sources/BrainyTube/Features/Library/Presentation/SidebarView.swift` | ~40 LOC | 5, 6 |
| `Sources/BrainyTube/Features/Shell/AppViewModel.swift` | ~15 LOC | 3, 6 |

### Deleted Files
None. `KSPlayerBridge.swift` (~40 LOC) only created if KSPlayer is actually integrated.

---

## Tests

### New Test Files

**File**: `Tests/BrainyTubeTests/CodecStrategyTests.swift` (~50 LOC)
- `test_nativeMode_prefersAV1ThenH264` — verify format string contains `-S "vcodec:av01,vcodec:avc1"`
- `test_universalMode_noSortFlag` — verify no `-S` flag
- `test_qualityCap_respected` — verify `height<=720` in format string for `.hd720`
- `test_noFfmpeg_fallsBackToPremerged` — verify `-f "b"` when ffmpeg absent

**File**: `Tests/BrainyTubeTests/ThumbnailExtractorTests.swift` (~60 LOC)
- `test_extractThumbnail_returnsValidImage` — use a bundled test MP4, verify NSImage dimensions
- `test_saveThumbnail_writesJPEG` — verify file on disk, JPEG header bytes
- `test_extractMissing_skipsExistingThumbnails` — verify already-thumbnailed videos not re-processed

**File**: `Tests/BrainyTubeTests/KeyRouterTests.swift` (~80 LOC)
- `test_gridMode_arrowRight_movesCell` — selectedCell increments
- `test_gridMode_enter_expandsCell` — mode transitions to .focused
- `test_focusedMode_arrowRight_seeks` — onSeek callback fires with +5
- `test_focusedMode_escape_collapsesToGrid` — mode transitions to .grid
- `test_singleMode_arrowRight_seeks` — same seek behavior as focused
- `test_gridMode_arrowDown_wrapsToNextRow` — column-aware navigation

**File**: `Tests/BrainyTubeTests/ContentFilterTests.swift` (~40 LOC)
- `test_hideVideo_filtersFromList`
- `test_unhideVideo_restoresInList`
- `test_blockedKeyword_matchesCaseInsensitive`
- `test_emptyBlocklist_hidesNothing`

**File**: `Tests/BrainyTubeTests/ProxyConfigTests.swift` (~30 LOC)
- `test_socks5Proxy_buildsCorrectArgument`
- `test_noProxy_returnsNil`
- `test_httpProxy_withCredentials_includesAuth`
- `test_geoBypass_appendsCountryFlag`

### Test Infrastructure Note

BrainyTube currently has zero tests (`Tests/BrainyTests/` only covers the RSS CLI). Need to add a `BrainyTubeTests` test target to `Package.swift`:

```swift
.testTarget(
    name: "BrainyTubeTests",
    dependencies: ["BrainyCore"],  // NOT BrainyTube — it's @main executable
    path: "Tests/BrainyTubeTests",
    resources: [.copy("Fixtures")]
)
```

Test fixtures: one short MP4 (H.264, 3 seconds, 320x180) for thumbnail extraction tests.

**Total test LOC: ~260**

---

## Build Order (Waves)

### Wave 1: Codec Strategy (foundation — unblocks everything)
- `CodecStrategy.swift` (new)
- `Models.swift` (add codec fields)
- `YTDLPService.swift` (format string delegation)
- `VideoLibrary.swift` (pass codec preference)
- `Package.swift` (KSPlayer conditional dep)
- Tests: `CodecStrategyTests.swift`
- **~165 LOC + ~50 test LOC**
- **Ship criterion**: existing downloads still work, new downloads prefer AV1/H.264

### Wave 2: Thumbnail Grid (biggest UX win)
- `ThumbnailExtractor.swift` (new)
- `ThumbnailCell.swift` (new)
- `GridViewModel.swift` (rewrite: remove per-slot AVPlayers)
- `GridPlayerView.swift` (rewrite: thumbnails + single expanded player)
- `VideoLibrary.swift` (post-download thumbnail extraction + migration)
- Tests: `ThumbnailExtractorTests.swift`
- **~320 LOC + ~60 test LOC**
- **Ship criterion**: grid shows thumbnails, tap expands to single player, no pixelation

### Wave 3: Keyboard Navigation (fixes the broken UX)
- `KeyRouter.swift` (new)
- `ContentView.swift` (key event capture)
- `GridPlayerView.swift` (cell highlight)
- `SinglePlayerView.swift` (remove NotificationCenter seek)
- `BrainyTubeApp.swift` (remove arrow shortcuts from menu)
- `AppViewModel.swift` (mode sync)
- Tests: `KeyRouterTests.swift`
- **~130 LOC + ~80 test LOC**
- **Ship criterion**: arrow keys work correctly in all three modes

### Wave 4: Geo-bypass + Settings (feature expansion)
- `ProxyConfig.swift` (new)
- `SettingsViewModel.swift` (new)
- `SettingsView.swift` (new)
- `YTDLPService.swift` (proxy/geo args)
- `VideoLibrary.swift` (settings forwarding)
- `BrainyTubeApp.swift` (Settings scene)
- Tests: `ProxyConfigTests.swift`
- **~305 LOC + ~30 test LOC**
- **Ship criterion**: can configure proxy, region-locked videos download successfully

### Wave 5: Quality Selector Enhancement (polish)
- `Models.swift` (VideoFormatInfo)
- `YTDLPService.swift` (parse available formats)
- `PlayerControlsView.swift` (format-aware menu)
- `SidebarView.swift` (format-aware context menu)
- **~115 LOC, no new tests (UI-driven)**
- **Ship criterion**: quality menu shows codec + size info per format

### Wave 6: Content Filter (cosmetic fix)
- `ContentFilter.swift` (new)
- `SidebarView.swift` (hide action + filter)
- `SettingsView.swift` (blocklist editor)
- `AppViewModel.swift` (wire filter)
- Tests: `ContentFilterTests.swift`
- **~105 LOC + ~40 test LOC**
- **Ship criterion**: can hide videos, keyword blocklist filters sidebar

---

## Total Estimates

| Metric | Count |
|--------|-------|
| New files | 8 |
| Modified files | 12 |
| New production LOC | ~1,140 |
| New test LOC | ~260 |
| **Total LOC** | **~1,400** |
| Waves | 6 |
| New SPM dependencies | 1 (KSPlayer, conditional) |

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| KSPlayer SPM build time / size | Bloated binary | Gate behind `.universal` preference; most users stay on `.native` |
| AV1 not available for older YouTube videos | Some videos download as VP9 anyway | Fallback in format string (`bv*+ba/b` without `-S` if first attempt 404s) |
| `AVAssetImageGenerator` slow for batch migration | First launch lag with large library | Run in background Task, show placeholder thumbnails until ready |
| `.onKeyPress` only macOS 14+ | Already our min target | No issue — Package.swift already declares `.macOS(.v14)` |
| yt-dlp format string syntax changes | Downloads break on yt-dlp update | Pin yt-dlp version in docs, test format strings in CI |
| Mullvad auto-detect false positive | Wrong proxy config | "Detect Mullvad" is manual button, not auto-applied |
