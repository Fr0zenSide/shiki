Run an interactive code walkthrough — a file-by-file guided presentation of code with inline annotations, findings, and navigation.

## Arguments

Parse the argument to determine scope:
- `<path>` — Walk through all files in a directory or glob pattern
- `<PR#>` — Walk through changed files in a PR (uses `gh pr diff`)
- `<branch>` — Walk through changes vs base branch (`git diff <base>...<branch>`)
- No argument — Walk through staged + unstaged changes (`git diff`)

## Presentation Format

### File Ordering (architecture-first)

Sort files by architecture layer, not alphabetically:
1. **Protocols/Interfaces** — abstractions and contracts
2. **Errors & Enums** — error types, state enums
3. **Models** — data models, DTOs, entities
4. **Implementations** — concrete classes
5. **DI / Registration** — dependency injection
6. **ViewModels/Presenters** — presentation logic
7. **Views/Components** — UI components
8. **Coordinators/Routers** — navigation
9. **Tests** — shown after their implementation
10. **Config & Scripts** — configuration, docs

Group related files together with a feature label.

### Progress Tracker

```
### Review Progress (3/12 reviewed)
  [1] [✓] ServiceProtocol.swift
  [2] [✓] SubscriptionTier.swift
  [3] [→] StoreKitService.swift          ← current
  [4] [ ] DIAssemblyStoreKit.swift
  [5] [ ] SubscriptionTierTests.swift
```

### Per-File Display

````markdown
### [3/12] `StoreKitService.swift` — Implementation
> Findings on this file: #5 (Important), #8 (Minor)

```swift
// src/services/StoreKitService.swift

class StoreKitService: StoreKitServiceProtocol {  // → StoreKitServiceProtocol [1]

    private var products: [Product] = []

    func loadProducts() async throws {
        do {
            self.products = try await Product.products(for: ProductID.all)  // → ProductID [2]
        } catch {
            // ⚠️ Finding #5: Error silently swallowed — no user surface
            Logger.storekit.error("Failed to load products: \(error)")
        }
    }
}
```

**References**: `[1]` = file 1 (`StoreKitServiceProtocol.swift`), `[2]` = file 2 (`SubscriptionTier.swift`)

> `next` / `read` / `comment L<N>` / `approve` / `changes`
````

### Inline Annotations

- Findings: `// ⚠️ Finding #N: description` at the relevant line
- Cross-references: `→ TypeName [file#]` for types defined in other files in the walkthrough
- Fixed items: `// ✅ Fixed — was <description>` for changes already addressed
- Backlogged: `// ⚠️ Finding #N (backlogged)` for items deferred to backlog

### Navigation Commands

```
Code navigation:
  next / n              Next file (architecture order)
  prev / p              Previous file
  file <name>           Jump to file (partial match)
  jump <TypeName>       Show definition of a type referenced in current file
  full                  Show full file (not just key sections)
  page <N>              Jump to file number N
  progress              Show progress checklist

File review:
  read / r              Mark current file as reviewed
  unread <N>            Unmark file N

Commenting:
  c L<N> <text>         Comment on line N
  c L<N>-L<M> <text>    Comment on line range

Compound shortcuts (parsed left-to-right):
  rn                    Read current + next file
  nr                    Next file + read it
  prc L5 typo here      Prev + read + comment L5

Decisions:
  approve / a           Done — looks good
  changes / ch          Request changes (list what needs fixing)
  summary               Re-show overview
  quit / q              Exit walkthrough
```

## Execution

1. Collect the file list from the argument scope
2. Sort by architecture layer
3. Group related files by feature/module
4. If findings exist (from a review or analysis), map them to files
5. Present the first file and enter interactive mode
6. Track progress state across the session
