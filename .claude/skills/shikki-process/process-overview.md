# Shiki Development Process — Complete Overview

How ideas become shipped features. Every path goes through quality gates.
No code ships without tests. No PR ships without review.

## The Big Picture

```
                        YOU (ideas, decisions, reviews)
                                    |
                    +---------------+---------------+
                    |               |               |
               Small fix      New feature      Scope change
                    |               |               |
                 /quick        /md-feature     /course-correct
                    |               |               |
              +-----+        +-----+-----+         |
              |              |           |          |
         Quick Spec     Phase 1-3    Phase 1-3  Impact Trace
         TDD + Ship    (interactive) (corrected)    |
              |              |           |     Tweak/Pivot/Fork
              |         Phase 5b         |          |
              |        Exec Plan    +----+     Resume from
              |              |      |          affected phase
              |         Phase 6     |
              |          (SDD)      |
              |       autonomous    |
              |      [subagents]    |
              |              |      |
              +---------+----+------+
                        |
                     /pre-pr
                   9 quality gates
                        |
                  +-----+-----+
                  |           |
              PR created   FAIL
                  |        fix loop
             /review       (max 3 tries
           interactive      then escalate)
                  |
              YOU approve
                  |
                merge
```

## Two Tracks

### Quick Track (`/quick "fix the broken animation"`)

```
Quick Spec ──> TDD ──> Self-Review ──> Ship
  (2 min)    (5-15m)    (2 min)      (1 min)
```

Scope guard auto-detects if it's bigger than a quick fix (7 signals, threshold 2).
Escalates to `/md-feature` when needed.

### Feature Track (`/md-feature "imperfect-days"`)

```
Phase 1         Phase 2       Phase 3        Phase 4        Phase 5
INSPIRATION     SYNTHESIS     BUSINESS       TEST PLAN      ARCHITECTURE
@Shogun(3)  --> Q&A with --> RULES       --> Test sigs  --> Files, DI,
@Hanami(3)      @Daimyo      BR-01..N       per BR-XX      data flow
@Kintsugi(2)                 @Sensei                        @Sensei
@Sensei(2)                   drafts,
10 ideas                     @Daimyo
ranked                       approves
    |               |             |              |              |
    v               v             v              v              v
 [Deepen?]                    [Deepen?]                     [Deepen?]
 Pre-mortem                   Edge Storm                    Inversion
 Skip -->                     Skip -->                      Skip -->

                                    Phase 5b            Phase 6
                                    EXECUTION PLAN      IMPLEMENTATION (SDD)
                                    Atomic tasks    --> Fresh subagent per task:
                                    2-5 min each        1. IMPLEMENTER (TDD)
                                    BR refs             2. SPEC REVIEWER
                                    Test commands       3. QUALITY REVIEWER
                                    @Sensei             4. FINAL REVIEWER
                                        |                       |
                                        v                       v
                                 [Readiness Gate]        [Def of Done]
                                  8 checks PASS          31 items PASS
                                        |                       |
                                        +----------+------------+
                                                   |
                                              Phase 7
                                           QUALITY GATE
                                             /pre-pr
```

## Quality Gates (`/pre-pr`)

```
Gate 1a: SPEC REVIEW ──> Gate 1b: QUALITY REVIEW ──> [Gate 1c: @RONIN]
  @Sensei checks            @Sensei (CTO)              Adversarial
  every BR-XX               @Hanami (UX)               (optional
  against the diff          @tech-expert               --adversarial)
         |                       |                          |
         v                       v                          v
Gate 2: FIX LOOP ────────────────────────────────> (3 failures = STOP)
         |
Gate 3: TEST COVERAGE ──> Gate 4: FIX LOOP
  {test_command}             Fix + re-test
  >= 60% changed
  100% critical
         |
Gate 5: VISUAL QC ──> Gate 6: USER REVIEW ──> Gate 7: FIX LOOP
  (if configured)      @Daimyo approves       Apply feedback
  (Standard mode only) side-by-side           re-capture
         |
Gate 8: AI SLOP SCAN ──> Gate 9: PR CREATION
  Zero AI markers           gh pr create
  (release PRs only)        with gate results
```

## Code Review (`/review`)

```
/review queue                    /review 42
    |                                |
 Ranked table                  Load PR + diff
 by priority                        |
 risk levels                   Pre-analysis (parallel):
 stale detection                 @Sensei  @Hanami  @tech-expert
    |                                |
 Pick a PR                     Findings table
    |                          Critical / Important / Minor
    +----->  Interactive Review  <-----+
                    |
             Navigate files (next/prev/file)
             Ask questions ("why this approach?")
             Challenge ("violates architecture")
                    |
             approve / changes / comment
                    |
             Post to GitHub (gh pr review)
                    |
             [Auto-fix agent if changes requested]
```

## Parallel Dispatch (`/dispatch`)

```
/dispatch "habit-streaks"        /dispatch all
         |                            |
   Create worktree              Scan features/
   story/<feature>              Filter to Phase 5b+
         |                      Readiness PASS
   Background agent                   |
   SDD -> DoD -> /pre-pr        Conflict detection
         |                      (max 3 concurrent)
   Dispatch Board                     |
   +-------+--------+--------+  Dispatch each
   | feat  | status | PR     |       |
   | str.. | 3/8    | --     |  Dispatch Board
   | imp.. | /pre-pr| --     |  (same table)
   | wk..  | DONE   | #45   |
   +-------+--------+--------+
```

## Agent Roster (8 personas)

Agents are **centralized in Shiki** and grow across all projects. Each agent has:
- A **persona definition** in `agents.md` (how they behave)
- A **growth file** in `shikki/team/<agent>.md` (what they've learned across projects)
- Per-project adaptation via `project-adapter.md`

See `shikki/team/README.md` for the 3-layer memory architecture.

| Agent | Role | Growth File | Invoked at |
|-------|------|-------------|-----------|
| @Sensei | CTO / Technical Architect | `team/sensei.md` | Phase 1, 3, 5, 5b, Gate 1a/1b |
| @Hanami | Product Designer / UX Lead | `team/hanami.md` | Phase 1, Gate 1b (UI only) |
| @Kintsugi | Philosophy & Repair | `team/kintsugi.md` | Phase 1, soul checks |
| @Enso | Brand Identity & Mindfulness | `team/enso.md` | Brand alignment, tone |
| @Tsubaki | Content & Copywriting | `team/tsubaki.md` | Copy, marketing, descriptions |
| @Shogun | Competitive Intelligence | `team/shogun.md` | Phase 1, market research |
| @Ronin | Adversarial Reviewer | `team/ronin.md` | Gate 1c, 3-failure escalation |
| @Daimyo | Founder (you) | — | All approvals, final decisions |

## Three-Pass Development Cycle

Every feature goes through three passes. Never mix structure work with polish work.
Between passes, stay creative — think out of the box, challenge assumptions, self-improve.
A living agency beats a rigid process every time.

```
Pass 1: SKELETON                    Pass 2: MUSCLE                     Pass 3: SKIN
────────────────                    ──────────────                     ──────────
Navigation, architecture,          Core features working              UI polish, animations,
DI, coordinators, data flow        end-to-end, business logic,        micro-interactions,
                                   persistence, error handling        visual QC

Quality bar:                       Quality bar:                       Quality bar:
  ✓ Compiles                         ✓ All features functional          ✓ Visual QC approved
  ✓ Navigates                        ✓ TDD green                        ✓ Multiple devices tested
  ✓ Tests pass                       ✓ /pre-pr gates pass               ✓ Motion design signed off
                                                                        ✓ /pre-release-scan clean

When:                              When:                              When:
  Feature development               Pre-v1, each sprint                Pre-release
  Move fast, break nothing           Merge to develop                   develop→main merge
```

### Philosophy

- **Pass 1-2 move fast.** The goal is working software, not beautiful software.
  Ugly-but-functional beats pretty-but-broken. Ship the skeleton, build the muscle.
- **Pass 3 is a dedicated quality sweep.** This is where visual QC, @Hanami visual review,
  animation timing, and pixel-level polish happen. Not before.
- **Between passes, innovate.** Don't just follow the process — challenge it.
  If a competitor does X, ask "what if we did the opposite?"
  The process serves creativity, not the other way around.
- **Pre-release QA is mandatory.** Before any release, every screen goes through
  visual QC. No exceptions. No "it looks fine on my device."

### Pass Tracking

Track current pass in the feature file:

```markdown
## Status
Pass: 2/3 (Muscle)
- [x] Pass 1: Skeleton — nav, arch, DI, coordinator
- [→] Pass 2: Muscle — features, TDD, /pre-pr
- [ ] Pass 3: Skin — UI polish, visual QC, animations
```

## Safety Rails

### Three-Failure Escalation
After 3 failed fix attempts on the same issue: STOP. Don't try a 4th.
Present to @Daimyo: rethink / @Ronin / skip / revert.

### Verification Before Completion
No "Done!" without fresh test output. Forbidden: "should work", "probably passes".

### Anti-Rationalization
52+ entries across all skills. Every excuse the AI will try has a counter.

### AI Slop Scan
Before release: zero tolerance for AI agent references in shipped code.

## File Structure

```
shiki/
  team/                    <-- Agent cross-project knowledge (Layer 1)
    README.md              <-- 3-layer architecture doc
    sensei.md              <-- @Sensei growth file
    hanami.md              <-- @Hanami growth file
    kintsugi.md            <-- @Kintsugi growth file
    enso.md                <-- @Enso growth file
    tsubaki.md             <-- @Tsubaki growth file
    shogun.md              <-- @Shogun growth file
    ronin.md               <-- @Ronin growth file
  .claude/
    commands/              <-- Slash command entry points (in git)
      quick.md
      md-feature.md
      pre-pr.md
      review.md
      dispatch.md
      course-correct.md
      pre-release-scan.md
      validate-pr.md
      retry.md
    skills/
      shikki-process/       <-- Process knowledge base (in git)
        README.md
        agents.md          <-- 8 agent personas + 3-layer model ref
        bootstrap.md       <-- SessionStart hook (always-on rules)
        feature-pipeline.md
        pre-pr-pipeline.md
        sdd-protocol.md
        quick-flow.md
        pr-review.md
        parallel-dispatch.md
        course-correct.md
        elicitation.md
        verification-protocol.md
        ai-slop-scan.md
        feature-tracking.md
        pr-checklist-validation.md
        process-overview.md  <-- This file
        project-adapter-template.md
        checklists/
          cto-review.md     <-- @Sensei (universal)
          ux-review.md      <-- @Hanami (universal)
          code-quality.md   <-- @tech-expert (universal)
          definition-of-done.md  <-- Phase 6 exit
        addons/
          cto-review-swift.md     <-- Swift-specific CTO review items
          code-quality-swift.md   <-- Swift-specific code quality items
    settings.json          <-- Hooks config (SessionStart bootstrap)

<project>/                 <-- Per-project (Layer 2 + 3)
  .claude/
    project-adapter.md     <-- Layer 2: tech stack, conventions, commands
    commands/              <-- Project-specific commands (backlog, etc.)
  memory/                  <-- Layer 3: project state
    backlog.md, features/, planner-state.md, ...
```

## Portability

### What moves with git (fully portable)
- All commands (`.claude/commands/`)
- All skills (`.claude/skills/shikki-process/`)
- Agent team knowledge (`team/`) — cross-project growth files
- Settings + hooks (`.claude/settings.json`)
- Project adapter template
- Scripts (`scripts/`)

### What stays on the machine
- Worktrees (`.claude/worktrees/`) — recreated per machine
- Local settings (`.claude/settings.local.json`) — machine-specific permissions
- Database state (PostgreSQL data)

### What Shiki provides for portability
- All memory/knowledge synced to Shiki PostgreSQL with vector embeddings
- `scripts/backup-db.sh` creates `.sql.gz` backups (14-day retention)
- On a new machine: restore the backup → all project knowledge is searchable
- Memory files can be regenerated from search results

### What a new machine needs
Run `./shikki init` — one command to bootstrap everything.

## Complete Command Set

| Command | What it does |
|---------|-------------|
| `/quick "desc"` | 4-step lightweight pipeline (spec, TDD, self-review, ship) |
| `/quick "desc" --yolo` | Quick Flow with no confirmations |
| `/md-feature "name"` | Start 8-phase feature pipeline (brainstorm to PR) |
| `/md-feature review "name"` | Revisit existing feature, Q&A |
| `/md-feature status` | List all features and their current phase |
| `/md-feature next "name"` | Advance feature to next phase |
| `/md-feature next "name" --yolo` | Auto-proceed, skip confirmations + elicitation |
| `/pre-pr` | Full 9-gate quality pipeline (spec, quality, tests, QC, PR) |
| `/pre-pr --web` | Simplified pipeline for web projects (4 gates) |
| `/pre-pr --skip-qc` | Skip visual QC gate |
| `/pre-pr --adversarial` | Add Gate 1c (@Ronin adversarial review) |
| `/pre-pr --yolo` | Auto-proceed through passing gates |
| `/review <PR#>` | Interactive review of specific PR with pre-analysis |
| `/review queue` | Show open PRs ranked by priority + dashboard |
| `/review batch` | Review all open PRs sequentially |
| `/dispatch "feature"` | Dispatch feature for autonomous parallel implementation |
| `/dispatch all` | Dispatch all ready features (Phase 5b+, readiness PASS) |
| `/dispatch status` | Show dispatch board (worktrees, agents, PRs) |
| `/dispatch cancel "feature"` | Cancel a running dispatch and clean up worktree |
| `/course-correct "feature"` | Mid-feature scope change (impact trace, Tweak/Pivot/Fork) |
| `/pre-release-scan` | Scan for AI markers before release |
| `/validate-pr` | Verify PR checklist before merge |
| `/retry` | Scan and relaunch stuck sub-agents |
