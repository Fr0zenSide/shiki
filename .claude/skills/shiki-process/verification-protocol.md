# Verification Before Completion

Hard gate: NO completion claims without fresh verification evidence.

## The Rule

Before claiming any work is complete, fixed, passing, or done:

1. **IDENTIFY** the verification command (what proves the claim?)
2. **RUN** it (actually execute it, don't recall from memory)
3. **READ** the full output (don't summarize, don't truncate, don't paraphrase)
4. **VERIFY** the output matches the claim (specific line, specific count, specific status)
5. **ONLY THEN** state the claim with evidence

## Forbidden Language (without evidence)

These phrases are NEVER allowed without immediately preceding verification output:

| Forbidden | Why | Replace with |
|-----------|-----|-------------|
| "Done!" | Claims completion without proof | "All N tests pass [paste output]" |
| "Fixed!" | Claims fix without verification | "The test now passes: [paste output]" |
| "Should work" | Speculation, not evidence | Run it and show the output |
| "Probably passes" | Uncertainty = not verified | Run it and show the output |
| "Seems fine" | Vague = not verified | Show specific evidence |
| "All tests pass" | Generic claim | "{test_command}: N tests, 0 failures [paste last 5 lines]" |
| "No issues found" | Absence claim without search | Show the search command and empty result |
| "I believe this is correct" | Belief is not evidence | Show the test output |

## Verification Commands by Context

Use the project adapter's `test_command` and `build_command` when available. Common defaults:

| Context | Verification Command | What to check in output |
|---------|---------------------|------------------------|
| Swift tests | `swift test 2>&1` | "Test Suite 'All tests' passed" + exact count |
| Swift build | `swift build 2>&1` | "Build complete!" + zero warnings |
| Node tests | `npm test 2>&1` | Exit code 0 + pass count |
| Deno tests | `deno test 2>&1` | "ok" + pass count |
| Go tests | `go test ./... 2>&1` | "ok" per package |
| Git status | `git status` | Expected files staged, no untracked surprises |
| AI slop scan | `rg -i "<pattern>" ...` | Zero matches |
| PR created | `gh pr view <N>` | URL, title, status |
| File exists | `ls -la <path>` | File with expected size |

## When Verification Applies

- After EVERY implementation step (not just at the end)
- After EVERY fix attempt
- After EVERY test run
- Before marking ANY task complete
- Before reporting to the user
- Before proceeding to the next phase/gate

## The "Fresh" Requirement

Verification must be FRESH -- from THIS session, after the LATEST change. Stale evidence is not evidence:

- "Tests passed 10 minutes ago" -> Run them again after your latest change
- "I saw the output earlier" -> Run it again and show current output
- "The build succeeded before my edit" -> Build again after your edit

## Escalation

If verification fails:
1. Do NOT claim completion
2. Do NOT retry the same approach hoping for a different result
3. Investigate the failure (use systematic-debugging approach)
4. Fix the root cause
5. Re-verify from scratch

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "I just ran this test, no need to run it again" | If you changed code since then, the evidence is stale. Run it again. |
| "The test is slow, I'll skip re-running" | A slow test that fails is better than a fast assumption that's wrong. Run it. |
| "I can see from the code that it works" | Code review is not verification. Run the test. |
| "The change is trivial, it can't break anything" | Trivial changes cause the most embarrassing bugs. Verify. |
| "I'll verify at the end instead of after each step" | Compound failures are harder to debug. Verify after each step. |
| "The user is waiting, I'll skip verification to be faster" | A wrong answer delivered fast wastes more time than a right answer delivered slow. Verify. |
| "Running the full suite is overkill for this change" | You don't know what your change affects. Run the full suite. |
| "I already know this works from similar code I've seen" | Similar is not identical. Your codebase is unique. Verify in YOUR codebase. |
