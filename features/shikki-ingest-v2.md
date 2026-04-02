---
title: "Ingest Pipeline v2 — Browser Engine + Moto Fallback"
status: draft
priority: P0
project: shikki
created: 2026-04-02
authors: "@Daimyo vision + @shi brainstorm"
tags: [ingest, browser, moto, knowledge, radar]
---

# Feature: Ingest Pipeline v2 — Browser Engine + Moto Fallback
> Created: 2026-04-02 | Status: Draft | Owner: @Daimyo

## Context

The current `/ingest` pipeline uses WebFetch (HTTP fetch + HTML-to-markdown stripping) for URLs. This works for static HTML but fails silently on the modern web: JS-rendered SPAs return empty shells, auth-gated pages return login forms, infinite-scroll pages capture only above-the-fold content, and social media embeds resolve to nothing. Meanwhile, Moto cache (shipped Phase 1) contains pre-indexed, checksummed architecture data for known projects — but `/ingest` never checks it. Two working systems, disconnected.

**Current code**: `.claude/commands/ingest.md` (skill), `src/backend/src/ingest.ts` (DB pipeline), `ShikkiKit/Moto/MotoCacheReader.swift` (cache reader).

## Problem

`/ingest <url>` produces empty or degraded output for ~40% of modern URLs (SPAs, dynamic docs sites, gated content). Radar scans and competitive intelligence depend on accurate ingestion. Every failed ingest means a gap in ShikiDB's knowledge layer that compounds across sessions. The Moto cache — already built and validated — sits unused during URL ingestion, forcing redundant network fetches for projects we already have indexed locally.

## @shi Brainstorm

**@Sensei (CTO):** The resolution chain must be deterministic: Moto cache (instant, pre-indexed) > ShikiDB dedup check (already ingested?) > browser engine (JS rendering) > basic WebFetch (static HTML). Detection heuristic for "needs browser": check Content-Type + scan for SPA markers (`<div id="root"></div>`, `<noscript>`, `__NEXT_DATA__`) in the initial HTML response. If the body is under 500 chars after stripping tags, escalate to browser. Playwright CLI (`npx playwright`) is the pragmatic first choice — battle-tested, Chromium-based, works today. Lightpanda is the strategic replacement once CORS lands (issue #2015).

**@Ronin (adversarial):** Playwright spawns Chromium — 200MB+ RAM, 3-15s per page. Anti-bot systems (Cloudflare Turnstile, hCaptcha) will block headless browsers. Resource budget: one Chromium instance per ingest, 15s hard timeout, kill on timeout. Never keep a browser process alive between ingests. What if Playwright is not installed? Fail gracefully to WebFetch, log a warning suggesting `npx playwright install chromium`. Do NOT auto-install browsers without user consent.

**@Metsuke (quality):** Success metric: "content completeness ratio" — compare token count of extracted content vs manual copy-paste. Target: >80% for the top 50 URL patterns in recent `/ingest` sessions. Test with a fixture suite of HTML files: static page, React SPA shell, Next.js SSR, YouTube community post, GitHub rendered markdown. Mock the browser via recorded HAR files — no live network in CI.

**@Katana (security):** Chromium sandbox is critical — never run with `--no-sandbox`. Playwright's default sandbox is sufficient for ingest (read-only extraction, no form submission). Block navigation away from the target URL (prevent redirects to malicious pages). Set a content size cap (5MB rendered DOM) to prevent memory bombs. Lightpanda's `--obey-robots` is good default behavior. Never execute user-supplied JS — only navigate + extract. Disable file:// and data:// URL schemes in the browser context.

## Resolution Chain

```
/ingest <url>
  1. URL normalization — strip tracking params, resolve redirects, validate scheme (http/https only)
  2. Moto cache lookup — MotoCacheReader.findType/findProtocol for code URLs (GitHub repos, pkg docs)
     → HIT: return pre-indexed architecture data as chunks (instant, zero network)
  3. ShikiDB dedup check — search by source_uri + content_hash
     → HIT + fresh (<7d): return cached chunks, skip re-ingestion
  4. Lightweight probe — HTTP HEAD + partial GET (first 16KB)
     → Detect: Content-Type, SPA markers, body emptiness, meta[name=robots]
  5. Render decision:
     a. Static HTML (body >500 chars after strip, no SPA markers) → WebFetch path
     b. SPA/dynamic (SPA markers OR body <500 chars) → Browser engine path
     c. YouTube URL → yt-dlp path (existing, unchanged)
     d. GitHub raw/API URL → git clone path (existing, unchanged)
  6. Content extraction → structured markdown chunks
  7. AI categorization + embedding → save to ShikiDB
```

## Business Rules

- **BR-01**: Moto cache is always checked first. A Moto hit skips all network activity.
- **BR-02**: ShikiDB dedup uses both `source_uri` exact match and embedding similarity (>0.92 threshold). Content younger than 7 days is considered fresh.
- **BR-03**: The lightweight probe MUST complete within 3s. Timeout = escalate to browser engine.
- **BR-04**: Browser engine timeout is 15s per page. On timeout, fall back to whatever the probe captured.
- **BR-05**: Maximum rendered DOM size is 5MB. Exceeding this aborts browser extraction and falls back to probe content.
- **BR-06**: Playwright is the default browser engine. Lightpanda is a configuration option (`--browser lightpanda`). Neither is auto-installed — missing browser logs a warning and falls to WebFetch.
- **BR-07**: Browser engine runs with default Chromium sandbox. `--no-sandbox` is never passed.
- **BR-08**: Only `http://` and `https://` schemes are accepted. `file://`, `data://`, `javascript:` are rejected with an error.
- **BR-09**: Navigation is locked to the target URL origin. Cross-origin redirects are blocked after the first hop (allow one redirect for URL shorteners).
- **BR-10**: The `--dry-run` flag shows which resolution step would be used without fetching.
- **BR-11**: Every successful ingest records `resolution_method` in chunk metadata (`moto_cache`, `shikidb_cache`, `browser_engine`, `webfetch`, `ytdlp`, `git_clone`).
- **BR-12**: Rate limiting: maximum 10 browser-engine ingests per minute (Chromium is heavy). WebFetch has no limit.

## URL Pattern Detection

| Pattern | Detection Signal | Resolution |
|---------|-----------------|------------|
| GitHub repo URL | `github.com/<owner>/<repo>` (no file path) | git clone path |
| GitHub file/blob | `github.com/.*/blob/` | WebFetch (raw content URL) |
| YouTube | `youtube.com/watch`, `youtu.be/`, `youtube.com/shorts/` | yt-dlp path |
| npm/PyPI/crates.io | known registry domains | WebFetch (server-rendered) |
| Docs sites (React) | SPA markers in probe: `<div id="root">`, `<div id="__next">`, `bundled.js` | Browser engine |
| Docs sites (static) | Full HTML body >500 chars, no SPA markers | WebFetch |
| Social media | `twitter.com`, `x.com`, `reddit.com`, `mastodon.*` | Browser engine (always) |
| API/JSON endpoints | Content-Type: `application/json` | Direct JSON parse |

**SPA marker detection** (checked in probe response body):
```
<div id="root"></div>    <div id="app"></div>     <div id="__next">
<noscript>               __NEXT_DATA__            window.__INITIAL_STATE__
bundle.js                chunk.js                 _app.js
```

## Playwright Integration

A bundled JS script (`scripts/ingest-browser.js`) that Playwright executes:
1. Launch Chromium (headless, sandboxed)
2. Navigate to URL, wait for `networkidle` (max 15s)
3. Extract `document.body.innerText` + `document.title` + meta tags
4. Output JSON to stdout: `{ "title": "...", "content": "...", "meta": {...} }`
5. Swift reads stdout, parses JSON, chunks the content

**Lightpanda alternative**: When `--browser lightpanda` is passed, use `lightpanda fetch --dump markdown <url>` instead. Same output contract, different binary. The `PlaywrightRenderer` becomes a `BrowserRenderer` protocol with two conformances.

## Moto Cache Integration

```swift
/// Check Moto cache before any network activity.
func checkMotoCache(for url: URL) -> [IngestChunk]? {
    // 1. Parse URL to identify project (github.com/owner/repo → repo slug)
    // 2. Look for .moto-cache/ in known project directories
    // 3. If found, use MotoCacheReader to load architecture data
    // 4. Convert ArchitectureCache → IngestChunk array
    //    - Package info → 1 chunk (overview)
    //    - Protocols → 1 chunk per protocol (signature + conformers)
    //    - Types → 1 chunk per public type (properties + methods)
    //    - Patterns → 1 chunk per pattern
    // 5. Return chunks with resolution_method: "moto_cache"
}
```

**URL-to-project mapping**: Maintain a `moto-sources.json` registry that maps GitHub URLs to local `.moto-cache/` paths. Built automatically by `shikki moto build` when it caches a project. Checked by `/ingest` before any network call.

## Test Scenarios

| # | Scenario | Input | Expected |
|---|----------|-------|----------|
| T1 | Moto cache hit | URL for a project with `.moto-cache/` | Returns cached chunks, zero network calls |
| T2 | ShikiDB dedup fresh | URL ingested 2 days ago | Returns cached chunks from DB, no re-fetch |
| T3 | ShikiDB dedup stale | URL ingested 10 days ago | Re-fetches via appropriate resolution path |
| T4 | Static HTML page | Plain HTML blog post | WebFetch path, >80% content completeness |
| T5 | React SPA | `<div id="root"></div>` + bundle.js | Browser engine path, renders full content |
| T6 | Browser timeout | Page that loads for >15s | Falls back to probe content, logs warning |
| T7 | Playwright not installed | `npx playwright` returns error | Falls to WebFetch, logs install suggestion |
| T8 | Blocked URL scheme | `file:///etc/passwd` | Rejected with error, no fetch attempted |
| T9 | Cross-origin redirect | URL redirects to different domain twice | Blocked after first redirect hop |
| T10 | DOM size bomb | Page with >5MB rendered DOM | Extraction aborted, falls to probe content |
| T11 | YouTube URL | `youtube.com/watch?v=xxx` | Routed to yt-dlp path (unchanged behavior) |
| T12 | `--dry-run` flag | Any URL | Shows resolution method without fetching |

**Test infrastructure**: HAR-recorded fixtures for T4-T6, mock process for T7, unit tests for URL pattern detection and SPA marker scanning. No live network in CI.

## Implementation Waves

### Wave 1: Resolution Chain + Moto Integration (P0)
- `IngestResolver` — URL normalization, pattern detection, resolution routing
- `MotoCacheIngestAdapter` — convert MotoCacheReader output to IngestChunk format
- `moto-sources.json` registry — URL-to-cache-path mapping
- SPA marker detection in probe response
- `--dry-run` shows resolution path
- Tests: T1, T2, T3, T8, T11, T12
- **Tier**: 80% coverage on resolver, smoke on CLI integration

### Wave 2: Browser Engine Integration (P0)
- `BrowserRenderer` protocol with `PlaywrightRenderer` conformance
- `scripts/ingest-browser.js` — Playwright extraction script
- Timeout handling (15s), DOM size cap (5MB), rate limiting (10/min)
- Fallback chain: browser timeout → probe content → error
- `LightpandaRenderer` conformance (behind `--browser lightpanda` flag)
- Tests: T4, T5, T6, T7, T9, T10
- **Tier**: 80% coverage on renderers, 100% on security checks (URL scheme, sandbox)

### Wave 3: Observability + Tuning (P1)
- `resolution_method` metadata on all chunks — audit which path each URL took
- Content completeness scoring — compare rendered vs raw token counts
- Ingest analytics: success rate per resolution method, average latency, failure reasons
- `shikki ingest stats` CLI command — show resolution method distribution
- Auto-escalation tuning: adjust SPA marker list based on observed false negatives
- Tests: integration tests with recorded fixtures, completeness benchmarks

## @shi Mini-Challenge

1. **@Ronin**: The 15s browser timeout covers "slow page" — but what about "page that never finishes loading" (infinite polling, WebSocket keepalive)? Should we use `domcontentloaded` instead of `networkidle` as the wait condition? Trade-off: faster but may miss lazy-loaded content.

2. **@Katana**: The single-redirect-hop rule blocks URL shorteners that chain (bit.ly -> t.co -> actual). Should we allow up to 3 hops but only within a whitelist of known shortener domains? Or just resolve shorteners in the normalization step before the chain starts?

3. **@Metsuke**: The 80% content completeness target is measured against what baseline? Manual copy-paste is subjective. Propose a concrete, automatable baseline — perhaps the Readability algorithm score or a reference corpus of "known good" extractions that we maintain as test fixtures.
