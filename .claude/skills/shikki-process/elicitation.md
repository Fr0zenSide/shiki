# Advanced Elicitation — Structured Deep Thinking

Optional "think harder" methods available at key phase checkpoints.
When offered, the user can pick one method or skip.

## When to Offer

Offer elicitation at the END of these phases (after the phase output, before proceeding):
- **Phase 1 (Inspiration)**: After brainstorm results, before @Daimyo selects ideas
- **Phase 3 (Business Rules)**: After BR-XX rules drafted, before @Daimyo approval
- **Phase 5 (Architecture)**: After architecture designed, before execution plan

Offer as: "Deepen this phase? Pick a method or skip: [Pre-mortem / Inversion / Edge Storm / Skip]"

At Phase 3 specifically, also offer: [Red Team / Edge Storm] (both are relevant for rule validation).
At Phase 5, also offer: [Constraint Removal] (architecture is where scope decisions solidify).

## Methods

### Pre-mortem

**Prompt**: "It's 6 months from now. This feature has failed completely. What went wrong?"

**Use when**: Validating feasibility, catching hidden risks, checking assumptions.

**Process**:
1. Assume total failure
2. Generate 5-7 specific failure scenarios (not vague -- concrete with user impact)
3. For each: root cause, warning sign we'd see today, mitigation
4. Present as table

**Output**:
```markdown
| # | Failure Scenario | Root Cause | Warning Sign Today | Mitigation |
|---|------------------|------------|--------------------|------------|
| 1 | Users abandon feature after day 2 | Onboarding too complex | 5+ taps to first value | Reduce to 3 taps max |
```

### Inversion

**Prompt**: "How would you make this feature as terrible as possible?"

**Use when**: Finding blind spots in UX, discovering anti-patterns, stress-testing design.

**Process**:
1. List 5-7 ways to make the feature actively harmful or annoying
2. For each: check if the current design accidentally does this (even partially)
3. If yes: flag as a design concern
4. Present findings

**Output**:
```markdown
| # | Terrible Version | Current Design Does This? | Concern |
|---|-----------------|:-------------------------:|---------|
| 1 | Require login before showing any value | Partially -- paywall on page 3 | Move paywall to after first win |
```

### Edge Storm

**Prompt**: "What inputs, states, or conditions break every business rule?"

**Use when**: After Phase 3, validating completeness of BR-XX rules.

**Process**:
1. For each BR-XX: find 2-3 edge cases not covered
2. Categories: nil/empty, boundary values, concurrent access, time zones, locale, device state (low memory, no network, background), accessibility mode
3. For each edge case: which BR fails? What is the user impact?
4. Propose additional BRs or BR amendments

**Output**:
```markdown
| BR | Edge Case | Category | Impact | Proposed Fix |
|----|-----------|----------|--------|-------------|
| BR-01 | Reset at midnight in user's TZ vs UTC | Time zone | Streak breaks at wrong time | Amend BR-01: use device local time |
```

### Red Team

**Prompt**: "You are a malicious user. How do you abuse this feature?"

**Use when**: Features with user input, payments, social features, data access.

**Process**:
1. Identify 3-5 abuse vectors
2. For each: attack method, impact, difficulty for attacker
3. Check if current BRs/architecture defend against each
4. Propose mitigations for undefended vectors

**Output**:
```markdown
| # | Attack Vector | Impact | Difficulty | Defended? | Mitigation |
|---|--------------|--------|:----------:|:---------:|------------|
| 1 | Replay purchase receipt | Free premium access | Medium | No | Server-side receipt validation |
```

### Constraint Removal

**Prompt**: "If you had unlimited time, budget, and no technical constraints, what would this feature look like?"

**Use when**: Checking if practical constraints have narrowed thinking too much.

**Process**:
1. Describe the "dream" version (5-7 bullet points)
2. Compare with current scope
3. Identify 1-2 elements from the dream version that ARE feasible and would significantly improve the feature
4. Propose as scope additions (user decides)

**Output**:
```markdown
### Dream Version
- <bullet points>

### Feasible Additions
| Element | Effort | Impact | Recommendation |
|---------|:------:|:------:|---------------|
| Haptic feedback on streak milestones | Low | High | Add to v1 scope |
```

## Output Format

After running any method, present:

```markdown
## Elicitation: <Method Name> -- <Feature>
<findings table>

### Recommended Actions
1. <specific action with phase reference>
2. <specific action>
3. (none -- current design holds up)

Apply these? (y/n/partial)
```

If user says yes: apply changes to the feature file, note in Review History which method was used.
If user says partial: ask which items to apply.
If user says no: log that elicitation was run but no changes applied.

## Integration with YOLO Mode

When `--yolo` is active, elicitation offers are auto-skipped. The pipeline proceeds without pausing at elicitation checkpoints. This is documented in `feature-pipeline.md`.

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "The user said skip, so elicitation is always optional" | Correct -- it IS optional. But always offer it at the designated checkpoints. Do not pre-skip. |
| "Pre-mortem is negative thinking, it will slow us down" | Pre-mortem takes 3 minutes and prevents 3-week disasters. Offer it. |
| "Edge cases are covered by the test plan" | Test plans cover KNOWN edge cases. Edge Storm finds the ones you have not thought of. |
| "Red Team is overkill for an internal feature" | Internal features become external features. Security debt compounds. Offer it when relevant. |
| "Constraint Removal is just daydreaming" | It is structured daydreaming. It catches scope-blindness where practical concerns kill good ideas prematurely. |
| "Running 2 methods on the same phase is wasteful" | If the user picks 2 methods, they want 2 perspectives. Run both. The user decides what is wasteful, not the pipeline. |
