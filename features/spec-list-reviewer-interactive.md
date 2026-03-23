# ListReviewer Interactive Mode — Implementation Spec

> @Sensei spec. Builds on render-only ListReviewer from PR #34. Target: shikki v1 ListReviewer v1 features (batch, smart ordering, progress persistence, scoped colors, pipe mode).

## Status

- **Base exists:** `ListReviewer.swift` (render-only enum), `TerminalInput.swift` (RawMode + KeyEvent + readKey), `KeyMode.swift` (emacs/vim/arrows InputAction mapping), `SelectionMenu.swift` (interactive arrow-key menu — reference pattern).
- **This spec adds:** interactive run loop, batch selection, action dispatch callback, progress persistence, hybrid smart ordering, scoped urgency colors, pipe mode detection.

---

## 1. TerminalInput Extensions

### 1.1 New KeyEvents

`KeyEvent` needs three additions for ListReviewer interactive mode:

```
case space          // 0x20 — batch toggle
case ctrlZ          // 0x1A — undo
case delete         // forward delete (CSI 3~)
```

Currently `0x20` falls through to `.char(" ")`. Add an explicit `space` case so consumers can pattern-match without checking `.char(" ")`. `ctrlZ` is `0x1A` (already reachable as `.char("\u{1A}")` but deserves a named case for readability). Forward delete is `ESC [ 3 ~`.

**File:** `TUI/TerminalInput.swift`

**Changes:**
- Add `case space`, `case ctrlZ`, `case delete` to `KeyEvent` enum.
- In `readKey()`, match `0x20` to `.space` and `0x1A` to `.ctrlZ`.
- In `parseEscapeSequence()`, after reading CSI, handle `3` + `~` as `.delete`. This requires reading an additional byte when the CSI parameter is a digit (currently only handles single-letter final bytes A/B/C/D).

**Migration:** Any existing code matching `.char(" ")` must also match `.space`. Add a deprecation comment. The `SelectionMenu` does not use space, so no breakage there.

### 1.2 KeyMode Extensions for ListReviewer

`InputAction` needs new cases for list-specific actions:

```
case toggleSelect   // Space — batch toggle
case undo           // Ctrl-Z
case kill           // k
case enrich         // e
case defer_         // d (trailing underscore to avoid keyword)
```

These map from the existing `ListAction.key` characters but through the `KeyMode` abstraction so that key bindings are configurable.

**File:** `TUI/KeyMode.swift`

**Changes:**
- Add `case toggleSelect, undo, kill, enrich, defer_` to `InputAction`.
- In all three key mode maps, add: `.space` -> `.toggleSelect`, `.ctrlZ` -> `.undo`.
- Single-key list actions (`k`, `e`, `d`) conflict with vim mode (`k` = prev, `j` = next). Resolution: list actions take priority when ListReviewer is active. `KeyMode.mapAction(for:context:)` gains an optional `ListContext` parameter. When context is `.listReviewer`, `k` maps to `.kill` instead of `.prev` in vim mode. Vim users navigate with `j`/arrow-down only. This is acceptable — the list is short, arrows always work.

**Alternative considered:** Separate `ListKeyMode` enum. Rejected — duplicates too much. The context parameter is cleaner.

---

## 2. Interactive Run Loop

### 2.1 Architecture

`ListReviewer` transforms from a `public enum` (namespace for static render functions) into a `public struct` that holds mutable state and runs an interactive loop. The static render functions remain as convenience entry points for non-interactive use.

```swift
public struct ListReviewer {
    // Immutable
    private let config: ListReviewerConfig
    private let keyMode: KeyMode
    private let onAction: (ListItem, ListAction) async -> ActionResult

    // Mutable state
    private var items: [ListItem]
    private var cursorIndex: Int
    private var selectedIds: Set<String>      // batch selection
    private var scrollOffset: Int             // viewport scroll
    private var progress: ListProgress        // persistence
    private var isRunning: Bool
}
```

### 2.2 The Loop

```
┌─────────────────────────────────────┐
│  1. Check isatty(STDIN_FILENO)      │
│     false → pipe mode (Section 7)   │
│     true  → continue                │
│                                     │
│  2. Load progress from disk         │
│     (resume cursorIndex, reviewed)  │
│                                     │
│  3. Enter raw mode (RawMode())      │
│  4. Hide cursor                     │
│  5. Render full frame               │
│                                     │
│  ┌─── LOOP ───────────────────────┐ │
│  │ 6. readKey()                   │ │
│  │ 7. keyMode.mapAction(for:ctx:) │ │
│  │ 8. dispatch(action)            │ │
│  │    → mutate items/cursor/sel   │ │
│  │    → call onAction if needed   │ │
│  │ 9. re-render (delta, not full) │ │
│  │10. save progress to disk       │ │
│  │    (debounced, not every key)  │ │
│  └────────────────────────────────┘ │
│                                     │
│ 11. On quit: restore terminal,      │
│     show cursor, final save         │
└─────────────────────────────────────┘
```

### 2.3 Rendering Strategy

No full-screen TUI framework. Direct ANSI cursor control, same pattern as `SelectionMenu.rerenderMenu()`:

1. **Initial render:** Print full frame from top. Record how many lines were printed (`frameHeight`).
2. **Re-render:** Move cursor up by `frameHeight` (`ESC[{N}A`), clear each line (`ESC[2K`), reprint. This avoids flicker and works inside tmux panes.
3. **Viewport:** If `items.count > terminalHeight - headerLines - footerLines`, show a scrolling window. `scrollOffset` tracks the first visible item index. Render only the visible slice. Show scroll indicators (`...N more above`, `...M more below`) in dim text.
4. **Cursor highlight:** The current item renders with `ANSIStyle.inverse` background. Selected (batch) items show a `[x]` checkbox prefix instead of `[ ]`.

### 2.4 Frame Layout

```
Line 0:   Title (bold, purple)
Line 1:   ──────────────── (separator)
Line 2:   (empty)
Line 3+:  [ 1] ○ Item title (pending)        ← normal
          [ 2] ◐ Item title (inReview)        ← cursor → inverse
          [x3] ○ Item title (pending)         ← selected (batch)
          ...
Line N:   (empty)
Line N+1: ████░░░░ 4 of 8 reviewed
Line N+2: (empty)
Line N+3: [a]pprove [k]ill [e]nrich [d]efer [Space]select [q]uit
```

The `[x3]` notation: `x` replaces the space before the number when the item is batch-selected. Compact, no extra columns.

### 2.5 ListReviewerConfig Changes

```swift
public struct ListReviewerConfig: Sendable {
    public let title: String
    public let listId: String              // NEW — for progress persistence key
    public let showProgress: Bool
    public let actions: [ListAction]
    public let keyMode: KeyMode            // NEW — default .emacs
    public let sortMode: SortMode          // NEW — .smart or .manual
    public let companyScope: String?       // NEW — for scoped urgency colors
}
```

`listId` is required. It keys the progress file. Consumers pass a stable identifier (e.g., `"inbox"`, `"backlog"`, `"review-plan"`).

---

## 3. Action Dispatch

### 3.1 The onAction Callback

```swift
public typealias ActionHandler = (ListItem, ListAction) async -> ActionResult

public enum ActionResult: Sendable {
    case success(newStatus: ListItem.ItemStatus)
    case failure(message: String)
    case noChange
}
```

When the user presses an action key (a/k/e/d or any custom `ListAction.key`):

1. Check if the action applies to the current item's status (`ListAction.appliesTo`).
2. If batch-selected items exist AND the pressed key is a batch-eligible action, iterate over all selected items and call `onAction` for each. Clear selection after batch completes.
3. If no batch, call `onAction` for the single item at `cursorIndex`.
4. On `.success(newStatus:)` — update the item's status in the local array, advance cursor to next unreviewed item.
5. On `.failure(message:)` — flash the message in a status line (bottom of frame, red, clears after next keypress).
6. On `.noChange` — do nothing (useful for "enrich" which opens an external editor and the status doesn't change).

### 3.2 Batch Action Flow

```
User presses Space on items 2, 4, 6 → selectedIds = {"2", "4", "6"}
User presses 'a' (approve)
→ for each id in selectedIds (order: by current sort):
    call onAction(item, .approve) async
    update item status on success
→ clear selectedIds
→ re-render with updated statuses
→ flash "3 items approved" in status line
```

Batch actions are sequential (not parallel) to avoid race conditions in the consumer's callback. Each call awaits before the next.

### 3.3 ListAction Extensions

`ListAction` needs a `batchable: Bool` property. Default `true` for approve, kill, defer. Default `false` for enrich (enrich is item-specific context). The `next` and `quit` meta-actions are never batchable.

```swift
public struct ListAction: Sendable {
    public let key: Character
    public let label: String
    public let appliesTo: Set<ListItem.ItemStatus>
    public let batchable: Bool  // NEW — default true
}
```

---

## 4. Progress Persistence

### 4.1 Data Model

```swift
public struct ListProgress: Codable, Sendable {
    public let listId: String
    public var reviewedItemIds: [String]
    public var pinnedOrder: [String]    // item IDs in user-defined order
    public var lastIndex: Int
    public var lastUpdated: Date
}
```

### 4.2 Storage

**File:** `~/.config/shiki/list-progress.json`

Format: JSON dictionary keyed by `listId`:

```json
{
  "inbox": {
    "listId": "inbox",
    "reviewedItemIds": ["pr-27", "pr-28"],
    "pinnedOrder": ["pr-29"],
    "lastIndex": 2,
    "lastUpdated": "2026-03-23T14:30:00Z"
  },
  "backlog": { ... }
}
```

### 4.3 ListProgressStore

```swift
public struct ListProgressStore {
    private let filePath: URL   // ~/.config/shiki/list-progress.json

    public init(filePath: URL? = nil)   // nil = default path
    public func load(listId: String) -> ListProgress?
    public func save(_ progress: ListProgress)
    public func clear(listId: String)
}
```

**Behavior:**
- `load()` reads file, decodes, returns entry for `listId`. Returns `nil` if file missing or entry absent. Never throws — graceful degradation.
- `save()` reads existing file (or empty dict), upserts entry, writes atomically (write to temp, rename). Sets `lastUpdated` to now.
- Save is **debounced**: the run loop calls `markDirty()` on state change. A 2-second timer flushes to disk. Quit always flushes immediately.
- Directory creation: `save()` creates `~/.config/shiki/` if missing.

### 4.4 Resume Behavior

On `ListReviewer.run()`:
1. Load progress for `config.listId`.
2. If progress exists and `lastIndex` is within bounds, set `cursorIndex = lastIndex`.
3. Mark items whose IDs appear in `reviewedItemIds` as already reviewed (skip them during auto-advance).
4. Apply `pinnedOrder` to item sort (see Section 5).

---

## 5. Hybrid Smart Ordering

### 5.1 SortMode

```swift
public enum SortMode: String, Sendable {
    case smart      // composite score, pins override
    case manual     // user-defined order only (pinnedOrder from progress)
    case raw        // items as provided, no reordering
}
```

`--sort smart` (default), `--sort manual`, `--sort raw` (for pipe consumers).

### 5.2 Composite Score

```swift
public struct ItemScore: Comparable {
    public let isPinned: Bool       // user pin — always wins
    public let pinnedRank: Int      // position in pinnedOrder (0 = top)
    public let priorityWeight: Int  // from metadata["priority"] — P0=100, P1=75, P2=50, P3=25
    public let ageWeight: Int       // hours since creation, capped at 168 (1 week)
    public let depsWeight: Int      // number of items blocked by this one
    public let blockingWeight: Int  // 50 if this blocks a P0 item, else 0

    public var composite: Int       // priorityWeight + ageWeight + depsWeight + blockingWeight
}
```

Sorting: pinned items first (by `pinnedRank`), then unpinned items descending by `composite`. Items with equal composite maintain their original order (stable sort).

### 5.3 Pin/Unpin

New action key: `p` = pin/unpin toggle. Pinned items get a `^` indicator after the number:

```
[ 1]^ ○ High priority thing     ← pinned to top
[ 2]  ◐ Normal item
```

Pin order is the order in which the user pins them. First pinned = top. Re-pinning an already-pinned item unpins it (toggle).

Pins are persisted in `ListProgress.pinnedOrder`.

### 5.4 Score Computation

The score is computed by `ListReviewer` at startup and after any status change. Consumers provide scoring metadata through `ListItem.metadata`:

- `metadata["priority"]` — "P0", "P1", "P2", "P3" (string, parsed to weight)
- `metadata["created"]` — ISO8601 date string (for age)
- `metadata["blocks"]` — comma-separated item IDs this item blocks
- `metadata["company"]` — company scope identifier

The scorer is a pure function: `func computeScores(items: [ListItem], pins: [String]) -> [(ListItem, ItemScore)]`. Testable without terminal.

---

## 6. Scoped Urgency Colors

### 6.1 UrgencyLevel

```swift
public enum UrgencyLevel: Sendable {
    case critical   // red — blocking within scope
    case aging      // yellow — past scope cadence
    case ready      // green — actionable
    case deferred   // dim — explicitly deferred
}
```

### 6.2 Scope-Relative Coloring

Urgency is relative to the company/project scope, not global. A maya P1 blocking 3 other maya items is `critical` within maya, but a kintsugi P1 with no blockers is just `ready`.

```swift
public struct UrgencyCalculator {
    /// Compute urgency for an item relative to its scope peers.
    public static func urgency(
        for item: ListItem,
        withinScope items: [ListItem]
    ) -> UrgencyLevel
}
```

Rules:
- `critical` — item has `blocks` metadata pointing to items that are also in the scope AND those blocked items are P0/P1.
- `aging` — item age exceeds scope cadence threshold. Default cadence: 48h for P0, 96h for P1, 168h for P2. Configurable per scope later.
- `deferred` — item status is `.pending` AND has metadata `deferred: true`.
- `ready` — everything else that is actionable (pending or inReview).

### 6.3 Grouped Display

When no `--company` filter is applied, `shikki inbox` groups items by company:

```
Shikki Inbox                          4 items
──────────────────────────────────────
  maya (2)
  [ 1] ○ Fix geo-discovery crash       ← red (critical in maya scope)
  [ 2] ○ Add family accounts           ← green (ready in maya scope)

  shikki (1)
  [ 3] ◐ ListReviewer interactive      ← yellow (aging in shikki scope)

  kintsugi (1)
  [ 4] ○ Token export CLI              ← green (ready in kintsugi scope)

████████░░░░░░░░░░░░ 0 of 4 reviewed
```

Company headers are styled with `.bold` and use the company's scope color (configurable in metadata, default `.white`). Items within a group are sorted by their scoped composite score.

### 6.4 Color Assignment

Urgency maps to existing `ANSIStyle`:
- `critical` -> `.red`
- `aging` -> `.yellow`
- `ready` -> `.green`
- `deferred` -> `.dim`

This overrides `ItemStatus.style` when urgency coloring is active. The status indicator (circle/check/cross) keeps its own color; the item title text gets urgency color.

---

## 7. Pipe Mode

### 7.1 Detection

```swift
let isTTY = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
```

If either stdin or stdout is not a TTY, ListReviewer enters pipe mode. No interactive loop, no raw mode, no ANSI codes.

### 7.2 Output Formats

**JSON mode** (`--json`):
```json
{
  "title": "Shikki Inbox",
  "items": [
    {"id": "pr-27", "title": "...", "status": "pending", "company": "maya", "urgency": "critical"}
  ],
  "progress": {"reviewed": 2, "total": 8}
}
```

**Count mode** (`--count`):
Outputs a single integer to stdout: `4\n`. For scripting: `if [ $(shikki inbox --count) -gt 0 ]; then ...`.

**Plain mode** (default pipe, no flag):
Same as `renderToString()` but with `stripANSI()` applied. Readable in logs, email, etc.

### 7.3 Implementation

```swift
public enum PipeOutput {
    public static func json(items: [ListItem], config: ListReviewerConfig) -> String
    public static func count(items: [ListItem]) -> String
    public static func plain(items: [ListItem], config: ListReviewerConfig) -> String
}
```

The `ListReviewer.run()` entry point checks TTY first. If pipe mode, it calls the appropriate `PipeOutput` function and returns immediately (no loop). The `onAction` callback is never called in pipe mode.

---

## 8. Action Callback Protocol

### 8.1 Public API

```swift
public struct ListReviewer {

    /// Run the interactive list reviewer.
    /// Returns when the user quits or all items are reviewed.
    public mutating func run() async -> ListReviewerResult
}

public struct ListReviewerResult: Sendable {
    public let reviewedCount: Int
    public let totalCount: Int
    public let actions: [(itemId: String, action: String, result: ActionResult)]
}
```

### 8.2 Consumer Example (inbox command)

```swift
let reviewer = ListReviewer(
    items: inboxItems,
    config: ListReviewerConfig(
        title: "Shikki Inbox",
        listId: "inbox",
        showProgress: true,
        actions: ListAction.defaults,
        keyMode: .emacs,
        sortMode: .smart,
        companyScope: nil  // show all companies grouped
    ),
    onAction: { item, action async in
        switch action.label {
        case "approve":
            await inboxService.approve(item.id)
            return .success(newStatus: .validated)
        case "kill":
            await inboxService.kill(item.id)
            return .success(newStatus: .killed)
        case "defer":
            await inboxService.defer(item.id)
            return .noChange
        default:
            return .noChange
        }
    }
)
var mutableReviewer = reviewer
let result = await mutableReviewer.run()
```

---

## Files to Create/Modify

### New Files

| File | Purpose | Est. LOC |
|------|---------|----------|
| `TUI/ListReviewerInteractive.swift` | Interactive run loop, rendering, batch, scroll | ~320 |
| `TUI/ListProgressStore.swift` | Progress persistence (read/write JSON) | ~90 |
| `TUI/ItemScorer.swift` | Composite scoring + sort | ~80 |
| `TUI/UrgencyCalculator.swift` | Scoped urgency level computation | ~60 |
| `TUI/PipeOutput.swift` | JSON/count/plain pipe output | ~70 |
| `Tests/ListReviewerInteractiveTests.swift` | Interactive logic tests (no real terminal) | ~200 |
| `Tests/ListProgressStoreTests.swift` | Persistence round-trip tests | ~80 |
| `Tests/ItemScorerTests.swift` | Scoring + sort order tests | ~90 |
| `Tests/UrgencyCalculatorTests.swift` | Scoped urgency tests | ~60 |
| `Tests/PipeOutputTests.swift` | JSON/count/plain output tests | ~50 |

### Modified Files

| File | Changes | Est. LOC delta |
|------|---------|----------------|
| `TUI/TerminalInput.swift` | Add `.space`, `.ctrlZ`, `.delete` to `KeyEvent`; update `readKey()` and `parseEscapeSequence()` | +25 |
| `TUI/KeyMode.swift` | Add `toggleSelect`, `undo`, `kill`, `enrich`, `defer_` to `InputAction`; add context-aware mapping | +40 |
| `TUI/ListReviewer.swift` | Refactor from `enum` to `struct`; keep static render functions as convenience wrappers calling instance methods | +30, -10 net +20 |
| `TUI/ANSIStyle.swift` | No changes needed — existing styles sufficient | 0 |
| `TUI/TerminalOutput.swift` | No changes needed — existing cursor/clear functions sufficient | 0 |
| `Tests/ListReviewerTests.swift` | Update for enum-to-struct migration (static functions stay, so minimal) | +5 |

### Totals

| Category | LOC |
|----------|-----|
| New production code | ~620 |
| Modified production code | ~85 |
| New test code | ~480 |
| Modified test code | ~5 |
| **Total** | **~1,190** |

---

## Testing Strategy

All interactive logic is testable without a real terminal by injecting dependencies:

### 1. KeySource Protocol

```swift
public protocol KeySource: Sendable {
    func readKey() -> KeyEvent
}
```

`TerminalInput` conforms. Tests inject `MockKeySource` with a predefined sequence of key events.

### 2. OutputSink Protocol

```swift
public protocol OutputSink: Sendable {
    func write(_ string: String)
}
```

Production uses `StdoutSink` (prints to stdout). Tests use `BufferSink` that captures output into a string array.

### 3. ListReviewer DI

```swift
public struct ListReviewer {
    // Production initializer (uses real terminal)
    public init(items: [ListItem], config: ListReviewerConfig, onAction: ...)

    // Testable initializer (injected dependencies)
    init(items: [ListItem], config: ListReviewerConfig, onAction: ...,
         keySource: KeySource, outputSink: OutputSink, progressStore: ListProgressStore)
}
```

### 4. Test Cases

**ListReviewerInteractiveTests (17 tests):**
- `cursorMovesDownOnArrowDown` — feed `.down`, assert cursorIndex incremented
- `cursorStopsAtBottom` — feed N `.down` events past end, cursor stays at last
- `cursorWrapsWithinViewport` — scroll offset adjusts when cursor exits visible range
- `spaceTogglesSelection` — feed `.space`, assert item ID in `selectedIds`
- `doubleSpaceDeselectsItem` — feed `.space` twice on same item, assert removed
- `batchApproveCallsOnActionForAllSelected` — select 3 items, press `a`, assert 3 onAction calls
- `batchSkipsNonApplicableItems` — select mix of pending+validated, approve, assert only pending items get callback
- `actionResultSuccessUpdatesStatus` — return `.success(.validated)`, assert item status changed
- `actionResultFailureShowsMessage` — return `.failure("oops")`, assert message in output
- `cursorAdvancesToNextUnreviewedAfterAction` — approve item 2 of 5, cursor moves to item 3
- `quitExitsLoop` — feed `q`, assert `run()` returns
- `escapeExitsLoop` — feed `.escape`, assert `run()` returns
- `unknownKeyIsIgnored` — feed `.unknown`, assert no state change
- `pinTogglesPinnedState` — feed `p`, assert item in pinnedOrder
- `pinnedItemsSortFirst` — pin item 3, re-sort, assert item 3 is at index 0
- `viewportScrollsWhenCursorExceedsBounds` — 50 items, terminal height 10, cursor at 12, assert scrollOffset adjusted
- `resultReportsCorrectCounts` — run through several actions, assert `ListReviewerResult` fields

**ListProgressStoreTests (7 tests):**
- `saveAndLoadRoundTrip` — save progress, load it back, assert equality
- `loadMissingFileReturnsNil` — no file on disk, returns nil
- `loadMissingListIdReturnsNil` — file exists but different listId
- `saveCreatesDirectoryIfMissing` — assert directory created
- `savePreservesOtherEntries` — save listId "a", save listId "b", load "a" still intact
- `clearRemovesEntry` — save then clear, load returns nil
- `atomicWriteSurvivesCrash` — write to temp file path, verify no partial writes (check file either has old or new content)

**ItemScorerTests (8 tests):**
- `p0HigherThanP1` — P0 item scores above P1
- `olderItemScoresHigher` — 72h old > 1h old (same priority)
- `blockingItemScoresHigher` — item blocking a P0 gets +50
- `pinnedItemAlwaysFirst` — pinned P3 sorts above unpinned P0
- `pinnedOrderIsRespected` — first pinned item sorts above second pinned item
- `stableSortOnEqualScore` — items with identical scores maintain original order
- `manualModeUsesOnlyPins` — sortMode .manual, unpinned items keep original order
- `rawModeNoReorder` — sortMode .raw, items stay as provided

**UrgencyCalculatorTests (5 tests):**
- `blockingP0IsCritical` — item blocking a P0 peer = critical
- `agedP1IsAging` — P1 item older than 96h = aging
- `freshP2IsReady` — P2 item created 1h ago = ready
- `deferredItemIsDim` — metadata deferred:true = deferred
- `urgencyIsScopeRelative` — same item is critical in scope A (blocks P0 there) but ready in scope B (no blockers)

**PipeOutputTests (4 tests):**
- `jsonOutputIsValidJSON` — parse output, assert structure
- `countOutputIsSingleNumber` — assert output matches `^\d+\n$`
- `plainOutputHasNoANSI` — assert no ESC codes in output
- `jsonIncludesUrgencyField` — assert urgency key present per item

**Total: 41 tests.**

---

## Implementation Order

1. **Wave 1 — Foundation (no interactive yet)**
   - `TerminalInput.swift` KeyEvent additions
   - `KeyMode.swift` InputAction additions
   - `ListProgressStore.swift` + tests
   - `ItemScorer.swift` + tests
   - `UrgencyCalculator.swift` + tests

2. **Wave 2 — Interactive Loop**
   - Refactor `ListReviewer.swift` enum -> struct
   - `ListReviewerInteractive.swift` (run loop, rendering, cursor, scroll)
   - `KeySource`/`OutputSink` protocols for testability
   - Interactive tests (cursor, navigation, quit)

3. **Wave 3 — Batch + Actions + Persistence**
   - Batch selection (Space toggle, visual indicator)
   - Action dispatch (onAction callback, ActionResult handling)
   - Progress save/load integration
   - Pin/unpin
   - Batch + action + persistence tests

4. **Wave 4 — Polish**
   - `PipeOutput.swift` + tests
   - Scoped urgency coloring in render
   - Grouped company display
   - Status line (flash messages)
   - Update `ListReviewerTests.swift` for struct migration

---

## Constraints and Decisions

1. **No curses/ncurses.** Direct ANSI escape codes only. Keeps the binary portable with zero C library dependencies beyond libc.
2. **No async readKey.** `TerminalInput.readKey()` blocks. The run loop is synchronous on the main thread. `onAction` is `async` (the callback may do network/DB calls), but the loop itself awaits inline. This is fine — the user is waiting for their action to complete before pressing the next key.
3. **No undo in v1.** `ctrlZ` is parsed and the `InputAction.undo` case exists, but the run loop ignores it with a "undo coming in v1.1" flash message. Undo requires a command stack, which is out of scope for v1 (see flow spec: undo is v1.1).
4. **Struct, not class.** `ListReviewer` is a value type. The `run()` method is `mutating`. Callers use `var reviewer = ...` then `await reviewer.run()`. No reference semantics, no shared mutable state.
5. **Progress file, not DB.** Local JSON file as specified in the flow spec. No ShikiDB dependency for progress. Keeps ListReviewer usable even when the backend is down.
6. **Scoring metadata is stringly typed.** `ListItem.metadata` is `[String: String]`. The scorer parses `"P0"` to `100`, `"2026-03-23T..."` to a Date. This avoids adding typed fields to `ListItem` that not all consumers need. If this becomes a pain point, add a `ListItemScoring` protocol later.

---

## Dependencies

- **Upstream:** None. ListReviewer is a leaf component — it depends only on Foundation and the existing TUI primitives (`TerminalInput`, `TerminalOutput`, `ANSIStyle`, `KeyMode`).
- **Downstream consumers (not part of this spec):** `shikki inbox`, `shikki backlog`, `shikki decide`, `shikki review-plan`. Each command creates a `ListReviewer` with its own `config` and `onAction` callback.
