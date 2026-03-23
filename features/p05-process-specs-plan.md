# P0.5 Process Specs — Implementation Plan

> Author: @Sensei (CTO) | Date: 2026-03-23 | Status: Ready for @Daimyo review
> Scope: Two process specs that gate every future release. Not features — infrastructure.

---

## Task 1: Epic Branching — Release Prep Process

### Current State (what exists)

**Git flow defined but not enforced.** The branching convention (`main <- release/* <- develop <- feature/*`) is documented in MEMORY.md but has no automated enforcement. The existing spec (`features/shiki-epic-branching.md`) focuses on ShikiCore code changes (DependencyTree, ShipService) — it treats this as a ship feature when it is actually a release process that must work TODAY, before ShikiCore exists in production.

**CI/CD exists per-project, not per-flow.**
- Maya: `ci.yml` triggers on PR/push to `develop` only. Two jobs: SPM tests + iOS build/test. Uses sparse checkout of `Fr0zenSide/shiki` for packages.
- WabiSabi: `ci.yml` triggers on PR/push to `develop` only. Single job: xcodebuild + test.
- Both CD pipelines (`cd-testflight.yml`) are `workflow_dispatch` only — TestFlight deploy is blocked until Apple Developer secrets are configured.
- obyw-one: deploy via GitHub Actions (rsync to VPS `92.134.242.73`), Caddy serves.
- Shiki monorepo: **zero CI**. No GitHub Actions workflow. Tests run locally only.

**Branch protection: none.** No GitHub branch protection rules on any repository.

### Gap Analysis

1. **CI does not know about epic branches.** Both Maya and WabiSabi CI triggers are `branches: [develop]`. A PR from `feat/wave1 -> epic/shiki-v1` will NOT trigger CI. This is the #1 blocker.

2. **No CI for the shiki monorepo itself.** The 441+ shiki-ctl tests and 45+ package tests have never run in CI. There is no `.github/workflows/ci.yml` at the repo root.

3. **Release branch missing from the flow.** The spec jumps from `epic -> develop` but never addresses `develop -> release/* -> main`. No release naming convention. No tag strategy.

4. **Multi-project release cadence not addressed.** Maya (Faustin's team, `UVC4JM6XD4`) and WabiSabi (OBYW.one, `L8NRHDDSWG`) ship independently. Shiki packages are shared — a CoreKit change can break both. No cross-project CI validation.

5. **Rollback strategy absent.** The existing spec has zero mention of what happens when a release goes bad — no revert plan, no hotfix branch convention, no App Store binary rollback process.

6. **The ShikiCore code changes (DependencyTree.epicBranch, ShipCommand --epic) are premature.** ShikiCore is not in production. The process must work with plain git + GitHub Actions today.

### Proposed Design

#### 1. Branch Convention (formalized)

```
main                          # production-tagged releases only
  <- release/X.Y.Z            # cut from develop, version bump, final QA
    <- develop                 # integration branch, always green
      <- epic/<name>           # scope container for 3+ branch / 2+ week work
        <- feat|fix|refactor/* # wave branches target epic (or develop if no epic)
      <- feat|fix/*            # small changes target develop directly
  <- hotfix/X.Y.Z+1           # emergency fix from main, merges back to main AND develop
```

**Threshold rule (from post-review):** Epic branch required when 3+ feature branches OR 2+ weeks of estimated work. Otherwise branch from develop directly.

**Naming convention:**
- Releases: `release/3.2.0` (semver, no `v` prefix in branch name)
- Tags: `v3.2.0` (semver with `v` prefix)
- Hotfixes: `hotfix/3.2.1` (patch bump from last release tag)

#### 2. CI Triggers — Epic-Aware

**Shiki monorepo** (new `/.github/workflows/ci.yml`):
```yaml
on:
  pull_request:
    branches: [develop, 'epic/**', 'story/**', 'release/**']
  push:
    branches: [develop]
```

This ensures:
- `feat/* -> epic/*` PRs run CI (wave validation)
- `epic/* -> develop` PRs run CI (full suite)
- `develop -> release/*` PRs run CI (release QA)

**Maya and WabiSabi CI** — update triggers identically:
```yaml
on:
  pull_request:
    branches: [develop, 'epic/**', 'story/**', 'release/**']
  push:
    branches: [develop]
```

**Shiki monorepo CI jobs** (three tiers):

| Job | Trigger | What runs | Timeout |
|-----|---------|-----------|---------|
| `spm-packages` | All PRs | `swift test --package-path packages/CoreKit`, NetKit, SecurityKit, ShikiKit, ShikiCore, ShikiMCP | 10min |
| `shiki-ctl` | All PRs | `swift test --package-path tools/shiki-ctl --skip-build` (after spm-packages) | 15min |
| `integration` | PRs to develop, release/* | Full suite + cross-package contract tests | 20min |

#### 3. CD Pipeline — Release Flow

**iOS (Maya/WabiSabi):**
```
develop (CI green)
  -> release/X.Y.Z branch cut
  -> version bump commit (Info.plist / project.yml)
  -> PR: release/X.Y.Z -> main
  -> CI runs on PR
  -> merge to main triggers cd-testflight.yml
  -> tag vX.Y.Z on main after TestFlight upload
  -> merge main back to develop (catch version bump)
```

**Web (obyw-one):**
```
develop (CI green)
  -> push to main triggers deploy job
  -> rsync to VPS 92.134.242.73
  -> Caddy serves immediately
  -> rollback: git revert on main, push triggers redeploy
```

**Shiki CLI (native binary):**
```
develop (CI green)
  -> release/X.Y.Z branch
  -> swift build -c release
  -> tag vX.Y.Z
  -> GitHub Release with binary artifact
  -> systemd service restart on VPS (manual for now, Ansible later)
```

#### 4. Branch Protection Rules

| Repository | Branch | Rules |
|------------|--------|-------|
| Fr0zenSide/shiki | `main` | Require PR, 1 approval, CI pass, no force push |
| Fr0zenSide/shiki | `develop` | Require PR, CI pass, no force push |
| Fr0zenSide/Maya | `main` | Require PR, 1 approval, CI pass |
| Fr0zenSide/Maya | `develop` | Require PR, CI pass |
| Fr0zenSide/wabisabi | `main` | Require PR, 1 approval, CI pass |
| Fr0zenSide/wabisabi | `develop` | Require PR, CI pass |

Epic/story branches: no protection (agent autonomy during waves).

#### 5. Multi-Provider Future

When Maya and WabiSabi diverge in release cadence:
- Shared packages (CoreKit, NetKit, SecurityKit, DSKintsugi) get their own semver tags
- iOS projects pin to specific package versions in `Package.swift` (not branch references)
- A CoreKit release triggers downstream CI in Maya + WabiSabi via `repository_dispatch`
- For now: all share `develop` branch of shiki monorepo. Cross-project breakage caught at PR time via sparse checkout CI.

#### 6. Rollback Strategy

| Scenario | Action |
|----------|--------|
| Bad release on App Store | Increment patch version, submit fix. Apple takes 24-48h review. No binary rollback available — only forward-fix. |
| Bad TestFlight build | Delete build in App Store Connect. Cut `hotfix/X.Y.Z+1` from `main`, fix, re-release. |
| Bad web deploy | `git revert <commit>` on `main`, push. Caddy serves new files in <1min. |
| Bad shiki CLI release | `systemctl stop shikki`, install previous binary from GitHub Release, restart. |
| Broken develop | `git revert` the merge commit. Never force-push develop. |

### Files to create/modify

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/ci.yml` (shiki root) | **CREATE** | Monorepo CI — SPM packages + shiki-ctl tests |
| `projects/Maya/.github/workflows/ci.yml` | MODIFY | Add epic/story/release branch triggers |
| `projects/wabisabi/.github/workflows/ci.yml` | MODIFY | Add epic/story/release branch triggers |
| `projects/Maya/.github/workflows/cd-testflight.yml` | MODIFY | Trigger on push to main (when secrets ready) |
| `projects/wabisabi/.github/workflows/cd-testflight.yml` | MODIFY | Trigger on push to main (when secrets ready) |
| `scripts/release.sh` | **CREATE** | Release cut script: branch, version bump, PR creation |
| `scripts/hotfix.sh` | **CREATE** | Hotfix script: branch from main, PR to main + develop |

### Dependency on other P-items

- **Blocks P1 (shiki ship --dry-run)** — ship needs to know which branch flow it operates in
- **Blocks P2 (Shiki public launch)** — can't launch without CI/CD
- **Depends on nothing** — pure process, no code dependencies
- **Soft dependency on Apple Developer enrollment** — CD to TestFlight blocked until secrets exist

### Sub-agent tasks (3 parallel groups)

**Group A — CI Workflows (infra)**
1. Create `.github/workflows/ci.yml` for shiki monorepo (3 jobs: spm-packages, shiki-ctl, integration)
2. Update Maya `ci.yml` triggers to include epic/story/release branches
3. Update WabiSabi `ci.yml` triggers to include epic/story/release branches

**Group B — Release Automation (scripts)**
1. Create `scripts/release.sh` — interactive release branch cutter (reads current version, bumps, creates branch, opens PR via `gh`)
2. Create `scripts/hotfix.sh` — hotfix branch from latest tag on main, opens PRs to both main and develop
3. Document release runbook in `features/shiki-epic-branching.md` (update existing spec — not a new doc)

**Group C — Branch Protection (GitHub config)**
1. Apply branch protection rules via `gh api` for shiki, Maya, WabiSabi repos (main + develop)
2. Validate CI triggers work by creating a test epic branch and opening a dry-run PR
3. Update `features/shiki-epic-branching.md` post-review section with the reframed design (process, not feature)

---

## Task 2: Scoped Testing — Challenged and Updated

### Current State (what exists)

**The spec is sound in principle but over-engineered for today's reality.** It defines TestScope as a struct on WaveNode in ShikiCore, QualityGate integration, PipelineRunner changes — all targeting code that is not yet running in production. Meanwhile, the actual problem (30-60s full test runs during TDD) is solvable with shell discipline and CI configuration.

**Current test inventory (verified):**

| Package | Test Files | Estimated Tests | Run Time (local) |
|---------|-----------|----------------|-------------------|
| CoreKit | 3 | ~37 | ~2s |
| NetKit | 3 | ~18 | ~3s |
| SecurityKit | 2 | ~14 | ~2s |
| ShikiCore | 22 | ~68 | ~5s |
| ShikiKit | 8 | ~30 | ~3s |
| ShikiMCP | 7 | ~37 (6 integration) | ~4s |
| shiki-ctl (Kit) | 57 | ~441 | ~30-60s |
| shiki-ctl (E2E) | 2 | ~10 | hangs (stdin) |
| **Total** | **104** | **~655** | **~50-80s** |

**What works and should stay:**
- BR-01 (scope declaration before coding) — good discipline
- BR-03 (scoped run <10s) — correct target
- BR-06 (full suite once at /pre-pr) — correct cadence
- BR-09 (scope format with package path + filter) — practical
- BR-11 (coverage check: changed files need test files) — catches gaps
- Post-review correction #1 (TestScope on WaveNode only, not TestPlan) — correct
- Post-review correction #5 (expected vs actual test count report) — catches silent filter typos

**What's missing or wrong:**

1. **No cross-package dependency testing.** If a CoreKit change breaks NetKit (which depends on it), the scoped test for CoreKit won't catch it. The spec only scopes to one package per wave — but dependency chains exist:
   ```
   CoreKit <- NetKit <- ShikiKit
   CoreKit <- SecurityKit
   CoreKit <- ShikiCore
   ShikiKit <- ShikiMCP
   ```

2. **Integration test isolation is undefined.** ShikiMCP has 6 integration tests that hit a real ShikiDB backend. shiki-ctl E2E tests hang on stdin. The spec lumps all tests into "scoped" vs "full" but never addresses: what requires Docker? What requires a running backend? What can run in pure-unit mode?

3. **CI integration completely absent.** The spec talks about agent discipline during development but never addresses: which test scopes run in which CI job? How does the CI matrix map to the scoped testing tiers?

4. **The ShikiCore code changes are premature** (same issue as Task 1). TestScope struct, QualityGate changes, PipelineRunner changes — all for code not yet in CI. The process must work with `swift test --filter` today.

5. **No test tagging strategy.** Swift Testing supports traits (`@Test(.tags(.integration))`). The spec uses filename-based filter patterns but never addresses semantic tagging for: unit vs integration vs E2E vs snapshot.

6. **BR-02 as written ("full suite explicitly forbidden") was already flagged.** Post-review softened it to "not required." But the spec body still says "forbidden." Inconsistent.

7. **Simulator requirements undefined.** The testing-strategy feedback says "ONE sim, latest iOS, boot once." But CI needs a sim too. What sim configuration? Who boots it? Is it cached?

### Gap Analysis

| Gap | Severity | Why it matters |
|-----|----------|---------------|
| No cross-package dependency tests in CI | HIGH | CoreKit change can silently break 4 downstream packages |
| Integration tests not isolated from unit tests | HIGH | CI can't run unit-only fast path if integration tests are mixed in |
| No CI job mapping to test tiers | HIGH | Task 1 (epic branching) CI design depends on this |
| Test tagging absent | MEDIUM | Can't filter integration vs unit without filename conventions |
| E2E stdin hang unresolved | MEDIUM | 10+ tests permanently skipped |
| ShikiCore code changes premature | LOW | Defer to when ShikiCore ships — process works without code |

### Proposed Design

#### 1. Three-Tier Test Architecture

```
Tier 1: UNIT (pure logic, no I/O, no network, no filesystem)
  - All packages except integration test files
  - Target: <2s per package, <10s total
  - CI: every PR, every push
  - Filter: swift test --package-path <pkg> --filter "^(?!.*Integration).*Tests"

Tier 2: INTEGRATION (requires backend, Docker, or filesystem)
  - ShikiMCP integration tests (need ShikiDB running)
  - shiki-ctl backend tests (need Deno backend)
  - Cross-package contract tests (ShikiCore/CrossPackageContractTests)
  - Target: <30s total
  - CI: PRs to develop and release/* only (not wave->epic PRs)
  - Requires: Docker Compose up (ShikiDB, backend)

Tier 3: E2E (full binary, real I/O, stdin/stdout)
  - shiki-ctl E2E scenario tests
  - Binary invocation tests
  - Target: <60s total
  - CI: PRs to develop and release/* only
  - BLOCKED: stdin hang must be resolved first (P0 backlog item)
```

#### 2. Test Tagging Convention

Adopt Swift Testing traits for new tests. Retrofit existing tests gradually:

```swift
extension Tag {
    @Tag static var unit: Self        // default — no tag needed
    @Tag static var integration: Self // requires external service
    @Tag static var e2e: Self         // requires compiled binary
    @Tag static var snapshot: Self    // visual regression
    @Tag static var slow: Self        // >5s individual test
}

// Usage:
@Test(.tags(.integration))
func shikiDBClientSavesMemory() async throws { ... }
```

For XCTest suites (not yet migrated): use filename convention:
- `*Tests.swift` = unit (default)
- `*IntegrationTests.swift` = integration
- `*E2ETests.swift` = e2e
- `*SnapshotTests.swift` = snapshot

#### 3. Cross-Package Dependency Matrix

When a package changes, CI must run its dependents:

| Changed Package | Also Run |
|----------------|----------|
| CoreKit | NetKit, SecurityKit, ShikiCore, ShikiKit |
| NetKit | ShikiKit, ShikiMCP |
| SecurityKit | (leaf — nothing depends on it in test) |
| ShikiKit | ShikiMCP, shiki-ctl |
| ShikiCore | shiki-ctl |
| ShikiMCP | (leaf) |

Implementation: CI workflow uses `paths` filter per job:

```yaml
spm-corekit:
  if: contains(github.event.pull_request.changed_files, 'packages/CoreKit/')
  # runs: CoreKit + NetKit + SecurityKit + ShikiCore + ShikiKit tests

spm-netkit:
  if: contains(github.event.pull_request.changed_files, 'packages/NetKit/')
  # runs: NetKit + ShikiKit + ShikiMCP tests
```

Fallback: if change detection fails or touches >3 packages, run full suite.

#### 4. CI-to-Tier Mapping (integrates with Task 1)

| CI Job | Tier | Trigger | Packages |
|--------|------|---------|----------|
| `unit-tests` | T1 | All PRs | Changed package + dependents (unit only) |
| `integration-tests` | T2 | PRs to develop, release/* | All packages with integration test files |
| `e2e-tests` | T3 | PRs to develop, release/* | shiki-ctl binary tests (when stdin fix lands) |
| `ios-build-test` | T1+Snapshot | All PRs (Maya/WabiSabi repos) | xcodebuild test |

#### 5. Developer Workflow (the actual scoped testing)

During TDD, agents use this decision tree:

```
What am I changing?
  -> Single package, single file
     -> swift test --package-path <pkg> --filter "MySuiteTests"
     -> Expected: 1-5s

  -> Single package, multiple files
     -> swift test --package-path <pkg>
     -> Expected: 2-8s

  -> Cross-package change (e.g., CoreKit API change)
     -> swift test --package-path packages/CoreKit
     -> swift test --package-path packages/NetKit (if NetKit uses changed API)
     -> Expected: 5-15s total

  -> Pre-PR (epic or develop)
     -> swift test (entire workspace, all packages)
     -> Expected: 50-80s (acceptable — runs once)
```

This replaces the forbidden/not-required debate: the rule is **run the minimum that validates your change**. If you changed CoreKit, running only ShikiMCP tests is wrong. If you changed ShikiMCP, running CoreKit tests is waste.

#### 6. Test Environment Requirements

| Environment | What needs it | CI Setup | Local Setup |
|-------------|--------------|----------|-------------|
| macOS (no deps) | All T1 unit tests | `runs-on: macos-15` | Already available |
| Docker (ShikiDB) | T2 integration tests | `services: shikidb` in workflow | `docker compose up shikidb` |
| Docker (Deno backend) | T2 backend integration | `services: backend` in workflow | `docker compose up backend` |
| iOS Simulator | Maya/WabiSabi tests | Xcode on macOS runner, `iPhone 16`, iOS 18.2 | Boot once at session start |
| Compiled binary | T3 E2E | `swift build` step before test | `swift build` |

### Files to create/modify

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/ci.yml` (shiki root) | **CREATE** (shared with Task 1) | Tier-based test jobs with path filtering |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/TestTags.swift` | **CREATE** | Tag definitions for Swift Testing migration |
| `packages/ShikiCore/Tests/ShikiCoreTests/TestTags.swift` | **CREATE** | Shared tag definitions |
| `features/shiki-scoped-testing.md` | MODIFY | Replace premature ShikiCore code with process-first design |
| `scripts/test-scope.sh` | **CREATE** | Helper: detect changed packages, run minimum test set |

### Dependency on other P-items

- **Co-dependent with Task 1** — CI workflow design is shared. Task 1 defines triggers, Task 2 defines job contents.
- **Blocked by P0 (E2E stdin hang)** — Tier 3 tests remain skipped until resolved
- **Informs P1 (shiki ship --dry-run)** — ship gate needs to know which tests to run
- **Informs P1 (Deno OpenAPI)** — backend integration tests need Deno test runner too

### Sub-agent tasks (3 parallel groups)

**Group A — CI Test Matrix (infra)**
1. Design the CI workflow job matrix (path-based triggers, tier-based jobs, dependency-aware package runs)
2. Implement `scripts/test-scope.sh` — given a list of changed files, output the minimal `swift test` commands
3. Wire the script into CI (or replicate logic in workflow YAML if script is too heavy)

**Group B — Test Tagging + Isolation (code)**
1. Create `TestTags.swift` with tag definitions in ShikiCore and shiki-ctl test targets
2. Audit all 7 ShikiMCP test files — tag integration tests that require ShikiDB
3. Audit shiki-ctl: identify which of the 57 test files are pure-unit vs require external services. Document in a test-manifest comment at the top of CI workflow.

**Group C — Developer Tooling (DX)**
1. Write the decision-tree as a Claude Code skill (`.claude/skills/test-scope.md`) so agents auto-apply scoped testing during TDD
2. Create a pre-commit hook or CI check that warns when `swift test` is run without `--package-path` or `--filter` during development (advisory, not blocking)
3. Update `features/shiki-scoped-testing.md` with the challenged design — keep what works, replace ShikiCore code sections with process-first approach, add cross-package matrix and tier definitions

---

## Cross-Cutting Concerns

### Task 1 + Task 2 share a single deliverable

The `.github/workflows/ci.yml` file for the shiki monorepo is the intersection point. Task 1 defines WHEN it runs (branch triggers). Task 2 defines WHAT it runs (test tiers). These must be designed together — Group A from both tasks should be assigned to the same agent or executed sequentially.

### Execution Order

```
Phase 1 (parallel):
  Task 1 Group C (branch protection via gh api) — no code changes
  Task 2 Group B (test audit + tagging) — read-only analysis first, then small code adds

Phase 2 (sequential, depends on Phase 1 analysis):
  Task 1 Group A + Task 2 Group A (merged) — create CI workflow with triggers + test matrix

Phase 3 (parallel):
  Task 1 Group B (release scripts)
  Task 2 Group C (developer tooling + spec update)
```

### What is NOT in scope

- ShikiCore code changes (DependencyTree.epicBranch, TestScope struct, QualityGate) — deferred until ShikiCore is in CI and production
- `shiki ship --epic` flag — deferred until Task 1 process is validated manually
- `shiki start --epic` automation — deferred to v1.1
- Nested epics — explicitly forbidden per post-review
- Multi-simulator test runs — explicitly rejected per testing strategy
- Benchmark tests — explicitly rejected per testing strategy
