# @Sensei — CTO Review Checklist

Run this checklist against `git diff` for every PR. Mark each item PASS/FAIL/N/A.
Read the project adapter (`project-adapter.md`) for tech stack context.

## Architecture

- [ ] Architecture layers respected (per project adapter: Clean Arch, MVC, MVVM, etc.)
- [ ] No leaked internal dependencies across layers
- [ ] DI registration for all new types (if DI configured in adapter)
- [ ] Navigation pattern followed (per project conventions)
- [ ] Models are value types unless shared state requires reference types

## Error Handling

- [ ] No force unwraps or unsafe operations in production code
- [ ] No unhandled exceptions in production code
- [ ] Errors are surfaced to the user (toast, alert, or error state) — not silently swallowed
- [ ] Network errors include retry logic or user-actionable message

## Performance

- [ ] No N+1 queries (check loop + async fetch patterns)
- [ ] No synchronous I/O on main/UI thread
- [ ] Large lists use lazy/virtualized rendering
- [ ] Images loaded asynchronously with placeholders
- [ ] No unnecessary state redraws

## Naming & Conventions

- [ ] Types: PascalCase (or per project convention)
- [ ] Files named after primary type they contain
- [ ] Protocol/interface names describe capability
- [ ] Method names are verb phrases
- [ ] Consistent with existing codebase patterns

## Security

- [ ] No secrets, API keys, or tokens in source code
- [ ] Credentials stored securely (Keychain, env vars, vault)
- [ ] No sensitive data logged (PII, tokens, passwords)
- [ ] All network calls use HTTPS
- [ ] User input validated and sanitized before use
- [ ] No injection vulnerabilities (SQL, XSS, command injection)

## Data Model

- [ ] New models have serialization support if persisted
- [ ] Backend schema names match
- [ ] Relationships modeled correctly
- [ ] Migration needed? Check migration directory

## Output Format

```markdown
## @Sensei Review
| Category | Status | Issues |
|----------|--------|--------|
| Architecture | PASS | — |
| Error Handling | PASS | — |
| Performance | N/A | No performance-sensitive changes |
| Naming | PASS | — |
| Security | PASS | — |
| Data Model | PASS | — |
```

**Note**: If the project adapter enables a language-specific addon (e.g., `addons/cto-review-swift.md`), also run those additional checks.
