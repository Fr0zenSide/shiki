# Feature: Shiki Augmented TUI — Command Palette, Chat, Editor Mode

> **Type**: /md-feature
> **Priority**: P1 — core DX, builds on Observatory + Event Router
> **Status**: Spec (validated by @Daimyo + @Shi team 2026-03-18)
> **Depends on**: Event Router (P0.5), Observatory (P1), TUI layer (DONE)
> **Lineage**: Revival of acc dashboard v3 FZF panel + chat module, now native TUI

---

## 1. Problem

The web dashboard (`src/frontend/`) has powerful features — FZF search, chat, alias targeting, command palette — but:
1. It requires Docker + browser (heavy)
2. The TUI is where the user lives 8h/day
3. Features were lost across dashboard versions
4. No way to search/target agents from the terminal during work

## 2. What Exists (web, to be ported to TUI)

| Web Feature | File | TUI Status |
|-------------|------|------------|
| FZF Panel (`Cmd+P`) | `src/frontend/src/components/fzf/` | NOT PORTED |
| Chat Module | `src/frontend/src/pages/ChatPage.vue` | NOT PORTED |
| Alias System (`@:`) | `src/frontend/src/composables/useAliasStore.ts` | NOT PORTED |
| Command Palette (`>`) | Built into FZF | NOT PORTED |
| Dashboard | `src/frontend/src/pages/DashboardPage.vue` | PARTIAL (shiki dashboard) |
| Agent targeting | Pinia store + WebSocket | NOT PORTED |

## 3. Solution — Three TUI Modules

### 3A. Command Palette (fzf revival)

Triggered by a keybinding in any Shiki TUI screen. Fuzzy search across everything:

```
┌─ SHIKI ──────────────────────────────────────────────────────┐
│ > search anything...                                          │
│                                                               │
│  SESSIONS                                                     │
│  ● maya:spm-wave3          working    [feature/v3-wave1]      │
│  ● wabisabi:onboard        prOpen     [story/onboarding]      │
│  ○ flsh:mlx                done       [feature/mlx]           │
│                                                               │
│  COMMANDS                                                     │
│  > /status                 Show orchestrator overview          │
│  > /doctor                 Diagnose environment                │
│  > /review 6               Review PR #6                       │
│  > /decide                 Answer pending decisions            │
│                                                               │
│  FEATURES                                                     │
│  □ shiki-observatory.md    P1 — Session intelligence          │
│  □ shiki-event-router.md   P0.5 — Intelligent middleware      │
│                                                               │
│  ↑/↓ navigate · Enter select · Tab cycle · Esc close          │
└──────────────────────────────────────────────────────────────┘
```

**Prefix modes** (from web FZF, adapted for TUI):

| Prefix | Scope | Source |
|--------|-------|--------|
| (none) | Everything | All sources fuzzy-merged |
| `s:` | Sessions | SessionRegistry |
| `a:` | Agents/personas | Running sessions + persona info |
| `@` | Alias targeting | Alias store (agents, teams, scopes) |
| `>` or `/` | Commands | Registered shiki subcommands |
| `f:` | Features/specs | `features/*.md` files |
| `t:` | Tasks | Dispatcher queue |
| `p:` | PRs | `gh pr list` cache |
| `m:` | Memory/knowledge | Shiki DB search |
| `d:` | Decisions | Decision journal |

**Data sources**:
- Local: SessionRegistry, feature files, git branches, commands
- DB: `shiki_search` MCP tool (when available) or `POST /api/memories/search`
- Git: `gh pr list`, branches
- Two-phase like web: instant fuzzy on local, debounced semantic on DB

**Actions on selection**:
- Session → attach to tmux pane, or show in Observatory detail
- Command → execute command
- Feature → open in `$EDITOR`
- Task → show task detail, option to claim
- PR → open review TUI
- Decision → open in Questions tab
- Memory → show in detail panel

### 3B. Chat / Agent Targeting

Inline messaging to running agents or the orchestrator. The `@` system from acc dashboard:

```
┌─ SHIKI CHAT ─────────────────────────────────────────────────┐
│                                                               │
│  @orchestrator How many slots are available?                  │
│  ┌─ Orchestrator: 1/2 slots free. maya:spm-wave3 running.    │
│                                                               │
│  @maya:spm-wave3 What's your current progress?                │
│  ┌─ Agent: Implementing SessionRegistry, 6/8 tests passing.  │
│  │  Blocked on: TmuxDiscoverer parse format.                  │
│                                                               │
│  @shi What's the risk assessment for PR #6?                   │
│  ┌─ @Sensei: Architecture PASS, 3 issues in Gate 1b...        │
│  ┌─ @tech-expert: Hygiene PASS, Documentation PASS...         │
│                                                               │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ @maya:spm-wave3 Try using tmux list-panes -s instead     │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                               │
│  Enter send · Tab autocomplete @target · Esc close            │
└──────────────────────────────────────────────────────────────┘
```

**Targeting resolution**:
- `@orchestrator` → HeartbeatLoop / main Claude session
- `@maya:spm-wave3` → specific agent session (inject via EventBus → tmux send-keys)
- `@shi` or `@shiki` → full team review (dispatches to all personas)
- `@Sensei`, `@Hanami`, etc. → specific persona prompt
- `@all` → broadcast to all running sessions

**Delivery mechanism**:
- EventBus `agentQuestion` event → picked up by agent's heartbeat or hook
- For tmux agents: `tmux send-keys` with the message
- For the orchestrator: direct prompt injection

### 3C. Editor Mode (distraction-free)

A minimal editor for composing prompts, specs, or messages with augmented search inline:

```
┌─ SHIKI EDITOR ──────────────────── feature/auth-flow.md ─────┐
│                                                               │
│  # Auth Flow Specification                                    │
│                                                               │
│  ## Requirements                                              │
│  - [ ] JWT token refresh on 401                               │
│  - [ ] Keychain storage for refresh token                     │
│  - [ ] @SecurityKit integration for token management          │
│           ↑                                                   │
│      ┌─ AUTOCOMPLETE ──────────────────────────────┐         │
│      │ @SecurityKit — Keychain, AuthPersistence     │         │
│      │ @CoreKit — DI Container, Extensions          │         │
│      │ @NetKit — HTTP + WebSocket networking         │         │
│      └──────────────────────────────────────────────┘         │
│                                                               │
│  ## Context                                                   │
│  Based on /d:auth-middleware-decision/ we chose JWT over...   │
│              ↑                                                │
│      ┌─ DECISION SEARCH ───────────────────────────┐         │
│      │ auth-middleware-decision (2026-03-15)         │         │
│      │   "JWT over session tokens — stateless..."    │         │
│      └──────────────────────────────────────────────┘         │
│                                                               │
│  Ctrl-S save · Ctrl-P search · @ autocomplete · Esc exit      │
└──────────────────────────────────────────────────────────────┘
```

**Philosophy**: distraction-free like Emacs focused mode. The editor does ONE thing — compose text. But `@` and `/` trigger inline augmented search from the command palette.

**Inline triggers**:
- `@` → autocomplete agents, packages, personas, aliases
- `/d:` → search decisions
- `/f:` → search features
- `/m:` → search memories
- `Tab` → accept autocomplete
- `Ctrl-P` → full command palette overlay

**File operations**:
- `Ctrl-S` → save to file
- `Ctrl-Shift-S` → save + send as prompt to target agent
- `Ctrl-N` → new buffer
- `Ctrl-O` → open file (via command palette)

---

## 4. Command Rebranding — @Shi Team Review

### Current commands and proposed aliases

| Current | Alias | Keep? | Team verdict |
|---------|-------|-------|-------------|
| `shiki start` | `shiki up` | YES | `up`/`down` is more natural than `start`/`stop` |
| `shiki stop` | `shiki down` | YES | Pair with `up` |
| `shiki restart` | `shiki reload` | YES | `reload` implies "keep state, restart process" |
| `shiki attach` | `shiki a` | YES | Short alias for frequent action |
| `shiki status` | `shiki s` | YES | Most used command, needs 1-char alias |
| `shiki board` | `shiki b` | MERGE | Merge into `shiki dashboard` with `--board` flag |
| `shiki history` | `shiki log` | RENAME | `log` is more unix-natural |
| `shiki heartbeat` | (internal) | HIDE | Should not be user-facing |
| `shiki wake` | — | YES | Clear intent |
| `shiki pause` | — | YES | Clear intent |
| `shiki decide` | `shiki d` | YES | Frequent interactive command |
| `shiki report` | — | YES | But consider `shiki digest` |
| `shiki pr` | `shiki review` | ALIAS | `review` is the action, `pr` is the object |
| `shiki doctor` | `shiki dr` | YES | New, keep |
| `shiki dashboard` | `shiki dash` | YES | New, keep |
| NEW: `shiki search` | `shiki /` | ADD | Command palette from terminal |
| NEW: `shiki chat` | `shiki @` | ADD | Agent targeting from terminal |
| NEW: `shiki edit` | `shiki e` | ADD | Editor mode |
| NEW: `shiki observe` | `shiki o` | ADD | Observatory TUI |
| NEW: `shiki push` | — | ADD | Stdin prompt ingestion (already spec'd) |

### Alias philosophy
- 1-char aliases for daily commands: `s`, `a`, `b`, `d`, `e`, `o`
- Action verbs over nouns: `review` over `pr`, `observe` over `observatory`
- Unix conventions: `up`/`down`, `log`, `push`

---

## 5. # Notation — The "Where" Dimension

The three targeting dimensions: `@` = who, `/` = what, `#` = where.

| Prefix | Dimension | Question it answers | Example |
|--------|-----------|-------------------|---------|
| `@` | Agent/persona | Who should handle this? | `@maya:spm-wave3`, `@Sensei`, `@all` |
| `/` | Command/action | What should happen? | `/status`, `/review 6`, `/decide` |
| `#` | Scope/context | Where does this apply? | `#maya`, `#PR-6`, `#wave1`, `#today` |

### 5.1 Sticky Context

`#` sets a persistent scope. Everything after is filtered:

```
$ #maya
  [scope: maya]
$ status           → maya sessions, maya tasks, maya budget only
$ @agent progress  → maya's agent, not wabisabi's
$ /review          → maya PRs only
$ /log             → maya history only
$ #PR-6            → narrow further: maya + PR 6
$ #                → clear all scopes (back to global)
```

Multiple `#` stack: `#maya #wave1` = maya project, wave 1 only.

### 5.2 Predefined Scopes

| Scope | Resolves to | EventScope mapping |
|-------|------------|-------------------|
| `#<company>` | Project slug | `.project(slug:)` |
| `#PR-<N>` | PR number | `.pr(number:)` |
| `#<branch>` | Git branch | custom tag |
| `#today` | Since midnight | `minTimestamp: today` |
| `#wave<N>` | Wave number | custom tag |
| `#session-<id>` | Specific session | `.session(id:)` |

### 5.3 User-Defined Scopes

Users can define shortcuts on the fly:

```
$ #define auth = #maya #wave1 f:auth
  [saved: #auth → maya + wave1 + files matching "auth"]
$ #auth
  [scope: maya, wave1, auth files]
```

Stored in `~/.config/shiki/scopes.json`. Persists across sessions.

### 5.4 Scope in Command Palette

When command palette is active, `#` narrows results:

```
┌─ SHIKI ──────────────────────────────────────────────────┐
│ #maya > search...                                [scope: maya]
│                                                           │
│  SESSIONS (maya only)                                     │
│  ● maya:spm-wave3          working                        │
│                                                           │
│  TASKS (maya only)                                        │
│  □ SPM wave 3 migration    in-progress                    │
│  □ Public API extraction   queued                         │
│                                                           │
│  FEATURES (maya only)                                     │
│  □ maya-spm-migration.md   P0                             │
└──────────────────────────────────────────────────────────┘
```

### 5.5 Scope in Editor / Chat

Works inline in the prompt composer and chat:

```
@Sensei #maya What's the risk of the SPM migration?
```

The scope `#maya` tells Sensei to only consider maya context — not pull in wabisabi or flsh knowledge. The agent receives the scope as metadata, and the Event Router enriches with maya-specific context.

### 5.6 The Full Intent Grammar

Three tokens express any interaction:

```
@who #where /what

@Sensei #maya /review       → Sensei reviews maya's code
@all #today /status         → all agents report today's status
@maya:agent #PR-6 /fix      → maya's agent fixes PR 6 issue
```

Each token is optional. Missing dimensions default to global:
- No `@` → orchestrator handles it
- No `#` → global scope
- No `/` → inferred from context (chat = message, palette = search)

## 6. Tmux Status Plugin

Replace the heartbeat pane (wastes 20% of screen) with a status bar widget.

### 6.1 `shiki status --mini` (compact mode)

Default (collapsed):
```
●2 ▲1 ○3 Q:1 $4/$15
```

Expanded (via keybinding toggle):
```
maya:● wabi:▲ flsh:○ | Q:1 | $4.20/$15
```

- `●` green = working normally
- `▲` yellow = needs attention (question pending, budget warning)
- `✗` red = failed, blocked, terminated
- `○` dim = idle/done
- `Q:N` = pending questions count — **the killer metric**
- `$spent/$budget` = daily cost at a glance

### 6.2 tmux Status Bar Integration

```bash
# Added by shiki start — lives in status-right
set -g status-right '#(shiki status --mini)'
set -g status-interval 30  # refresh every 30s
```

User can configure in `~/.config/shiki/tmux.conf`:
```bash
SHIKI_STATUS_EXPANDED=false  # default collapsed
SHIKI_STATUS_BUDGET=true     # show budget (default true)
SHIKI_STATUS_INTERVAL=30     # refresh interval
```

### 6.3 Shiki-Scoped Keybindings (no tmux collision)

tmux `prefix + ?` is tmux help — we don't touch it. Instead, Shiki uses its own prefix:

**Option A: Double-prefix** — `prefix prefix` (press prefix twice)
```bash
# In tmux.conf added by shiki start
bind-key C-b switch-client -T shiki  # second prefix enters shiki key table
bind-key -T shiki s display-popup -E "shiki status"
bind-key -T shiki d display-popup -E "shiki decide"
bind-key -T shiki o display-popup -E "shiki observe"
bind-key -T shiki / display-popup -E "shiki search"
bind-key -T shiki m display-popup -E "shiki menu"
bind-key -T shiki t run-shell "shiki status --toggle-expand"
```

Usage: `Ctrl-B Ctrl-B s` = shiki status popup. `Ctrl-B Ctrl-B m` = mini menu.

**Option B: Dedicated prefix** — `Ctrl-\` (unused by most setups)
```bash
set -g prefix2 C-\\
bind-key -T prefix2 s display-popup -E "shiki status"
# etc.
```

**Option C: Direct binds in root table** — `Ctrl-B S` (capital S, no conflict)
```bash
bind-key S display-popup -E "shiki status"
bind-key D display-popup -E "shiki decide"
bind-key O display-popup -E "shiki observe"
bind-key M display-popup -E "shiki menu"
bind-key T run-shell "shiki status --toggle-expand"
```

Recommend Option C — simplest, capital letters don't conflict with tmux defaults.

### 6.4 `shiki menu` — The ? Replacement

Since we can't use `prefix + ?`, the menu lives at `prefix + M`:

```
┌─ SHIKI ──────────────────────────┐
│                                  │
│  S  status      D  decide        │
│  A  attach      O  observe       │
│  /  search      @  chat          │
│  E  edit        DR doctor        │
│                                  │
│  UP  start      DN  stop         │
│  R   reload     T   toggle bar   │
│                                  │
│  Esc close                       │
└──────────────────────────────────┘
```

### 6.5 Toggle Expand/Collapse

`prefix + T` toggles between compact and expanded status bar:

```
Collapsed:  ●2 ▲1 ○3 Q:1 $4/$15
Expanded:   maya:● wabi:▲ flsh:○ | Q:1 decide pending | $4.20/$15.00
```

State persisted in `~/.config/shiki/tmux-state.json`.

### 6.6 What Dies

- Heartbeat pane in orchestrator window (**20% screen reclaimed**)
- Bottom split showing heartbeat output nobody reads
- Replaced by: status bar widget + popup menu + popup commands
- **Net effect**: more screen for actual work, less noise, information at a glance

## 7. Implementation Phases

### Phase A: Command Palette Engine (~200 LOC, ~8 tests)
- `CommandPalette` struct — fuzzy search across multiple sources
- `PaletteSource` protocol — each data source implements
- Built-in sources: commands, sessions, features, branches
- Fuse.js-style scoring (substring match, position weighting)

### Phase B: Command Palette TUI (~150 LOC, ~5 tests)
- `PaletteRenderer` — full-screen overlay
- Input handling: type to filter, prefix modes, arrow navigate, Enter select
- Integrates with KeyMode (emacs/vim/arrows)

### Phase C: Chat / Agent Targeting (~200 LOC, ~6 tests)
- `ChatEngine` — message routing via EventBus
- `@` targeting resolution (agent, persona, alias, broadcast)
- Delivery via EventBus → tmux send-keys bridge
- Message history (in-memory + optional DB persistence)

### Phase D: Editor Mode (~250 LOC, ~5 tests)
- `EditorEngine` — minimal text buffer with cursor management
- Inline `@` autocomplete trigger → command palette results
- Inline `/` search trigger → decision/feature/memory search
- File save/load
- Send-as-prompt action

### Phase E: Command Registration + Aliases (~50 LOC)
- Update ShikiCtl.swift with new commands + aliases
- Hide internal commands (`heartbeat`)
- Add alias resolution in argument parser

**Total**: ~850 LOC, ~24 tests

---

## 6. Flsh Integration (backlog)

The augmented search module is also relevant to Flsh:
- `flsh read --raw` pipes content to `shiki push` (already spec'd)
- Flsh could have its own `@` autocomplete for voice-to-agent targeting
- The fuzzy search engine (Phase A) should be a shared package (`SearchKit`?)

**Backlog item**: Add augmented search to Flsh as `FL-XXX` after Shiki implementation proves the pattern.

---

## 7. Notion-style Node System (inspiration, not implementation)

The user noted Notion's minimal node system as inspiration — "shows almost nothing but can build everything." This philosophy applies to:
- Command palette results as nodes (select → expand → act)
- Editor mode paragraphs as nodes (@ links create edges)
- Decision chain as a node graph (parent → children)

**Action**: `/ingest notion` + add to `/radar` for ongoing monitoring. Not a feature to build now — an interaction pattern to steal from.

---

## 8. Unified Node Model (Notion/AnyType steal)

From `/radar` analysis: Notion and AnyType converge on "everything is one entity type." Apply this to Shiki:

```swift
/// Everything in Shiki is a ShikiNode.
/// Sessions, tasks, features, decisions, agents, files — all queryable the same way.
public protocol ShikiNode: Identifiable, Sendable {
    var id: String { get }
    var nodeType: NodeType { get }
    var title: String { get }
    var parentId: String? { get }
    var relations: [String: String] { get } // key-value relations (like AnyType)
    var createdAt: Date { get }
}

public enum NodeType: String, Codable, Sendable {
    case session, task, feature, decision, agent, file, pr, memory, plan, concern
}
```

**Why this matters for the command palette**: every search result is a `ShikiNode`. The palette doesn't need separate rendering logic per type — it renders nodes. Actions are type-specific but the display is uniform.

**View projections** (Notion pattern):
- Same `[ShikiNode]` dataset displayed as:
  - **List**: timeline view (Observatory)
  - **Board**: grouped by attention zone (Dashboard)
  - **Tree**: dependency hierarchy (Autopilot)
  - **Detail**: single node expanded (right panel)

**Global relations** (AnyType pattern):
- `status`, `priority`, `attentionZone` can be attached to ANY node type
- A feature, a session, and a task can all have `priority: high`
- Enables cross-type queries: "show me everything with priority high"

## 9. Critical References

- Web FZF Panel: `src/frontend/src/components/fzf/FzfPanel.vue`
- Web Chat: `src/frontend/src/pages/ChatPage.vue`
- Web Alias System: `src/frontend/src/composables/useAliasStore.ts`
- Web Keyboard Shortcuts: `src/frontend/src/composables/useKeyboardShortcuts.ts`
- `/decide` TUI pattern: screenshots from 2026-03-15 (tab nav + options + submit)
- SelectionMenu: `ShikiCtlKit/TUI/SelectionMenu.swift`
- KeyMode: `ShikiCtlKit/TUI/KeyMode.swift`
- TerminalInput: `ShikiCtlKit/TUI/TerminalInput.swift`
