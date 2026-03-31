# Shiki Decide PWA — Spec v2 (Self-Hosted)

> **Goal**: Unblock @Daimyo's decision workflow from iPhone, zero downtime for running Claude agents.
> **Infra**: Zero new infra. Served by the existing Shiki Deno backend on port 3900.
> **Time to deploy**: 15 minutes (1 route + 1 HTML file).

---

## v1 vs v2 — What Changed

| v1 (killed) | v2 (this) |
|---|---|
| PocketBase mirror on VPS | Direct to Shiki backend |
| ntfy as answer transport | Direct PATCH to `/api/decision-queue/:id` |
| obyw-one dependency | Self-contained in Shiki repo |
| `decide.obyw.one` domain | `localhost:3900/decide` (+ Tailscale for remote) |
| 2 sync scripts | Zero sync (same DB) |
| 10-step deploy | 3-step deploy |

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Mac (Shiki backend — localhost:3900)             │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │ Deno HTTP Server                           │  │
│  │                                            │  │
│  │ GET  /decide              → serves PWA HTML│  │
│  │ GET  /decide/manifest.json→ PWA manifest   │  │
│  │                                            │  │
│  │ GET  /api/decision-queue/pending  (exists) │  │
│  │ PATCH /api/decision-queue/:id     (exists) │  │
│  │ GET  /api/orchestrator/status     (exists) │  │
│  │ GET  /api/companies               (exists) │  │
│  │                                            │  │
│  │ PostgreSQL ← decision_queue (source of     │  │
│  │              truth, no mirror)              │  │
│  └────────────────────────────────────────────┘  │
│                      │                           │
│               Tailscale mesh                     │
│              (100.x.x.x:3900)                    │
│                      │                           │
└──────────────────────┼───────────────────────────┘
                       │
            ┌──────────┴──────────┐
            │  iPhone (Safari /   │
            │  Home Screen PWA)   │
            │                     │
            │  → 100.x.x.x:3900  │
            │    /decide          │
            └─────────────────────┘
```

### Why Tailscale (not tunnel, not VPS proxy)

- **Zero config**: install on Mac + iPhone, done. Both get stable IPs.
- **No new infra**: no Docker container, no DNS record, no VPS routing.
- **Works everywhere**: home WiFi, 4G, café — same IP.
- **Free tier**: 3 users, 100 devices. Way more than enough.
- **Secure**: WireGuard encrypted, no port exposed to internet.
- **Aligns with user preferences**: no external platform dependency.
- **Bonus**: also gives you remote SSH to your Mac from iPhone.

Alternative for at-home-only: use Mac's local IP (e.g. `192.168.1.x:3900`).

---

## Backend Changes

### 1. Add static file serving for `/decide`

**File**: `src/backend/src/routes.ts` — add before the final 404 catch-all:

```typescript
// ── Decide PWA ──
if (path === "/decide" || path === "/decide/") {
  const html = await Deno.readTextFile(
    new URL("../public/decide/index.html", import.meta.url)
  );
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

if (path === "/decide/manifest.json") {
  const manifest = await Deno.readTextFile(
    new URL("../public/decide/manifest.json", import.meta.url)
  );
  return new Response(manifest, {
    headers: { "content-type": "application/manifest+json" },
  });
}
```

**File location**: `src/backend/public/decide/index.html`

### 2. Skip auth for `/decide` route

The PWA is served as a page, not an API call. In `middleware.ts`, the auth check should skip `/decide`:

```typescript
// Skip auth for health checks and the decide PWA
if (path === "/health" || path.startsWith("/decide")) {
  return null; // no auth needed
}
```

**Security note**: The API endpoints (`/api/decision-queue/*`) still require auth. The PWA sends the API key from its settings (stored in localStorage).

### 3. Add API key header support to PWA

The PWA settings panel gets an "API Key" field. All fetch calls include:
```javascript
headers: { "Authorization": `Bearer ${cfg.apiKey}` }
```

---

## shiki-ctl Integration

### New command: `shiki-ctl web`

Opens the decide PWA URL in the default browser or prints the URL for sharing to iPhone.

```swift
// Sources/shiki-ctl/Commands/WebCommand.swift
struct WebCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "web",
        abstract: "Open the Shiki Decide web UI"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Flag(name: .long, help: "Print URL + QR code instead of opening browser")
    var qr: Bool = false

    func run() throws {
        let decideURL = "\(url)/decide"

        if qr {
            // Print URL + generate terminal QR code for iPhone scanning
            print("Shiki Decide PWA:")
            print(decideURL)
            print("")
            // QR code via qrencode (brew install qrencode)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["qrencode", "-t", "UTF8", decideURL]
            try process.run()
            process.waitUntilExit()
        } else {
            // Open in browser
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [decideURL]
            try process.run()
        }
    }
}
```

**Usage**:
```bash
# Open in browser
shiki-ctl web

# Show QR code to scan with iPhone
shiki-ctl web --qr

# Use Tailscale IP for remote access
shiki-ctl web --url http://100.64.0.1:3900 --qr
```

### Integration with `shiki-ctl decide`

The existing `decide` command becomes the CLI fallback. When running interactively on the Mac, `shiki-ctl decide` works as before. When away from laptop, you use the PWA instead. Same backend, same endpoints, same data.

### Integration with ntfy notifications

When a T1 decision is created, the orchestrator already sends an ntfy push. Update the notification to include a **clickable link** to the PWA:

```bash
# In the heartbeat loop's notification hook:
-H "Click: http://100.64.0.1:3900/decide"
```

Flow becomes:
1. Agent creates T1 decision → Shiki DB
2. Heartbeat detects it → ntfy push to iPhone with "Open Decide" link
3. Tap notification → Safari opens `/decide` → full context + options
4. Tap answer → direct PATCH to Shiki backend → agent unblocks

---

## PWA HTML Updates (v2)

Changes from v1:
- **Backend URL default**: `http://localhost:3900` (not PocketBase)
- **API calls go to same origin**: `/api/decision-queue/pending` (relative, no CORS)
- **Auth header**: API key from settings
- **No ntfy publish on answer**: direct PATCH is enough (backend is the source of truth)
- **Company dashboard section**: added as a collapsible panel (uses `/api/orchestrator/status`)

See companion file: `shiki-decide-pwa.html` (updated)

---

## File Layout in Shiki Repo

```
shiki/
├── src/backend/
│   ├── public/
│   │   └── decide/
│   │       ├── index.html        ← PWA (single file, < 15KB)
│   │       └── manifest.json     ← PWA manifest
│   └── src/
│       ├── routes.ts             ← add /decide route
│       └── middleware.ts         ← skip auth for /decide
└── tools/shiki-ctl/
    └── Sources/shiki-ctl/
        └── Commands/
            └── WebCommand.swift  ← shiki-ctl web
```

---

## Deployment Checklist

```
[ ] 1. Create src/backend/public/decide/ directory
[ ] 2. Drop index.html + manifest.json into it
[ ] 3. Add /decide route to routes.ts (before 404 catch-all)
[ ] 4. Skip auth for /decide in middleware.ts
[ ] 5. Restart Deno backend (shiki stop && shiki start)
[ ] 6. Open http://localhost:3900/decide — verify it works
[ ] 7. Install Tailscale on Mac + iPhone (optional, for remote)
[ ] 8. Add WebCommand.swift to shiki-ctl (optional, for QR code)
[ ] 9. Update ntfy notification Click URL to include /decide link
[ ] 10. iPhone: open URL → Share → Add to Home Screen
```

Steps 1-6 are the MVP. A Claude session can do this in 15 minutes.

---

## Future: More Shiki Web Panels

The `/decide` route establishes the pattern. Future panels live under the same backend:

| Route | Purpose | Data Source |
|-------|---------|-------------|
| `/decide` | Decision queue (this spec) | `/api/decision-queue/*` |
| `/board` | Company dashboard + budget | `/api/orchestrator/status` |
| `/radar` | Tech radar results | `/api/radar/*` |
| `/report` | Daily digest viewer | `/api/orchestrator/report` |

All served from `src/backend/public/`, all using the same API, all installable as separate PWA icons on iPhone Home Screen.

Eventually these become screens in ShikiRemote (native app).
