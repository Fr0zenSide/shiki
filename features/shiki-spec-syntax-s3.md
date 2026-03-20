# Feature: S3 — Shiki Spec Syntax (Natural Language Test Specifications)

> **Type**: /md-feature
> **Priority**: P1 — core innovation, used by TPDD, SpecDocument, and future non-dev users
> **Status**: Spec (validated by @Daimyo + @Sensei 2026-03-18)
> **Depends on**: SpecDocument (DONE), TPDD (spec'd in autopilot-v2)
> **Target users**: developers today, product designers + UX + CEOs tomorrow

---

## 1. Problem

Test specifications today are either:
- **Prose** (human-readable, not machine-parseable) → "the auth should work"
- **Code** (machine-parseable, not human-readable) → `@Test func validJWTRefresh()`
- **Gherkin** (structured but dev-oriented) → `Given/When/Then` feels like programming

None of these work for the future Shiki user: a product designer who thinks in flows, not functions. We need a specification language that:
- Reads like a conversation
- Expresses conditions, loops, and expectations
- Parses into `@Test` function signatures
- Non-devs can write, devs can execute

## 2. Solution — S3 (Shiki Spec Syntax)

A natural-language-first specification format that compiles to test scenarios.

---

## 3. Core Syntax

### 3.1 When/Then — The basic flow

```
When <context description>:
  → <expected outcome>
  → <expected outcome>
```

**Rules:**
- `When` starts a scenario (always at line start, ends with `:`)
- `→` (or `->`) starts an assertion (indented under When)
- Multiple `→` under one `When` = multiple assertions in one test

**Parses to:**
```swift
@Test("Context description")
func contextDescription() {
    // assert expected outcome 1
    // assert expected outcome 2
}
```

**Example:**
```
When user opens the app for the first time:
  → show onboarding screen
  → skip button visible after 3 seconds
```

### 3.2 Conditions — if / otherwise

```
When <context>:
  if <condition A>:
    → <outcome>
  if <condition B>:
    → <outcome>
  otherwise:
    → <fallback outcome>
```

**Rules:**
- `if` is indented under `When` (condition, ends with `:`)
- `otherwise` = the else/default case (no condition)
- Each `if` block generates a separate test
- `otherwise` generates a test named "...otherwise" or "...default case"

**Example:**
```
When user submits the login form:
  if credentials are valid:
    → create session token
    → redirect to dashboard
    → show welcome toast with user name
  if email not found:
    → show "No account with this email"
    → suggest sign-up link
  if password is wrong:
    → show "Incorrect password"
    → offer password reset link
    → increment failed attempts counter
  otherwise:
    → show generic error
    → log the unexpected case
```

**Parses to 4 tests:**
```swift
@Test("Login with valid credentials")
@Test("Login with unknown email")
@Test("Login with wrong password")
@Test("Login with unexpected error")
```

### 3.3 Switch — depending on

```
When <context>:
  depending on <variable>:
    "<value A>" → <outcome>
    "<value B>" → <outcome>
    "<value C>" → <outcome>
```

**Rules:**
- `depending on` introduces a switch (indented, ends with `:`)
- Each case is `"value" → outcome` (inline, one per line)
- Generates one test per case

**Example:**
```
When subscription status changes:
  depending on the new status:
    "active"    → unlock all features, hide upgrade banner
    "trial"     → show 14-day countdown, limited features only
    "expired"   → show paywall, keep read-only access
    "cancelled" → show reactivation offer after 7 days
```

**Parses to 4 tests:**
```swift
@Test("Subscription active unlocks features")
@Test("Subscription trial shows countdown")
@Test("Subscription expired shows paywall")
@Test("Subscription cancelled shows reactivation")
```

### 3.4 Loops — for each

```
For each <item> in [<list>]:
  when <condition with {item}>:
    → <outcome with {item}>
```

**Rules:**
- `For each` starts a parameterized block (line start)
- `[list]` is comma-separated values in brackets
- `{item}` is the loop variable, interpolated in text
- Generates one parameterized test (or N tests if framework doesn't support params)

**Example:**
```
For each field in [name, email, password]:
  when {field} is empty:
    → show "{field} is required" error
    → highlight {field} border in red
  when {field} has invalid format:
    → show "{field} format is invalid"
  when {field} is valid:
    → show green checkmark next to {field}
```

**Parses to:**
```swift
@Test("Empty field shows required error", arguments: ["name", "email", "password"])
@Test("Invalid format shows error", arguments: ["name", "email", "password"])
@Test("Valid field shows checkmark", arguments: ["name", "email", "password"])
```

### 3.5 Expectations — should / within / at most

Natural-language assertions:

| S3 phrase | Meaning | Test equivalent |
|-----------|---------|-----------------|
| `→ X should be Y` | equality | `#expect(x == y)` |
| `→ X should contain Y` | inclusion | `#expect(x.contains(y))` |
| `→ X should not be empty` | non-empty | `#expect(!x.isEmpty)` |
| `→ X should be greater than Y` | comparison | `#expect(x > y)` |
| `→ X within N seconds` | timeout | `try await withTimeout(N) { ... }` |
| `→ at most N retries` | retry limit | `#expect(retries <= n)` |
| `→ X should change from A to B` | state transition | `#expect(before == a); ...; #expect(after == b)` |

**Example:**
```
When session has been idle:
  → idle duration should be greater than 0
  → watchdog should evaluate within 1 second
  → escalation level should change from "none" to "warn"
```

### 3.6 Concerns — things that worry me

```
? <question>
  expect: <expected behavior>
  edge case: <what might break>
  severity: <low | medium | high>
```

**Rules:**
- `?` starts a concern (line start)
- `expect:` = what SHOULD happen (generates a test)
- `edge case:` = what MIGHT break (generates an edge case test)
- `severity:` = priority for test implementation order
- Concerns without `expect:` are review checkpoints (no test generated)

**Example:**
```
? What if the journal file is locked by another process?
  expect: checkpoint write throws, does not corrupt existing data
  edge case: NFS mount with stale lock — should timeout after 5 seconds
  severity: medium

? Can two sessions write to the same journal concurrently?
  expect: actor isolation prevents data race
  edge case: two separate processes (not actors) writing simultaneously
  severity: high

? Is the 5-minute staleness threshold appropriate for CI environments?
  expect: threshold is configurable via WatchdogConfig
  edge case: GitHub Actions runners with slow I/O might appear stale falsely
  severity: low
```

### 3.7 Sequences — then / and then

For multi-step flows:

```
When user goes through onboarding:
  → show welcome screen
  then user taps "Next":
    → show feature highlights
  then user taps "Get Started":
    → show account creation form
  then user fills and submits:
    → create account
    → redirect to dashboard
```

**Rules:**
- `then` continues a sequence (indented, with `:`)
- Each `then` is a step that depends on the previous
- Generates either one long integration test or chained unit tests

### 3.8 Annotations — metadata

```
@slow           — test takes > 5 seconds (exclude from quick suite)
@flaky          — known to be timing-dependent
@manual         — cannot be automated, needs human verification
@skip("reason") — temporarily disabled
@priority(high) — implement this test first
```

**Example:**
```
@slow @priority(high)
When user uploads a 500MB video:
  → progress bar should update every second
  → upload should complete within 60 seconds
  → thumbnail should be generated within 10 seconds after upload
```

---

## 4. Full Example — Session Lifecycle

```markdown
# Session Lifecycle Spec

## State Machine

When a new session is created:
  → state should be "spawning"
  → attention zone should be "pending"
  → transition history should be empty

When session transitions to working:
  → state should change from "spawning" to "working"
  → transition history should record actor and reason
  → attention zone should change to "working"

For each valid transition in [spawning→working, working→prOpen, prOpen→approved, approved→merged]:
  when transition is requested:
    → should succeed without error
    → history should record the transition

When session receives invalid transition (done → working):
  → should throw invalidTransition error
  → state should remain "done"
  → history should NOT record the failed attempt

## Budget

When session spend reaches daily budget:
  → shouldBudgetPause should return true

  if budget is 0 (unlimited):
    → shouldBudgetPause should return false regardless of spend

## ZFC Reconciliation

When tmux pane dies but session state is "working":
  → reconciliation should transition to "done"
  → reason should contain "ZFC reconcile"
  → journal should record the forced transition

  if tmux is alive but state is "done":
    → should NOT change state
    → should trust recorded state over observable state

## Watchdog Integration

For each protected state in [awaitingApproval, budgetPaused]:
  when session has been idle for 15 minutes:
    → watchdog should return "none" (no escalation)
    → session should remain in current state

When working session has high context pressure (>80%):
  → idle thresholds should effectively halve
  → 1 minute of real idle should trigger warn level

## Concerns

? What if two registries observe the same tmux pane?
  expect: both register it, but only one should own lifecycle transitions
  edge case: split-brain during network partition between processes
  severity: medium

? Does the coalesced journal debounce lose data on kill -9?
  expect: only the debounce buffer (last 2 seconds) is lost
  edge case: rapid state changes right before crash — all lost
  severity: high

? Is 11 states too many for the lifecycle?
  expect: each state maps to a distinct attention zone and action
  edge case: some states may never be reached in practice (reviewPending?)
  severity: low — monitor real usage before simplifying
```

---

## 5. Discoverability — Ghost Text + Inline Assist

### The principle: elevator, not climbing tools

Users shouldn't read documentation to learn S3. They should learn by writing.

### 5.1 Contextual Ghost Text

After each S3 construct, show faded hint text of what comes next:

| User just typed | Ghost text shown |
|-----------------|-----------------|
| `When ` | `user does something:` |
| `When user opens app:` + Enter | `  → show what happens` |
| `  → ` line + Enter | `  → next assertion` or blank for new block |
| Blank line | `When / For each / ? / ##` |
| `if ` | `condition is true:` |
| `for each ` | `item in [list]:` |
| `?` | ` What could go wrong?` |
| `depending on ` | `the value:` |

Tab accepts, Esc dismisses. User never sees an empty page — the ghost text guides.

### 5.2 S3 Assist Palette

Triggered when user pauses (500ms no typing) or presses `Ctrl-Space`:

```
┌─ S3 SYNTAX ──────────────────────────┐
│  When ...    scenario context         │
│  → ...       expected outcome         │
│  if ...      condition branch         │
│  otherwise   default case             │
│  for each    loop over items          │
│  depending   switch/case              │
│  then ...    sequence step            │
│  ? ...       concern / question       │
│  should      assertion keyword        │
│  within N    timeout expectation      │
│  @slow       test annotation          │
│  ## Section  new section header       │
└──────────────────────────────────────┘
```

### 5.3 Inline Validation

As user types, highlight issues in real-time:
- `When` without `:` → dim warning "missing colon"
- `→` without parent `When` → red "assertion outside scenario"
- `if` without parent `When` → red "condition outside scenario"
- `for each` without `[list]` → dim "add [items] to loop"

### 5.4 Template Starters

On empty document, offer starter templates:

```
What are you specifying?
  1. User flow (When user... → show...)
  2. State machine (When state changes... depending on...)
  3. API behavior (When request... if valid... otherwise...)
  4. Data validation (For each field... when empty...)
  5. Blank (start from scratch)
```

Each template pre-fills 3-4 lines as a starting point. User edits from there.

## 6. Parser Architecture

### 5.1 S3 → Test Scenario List

```swift
public struct S3Parser {
    /// Parse S3 markdown into structured test scenarios.
    public static func parse(_ markdown: String) -> S3Spec
}

public struct S3Spec: Codable, Sendable {
    public let title: String
    public let sections: [S3Section]
    public let concerns: [S3Concern]
}

public struct S3Section: Codable, Sendable {
    public let title: String
    public let scenarios: [S3Scenario]
}

public struct S3Scenario: Codable, Sendable {
    public let context: String          // "When user submits form"
    public let conditions: [S3Condition] // if/depending on branches
    public let assertions: [String]      // → outcomes
    public let annotations: [String]     // @slow, @priority(high)
    public let loopVariable: String?     // for each {item}
    public let loopValues: [String]?     // [name, email, password]
}

public struct S3Condition: Codable, Sendable {
    public let condition: String        // "credentials are valid"
    public let assertions: [String]     // → outcomes under this condition
    public let isDefault: Bool          // true for "otherwise"
}

public struct S3Concern: Codable, Sendable {
    public let question: String
    public let expectation: String?
    public let edgeCase: String?
    public let severity: String?
}
```

### 5.2 S3 → Swift @Test Generation

```swift
public struct S3TestGenerator {
    /// Generate Swift Testing @Test functions from parsed S3 spec.
    public static func generate(_ spec: S3Spec) -> String
}
```

Output example:
```swift
@Suite("Session Lifecycle Spec")
struct SessionLifecycleSpecTests {
    @Test("New session state is spawning")
    func newSessionStateIsSpawning() { ... }

    @Test("Valid transition spawning to working")
    func validTransitionSpawningToWorking() { ... }

    @Test("Invalid transition done to working throws", arguments: ...)
    func invalidTransitionDoneToWorking() { ... }
}
```

---

## 6. Integration Points

| Consumer | How it uses S3 |
|----------|---------------|
| `/md-feature` Phase 3 | Agent generates S3 test plan, user edits before execution |
| SpecDocument | `testPlan` field stores S3 content |
| TPDD | S3 IS the test plan format |
| Observatory | Concerns show as review checkpoints |
| Agent Report Card | Maps completed tests to S3 scenarios |
| `/pre-pr` Gate 3 | Validates all S3 scenarios have passing tests |

---

## 7. Why This Matters Beyond Devs

A product designer writes:
```
When user sees the habit streak counter:
  if streak is 0 days:
    → show motivational message "Start your journey today"
  if streak is 1-6 days:
    → show flame icon with day count
  if streak is 7+ days:
    → show golden flame icon
    → unlock "Streak Master" achievement
```

This IS the spec. This IS the test plan. The agent reads it, writes the tests, implements the feature, and the designer can verify by reading the test names. **No code literacy required to specify software behavior.**

---

## 8. Deliverables

- `ShikiCtlKit/Services/S3Parser.swift` (~200 LOC)
- `ShikiCtlKit/Services/S3TestGenerator.swift` (~150 LOC)
- `S3Spec`, `S3Scenario`, `S3Condition`, `S3Concern` models (~80 LOC)
- Tests: parser (10), generator (5), round-trip (3) = ~18 tests
- Documentation: `docs/s3-syntax-guide.md`

**Total**: ~430 LOC, ~18 tests
