# Definition of Done — Phase 6 Completion Checklist

Run this checklist after all SDD tasks are complete, before proceeding to Phase 7 (Quality Gate).
Every item must be PASS or N/A. Any FAIL blocks Phase 7.

Read the project adapter (`project-adapter.md`) for test commands and conventions.

## Implementation Completeness

- [ ] All tasks from Phase 5b execution plan are marked complete
- [ ] All BR-XX business rules have corresponding implementation
- [ ] No TODO or FIXME comments referencing incomplete work
- [ ] No placeholder implementations (empty method bodies, hardcoded returns)
- [ ] All new files are tracked in git (no untracked production files)

## Test Coverage

- [ ] All Phase 4 test signatures have implementations
- [ ] All tests pass (run project test command, paste last 5 lines of output)
- [ ] Coverage on changed files >= 60% (if coverage tooling available)
- [ ] Edge cases from business rules are covered (boundary values, empty states, error paths)
- [ ] No flaky tests (run suite twice if uncertain)

## Architecture Compliance

- [ ] DI registration for all new types (if applicable per adapter)
- [ ] Navigation routes added for new screens (if applicable)
- [ ] Architecture layers respected (no cross-layer imports)
- [ ] Models follow project type conventions

## Concurrency & Safety

- [ ] No data races: mutable shared state is properly protected
- [ ] Async operations use correct isolation patterns
- [ ] Zero compiler warnings (paste build output)

## UX Compliance (if UI changes)

- [ ] Accessibility labels on all interactive elements
- [ ] Text scaling works (no hardcoded font sizes)
- [ ] Theme variants verified (dark mode, etc.)
- [ ] Touch/click targets adequately sized
- [ ] Loading, empty, and error states handled

## Documentation

- [ ] Feature file `features/<name>.md` Implementation Log updated
- [ ] Public types have doc comments
- [ ] Complex algorithms have inline "why" comments

## Clean State

- [ ] No debug prints or log statements left in production code
- [ ] No commented-out code blocks
- [ ] No unused imports
- [ ] No hardcoded strings that should be localized
- [ ] `git diff` shows only expected changes (no stray formatting, no unrelated files)

## Output Format

```markdown
## Definition of Done — <Feature Name>
| Category | Status | Issues |
|----------|--------|--------|
| Implementation | PASS | 8/8 tasks complete |
| Test Coverage | PASS | 24 tests, 0 failures |
| Architecture | PASS | DI registered |
| Concurrency | PASS | Zero warnings |
| UX | N/A | No UI changes |
| Documentation | PASS | Feature file updated |
| Clean State | FAIL | 1 debug print in file:42 |

Verdict: FAIL — remove debug print before Phase 7
```

Verdict: PASS -> proceed to Phase 7 (/pre-pr)
Verdict: FAIL -> fix issues, re-check
