# BrainyTube iPad Support

> **Status**: Draft
> **Date**: 2026-03-28
> **Scope**: Multi-platform expansion — iPad playback client + Mac download engine
> **Project**: `/projects/brainy` → `Sources/BrainyTube`

---

## Phase 1 — Architecture Brainstorm

### Options Matrix

| | Option A: Mac Catalyst | Option B: Shared Codebase (Recommended) | Option C: VPS Proxy | Option D: Swift YouTube Extraction |
|---|---|---|---|---|
| **Runs on real iPad** | No — Mac only | Yes | Yes | Yes |
| **yt-dlp works** | Yes (runs on Mac) | Yes (Mac target only) | Yes (runs on VPS) | No — fragile Swift alternative |
| **Code changes** | Minimal (checkbox) | Moderate (~200 LOC guards) | High (server + sync) | Extreme (library maintenance) |
| **Offline playback** | Yes | Yes | Partial (stream or cache) | Yes |
| **Sync complexity** | None | iCloud Drive (simple) | API + polling + auth | None |
| **App Store viable** | Yes (macOS only) | Yes (iPad target, playback-only) | Risky (downloads in cloud) | Very risky (ToS + review) |
| **Without Mac nearby** | Yes | No — Mac must be on | Yes | Yes |
| **Maintenance burden** | Low | Low-Medium | Medium-High | Very High |
| **Development time** | 1 day | 3–5 days | 2–3 weeks | Unknown / unbounded |

### Agent Analysis

**@Sensei — Architecture**

Option B is the correct long-term choice. The codebase is 90% pure SwiftUI + AVKit — already platform-agnostic. The only macOS-specific surface is:
- `YTDLPService` — calls `Process()`, unavailable on iOS. Entire service must be `#if os(macOS)`.
- `NSWorkspace.shared.selectFile` in `SidebarView` — one line behind `#if os(macOS)`.
- `ExportService` — uses `FileManager` + `NSWorkspace`; export button hidden on iPad.
- `BrainyTubeApp` `.commands {}` block — AppKit menu bar, harmless on iPadOS (ignored).
- `VideoLibrary.videosDirectory` — `applicationSupportDirectory` doesn't sync; swap to iCloud container on iPad.
- `Storage` (SQLite via libsql-swift) — must verify libsql-swift supports iOS. If not, swap to raw SQLite or a lightweight alternative for the iPad target.

Option C (VPS proxy) makes sense as v2 — download anywhere without the Mac. It layers on top of Option B cleanly: the iPad app gains a second download source (VPS) when the Mac is not on the same iCloud Drive.

**@Hanami — iPad UX**

The Mac app has a NavigationSplitView sidebar + detail. On iPad this maps directly:
- iPad landscape = sidebar + player (same layout, works as-is)
- iPad portrait = sidebar collapses to overlay (NavigationSplitView handles this automatically)
- Grid mode (multi-video tiles) needs a column cap at 2x2 on 11" screen vs 4x4 on Mac
- Magic Keyboard shortcuts must be documented: Space = play/pause, arrows = seek, Cmd+1-4 = speed
- "Add video" flow on iPad: paste URL (no yt-dlp) → show placeholder "Queued on Mac" state
- Storage management becomes visible (iPad has limited space): storage used badge, per-video delete

**@Ronin — What Breaks**

1. **iCloud Drive sync latency**: videos are large (500MB–2GB). First-time sync after Mac download may take 20–30 min. iPad must show "downloading from iCloud" progress, not a broken file.
2. **iCloud Drive availability**: user must enable iCloud Drive in macOS System Settings AND in iPad Settings. No silent failure — app must detect and guide the user.
3. **File coordination**: macOS and iPadOS both accessing the same iCloud Drive container simultaneously risks write conflicts. Use `NSFileCoordinator` (or `FilePresenter`) on Mac side; iPad is read-only on shared files.
4. **libsql-swift on iOS**: The SPM package targets Linux/macOS via a compiled C library. If it lacks iOS arm64 slices, the iPad target won't build. Mitigation: separate DB per platform (Mac = libsql, iPad = SQLite directly).
5. **iCloud Drive container path**: `applicationSupportDirectory` is not iCloud. Must use `FileManager.default.url(forUbiquityContainerIdentifier:)`. Requires iCloud entitlement and provisioning profile (needs Apple Developer account — user is enrolling).
6. **App Store gray zone**: iPad app that only plays downloaded videos (no in-app download) is clean — no different from VLC or Infuse. Download happens on Mac, user transfers via iCloud. This is a standard workflow, not a policy issue.

**@Shogun — Market**

- VLC, Infuse, nPlayer all pass App Store review as playback-only apps with file import.
- No App Store app ships yt-dlp directly on iOS — but side-loading via AltStore / direct install is common in dev community.
- Distribution path: direct install (TestFlight or `.ipa` via Xcode) for v1 is zero risk. App Store submission for v2 (playback-only) is viable if download UI is Mac-only.
- Competitive advantage: grid mode (multi-video simultaneously) is unique. No other iOS player does it.

---

## Phase 2 — Feature Brief

### v1 — Playback-Only iPad Client (iCloud Sync from Mac)

**What it is**: A second Xcode target (`BrainyTubeiOS`) in the same SPM package, sharing all playback and model code. Videos are downloaded on the Mac as today, then appear automatically on iPad via iCloud Drive.

**What it does NOT do**: Download videos on the iPad. The iPad is a consumption device, not a download station.

**User flow**:
1. User downloads videos on Mac (unchanged workflow)
2. Mac app writes to iCloud Drive container instead of `applicationSupportDirectory`
3. iPad app reads the same iCloud container, shows synced videos
4. User taps a video → iCloud streams/downloads the file locally → AVPlayer plays it
5. User can delete from iPad (frees local iPad storage; Mac copy remains on iCloud)

**iPad-specific features**:
- Thumbnail grid for library (larger touch targets than Mac sidebar)
- Single-player full-screen mode with gesture controls (tap = play/pause, swipe = seek)
- Grid mode capped at 2x2 (4 videos max on iPad screen)
- Magic Keyboard shortcut parity with Mac
- iCloud sync status indicator (cloud progress icon per video)
- Storage used badge in sidebar header
- "Download to iPad" button (triggers iCloud file download for offline use)

**Out of scope for v1**:
- App Store distribution (direct install only — user's Apple Developer account enrolling)
- Downloading new YouTube videos from iPad
- VPS proxy
- Any server component

---

### v2 — VPS Download Proxy + DLNA Local Streaming

**What it is**: A lightweight server endpoint (Deno or Go) on the existing VPS (`92.134.242.73`) that accepts a YouTube URL, runs yt-dlp, and stores the video on the VPS. Plus a DLNA/minidlna-like service for streaming to local devices.

**Architecture**: Mac is the master node. VPS is a storage + download node. iOS/tvOS/visionOS are companion consumers.

**What it adds**:
- "Add video" on iPad sends URL to VPS API → VPS downloads → file stored on VPS
- DLNA-like service on VPS or Mac for local network streaming to companions
- Companion devices can browse the master's library and download (direct download, like from any web source)
- Context menu on sidebar: right-click → "Get in Local" (SF Symbol: arrow.down.circle) downloads from master to companion device
- Multi-select → "Get in Local (5)" downloads all selected to companion
- Videos consumed offline after local download — no streaming dependency
- Download status via webhook or short-poll
- Auth: simple API key (shared secret stored in Keychain)

**NO iCloud Drive for videos.** Videos stay on VPS or Mac local storage. Companions download via direct transfer.

**Out of scope for v2**:
- iCloud Drive video sync (explicitly rejected)
- Native streaming (download first, watch offline)
- Multiple user support
- App Store distribution

---

### Out of Scope (Both Versions)

- App Store distribution until v2 is stable and playback-only mode is confirmed clean by review
- watchOS target (screen too small)
- In-app YouTube search / browsing
- Android / web clients
- Any Swift-native YouTube extraction library (fragile, unmaintainable)
- Mac Catalyst (doesn't run on real iPad, no value)

---

## Phase 3 — Business Requirements

### BR-001 — Multi-Platform SPM Target

**Description**: Add an iOS/iPadOS executable target `BrainyTubeiOS` in `Package.swift`, sharing `BrainyCore` and all platform-agnostic sources with the existing `BrainyTube` macOS target.

**Acceptance Criteria**:
- `Package.swift` declares a new `.executableTarget(name: "BrainyTubeiOS")` with `platforms: [.iOS(.v17)]`
- Both targets compile cleanly in Xcode without modification to shared sources
- `BrainyCore` target builds for both `.macOS(.v14)` and `.iOS(.v17)`
- No source file is duplicated between targets — only new platform-specific files are added

**Technical notes**:
- `Package.swift` `platforms` array updated from `[.macOS(.v14)]` to `[.macOS(.v14), .iOS(.v17)]`
- `BrainyCore` must compile on iOS: audit all imports for macOS-only APIs
- `libsql-swift` iOS support TBD — if unavailable, `BrainyCore` on iOS uses a separate `StorageProtocol` backed by raw SQLite (via `SQLite3` C module already available on iOS)

---

### BR-002 — Platform Code Isolation

**Description**: All macOS-specific code must be isolated behind `#if os(macOS)` guards so the iOS target compiles without errors.

**Acceptance Criteria**:
- `YTDLPService.swift` is conditionally compiled: `#if os(macOS)` wraps the entire file (or a `DownloadUnavailableService` stub is provided for iOS)
- `SidebarView.swift`: `NSWorkspace.shared.selectFile` call wrapped in `#if os(macOS)`, replaced with no-op on iOS
- `ExportService.swift` calls (export button) conditionally hidden on iPad: `#if os(macOS)` or `.hidden()` modifier
- `BrainyTubeApp.swift` `.commands {}` block compiles on iOS (SwiftUI `.commands` is macOS-only — wrap or remove for iOS entry point)
- Zero `#if os(macOS)` omissions: CI build for iOS target must compile without warnings

**Files to audit**:
- `Sources/BrainyTube/Services/YTDLPService.swift` — Process(), macOS-only
- `Sources/BrainyTube/Services/ExportService.swift` — NSWorkspace
- `Sources/BrainyTube/Features/Library/Presentation/SidebarView.swift` — NSWorkspace.shared.selectFile
- `Sources/BrainyTube/BrainyTubeApp.swift` — .commands{}, .defaultSize() (macOS only modifier)
- `Sources/BrainyTube/Features/Shell/AppViewModel.swift` — applicationSupportDirectory (works on iOS but path differs from iCloud container)

---

### BR-003 — Local Video Transfer (NO iCloud Drive for videos)

**Description**: Videos stay on Mac (local) or VPS. Companion devices (iPad/tvOS/visionOS) download videos via direct transfer from the master node, NOT via iCloud Drive.

**Acceptance Criteria**:
- Mac app stores videos in `applicationSupportDirectory` (unchanged from current behavior)
- VPS stores videos downloaded via VPS proxy (v2)
- Companion devices browse the master's library via local network API or DLNA
- Context menu on companion: "Get in Local" (SF Symbol: `arrow.down.circle`) downloads video file from master
- Multi-select: "Get in Local (N)" downloads all selected
- Per-video `transferStatus` enum: `.remote`, `.downloading(progress: Double)`, `.local`
- Downloaded videos play offline — no streaming dependency
- iCloud used ONLY for lightweight data sync (DB metadata, preferences) — NOT video files
- Master exposes a simple HTTP endpoint or DLNA service for file transfer

**Technical notes**:
- Local network discovery via Bonjour/mDNS (same as Shikki mesh protocol pattern)
- Direct download = simple HTTP GET from master's video directory
- No iCloud Drive entitlement needed for video files
- DB metadata can sync via iCloud KV store (lightweight, no video data)
- Check existing CoreKit/DataKit for libsql usage — may already have iOS patterns

---

### BR-004 — iPad Library UI (Thumbnail Grid)

**Description**: Replace the Mac sidebar list with a thumbnail grid for the iPad library view, optimized for touch interaction with larger tap targets.

**Acceptance Criteria**:
- iPad library shows a 3-column thumbnail grid in portrait mode, 4-column in landscape (iPad 11"), adaptive for iPad Pro 13"
- Each cell shows: thumbnail (16:9 aspect ratio), title (2 lines max, ellipsis), channel name, duration badge, download status indicator
- Tap = select and play video in main area
- Long-press context menu = Delete, Download to iPad, Share (on iOS)
- Selection state is single-select by default on iPad (no multi-select sidebar behavior from macOS)
- Pull-to-refresh triggers iCloud sync status refresh (re-query `NSMetadataQuery`)
- Empty state shows illustration + "Open BrainyTube on your Mac to download videos"

**Technical notes**:
- `NavigationSplitView` replaces sidebar list with `LazyVGrid` on iPad
- Use `@Environment(\.horizontalSizeClass)` to adapt column count
- Thumbnail loading uses `AsyncImage` with the cached local thumbnail path, with iCloud download fallback

---

### BR-005 — iPad Single Player

**Description**: Full-screen video player with gesture controls for iPad, sharing `PlayerViewModel` with the Mac target.

**Acceptance Criteria**:
- Tapping a video from the library grid opens full-screen player
- Double-tap left/right zones seeks -10s / +10s (standard iOS video player convention)
- Single tap toggles controls overlay (play/pause button, scrubber, speed selector)
- Swipe down dismisses player back to library grid
- Speed control: 0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x, 3x (iOS-native speed picker or custom overlay)
- Subtitles (VTT) rendered when available, toggle button in controls overlay
- Picture-in-Picture (PiP) via AVKit's built-in PiP support
- Landscape and portrait supported; video always centered with letterbox/pillarbox as needed
- `PlayerViewModel` is shared with macOS target — no iOS-specific fork

**Technical notes**:
- `VideoPlayerCell` refactored to support: Mac (mouse hover for controls), iPad (tap for controls), tvOS (focus-based navigation via `@FocusState` + `focusable()` modifier), visionOS (gaze + tap). Use `#if os(iOS)` / `#if os(tvOS)` / `#if os(visionOS)` guards for gesture/focus attachment.
- `AVPlayerViewController` wrapping is acceptable for PiP on iOS vs custom `VideoPlayerLayer` on macOS
- **PiP behavior**: see BR-007b below.

---

### BR-006 — iPad Grid Mode

**Description**: Multi-video grid playback adapted for iPad screen size.

**Acceptance Criteria**:
- Maximum grid size on iPad: 2x2 (4 cells). macOS max remains 4x4.
- Grid mode accessible via toolbar button (replaces Mac bottom segmented control)
- Drag-and-drop from library grid to player grid works on iPadOS 17+
- Audio routing: same "active audio slot" single-audio model as macOS
- Expand-to-full-screen gesture on individual cells
- Column/row stepper removed on iPad; preset layouts only: 1x1, 1x2, 2x1, 2x2

**Technical notes**:
- `GridViewModel` already has `columns` and `rows` properties; cap them at `#if os(iOS) max(2)`
- iPad layout may use a split view: library on left, grid player on right in landscape mode

---

### BR-007 — Magic Keyboard Shortcuts (iPad)

**Description**: Full keyboard shortcut parity with the macOS app when using iPad with Magic Keyboard.

**Acceptance Criteria**:
- Space — play/pause (active player)
- Left/Right Arrow — seek -10s / +10s
- Cmd+1 — speed 1x
- Cmd+2 — speed 1.5x
- Cmd+3 — speed 2x
- Cmd+4 — speed 3x
- Cmd+F — toggle full-screen player
- Escape — dismiss full-screen / collapse expanded grid cell
- All shortcuts discoverable via iOS 15+ keyboard shortcut overlay (hold Cmd)
- Shortcuts registered via SwiftUI `.keyboardShortcut()` modifier — same modifier used on macOS

**Technical notes**:
- SwiftUI `.keyboardShortcut()` works on iPadOS 15+. The existing macOS `.commands {}` approach does not exist on iOS, but `Button` with `.keyboardShortcut()` works directly in views.
- Notification-based shortcuts (current macOS approach using `NotificationCenter`) must be replaced with direct `Button` + `.keyboardShortcut()` in the player view for iPad compatibility.
- **`M` key** = toggle mute/unmute on active player. In grid mode: toggles on the current active audio slot. If keyboard focus/cursor is on a specific grid cell, toggle that cell instead.

### BR-007b — Picture-in-Picture Lifecycle

**Description**: Swipe down on any video player detaches to PiP. All other players stop. On re-attach, restore previous multi-player state.

**Acceptance Criteria**:
- Swipe down on video (single or grid cell) → detach to PiP via AVKit
- All other running players pause immediately and store their state (currentTime, playbackRate, muted)
- PiP video continues playing independently
- On PiP re-attach (user taps to return) → all previously-running players resume from stored state
- Player states stored in memory only (not persisted) — PiP is a transient mode
- Works on iPad, iPhone (if ever supported), and macOS (native PiP)
- `AVPictureInPictureController` for iOS, `AVPlayerView.allowsPictureInPicturePlayback` for macOS

---

### BR-008 — Storage Management

**Description**: iPad has constrained storage. The app must surface storage usage and allow per-video deletion to free space.

**Acceptance Criteria**:
- Library header shows "X videos · Y GB on device" badge
- Per-video storage size shown in cell (e.g., "1.2 GB") from file attributes
- "Remove from iPad" action in long-press context menu: deletes local copy, video stays available on master (Mac/VPS) for re-download
- "Delete" action removes from local + master library (requires confirmation)
- Storage sort: library sortable by size (largest first) for easy cleanup

**Technical notes**:
- File size from `URLResourceValues.fileSizeKey` on the local video file
- "Remove from iPad" = simple file delete. Video metadata stays in local DB with `transferStatus = .remote`
- No iCloud eviction API — just delete the file

---

### BR-009 — Offline Playback

**Description**: Videos that have been downloaded to iPad must play with no network connection.

**Acceptance Criteria**:
- `cloudOnly` videos show "Tap to download" overlay — not playable until downloaded locally
- `local` videos play immediately with no network
- `downloading(progress:)` videos show a progress ring and block playback until complete
- App launches and loads library with no network (reads local DB, shows local + cloud file status from cached metadata)
- Subtitles stored alongside video in iCloud container — same iCloud download flow

**Technical notes**:
- AVPlayer works offline for local files. Ensure `videoPath` always points to the fully-downloaded iCloud local copy, not the iCloud URL directly (which would require network).
- Before loading a video, check `URLResourceValues.ubiquitousItemDownloadingStatusKey == .current` to confirm the file is fully local.

---

### BR-010 — Data Sync (iCloud KV Store only, NO video files)

**Description**: iCloud is used ONLY for lightweight data sync (library metadata, preferences, watch history). Video files are NEVER stored in iCloud — they stay local on Mac/VPS and are transferred via direct download.

**Acceptance Criteria**:
- `NSUbiquitousKeyValueStore` for syncing: video metadata (title, URL, channel, download date), user preferences, watch progress
- NO `iCloud.one.obyw.BrainyTube` container for video files — no iCloud Drive usage
- Only `com.apple.developer.ubiquity-kvstore-identifier` entitlement needed (lightweight KV, not file container)
- App works fully without iCloud: local DB is the source of truth, iCloud KV is optional sync layer
- Check existing CoreKit/DataKit SPM packages for libsql usage patterns — may already have iOS-compatible storage

---

## Phase 4 — Test Plan

### T-001 — Build Validation

| Test | Expected |
|---|---|
| `xcodebuild -target BrainyTubeiOS -destination "platform=iPadOS Simulator,name=iPad Pro 11-inch (M4)"` compiles cleanly | Zero errors, zero warnings on platform guards |
| `xcodebuild -target BrainyTube` still compiles cleanly after all guards added | Unchanged macOS behavior |
| `swift build` for BrainyCore with iOS target | No `#unavailable` API usage |

### T-002 — Platform Guard Unit Tests

| Test | Expected |
|---|---|
| `YTDLPService` not instantiable on iOS build | Compile-time exclusion via `#if os(macOS)` |
| `VideoLibrary` on iOS uses iCloud container path | `videosDirectory` returns ubiquity URL on iOS |
| `AppViewModel` on iOS has no `downloadQueue` behavior | `importURLs()` on iOS shows "Mac required" alert instead of queuing |

### T-003 — Data Sync + Local Transfer Tests

Run on device pair (Mac + iPad on same network):

| Test | Expected |
|---|---|
| Download video on Mac → iPad sees it in library as `.remote` | Video metadata synced via iCloud KV, status = `.remote` |
| Tap "Get in Local" on iPad → progress shows → video plays | Direct HTTP download from Mac, video plays offline after download |
| "Remove from iPad" → local file deleted → still in Mac library | File deleted, metadata stays with `.remote` status, Mac unchanged |
| Disconnect iPad from network → play already-downloaded video | AVPlayer plays from local copy, no network required |
| iCloud KV unavailable → launch app | Local DB is source of truth, no crash, library shows local-only content |
| VPS download (v2) → iPad fetches from VPS | Same flow as Mac transfer but from VPS endpoint |

### T-004 — iPad UI Tests (Simulator)

| Test | Expected |
|---|---|
| Library grid — portrait mode (iPad 11") | 3 columns, thumbnails fill width correctly |
| Library grid — landscape mode (iPad 11") | 4 columns, no layout overflow |
| Single player — tap to show/hide controls | Controls overlay appears/disappears |
| Single player — double-tap left zone | Seeks back 10s, shows seek animation |
| Single player — swipe down | Dismisses to library grid |
| Grid mode — max 2x2 enforced | Cannot add 3rd column or row |
| Grid mode — expand cell full screen | Cell expands with animation, audio continues |
| Long-press on library cell | Context menu shows: Download to iPad / Remove from iPad / Delete |

### T-005 — Magic Keyboard Shortcuts (Device)

Requires iPad with Magic Keyboard attached:

| Shortcut | Expected |
|---|---|
| Space | Active player play/pause |
| Left Arrow | Seek -10s |
| Right Arrow | Seek +10s |
| Cmd+1 | Speed = 1x |
| Cmd+2 | Speed = 1.5x |
| Cmd+3 | Speed = 2x |
| Cmd+4 | Speed = 3x |
| M | Toggle mute/unmute on active player (grid: active audio slot or focused cell) |
| Hold Cmd | Keyboard shortcut overlay shown by iPadOS |
| Escape (in full-screen) | Dismiss to library |

### T-005b — PiP Lifecycle Tests (Device)

| Test | Expected |
|---|---|
| Swipe down on single player → PiP | Video continues in PiP, player view shows library |
| Swipe down in grid mode → PiP active cell | Active cell goes PiP, other players pause, states stored |
| Re-attach from PiP | All previously-running players resume from stored positions |
| PiP + app background → foreground | PiP continues, re-attach restores state |

### T-006 — Storage Management Tests

| Test | Expected |
|---|---|
| Library header shows correct "X GB on device" | Matches sum of local video file sizes |
| Per-video size badge shows correct value | Matches `URLResourceValues.fileSizeKey` |
| Sort by size | Largest videos first |
| "Remove from iPad" → file size decreases | Badge updates after eviction |

### T-007 — Performance Tests (iPad)

| Test | Expected |
|---|---|
| Library grid with 50+ videos scrolls at 60fps | No frame drops on LazyVGrid |
| Thumbnail loading — 50 visible cells | No main thread blocking, async load |
| Grid mode 2x2 — all 4 players running | No memory warning within 60s |
| Video switch in single player | Loads within 500ms for local file |

---

## Implementation Waves

### Wave 1 — Platform Foundation (1–2 days)
1. Update `Package.swift`: add `.iOS(.v17)` to platforms, add `BrainyTubeiOS` target
2. Add `#if os(macOS)` guards: `YTDLPService`, `ExportService`, `NSWorkspace` calls in SidebarView
3. Create `BrainyTubeApp+iOS.swift` entry point (separate from macOS `.commands` app)
4. Verify `BrainyCore` compiles for iOS (libsql-swift iOS support check)

### Wave 2 — iCloud Storage (1–2 days)
1. `VideoLibrary` gains `iCloudContainerURL()` — returns ubiquity URL on iOS, fallback to appSupport on macOS
2. `Video` model gains `cloudStatus` computed property + `NSMetadataQuery` integration
3. Entitlements files created for both targets
4. `NSFileCoordinator` added to Mac write path

### Wave 3 — iPad Library UI (1–2 days)
1. `LibraryGridView.swift` — new thumbnail grid view (iOS only)
2. `VideoThumbnailCell.swift` — touch-optimized cell with status badge
3. Cloud download progress on cells
4. Empty state + iCloud setup guidance

### Wave 4 — iPad Player (1 day)
1. `VideoPlayerCell` gesture layer for iOS (tap, double-tap, swipe-down)
2. `AVPlayerViewController` wrapper for PiP on iOS
3. Subtitle overlay shared from macOS code
4. `.keyboardShortcut()` modifiers moved into view body (replaces NotificationCenter approach on iOS)

### Wave 5 — Grid Mode + Storage UI (1 day)
1. `GridViewModel` column/row cap for iOS
2. iPad grid toolbar (preset layouts)
3. Storage badge in library header
4. "Remove from iPad" / eviction actions

### Wave 6 — Polish + Testing (1 day)
1. Full T-001 → T-007 pass on simulator + device
2. iCloud sync end-to-end test on Mac + iPad device pair
3. Memory footprint check in grid 2x2 mode
4. Magic Keyboard shortcut validation

---

*Saved to Shiki DB. Spec author: Claude. Challenge: @shi should flag any BR that would require breaking `BrainyCore`'s current SQLite interface, any iCloud file coordination edge case not covered, and any memory concern in 4-player grid on iPad M1/M2.*
