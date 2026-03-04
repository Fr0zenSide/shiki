# @Sensei — Swift CTO Review Addon

Additional checks for Swift/iOS projects. Run alongside `checklists/cto-review.md`.
Only active when project adapter specifies `Language: Swift`.

## Swift 6 Concurrency

- [ ] All `@Observable` classes are `@MainActor` isolated
- [ ] All async functions use proper actor isolation
- [ ] `Sendable` conformance on types crossing isolation boundaries
- [ ] No `nonisolated(unsafe)` without a comment explaining why
- [ ] No `Task { @MainActor in }` where `@MainActor` annotation would suffice
- [ ] No data races: mutable shared state is actor-protected or locked

## SwiftUI Specifics

- [ ] No leaked internal dependencies across layers (e.g., Repository importing SwiftUI)
- [ ] Coordinator pattern used for navigation (no direct `NavigationLink` coupling)
- [ ] Large lists use `LazyVStack` / `LazyHGrid`, not `VStack`
- [ ] Images use `.resizable()` + `AsyncImage` with placeholder
- [ ] No unnecessary `@State` redraws (prefer `let` bindings)

## iOS Security

- [ ] Credentials stored in Keychain, never UserDefaults or plain files
- [ ] StoreKit receipt/transaction verification follows Apple guidelines
- [ ] No `allowsArbitraryLoads` in Info.plist ATS config (except for known dev endpoints)
- [ ] Deep link URL parameters are decoded safely (no injection via URL schemes)

## Data Model

- [ ] New models have `Codable` conformance if persisted
- [ ] Backend collection names match schema
- [ ] Migration needed? (check migrations directory)
