---
title: "Originate — DNS for Code: Pre-Computed Project Cache Standard"
status: brainstorm
priority: P1
project: shikki-ecosystem
created: 2026-03-26
co-designed-with: "@Daimyo + @team brainstorm"
depends-on: "Shikki CodeGen Engine (ArchitectureCache), Shikki v1"
---

# Originate — DNS for Code

## @Daimyo Context

`.originate` is not just attribution — it's **DNS for code**. A dotfile that redirects AI agents to a pre-computed MCP-queryable cache of the project, so they don't need to scrape the raw repo. Every company will eventually need a "project cache DB" — this IS that standard.

---

## @Sensei — Architecture Deep Dive

### What `.originate` Contains

The dotfile is a pointer, not a payload. Like `.gitignore` points to patterns and `.editorconfig` points to rules, `.originate` points to the pre-computed cache and declares the project's identity.

#### Concrete `.originate` File

```toml
# .originate — DNS for code
# This file tells AI agents where to find the project's architecture cache
# instead of scraping the raw repository.

[project]
name = "Brainy"
description = "RSS reader with AI-powered content analysis"
language = "swift"
license = "MIT"
repository = "https://github.com/example/brainy"

[cache]
# Where the pre-computed cache lives
# Supports: local path, HTTPS URL, or MCP endpoint
endpoint = "https://cache.originate.dev/example/brainy"

# Current cache version (matches git tag or commit)
version = "1.2.0"
commit = "a1b2c3d4"

# Cache format version (for parser compatibility)
schema = "1"

# Branches with available caches
branches = ["main", "develop"]

[attribution]
# Who built this project — the provenance layer
authors = ["Alice Smith <alice@example.com>"]
organization = "Example Corp"
created = "2024-06-15"

[cache.local]
# Local fallback (if the project is checked out)
path = ".originate-cache/"
```

### Cache Structure

The cache is a directory (local) or a JSON/MessagePack bundle (remote) containing pre-analyzed project knowledge. This is a direct externalization of Shikki's `ArchitectureCache` struct — made universal.

```
.originate-cache/
├── manifest.json          # Index: version, timestamp, file list, checksums
├── package.json           # SPM/Cargo/npm structure, targets, dependencies
├── protocols.json         # All protocols: name, methods, conformers, module
├── types.json             # All types: name, kind, fields, conformances, visibility
├── dependencies.json      # Dependency graph: module → imported modules
├── patterns.json          # Code patterns: error handling, DI, naming, mocks
├── tests.json             # Test framework, count, mock patterns, fixture patterns
├── api-surface.json       # Public API: exported symbols, function signatures
└── README.md              # Human-readable summary (auto-generated)
```

#### `manifest.json` (the root index)

```json
{
  "schema_version": 1,
  "project": "brainy",
  "language": "swift",
  "git_commit": "a1b2c3d4e5f6",
  "git_branch": "main",
  "git_tag": "v1.2.0",
  "built_at": "2026-03-26T10:30:00Z",
  "builder": "originate-action@v1",
  "files": {
    "package": { "path": "package.json", "sha256": "abc..." },
    "protocols": { "path": "protocols.json", "sha256": "def..." },
    "types": { "path": "types.json", "sha256": "ghi..." },
    "dependencies": { "path": "dependencies.json", "sha256": "jkl..." },
    "patterns": { "path": "patterns.json", "sha256": "mno..." },
    "tests": { "path": "tests.json", "sha256": "pqr..." },
    "api_surface": { "path": "api-surface.json", "sha256": "stu..." }
  },
  "stats": {
    "source_files": 47,
    "protocols": 12,
    "types": 89,
    "test_count": 234,
    "total_cache_tokens": 4200
  }
}
```

#### Key Design Decisions

1. **JSON over binary** — human-readable, diffable, no special tooling needed. MessagePack as optional optimization for large projects.
2. **Separate files per concern** — agents can query just `protocols.json` without loading the full cache. Reduces token cost further.
3. **SHA-256 checksums in manifest** — integrity verification without re-parsing.
4. **`total_cache_tokens`** — tells the agent exactly how much context this will cost. A 50-file project might be 4K tokens of cache vs. 30K tokens of raw file reads.

### GitHub Action: Cache Computation

```yaml
# .github/workflows/originate.yml
name: Build Originate Cache
on:
  push:
    branches: [main, develop]
  release:
    types: [published]

jobs:
  build-cache:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build architecture cache
        uses: originate-dev/action@v1
        with:
          language: auto          # auto-detect from files
          output: .originate-cache/
          branches: main,develop  # build cache for these branches

      - name: Publish cache
        uses: originate-dev/publish@v1
        with:
          cache-dir: .originate-cache/
          # Option A: GitHub Pages (free, static)
          target: github-pages
          # Option B: Originate CDN (faster, MCP-queryable)
          # target: originate-cdn
          # api-key: ${{ secrets.ORIGINATE_API_KEY }}
```

#### What the Action Does Internally

1. **Language detection**: scans for `Package.swift`, `Cargo.toml`, `package.json`, `go.mod`, `pyproject.toml`, etc.
2. **Parser dispatch**: runs the appropriate AST parser (Tree-sitter for Go core, language-specific analyzers for each ecosystem)
3. **Protocol extraction**: finds all interfaces/protocols/traits/abstract classes
4. **Type extraction**: finds all public types, their fields, conformances
5. **Dependency graph**: builds module-level import graph
6. **Pattern detection**: identifies error handling, DI, test, mock patterns via heuristics
7. **API surface**: extracts public exported symbols (what external consumers see)
8. **Serialization**: writes JSON files to output directory
9. **Manifest**: generates `manifest.json` with checksums and stats
10. **Publish**: uploads to target (GitHub Pages, CDN, or commits back to repo)

### MCP Query Interface

The remote cache endpoint speaks MCP (or plain HTTPS with JSON responses).

```
# Full project context (~2-4K tokens)
GET /example/brainy/v1.2.0/manifest.json

# Just protocols (~500 tokens)
GET /example/brainy/v1.2.0/protocols.json

# Just one protocol by name
GET /example/brainy/v1.2.0/protocols/ContentAnalyzer

# Dependency graph
GET /example/brainy/v1.2.0/dependencies.json

# MCP tool call (for MCP-aware agents)
originate_get_context(project="example/brainy", scope="protocols")
originate_get_type(project="example/brainy", name="Article")
originate_get_pattern(project="example/brainy", name="error_pattern")
```

### Mapping to Shikki's ArchitectureCache

| ArchitectureCache field | Originate cache file | Notes |
|------------------------|---------------------|-------|
| `packageInfo` | `package.json` | Direct mapping |
| `protocols` | `protocols.json` | Direct mapping |
| `types` | `types.json` | Direct mapping |
| `dependencyGraph` | `dependencies.json` | Direct mapping |
| `patterns` | `patterns.json` | Direct mapping |
| `testInfo` | `tests.json` | Direct mapping |
| (new) | `api-surface.json` | External consumers need this; Shikki's internal cache doesn't |
| `projectId`, `gitHash`, `builtAt` | `manifest.json` | Metadata |

**The Shikki ArchitectureCache IS the originate cache schema, externalized.** Shikki was the internal prototype; Originate is the open standard.

### Go Core Implementation

Why Go:
- Single static binary, cross-platform
- Tree-sitter bindings exist for Go (best multi-language AST parser)
- GitHub Actions run on Ubuntu — Go compiles instantly
- No runtime dependencies

```
originate/
├── cmd/originate/          # CLI entrypoint
├── pkg/
│   ├── detect/             # Language detection
│   ├── parser/             # Tree-sitter based parsers
│   │   ├── swift.go
│   │   ├── typescript.go
│   │   ├── python.go
│   │   ├── go.go
│   │   ├── rust.go
│   │   └── kotlin.go
│   ├── cache/              # Cache builder + serializer
│   ├── manifest/           # Manifest generator
│   ├── mcp/                # MCP server (for local serving)
│   └── publish/            # GitHub Pages / CDN publisher
├── schema/                 # JSON Schema definitions (v1)
├── wrappers/               # Auto-generated client libraries
│   ├── swift/              # Swift Package (generated)
│   ├── typescript/         # npm package (generated)
│   ├── python/             # PyPI package (generated)
│   └── rust/               # Crate (generated)
└── action/                 # GitHub Action definition
```

### Client Wrapper Generation

Like protobuf generates typed clients, the Go core generates typed cache readers:

```swift
// Auto-generated Swift wrapper
import Foundation

public struct OriginateCache: Codable, Sendable {
    public let manifest: Manifest
    public let protocols: [ProtocolDescriptor]
    public let types: [TypeDescriptor]
    // ...

    public static func load(from url: URL) async throws -> OriginateCache { ... }
    public static func load(from directory: URL) throws -> OriginateCache { ... }
}
```

---

## @Shogun — Market & Economic Analysis

### The "DNS for Code" Pitch Transformation

**Before (Attribution angle)**: "Track who made your code."
- Sounds like compliance. Legal teams care, developers groan.

**After (DNS for Code angle)**: "Stop wasting compute. One query instead of scraping an entire repo."
- Sounds like infrastructure. Developers AND companies care.

This is the difference between selling seat belts vs. selling a faster car. The seat belt (attribution) is still there, but the car (efficiency) is what people buy.

### Economic Argument: The Scale of Wasted Compute

#### The Math

Conservative estimates (2026):

| Variable | Estimate | Source |
|----------|----------|--------|
| Public repos on GitHub | 420M+ | GitHub 2025 report |
| Repos actively used by AI agents (indexed, popular) | ~5M | Top repos by stars/downloads/dependencies |
| AI coding agents in production | ~50M developer seats | Copilot 15M + Cursor 5M + Claude Code 3M + others |
| Avg repo scrapes per agent per day | ~3 | Context loading, re-reads, multi-file exploration |
| Avg tokens per full repo read | ~30K | Medium-size project, 20-50 files |
| Cost per 1K input tokens (avg across providers) | $0.003 | Blended across GPT-4o, Claude, etc. |

#### Daily Waste (Without Originate)

```
5M repos × 50 scrapes/day avg × 30K tokens/scrape = 7.5 TRILLION tokens/day

Cost: 7.5T tokens × $0.003/1K = $22.5M/day = $8.2B/year
```

#### With Originate

```
Same queries, but cache = ~3K tokens instead of 30K:
7.5T tokens → 750B tokens (10x reduction)

Savings: $7.4B/year in reduced token consumption
Energy: proportional reduction in GPU hours
```

#### Per-Company Impact

A company with 500 developers using AI coding tools:
- **Without Originate**: Each developer's agent re-reads the same 20 internal repos daily. 500 devs x 20 repos x 30K tokens = 300M tokens/day = $900/day = **$328K/year** just in redundant context loading.
- **With Originate**: 500 devs x 20 repos x 3K tokens = 30M tokens/day = $90/day = **$33K/year**.
- **Savings per company**: ~$295K/year. That funds the entire Originate adoption.

### Positioning

**Tagline options**:
- "Stop scraping. Start querying."
- "Your repo, pre-compiled for AI."
- "DNS for code. One lookup instead of a thousand reads."

**Target segments (in order)**:
1. **Open source maintainers** — reduce the load on their repos from AI scraping. Free tier. Viral adoption.
2. **Platform teams at companies** — internal architecture cache for their monorepos. Enterprise tier.
3. **AI tool builders** — integrate Originate as a standard input format. Partnership tier.

**Competitive landscape**: Nobody does this. GitHub Copilot reads raw files. Cursor reads raw files. Claude Code reads raw files. Every single AI coding tool re-discovers project architecture from scratch, every single time. There is no caching standard. This is greenfield.

### Business Model Sketch

| Tier | Price | Features |
|------|-------|----------|
| Open Source | Free forever | GitHub Action, static cache, up to 10 repos |
| Team | $29/mo | Unlimited repos, private cache hosting, MCP endpoint |
| Enterprise | $199/mo | On-prem cache server, SAML, audit logs, custom parsers |

Revenue is in the hosting and MCP endpoint, not the format. The format is open. The convenience is paid.

---

## @Enso + @Tsubaki — Naming Brainstorm

### Constraints
- Must fit the Shikki ecosystem (Japanese craft lineage)
- The "DNS for code" metaphor should resonate
- Short enough for CLI (`originate build` vs `??? build`)
- Dotfile must feel natural (`.originate` vs `.???`)
- README badge must look good

### 10 Alternatives

| # | Name | Dotfile | Japanese/Craft Origin | DNS Metaphor Fit | CLI Feel | Badge Look | Notes |
|---|------|---------|----------------------|-------------------|----------|------------|-------|
| 1 | **Hanko** | `.hanko` | Personal seal (判子) — the stamp that authenticates a document in Japan. Every official paper needs a hanko. | A hanko is both identity AND authentication — like DNS resolves identity to address. | `hanko build`, `hanko serve` | `[hanko: cached]` | **Strong.** A hanko IS a lookup seal. "Where do I find this project?" → stamp points you there. Fits OBYW craft lineage perfectly. |
| 2 | **Inkan** | `.inkan` | Registered seal (印鑑) — the more formal variant of hanko, used for legal documents. | Same as hanko but more formal/official. | `inkan build` | `[inkan: v1.2]` | More formal. Might confuse non-Japanese speakers. |
| 3 | **Fuda** | `.fuda` | Tag/label (札) — wooden tags hung on temple gates, price tags, identification cards. | A fuda IS a pointer — it directs you somewhere. | `fuda build` | `[fuda: cached]` | Short, unique, the metaphor is "label that points." But not widely known. |
| 4 | **Shirube** | `.shirube` | Guide/signpost (導) — the kanji for guidance, used in 道標 (dōhyō, road sign). | A signpost IS DNS — it resolves "where is X?" to a direction. | `shirube build` | `[shirube: v1.2]` | Beautiful meaning. Might be too long for daily typing. |
| 5 | **Mokkan** | `.mokkan` | Wooden tablet (木簡) — ancient Japanese wooden slips used for record-keeping and identification. Precursor to paper documents. | Historical data lookup system — the original "cache." | `mokkan build` | `[mokkan: cached]` | Unique, historical depth. "Wooden cache tablet" is poetic. |
| 6 | **Insho** | `.insho` | Seal/stamp impression (印章) — the physical impression left by a hanko. | The mark left behind — the cached footprint of a project. | `insho build` | `[insho: v1.2]` | Elegant but similar to inkan. |
| 7 | **Kashira** | `.kashira` | Head/origin (頭) — the head of something, the starting point, the source. | The origin point you query to understand the whole. | `kashira build` | `[kashira: cached]` | Interesting "head/origin" meaning. |
| 8 | **Tōroku** | `.toroku` | Registration (登録) — the act of registering something officially. | DNS is literally a registration system. | `toroku build` | `[toroku: v1.2]` | Too literal. Sounds bureaucratic. |
| 9 | **Sashizu** | `.sashizu` | Instructions/directions (指図) — literally "pointing with fingers." | Pointing to the cache = giving directions = DNS resolution. | `sashizu build` | `[sashizu: cached]` | Great meaning ("here, this way") but long. |
| 10 | **Kamon** | `.kamon` | Family crest (家紋) — the emblem that identifies a house/clan. Used on armor, documents, buildings. One look tells you who this belongs to. | A kamon IS a project identity marker. Resolves "whose code is this?" instantly. | `kamon build` | `[kamon: cached]` | **Very strong.** Visual, recognizable, the crest concept is universal. A kamon on a repo = "this project has registered its identity and architecture." |

### @Tsubaki's Top 3 Recommendation

**1. Hanko** (判子)
- Best overall. A hanko is literally a seal that authenticates and identifies. In Japanese business, you stamp your hanko to say "this is verified, this is mine." A `.hanko` file says "this project has been stamped — here's its verified architecture." Short (5 chars), pronounceable globally, unique in the developer tooling space. The CLI reads naturally: `hanko build`, `hanko serve`, `hanko publish`.
- Badge: `[hanko cached | v1.2.0]` with a small seal icon.

**2. Kamon** (家紋)
- Close second. More visual — a kamon is a crest you recognize at a glance. Works if the brand leans into the visual/badge aspect. `.kamon` as a dotfile is clean. The downside: "kamon" might get confused with "common."

**3. Fuda** (札)
- Dark horse. Shortest (4 chars), and the meaning — a tag/label that points — is exactly what the dotfile does. Less elegant than hanko, but maximum CLI ergonomics.

### @Enso's Brand Assessment

**Hanko wins.** Here's why from a brand coherence perspective:

The Shikki ecosystem already has:
- **Shikki** (漆器) — lacquerware, the craft of building
- **Kintsugi** (金継ぎ) — golden repair, the design system
- **WabiSabi** (侘寂) — imperfect beauty, the iOS app

**Hanko** (判子) adds "the seal of authenticity" to this lineage. It completes a narrative:
- You BUILD with Shikki (the craft)
- You DESIGN with Kintsugi (the aesthetic)
- You PRESENT with WabiSabi (the philosophy)
- You AUTHENTICATE with Hanko (the seal)

The DNS metaphor maps perfectly: a hanko is pressed once, and then anyone who sees the impression knows exactly who/what this is. The cache is the impression. The `.hanko` file is the stamp.

---

## @Kintsugi — Philosophy Evolution

### From "Protect Against Theft" to "Make Consumption Efficient AND Respectful"

The original framing was defensive: "AI tools are stealing code. We need to track attribution."

The evolved framing is constructive: "AI tools are wastefully re-reading code. We can make this efficient for everyone AND preserve attribution as a natural byproduct."

This is a profound shift. Here's why:

### The Defensive Frame (Old)

- **Message**: "Your code is being scraped without credit."
- **Emotion**: Fear, anger, protectionism.
- **Action**: Lock down, add restrictions, monitor.
- **Result**: Friction. Maintainers vs. AI tools. Zero-sum.

### The Constructive Frame (New)

- **Message**: "Your project can be understood in 3K tokens instead of 30K. And your name stays attached."
- **Emotion**: Pride, efficiency, contribution.
- **Action**: Publish your architecture cache. Make your project AI-ready.
- **Result**: Win-win. Maintainers get credit AND reduced load. AI tools get faster, cheaper context. Positive-sum.

### The Kintsugi Principle Applied

In kintsugi, the break is not hidden — it's highlighted with gold. The repair is more beautiful than the original.

The "break" in open source is the disconnect between creators and AI consumers. Attribution was broken when AI tools started scraping without credit. The old response was to hide the break — make it harder to scrape, add legal threats.

**Hanko's response is kintsugi**: make the attribution the most visible, most useful part. The `.hanko` file doesn't just say "credit me" — it says "here's my architecture, pre-analyzed, ready for you. My name is in the manifest. Use it well."

The attribution is the gold in the repair. It's not a legal requirement — it's a gift. The project says: "I've done the work of understanding myself. Here's the result. My identity comes with it."

### Both Sides Win — The New Messaging

| Stakeholder | What they get |
|-------------|---------------|
| **Open source maintainer** | Reduced scraping load, permanent attribution in every cache query, pride of a well-documented project |
| **AI tool builder** | 10x cheaper context loading, standardized format (no per-language scraping), faster agent startup |
| **Developer using AI tools** | Faster responses, more accurate code generation (architecture-aware), lower API costs |
| **The planet** | Less redundant compute = less electricity = less carbon. Multiplied across millions of daily queries |

### The Messaging Hierarchy

1. **Lead with efficiency** — "10x faster project understanding for AI agents."
2. **Follow with elegance** — "A pre-computed architecture cache, like DNS for code."
3. **Attribution emerges naturally** — "Every cache carries its creator's seal."
4. **Philosophy as depth** — "Consumption should be efficient AND respectful. Hanko makes both automatic."

The old pitch asked maintainers to do work (add attribution) for ethical reasons. The new pitch asks them to do work (publish a cache) for practical reasons, and attribution comes free. This is how adoption happens — utility first, values baked in.

---

## Synthesis: @Daimyo Review Package

### The Concept

**Hanko** (working name, pending @Daimyo approval) — an open standard for pre-computed project architecture caches. A `.hanko` dotfile in a repo points AI agents to a cached representation of the project's architecture (protocols, types, dependencies, patterns, tests) so they never need to scrape the raw repo.

### The Architecture

1. **`.hanko` dotfile** — TOML pointer to cache endpoint + project identity + attribution
2. **Cache format** — JSON files (manifest, protocols, types, dependencies, patterns, tests, api-surface), version-pinned to git commits
3. **GitHub Action** — computes cache at push/release, publishes to GitHub Pages or Hanko CDN
4. **Go core** — Tree-sitter-based multi-language parser, generates cache + typed client wrappers
5. **MCP interface** — standard query tools (`hanko_get_context`, `hanko_get_type`, etc.)
6. **Client wrappers** — auto-generated Swift/TS/Python/Rust/Go/Kotlin/Ruby/PHP libraries

### The Economics

- $8.2B/year in redundant AI token consumption across the industry
- 10x reduction per query (30K tokens → 3K)
- Per-company savings: ~$295K/year for a 500-dev team
- Business model: open format, paid hosting/MCP endpoint

### The Name

**Hanko** (判子) — recommended. Japanese seal of authenticity. Fits Shikki ecosystem. Short, pronounceable, unique in dev tooling. Badge: `[hanko cached | v1.2.0]`.

### The Philosophy

From "protect against theft" to "make consumption efficient AND respectful." Both sides win. Utility drives adoption. Attribution is baked in, not bolted on.

### Timing

- Architecture designed now (during Shikki v1)
- ArchitectureCache in ShikkiKit IS the prototype of the cache schema
- Go core implementation after Shikki v1 launch
- GitHub Action as first public artifact
- Open source (MIT license — the cache format must be maximally permissive for adoption)

### Open Questions for @Daimyo

1. **Name approval**: Hanko, Kamon, or something else?
2. **Cache hosting**: GitHub Pages (free, decentralized) vs. Hanko CDN (centralized, MCP-native, revenue opportunity)?
3. **Schema governance**: Who owns the cache schema version? OBYW.one? A foundation? Community RFC?
4. **Shikki integration**: Should Shikki consume `.hanko` files natively in the CodeGen pipeline, making it the first reference consumer?
5. **License for the standard**: MIT (max adoption) or Apache-2.0 (patent protection)?
