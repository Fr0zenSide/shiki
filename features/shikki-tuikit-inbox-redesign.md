---
title: "TUIKit Component System + Theme Engine + Inbox Redesign"
status: draft
priority: P0
project: shikki
created: 2026-04-03
authors: ["@Daimyo"]
tags: [tui, theme, base16, inbox, components, dracula]
depends-on: []
relates-to: [shikki-quality-gates.md]
epic-branch: feature/tuikit-inbox-redesign
validated-commit: —
test-run-id: —
---

# Feature: TUIKit Component System + Theme Engine + Inbox Redesign
> Created: 2026-04-03 | Status: Draft | Owner: @Daimyo

## Context

Every renderer reimplements the same primitives: DashboardRenderer has box-drawing, ChatRenderer has box-drawing, TUIReportRenderer has padding, ProjectStatusFormatter defines Dracula inline, SplashRenderer defines Dracula inline again. InboxCommand is the worst — raw 8-color ANSI, no structure, no theming, no alignment. Meanwhile, the terminal ecosystem has a universal theme standard: **Base16** — 16 named color slots (base00-base0F), YAML format, 200+ schemes on GitHub (Dracula, Catppuccin, Tokyo Night, Solarized, etc.). Users already have theme files for bat, Emacs, Alacritty, iTerm. We should load those, not hardcode colors.

## Architecture Decision: 3-Target DSKintsugi

The kintsugi-ds package splits into 3 independent layers. Core is pure data (tokens + themes). TUI and SwiftUI are parallel rendering targets that both depend on Core but never on each other.

```
DSKintsugiCore    ← pure Swift, NO platform deps (Linux + macOS + iOS + visionOS)
  └── TUI/Theme/  — Base16 engine, TUITheme, BuiltInThemes, ThemeLoader, semantic roles

DSKintsugiTUI     ← terminal rendering, depends on Core
  ├── ANSI/       — TerminalOutput, stripANSI, truecolor detection
  └── Components/ — Box, Table, Badge, Bar, List, Pager

DSKintsugi        ← SwiftUI layer (iOS 16+ / macOS 13+ / visionOS 1+), depends on Core
  ├── Components/ — Toast, ViewModifiers
  ├── Generated/  — WSColors, WSSpacing, WSTypography
  └── Theme/      — WabiSabiTheme, environment injection

DSKintsugiGallery ← SwiftUI gallery (depends on DSKintsugi)
```

**Dependency graph:**
```
                  ┌──────────────────┐
                  │  DSKintsugiCore  │  ← tokens + themes (pure Swift)
                  └────────┬─────────┘
                     ┌─────┴─────┐
                     ▼           ▼
            ┌────────────┐ ┌──────────┐
            │ DSKintsugiTUI │ │ DSKintsugi │  ← TUI and SwiftUI are PEERS
            └────────────┘ └─────┬────┘
                                 ▼
                        ┌────────────────┐
                        │DSKintsugiGallery│
                        └────────────────┘
```

**Who imports what:**
- **CLI tools** (shikki, brainy, moto) → `import DSKintsugiTUI` (gets Core via `@_exported`)
- **iOS/macOS apps** (WabiSabi, Maya) → `import DSKintsugi` (gets Core via dependency)
- **Both** share the same theme tokens from Core — one source of truth
- **Future targets**: DSKintsugiUIKit, DSKintsugiCompose, DSKintsugiWeb — all depend only on Core

### Implemented Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DSKintsugi",
    platforms: [.iOS(.v16), .macOS(.v13), .visionOS(.v1)],
    products: [
        .library(name: "DSKintsugiCore", targets: ["DSKintsugiCore"]),
        .library(name: "DSKintsugiTUI", targets: ["DSKintsugiTUI"]),
        .library(name: "DSKintsugi", targets: ["DSKintsugi"]),
        .library(name: "DSKintsugiGallery", targets: ["DSKintsugiGallery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        // Core: tokens + themes (pure Swift, zero deps)
        .target(name: "DSKintsugiCore", path: "Sources/DSKintsugiCore"),
        // TUI: terminal rendering (depends on Core)
        .target(name: "DSKintsugiTUI", dependencies: ["DSKintsugiCore"], path: "Sources/DSKintsugiTUI"),
        // SwiftUI: app UI layer (depends on Core)
        .target(name: "DSKintsugi", dependencies: ["DSKintsugiCore"], path: "Sources/DSKintsugi"),
        // Gallery: SwiftUI visual testing
        .target(name: "DSKintsugiGallery", dependencies: ["DSKintsugi"], path: "Sources/DSKintsugiGallery"),
        // Tests
        .testTarget(name: "DSKintsugiCoreTests", dependencies: ["DSKintsugiCore"], path: "Tests/DSKintsugiCoreTests"),
        .testTarget(name: "DSKintsugiTUITests", dependencies: ["DSKintsugiTUI"], path: "Tests/DSKintsugiTUITests"),
        .testTarget(name: "DSKintsugiTests", dependencies: ["DSKintsugi", "DSKintsugiGallery",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing")], path: "Tests/DSKintsugiTests"),
    ]
)
```

### ShikkiKit Dependency Change

```swift
// In shikki Package.swift — import TUI layer (gets Core via @_exported)
.target(
    name: "ShikkiKit",
    dependencies: [
        .product(name: "DSKintsugiTUI", package: "kintsugi-ds"),
        // ... other deps
    ]
)
```

## Business Rules

```
BR-01: TUITheme MUST use the Base16 color scheme format — 16 slots (base00-base0F) as hex RGB strings
BR-02: Theme files MUST be YAML, loadable from ~/.shikki/themes/<name>.yaml (Base16 scheme format)
BR-02b: ThemeLoader MUST auto-scan ~/.shikki/themes/ at startup — every .yaml file is a theme, no registration needed
BR-02c: Theme name MUST be derived from: (1) `scheme:` field inside YAML if present, otherwise (2) filename without extension
BR-03: Active theme MUST be set via ~/.shikki/config.yaml key `theme: <name>` (default: "dracula")
BR-04: Shikki MUST ship 3 built-in themes: dracula, catppuccin-mocha, tokyo-night (compiled in, no file needed)
BR-05: TUITheme MUST map Base16 slots to semantic roles: error (base08), warning (base0A), success (base0B), info (base0D), accent (base0E), dim (base03), fg (base05), bg (base00)
BR-06: All TUI components MUST accept a theme parameter, defaulting to TUITheme.active
BR-06b: Theme engine and TUI components MUST live in DSKintsugiCore (platform-agnostic SPM target in kintsugi-ds package)
BR-06c: ShikkiKit MUST depend on DSKintsugiCore for all TUI rendering — no inline ANSI in ShikkiKit
BR-07: TUITheme MUST provide both 24-bit RGB and 8-color ANSI fallback per slot
BR-08: COLORTERM env var MUST be checked — use 24-bit when "truecolor" or "24bit", otherwise 8-color fallback
BR-09: Box component MUST render bordered panels with title, configurable border style (light/heavy/double/rounded)
BR-10: Table component MUST render headers, rows, column alignment (left/right/center), ANSI-aware padding
BR-11: Badge component MUST render fixed-width (4 chars visible) colored type tags
BR-12: Bar component MUST render horizontal urgency/progress visualization with theme-aware gradient
BR-13: List component MUST render grouped items with section headers and dimmed separators
BR-14: Pager MUST auto-pipe through `bat --style=plain --paging=always -l c3` (with matching theme name) or `less -R` when output exceeds terminal height. c3 = compact colored columns
BR-15: Inbox MUST be redesigned: grouped by urgency zone (hot/warm/cool), table layout, badges, urgency bars
BR-16: --plain flag MUST strip all ANSI and replace box chars with ASCII (+ - |) for piping
BR-17: Terminal width-responsive layout — tables MUST adapt to narrow terminals (< 80 cols)
BR-18: All existing renderers MUST still compile — TUIKit is additive, not breaking
BR-19: On theme change, MUST auto-generate `shikki-active.tmTheme` from Base16 colors into `$(bat --config-dir)/themes/` and run `bat cache --build`. TUIPager always uses `--theme=shikki-active` — no name matching needed
BR-19b: tmTheme generation MUST be skipped if bat is not installed (no-op)
BR-19c: Generated tmTheme MUST have header comment `<!-- Auto-generated by shikki -->` — skip generation if file exists without this header (user hand-crafted)
BR-20: shi theme list MUST show available themes (built-in + ~/.shikki/themes/) with preview swatch
BR-21: shi theme set <name> MUST update ~/.shikki/config.yaml and print confirmation with new colors
```

## TDDP — Test Summary Table

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01 | Core (80%) | Unit | When loading Base16 YAML → 16 slots parsed |
| T-02 | BR-02 | Core (80%) | Unit | When theme file at ~/.shikki/themes/ → loaded by name |
| T-03 | BR-03 | Core (80%) | Unit | When config says theme: catppuccin-mocha → that theme active |
| T-04 | BR-04 | Core (80%) | Unit | When no config and no file → dracula built-in used |
| T-05 | BR-05 | Core (80%) | Unit | When accessing semantic role .error → maps to base08 |
| T-06 | BR-07, BR-08 | Core (80%) | Unit | When COLORTERM=truecolor → 24-bit codes emitted |
| T-07 | BR-07, BR-08 | Core (80%) | Unit | When COLORTERM unset → 8-color fallback emitted |
| T-08 | BR-09 | Core (80%) | Unit | When rendering TUIBox with title → bordered panel output |
| T-09 | BR-09 | Core (80%) | Unit | When rendering TUIBox with .rounded → rounded corners used |
| T-10 | BR-09 | Core (80%) | Unit | When terminal width < box width → content truncated |
| T-11 | BR-10 | Core (80%) | Unit | When rendering TUITable → aligned columns with headers |
| T-12 | BR-10 | Core (80%) | Unit | When cell contains ANSI → column width uses visible length |
| T-13 | BR-10 | Core (80%) | Unit | When column is .right aligned → numbers right-padded |
| T-14 | BR-10, BR-17 | Core (80%) | Unit | When terminal < total column width → last column truncated |
| T-15 | BR-11 | Core (80%) | Unit | When rendering TUIBadge("SP") → 4 chars visible, themed |
| T-16 | BR-11 | Core (80%) | Unit | When badge type is .spec → uses theme.accent color |
| T-17 | BR-12 | Core (80%) | Unit | When urgency 80 → bar in theme.error color |
| T-18 | BR-12 | Core (80%) | Unit | When urgency 20 → bar in theme.success color |
| T-19 | BR-13 | Core (80%) | Unit | When rendering grouped list → section headers bold |
| T-20 | BR-13 | Core (80%) | Unit | When 3 groups → dim separator between each, none at edges |
| T-21 | BR-14 | Smoke (CLI) | Unit | When output > terminal height and bat installed → pipes to bat |
| T-22 | BR-14, BR-19 | Smoke (CLI) | Unit | When theme is dracula → bat gets --theme=Dracula |
| T-23 | BR-14 | Smoke (CLI) | Unit | When output fits terminal → prints directly, no pager |
| T-24 | BR-15 | Core (80%) | Unit | When inbox has mixed scores → grouped into 3 urgency zones |
| T-25 | BR-15 | Core (80%) | Unit | When inbox rendered → header box with item counts |
| T-26 | BR-15 | Core (80%) | Unit | When inbox row rendered → badge + bar + title + project + age |
| T-27 | BR-15 | Core (80%) | Unit | When inbox rendered → footer with filter hints |
| T-28 | BR-16 | Core (80%) | Unit | When --plain → no ANSI codes, ASCII box chars |
| T-29 | BR-01 | Core (80%) | Unit | When stripANSI on 24-bit codes → clean text returned |
| T-30 | BR-20 | Smoke (CLI) | Integration | When shi theme list → shows built-in + user themes |
| T-31 | BR-21 | Smoke (CLI) | Integration | When shi theme set tokyo-night → config updated |

### S3 Test Scenarios

```
T-01 [BR-01, Core 80%]:
When loading a Base16 YAML file:
  if file contains base00 through base0F as 6-char hex strings:
    → returns TUITheme with 16 color slots populated
    → base00 = "282a36" parsed as RGB(40, 42, 54)
  if file is missing base0D:
    → throws ThemeError.missingSlot("base0D")
  if hex value is invalid ("ZZZZZZ"):
    → throws ThemeError.invalidHex("ZZZZZZ")

T-02 [BR-02, BR-02b, BR-02c, Core 80%]:
When ThemeLoader scans ~/.shikki/themes/:
  if folder contains solarized-dark.yaml and gruvbox.yaml:
    → both themes available by name
  if solarized-dark.yaml has `scheme: "Solarized Dark"` inside:
    → theme name is "Solarized Dark" (from file), slug is "solarized-dark" (from filename)
  if gruvbox.yaml has no `scheme:` field:
    → theme name is "gruvbox" (derived from filename without extension)
  if requesting a name that matches no built-in and no file:
    → throws ThemeError.notFound("unknown-theme")

T-03 [BR-03, Core 80%]:
When ~/.shikki/config.yaml contains `theme: catppuccin-mocha`:
  → TUITheme.active returns the catppuccin-mocha theme
  if config file does not exist:
    → TUITheme.active returns dracula (default)
  if config file exists but has no theme key:
    → TUITheme.active returns dracula (default)

T-04 [BR-04, Core 80%]:
When requesting built-in theme "dracula":
  → returns theme without any file I/O
  → base00 == "282a36", base05 == "f8f8f2", base0E == "bd93f9"
When requesting built-in theme "catppuccin-mocha":
  → base00 == "1e1e2e", base0E == "cba6f7"
When requesting built-in theme "tokyo-night":
  → base00 == "1a1b26", base0E == "bb9af7"

T-05 [BR-05, Core 80%]:
When accessing semantic roles on a loaded theme:
  → theme.error returns base08 color (red accent)
  → theme.warning returns base0A color (yellow)
  → theme.success returns base0B color (green)
  → theme.info returns base0D color (blue)
  → theme.accent returns base0E color (purple/magenta)
  → theme.dim returns base03 color (comment gray)
  → theme.fg returns base05 color (foreground)
  → theme.bg returns base00 color (background)

T-06 [BR-07, BR-08, Core 80%]:
When COLORTERM is "truecolor" or "24bit":
  → theme.error.ansi returns "\u{1B}[38;2;255;85;85m" (24-bit RGB)
  → theme.accent.ansi returns "\u{1B}[38;2;189;147;249m"
When COLORTERM is "truecolor":
  → theme.error.ansiBg returns "\u{1B}[48;2;255;85;85m" (background variant)

T-07 [BR-07, BR-08, Core 80%]:
When COLORTERM is unset or empty:
  → theme.error.ansi returns "\u{1B}[31m" (basic red)
  → theme.accent.ansi returns "\u{1B}[35m" (basic magenta)
  → theme.success.ansi returns "\u{1B}[32m" (basic green)

T-08 [BR-09, Core 80%]:
When rendering TUIBox(title: "Inbox", width: 40, style: .rounded, theme: theme):
  → first line starts with "╭─" and contains themed title and ends with "╮"
  → last line starts with "╰" and ends with "╯"
  → content lines start with "│ " and end with " │"
  → title is colored with theme.accent

T-09 [BR-09, Core 80%]:
When rendering TUIBox with style:
  if .light   → borders use ┌ ┐ └ ┘ │ ─
  if .heavy   → borders use ┏ ┓ ┗ ┛ ┃ ━
  if .double  → borders use ╔ ╗ ╚ ╝ ║ ═
  if .rounded → borders use ╭ ╮ ╰ ╯ │ ─

T-10 [BR-09, Core 80%]:
When terminal width is 50 and box content is wider:
  → box renders at 50 columns
  → content lines truncated with "…" before right border

T-11 [BR-10, Core 80%]:
When rendering TUITable with columns ["Type", "Score", "Title"] and 2 rows:
  → headers are bold (theme.fg + bold)
  → separator line "───" follows headers
  → each column padded to max content width + 2 gutter

T-12 [BR-10, Core 80%]:
When a table cell contains ANSI-styled text:
  → column width calculated from visible length, not raw string length
  → "\u{1B}[38;2;189;147;249mSP\u{1B}[0m" has visible length 2, not 26

T-13 [BR-10, Core 80%]:
When column alignment is .right:
  → values ["50", "5", "100"] render as " 50", "  5", "100" (right-padded within column)

T-14 [BR-10, BR-17, Core 80%]:
When terminal width is 80 and 5 columns total 120 chars:
  → last column truncated with "…"
  → total visible width does not exceed 80

T-15 [BR-11, Core 80%]:
When rendering TUIBadge("SP", role: .accent):
  → output is 4 chars visible: " SP " with theme.accent color
When rendering TUIBadge("PR", role: .success):
  → output is 4 chars visible: " PR " with theme.success color

T-16 [BR-11, Core 80%]:
When mapping InboxItem.ItemType to badge role:
  → .spec uses .accent (base0E — purple)
  → .pr uses .success (base0B — green)
  → .decision uses .warning (base0A — yellow/orange)
  → .task uses .info (base0D — blue/cyan)
  → .gate uses .error (base08 — red)

T-17 [BR-12, Core 80%]:
When rendering TUIBar(value: 80, max: 100, width: 8):
  → 6 filled blocks + 2 empty blocks
  → filled blocks colored with theme.error (high urgency)

T-18 [BR-12, Core 80%]:
When rendering TUIBar(value: 20, max: 100, width: 8):
  → 2 filled blocks + 6 empty blocks
  → filled blocks colored with theme.success (low urgency)

T-19 [BR-13, Core 80%]:
When rendering TUIList with groups [("Hot", items), ("Warm", items)]:
  → "Hot" header is bold with theme.error color
  → "Warm" header is bold with theme.warning color
  → items indented under their group

T-20 [BR-13, Core 80%]:
When rendering TUIList with 3 groups:
  → dim "─" separator between group 1 and 2
  → dim "─" separator between group 2 and 3
  → no separator before group 1 or after group 3

T-21 [BR-14, Smoke CLI]:
When output is 60 lines and terminal height is 40:
  if bat is installed:
    → output piped to bat --style=plain --paging=always
  otherwise:
    → output piped to less -R

T-22 [BR-14, BR-19, BR-19b, BR-19c, Smoke CLI]:
When shi theme set dracula is called:
  if bat is installed:
    → generates shikki-active.tmTheme from dracula Base16 colors
    → writes to $(bat --config-dir)/themes/shikki-active.tmTheme
    → file starts with "<!-- Auto-generated by shikki -->"
    → runs bat cache --build
  if bat is not installed:
    → tmTheme generation skipped (no error)
When paging through bat:
  → bat always receives --theme=shikki-active
When shikki-active.tmTheme exists without auto-generated header:
  → skip generation (user owns the file)
  → bat still receives --theme=shikki-active

T-23 [BR-14, Smoke CLI]:
When output is 10 lines and terminal height is 40:
  → output printed directly to stdout
  → no pager subprocess spawned

T-24 [BR-15, Core 80%]:
When inbox contains items with scores [80, 75, 50, 45, 20, 10]:
  → 2 items under "Hot (70+)" section, colored theme.error
  → 2 items under "Active (40-69)" section, colored theme.warning
  → 2 items under "Queued (<40)" section, colored theme.success
  if a section has 0 items:
    → that section is omitted entirely

T-25 [BR-15, Core 80%]:
When inbox has 20 items (3 PR, 5 SP, 2 DC, 8 TK, 2 GT):
  → header box (rounded style) shows:
    "20 items │ PR:3 SP:5 DC:2 TK:8 GT:2"
  → title "Inbox" colored with theme.accent

T-26 [BR-15, Core 80%]:
When rendering an inbox row for type=.spec, score=50, title="AIKit", project="shiki", age=3d:
  → row contains: TUIBadge("SP") + TUIBar(50) + bold "AIKit" + dim "[shiki]" + dim "(3d)"
  if item has subtitle:
    → subtitle dimmed and indented on next line

T-27 [BR-15, Core 80%]:
When inbox rendering completes:
  → footer line shows: "Filter: --prs --specs --tasks │ Sort: --sort urgency|age|type"
  → footer colored with theme.dim

T-28 [BR-16, Core 80%]:
When rendering with plain=true:
  → no \u{1B}[ escape sequences in output
  → "╭" replaced with "+", "─" replaced with "-", "│" replaced with "|"
  → column alignment preserved via spaces

T-29 [BR-01, Core 80%]:
When calling stripANSI on text with 24-bit color "\u{1B}[38;2;189;147;249mhello\u{1B}[0m":
  → returns "hello"
When calling stripANSI on text with 8-color "\u{1B}[32mworld\u{1B}[0m":
  → returns "world"

T-30 [BR-20, Smoke CLI]:
When running shi theme list:
  → shows "dracula (built-in) *" (asterisk = active)
  → shows "catppuccin-mocha (built-in)"
  → shows "tokyo-night (built-in)"
  if ~/.shikki/themes/solarized-dark.yaml exists:
    → shows "solarized-dark (custom)"
  → each theme shows a 16-color swatch preview

T-31 [BR-21, Smoke CLI]:
When running shi theme set tokyo-night:
  → ~/.shikki/config.yaml updated with theme: tokyo-night
  → prints "Theme set to tokyo-night" in the new theme's accent color
  if theme name not found:
    → prints error with available themes listed
```

## Wave Dispatch Tree

```
         ┌────────────────────────────────────────────┐
         │ DSKintsugiCore (pure Swift — tokens/themes) │
         └───────────────────┬────────────────────────┘
                             │
Wave 1: TUITheme Engine ─────┘  ✅ DONE (10 tests passing)
  ├── TUITheme.swift — Base16 model + semantic roles + ANSI output
  ├── ThemeLoader.swift — auto-scan ~/.shikki/themes/, scheme: or filename
  ├── BuiltInThemes.swift — dracula, catppuccin-mocha, tokyo-night
  └── Base16Fallback.swift — 8-color mapping
  Input:  Base16 YAML files or built-in constants
  Output: TUITheme.active with .error/.success/.accent/.dim etc.
  Tests:  T-01..T-07, T-29
  Gate:   swift test --filter TUITheme → ✅ GREEN
  ║
  ║        ┌──────────────────────────────────────────┐
  ║        │ DSKintsugiTUI (terminal — depends on Core)│
  ║        └──────────────────┬───────────────────────┘
  ║                           │
  ╠══ Wave 2: TUI Components ─┘  ← BLOCKED BY Wave 1
  ║   ├── TerminalOutput.swift — ANSI primitives, stripANSI  ✅ DONE (7 tests)
  ║   ├── TUIBox.swift — 4 border styles, width-adaptive, themed title
  ║   ├── TUIBadge.swift — fixed-width tags, semantic role coloring
  ║   └── TUIBar.swift — urgency gradient + progress fill
  ║   Input:  TUITheme from Core
  ║   Output: Rendered string components
  ║   Tests:  T-08..T-10, T-15..T-18
  ║   Gate:   swift test --filter TUIBox,TUIBadge,TUIBar → green
  ║   ║
  ║   ╠══ Wave 3: Composite Components ← BLOCKED BY Wave 2
  ║   ║   ├── TUITable.swift — headers, alignment, ANSI-aware, truncation
  ║   ║   ├── TUIList.swift — grouped sections, dim separators
  ║   ║   ├── TUIPager.swift — bat (auto theme sync) / less / direct
  ║   ║   └── TUIPlain.swift — ASCII fallback for --plain
  ║   ║   Input:  TUITheme + primitives from Wave 2
  ║   ║   Output: Composed multi-component output strings
  ║   ║   Tests:  T-11..T-14, T-19..T-23, T-28
  ║   ║   Gate:   swift test --filter TUITable,TUIList,TUIPager → green
  ║   ║
  ║   ║   ┌───────────────────────────────────────────────┐
  ║   ║   │ ShikkiKit (imports DSKintsugiTUI — gets Core)  │
  ║   ║   └───────────────────┬───────────────────────────┘
  ║   ║                       │
  ║   ╠══ Wave 4: InboxRenderer ← BLOCKED BY Wave 3
  ║   ║   ├── InboxRenderer.swift — imports DSKintsugiTUI
  ║   ║   ├── InboxCommand.swift — rewrite to use InboxRenderer
  ║   ║   └── Package.swift — add DSKintsugiTUI dep to ShikkiKit
  ║   ║   Input:  [InboxItem] + TUITheme (via DSKintsugiTUI)
  ║   ║   Output: Full themed inbox output
  ║   ║   Tests:  T-24..T-27
  ║   ║   Gate:   shi inbox renders themed → visual + tests green
  ║   ║
  ║   ╚══ Wave 5: Theme CLI + Migration ← BLOCKED BY Wave 1 (parallel w/ 2-4)
  ║       ├── ThemeCommand.swift — shi theme list|set
  ║       ├── DELETE ShikkiKit ANSIStyle.swift + TerminalOutput.swift
  ║       └── Migrate SplashRenderer + ProjectStatusFormatter to TUITheme
  ║       Input:  TUITheme engine via DSKintsugiTUI
  ║       Output: CLI commands + migrated renderers
  ║       Tests:  T-30, T-31
  ║       Gate:   shi theme list + shi theme set work
```

## Implementation Waves

### Wave 1: TUITheme Engine in DSKintsugiCore
**Files (in projects/kintsugi-ds/):**
- `Sources/DSKintsugiCore/TUI/Theme/TUITheme.swift` — Base16 model, semantic roles, ANSI output (DONE)
- `Sources/DSKintsugiCore/TUI/Theme/ThemeLoader.swift` — auto-scan ~/.shikki/themes/, config reader (DONE)
- `Sources/DSKintsugiCore/TUI/Theme/BuiltInThemes.swift` — dracula/catppuccin-mocha/tokyo-night (DONE)
- `Sources/DSKintsugiCore/TUI/Theme/Base16Fallback.swift` — base0X → ANSI 8-color mapping table
- `Tests/DSKintsugiCoreTests/TUI/TUIThemeTests.swift` (DONE — 10 tests passing)
**Tests:** T-01, T-02, T-03, T-04, T-05, T-06, T-07, T-29
**BRs:** BR-01, BR-02, BR-02b, BR-02c, BR-03, BR-04, BR-05, BR-06b, BR-07, BR-08
**Deps:** none
**Gate:** `swift test --filter TUITheme` green (PASSING)

### Wave 2: TUI Components in DSKintsugiTUI ← BLOCKED BY Wave 1
**Files (in projects/kintsugi-ds/):**
- `Sources/DSKintsugiTUI/ANSI/TerminalOutput.swift` — terminal primitives + stripANSI (DONE — 7 tests passing)
- `Sources/DSKintsugiTUI/Components/TUIBox.swift` — 4 border styles, width-adaptive, theme-colored title
- `Sources/DSKintsugiTUI/Components/TUIBadge.swift` — fixed-width tags, semantic role → theme color
- `Sources/DSKintsugiTUI/Components/TUIBar.swift` — urgency gradient (error→warning→success), progress fill
- `Tests/DSKintsugiTUITests/TUIBoxTests.swift`
- `Tests/DSKintsugiTUITests/TUIBadgeTests.swift`
- `Tests/DSKintsugiTUITests/TUIBarTests.swift`
**Tests:** T-08, T-09, T-10, T-15, T-16, T-17, T-18
**BRs:** BR-06, BR-09, BR-11, BR-12
**Deps:** Wave 1 (DSKintsugiCore/TUITheme)
**Gate:** `swift test --filter TUIBox,TUIBadge,TUIBar` green

### Wave 3: Composite Components in DSKintsugiTUI ← BLOCKED BY Wave 2
**Files (in projects/kintsugi-ds/):**
- `Sources/DSKintsugiTUI/Components/TUITable.swift` — headers, alignment, ANSI-aware pad, truncation
- `Sources/DSKintsugiTUI/Components/TUIList.swift` — grouped sections, themed headers, dim separators
- `Sources/DSKintsugiTUI/Components/TUIPager.swift` — bat (auto theme sync) → less -R → direct
- `Sources/DSKintsugiTUI/Components/TUIPlain.swift` — ASCII replacements for --plain
- `Tests/DSKintsugiTUITests/TUITableTests.swift`
- `Tests/DSKintsugiTUITests/TUIListTests.swift`
- `Tests/DSKintsugiTUITests/TUIPagerTests.swift`
**Tests:** T-11, T-12, T-13, T-14, T-19, T-20, T-21, T-22, T-23, T-28
**BRs:** BR-10, BR-13, BR-14, BR-16, BR-17, BR-19
**Deps:** Wave 2 (TUI components)
**Gate:** `swift test --filter TUITable,TUIList,TUIPager` green

### Wave 4: InboxRenderer + InboxCommand Rewrite ← BLOCKED BY Wave 3
**Files (in projects/shikki/):**
- `Sources/ShikkiKit/TUI/InboxRenderer.swift` — `import DSKintsugiTUI`, uses all components
- `Sources/shikki/Commands/InboxCommand.swift` — rewrite renderList() to use InboxRenderer
- `Tests/ShikkiKitTests/TUI/InboxRendererTests.swift`
- `projects/shikki/Package.swift` — add DSKintsugiTUI dependency to ShikkiKit
**Tests:** T-24, T-25, T-26, T-27
**BRs:** BR-06c, BR-15, BR-18
**Deps:** Wave 3 (all DSKintsugiTUI components)
**Gate:** `shi inbox` renders themed output, tests green

### Wave 5: Theme CLI + ShikkiKit Migration ← BLOCKED BY Wave 1 (parallel with 2-4)
**Files (in projects/shikki/):**
- `Sources/shikki/Commands/ThemeCommand.swift` — `shi theme list` + `shi theme set <name>`
- `Sources/ShikkiKit/TUI/ANSIStyle.swift` — DELETE, replaced by DSKintsugiTUI re-export
- `Sources/ShikkiKit/TUI/TerminalOutput.swift` — DELETE, replaced by DSKintsugiTUI
- `Sources/ShikkiKit/TUI/ProjectStatusFormatter.swift` — replace inline Dracula with TUITheme
- `Sources/ShikkiKit/TUI/SplashRenderer.swift` — replace inline Dracula with TUITheme
- `Tests/ShikkiKitTests/TUI/ThemeCommandTests.swift`
**Tests:** T-30, T-31
**BRs:** BR-20, BR-21
**Deps:** Wave 1 (DSKintsugiCore theme engine only)
**Gate:** `shi theme list` + `shi theme set` work, existing renderers compile

## Reuse Audit

| Utility | Exists In | Decision |
|---------|-----------|----------|
| ANSI-aware padding | TerminalOutput.pad() / visibleLength() | Reuse directly in TUITable |
| Box-drawing chars | DashboardRenderer (line 120-130) | Extract to TUIBox |
| Progress bar | DashboardRenderer.progressBar() | Extract to TUIBar |
| Terminal dimensions | TerminalOutput.terminalWidth/Height() | Reuse |
| Tool detection (bat) | ExternalTools.isAvailable() | Reuse in TUIPager |
| stripANSI | ANSIStyle.stripANSI() | Fix regex for 24-bit, keep in place |
| Dracula colors | ProjectStatusFormatter (5 inline), SplashRenderer (1 inline), ANSIStyle.purple | Replace all with TUITheme |
| boxTop/boxLine/boxBottom | ChatRenderer (lines 103-118) | Replace with TUIBox |
| padToWidthAnsi | DashboardRenderer (line 565-569) | Replace with TUITable |

## Base16 Slot → Semantic Role Mapping

```
base00 (darkest bg)     → .bg         — background fill
base01 (dark bg)        → .bgAlt      — alternate background (selection)
base02 (selection)      → .selection   — highlight / selection
base03 (comments)       → .dim        — dimmed text, separators, timestamps
base04 (dark fg)        → .fgAlt      — secondary foreground
base05 (default fg)     → .fg         — primary text
base06 (light fg)       → .fgBright   — emphasized text
base07 (lightest fg)    → .fgMax      — maximum contrast
base08 (red)            → .error      — errors, critical urgency, gate failures
base09 (orange)         → .warning2   — secondary warning, orange accents
base0A (yellow)         → .warning    — warnings, medium urgency
base0B (green)          → .success    — success, low urgency, passing tests
base0C (cyan)           → .info2      — secondary info, project tags
base0D (blue)           → .info       — info, links, task badges
base0E (purple/magenta) → .accent     — primary accent, spec badges, titles
base0F (brown)          → .subtle     — deprecated, de-emphasized
```

## Built-In Theme Values (Dracula)

```yaml
# ~/.shikki/themes/dracula.yaml — or compiled in BuiltInThemes.swift
scheme: "Dracula"
author: "Zeno Rocha"
base00: "282a36"  # bg
base01: "3a3c4e"  # bg alt
base02: "44475a"  # selection
base03: "6272a4"  # comment/dim
base04: "b0b8d1"  # dark fg
base05: "f8f8f2"  # fg
base06: "f0f0ec"  # light fg
base07: "ffffff"  # max fg
base08: "ff5555"  # red/error
base09: "ffb86c"  # orange
base0A: "f1fa8c"  # yellow/warning
base0B: "50fa7b"  # green/success
base0C: "8be9fd"  # cyan/info2
base0D: "6272a4"  # blue/info
base0E: "bd93f9"  # purple/accent
base0F: "a16946"  # brown/subtle
```

## @t Review

### @Sensei (CTO)
Base16 is the right call — it's the closest thing to a universal standard. 16 slots is simple enough to reason about, and 200+ schemes already exist. The semantic role mapping (base08 → .error) means component code never references colors directly — only roles. Swapping themes changes everything. Keep the ThemeLoader dead simple: read YAML, map to struct, done. No caching, no hot-reload. `TUITheme.active` is computed once at startup.

The bat theme sync (BR-19) is clever — when a user sets theme: dracula, TUIPager passes `--theme=Dracula` to bat automatically. This makes `shi inbox | bat` look consistent without the user doing anything.

### @Hanami (UX)
The semantic roles are the key insight. Component authors think in .error/.success/.accent, never in hex codes. This means every component automatically looks right in every theme. The `shi theme list` with color swatch preview is important for discovery — users need to see the theme before committing.

For the inbox: urgency zones now use theme.error/warning/success instead of hardcoded red/yellow/green. A user with Solarized Light gets warm tones instead of neon. The cognitive load stays low regardless of palette.

### @Kintsugi (Philosophy)
A theme is not decoration — it's the developer's emotional environment. By supporting Base16, we're saying "bring your personality to the CLI." The developer who uses Catppuccin in their editor, their terminal, and their browser now gets it in Shikki too. Consistency across tools creates calm. The 3 built-in themes (dracula=warm dark, catppuccin=soft pastel, tokyo-night=cool night) cover the 3 major aesthetic families.

### @Ronin (Adversarial)
Watch for:
- **bat theme name mismatch**: Base16 scheme name "dracula" vs bat theme name "Dracula" vs "Dracula (base16)". Need a lookup table for bat mapping, not string matching.
- **YAML parsing without Yams**: If we don't want the Yams SPM dependency, Base16 YAML is simple enough for regex parsing (just key: value pairs, no nesting). But test edge cases: comments, quotes, trailing spaces.
- **Theme hot-swap mid-render**: `TUITheme.active` must be stable during a single render pass. Don't re-read config between components.
- **CI environments**: No `~/.shikki/config.yaml` in CI. Default must work with zero configuration.

### @Katana (Security)
Yams (Swift YAML) is safe — it maps to Codable structs, no arbitrary object instantiation like Python/Ruby YAML. Used by SwiftLint, SwiftFormat, Vapor. The real risk is supply chain (malicious version push), not the parser. Mitigation: pin exact versions, commit Package.resolved, audit changelogs before updates. Future: `shi deps audit` command.

**Decision**: DSKintsugiCore stays dependency-free — Base16 YAML is flat `key: "value"`, the manual parser (20 lines) is simpler than adding a dep. Yams goes in ShikkiKit for nested YAML (.shikki-quality parsing). Two layers, right tool for each.

## Design Reference: Target Output (with theme)

```
╭─ Inbox ─────────────────────────────────────────────────────╮   ← theme.accent title
│  20 items │ SP:8  PR:1  DC:0  TK:8  GT:2  │  develop       │   ← theme.fg / theme.dim
╰─────────────────────────────────────────────────────────────╯

🔥 Hot (70+)                                                      ← theme.error header
 SP  ████████ 50  AIKit — Shared Model-Agnostic AI Package      [shiki]   (3d)
 ↑   ↑            ↑                                              ↑         ↑
 accent  error    fg+bold                                        info2     dim

⚡ Active (40-69)                                                 ← theme.warning header
 SP  ██████░░ 40  Hot-Reload Restart with Version Check          [shikki]  (16h)
 ↑   ↑            ↑                                              ↑         ↑
 accent  warning  fg+bold                                        info2     dim

📋 Queued (<40)                                                   ← theme.success header
 SP  ████░░░░ 20  Dynamic Election Timing                        [shikki]  (2h)
 ↑   ↑            ↑                                              ↑         ↑
 accent  success  fg                                             info2     dim

──────────────────────────────────────────────────────────────────  ← theme.dim
 Filter: --prs --specs --tasks │ Sort: --sort urgency|age|type    ← theme.dim
```
