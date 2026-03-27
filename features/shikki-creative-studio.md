# Feature: Shikki Creative Studio — Local AI Image & Video Generation Plugin

> Created: 2026-03-27 | Status: Spec (validated by @Daimyo + @shi team) | Owner: @Daimyo
> Priority: **P2** — add-on module, not core infrastructure
> Location: Plugin — NOT part of ShikkiKit or ShikiCore
> Depends on: AIKit (MLXEngine, MLXVideoProvider, ShellRunner, ModelDownloader, LocalModelStore)

---

## Context

Yesterday we built a local AI creative stack: SDXL Turbo for text-to-image, Wan2.1 for text-to-video, Pillow for compositing, and ComfyUI for advanced workflows. The stack lives at `~/.venvs/mlx-video/` with outputs in the `ai-creative-lab/` private repo.

This capability must NOT live in Shikki core. It is a plugin/module — installable, removable, with external dependencies (Python venvs, multi-GB models, GPU time). Same architectural boundary as agent personas (plugin), research (module), or `.moto` (separate project).

AIKit already has the foundation: `MLXVideoProvider` shells out to `mlx_video` via `ShellRunner`, `ModelDownloader` handles HuggingFace downloads with progress, `LocalModelStore` manages the on-disk manifest, and `AICapabilities` includes `.imageGeneration` and `.videoGeneration`. The Creative Studio wraps this with a CLI interface, prompt management, progress display, and plugin lifecycle.

---

## Phase 1: Team Brainstorm

### @Sensei (Architecture) — 3 Ideas

**1. PluginManifest — The Module's Passport**

Following the AgentManifest pattern from the persona spec, every Shikki plugin needs a typed manifest. The Creative Studio is the first non-agent plugin — it establishes the pattern for all future modules.

```swift
public struct PluginManifest: Codable, Sendable, Identifiable {
    public let id: PluginID                        // "shikki/creative-studio"
    public let displayName: String                 // "Creative Studio"
    public let version: SemanticVersion            // 0.1.0
    public let source: PluginSource                // .builtin, .local, .marketplace

    // What this plugin provides
    public let commands: [PluginCommand]            // ["creative", "🎨"]
    public let capabilities: [String]               // ["t2i", "t2v", "compositing", "comfyui"]

    // What this plugin requires
    public let dependencies: PluginDependencies
    public let minimumShikkiVersion: SemanticVersion

    // Runtime
    public let entryPoint: String                   // Swift module or script path
    public let configSchema: PluginConfigSchema?     // typed config fields

    // Metadata
    public let author: String
    public let license: String
    public let description: String
    public let checksum: String
}

public struct PluginDependencies: Codable, Sendable {
    public let systemTools: [String]               // ["python3", "pip3"]
    public let pythonPackages: [String]             // ["diffusers", "mlx-video", "Pillow"]
    public let minimumDiskGB: Double                // 15.0 (for models)
    public let minimumRAMGB: Double                 // 16.0 (for inference)
    public let requiredCapabilities: AICapabilities // [.imageGeneration]
    public let venvPath: String?                   // "~/.venvs/shikki-creative"
}

public enum PluginSource: Codable, Sendable {
    case builtin
    case local(path: String)
    case marketplace(url: URL, verified: Bool)
}
```

This establishes a universal plugin contract. Any future module (research, .moto, analytics) follows the same manifest pattern. The Creative Studio is the proving ground.

**2. Thin CLI Wrapper Around AIKit Providers**

The Creative Studio should NOT reimplement model inference. It wraps existing AIKit providers with creative-specific UX:

```
shikki creative "prompt"
    │
    ├── Parse flags (--video, --overlay, --model, --size, --steps)
    ├── Resolve model → AIKit ModelDescriptor
    ├── Check dependencies (venv, model downloaded, disk space)
    ├── Build AIRequest with prompt + options
    ├── Dispatch to appropriate AIProvider:
    │     T2I → new SDXLProvider (via ShellRunner → diffusers)
    │     T2V → existing MLXVideoProvider
    │     Composite → new PillowProvider (via ShellRunner → Pillow)
    │     ComfyUI → new ComfyUIProvider (HTTP → ComfyUI API)
    ├── Stream progress to TUI (inference steps, ETA)
    └── Save output + update prompt history
```

The new providers needed are:
- `SDXLProvider: AIProvider` — shells out to `python3 -m diffusers` (or direct script) for T2I
- `PillowProvider` — shells out to Python Pillow for text overlay / compositing
- `ComfyUIProvider: AIProvider` — HTTP client to ComfyUI API for workflow execution

These live in AIKit (they're AI providers), not in the Creative Studio plugin. The plugin is pure CLI/UX.

**3. ComfyUI Workflow Templates as JSON**

ComfyUI's power is its node graph, serialized as JSON. The Creative Studio should ship with curated workflow templates:

```
~/.shikki/plugins/creative-studio/workflows/
  ├── t2i-sdxl-turbo.json          # fast T2I, 1-4 steps
  ├── t2i-flux-quality.json         # slow T2I, high quality
  ├── t2v-wan21-default.json        # T2V with Wan2.1
  ├── i2v-wan21-animate.json        # image-to-video
  ├── composite-text-overlay.json   # text on image
  ├── composite-watermark.json      # brand watermark
  └── custom/                       # user-created workflows
```

Users can create workflows in ComfyUI's web UI, export the JSON, drop it in `custom/`, and invoke it: `shikki creative --workflow custom/my-pipeline "prompt"`. This makes the Creative Studio infinitely extensible without code changes.

---

### @Hanami (UX) — 2 Ideas

**1. The `shikki creative` Experience**

The command should feel immediate and craft-oriented. No configuration ceremony on first use.

```
$ shikki creative "hooded samurai in blizzard, manga style"

  🎨 Creative Studio — SDXL Turbo
  ────────────────────────────────
  Model:    stabilityai/sdxl-turbo (4.9 GB, local)
  Size:     1024x1024
  Steps:    4 (turbo)

  Generating...
  ████████████████████░░░░░  step 3/4  [2.1s elapsed]

  ✓ Saved to ~/Creative/2026-03-27/samurai-blizzard-001.png
  ────────────────────────────────
  Open:  ⌘+click path  │  Redo: shikki creative --redo
  Vary:  shikki creative --seed 42 "..."
```

For video generation (longer process):

```
$ shikki creative --video "gold flowing through kintsugi cracks"

  🎨 Creative Studio — Wan2.1
  ────────────────────────────────
  Model:    Wan-AI/Wan2.1-T2V-14B (28 GB, local)
  Size:     480x320, 49 frames @ 24fps (~2s)
  Steps:    30

  Generating... ━━━━━━━━━━━━━━━━━━━━━━━━━  12/30 steps
  Elapsed: 8m 23s  │  ETA: ~12m 40s

  ✓ Saved to ~/Creative/2026-03-27/kintsugi-gold-001.mp4
```

Key UX decisions:
- Default output dir: `~/Creative/YYYY-MM-DD/` (configurable)
- Auto-naming: slug from first 3 words of prompt + sequential number
- `--redo` reruns last prompt with same settings
- `--seed N` for reproducibility
- `--open` auto-opens in Preview.app / QuickLook
- Progress bar with step count and ETA (from ShellRunner stream parsing)

**2. Gallery and Prompt History**

Past generations should be browsable:

```
$ shikki creative --history

  RECENT GENERATIONS (last 7 days)
  ────────────────────────────────
  #  Date        Type   Model        Prompt (truncated)           Output
  1  2026-03-27  T2I    SDXL Turbo   "hooded samurai in blizza…"  samurai-blizzard-001.png
  2  2026-03-27  T2V    Wan2.1       "gold flowing through kin…"  kintsugi-gold-001.mp4
  3  2026-03-26  T2I    SDXL Turbo   "dark temple, rain, neon …"  temple-rain-003.png

  ────────────────────────────────
  Rerun:  shikki creative --rerun 1
  Fav:    shikki creative --fav 1
  Gallery: shikki creative --gallery (opens Finder)
```

Prompt history stored in `~/.shikki/plugins/creative-studio/history.json`. Favorites get a `starred: true` flag. Gallery opens the output directory in Finder.

Future (v2): TUI gallery with thumbnail previews using iTerm2/Kitty image protocol.

---

### @Shogun (Market) — 2 Ideas

**1. Competitive Landscape: CLI AI Creative Tools**

| Tool | Model Support | CLI? | Local? | Plugin? | Verdict |
|------|--------------|------|--------|---------|---------|
| **ComfyUI** | All diffusion models | Web UI only | Yes | Nodes (Python) | Powerful but no CLI. We wrap it. |
| **Automatic1111** | SD 1.5/XL | Web UI + API | Yes | Extensions (Python) | Legacy. SDXL Turbo makes it less relevant. |
| **Fooocus** | SDXL-based | Web UI | Yes | No | Simple but no CLI, no extensibility. |
| **Draw Things** (macOS) | CoreML/MLX | GUI app | Yes | No | Great Mac app but not scriptable. |
| **mlx-image** (community) | SDXL via MLX | Python CLI | Yes | No | Raw CLI, no UX, no prompt mgmt. |
| **Invoke AI** | Many | Web UI + CLI | Yes | Nodes | Closest competitor. Heavy, complex setup. |

**Shikki differentiator**: First CLI-native creative tool that is:
- Part of a developer workflow (not a separate app)
- Plugin-based (install/remove without breaking anything)
- Wraps multiple backends (SDXL, FLUX, Wan2.1, ComfyUI) behind one command
- Has prompt history, favorites, reproducible seeds
- Integrates with the rest of Shikki (generate app icons, marketing screenshots, video demos)

**2. Indie Dev Use Cases**

This is not art-for-art's-sake. Practical use cases for indie devs using Shikki:

| Use Case | Command | Value |
|----------|---------|-------|
| App Store screenshots | `shikki creative "iPhone showing fitness app, dark mode"` | No Figma needed for mockups |
| Marketing hero image | `shikki creative "abstract kintsugi pattern, gold on black, 4K"` | Landing page assets |
| App icon generation | `shikki creative --size 1024x1024 "minimalist icon, ..."` | Rapid icon iteration |
| Video demo | `shikki creative --video "app walkthrough animation"` | Promo videos |
| Brand watermark | `shikki creative --overlay "OBYW.ONE" --on hero.png` | Branded assets |
| Social media posts | `shikki creative --size 1200x630 "OG image for blog post"` | Auto-sized for platforms |
| README badges/art | `shikki creative --size 800x200 "banner for Shikki repo"` | GitHub README art |

The creative studio turns a developer CLI into a one-person creative agency.

---

### @Kintsugi (Philosophy) — 1 Idea

**Lacquerware Creating Beauty**

Shikki (漆器) is lacquerware — functional objects made beautiful through layers of craft. The Creative Studio is where lacquerware creates art. Not code, not orchestration, not process — visual beauty.

This is the most literal expression of the Shikki metaphor. The tool named after lacquerware now literally produces visual artifacts. Each generation is a layer of lacquer: the model is the base wood, the prompt is the artist's intent, the inference is the curing process, and the output is the finished piece.

The naming should reflect this:
- Output directory: `~/Creative/` (not `~/ai-output/` or `~/generated/`)
- History entries are "pieces" not "generations"
- Favorites are "gallery" not "bookmarks"
- Workflows are "techniques" not "pipelines"

The craft metaphor keeps the creative studio grounded. It is not a factory producing assets. It is an atelier where a craftsperson uses local tools (their own machine, their own models, no cloud dependency) to create something with intent.

---

### @Ronin (Adversarial) — 2 Concerns

**1. Disk Space: Models Are Enormous**

Reality check on model sizes:
- SDXL Turbo: ~5 GB
- FLUX.1-dev: ~12 GB
- Wan2.1-T2V-14B: ~28 GB
- Wan2.1-I2V-14B: ~28 GB
- ComfyUI + custom nodes: ~2 GB
- Python venv (diffusers, torch, mlx): ~4 GB
- **Total for full stack: ~79 GB**

On a 512 GB MacBook with macOS, Xcode, and other projects, this is 15% of total storage. On a 256 GB machine, it is unacceptable.

**Mitigations**:
1. **Tiered installation**: v1 installs ONLY SDXL Turbo (~5 GB) + venv (~4 GB) = ~9 GB. Video models are opt-in: `shikki creative models add wan21-t2v`.
2. **Disk space check BEFORE download**: `shikki creative doctor` reports available space vs required space. Block installation if < 10 GB free after download.
3. **Model eviction**: `shikki creative models prune` removes unused models. Track last-used date in `LocalModelStore`.
4. **Shared HuggingFace cache**: Use `~/.cache/huggingface/` (standard HF cache) instead of duplicating models. Multiple tools share the same downloads.
5. **Size warnings in --history**: Show total disk usage: "Creative Studio: 37.2 GB across 3 models."

**2. Python Dependency: Venv Management from Swift CLI**

The Creative Studio shells out to Python. This creates fragility:

- **Scenario A**: User upgrades Python via Homebrew. Old venv breaks (wrong Python path). Generation fails with cryptic `ModuleNotFoundError`.
- **Scenario B**: Model download interrupted (network drop). Partial model on disk. Inference produces garbage or crashes.
- **Scenario C**: Two Shikki sessions run concurrent generations. GPU memory exhaustion, both fail.

**Mitigations**:
1. **Venv health check**: `shikki creative doctor` verifies venv integrity (Python path exists, key packages importable, model files complete).
2. **Atomic model downloads**: Use `ModelDownloader` (already handles temp file + atomic move). Verify SHA256 checksum after download.
3. **GPU lock**: Generation acquires a lock file (`~/.shikki/plugins/creative-studio/gpu.lock`). Second concurrent generation queues or rejects with clear message.
4. **Venv recreation**: `shikki creative setup --force` nukes and recreates the venv. Documents the Python version requirement.
5. **Graceful degradation**: If Python/venv is broken, the rest of Shikki is unaffected. The plugin is isolated. `shikki creative` shows "Plugin unavailable: Python venv not found. Run `shikki creative setup`."

---

## Phase 2: Feature Brief

### Scope

**v0.1.0 — Text-to-Image via CLI (MVP)**

| Feature | Description |
|---------|-------------|
| `shikki creative "prompt"` | Generate image from text using SDXL Turbo |
| `shikki creative setup` | Create Python venv, install dependencies, download SDXL Turbo |
| `shikki creative doctor` | Check venv, models, disk space, GPU availability |
| `shikki creative models list` | Show installed models with sizes |
| Progress display | Step-by-step progress bar during generation |
| Output directory | `~/Creative/YYYY-MM-DD/` with auto-naming |
| `--size WxH` | Output dimensions (default 1024x1024) |
| `--steps N` | Inference steps (default 4 for turbo) |
| `--seed N` | Reproducible generation |
| `--open` | Open result in Preview.app |
| Plugin manifest | `PluginManifest` struct, `shikki plugin list` shows it |

**v0.2.0 — Video + Compositing**

| Feature | Description |
|---------|-------------|
| `shikki creative --video "prompt"` | Generate video via Wan2.1 (wraps existing `MLXVideoProvider`) |
| `shikki creative --overlay "TEXT" --on image.png` | Text overlay via Pillow |
| `shikki creative models add <model>` | Download additional models (FLUX, Wan2.1-I2V) |
| `shikki creative models remove <model>` | Remove model + reclaim disk space |
| `--history` | View past generations |
| `--redo` / `--rerun N` | Repeat last/specific generation |
| `--fav N` | Mark generation as favorite |
| Prompt history | JSON log of all generations with params |
| `--format png\|jpg\|webp` | Output format selection |
| `--i2v input.png` | Image-to-video (Wan2.1 I2V) |

**v1.0.0 — ComfyUI Workflows + Gallery**

| Feature | Description |
|---------|-------------|
| `shikki creative --workflow <name> "prompt"` | Execute ComfyUI workflow template |
| `shikki creative workflows list` | Show available workflow templates |
| `shikki creative workflows import <file.json>` | Import ComfyUI workflow |
| `shikki creative --gallery` | TUI gallery with image previews (iTerm2/Kitty protocol) |
| `--batch "prompt1" "prompt2" ...` | Generate multiple images from prompt list |
| `--style <preset>` | Style presets (manga, photorealistic, watercolor, etc.) |
| `shikki creative serve` | Start ComfyUI server for web UI access |
| ShikiDB integration | Prompt history + metadata synced to DB |

### Out of Scope (explicitly)

- Cloud API providers (Midjourney, DALL-E, Stability API) — local only, by design
- Training / fine-tuning models — use dedicated tools
- Real-time generation (live preview) — batch only for v1
- iOS/macOS native app — CLI/TUI only
- LoRA management — future, post-v1.0

---

## Phase 3: Business Rules

### BR-01: Plugin Installation

```
shikki plugin add creative-studio
```

Installation sequence:
1. Check `PluginManifest.dependencies.minimumRAMGB` — warn if system RAM < 16 GB
2. Check available disk space vs `PluginManifest.dependencies.minimumDiskGB` (15 GB)
3. Create plugin directory: `~/.shikki/plugins/creative-studio/`
4. Create Python venv at configured path (default `~/.venvs/shikki-creative/`)
5. Install Python packages: `pip install diffusers transformers accelerate torch Pillow mlx mlx-video`
6. Download default model (SDXL Turbo, ~5 GB) via `ModelDownloader` with progress
7. Register plugin in `~/.shikki/plugins/manifest.json`
8. Verify: `shikki creative doctor` runs automatically

Uninstallation:
```
shikki plugin remove creative-studio
# Prompts: "Remove models too? (37.2 GB) [y/N]"
# Removes plugin dir, optionally removes venv + models
# Does NOT affect core Shikki in any way
```

### BR-02: Model Management

Models are tracked via AIKit's `LocalModelStore` (existing `~/.aikit/models/manifest.json`).

| Model | ID | Size | Domain | Default? |
|-------|----|------|--------|----------|
| SDXL Turbo | `stabilityai/sdxl-turbo` | ~5 GB | image | Yes (installed with plugin) |
| FLUX.1-dev | `black-forest-labs/FLUX.1-dev` | ~12 GB | image | No |
| FLUX.1-schnell | `black-forest-labs/FLUX.1-schnell` | ~12 GB | image | No |
| Wan2.1-T2V-14B | `Wan-AI/Wan2.1-T2V-14B` | ~28 GB | video | No |
| Wan2.1-I2V-14B | `Wan-AI/Wan2.1-I2V-14B` | ~28 GB | video | No |

Rules:
- Default model for T2I: SDXL Turbo (fastest, smallest)
- Default model for T2V: Wan2.1-T2V-14B (only option currently)
- `--model <id>` flag overrides default
- Model auto-detection: if only one T2I model installed, use it. If multiple, use configured default.
- `shikki creative models add flux-dev` downloads and registers
- `shikki creative models remove sdxl-turbo` deletes files + deregisters (refuses if it is the only T2I model)
- HuggingFace cache: respect `HF_HOME` env var, default to `~/.cache/huggingface/`

### BR-03: Output Directory

Default: `~/Creative/YYYY-MM-DD/`

Configurable via:
- `~/.shikki/plugins/creative-studio/config.json` → `"outputDir": "~/Creative"`
- `--output /path/to/file.png` — single-file override
- `SHIKKI_CREATIVE_OUTPUT` env var

Naming convention: `{slug}-{NNN}.{ext}`
- Slug: first 3 meaningful words of prompt, lowercased, hyphenated
- NNN: zero-padded sequential number (001, 002, ...)
- Example: `samurai-blizzard-manga-001.png`

### BR-04: Prompt History

Stored at: `~/.shikki/plugins/creative-studio/history.json`

Each entry:
```json
{
    "id": "uuid",
    "prompt": "hooded samurai in blizzard, manga style",
    "type": "t2i",
    "model": "stabilityai/sdxl-turbo",
    "params": { "width": 1024, "height": 1024, "steps": 4, "seed": null },
    "outputPath": "~/Creative/2026-03-27/samurai-blizzard-manga-001.png",
    "createdAt": "2026-03-27T14:32:00Z",
    "durationSeconds": 3.2,
    "starred": false
}
```

Rules:
- History retained for 90 days by default (configurable)
- Starred items never auto-pruned
- `--redo` replays last entry with same params (new seed unless --seed specified)
- `--rerun N` replays entry #N from history
- History is local-only in v0.x; synced to ShikiDB in v1.0

### BR-05: Format Flags

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--size WxH` | 512x512, 1024x1024, 1280x720, custom | 1024x1024 (T2I), 480x320 (T2V) | Output dimensions |
| `--steps N` | 1-100 | 4 (SDXL Turbo), 30 (Wan2.1) | Inference steps |
| `--seed N` | integer | random | Deterministic seed |
| `--format` | png, jpg, webp | png | Output format (T2I only) |
| `--quality` | draft, normal, high | normal | Preset: draft=1step, normal=4step, high=20step |
| `--video` | flag | off | Switch to T2V mode |
| `--overlay "TEXT"` | string | - | Text to composite |
| `--on <file>` | path | - | Base image for overlay |
| `--font-size N` | integer | 48 | Overlay font size |
| `--model <id>` | model identifier | auto | Override model selection |
| `--workflow <name>` | workflow template name | - | ComfyUI workflow (v1.0) |
| `--open` | flag | off | Open result after generation |
| `--batch` | flag | off | Read prompts from stdin, one per line |

### BR-06: Progress Display

T2I (fast, ~2-5 seconds):
- Single progress bar: `Generating... ████████████░░░░  step 3/4  [2.1s]`
- On completion: file path + size

T2V (slow, ~10-30 minutes):
- Progress bar with ETA: `Generating... ━━━━━━━━━━━━━  12/30 steps  [8m 23s / ~20m 50s]`
- Show elapsed time and estimated remaining
- Stream stderr from Python process (inference step logs)
- On completion: file path + size + duration

Parse progress from ShellRunner stream output. MLXVideoProvider already supports streaming via `ShellRunner.stream()`.

### BR-07: Disk Space Checks

Before any model download:
1. Query available disk space via `FileManager`
2. Compare to model size (from HuggingFace metadata or known sizes)
3. If available < modelSize + 5 GB buffer: REFUSE with clear message
4. Show projected space after download: "After download: 42 GB free (from 70 GB)"

`shikki creative doctor` shows:
```
Disk Space
  Available:     78.3 GB
  Models:        37.2 GB (3 models)
  Venv:           3.8 GB
  Outputs:        1.2 GB (47 files)
  After cleanup:  83.3 GB (if models pruned)
```

### BR-08: Plugin Isolation

The Creative Studio MUST NOT affect core Shikki when:
- Not installed: `shikki creative` shows "Plugin not installed. Run `shikki plugin add creative-studio`"
- Broken venv: `shikki creative` shows clear error, all other commands work
- Models missing: `shikki creative` shows "No models installed. Run `shikki creative models add sdxl-turbo`"
- Python not found: `shikki creative doctor` diagnoses, suggests fix

Plugin registration in ShikkiKit:
```swift
public protocol ShikkiPlugin: Sendable {
    var manifest: PluginManifest { get }
    func isAvailable() async -> Bool
    func doctor() async -> [DiagnosticResult]
    func setup() async throws
    func teardown() async throws
}
```

Core Shikki discovers plugins via `~/.shikki/plugins/manifest.json`. No compile-time dependency — plugins are runtime-discovered.

### BR-09: GPU Lock

Only one generation can run at a time (Apple Silicon unified memory constraint).

Lock file: `~/.shikki/plugins/creative-studio/gpu.lock`
- Created when generation starts, contains PID + timestamp
- Deleted on completion (or crash — stale lock detected by PID check)
- Second concurrent request: "GPU busy — generation in progress (started 2m ago). Queue? [y/N]"
- Queuing: second request waits for lock release, then proceeds

### BR-10: Emoji Alias

`shikki creative` is the canonical command. `shikki` with the paintbrush emoji is an alias:

```
shikki creative "prompt"       # canonical
```

The emoji alias is registered in the plugin manifest's `commands` field and resolved by ShikkiKit's command router.

---

## Phase 4: Test Plan

### Unit Tests (in AIKit)

| # | Test | What It Verifies |
|---|------|------------------|
| 1 | `SDXLProviderTests.testComplete_buildsCorrectArguments` | ShellRunner receives correct python arguments for T2I |
| 2 | `SDXLProviderTests.testComplete_returnsOutputPath` | Response content is the file path |
| 3 | `SDXLProviderTests.testComplete_failsOnNonZeroExit` | AIKitError.requestFailed on exit code != 0 |
| 4 | `SDXLProviderTests.testStatus_readyWhenPythonExists` | Provider reports .ready when python path valid |
| 5 | `SDXLProviderTests.testStatus_unavailableWhenMissing` | Provider reports .unavailable when python missing |
| 6 | `PillowProviderTests.testOverlay_buildsCorrectArguments` | Overlay command has text, position, font size |
| 7 | `PillowProviderTests.testOverlay_failsOnMissingInput` | Error when --on file doesn't exist |
| 8 | `ComfyUIProviderTests.testWorkflowLoad_parsesJSON` | Workflow JSON parsed correctly |
| 9 | `ComfyUIProviderTests.testComplete_sendsHTTPRequest` | Correct POST to ComfyUI API |
| 10 | `ComfyUIProviderTests.testComplete_failsWhenServerDown` | Clean error when ComfyUI not running |

### Unit Tests (in Creative Studio Plugin)

| # | Test | What It Verifies |
|---|------|------------------|
| 11 | `PromptHistoryTests.testAppend_savesToJSON` | New entry written to history file |
| 12 | `PromptHistoryTests.testPrune_removesOlderThan90Days` | Auto-pruning respects retention |
| 13 | `PromptHistoryTests.testPrune_keepsStarred` | Starred items survive pruning |
| 14 | `PromptHistoryTests.testRerun_loadsCorrectEntry` | --rerun N returns correct history item |
| 15 | `OutputNamerTests.testSlug_threeWords` | "hooded samurai in blizzard" -> "hooded-samurai-blizzard" |
| 16 | `OutputNamerTests.testSequential_incrementsCorrectly` | 001, 002, 003 in same directory |
| 17 | `OutputNamerTests.testSequential_handlesExistingFiles` | Picks next number if 001-003 exist |
| 18 | `DiskSpaceCheckerTests.testRefuses_whenInsufficient` | Blocks download when space < model + 5 GB |
| 19 | `DiskSpaceCheckerTests.testAllows_whenSufficient` | Proceeds when space adequate |
| 20 | `GPULockTests.testAcquire_createsLockFile` | Lock file created with PID |
| 21 | `GPULockTests.testAcquire_failsWhenLocked` | Second acquire returns .busy |
| 22 | `GPULockTests.testRelease_deletesLockFile` | Lock file removed |
| 23 | `GPULockTests.testStaleLock_detectedByPID` | Dead PID lock is considered stale |
| 24 | `PluginManifestTests.testDecode_fromJSON` | Manifest deserializes correctly |
| 25 | `PluginManifestTests.testDependencyCheck_reportsAllMissing` | Missing python, pip flagged |
| 26 | `CreativeDoctorTests.testDoctor_allGreen` | All checks pass when setup complete |
| 27 | `CreativeDoctorTests.testDoctor_missingVenv` | Reports venv issue with fix command |
| 28 | `CreativeDoctorTests.testDoctor_missingModel` | Reports no models with install command |
| 29 | `ModelResolverTests.testAutoSelect_onlyModelUsed` | Single installed model auto-selected |
| 30 | `ModelResolverTests.testExplicitOverride_respectsFlag` | --model flag overrides default |

### Integration Tests

| # | Test | What It Verifies |
|---|------|------------------|
| 31 | `CreativeE2E.testSetup_createsVenvAndDownloadsModel` | Full setup flow (skip in CI — large download) |
| 32 | `CreativeE2E.testGenerate_producesImageFile` | End-to-end T2I produces valid PNG |
| 33 | `CreativeE2E.testGenerate_writesHistory` | Generation appends to history |
| 34 | `CreativeE2E.testRedo_repeatsLastGeneration` | --redo produces new file with same params |
| 35 | `PluginLifecycleTests.testInstall_registersPlugin` | Plugin appears in manifest after install |
| 36 | `PluginLifecycleTests.testRemove_cleansUp` | Plugin removed, Shikki unaffected |
| 37 | `PluginLifecycleTests.testUnavailable_gracefulError` | Missing plugin shows install instruction |

### Performance Benchmarks (manual, not CI)

| # | Test | Target |
|---|------|--------|
| 38 | SDXL Turbo T2I 1024x1024 4 steps | < 5s on M1 Pro |
| 39 | Wan2.1 T2V 480x320 30 steps | < 25min on M1 Pro |
| 40 | Pillow text overlay | < 1s |
| 41 | Plugin load time (discovery + manifest parse) | < 50ms |

---

## Plugin Architecture

### How This Fits the Shikki Plugin System

The Creative Studio establishes the `ShikkiPlugin` protocol that all future modules follow:

```
~/.shikki/
  plugins/
    manifest.json                          # registry of installed plugins
    creative-studio/
      plugin.json                          # PluginManifest
      config.json                          # user config (output dir, default model)
      history.json                         # prompt history
      workflows/                           # ComfyUI workflow templates
        t2i-sdxl-turbo.json
        custom/
      gpu.lock                             # runtime lock file
```

### PluginManifest for Creative Studio

```json
{
    "id": "shikki/creative-studio",
    "displayName": "Creative Studio",
    "version": "0.1.0",
    "source": "builtin",
    "commands": ["creative"],
    "capabilities": ["t2i", "t2v", "compositing", "comfyui"],
    "dependencies": {
        "systemTools": ["python3", "pip3"],
        "pythonPackages": ["diffusers", "transformers", "accelerate", "torch", "Pillow"],
        "minimumDiskGB": 15.0,
        "minimumRAMGB": 16.0,
        "venvPath": "~/.venvs/shikki-creative"
    },
    "minimumShikkiVersion": "0.3.0",
    "entryPoint": "CreativeStudioPlugin",
    "author": "shikki",
    "license": "AGPL-3.0",
    "description": "Local AI image and video generation. SDXL Turbo, FLUX, Wan2.1, ComfyUI workflows."
}
```

### Dependency on AIKit

The Creative Studio does NOT bundle AI inference. It depends on AIKit providers:

```
CreativeStudioPlugin
  ├── uses AIKit.SDXLProvider (new, for T2I)
  ├── uses AIKit.MLXVideoProvider (existing, for T2V)
  ├── uses AIKit.PillowProvider (new, for compositing)
  ├── uses AIKit.ComfyUIProvider (new, for workflows)
  ├── uses AIKit.ModelDownloader (existing, for model downloads)
  ├── uses AIKit.LocalModelStore (existing, for model management)
  └── uses AIKit.ShellRunner (existing, for Python shell-out)
```

New AIKit providers needed (v0.1.0): `SDXLProvider`
New AIKit providers needed (v0.2.0): `PillowProvider`
New AIKit providers needed (v1.0.0): `ComfyUIProvider`

AIKit gains a new `ModelDomain.image` case (currently missing — only `video` exists for visual generation).

### Disabling Without Breaking Core

```swift
// In ShikkiKit plugin discovery
let plugins = PluginRegistry.discover()  // reads ~/.shikki/plugins/manifest.json
if let creative = plugins["shikki/creative-studio"] {
    // Register commands: "creative"
    router.register(creative.commands, handler: creative)
} else {
    // "creative" command not registered — shikki creative shows install prompt
    router.registerFallback("creative") {
        print("Plugin not installed. Run: shikki plugin add creative-studio")
    }
}
```

No conditional compilation. No feature flags. Plugin absent = command absent. Shikki binary is identical with or without the plugin.

---

## Migration from Current Setup

The existing `~/.venvs/mlx-video/` setup becomes the seed for the plugin:

1. `shikki plugin add creative-studio` detects existing venv at `~/.venvs/mlx-video/`
2. Offers to migrate: "Found existing AI creative venv. Migrate to Creative Studio? [y/N]"
3. If yes: symlinks or moves venv to `~/.venvs/shikki-creative/`, registers models in `LocalModelStore`
4. If no: creates fresh venv alongside

The `ai-creative-lab/` private repo remains independent — it is the output gallery, not the tool.

---

## New AIKit Types Needed

```swift
// Addition to ModelDomain (existing enum)
case image  // new — alongside .video

// New provider
public struct SDXLProvider: AIProvider {
    // Wraps: python3 -c "from diffusers import ...; pipe(...)"
    // Or: python3 generate.py --prompt ... --output ...
    // Uses ShellRunner, same pattern as MLXVideoProvider
}
```

---

## Wave Plan

| Wave | Scope | Effort | Dependencies |
|------|-------|--------|--------------|
| **Wave 1** | `PluginManifest` + `ShikkiPlugin` protocol + `PluginRegistry` in ShikkiKit | 1 day | None |
| **Wave 2** | `SDXLProvider` in AIKit + `ModelDomain.image` | 0.5 day | Wave 1 |
| **Wave 3** | `shikki creative` command (T2I only) + setup + doctor + progress | 1 day | Wave 2 |
| **Wave 4** | Output naming + prompt history + --redo/--rerun/--seed | 0.5 day | Wave 3 |
| **Wave 5** | `PillowProvider` + `--video` (wraps MLXVideoProvider) + `--overlay` | 1 day | Wave 3 |
| **Wave 6** | `ComfyUIProvider` + workflow templates + gallery | 1 day | Wave 5 |

Total: ~5 days for full v1.0.0. MVP (v0.1.0, Waves 1-4): ~3 days.
