# Decision Queue Skill

The decision queue replaces interactive blocking questions with a persistent, cross-company queue stored in Shiki DB. Questions survive crashes, are answerable from any session, and automatically unblock tasks when answered.

## Tier System

| Tier | Tag | Behavior | Who answers |
|------|-----|----------|-------------|
| **T1** | `[BLOCKING]` | Task stops, written to DB, orchestrator notifies user | @Daimyo via /orchestrate decide |
| **T2** | `[IMPORTANT]` | If `--yolo`: auto-answered with default. Otherwise: written to DB | @Daimyo or auto-default |
| **T3** | `[DEFAULT-OK]` | Always auto-answered with subagent's default choice | Subagent (logged but not queued) |

## Flow: Company Autopilot → Decision Queue

### When a company's autopilot hits a T1 question during Wave 1:

```
1. POST /api/decision-queue
   {
     "companyId": "<company-uuid>",
     "taskId": "<current-task-uuid>",
     "tier": 1,
     "question": "Where should the haiku appear?",
     "options": {
       "a": "Full-screen overlay on first open",
       "b": "Card in Today tab",
       "c": "Splash-to-home transition"
     },
     "context": "This affects the coordinator flow and whether we need a new screen vs a card component."
   }

2. Get back decision ID

3. PATCH /api/task-queue/<task-id>
   {
     "status": "blocked",
     "blockingQuestionIds": ["<decision-id>"]
   }

4. Move to next non-blocked task in queue
```

### Polling for answers (company session):

```
Every 30 seconds:
  GET /api/decision-queue?company_id=<id>&answered=false

  If a previously-blocking decision is now answered:
    → The API already unblocked the task (answerDecision auto-unblocks)
    → Resume the task from checkpoint
```

## Flow: Orchestrator → User → Answer

```
1. Orchestrator heartbeat detects pending T1 decisions
   GET /api/decision-queue/pending

2. Send ntfy push:
   "🔴 3 decisions needed (WabiSabi: 2, Maya: 1)"

3. User runs /orchestrate decide (or /decide)

4. Decisions presented in standard ballot format:

   ## Decisions — Cross-Company

   ### WabiSabi
   Q1: Where should the haiku appear?
     (a) Full-screen overlay **(Recommended)** — minimal coordinator changes
     (b) Card in Today tab — requires new card component
     (c) Splash transition — most complex, best UX

   Q2: Content source?
     (a) Bundled seed data **(Recommended)** — offline-first
     (b) Backend-fetched — requires API endpoint

   ### Maya
   Q3: Geo-fence radius for discovery?
     (a) 500m **(Recommended)** — walking distance
     (b) 2km — cycling distance

   Answer: 1a, 2a, 3b

5. For each answer:
   PATCH /api/decision-queue/<id>
   {
     "answer": "a — Full-screen overlay",
     "answeredBy": "@Daimyo"
   }

6. API auto-unblocks tasks whose decisions are all answered
```

## Answer Routing

When a decision is answered via `PATCH /api/decision-queue/:id`:

1. The `answerDecision()` function:
   - Sets `answered=TRUE`, records answer and timestamp
   - Checks remaining unanswered decisions for the same task
   - If all answered → sets task status back to `pending`

2. The company session (on next 30s poll):
   - Sees previously-blocked task is now `pending`
   - Reclaims and resumes from last pipeline checkpoint

## Options Format

Options are stored as JSONB. Two formats are supported:

### Keyed options (ballot-style):
```json
{
  "a": "Full-screen overlay",
  "b": "Card in Today tab",
  "c": "Splash transition"
}
```

### Rich options (with metadata):
```json
{
  "a": {"label": "Full-screen overlay", "recommended": true, "rationale": "Minimal changes"},
  "b": {"label": "Card in Today tab", "rationale": "Requires new component"},
  "c": {"label": "Splash transition", "rationale": "Best UX, most complex"}
}
```

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Decision answered but company exited | Orchestrator relaunches company on next heartbeat |
| Multiple decisions block same task | Task unblocks only when ALL are answered |
| User answers with free text (not a/b/c) | Recorded verbatim, task unblocks |
| Decision created with no task_id | Standalone decision, no auto-unblock logic |
| Company archived with pending decisions | Decisions remain in DB but are effectively orphaned |
