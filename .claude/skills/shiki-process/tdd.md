---
name: tdd
description: "TDD bug-fix loop: run tests, reproduce failure, plan fix, implement, verify, PR, merge"
user_invocable: true
---

# /tdd — Test-Driven Development Fix Loop

**Trigger**: Run all unit tests in the current project and fix every non-green result.

## Process

### Phase 0: Discovery
1. Detect the project type and test runner:
   - Swift: `swift test` or `xcodebuild test`
   - Deno/TS: `deno test`
   - Go: `go test ./...`
2. Run the FULL test suite. Capture FULL output — no truncation.
3. If ALL GREEN → report success and exit.
4. If ANY RED → continue to Phase 1 for each failing test.

### Phase 1: Reproduce (per failing test)
1. Isolate the failing test(s) — run individually to confirm reproducibility.
2. If the failure is in existing code with NO test coverage:
   - Write a NEW unit test that reproduces the exact failure.
   - Confirm it fails (red).
3. Record the failure: test name, error message, file:line.

### Phase 2: Plan Fix
1. Read the failing code. Understand root cause.
2. Draft a minimal fix — smallest change that makes the test green.
3. **If NOT in --yolo mode**: Present the fix plan to @Daimyo for challenge/approval.
4. **If in --yolo mode**: Skip challenge, proceed directly.

### Phase 3: Implement
1. Apply the fix.
2. Re-run the specific failing test(s).
3. If STILL RED → go back to Phase 2 (re-plan).
4. If GREEN → continue.

### Phase 4: Full Verify
1. Run the FULL test suite again (not just the fixed test).
2. If any NEW failures introduced → go back to Phase 2 for those.
3. If ALL GREEN → continue.

### Phase 5: Ship
1. Create a fix branch: `fix/<short-description>` from current branch.
2. Commit with descriptive message: `fix(<scope>): <what was fixed>`.
3. Push immediately (feedback: push before review).
4. Create a small PR on GitHub targeting `develop`.

### Phase 6: Quality Gate (--yolo mode only)
1. Run `/pre-pr` on the fix branch.
2. Fix ALL issues found (including minor) with additional commits.
3. Add a comment on the GH PR summarizing /pre-pr results and fixes applied.
4. Re-run `/pre-pr` until clean.
5. Re-run FULL test suite one final time.
6. If ALL GREEN → auto-merge to develop.
7. If NOT GREEN → restart from Phase 2.

## Rules

- **TDD is sacred**: NO production code without a failing test first.
- **One fix per cycle**: Don't batch multiple unrelated fixes.
- **Full output always**: Never truncate test output. Read EVERY line.
- **No "should work"**: Every claim must be backed by green test output.
- **Broken = top priority**: When something breaks during usage, this process takes over immediately.

## Entry Points

| Trigger | Behavior |
|---------|----------|
| `/tdd` | Run all tests in current project, fix all failures |
| `/tdd <test-name>` | Run specific test, fix if failing |
| Unexpected breakage during session | Auto-trigger: flag user → create test → fix loop |

## Integration with Other Skills

- Phase 5 uses git flow branching (PRs target `develop`)
- Phase 6 invokes `/pre-pr` pipeline
- Follows "push before review" feedback
- Follows "no silent workarounds" feedback
