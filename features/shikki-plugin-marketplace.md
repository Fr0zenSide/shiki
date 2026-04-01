---
title: "Shikki Plugin Marketplace — Build, Share, Certify"
status: draft
priority: P2
project: shikki
created: 2026-04-01
authors: "@Daimyo + @Sensei brainstorm"
epic: epic/plugin-marketplace
depends-on:
  - shikki-creative-studio.md (first plugin, proving ground)
---

# Shikki Plugin Marketplace

> Build locally. Share via GitHub. Certify for enterprise. Search instantly.

---

## 1. Plugin Structure

A plugin is a folder with `manifest.json` + code:

```
my-plugin/
  manifest.json          ← identity, deps, commands, certification
  Sources/               ← Swift code (SPM package) OR
  prompts/               ← skill markdown files OR
  scripts/               ← bash/python scripts
  README.md              ← documentation
  CHANGELOG.md           ← version history
```

## 2. Three Distribution Tiers

### Tier 1: Local (today — implemented)
- Build: create folder + manifest.json
- Share: zip / git clone
- Install: `shikki plugins install ./my-plugin/`
- Trust: user's responsibility

### Tier 2: GitHub Registry (near term)
- Build: GitHub repo with manifest.json at root
- Share: `shikki plugins install github:obyw-one/creative-studio`
- Index: Static JSON registry in `shikki-plugins/registry` repo
- Trust: GitHub stars + community reviews + CI validation

### Tier 3: Marketplace Website (long term)
- Build: same repo, submit for certification
- Share: `shikki plugins install creative-studio` (by name)
- Index: Astro static site at plugins.shikki.dev
- Trust: 4-level certification (uncertified → enterpriseSafe)

## 3. Registry Architecture

```
GitHub repo: shikki-plugins/registry
  plugins/
    obyw-one/creative-studio.json
    community/code-review-plus.json
    community/tmux-spotify.json
  index.json                          ← auto-generated, compressed

Astro site: plugins.shikki.dev
  → Built from registry repo (GitHub Actions)
  → Static, no backend, Pagefind search
  → Plugin detail pages: README + install cmd + cert badge

Daily CI:
  → Crawl registered plugins for updates
  → Verify checksums still match
  → Security scan (dependency audit)
  → Rebuild index.json + Astro site
```

## 4. Submission Flow

```
1. Developer creates plugin repo with manifest.json
2. Opens PR to shikki-plugins/registry
3. CI runs:
   → manifest.json schema validation
   → checksum computation + verify
   → dependency audit (known vulnerabilities)
   → license compatibility check (must be AGPL-compatible)
4. Community review (upvotes, comments on PR)
5. Optional: Shikki team review → shikkiCertified badge + GPG signature
6. PR merged → GitHub Action rebuilds index + Astro site
7. Plugin live on marketplace within minutes
```

## 5. Client-Side Search (no backend)

```
shikki plugins search "video"
  → downloads index.json (~100KB compressed, cached locally)
  → filters client-side (instant, works offline)
  → shows results with cert badges

Same pattern as Homebrew formulae — compressed client-side index,
daily automated crawl, zero backend infrastructure.
```

## 6. Certification Levels

| Level | Badge | Who | What |
|-------|-------|-----|------|
| uncertified | — | anyone | local use, no review |
| communityReviewed | 👥 | PR merged to registry | CI passed, community upvotes |
| shikkiCertified | ✅ | Shikki team | manual review, GPG signed by shikki-bot |
| enterpriseSafe | 🏢 | security audit | full audit report, compliance check |

## 7. Install Flow

```
# Local
shikki plugins install ./path/to/plugin

# GitHub (Tier 2)
shikki plugins install github:obyw-one/creative-studio
  → clone repo → verify manifest → verify checksum → copy to ~/.shikki/plugins/ → register

# Marketplace (Tier 3)
shikki plugins install creative-studio
  → fetch index.json → find plugin URL → clone → verify → install
```

## 8. Implementation Waves

### Wave 1: GitHub install (P2)
- `shikki plugins install github:<owner>/<repo>`
- Clone, verify manifest, verify checksum, register
- **10 tests**

### Wave 2: Registry repo + CI (P2)
- Create `shikki-plugins/registry` repo
- GitHub Actions: validate manifest, compute checksum, build index.json
- PR-based submission flow
- **5 tests** (CI scripts)

### Wave 3: Astro marketplace site (P3)
- Astro + Starlight + Pagefind
- Plugin detail pages from registry JSON
- Cert badge rendering
- Deploy to plugins.shikki.dev

### Wave 4: Client-side search (P3)
- `shikki plugins search` downloads + caches index.json
- Offline search with fuzzy matching
- **8 tests**

---

## 9. @shi Mini-Challenge

1. **@Ronin**: A malicious plugin could register a command that shadows a built-in (e.g., `shikki ship` → runs attacker code). Should the registry reject plugins whose commands conflict with built-ins?
2. **@Katana**: The GPG signature for shikkiCertified — who holds the private key? If it's on the CI server, a compromised CI = compromised trust chain.
3. **@Sensei**: Should plugins be SPM packages (compiled Swift) or scripts (bash/python)? Or both? SPM gives type safety but requires Swift on the user's machine.
