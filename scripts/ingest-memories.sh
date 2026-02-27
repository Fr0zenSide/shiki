#!/bin/bash
# ACC v3 — Memory Encyclopedia Ingestion
# Reads all memory/*.md files, chunks by section, POSTs to /api/memories
# Each chunk gets a category, importance, and the full section content

API="http://localhost:3900/api/memories"
PROJ_ID="00000000-0000-0000-0000-000000000000"
SESS_ID="a0000001-0000-0000-0000-000000000001"
COORD_ID="b0000001-0000-0000-0000-000000000001"

COUNT=0
FAIL=0

post_memory() {
  local category="$1"
  local importance="$2"
  local content="$3"

  # Escape content for JSON (handle newlines, quotes, backslashes)
  local escaped
  escaped=$(printf '%s' "$content" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

  local body="{\"projectId\":\"$PROJ_ID\",\"sessionId\":\"$SESS_ID\",\"agentId\":\"$COORD_ID\",\"content\":$escaped,\"category\":\"$category\",\"importance\":$importance}"

  local result
  result=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API" -H "Content-Type: application/json" -d "$body" 2>/dev/null)

  if [ "$result" = "200" ]; then
    COUNT=$((COUNT + 1))
    echo "  [$COUNT] $category (imp=$importance) — ${#content} chars"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL ($result) $category — ${content:0:60}..."
  fi
}

echo "=== ACC v3 Memory Encyclopedia Ingestion ==="
echo ""

# ── MEMORY.md — Core Rules & Architecture ──
echo "MEMORY.md — Core Rules & Architecture"

post_memory "process" 9 "PROJECT RULES (always follow):
- /retry: Scan all sub-agents/processes. If stuck, needs permission, has network error, or requires attention → relaunch or ask user.
- Git worktrees for cross-branch work — never stash/switch.
- Side projects live in sp/<name>/ with their own epic/<name> branch and dedicated worktree.
- Merge --no-ff into develop, squash merge only develop→main for releases.
- Force push rules: main/develop → ALWAYS ask permission first. epic/story → explain why then push directly. Regular push → just do it.
- Publish to ACC during work sessions.
- Backup context before compaction → memory/backups/.
- Xcode 26.3 filesystem mirroring — no .xcodeproj management needed.
- Split big research tasks: 1 coordinator + 2+ specialists. Keep orchestrator free for user interaction."

post_memory "architecture" 9 "ARCHITECTURE (quick ref):
- iOS 17+ SwiftUI, Clean Architecture + MVVM + Coordinator pattern, custom DI container (Container.swift), Swift 6 strict concurrency.
- @unchecked Sendable + NSLock pattern for thread safety across services.
- PocketBase backend with server-driven config: network → cache → defaults fallback chain.
- Build target: iPhone 17 Pro simulator. .mcp.json for Xcode MCP bridge.
- App entry: WabiSabiApp.swift → AppPresenter (bootstrap) → AppCoordinator (navigation).
- Config models at WabiSabi/Core/Abstracts/Data Layer/Models/Config/."

post_memory "environment" 8 "ENVIRONMENTS & IDENTIFIERS:
- Dev: 127.0.0.1:8090 (local PocketBase)
- Preprod: example.staging.com
- Prod: example.app.com
- Local PocketBase binary: /path/to/pocketbase (ready to run, has migrations)
- App Store ID: REDACTED
- Bundle ID: com.example.app
- ACC v2: Dashboard localhost:5173 | WS localhost:3800
- ACC v3: Dashboard localhost:5174 | API localhost:3900 | DB localhost:5433 | Ollama localhost:11435"

post_memory "context" 6 "SIDE PROJECTS in sp/ folder:
- ACC v2: epic/acc branch, worktree trusting-ellis, files in sp/acc/ (prompt-tools/acc/). Vue 3 + Deno WebSocket.
- ACC v3: epic/acc-v3 branch, worktree acc-v3-workspace, files in sp/acc/. Vue 3 + Deno + PostgreSQL + TimescaleDB + Ollama embeddings.
- AIL: epic/ail branch, worktree ail-workspace, files in sp/ail/. AI Link — distributed computing from ESP32 controllers."

# ── backlog.md — Roadmap & Feature Status ──
echo "backlog.md — Roadmap & Feature Status"

post_memory "roadmap" 9 "CTO ROADMAP (18-26 weeks total):
P0: Shared Components (AnimationPlayer, MarkdownRenderer, SwipeCard, TimerEngine) — ~8 files, 1-2w, no deps
P1: Settings Page (24 files, 3-4w, needs P0) + Pomodoro Timer (12 files, 2-3w, needs TimerEngine)
P2: Gamification/Streaks (14 files, 3-4w, needs Todo observer) + Planner (12 files, 2-3w, needs SwipeCard)
P3: Community Feed (11 files, 2-3w, needs Login)
P4: Siri Shortcuts (~5 files, 1-2w) + CLI Tool (~3 files, 1w) + macOS Support (~15 files, 3-4w)
Source: Documentations/Strategy/02-cto-architecture-plan.md"

post_memory "roadmap" 8 "FIX PLAN (21 regressions across 5 phases):
Phase 1: LoginViewModel — restore MainActor.run{}, remove legacy login/register methods, fix refreshToken(), restore private(set).
Phase 2: DI — remove orphan LoginViewModel registration, clean TestingConfiguration.
Phase 3: Todo UI — fix toast auto-dismiss (DispatchWorkItem cancellation), SwipeActionView measurement, cache filteredTodos with Combine.
Phase 4: Notifications & DeepLink — shared Logger, DI-registered DeepLinkHandler, safe URL construction, surface errors in toggleReminder, replace deprecated badge API.
Phase 5: Calendar/Kanban — simplify date arithmetic, fix non-unique ForEach keys, add swipe actions in calendar day sheet."

post_memory "vision" 9 "USER VISION — 'Use the app without launching it':
- Siri Shortcuts: full workflow integration (add task, start pomodoro, check streak)
- Live Activities: active during focus sessions, planning sessions, task search
- Widgets: interactive home screen widget (iOS 17+), launch pomodoro from widget
- watchOS: companion app, pomodoro timer on wrist
- macOS CLI: core features as terminal commands (system process), status bar icon
All core features should be accessible outside the app context."

post_memory "feature" 8 "FEATURE STATUS SUMMARY:
IMPLEMENTED: Login (full auth, Keychain, tests), Todo (CRUD, list/calendar/kanban views, filters, tracking), App Shell (bootstrap, blocking screens, force update, admin messages), Server Config (AppConfigService, PocketBase hooks, Docker infra), Onboarding (4-page with animations, PR #19).
BASIC: Home (tab nav works, Chat/Relations are stubs).
NOT STARTED: Settings (P1), Pomodoro (P1), Gamification (P2), Planner (P2), Community (P3)."

post_memory "feature" 7 "WORKSHOP FEATURES (brainstorm results):
APPROVED P1:
- Imperfect Days: Declare 'imperfect day' — streak pauses (not breaks). 4/month/habit. Intentional rest > forced failure.
- Resonance Stones: Single irreversible stone per post, builds cairn. Long-press gesture. Wabi-sabi version of 'like' reaction.
APPROVED (Seasonal Practice): Habits designated seasonal, auto-pause/resume with natural year. 4 classical seasons v1, 72 Japanese micro-seasons (sekki) v1.1. App visual theme shifts with seasons.
BACKLOG: Identity Practice Framing, HealthKit Integration, User-Defined Routines, The Repair Log, The Vessel/Japanese Garden, Periodic Tasks."

post_memory "roadmap" 7 "PRE-LAUNCH CHECKLIST:
- Email waitlist: PocketBase collection for landing page email capture
- Landing page polish: SEO optimization, unified version from v2/v2a/v2b/v2c
- Legal page: Simple bullet points with legal force, human-readable, web version
- Social accounts: X/Twitter + Bluesky + Instagram (TikTok low priority)
- Umami referral system: Full tracking MUST be ready before any ad spend
- Blog/micro-blog: On website, cross-post to Medium
- Apple Developer account: $99/year, required for TestFlight + App Store
- In-app review flow: Mood feedback after Pomodoro → rate prompt if 4-5"

post_memory "roadmap" 6 "POST-LAUNCH ENHANCEMENTS (v1.1+):
- Pomodoro Mini-Games: Stone Garden, Cloud Watching, Water Drop, Haiku — each standalone module
- Kintsugi Rich Animation: Lottie 'repair moment', particle effects, texture (Canvas minimal ships at P2)
- Planner Shuffle Day: Random task assignment — fun easter egg
- Mood gauge: Visualization built from collected mood data over time
- Ad budget manager: Automatic inject ad money only when verified premium conversions"

# ── decision-backlog.md — Open Questions ──
echo "decision-backlog.md — Open Questions"

post_memory "decision" 7 "OPEN DECISION QUESTIONS (20 pending):
Q09 [ARCH] MarkdownRenderer approach: A) AttributedString (native, recommended) B) cmark-gfm C library C) WKWebView
Q11 [UX] Seasonal Practice scope for v1: A) Auto-pause/resume + theme shift (recommended) B) Full seasonal config C) Theme shift only
Q12 [UX] Imperfect Days monthly limit: A) 4/month/habit (recommended) B) 3/month C) Unlimited
Q14 [BIZ] Community moderation: A) Defer to P3 (recommended) B) Research now C) Simple report button
Q15 [BIZ] PocketBase long-term: A) Keep, revisit at 10K users (recommended) B) Migrate to Supabase C) Keep + Redis cache"

post_memory "decision" 7 "OPEN DECISION QUESTIONS (continued):
Q17 [BIZ] Email waitlist: A) PocketBase collection + form (recommended) B) Mailchimp C) Defer
Q18 [BIZ] Legal page format: A) Simple bullet points (recommended) B) Full legal template C) Generator service
Q19 [BIZ] Social media accounts: A) X + Bluesky + Instagram now (recommended) B) X only C) Defer until launch
Q20 [VISION] WabiSabi MCP for enterprise: A) Add to P4 B) Research MCP now C) Wait for Apple stance (recommended)
Q23 [ARCH] DeepLink routes: A) Add skeleton routes now (recommended) B) Extend per feature C) Universal Links"

post_memory "decision" 7 "OPEN DECISION QUESTIONS (from Cycle 3):
Q26 [PROC] CI/CD pipeline scope: A) GitHub Actions + Xcode Cloud combo (recommended) B) Xcode Cloud only C) GitHub Actions only
Q27 [UX] Notification cadence: A) Morning + evening recurring at P1 (recommended) B) Per-todo only C) Full notification engine
Q28 [BIZ] Referral system: A) Ship with P1 Settings (recommended) B) Defer until post-launch C) Full StoreKit2 offer codes
Q29 [ARCH] DI Container actor migration: A) Keep NSLock (recommended, performance-critical) B) @MainActor C) Custom global actor
Q30 [VISION] HealthKit scope: A) Defer to v1.1 (recommended) B) P1 read-only C) Full integration"

post_memory "decision" 7 "OPEN DECISION QUESTIONS (Cycle 3 surfaced):
Q31 [PROC] Apple Developer Account setup: A) Set up this week (blocks TestFlight) B) Next week C) Defer until feature-complete
Q32 [ARCH] Trigger Action Engine design: A) Simple EventBus + RuleEngine protocol (recommended) B) Combine pipeline C) PocketBase-driven rules
Q33 [PROC] Analytical tagging plan: A) Define now, implement with trigger engine (recommended) B) Basic events first C) Wait for UX review
Q34 [ARCH] FeatureFlags bit-mask: A) Int64 OptionSet + PocketBase integer field (recommended) B) Two fields C) Bit string
Q35 [ARCH] Tab architecture Me placement: A) Top-right avatar → sheet (recommended) B) Hamburger menu C) Gear icon → settings"

# ── planner-state.md — Decision Log ──
echo "planner-state.md — Decision Log"

post_memory "decision" 9 "DECISIONS MADE (15 total, 2026-02-27):
Q01 [BIZ] Pricing confirmed: REDACTED/mo | REDACTED/yr | REDACTED lifetime (A)
Q02 [ARCH] Roadmap confirmed: P0→P1→P2→P3 locked (A)
Q03 [UX] Animation approach: SwiftUI Canvas minimal (A)
Q04 [UX] Tab navigation: Today | Garden | Community | Me. Plan → Settings+Today (custom)
Q05 [PROC] Git strategy: Rebase + merge --no-ff (B)
Q06 [PROC] Fix plan timing: Start Phase 1 fixes now (A)
Q07 [ARCH] Timer architecture: Combine timer publisher (C)
Q08 [ARCH] Swipe implementation: SwiftUI DragGesture (A)
Q10 [PROC] Test coverage target: 60% (pragmatic) (A)
Q13 [UX] Onboarding: 3 screens, animated (A, expanded to 4)
Q16 [BIZ] Launch strategy: TestFlight beta first → private feedback → then Store (B)
Q21 [ARCH] Navigation: 2-tab Today + Growth. Me → top corner. Community 3rd tab later (A)
Q22 [ARCH] Feature flags: Bit-mask integer (compact + obfuscated) (B)
Q24 [UX] In-app review trigger: First of 10th todo OR 7-day streak. Build trigger engine (custom)
Q25 [PROC] Beta strategy: Private invites only (realistic for 5d timeline) (B)"

post_memory "process" 8 "PLANNER STATE (current):
- Last cycle: 2026-02-27 ~04:00 (Cycle 3), 3 cycles today
- Queue: 20/20 (refilled with Q31-Q35)
- Active agents: 0 (all 5 PRs shipped + ACC v3 done)
- DEADLINE: v1 target 2026-03-02 (3 days from session start)
- Completed PRs: #15 (StoreKit), #16 (FeatureFlags), #17 (AppConfig), #18 (Coordinator), #19 (Onboarding)
- Ready to dispatch: Tab migration (Q21), FeatureFlags bit-mask (Q22+Q34), Trigger engine (Q24+Q32), Apple Dev account (Q16+Q31)"

# ── commands-reference.md — Commands & Agents ──
echo "commands-reference.md — Commands & Agents"

post_memory "commands" 7 "AGENT PERSONAS (mention @name to invoke):
@Shogun — Competitive Intelligence Analyst: market positioning, benchmarks, user acquisition, pricing strategy
@Sensei — CTO / Technical Architect: iOS/SwiftUI, Swift 6, architecture, feasibility, code quality
@Hanami — Product Designer / UX Lead: user psychology, wabi-sabi philosophy, accessibility, emotional design
@Kintsugi — Philosophy & Repair Specialist: wabi-sabi, kintsugi metaphor, imperfection as beauty
@Enso — Brand Identity & Mindfulness: brand voice, tone consistency, mindfulness practice
@Tsubaki — Content & Copywriting: conversion copy, storytelling, SEO, headlines
@Daimyo — Founder (user): final authority on all strategic, product, and business questions
Multi-agent: '@Shogun launch discussion with @Sensei and @Hanami' triggers brainstorm."

post_memory "commands" 6 "COMMANDS & TOOLS REFERENCE:
Custom: /retry (fix stuck agents), /plan (5-question cycle), /plan status (queue health), /report (daily report), @backlogger (refresh queue)
Built-in: /help, /clear, /compact, /sandbox, /fast, /tasks
Prompt tools (in prompt-tools/): my-dev-agency.md (ACC foundational spec), generate-feature-docs.md (pre-PR docs), git-weekly-stats.md (weekly report)
Installed skills: Swift Concurrency (.agents/skills/swift-concurrency/), Swift Testing (.agents/skills/swift-testing-expert/), SwiftUI Expert (.agents/skills/swiftui-expert-skill/)
Sandbox auto-allowed: git, gh, xcodebuild, xcrun, swift, brew, npm, docker, curl, ls, mkdir, cp, mv, rm, find, grep, rg"

# ── process-optimizer.md — Process Design ──
echo "process-optimizer.md — Process Design"

post_memory "process" 7 "PROCESS OPTIMIZER PROTOCOL (@backlogger + @planner):
Constraints: No timers, no cron, no persistent background processes. Everything is pull-based.
@backlogger: Maintains 20 prioritized decision questions in decision-backlog.md. Refills when queue < 15. Brainstorms with @ux/@brainstormer/@cto when < 10.
@planner: Picks 5 questions per cycle, mixed categories (max 2 from same). Presents rapid-fire (<15s per answer). After answers → dispatch agents, update state.
Session startup: Read 3 state files → print status → refill if needed → suggest /plan if >2h since last → suggest /report at 17:00-18:00.
Self-optimization: Every 5 cycles track answer speed, skip rate, queue drain. Deprioritize categories with >30% skip rate."

# ── project-structure.md — File Tree ──
echo "project-structure.md — File Tree"

post_memory "architecture" 8 "iOS APP FILE STRUCTURE:
WabiSabi/Features/App/ — WabiSabiApp.swift (@main), AppPresenter.swift (bootstrap), AppCoordinator.swift (navigation), AppTrackInfo.swift (Umami), BlockingScreen/, ForceUpdate/, AdminMessages/
WabiSabi/Features/ — Home/, Login/ (full auth + DI), Todo/ (CRUD + kanban/calendar/chat), Onboarding/
WabiSabi/Core/Abstracts/Data Layer/ — Models/Config/ (AppConfig, AdminMessage, UserStatus, BootstrapResponse), Models/Env/ (Environment, Distribution, FeatureFlags), Models/Plist/, Repositories/ (ConfigEndPoint)
WabiSabi/Core/Abstracts/Domain/ — Repositories/ (NetworkProtocol, SystemServices, HTTPNetwork/), UseCases/ (AppConfigService, CRUDUseCase/)
WabiSabi/Core/DI/ — Container.swift, assemblies, factories, mocks
WabiSabi/Core/Tools/ — Logger, NetworkStatus, AppIdentity, VersionComparator
WabiSabi/Commons/Presentation/ — Reusable UI (Toast, Chat, TabBar, Confetti)"

post_memory "architecture" 7 "POCKETBASE BACKEND STRUCTURE:
pocketbase/Dockerfile — Alpine + PocketBase v0.25.3
pocketbase/docker-compose.yml — Dev setup (port 8090)
pocketbase/docker-compose.prod.yml — Prod overlay (Caddy TLS, resource limits)
pocketbase/pb_hooks/ — config_route.js (GET /api/custom/app-bootstrap), rate_limit.js (60/min), seed.js (idempotent)
pocketbase/pb_migrations/ — 1708800000_create_collections.js (app_configs, user_statuses, admin_messages)
pocketbase/scripts/ — init-instance.sh (provisioning), export-schema.sh, backup.sh
CI/CD: .github/workflows/ — ios-build.yml, pocketbase-deploy.yml, schema-check.yml"

# ── backup-strategy.md — Recovery ──
echo "backup-strategy.md — Recovery Protocol"

post_memory "process" 6 "BACKUP & RECOVERY PROTOCOL:
When: Before compaction, end of work session, after major milestones, every ~30min of active work.
What: Session date, accomplishments with file paths, decisions made, active state (branch, PRs, build), files created/modified, pending work, JSONL link.
Naming: backups/YYYY-MM-DD_session-NN_<trigger>.md (triggers: pre-compact, end-session, milestone-<name>, periodic).
Recovery: Use Encyclopedia Sub-Agent pattern — Explore agent reads backups newest→oldest, greps keywords, falls back to JSONL transcripts.
JSONL transcripts: Raw conversation, each line is JSON with role+content. Use Explore agent to process (don't load full files into main context).
Maintenance: Delete backups >30 days (keep milestones forever), consolidate weekly."

# ── docs-index.md — File References ──
echo "docs-index.md — Documentation Index"

post_memory "context" 5 "DOCUMENTATION INDEX:
Primary workspace: /path/to/project/
- prompt-tools/AGENT.md — iOS feature implementation guide (MVVM + Coordinator, 5 phases)
- prompt-tools/AAGENT.md — Universal dev agent guide (1626 lines)
- prompt-tools/my-dev-agency.md — ACC foundational spec (all agent roles, feature requirements)
Secondary: /Users/jeoffrey/.wsx/26-Perso/WabiSabi-claude/
- Documentations/ARCHITECTURE.md — App architecture (52KB)
- Documentations/Strategy/01-05 — Creative brainstorm, CTO plan, UX analysis, Marketing, Daimyo review
- Documentations/Strategy/06-swiftui-testing-strategy.md — Testing strategy
- Documentations/Design/unified-design-system-proposal.md — Zen + Sakura tokens
- Documentations/Login/README.md — Login feature docs (70 tests, all passing)"

# ── session backup — Wave 1-2 Accomplishments ──
echo "session-backup — Wave 1-2 History"

post_memory "context" 6 "SESSION HISTORY — Wave 1-2 (2026-02-25):
Wave 1 (iOS) completed: Agent 1A (BlockingScreenView — kill switch, maintenance, ban overlays), Agent 1B (VersionComparator + ForceUpdateView), Agent 1C (AdminMessageBannerView + AdminMessageListView), Agent 1D (Feature flag merging in SystemServices.swift), Manual: AppPresenter integration.
Wave 2 (Infrastructure) completed: Agent 2A (Docker — Dockerfile, docker-compose, Caddyfile), Agent 2B (Schema — pb_migrations, pb_hooks/seed.js, init scripts), Agent 2C (CI/CD — ios-build.yml, pocketbase-deploy.yml, schema-check.yml).
PRs: #2 fix/umami-website-ids merged, #3 feat/app-open-tracking merged, #4 closed (superseded), #5 epic/server-driven-config draft opened.
Daimyo Review reconstructed: 20 questions, P0-P4 roadmap validation, 4 cross-doc conflicts, 13 locked UX decisions."

post_memory "context" 6 "SESSION HISTORY — Cycle 3 (2026-02-27):
5 iOS PRs shipped in parallel: #15 (StoreKit2 subscription — 6 files), #16 (FeatureFlags — 3 files), #17 (AppConfig service — 8 files), #18 (AppCoordinator — 4 files), #19 (Onboarding 4-page — 7 files).
ACC v3 infrastructure: Installed colima (Docker runtime), docker-compose plugin, started PostgreSQL + TimescaleDB, connected to LM Studio for embeddings (text-embedding-nomic-embed-text-v1.5).
Cycle 3 decisions: Q21 (2-tab nav), Q22 (bit-mask flags), Q16 (TestFlight first), Q24 (trigger engine), Q25 (private beta).
Swift 6 fixes: NSLock in async contexts (StoreKitService, MockStoreKitService), withAnimation return value (OnboardingPage3View), foregroundStyle iOS 17 compat (OnboardingPage4View)."

# ── Design System Tokens ──
echo "Design System — Color Tokens"

post_memory "architecture" 7 "WABISABI DESIGN SYSTEM TOKENS:
Primary: Moss #6B7F5E (wsAccent, wsMoss). Used for all primary actions, navigation highlights.
Secondary: Sakura Pink for celebrations ONLY. Kintsugi Gold for streak repair moments.
Dark theme: wsBackground #0F1210, wsSurface #1A1E1B, wsSurfaceElevated #242A26.
Text: wsTextPrimary #E8E4DF, wsTextSecondary #B5AFA8, wsTextMuted #7A7570.
Typography: .ws(.title), .ws(.body), .ws(.caption) — custom font system.
Spacing: WSSpacing enum (xs=4, sm=8, md=12, lg=16, xl=24, xxl=32).
Philosophy: minimal, nature-inspired, imperfection-embracing. No sharp edges, no aggressive colors."

# ── Pricing & Business ──
echo "Pricing & Business Model"

post_memory "decision" 8 "PRICING & BUSINESS MODEL (locked):
Tiers: Seed (free), Growth (REDACTED/mo), Harvest (REDACTED/yr), Evergreen (REDACTED lifetime).
Trial: Stealth trial — time-based progressive nudging via TrialPhase enum (stealth → gentle → urgent → expired). No hard feature gate initially.
Implementation: StoreKit 2 only (no RevenueCat), Apple-only payments. PR #15 shipped.
Subscription tier mapping: ProductID.all maps to SubscriptionTier enum. currentTier determines feature access via isPremium computed property.
Transaction listener: Runs continuously, processes Transaction.updates, refreshes entitlements on changes."

echo ""
echo "=== DONE ==="
echo "Inserted: $COUNT memories"
echo "Failed: $FAIL"
