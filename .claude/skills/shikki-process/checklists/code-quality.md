# @tech-expert — Code Quality Checklist

Run this checklist against `git diff` for every PR. Mark each item PASS/FAIL/N/A.
Read the project adapter (`project-adapter.md`) for language and convention context.

## Code Hygiene

- [ ] No `TODO` or `FIXME` without a linked issue number or explanation
- [ ] No dead code (unused functions, commented-out blocks, unreachable paths)
- [ ] No unused imports/dependencies
- [ ] No debug/print statements in production code (use proper logging)
- [ ] No hardcoded strings that should be localized (UI-facing text)

## Documentation

- [ ] Public types have doc comments explaining purpose
- [ ] Public methods have doc comments with parameter descriptions
- [ ] Complex algorithms have inline comments explaining "why" not "what"
- [ ] No doc comments on private/internal types (unless complex)

## Testing

- [ ] Test file exists for new business logic
- [ ] Test names follow project naming convention (from project adapter)
- [ ] Tests are independent (no shared mutable state between tests)
- [ ] Edge cases covered (empty input, nil/null, boundary values)
- [ ] No flaky tests (no sleep-based timing, no network dependencies)

## Formatting

- [ ] Consistent indentation (per project convention)
- [ ] Section organization in large files
- [ ] Blank line between functions/properties
- [ ] Imports sorted (per project convention)

## Best Practices

- [ ] Prefer immutable over mutable where possible
- [ ] Use early returns for guard conditions
- [ ] Prefer value types over reference types where appropriate
- [ ] Use typed errors, not stringly-typed error handling
- [ ] Avoid deeply nested closures/callbacks (extract to named functions)

## Output Format

```markdown
## @tech-expert Review
| Category | Status | Issues |
|----------|--------|--------|
| Hygiene | PASS | — |
| Documentation | FAIL | Public methods undocumented |
| Testing | PASS | — |
| Formatting | PASS | — |
| Best Practices | PASS | — |
```

**Note**: If the project adapter enables a language-specific addon (e.g., `addons/code-quality-swift.md`), also run those additional checks.
