# ShikiRemote — Native App Brief

> **Vision**: Your Shiki command center in your pocket. Review decisions, monitor agents, control budget — from iPhone, Apple Watch, and Mac.
> **Stack**: SwiftUI + CoreKit + NetKit + SecurityKit + ShikiKit
> **Target**: iOS 17+ / watchOS 10+ / macOS 14+
> **Lives in**: `projects/shiki-remote/` — imports shared SPM packages
> **Backend**: Shiki Deno backend (`localhost:3900` / Tailscale IP) — NOT PocketBase, NOT obyw-one
> **CLI companion**: `shiki-ctl` — the app is the mobile face of the same control plane

---

## Why Native (Not Just the PWA)

| Concern | PWA | Native |
|---------|-----|--------|
| Push notifications | ntfy app required | Native APNs, rich notifications |
| Background refresh | Limited, killed by iOS | BGAppRefreshTask, reliable |
| Apple Watch | No | Complications + quick actions |
| Haptics | Basic vibration | UIFeedbackGenerator, full taptic |
| Offline | Service worker cache | Core Data / libsql |
| Keychain | No | SecurityKit (already built) |
| Lock screen widgets | No | WidgetKit + Live Activities |
| Siri / Shortcuts | No | App Intents → "Hey Siri, approve all recommended" |
| Performance | WebView overhead | Metal-backed SwiftUI |

**The PWA is the bridge. ShikiRemote is the destination.**

---

## Core Screens (MVP — 4 screens)

### 1. Decision Queue (Home)

```
┌──────────────────────────────────┐
│ ShikiRemote            ⚡ 3 T1   │
├──────────────────────────────────┤
│                                  │
│  ┌────────────────────────────┐  │
│  │ 🔴 T1 · WabiSabi          │  │
│  │                            │  │
│  │ Where should the seasonal  │  │
│  │ haiku appear?              │  │
│  │                            │  │
│  │ ┌──────────────────────┐   │  │
│  │ │ a) Full-screen overlay│   │  │
│  │ │    ⭐ Recommended     │   │  │
│  │ └──────────────────────┘   │  │
│  │ ┌──────────────────────┐   │  │
│  │ │ b) Card in Today tab │   │  │
│  │ └──────────────────────┘   │  │
│  │ ┌──────────────────────┐   │  │
│  │ │ c) Splash transition │   │  │
│  │ └──────────────────────┘   │  │
│  │                            │  │
│  │ 💬 Or type your answer...  │  │
│  │ ┌──────────────────────┐   │  │
│  │ │                      │   │  │
│  │ └──────────────────────┘   │  │
│  └────────────────────────────┘  │
│                                  │
│  ┌────────────────────────────┐  │
│  │ 🟡 T2 · Maya              │  │
│  │ Animation duration: 0.3s  │  │
│  │ or 0.5s?                  │  │
│  │            [0.3s] [0.5s]  │  │
│  └────────────────────────────┘  │
│                                  │
│  ┌──────────┐                    │
│  │ ✅ All    │ ← batch approve   │
│  │Recommended│   all recommended │
│  └──────────┘                    │
│                                  │
├──────────────────────────────────┤
│  🏠    📊    ⚙️                   │
│ Decide Stats Settings            │
└──────────────────────────────────┘
```

**Key interactions**:
- Tap an option → confirm → sends answer
- Swipe left → dismiss (T2/T3 only, auto-answers with default)
- "All Recommended" button → batch approve all with recommended option
- Pull to refresh
- Badge count shows pending T1s

### 2. Company Dashboard

```
┌──────────────────────────────────┐
│ ← Companies                     │
├──────────────────────────────────┤
│                                  │
│  WabiSabi                        │
│  ●  Active · 2h 14m uptime      │
│  Tasks: 3 running, 1 blocked    │
│  Budget: $2.40 / $5.00 today    │
│  ████████░░░░░ 48%              │
│                                  │
│  Maya                            │
│  ◐  Paused (budget exceeded)    │
│  Tasks: 0 running, 2 pending    │
│  Budget: $5.00 / $5.00 today    │
│  ██████████████ 100%            │
│                                  │
│  Brainy                          │
│  ○  Idle · last active 3h ago   │
│  Tasks: 0 running, 5 pending    │
│  Budget: $0.00 / $3.00 today    │
│  ░░░░░░░░░░░░░ 0%              │
│                                  │
│  ──────────────────────────────  │
│  Total today: $7.40 / $13.00    │
│  Decisions pending: 3 (1 T1)    │
│                                  │
└──────────────────────────────────┘
```

**Data source**: `GET /api/orchestrator/status` + `GET /api/companies`

### 3. Decision Detail (Expanded)

Full-screen view for complex T1 decisions:
- Complete context text (scrollable)
- All options with rationale expanded
- Related task info (title, pipeline, wave)
- Free-text input with keyboard
- "Ask for more context" button (posts a follow-up question back to the agent)

### 4. Settings

- Backend URL configuration (local IP / tunnel URL)
- ntfy topic configuration
- Notification preferences (T1 only / T1+T2 / all)
- Haptic intensity
- Auto-approve T3 toggle

---

## Package Architecture

```
ShikiRemote/
├── Package.swift
├── ShikiRemoteApp/          ← Thin app target
│   ├── ShikiRemoteApp.swift
│   ├── Assets.xcassets
│   └── Info.plist
├── Sources/
│   └── ShikiRemote/         ← SPM module (all logic here)
│       ├── DI/
│       │   └── AppAssembly.swift        ← CoreKit Container setup
│       ├── Coordinators/
│       │   ├── AppCoordinator.swift      ← CoreKit Coordinator
│       │   └── DecisionCoordinator.swift
│       ├── Services/
│       │   ├── DecisionService.swift     ← NetKit HTTP to backend
│       │   ├── NotificationService.swift ← ntfy WebSocket via NetKit
│       │   └── SyncService.swift         ← PocketBase ↔ local sync
│       ├── Models/
│       │   └── (imports ShikiKit DTOs)
│       ├── Views/
│       │   ├── DecisionQueue/
│       │   │   ├── DecisionQueueView.swift
│       │   │   ├── DecisionCardView.swift
│       │   │   └── DecisionDetailView.swift
│       │   ├── Dashboard/
│       │   │   ├── CompanyDashboardView.swift
│       │   │   └── BudgetGaugeView.swift
│       │   └── Settings/
│       │       └── SettingsView.swift
│       └── ViewModels/
│           ├── DecisionQueueViewModel.swift
│           └── DashboardViewModel.swift
├── ShikiRemoteWatch/        ← watchOS target
│   ├── DecisionGlance.swift
│   └── QuickApproveView.swift
├── ShikiRemoteWidgets/      ← WidgetKit
│   ├── PendingDecisionsWidget.swift
│   └── BudgetWidget.swift
└── Tests/
    └── ShikiRemoteTests/
```

### SPM Dependencies

```swift
// Package.swift
dependencies: [
    .package(path: "../packages/CoreKit"),      // DI + Coordinator + AppLog
    .package(path: "../packages/NetworkKit"),    // HTTP + WebSocket (NetKit)
    .package(path: "../packages/SecurityKit"),   // Keychain for auth tokens
    .package(path: "../packages/ShikiKit"),      // Shared DTOs
]
```

**Zero external dependencies.** Everything built on your own packages.

---

## API Integration

### Primary Endpoints (NetKit EndPoint protocol)

```swift
enum ShikiAPI: EndPoint {
    case pendingDecisions
    case answerDecision(id: String, answer: String)
    case orchestratorStatus
    case companies
    case companyDetail(id: String)

    var host: String { Settings.backendHost }
    var scheme: String { Settings.backendScheme }
    var apiPath: String { "/api" }

    var path: String {
        switch self {
        case .pendingDecisions:           return "/decision-queue/pending"
        case .answerDecision(let id, _):  return "/decision-queue/\(id)"
        case .orchestratorStatus:         return "/orchestrator/status"
        case .companies:                  return "/companies"
        case .companyDetail(let id):      return "/companies/\(id)"
        }
    }

    var method: RequestMethod {
        switch self {
        case .answerDecision: return .PATCH
        default:              return .GET
        }
    }

    var body: [String: Any]? {
        switch self {
        case .answerDecision(_, let answer):
            return ["answer": answer, "answeredBy": "@Daimyo (ShikiRemote)"]
        default: return nil
        }
    }
}
```

### WebSocket (Real-time updates)

```swift
// Connect to PocketBase realtime for decisions_mirror collection
let ws = WebSocketClient(url: "wss://back.obyw.one/api/realtime")
// Subscribe to collection changes for live updates
```

---

## Apple Watch MVP

### Complication
- Shows pending T1 count as badge
- Tapping opens the app

### Quick Approve View
```
┌─────────────────────┐
│  🔴 1 Decision      │
│                     │
│  Where should the   │
│  haiku appear?      │
│                     │
│  ┌───────────────┐  │
│  │ ⭐ Recommended │  │
│  │  Full-screen   │  │
│  └───────────────┘  │
│                     │
│  ┌───────────────┐  │
│  │ Open on iPhone│  │
│  └───────────────┘  │
│                     │
└─────────────────────┘
```

- One-tap approve recommended
- "Open on iPhone" for complex decisions needing text input
- Crown scroll through multiple decisions

---

## Live Activities (iOS 16.1+)

When a T1 decision is pending for > 5 minutes:

```
┌─────────────────────────────────────┐
│ 🔴 ShikiRemote  ·  WabiSabi blocked │
│ "Where should the haiku appear?"    │
│            [Approve ⭐] [Open]       │
└─────────────────────────────────────┘
```

Shows on Lock Screen and Dynamic Island. Tapping "Approve ⭐" sends the recommended answer without opening the app.

---

## Siri / App Intents

```swift
struct ApproveAllRecommendedIntent: AppIntent {
    static var title: LocalizedStringResource = "Approve All Recommended"
    static var description = "Approve all pending decisions with their recommended option"

    func perform() async throws -> some IntentResult {
        let decisions = try await DecisionService.shared.fetchPending()
        for decision in decisions where decision.hasRecommended {
            try await DecisionService.shared.answer(
                id: decision.shikiId,
                answer: decision.recommendedOption
            )
        }
        return .result(dialog: "Approved \(decisions.count) decisions")
    }
}
// "Hey Siri, approve all recommended on Shiki"
```

---

## Phased Delivery

### Phase 0 — PWA Bridge (NOW)
- Deploy the PWA (see `spec-shiki-decide-pwa.md`)
- Validates the UX and data flow
- Immediate unblock for @Daimyo

### Phase 1 — iPhone MVP (1 week)
- Decision Queue screen + Decision Detail
- NetKit integration to local backend (manual IP config)
- Push notifications via ntfy (reuse existing infra)
- No auth (local network only)

### Phase 2 — Polish (1 week)
- Company Dashboard screen
- Settings screen
- Tailscale for remote access (no PocketBase mirror needed)
- SecurityKit auth (token in Keychain)
- Dark mode + haptics

### Phase 3 — Platform (1 week)
- Apple Watch app (complication + quick approve)
- WidgetKit (pending count + budget)
- Live Activities for stale T1s
- App Intents / Siri

### Phase 4 — Power Features (later)
- Budget management (adjust daily limits)
- Roadmap prioritization (drag-to-reorder tasks)
- Agent monitoring (live session logs)
- Audit trail viewer
- Multi-user (invite co-founders)

---

## Connectivity Strategy

The app needs to reach the Shiki backend which runs on your Mac. Options by phase:

| Phase | Method | Setup |
|-------|--------|-------|
| PWA + Phase 1 | **Local WiFi** | iPhone → Mac IP on port 3900 |
| Phase 1+ | **Tailscale** | Zero-config VPN mesh, works everywhere |
| Both use same backend | **Shiki Deno** | `localhost:3900` or `100.x.x.x:3900` via Tailscale |

**Recommended**: Install Tailscale on Mac + iPhone. Free tier. Your Mac gets a stable IP like `100.x.x.x` that works from anywhere — home, café, 4G. No port forwarding, no tunnels, no DNS.

---

## Why This Matters

```
Before ShikiRemote:
  Decision created → ntfy buzz → walk to laptop → read context → type answer
  Average response time: 30min - 4 hours
  Agent idle cost: $2-8 per blocked decision

After ShikiRemote:
  Decision created → rich push → tap option on iPhone → done
  Average response time: < 2 minutes
  Agent idle cost: ~$0
```

At 5 T1 decisions/day across 3 companies, saving 30min each:
- **2.5 hours/day** of agent idle time eliminated
- **$10-40/day** in wasted compute saved
- **Your sanity**: stop being the bottleneck

---

## Relationship to shiki-ctl

ShikiRemote is the **mobile face of shiki-ctl**. Same backend, same APIs, same data.

| | shiki-ctl (CLI) | PWA (browser) | ShikiRemote (native) |
|---|---|---|---|
| Where | Mac terminal | Any browser | iPhone / Watch / Mac |
| When | At laptop | Quick bridge | Always |
| Input | Interactive prompt | Tap + text | Tap + text + voice |
| Push | ntfy (3 buttons) | Manual refresh | APNs + Live Activities |
| Offline | N/A | No | Yes (cached state) |

They don't compete — they complement. shiki-ctl for power users at the keyboard, PWA for quick remote access, ShikiRemote for the full mobile experience.

---

## Open Questions for @Daimyo

1. **Tailscale**: Install on Mac + iPhone now? Free tier, zero-config, works everywhere. Alternative: local WiFi only.
2. **Auth for Phase 1?** — Skip auth entirely for local/Tailscale? Or SecurityKit from day 1?
3. **App name**: ShikiRemote? ShikiControl? Shiki? 式?
4. **Project location**: `projects/shiki-remote/` — separate from other projects, imports shared packages
