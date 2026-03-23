# /inbox — Pending Task Review Dashboard

Open a tmux review window with one pane per pending deliverable. Each pane displays a summary for @Daimyo to validate, correct, or approve.

## Arguments
- No arguments: show all pending items (specs, PRs, decisions, plans)
- `prs` — show only pending PRs
- `specs` — show only pending specs/plans
- `decisions` — show only pending T1 decisions

## Execution

### Step 1: Gather Pending Items
Collect ALL items that need user attention:

1. **Open PRs**: `gh pr list --json number,title,headRefName,body --limit 20`
2. **Pending T1 Decisions**: `curl -s http://localhost:3900/api/decision-queue?pending=true`
3. **Unreviewed spec files**: Check `features/p*.md` files modified in the last 24h
4. **Claude plan files**: Check `~/.claude/plans/*.md` — plans that haven't been executed
5. **Completed background agents**: Check recent task outputs for unreviewed results

### Step 2: Create Review Window
Create a new tmux window called "inbox" in the current session:

```bash
tmux new-window -t shiki -n inbox
```

### Step 3: Create Panes
For each pending item (max 8 panes), split the window into a grid:
- Use `split-window -v` and `split-window -h` to create a grid layout
- Each pane gets a title via `select-pane -T "ITEM_TYPE: short_name"`

### Step 4: Populate Each Pane
Send a summary to each pane via `send-keys`. The summary format:

```
═══════════════════════════════════════
  TYPE: Item Name
  Status: pending | needs-review | blocked
  Branch: feature/xxx (if applicable)
═══════════════════════════════════════

SUMMARY:
[2-3 line description of what this is]

ACTION NEEDED:
[What the user should do — approve, correct, or reject]

TO APPROVE: Copy this to orchestrator pane:
  > approve PR #XX / approve spec p0-immediate-plan

TO CORRECT: Copy this to orchestrator pane:
  > /course-correct [your correction here]

═══════════════════════════════════════
```

### Step 5: Report
Print to the orchestrator pane:
```
Inbox opened: N items across M categories
Window: shiki:inbox (Ctrl-b n to switch)
Items auto-close after 10min idle.
```

## Rules
- Max 8 panes per window (more than 8 = paginate into multiple windows: inbox-1, inbox-2)
- Pane border titles enabled with `pane-border-status top`
- Grid layout: `select-layout tiled` after all panes created
- Each pane runs `bash -c 'echo "...summary..." && read -t 600'` (auto-closes after 10min)
- Never create empty panes — skip categories with 0 items
- If zero pending items: print "Inbox clear — nothing pending." and don't create a window
