# Quick Flow — Lightweight Change Pipeline

For small, well-understood changes that don't need the full `/md-feature` ceremony.
Bug fixes, small tweaks, single-file refactors, config changes.

## When to use Quick Flow

- Bug fix with known root cause
- Single-feature tweak (< 3 files changed)
- Config or copy change
- Refactor with no behavior change
- Test addition for existing code

## When NOT to use Quick Flow (escalate to /md-feature)

- New feature with user-facing behavior
- Change spanning > 5 files
- Architecture change (new protocols, DI changes, new coordinators)
- Change affecting state machine or business rules
- Anything requiring Phase 1 brainstorming

## Scope Detection (automatic)

Before starting, evaluate these signals. If 2+ are present, WARN and recommend `/md-feature`:

| Signal | Weight |
|--------|--------|
| Multiple components mentioned | +1 |
| "System", "architecture", "redesign" language | +1 |
| User uncertainty ("maybe", "not sure if") | +1 |
| Cross-feature interaction | +1 |
| New navigation route needed | +1 |
| New DI registration needed | +1 |
| Estimated > 5 files changed | +1 |

Score >= 2 — "This looks bigger than a quick fix. Consider `/md-feature` instead. Proceed anyway? (y/n)"

## Pipeline (4 steps)

### Step 1: Quick Spec (~2 min)

Write a mini-spec covering:
- **Problem**: 1-2 sentences — what's wrong or what's needed
- **Solution**: 1-2 sentences — what to do
- **Files**: List of files to create/modify
- **Test plan**: Which test(s) to write or modify
- **Risk**: Low/Medium — if Medium, add mitigation

Present to user for approval. In `--yolo` mode, skip confirmation.

### Step 2: TDD Implementation (~5-15 min)

Strict TDD cycle:
1. Write failing test(s)
2. Run tests — verify RED
3. Implement the fix/change
4. Run tests — verify GREEN
5. If refactor needed, do it (keep GREEN)

Rules:
- NO production code without a failing test first
- If you write code before the test: DELETE IT (not "keep as reference")
- Run the project's test command (from project adapter, or detect: `swift test`, `npm test`, `deno test`, etc.) after EVERY change
- Capture full test output — do not summarize or truncate

**Escalation**: If 3 fix attempts fail on the same test, STOP. This is not a quick fix — escalate to `/md-feature` or ask @Daimyo for guidance. Quick Flow is for well-understood changes; repeated failures mean the change is not well-understood.

### Step 3: Self-Review (~2 min)

Before declaring done, run a quick self-review:
1. `git diff` — read every changed line
2. Check against quick spec — did you implement what was specified? Nothing more?
3. Verify no unintended changes (stray formatting, debug prints, commented code)
4. Verify all tests pass (run again, capture output)
5. Check for common issues per project adapter (e.g., force unwraps, hardcoded strings, missing accessibility labels)

### Step 4: Ship (~1 min)

Offer the user 3 options:
- **Commit + PR**: `git add <specific files>` then commit then `gh pr create`
- **Commit only**: `git add <specific files>` then commit
- **Keep unstaged**: Leave changes for user to review

In `--yolo` mode, auto-commit with conventional commit message.

## Verification Protocol

Before declaring Step 2 complete:
1. Run the FULL test suite (not just new tests)
2. Parse output for exact pass/fail count
3. Zero failures required
4. If any failure: investigate (do NOT just re-run hoping it passes)

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "This is so small it doesn't need a test" | If it's small, the test is fast. Write it. |
| "I'll write the test after since I know the fix" | You don't know the fix works until the test proves it. TDD is not optional. |
| "The existing tests cover this case" | Then the bug wouldn't exist. Write a test that reproduces the bug. |
| "Quick spec is overkill for a one-liner" | The spec takes 30 seconds. Skipping it means you might fix the wrong thing. |
| "Self-review is unnecessary, the tests pass" | Tests verify behavior. Self-review catches: scope creep, debug artifacts, style violations. |
| "I'll skip scope detection, the user already decided" | Scope detection protects the user from underestimating. Always run it. |

## README Tracking

Quick Flow features are tracked in `README.md` → `## Feature Roadmap` (see `feature-tracking.md`).

After each step completes:
1. Check the completed step in the sub-checklist
2. Update the WIP counter: `(N/4 steps)`

On Step 1 (Quick Spec): create `features/<name>.md` with the mini-spec and add entry to README.
On Step 4 (Ship): if PR merged via `/validate-pr`, check top-level checkbox and remove sub-checklist.

## Output Format

After Quick Flow completes:
```
## Quick Flow Complete
- Spec: <1-line summary>
- Files: <count> changed
- Tests: <count> passing (X new)
- Commit: <hash> (or "unstaged")
- Time: <duration>
```
