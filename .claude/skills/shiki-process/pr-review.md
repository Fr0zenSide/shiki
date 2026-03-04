# Interactive PR Review

Interactive code review protocol that pre-digests PRs so @Daimyo focuses only on what matters. Supports single PR review, queue management, batch processing, and epic splitting.

## Commands

| Command | Action |
|---------|--------|
| `/review <PR#>` | Interactive review of specific PR |
| `/review queue` | Show open PRs ranked by priority |
| `/review batch` | Review all open PRs one by one |
| `/review` | Alias for `queue` |

## Review Queue (`/review queue`)

Fetch all open PRs and rank them:

```bash
gh pr list --json number,title,author,createdAt,additions,deletions,changedFiles,labels,headRefName,baseRefName,isDraft
```

For each PR, calculate priority score:
- Base: age in hours (older = higher priority)
- +10 if targeting `develop` or `main`
- +5 if label contains "urgent" or "hotfix"
- +3 per 100 lines changed (larger = review sooner)
- -5 if draft

Display as table:
```
## Open PRs (N total)
| # | PR | Branch | Size | Age | Priority | Status |
|---|-----|--------|------|-----|----------|--------|
| 1 | #42 | feat/x | +120/-30 (5 files) | 2h | HIGH | Ready |
| 2 | #41 | fix/y  | +15/-3 (2 files)   | 5h | MED  | Draft |
```

Priority thresholds:
- HIGH: score >= 20
- MED: score >= 10
- LOW: score < 10

Ask: "Review which PR? (number, or 'batch' for all)"

### Queue Dashboard

When there are 3+ open PRs, show a dashboard summary above the queue prompt:

```markdown
## PR Dashboard
- Open: 5 | Draft: 1 | Ready: 4
- Oldest: PR #38 (3 days) -- needs attention
- Largest: PR #42 (+450/-120, 12 files)
- Blocking: PR #40 targets main (release PR)
- Total review load: ~25 min estimated

### By author
| Author | PRs | Total lines |
|--------|-----|-------------|
| @claude | 3 | +580/-200 |
| @daimyo | 1 | +45/-10 |

### By risk
| Risk | Count | PRs |
|------|-------|-----|
| High (targets main/develop, >200 lines) | 2 | #40, #42 |
| Medium (>50 lines or >3 files) | 2 | #38, #41 |
| Low (<50 lines, <=3 files) | 1 | #39 |
```

Risk calculation:
- **High**: targets `main` or `develop`, OR >200 lines changed, OR >8 files
- **Medium**: >50 lines changed, OR >3 files, OR has label "needs-review"
- **Low**: everything else

Review load estimate: ~3 min per 100 lines changed + 2 min base per PR.

### Stale PR Detection

Flag PRs that match any of these conditions:

| Condition | Age | Label |
|-----------|-----|-------|
| No review activity | > 3 days | STALE -- needs attention |
| No activity at all | > 7 days | ABANDONED? -- consider closing or rebasing |
| Has merge conflicts | any | CONFLICTS -- needs rebase |

Check merge conflicts via:
```bash
gh pr view <N> --json mergeable --jq .mergeable
```

Stale labels appear in the **Status** column of the queue table. A PR can have multiple labels (e.g., "STALE | CONFLICTS").

---

## Single PR Review (`/review <PR#>`)

### Phase 1: Load Context & Size Check

Run in parallel:
1. `gh pr view <PR#> --json number,title,body,author,headRefName,baseRefName,additions,deletions,changedFiles,files,comments,reviews,reviewRequests,labels,isDraft`
2. `gh pr diff <PR#>`
3. `gh api repos/{owner}/{repo}/pulls/<PR#>/comments` — all inline review comments
4. `gh api repos/{owner}/{repo}/pulls/<PR#>/reviews` — all reviews
5. Check if PR body references a feature file (`features/*.md`) — if so, load it

**Size check** — Before proceeding, evaluate PR scope:
- **>400 lines changed** OR **>10 files** OR **touches >2 distinct feature directories** → trigger Epic Split suggestion (see Epic Split section)
- Otherwise proceed normally

Extract from PR body:
- Quality gate results (if present from `/pre-pr`)
- Test report
- Feature file reference
- Checklist items (`- [ ]` / `- [x]`) — extract as structured list

### Phase 2: PR Overview (presented to @Daimyo)

Present the PR overview in this exact format:

```markdown
## [PR #42: Feature title](https://github.com/{owner}/{repo}/pull/42)

`story/feature-branch` → `develop` | +420/-30 | 12 files
Author: @login | Created: 2 days ago

---

### Checklist
- [x] Unit tests pass
- [ ] Accessibility labels on all interactive elements  ← REVIEW PRIORITY
- [ ] Performance tested on target device
- [ ] Documentation updated

**2/4 complete** — Incomplete items drive the review order.

---

### Previous Discussions (2 open / 5 total)

**OPEN**
| # | File | Topic | Last activity |
|---|------|-------|---------------|
| ▸ 1 | `StoreKitService.ts:53` | Silent error swallowing in loadProducts() | 2h ago |
| ▸ 2 | `MockStoreKitService.ts:15` | Concurrency approach | 1d ago |

**RESOLVED**
| # | File | Topic | Resolution |
|---|------|-------|------------|
| ~~3~~ | `SubscriptionTier.ts:78` | ~~isPremium naming~~ | Kept as-is — semantic tier |
| ~~4~~ | `DI.ts:107` | ~~Missing registration~~ | Fixed in commit 82889da |
| ~~5~~ | `TouchOverlay.ts:39` | ~~Debug log in production~~ | Replaced with Logger.debug |

> Type `expand 1` to see full discussion thread, `expand all` to see all.
```

**Discussion formatting rules**:
- Open threads: **bold** number, `▸` expand marker, normal text
- Resolved threads: ~~strikethrough~~ number and topic, resolution summary
- `expand <N>` shows full conversation for thread N with syntax-highlighted code snippets
- `collapse <N>` hides it back
- `expand all` / `collapse all` for bulk toggle

### Phase 3: Pre-Analysis

Dispatch 3 parallel sub-agents (Task tool), each analyzing the diff:

**@Sensei (CTO Review)**:
- Architecture compliance, concurrency, error handling, performance, naming, security, data model
- Uses `checklists/cto-review.md` (+ addon if configured in project adapter)
- Output: list of findings with severity (Critical/Important/Minor) and file:line references

**@Hanami (UX Review)** — only if diff contains UI files:
- UI file detection: based on project adapter config or common patterns (Views/, Components/, UI/)
- Accessibility, Dynamic Type, color, touch targets, states, motion, navigation
- Uses `checklists/ux-review.md`
- Output: list of findings with severity and file:line references
- If no UI files in diff: skip entirely, report N/A

**@tech-expert (Code Quality)**:
- Code hygiene, documentation, testing, formatting, best practices
- Uses `checklists/code-quality.md` (+ addon if configured in project adapter)
- Output: list of findings with severity and file:line references

Each sub-agent reads the full diff and their assigned checklist, then returns structured findings.

### Phase 4: Findings Summary

Present consolidated findings AFTER the PR overview:

```markdown
### Pre-Analysis Findings
| # | Severity | Reviewer | File:Line | Finding |
|---|----------|----------|-----------|---------|
| 1 | Critical | @Sensei  | `Foo.ts:42` | Unhandled error in async call |
| 2 | Important | @Hanami | `Bar.ts:15` | Missing accessibility label on button |
| 3 | Minor | @tech-expert | `Baz.ts:8` | Unused import |

### Verdict
- Critical: N | Important: N | Minor: N
- Recommendation: **APPROVE** / **CHANGES REQUESTED** / **NEEDS DISCUSSION**
```

Recommendation logic:
- Any Critical findings → CHANGES REQUESTED
- 3+ Important findings → CHANGES REQUESTED
- 1-2 Important findings → NEEDS DISCUSSION
- Only Minor findings → APPROVE
- No findings → APPROVE

The recommendation is a suggestion. Only @Daimyo decides.

If the PR has **incomplete checklist items**, present them as the first review priority:
```
### Review Priority
The PR checklist has 2 incomplete items. Starting review through those angles first.
```

### Phase 5: Interactive Code Review

This is the main review phase. Present code organized by **architecture layer**, not alphabetically.

#### File Ordering (architecture-first)

Sort files in this order (adapt to project's architecture from project adapter):
1. **Protocols/Interfaces** — abstractions and contracts
2. **Errors & Enums** — error types, state enums, type definitions
3. **Models** — data models, DTOs, entities
4. **Implementations** — concrete classes implementing the protocols
5. **DI / Registration** — dependency injection, service registration
6. **ViewModels/Presenters** — presentation logic
7. **Views/Components** — UI components
8. **Coordinators/Routers** — navigation
9. **Tests** — corresponding test files shown after their implementation
10. **Config & Scripts** — configuration, shell scripts, documentation

Group related files together. Example:
```
Feature (4 files + 1 test):
  [1] [ ] ServiceProtocol.ts        — Protocol + errors
  [2] [ ] SubscriptionTier.ts       — Models & enums
  [3] [ ] StoreKitService.ts        — Implementation
  [4] [ ] DIAssemblyStoreKit.ts     — DI registration
  [5] [ ] SubscriptionTierTests.ts  — Tests
```

#### Code Presentation

When showing a file, use this format:

````markdown
### [3/12] `StoreKitService.ts` — Implementation
> Findings on this file: #5 (Important), #8 (Minor)

```typescript
// src/services/StoreKitService.ts

class StoreKitService implements StoreKitServiceProtocol {  // → StoreKitServiceProtocol [1]

    private products: Product[] = [];
    private purchasedTiers: Set<SubscriptionTier> = new Set();  // → SubscriptionTier [2]

    async loadProducts() {
        try {
            this.products = await Product.products(ProductID.all);  // → ProductID [2]
        } catch (error) {
            // ⚠️ Finding #5: Error silently swallowed — no user surface
            Logger.storekit.error(`Failed to load products: ${error}`);
        }
    }
}
```

**References**: `[1]` = file 1 (`StoreKitServiceProtocol.ts`), `[2]` = file 2 (`SubscriptionTier.ts`)

> `comment L8-L12` to discuss lines | `read` to mark as reviewed | `next` for next file
````

**Formatting rules**:
- Always use appropriate language fenced blocks for syntax highlighting
- Inline findings as `// ⚠️ Finding #N:` comments at the relevant line
- Cross-references to other PR files as `→ TypeName [file#]`
- Show only the changed hunks by default, `full` to show entire file

#### Review State Tracking

Track which files have been reviewed:

```
### Review Progress (3/12 reviewed)
  [1] [✓] StoreKitServiceProtocol.ts
  [2] [✓] SubscriptionTier.ts
  [3] [→] StoreKitService.ts          ← current
  [4] [ ] DIAssemblyStoreKit.ts
  [5] [ ] MockStoreKitService.ts
  ...
```

- `[✓]` — reviewed (user marked with `read` command)
- `[→]` — currently viewing
- `[ ]` — not yet reviewed
- `read` / `r` — mark current file as reviewed
- `unread <N>` — unmark a file

#### Inline Commenting

When the user wants to comment on specific lines:

```
User: comment L42-L50
```

Response:
```
Commenting on StoreKitService.ts:42-50:

```typescript
42 │    async loadProducts() {
43 │        try {
44 │            this.products = await Product.products(ProductID.all);
45 │        } catch (error) {
46 │            Logger.storekit.error(`Failed: ${error}`);
47 │        }
48 │    }
```

What's your comment? (I'll post it as a GitHub review comment)
```

After user types their comment:
1. Post to GitHub via `gh api repos/{owner}/{repo}/pulls/<PR#>/comments`
2. Add to findings table with severity chosen by user (or auto-detect)
3. Ask: "Discussion opened on GitHub. Continue reviewing? (next/stay)"

#### Navigation Commands

```
Code navigation:
  next / n              Next file (architecture order)
  prev / p              Previous file
  file <name>           Jump to file (partial match)
  jump <TypeName>       Show definition of a type referenced in current file
  full                  Show full file (not just diff hunks)
  page <N>              Jump to file number N in the review list
  progress              Show review progress checklist

File review:
  read / r              Mark current file as reviewed
  unread <N>            Unmark file N

Commenting:
  comment L<N>          Comment on line N
  comment L<N>-L<M>     Comment on line range N-M
  discuss <finding#>    Open discussion about a specific finding

Discussions:
  expand <N>            Show full discussion thread N
  collapse <N>          Collapse discussion thread N
  expand all            Show all discussions
  threads               List all open discussion threads

Findings:
  findings              Re-show findings table
  summary               Re-show PR overview + summary

Decisions:
  approve / a           Approve the PR
  changes / c           Request changes
  comment / m           Leave a comment (no approval/rejection)
  skip                  Move to next PR (batch mode)
  quit / q              Exit review

Free-text:
  Any question about the code → answered from feature context + codebase analysis
```

### Phase 6: Post to GitHub

Based on the user's decision, construct and post the review.

**Review body format**:
```markdown
## Review Summary

<user's summary comment if provided, otherwise auto-generated from findings>

### Findings
| # | Severity | Category | Finding |
|---|----------|----------|---------|
<all findings from pre-analysis + interactive session>

### Review Progress
- Files reviewed: N/M
- Discussions opened: N (N resolved)

### Verdict
<APPROVED / CHANGES REQUESTED / COMMENTED>

---
Reviewed via Shiki /review
```

**Approve**:
```bash
gh pr review <PR#> --approve --body "<review body>"
```

**Request Changes**:
```bash
gh pr review <PR#> --request-changes --body "<review body>"
```

**Comment only**:
```bash
gh pr review <PR#> --comment --body "<review body>"
```

**Post inline comments** for all findings that have file:line references:
```bash
gh api repos/{owner}/{repo}/pulls/<PR#>/comments \
  -f body="**<severity>** (<reviewer>): <finding>" \
  -f path="<file>" \
  -F line=<line> \
  -f side="RIGHT" \
  -f commit_id="$(gh pr view <PR#> --json headRefOid -q .headRefOid)"
```

Get owner/repo from:
```bash
gh repo view --json owner,name -q '.owner.login + "/" + .name'
```

**After posting "Request Changes"**: Offer auto-fix dispatch:
```
Changes posted to PR #<N>.
Want me to dispatch a fix agent for the critical/important items? (y/n)
```

If the user says yes, execute the fix workflow (see Integration with Fix Workflow below).

---

## Epic Split (Large PR Detection)

### When to trigger

A PR is "too big" when ANY of these conditions match:
- **>400 lines changed** (excluding auto-generated files)
- **>10 files changed** (excluding auto-generated)
- **Touches >2 distinct feature directories**
- **PR description mentions multiple unrelated features**

### Epic Split Flow

When a large PR is detected, present this to @Daimyo before starting code review:

```markdown
### Large PR Detected

This PR changes +7,051/-156 across 86 files touching 3 features.
A big PR is not a good PR — it's harder to review, riskier to merge, and slower to iterate on.

**Suggested split:**

| # | Feature PR | Scope | Est. lines |
|---|------------|-------|------------|
| 1 | `feat/storekit-pricing` | StoreKit2 models, service, DI, tests | ~500 |
| 2 | `feat/onboarding-ui` | 4 pages, atmosphere, coordinator, tests | ~2,000 |
| 3 | `feat/process-skills` | Skill files, commands, settings, scripts | ~3,500 (docs) |

**Epic branch**: `epic/<name>` (targets `develop`)
**Epic PR body**: Checklist linking each feature PR

Split now? (y/n) Or review as-is?
```

If user agrees to split:

1. **Create epic branch** from current PR branch
2. **Create feature branches** from epic
3. **Create feature PRs** targeting the epic branch
4. **Create epic PR** targeting `develop` with checklist body
5. **Review each feature PR** individually via `/review <N>`
6. **Update epic checklist** as each feature PR merges

### Auto-generated file exclusion

These files are excluded from line count for size detection:
- `*.pbxproj` (Xcode project)
- `snapshots/**/*.png` (snapshot tests)
- `*.storekit` (StoreKit config)
- `*.xcscheme` (Xcode schemes)
- `package-lock.json`, `yarn.lock`, `*.lock`
- `*.generated.*` (code generation)

---

## Batch Review (`/review batch`)

1. Load queue (same as `/review queue`)
2. For each PR in priority order:
   - Run Phase 1-4 (context + analysis + findings)
   - Present PR overview to user
   - Enter abbreviated interactive mode: user can ask questions, then must decide
   - Accept: `approve` / `changes` / `skip` / `quit`
   - Post to GitHub (except skip)
   - If quit: stop batch, show partial summary
   - Move to next PR
3. After all PRs processed, show batch summary:

```
## Batch Review Complete
- Reviewed: N PRs
- Approved: N
- Changes Requested: N
- Commented: N
- Skipped: N
- Fix agents dispatched: N
```

---

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "The /pre-pr gates passed, no need for deep review" | Gates check rules. Review checks intent. They are complementary. |
| "This is a small PR, I'll skip pre-analysis" | Small PRs have small analysis. The overhead is seconds, the safety is real. |
| "I'll post the review without asking the user" | Review decisions ALWAYS require @Daimyo. You analyze, they decide. |
| "The user said approve, I'll skip posting inline comments" | Inline comments help future reviewers and the PR author. Always post findings. |
| "No Critical findings, so auto-approve" | Only @Daimyo approves. Important findings may be blockers in their judgment. |
| "I'll skip @Hanami, it's mostly backend" | Let the UI detection logic decide. If it says N/A, that's fine. Don't pre-judge. |
| "The PR is big but I'll review it all at once" | Big PRs hide bugs. Suggest epic split. Small PRs get better reviews. |
| "I'll show files alphabetically, it's simpler" | Architecture order helps @Daimyo understand the feature flow. Always use layer ordering. |
| "I'll skip the discussion summary, there are no comments" | Always show the section. Zero discussions is status information the reviewer needs. |

---

## Integration with Fix Workflow

When the user requests changes and wants auto-fix:

1. Determine the PR's head branch:
   ```bash
   gh pr view <PR#> --json headRefName -q .headRefName
   ```

2. Create a fix branch from the PR branch:
   ```bash
   git fetch origin <head-branch>
   git worktree add -b fix/<PR#>-review-feedback .claude/worktrees/fix-<PR#> origin/<head-branch>
   ```

3. Dispatch a sub-agent in the worktree with:
   - The full findings list (Critical + Important only)
   - Exact file:line references
   - Expected fix for each finding
   - Instruction: fix -> run tests -> commit -> push

4. Sub-agent workflow:
   ```
   cd .claude/worktrees/fix-<PR#>
   # Apply fixes per finding
   # Run: {test_command}
   # Commit: git commit -m "fix(review): address PR #<N> review feedback"
   # Push: git push origin fix/<PR#>-review-feedback
   ```

5. Create a follow-up PR or push to the existing PR branch:
   - If the fix branch can push directly to the head branch (same repo): push to head branch
   - Otherwise: create a new PR targeting the head branch

6. Notify user:
   ```
   Fixes pushed to <branch>. PR #<N> updated with new commits.
   Re-review? (/review <PR#>)
   ```

7. Clean up worktree after push:
   ```bash
   git worktree remove .claude/worktrees/fix-<PR#>
   ```
