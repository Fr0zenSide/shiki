Run the /decide interactive decision ballot for @Daimyo.

A fast, structured Q/A format to unlock blocked decisions. Similar to `/backlog-challenge` but usable anywhere — during autopilot, mid-feature, or ad-hoc.

## Usage

```
/decide                          # Present next pending decisions from current context
/decide "<topic>"                # Ask decisions about a specific topic
/decide recap                    # Show all decisions made this session
```

## Arguments

Parse `$ARGUMENTS`:
- No args → detect pending decisions from current pipeline state (autopilot wave, feature phase, backlog)
- `"<topic>"` → generate decisions about the given topic
- `recap` → display all decisions recorded in the current session

## Presentation Format

Present decisions in a compact, numbered ballot format. Each question has lettered options with one marked as **(Recommended)** and a short rationale.

```markdown
## Decisions — <context>

### Q1: <Short question title>
<One line of context explaining why this matters>

  (a) Option A description **(Recommended)** — rationale
  (b) Option B description — rationale
  (c) Option C description — rationale

### Q2: <Short question title>
<Context>

  (a) Option A **(Recommended)** — rationale
  (b) Option B — rationale

---
Answer: `1a, 2b` or discuss any question.
```

## Rules

### Presentation
- MAX 6 decisions per ballot (avoid decision fatigue)
- Each question has 2-4 options, never more
- Always mark one option as **(Recommended)** with @Sensei rationale
- Keep option descriptions to ONE line
- Context line explains WHY this decision matters (consequence of wrong choice)
- Show the answer format at the bottom as a reminder

### Accepting Answers
- Accept batch format: `1a, 2b, 3c` (comma-separated)
- Accept shorthand: `all R` or `all recommended` (accept all recommended)
- Accept discussion: "discuss Q2" or "tell me more about 2b"
- Accept partial: answer some now, defer others
- Accept override: any free-text answer is recorded verbatim

### After Answers
1. Confirm the decisions in a recap table:
   ```
   | Q# | Decision | vs Recommended |
   |-----|----------|----------------|
   | Q1 | (a) ✓ | = Recommended |
   | Q2 | (b) | Override — rationale noted |
   ```
2. Persist to `memory/planner-state.md` decision log (append to the table)
3. If in an autopilot or feature pipeline, feed decisions back and continue
4. Update any blocked backlog items that were waiting on these decisions

### Sources for Decisions
When auto-detecting pending decisions, check:
1. **Decision queue** (cross-company): Use the `shiki_search` MCP tool with: `{ query: "pending decisions", projectIds: [] }` — highest priority source
2. Current autopilot wave state (blocking questions from Wave 0/1)
3. Feature files in `memory/features/` with `blocking_questions > 0`
4. Backlog items marked `Status: Needs decision`
5. Mid-conversation context (questions asked but not yet answered)

### Cross-Company Mode
When decisions come from the decision queue API, group them by company and include the company name in the header:

```markdown
## Decisions — Cross-Company

### WabiSabi (2 pending)
Q1: ...
Q2: ...

### Maya (1 pending)
Q3: ...
```

After answering, record each decision: Use the `shiki_save_event` MCP tool with: `{ type: "decision_answered", scope: "orchestrator", data: { decisionId: "<id>", answer: "<chosen option>", answeredBy: "@Daimyo" } }`

The system automatically unblocks tasks whose decisions are all answered.

## Anti-Rationalization

| Temptation | Why it's wrong |
|-----------|---------------|
| "Present 12 decisions at once" | Decision fatigue. Max 6. Batch the rest for next round. |
| "Skip the Recommended tag" | @Daimyo needs a starting point. Recommending is not deciding. |
| "Record without confirming" | Always show the recap table. Misrecorded decisions are worse than no decision. |
| "Skip persistence" | Decisions not in planner-state.md will be forgotten. Write them down. |
