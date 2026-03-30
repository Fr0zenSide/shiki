---
name: lightpanda-io/browser
type: reference
description: Headless browser built from scratch in Zig for AI agents and automation. 11x faster, 9x less RAM than Chrome. Native MCP server, CDP-compatible.
source: https://github.com/lightpanda-io/browser
relevance: HIGH — direct accelerator for /ingest pipeline and Moto protocol web content layer
discovered: 2026-03-30
---

## What It Is

Lightpanda is a headless browser written from scratch in Zig -- not a Chromium fork, not a WebKit patch. It targets a single use case: machine-driven web browsing without graphical rendering. Founded in Paris by Francis Bouvier (company: Selecy SAS), pre-seed funded mid-2025.

**Key stats** (as of 2026-03-30):
- 25,955 GitHub stars, 1,050 forks, 91 open issues
- License: AGPL-3.0 + CLA (same model as Shikki)
- Latest release: 0.2.7 (2026-03-25), active weekly releases
- Beta status -- many sites work, some crashes, CORS not yet implemented
- Binaries: macOS aarch64, Linux x86_64 (nightly builds + Docker)
- Cloud: managed service at console.lightpanda.io (WebSocket API, token auth)

## Architecture

### Engine Stack
- **Language**: Zig 0.15.2 (system-level, manual memory control)
- **JS engine**: V8 (with snapshot embedding for instant startup)
- **HTML parser**: html5ever (from Servo)
- **HTTP**: libcurl
- **DOM**: Custom Zig implementation (replaced LibDOM in Jan 2026 for full control over memory/events)
- **No graphical layer** -- no CSS layout, no painting, no GPU

### Protocol Surface
1. **CDP (Chrome DevTools Protocol)** -- primary interface. Puppeteer, Playwright, chromedp all work as drop-in replacements. WebSocket at port 9222.
2. **Native MCP server** (stdio) -- built into the binary since v0.2.5 (March 2026). Run `lightpanda mcp`. No external process needed.
3. **Go MCP server** (gomcp) -- deprecated wrapper that connected via CDP. Now superseded by native MCP.
4. **CLI fetch mode** -- `lightpanda fetch --dump markdown|html <URL>` for one-shot page retrieval.
5. **Custom CDP commands** -- `LP.getMarkdown`, `LP.getSemanticTree`, `LP.getInteractiveElements`, `LP.getStructuredData` (AI-native extensions beyond standard CDP).

### Native MCP Tools (12 tools, from src/mcp/tools.zig)
| Tool | Description |
|------|-------------|
| `goto` | Navigate to URL, load page in memory |
| `markdown` | Get page content as markdown (AI-optimized) |
| `links` | Extract all links from page |
| `evaluate` | Execute JavaScript in page context |
| `semantic_tree` | Simplified semantic DOM tree for AI reasoning (supports maxDepth, subtree via backendNodeId) |
| `interactiveElements` | Extract clickable/fillable elements |
| `structuredData` | Extract JSON-LD, OpenGraph, etc. |
| `detectForms` | Detect form structure (fields, types, required) |
| `click` | Click element by backendNodeId |
| `fill` | Fill text into input by backendNodeId |
| `scroll` | Scroll page or element |
| `waitForSelector` | Wait for CSS selector match |

### SemanticTree (src/SemanticTree.zig)
A pruned, AI-friendly DOM representation that strips invisible/decorative nodes and annotates interactive elements with XPaths and event listener data. Outputs as JSON or indented text. This is the key differentiator vs raw HTML scraping -- it gives agents a structured view of what matters on the page.

## Performance Claims (Verified by Third-Party Benchmarks)

Benchmarked on AWS EC2 m5.large, 933 real web pages with JS rendering:

| Metric | Chrome Headless | Lightpanda | Improvement |
|--------|----------------|------------|-------------|
| 100-page scrape | 25.2s | 2.3s | **11x faster** |
| Peak RAM (100 pages) | 207 MB | 24 MB | **9x less** |
| Concurrent instances (8GB) | ~15 | ~140 | **9.3x density** |
| Startup | ~500ms | <100ms | **Instant** |
| Cost (infra) | baseline | -82% | **82% savings** |
| Parallelism ceiling | ~5 tabs | ~25 processes | **5x wider** |

Lightpanda uses one process per CDP connection (single context, single page). Parallelism comes from spawning multiple lightweight processes, not tabs.

## Ecosystem

| Repo | Description | Stars |
|------|-------------|-------|
| `browser` | Core browser engine | 25,955 |
| `gomcp` | Go MCP server (deprecated, native MCP supersedes) | 63 |
| `agent-skill` | SKILL.md for Claude Code / Openclaw agents | 35 |
| `demo` | Benchmark scripts and demo pages | 46 |
| `cdpproxy` | CDP proxy for debugging | -- |
| `awesome-lightpanda` | Community resources | -- |
| `awesome-mcp-servers` | Fork of MCP server list | -- |

## Competitive Landscape

| Tool | Model | Key Difference |
|------|-------|----------------|
| **Lightpanda** | AGPL OSS + cloud | From-scratch Zig, 11x perf, native MCP |
| **Browserbase** | Closed cloud ($40M Series B) | Managed Chrome fleet, Stagehand NL framework |
| **Steel** | Open-source cloud API | Chrome-based, enterprise fleet mgmt |
| **Stagehand** | OSS framework (by Browserbase) | NL abstraction over Playwright, not a browser |
| **Playwright/Puppeteer** | OSS libraries | Control layer, not a browser engine |

Lightpanda's moat: it IS the browser, not a wrapper around Chrome. Every competitor still runs Chromium underneath.

## Limitations (Current Beta)

- **No CORS** (issue #2015) -- blocks cross-origin fetch in some SPAs
- **No Web Workers / SharedWorker** (issue #2017)
- **Single page per CDP connection** -- need multiple processes for parallelism
- **Partial Web API coverage** -- hundreds of APIs still missing
- **Google blocks it** -- fingerprinting detection. Use DuckDuckGo for search.
- **Playwright scripts may break** on upgrade -- Playwright's feature detection chooses different code paths as Lightpanda adds APIs
- **No Windows native** -- WSL only
- **Telemetry on by default** (disable via env var)
- **Crashes on some sites** -- beta quality, but rapidly improving (weekly releases)

## Relevance to Shikki Ecosystem

### 1. /ingest Pipeline Acceleration (HIGH)
Current `/ingest` relies on HTTP fetch + HTML parsing. Many modern repos have GitHub Pages, documentation sites, and wikis that are JS-rendered SPAs. Lightpanda's `markdown` MCP tool would let `/ingest` handle these with:
- 11x faster throughput than headless Chrome
- Native markdown output (no external html-to-markdown step)
- Structured data extraction (JSON-LD, OpenGraph) for richer metadata
- SemanticTree for intelligent content extraction vs brute-force HTML parsing
- 82% lower infra cost for batch ingestion jobs

**Integration path**: Add Lightpanda as an optional backend in the `/ingest` pipeline. When a URL returns JS-heavy content (or always for docs sites), route through Lightpanda's MCP `markdown` tool instead of raw HTTP fetch.

### 2. Moto Protocol Integration (HIGH)
Moto is a public code cache protocol. Lightpanda could serve as the **content acquisition layer** for Moto nodes:
- Pre-compute and cache rendered versions of documentation, READMEs, changelogs
- Extract structured data (package.json, Cargo.toml info from rendered pages)
- `semantic_tree` provides a canonical, diff-friendly representation of page content
- `--obey-robots` flag means Moto can respect site policies natively

**Opportunity**: Propose to Lightpanda team a "Moto adapter" -- a standardized content extraction profile that outputs Moto-compatible cache entries. Their AGPL license aligns with our AGPL choice, making collaboration natural.

### 3. ShikkiMCP Web Knowledge Tool (MEDIUM)
ShikkiMCP could expose a `web_read` tool that wraps Lightpanda for on-demand web content retrieval during agent sessions. Instead of agents relying on WebSearch (which has rate limits and strips context), they could:
- Fetch full page content as markdown
- Extract interactive elements for form-filling workflows
- Get structured data for API discovery

### 4. Agent Skill Distribution (LOW)
Lightpanda already publishes an `agent-skill` (SKILL.md format) for Claude Code / Openclaw. This validates our skills.sh distribution model. Their skill teaches agents to use Lightpanda as a Chrome replacement -- we could bundle it as a recommended skill in the Shikki ecosystem.

### 5. License Alignment (NOTABLE)
Both Lightpanda and Shikki use AGPL-3.0 + CLA. Same licensing philosophy. This means:
- We can self-host and modify freely under AGPL
- Contributing upstream is natural (CLA required)
- No license friction for deep integration
- Shared Paris tech ecosystem (French startup, OBYW.one SASU)

## Action Items

### P1 -- Do Now
- [ ] **Install Lightpanda nightly on dev machine** -- `curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-macos && chmod a+x ./lightpanda`
- [ ] **Test native MCP with Claude Code** -- add to `.mcp.json` as `lightpanda mcp` stdio server. Evaluate tool quality on 10 representative URLs (GitHub READMEs, docs sites, SPAs).
- [ ] **Benchmark for /ingest** -- compare current HTTP-fetch pipeline vs Lightpanda `markdown` tool on 50 URLs from recent /ingest sessions. Measure: speed, content completeness, token count.

### P2 -- Next Iteration
- [ ] **Add Lightpanda backend to /ingest** -- optional `--browser` flag that routes through Lightpanda MCP for JS-rendered content. Fallback to HTTP fetch for simple HTML.
- [ ] **Evaluate for Moto content layer** -- prototype a Moto cache builder that uses Lightpanda to pre-render and store documentation pages. Test with 5 popular open-source project doc sites.
- [ ] **ShikkiMCP `web_read` tool** -- wrap Lightpanda's `markdown` + `structuredData` tools behind a single ShikkiMCP tool for agent-accessible web reading.

### P3 -- Watch / Collaborate
- [ ] **Monitor CORS implementation** (issue #2015) -- this is a blocker for many SPA-heavy sites
- [ ] **Track Web Worker support** (issue #2017) -- needed for complex web apps
- [ ] **Propose Moto adapter to Lightpanda team** -- open discussion on their Discord or GitHub about standardized content extraction for protocol-level caching. French startup to French startup conversation.
- [ ] **Contribute upstream** -- if we hit bugs during /ingest integration, file issues and PRs. CLA-compatible.
- [ ] **Watch cloud pricing** -- if self-hosting becomes impractical at scale, console.lightpanda.io may be the fallback

## Sources

- [lightpanda-io/browser](https://github.com/lightpanda-io/browser) -- main repo, README, source code
- [lightpanda-io/gomcp](https://github.com/lightpanda-io/gomcp) -- Go MCP server (deprecated)
- [lightpanda-io/agent-skill](https://github.com/lightpanda-io/agent-skill) -- Claude Code / Openclaw skill
- [Lightpanda blog](https://lightpanda.io/blog/) -- architecture posts, release notes
- [Migrating our DOM to Zig](https://lightpanda.io/blog/posts/migrating-our-dom-to-zig) -- Jan 2026 architecture deep dive
- [Why build a new browser?](https://lightpanda.io/blog/posts/why-build-a-new-browser) -- founding thesis
- [Lightpanda Console](https://console.lightpanda.io/) -- managed cloud service
- [Lightpanda MCP Demo](https://trymcp.lightpanda.io/) -- interactive MCP demo
- [Benchmark details](https://github.com/lightpanda-io/demo/blob/main/BENCHMARKS.md#crawler-benchmark) -- AWS EC2 m5.large methodology
- [OpenAlternative: Lightpanda](https://openalternative.co/lightpanda) -- competitive positioning
