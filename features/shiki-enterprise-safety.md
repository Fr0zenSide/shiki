# Feature: Enterprise Safety — Budget ACL, Anomaly Detection, Audit Trail

> **Type**: /md-feature
> **Priority**: P2 — needed for enterprise tier, architecture decisions now
> **Status**: Spec (validated by @Daimyo + @Shi team 2026-03-18)
> **Depends on**: Knowledge MCP (P0), Event Router (P0.5), Multi-user (future)

---

## 1. Problem

Single-user Shiki has no access control. Enterprise Shiki needs:
- Cost control per user/team (who spends how much)
- IP theft prevention (detect extraction vs legitimate usage)
- Compliance audit trail (SOC 2 / ISO 27001 readiness)
- Protection of humans (detect burnout patterns, role confusion)

## 2. Three Capabilities

### 2A. Per-User Budget ACL

Every MCP tool call passes through budget check:

```
User → MCP Tool → Budget Check → Router → Execute
                      ↓
                  Over budget? → BLOCKED + notify admin
```

- Daily/weekly/monthly caps per user
- Per-workspace budget isolation (company A's spend doesn't affect company B)
- Budget inheritance: workspace default → team override → user override
- Real-time spend dashboard in Observatory TUI

### 2B. Anomaly Detection (Event Router pattern)

New pattern detector in the Event Router alongside `stuck_agent` and `repeat_failure`:

```swift
case .security(SecurityAnomaly)

enum SecurityAnomaly {
    case bulkExtraction    // 100+ queries in 5 min (normal: 12/hour)
    case crossProjectScan  // user accessing 5+ projects they don't own
    case offHoursAccess    // queries at 3AM from user who works 9-5
    case exportPattern     // sequential scan of all memories in a project
}
```

Actions:
- `bulkExtraction` → auto-block + alert CODIR
- `crossProjectScan` → alert manager + log
- `offHoursAccess` → log only (might be legitimate crunch)
- `exportPattern` → throttle + alert CODIR

### 2C. Audit Trail

Every MCP tool call logged with 5W1H:

| Field | Source |
|-------|--------|
| **Who** | User ID from auth token / API key |
| **What** | Tool name + parameters |
| **Where** | Project scope, workspace |
| **When** | Timestamp (ISO 8601) |
| **Why** | Inferred from context (search query, task in progress) |
| **How** | MCP tool call chain, session ID |

Query endpoint:
```
GET /api/audit?user=bob&since=2026-03-01&project=maya
```

Report generator:
```
shiki audit --user bob --since 2026-03-01 --format pdf
```

## 3. What to Build Now (Architecture Prep)

Even before multi-user, add these fields:

1. **`userId` on every ShikiEvent** — default "local" for single-user
2. **Budget fields in MCP tool schema** — `dailyCapUsd`, `spentTodayUsd` per session
3. **Security pattern detector stub** in Event Router — ready to activate
4. **Audit log table** in DB schema — `audit_events` with user, tool, params, timestamp

## 4. Enterprise Pricing Lever

| Tier | Budget | Anomaly | Audit |
|------|--------|---------|-------|
| Free / Solo | Global budget only | None | None |
| Team | Per-user budget | Basic alerts | 30-day log |
| Enterprise | Per-user + per-project | Full detection + auto-block | Unlimited + export + CODIR alerts |

## 5. Human Safety Layer

Beyond cybersecurity — organizational health signals:

- **Burnout detection**: budget burn at midnight, 16h continuous usage
- **Role confusion**: accessing projects outside assigned scope
- **Knowledge hoarding**: one user becomes single point of failure

Shiki surfaces signals. Humans decide meaning. Never automated HR decisions.

## 6. Deliverables (when multi-user is built)

- `BudgetACL` service — per-user caps, workspace isolation
- `SecurityPatternDetector` — Event Router pattern (anomaly detection)
- `AuditLogger` — MCP middleware logging all tool calls
- `shiki audit` command — query + report generation
- `AnomalyAlert` — CODIR notification via ntfy/email
- DB: `audit_events`, `user_budgets`, `security_incidents` tables

## 7. Key Decision

**Shiki doesn't make security decisions. Shiki makes security visible.**

The system detects, logs, and alerts. Humans investigate and act. No automated blocking without human-defined rules. The default is transparency, not restriction.
