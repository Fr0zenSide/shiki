# @tech-expert — Swift Code Quality Addon

Additional checks for Swift projects. Run alongside `checklists/code-quality.md`.
Only active when project adapter specifies `Language: Swift`.

## Swift Best Practices

- [ ] Prefer `let` over `var` where possible
- [ ] Use `guard` for early returns, `if let` for conditional binding
- [ ] Prefer value types (struct/enum) over reference types (class)
- [ ] Use `Result` or typed errors, not stringly-typed error handling
- [ ] No force unwraps (`!`) in production code (tests are fine)
- [ ] No `try!` in production code

## Formatting (Swift)

- [ ] 4-space indentation, no tabs
- [ ] MARK comments for section organization in files > 100 lines
- [ ] Imports sorted: Foundation -> SwiftUI -> third-party -> project modules
- [ ] Trailing commas on multi-line arrays/parameters

## API Compatibility (Backport Pattern)

Ref: [Dave DeLong — Simplifying Backwards Compatibility](https://davedelong.com/blog/2021/10/09/simplifying-backwards-compatibility-in-swift/)

- [ ] Deprecated APIs wrapped via `Backport<Content>` pattern
- [ ] NO inline `if #available` scattered across views — centralize in `Backport.swift`
- [ ] No direct use of deprecated APIs when a backport exists
- [ ] **On min iOS version bump**: audit all `Backport` extensions and remove dead branches
- [ ] Colors, spacing, and design tokens use the design system — no inline hex literals
