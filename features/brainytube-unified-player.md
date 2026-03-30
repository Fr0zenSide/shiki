# BrainyTube Unified Player v2

> **Status**: implementing
> **Date**: 2026-03-29
> **Scope**: Single player component shared across all modes (single, grid, stream, local)

---

## Requirements

### R-01: One Player, All Modes

One `VideoPlayerCell` used everywhere — macOS single, macOS grid, iPad single, iPad stream, iPad grid. Same controls, same gestures, same behavior. No platform-specific forks.

### R-02: Speed Control on Stream

Speed picker must work on streaming (remote DLNA URL) the same as local playback. `AVPlayer.rate` works on both local and HTTP streams.

### R-03: Double-Tap Fast-Forward/Rewind

Divide the player view into left half (rewind) and right half (forward).

**Double-tap on right half** = seek forward:
- First double-tap: +10s
- If another double-tap within 2s debounce: +20s total
- Continue double-tapping within debounce: +10s each
- After accumulating >1min: each subsequent tap adds +30s
- After accumulating >3min: each subsequent tap adds +2min

**Double-tap on left half** = same logic but backwards.

**Visual overlay**:
- 50px-wide transparent strip on left/right border
- SF Symbol: `forward.fill` (right) or `backward.fill` (left)
- Text showing accumulated time: "+10s", "+20s", "+1:00", "+1:30", etc.
- Fade out after debounce expires (2s)

### R-04: Two-Finger Horizontal Swipe Seek

Pan gesture with 2 fingers horizontally = seek through video.
- Gesture translation maps to seek position (proportional to video duration)
- While panning, show a **thumbnail preview card** above the seek bar:
  - Thumbnail: generated from `AVAssetImageGenerator` at the target time
  - Time label: formatted time at target position
  - Card follows finger position horizontally

### R-05: Seek Bar Thumbnail Preview

When dragging the seek slider, show a floating card above the thumb with:
- Generated thumbnail at the seek target time
- Formatted time label
- Card dismisses when drag ends

### R-06: PiP Button

PiP button in the player controls bar, right side, next to fullscreen button.
- SF Symbol: `pip.enter` / `pip.exit` (toggles)
- Works on iPad (AVPictureInPictureController), macOS (AVPlayerView.allowsPictureInPicturePlayback)
- On stream mode: PiP works with remote URLs (AVPlayer handles this natively)

### R-07: Fullscreen Button on All Modes

Fullscreen (expand) button visible on ALL player instances, not just grid cells.
- Single player: expands to full window (hides sidebar)
- Grid cell: expands to full detail view (existing behavior)
- Stream player: same as single player
- SF Symbol: `arrow.up.left.and.arrow.down.right` / `arrow.down.right.and.arrow.up.left`

### R-08: Auto-Play Next

Toggle in player controls or settings:
- When current video ends, automatically play the next video in the list
- Respect the current sort order (or manual order if reordered)
- Show a 5s countdown overlay before auto-playing ("Next: [title] in 5s" with cancel button)
- SF Symbol for toggle: `text.line.last.and.arrowtriangle.forward`

### R-09: Drag & Drop Reorder in Sidebar

- Drag a video row in the sidebar list
- Drop on another row = reorder (save position in UserDefaults)
- Drop on the player area = play that video immediately
- Visual feedback: dragged row lifts, drop target shows insertion indicator

### R-10: Controls Visibility (Touch-Friendly)

Controls should appear on:
- Single tap (existing)
- Touch-and-move (drag/pan without release) — shows controls without toggling play/pause
- Mouse hover (macOS, existing)

Controls should NOT toggle play/pause on:
- Pan gesture start (only on clean tap with no movement)

Auto-hide after 3s of inactivity (existing).

---

## Seek Acceleration Table

| Tap count | Time within debounce | Increment | Accumulated |
|-----------|---------------------|-----------|-------------|
| 1 (double-tap) | — | +10s | 10s |
| 2 | <2s | +10s | 20s |
| 3 | <2s | +10s | 30s |
| ... | <2s | +10s | up to 60s |
| 7 | <2s | +30s | 1:30 |
| 8 | <2s | +30s | 2:00 |
| ... | <2s | +30s | up to 3:00 |
| 13+ | <2s | +2min | 5:00+ |

Debounce resets to 0 after 2s of no taps.

---

## Implementation Notes

- `VideoPlayerCell` is in `BrainyTubeKit` — shared across both targets
- `PlayerControlsView` is in `BrainyTubeKit` — same
- Seek thumbnail: `AVAssetImageGenerator.image(at: CMTime)` — works for both local and HTTP
- PiP: already has `PiPCoordinator` on iOS, just needs a button to trigger
- The gesture layer should be a transparent overlay on top of the video, below controls
- Speed: `AVPlayer.rate` already handles all sources
- Drag & drop: uses SwiftUI `.draggable()` / `.dropDestination()` (iOS 16+)
