# /pre-pr — Quality Gate Pipeline

No code ships without passing this pipeline.

## Modes

| Flag | Mode | Gates |
|------|------|-------|
| (default) | Standard | All gates (1a, 1b, 2-9) |
| `--web` | Web | Gates 1a-4 + 9 (no visual QC, no @Hanami in 1b) |
| `--skip-qc` | Standard sans QC | Gates 1a-4 + 8-9 (no visual QC) |
| `--adversarial` | + Adversarial | Adds optional Gate 1c after 1b (any mode) |
| `--yolo` | YOLO | Auto-proceed through passing gates (any mode) |

### YOLO Mode (`--yolo`)

Add `--yolo` to `/pre-pr` to auto-proceed through passing gates.

**What YOLO skips**:
- Gate 6 (User Review): Auto-approves if visual QC delta is 0 (no visual changes)
- Inter-gate confirmations: No "Gate N passed, proceed?" prompts

**What YOLO never skips**:
- Gate 1a/1b (reviews always run)
- Gate 3 (tests must pass)
- Gate 8 (AI slop scan -- never skip)
- Gate 9 (PR creation -- always confirm title/body)
- Any FAIL result (failures always stop for fixing)

YOLO saves ~2 minutes of confirmation prompts on a clean run.

## Gate Flow

```
/pre-pr
  │
  ▼
Gate 1a: SPEC REVIEW          ← @Sensei (spec compliance)
│  Load feature file (features/*.md) + git diff
│  Map each BR-XX to implementation evidence
│  Check for scope creep and missing items
│  Output: BR traceability table + verdict
│  Skip if: no feature file found (warn and proceed)
│
Gate 1b: QUALITY REVIEW       ← @Sensei + @Hanami (if UI) + @tech-expert
│  Only runs after Gate 1a passes (or was skipped)
│  Parallel sub-agents review `git diff` against checklists
│  Load addon checklists if project adapter specifies them
│  Output: Review report table (PASS/FAIL per reviewer)
│
Gate 1c: ADVERSARIAL REVIEW   ← @Ronin (optional)
│  Only runs if --adversarial flag is set or explicitly requested
│  Reads full git diff, produces adversarial findings (min 5)
│  Output: Concern table + fragile code list + verdict
│  Skip if: --adversarial not set
│
Gate 2: FIX LOOP              ← auto-fix or manual
│  If Gate 1a failed: fix missing BRs, re-run 1a
│  Once 1a passes: if Gate 1b failed, fix quality issues, re-run 1b
│  Loop until both 1a and 1b pass
│  3 failures on same issue -> STOP + escalate to @Daimyo
│
Gate 3: TEST COVERAGE         ← {test_command} from project adapter
│  Run full test suite
│  Check coverage >= 60% on changed files
│  Critical paths (BR-XX rules) need 100% coverage
│  Output: Test report (count, coverage %, failures)
│
Gate 4: FIX LOOP              ← auto-fix or manual
│  Fix failing tests, add missing coverage
│  Re-run Gate 3 until green
│  3 failures on same issue -> STOP + escalate to @Daimyo
│
Gate 5: VISUAL QC             ← project-specific (Standard mode only)
│  Run visual QC tool if configured in project adapter
│  (e.g., SwiftUI QC for iOS, Storybook snapshots for web)
│  Output: Delta report
│  Skip if: --skip-qc, --web, or QC tool not available
│
Gate 6: USER REVIEW           ← @Daimyo notification
│  Push QC report to review tool
│  User approves/rejects per screen
│  Skip if Gate 5 skipped
│
Gate 7: FIX LOOP              ← if rejected
│  Apply feedback, re-capture, re-notify
│  Loop until approved
│  3 failures on same issue -> STOP + escalate to @Daimyo
│
Gate 8: AI SLOP SCAN          ← release PRs only
│  Scan shipped source for AI markers
│  See ai-slop-scan.md for patterns
│  Must be CLEAN before proceeding
│
Gate 9: PR CREATION           ← gh pr create
│  Create PR with quality gate results in body
│  Include: summary, review table, test report, QC status
│  Return PR URL
```

## Gate 1a: Spec Review Execution

Purpose: Verify the implementation matches the feature spec / business rules.
Catches "clean code that does the wrong thing."

**Agent:** @Sensei (spec compliance mode — NOT the CTO review checklist)

**Process:**

1. **Load feature file** — scan branch name and recent commit messages for references to `features/*.md`. If a feature file path is found, load it. If not, skip Gate 1a with warning.
2. **Load diff** — `git diff` of all changes (staged + unstaged vs. base branch).
3. **BR traceability** — for each `BR-XX` in the feature file, search the diff for corresponding implementation. Record file path and line number as evidence.
4. **Architecture alignment** — for each changed file in the diff, verify it was expected per the architecture plan in the feature file. Flag unexpected files.
5. **Scope creep check** — anything implemented that was not described in the spec.
6. **Missing items check** — anything in the spec that has no implementation in the diff.

**Output format:**

```markdown
## Gate 1a: Spec Review
| BR | Status | Evidence |
|----|--------|----------|
| BR-01 | PASS | Implemented in HabitService.ts:42 |
| BR-02 | FAIL | No implementation found |
| BR-03 | PASS | Implemented in HabitViewModel.ts:15 |

Scope check: PASS (no unexpected files)
Missing: BR-02 not implemented
Verdict: FAIL — 1 BR missing
```

**Pass criteria:** All BRs mapped to implementation, no scope creep.

**Graceful degradation:** If no feature file is found, output:
```
Gate 1a: SKIPPED — No feature file found. Spec compliance not verified.
```
Then proceed directly to Gate 1b.

---

## Gate 1b: Quality Review Execution

Purpose: Verify the code is well-built (architecture, concurrency, UX, quality).
Only runs after Gate 1a passes or was skipped.

Launch 3 parallel sub-agents:

1. **@Sensei** — reads `checklists/cto-review.md` (+ addon if specified in project adapter), reviews diff (architecture, concurrency, error handling, performance, naming, security, data model)
2. **@Hanami** — reads `checklists/ux-review.md`, reviews diff (only if UI files changed)
3. **@tech-expert** — reads `checklists/code-quality.md` (+ addon if specified in project adapter), reviews diff

Each returns a structured report. Merge into summary table.

### UI change detection

Detect UI files based on project adapter configuration. Common patterns:
- Files in `*/Views/*`, `*/Presentation/*`, `*/Components/*`, `*/UI/*`
- Files containing UI framework imports (SwiftUI, React, Vue, etc.)

---

## Gate 1c: Adversarial Review Execution (optional)

Purpose: Find what cooperative reviewers miss. Stress-test assumptions, edge cases, and failure modes.
Only runs when `--adversarial` flag is set or when explicitly requested.

**Agent:** @Ronin

**Process:**

1. **Read full diff** — `git diff` of all changes. No skimming, no shortcuts.
2. **Produce adversarial findings** — minimum 5 concerns. If fewer than 5 found, re-read the diff (fewer than 5 is suspicious).
3. **Classify each concern** — Critical (must fix), Dangerous (should fix), Suspect (worth investigating).
4. **Identify fragile code** — things that are correct now but will break with future changes.
5. **Render verdict** — SURVIVES or VULNERABLE.

**Output format:**

```markdown
## Gate 1c: Adversarial Review (@Ronin)
| # | Severity | File:Line | Concern | What Breaks |
|---|----------|-----------|---------|-------------|
| 1 | Critical | Foo.ts:42 | Unhandled error in async call | Crash on server error |
| 2 | Dangerous | Bar.ts:15 | No cancellation check in async loop | Memory leak on navigation |
| 3 | Suspect | Baz.ts:8 | Shared mutable state without synchronization | Race condition under load |

### Fragile Code
- `Config.ts:20` — hardcoded timeout; will break when backend moves to different region
- `HabitVM.ts:55` — assumes exactly 4 imperfect days; BR may change

Verdict: VULNERABLE — 1 Critical item must be fixed
```

**Pass criteria:** No Critical items. Dangerous items flagged for decision. Suspect items noted.

**Graceful skip:** If `--adversarial` is not set and @Ronin was not explicitly requested, output:
```
Gate 1c: SKIPPED — Adversarial review not requested.
```
Then proceed directly to Gate 2.

---

## Gate 2: Fix Loop Execution

Gate 2 covers failures from both Gate 1a and Gate 1b.

**Sequence:**

1. If Gate 1a failed: fix missing BRs / scope issues first, then re-run Gate 1a.
2. Once Gate 1a passes: if Gate 1b failed, fix quality issues, then re-run Gate 1b.
3. Loop until both gates pass.
4. **Three-Failure Escalation applies** — see below.

## Three-Failure Escalation (All Fix Loops)

Applies to every fix loop in this pipeline: Gate 2, Gate 4, and Gate 7.

Three consecutive failures on the same issue means the **approach** is wrong, not just the implementation. A 4th attempt with the same thinking will produce a 4th failure.

After 3 consecutive failed fix attempts on the same gate issue:

### 1. STOP

Do not attempt a 4th fix.

### 2. Summarize

Document what was tried:

```markdown
### Escalation: Gate {N} — {issue}

**Attempts**:
1. {what was tried} -> {why it failed}
2. {what was tried} -> {why it failed}
3. {what was tried} -> {why it failed}

**Pattern**: {what these failures have in common}
**Hypothesis**: {why the approach may be fundamentally wrong}
```

### 3. Escalate

Present to @Daimyo with options:

> Gate {N} fix loop has failed 3 consecutive attempts. The pattern suggests {hypothesis}.
>
> Options:
> - **(a) Rethink the approach** — the fix targets the wrong root cause or fights the architecture
> - **(b) Invoke @Ronin** — adversarial analysis to challenge assumptions about the problem
> - **(c) Skip and track** — mark as known issue, continue the pipeline, create a follow-up ticket
> - **(d) Revert entirely** — the change that introduced the issue should be undone

### 4. Wait

Do NOT proceed until @Daimyo responds. The pipeline does not have authority to skip a failed gate unilaterally.

This protocol mirrors the SDD protocol's Three-Failure Escalation (see `sdd-protocol.md`). The principle is the same everywhere: 3 failures = stop and think, not try harder.

## Gate 3 Execution

Run the project's test command from the project adapter. Examples:

```bash
# Swift
swift test 2>&1

# Node/npm
npm test 2>&1

# Deno
deno test 2>&1

# Go
go test ./... 2>&1
```

Parse output for: total tests, passed, failed, test names.

### Coverage check
Compare changed files against test files. Flag files with new business logic that have no corresponding test file.

## Gate 9: PR Body Template

```markdown
## Summary
<1-3 bullets describing the change>

## Quality Gate Results
| Gate | Status |
|------|--------|
| Spec review (1a) | PASS (or SKIPPED) |
| @Sensei review (1b) | PASS |
| @Hanami review (1b) | PASS (or N/A) |
| @tech-expert review (1b) | PASS |
| @Ronin review (1c) | SURVIVES (or SKIPPED) |
| Tests | 216/216 passed |
| Visual QC | 6/6 approved (or SKIPPED) |
| AI Slop Scan | CLEAN |

## Test plan
- [ ] Run tests — all green
- [ ] Verify on target environment
- [ ] Check visual appearance
```

## Pipeline Checkpointing

If ShikiMCP tools are available (verify with `shiki_health` MCP tool), checkpoint each gate for resume support. If unavailable, skip checkpointing silently — the pipeline works without it.

**On start**: Create a pipeline run: Use the `shiki_save_event` MCP tool with:
```json
{ "type": "pipeline_started", "scope": "pre-pr", "data": { "pipelineType": "pre-pr", "config": { "mode": "standard" } } }
```
Store the returned ID as RUN_ID.

**After each gate**: Record a checkpoint: Use the `shiki_save_event` MCP tool with:
```json
{ "type": "pipeline_checkpoint", "scope": "pre-pr", "data": { "runId": "<RUN_ID>", "phase": "<gate>", "phaseIndex": "<N>", "status": "completed", "stateAfter": {...} } }
```

**Phase names**: `gate_1a_spec_review` (0), `gate_1b_quality_review` (1), `gate_1c_adversarial` (2), `gate_2_fix_loop` (3), `gate_3_test_coverage` (4), `gate_4_fix_loop` (5), `gate_5_visual_qc` (6), `gate_6_user_review` (7), `gate_7_fix_loop` (8), `gate_8_ai_slop` (9), `gate_9_pr_creation` (10)

**On gate failure**: Record with `"status":"failed"`, then check routing rules: Use the `shiki_save_event` MCP tool with:
```json
{ "type": "pipeline_route", "scope": "pre-pr", "data": { "runId": "<RUN_ID>", "failedPhase": "<gate>" } }
```
Actions: `auto_fix` (attempt fix + retry), `retry_phase` (re-run gate), `escalate` (ask @Daimyo).

**On completion**: Use the `shiki_save_event` MCP tool with: `{ "type": "pipeline_completed", "scope": "pre-pr", "data": { "runId": "<RUN_ID>", "status": "completed" } }`

**On resume** (via `/retry`): Skip gates with index < resumeFromIndex. Use the provided state.

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "The diff is small, Gate 1 is overkill" | Small diffs have caused the worst production bugs. Small review is fast. Run it. |
| "Tests pass, no need for Gate 1 review" | Tests verify behavior. Review verifies architecture, concurrency, security. They're orthogonal. |
| "I'll skip @Hanami, there are no UI changes" | Check the file list. If ANY file contains UI framework code, @Hanami reviews. |
| "The user is in a hurry, I'll skip gates to ship faster" | Gates exist BECAUSE of urgency. Rushed code is where bugs hide. Run every gate. |
| "Gate 5 (Visual QC) isn't available, so skip it" | Use `--skip-qc` flag explicitly. Never silently skip a gate. |
| "All gates passed last time, this small change doesn't need re-running" | Every diff is a new PR. Every PR runs all gates. No exceptions. |
| "I'll create the PR first and run gates later" | Gate 9 (PR creation) is the LAST gate. Creating a PR without passing gates 1-8 is a process violation. |
| "The AI slop scan is only for releases" | Correct — Gate 8 is only for PRs targeting the main/release branch. But when it applies, it's mandatory. |
| "3 failures but I think the 4th attempt will work" | It will not. 3 failures means the approach is wrong, not the execution. Escalate. |
