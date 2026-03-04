# /validate-pr — PR Checklist Validation

Verify every checklist item in a PR description before merge.
Unaddressed items go to the top of the backlog. No PR closes with unchecked mystery items.

## When to use

- Before merging any PR that has a checklist in its description
- After all code review and QC passes, as the final merge gate
- Can be run multiple times as items get addressed

## Commands

| Command | Action |
|---------|--------|
| `/validate-pr <PR#>` | Validate checklist for a specific PR |
| `/validate-pr` | Validate checklist for the current branch's PR |

## Pipeline (5 steps)

### Step 1: Fetch PR

```bash
gh pr view <PR#> --json number,title,body,url,headRefName,baseRefName
```

Parse the PR body for checklist items:
- `- [ ] item` → unchecked
- `- [x] item` → already checked

If no checklist found → report "No checklist in PR description" and stop.

### Step 2: Verify Each Unchecked Item

For each unchecked item (`- [ ]`):

1. **Parse the item text** — extract the requirement being described
2. **Search the diff** — `git diff <base>...<head>` for evidence of implementation
3. **Search the codebase** — grep for relevant code if diff isn't conclusive
4. **Classify**:
   - `IMPLEMENTED` — clear evidence in code that this item is done
   - `PARTIAL` — some evidence but incomplete
   - `NOT_ADDRESSED` — no evidence found

**Evidence requirements** (per Verification Protocol):
- Must cite specific file:line as evidence
- Must not guess or assume — if unclear, classify as `PARTIAL`

### Step 3: Update PR Description

For items classified as `IMPLEMENTED`:
- Update the PR body to check the box (`- [x]`)
- Use `gh pr edit <PR#> --body "..."` with the updated body

For `PARTIAL` items:
- Leave unchecked
- Add a comment note: `<!-- partial: evidence in file:line but incomplete -->`

For `NOT_ADDRESSED` items:
- Leave unchecked

### Step 4: Backlog Unaddressed Items

For each `NOT_ADDRESSED` or `PARTIAL` item:

1. Add to the **top** of `backlog.md` under a new section:
   ```markdown
   ## Carried from PR #<number> — <title>
   - [ ] <item text> (from PR #<number>)
   ```
2. Sync to Shiki if available:
   ```bash
   POST http://localhost:3900/api/memories
   {
     "projectId": "{project_id}",
     "content": "Backlogged from PR #<number>: <item>",
     "category": "roadmap",
     "importance": 0.7,
     "metadata": { "sourceFile": "backlog.md", "pr": <number> }
   }
   ```

Note: `{project_id}` comes from the project adapter or Shiki workspace registration.

### Step 5: Report

Display a summary table:

```markdown
## PR #<number> Checklist Validation

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | Run tests — all green | IMPLEMENTED | CI passed, test output in PR |
| 2 | Verify on target device | NOT_ADDRESSED | No evidence found |
| 3 | Check dark mode | IMPLEMENTED | Snapshots in QC report |

### Result
- **Validated**: 2/3 items checked
- **Backlogged**: 1 item → backlog.md
- **Verdict**: HAS GAPS — 1 item moved to backlog

### Backlogged Items
1. "Verify on target device" → added to backlog (from PR #19)
```

**Verdicts:**
- `READY TO MERGE` — all items checked (implemented or were already checked)
- `HAS GAPS` — some items not addressed, moved to backlog
- `BLOCKED` — critical items not addressed (items containing "must", "required", "blocking")

## Integration with /pre-pr

Gate 9 (PR Creation) generates the initial checklist in the PR body.
`/validate-pr` runs as the final step before merge, after all reviews and fixes.

Recommended flow:
```
/pre-pr → PR created with checklist
  ... code review, fixes, discussion ...
/validate-pr <PR#> → verify checklist before merge
  gh pr merge <PR#>
```

## Anti-Rationalization

| Thought | Response |
|---------|----------|
| "All the important items are checked, the rest are minor" | Minor items become major bugs. Validate everything or backlog it explicitly. |
| "I can check this manually, no need to verify in code" | If it's not in the diff, it's not implemented. Check evidence, not intentions. |
| "The PR is already approved, validation is redundant" | Approval means the code is good. Validation means the scope is complete. Different things. |
| "I'll address the unchecked items in a follow-up PR" | That's exactly what backlogging does — but explicitly tracked, not forgotten. |
