# Feature Tracking — README Roadmap

Maintain a living feature checklist in `README.md` that tracks every feature's progress
through the pipeline. Single source of truth for "what's done, what's in progress."

## Location

- **Feature files**: `features/<name>.md` (repo root, tracked in git)
- **Feature checklist**: `README.md` → `## Feature Roadmap` section

## README Format

The `## Feature Roadmap` section in `README.md` contains a checklist of all features:

```markdown
## Feature Roadmap

- [x] [Onboarding](features/onboarding.md) — Interactive onboarding flow with atmosphere animations
- [ ] [Habit Tracking](features/habit-tracking.md) — Core habit creation and daily tracking
  **WIP (5/8 phases)**
  - [x] Phase 1: Inspiration
  - [x] Phase 2: Synthesis
  - [x] Phase 3: Business Rules
  - [x] Phase 4: Test Plan
  - [x] Phase 5: Architecture
  - [ ] Phase 5b: Execution Plan
  - [ ] Phase 6: Implementation
  - [ ] Phase 7: Quality Gate
- [ ] [Push Notifications](features/push-notifications.md) — Daily reminders and streak alerts
  **WIP (2/4 steps)**
  - [x] Step 1: Quick Spec
  - [x] Step 2: TDD Implementation
  - [ ] Step 3: Self-Review
  - [ ] Step 4: Ship
```

### Rules

1. **Top-level checkbox** = feature fully shipped (PR merged and validated via `/validate-pr`)
2. **Unchecked top-level** = feature in progress or planned
3. **Sub-checklist** = WIP phase/step tracking (only for in-progress features)
4. **Title** = feature name as markdown link to `features/<name>.md`
5. **Description** = one-line summary after the `—` dash
6. **WIP counter** = `(N/M phases)` or `(N/M steps)` bold prefix on sub-checklist
7. Sub-checklist is removed once the feature is complete (top-level checked)

### /md-feature sub-checklist (8 phases)

```markdown
  **WIP (0/8 phases)**
  - [ ] Phase 1: Inspiration
  - [ ] Phase 2: Synthesis
  - [ ] Phase 3: Business Rules
  - [ ] Phase 4: Test Plan
  - [ ] Phase 5: Architecture
  - [ ] Phase 5b: Execution Plan
  - [ ] Phase 6: Implementation
  - [ ] Phase 7: Quality Gate
```

### /quick sub-checklist (4 steps)

```markdown
  **WIP (0/4 steps)**
  - [ ] Step 1: Quick Spec
  - [ ] Step 2: TDD Implementation
  - [ ] Step 3: Self-Review
  - [ ] Step 4: Ship
```

## When to Update

| Event | Action |
|-------|--------|
| `/md-feature "<name>"` starts | Add new entry with Phase 1 checked |
| `/md-feature next "<name>"` completes a phase | Check the completed phase |
| `/quick "<desc>"` starts | Add new entry with Step 1 checked |
| `/quick` completes a step | Check the completed step |
| `/validate-pr` passes with all items | Check top-level checkbox, remove sub-checklist |
| Feature abandoned | Remove entry or mark with ~~strikethrough~~ |

## Update Protocol

### Adding a new feature

1. Create `features/<name>.md` using the feature file template
2. In `README.md`, find `## Feature Roadmap` section
3. Add new entry at the bottom of the list:
   ```markdown
   - [ ] [Feature Name](features/<name>.md) — Short description
     **WIP (1/8 phases)**
     - [x] Phase 1: Inspiration
     - [ ] Phase 2: Synthesis
     ...
   ```
4. If the section doesn't exist, create it after `## Features`

### Advancing a phase

1. In `README.md`, find the feature entry
2. Check the completed phase checkbox
3. Update the WIP counter: `(N/M phases)` → `(N+1/M phases)`

### Completing a feature

1. Check the top-level checkbox: `- [ ]` → `- [x]`
2. Remove the entire WIP sub-checklist (clean up)
3. Keep the title link and description

## Feature File Location

Feature files live in `features/` in the repo root:

- **Path**: `features/<name>.md` (in repo, tracked in git, linkable from README)

The feature pipeline template and content remain the same — only the path changes.

Update in your pipeline commands:
- `/md-feature` → creates/updates `features/<name>.md`
- `/md-feature status` → scans `features/` directory
- Gate 1a (Spec Review) → loads from `features/*.md`

## Shiki Sync

After updating the README feature roadmap, sync the status to Shiki if available:
```bash
POST http://localhost:3900/api/memories
{
  "projectId": "{project_id}",
  "content": "Feature roadmap updated: <feature> advanced to Phase N",
  "category": "roadmap",
  "importance": 0.6,
  "metadata": { "sourceFile": "README.md" }
}
```

Note: `{project_id}` comes from the project adapter or Shiki workspace registration.
