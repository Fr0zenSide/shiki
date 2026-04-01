# Radar: Appsmith vs NocoDB vs Grafana — Dashboard/Monitoring for Shikki

> **Date**: 2026-04-01
> **Type**: /radar — Tool Evaluation
> **Author**: @Sensei (CTO agent)
> **Status**: Complete
> **Decision**: See Section 7

---

## 1. Executive Summary

Shikki needs operational visibility into its orchestrator: health checks, agent status, test results, dispatch state, sessions. Three external tools evaluated (Appsmith, NocoDB, Grafana) plus the existing TUI approach (Observatory). **Recommendation: Grafana for monitoring, NocoDB as optional DB inspector, keep TUI as primary interface.** Appsmith is overkill.

---

## 2. Tool Profiles

### 2.1 Appsmith

| Attribute | Detail |
|-----------|--------|
| **What** | Low-code platform for building internal tools, admin panels, dashboards |
| **Stars** | 39.5k |
| **License** | Apache-2.0 (Community Edition). Enterprise features gated behind $15/user/mo or $2,500/mo |
| **Language** | TypeScript (client), Java/Spring WebFlux (server) |
| **Internal deps** | MongoDB + Redis + Nginx (bundled in Docker image) |
| **Self-hosted** | Docker (single image bundles everything). Ports 80/443 |
| **Resource footprint** | **Heavy**. Java + MongoDB + Redis in one container. Expect 1-2 GB RAM minimum |
| **Data connectors** | 25+ databases (PostgreSQL, MySQL, MongoDB, MSSQL, Oracle, Elasticsearch, Redis, DynamoDB, Redshift, Snowflake, etc.) + REST API + GraphQL + 30+ SaaS integrations |
| **PocketBase support** | No native connector, but REST API connector covers it |
| **AI features** | "Appsmith Agents" — connect LLMs (OpenAI, Anthropic, Google) to private data. AI actions for text analysis, classification. "Appy" copilot for coding help |
| **Auth** | Google SSO free. SAML/OIDC/SCIM on Enterprise plan only |
| **Key strength** | Full app builder. Drag-drop widgets, JS logic, workflows, version control |
| **Key weakness** | Massive footprint for what we need. It's a platform, not a dashboard tool |

### 2.2 NocoDB

| Attribute | Detail |
|-----------|--------|
| **What** | Airtable alternative — spreadsheet UI on top of databases |
| **Stars** | 62.6k |
| **License** | **Sustainable Use License** (NOT AGPL/open-source). Internal/non-commercial use OK, cannot redistribute commercially. NOT the same as Shikki's AGPL |
| **Language** | TypeScript (full stack, Node.js backend) |
| **Internal deps** | PostgreSQL or SQLite for its own metadata |
| **Self-hosted** | Docker (NocoDB container + optional PG container). Port 8080 |
| **Resource footprint** | **Light-medium**. Node.js app + PG. ~256-512 MB RAM |
| **External DB support** | PostgreSQL and MySQL. Can connect to existing databases with existing tables |
| **Auto-discovery** | Yes — connects to PG, discovers tables/columns, presents as spreadsheet views |
| **Views** | Grid, Kanban, Gallery, Form, Calendar, ERD diagram |
| **API** | REST API (v2/v3) + SDK. JWT auth. Webhooks for automation |
| **AI features** | None |
| **Auth** | JWT, social auth |
| **Key strength** | Instant spreadsheet UI on any PostgreSQL. Zero code. Great for "see into the DB" |
| **Key weakness** | Not a dashboard builder. No charts, gauges, or real-time monitoring. Just data tables |

### 2.3 Grafana (comparison baseline)

| Attribute | Detail |
|-----------|--------|
| **What** | Observability/monitoring platform. Dashboards, alerts, metrics visualization |
| **Stars** | 67k+ |
| **License** | AGPL-3.0 (OSS) / Apache-2.0 (Enterprise). Same license family as Shikki |
| **Language** | Go (backend), TypeScript (frontend) |
| **Internal deps** | None required (embedded SQLite). Optional: PostgreSQL/MySQL for HA |
| **Self-hosted** | Single Docker container. Alpine-based. Port 3000 |
| **Resource footprint** | **Very light**. Single Go binary + SQLite. ~128-256 MB RAM |
| **Data sources** | PostgreSQL, MySQL, Prometheus, Loki, Elasticsearch, InfluxDB, CloudWatch, 100+ via plugins |
| **Real-time** | Yes — Grafana Live, auto-refresh, streaming |
| **Alerting** | Built-in alert rules, multi-channel notification (Slack, email, webhook, **ntfy**) |
| **Visualization** | Gauges, time series, stat panels, status history, tables, heatmaps, logs, traces |
| **AI features** | Grafana AI/ML for anomaly detection (Enterprise), SLO assistant |
| **Auth** | Built-in auth, LDAP, OAuth2, SAML (Enterprise) |
| **Key strength** | Purpose-built for exactly what Shikki needs: monitoring, status, health, alerting |
| **Key weakness** | Not an app builder. Read-only visualization (no CRUD). Query-oriented |

---

## 3. Shikki Dashboard Requirements Matrix

| Requirement | Appsmith | NocoDB | Grafana | TUI (Observatory) |
|-------------|----------|--------|---------|-------------------|
| **Health check (kernel, NATS, DB, backend, Docker)** | Build custom | No | Native (SQL + health endpoints) | Existing `DashboardRenderer` |
| **Agent status (running, idle, stalled)** | Build custom | Table view only | Native (status panels, gauges) | Observatory Layer 3 |
| **Test results history** | Build custom | Table + filter views | Native (time series, tables) | CLI output |
| **Dispatch state (waves, branches, progress)** | Build custom | Kanban view fits waves | Custom panels | Observatory Layer 2 |
| **Session overview** | Build custom | Table view | Native (logs panel) | Decision Journal |
| **Real-time updates** | WebSocket polling | No streaming | Native (Grafana Live) | Terminal refresh |
| **Alerting** | Custom JS | Webhooks (limited) | Native + ntfy integration | ntfy (existing) |
| **Mobile access** | Responsive web | Responsive web | Grafana mobile app exists | SSH + tmux |
| **Setup effort** | Days (build each view) | Hours (connect DB, done) | Hours (connect PG, build panels) | Already built |
| **Maintenance** | High (Java/MongoDB stack) | Low (Node.js) | Very low (single binary) | Zero (compiled in) |
| **Resource cost** | 1-2 GB RAM | 256-512 MB RAM | 128-256 MB RAM | 0 (runs in Shikki) |

---

## 4. Detailed Analysis

### 4.1 Appsmith — Verdict: PASS

**Why not**: Appsmith solves a different problem. It's a platform for building full CRUD internal tools — think "admin panel where support agents edit orders." Shikki needs read-only monitoring dashboards, not form-based data entry.

The cost-benefit is terrible:
- **Footprint**: Java + MongoDB + Redis = 1-2 GB RAM for a monitoring dashboard
- **Build effort**: Every panel is drag-drop + custom queries + JS glue code. It's faster than raw HTML but slower than Grafana for dashboards
- **Maintenance**: MongoDB dependency adds operational burden
- **AI features**: Impressive but irrelevant. LLM-powered text analysis is not what we need for system monitoring

Appsmith would make sense if Shikki needed a customer-facing admin panel or a multi-user tool with forms, RBAC, and workflows. For monitoring, it's a 747 when we need a bicycle.

### 4.2 NocoDB — Verdict: USEFUL AS DB INSPECTOR, NOT AS DASHBOARD

**What it does well**: Connect to ShikiDB (PostgreSQL), auto-discover all tables (`agent_events`, `memories`, `decisions`, `plans`, `reports`), present them as filterable/sortable spreadsheets. Kanban view could visualize dispatch waves by status column. Calendar view could show session history by date.

**What it doesn't do**: Charts, gauges, health indicators, real-time status, alerting. It's a spreadsheet, not a dashboard.

**License concern**: "Sustainable Use License" is NOT open source. It allows internal business use and non-commercial distribution, but cannot be redistributed commercially. This is fine for internal tooling but philosophically misaligned with Shikki's AGPL stance. NocoDB used to be MIT, then moved to this custom license. This is the BSL/SSPL pattern that erodes open-source trust.

**Best use case**: Quick "see into the DB" tool during development. Point it at ShikiDB, browse `agent_events`, filter by agent, sort by timestamp. Faster than `psql` for ad-hoc exploration. Not a production component.

**Docker setup** (if wanted):
```yaml
# docker-compose.nocodb.yml — dev-only DB inspector
services:
  nocodb:
    image: nocodb/nocodb:latest
    environment:
      NC_DB: "pg://host.docker.internal:5432?u=shiki&p=xxx&d=shikidb"
    ports:
      - "8090:8080"
    volumes:
      - nc_data:/usr/app/data
volumes:
  nc_data: {}
```

### 4.3 Grafana — Verdict: STRONG FIT FOR MONITORING LAYER

Grafana is purpose-built for exactly what Shikki needs:

1. **Health checks**: SQL query against ShikiDB → stat panel showing UP/DOWN for each component. Or HTTP health endpoint → uptime panel
2. **Agent status**: Query `agent_events` table → status history panel showing running/idle/stalled per agent over time
3. **Test results**: Query test event data → time series of pass/fail rates, table of recent runs
4. **Dispatch state**: Query dispatch/wave tables → stat panels per wave, progress bars via gauge panels
5. **Sessions**: Query session events → logs panel with timeline, filterable by agent/company

**Key advantages for Shikki**:
- **AGPL-3.0 license** — same license family. No philosophical conflict
- **128 MB RAM** — runs on anything. Single Alpine container
- **PostgreSQL native** — direct connection to ShikiDB, no middleware
- **ntfy integration** — Grafana alerts can fire to ntfy endpoints. Connects to existing remote approval system
- **No code to maintain** — dashboards are JSON configs, version-controllable
- **Embedable panels** — individual panels can be embedded as iframes if we ever want web views
- **Plugin ecosystem** — 100+ data source plugins if we add Prometheus/NATS monitoring later

**Setup would be**:
```yaml
# docker-compose.grafana.yml — monitoring dashboard
services:
  grafana:
    image: grafana/grafana-oss:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: shikki
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
volumes:
  grafana_data: {}
```

Then provision a PostgreSQL data source pointing at ShikiDB, build dashboard panels with SQL queries.

---

## 5. The TUI vs Web Dashboard Question

> "The competitive radar said 'No web dashboard — TUI is the differentiator.' But for MONITORING (not building), a web view makes sense."

This is the correct distinction. Two separate concerns:

| Concern | Interface | Tool |
|---------|-----------|------|
| **Operating** Shikki (dispatch, spec, ship, review) | TUI | Observatory + existing CLI |
| **Monitoring** Shikki (is it healthy? what happened?) | Web | Grafana |

The TUI is the **control plane** — where you give commands and see live output. The web dashboard is the **observation plane** — where you check health, review history, spot trends.

These are complementary, not competing. Grafana for monitoring does NOT replace the TUI for operating. Just like a pilot has instruments (monitoring) AND a yoke (control).

**Important**: Grafana should be opt-in for operators who want web-based monitoring. The TUI remains the primary and only required interface. Grafana is a "nice to have" that takes 30 minutes to set up if someone wants it.

---

## 6. Comparison Summary

| Criterion | Appsmith | NocoDB | Grafana | TUI (current) |
|-----------|----------|--------|---------|---------------|
| **Fit for Shikki monitoring** | Poor | Partial | Excellent | Good |
| **Setup effort** | Days | 30 min | 1-2 hours | Already done |
| **Resource cost** | 1-2 GB | 256 MB | 128 MB | 0 |
| **Maintenance burden** | High | Low | Very low | Zero |
| **License alignment** | Apache-2.0 (ok) | Sustainable Use (concern) | AGPL-3.0 (perfect) | N/A |
| **Real-time monitoring** | Manual build | No | Native | Terminal refresh |
| **Alerting** | Manual build | Basic webhooks | Native + ntfy | ntfy (existing) |
| **PostgreSQL support** | Yes (connector) | Yes (external DB) | Yes (data source) | Via ShikiKit |
| **Charts/gauges** | Build yourself | No | 50+ panel types | ASCII art possible |
| **Mobile access** | Responsive web | Responsive web | Mobile app + responsive | SSH only |
| **Would user actually use it?** | Unlikely (too heavy) | For DB browsing, yes | For monitoring, yes | Daily driver |

---

## 7. Recommendation

### Tier 1 — Keep (already done)
**Observatory TUI** remains the primary interface. Already built (Layers 1-3 shipped on `feature/observatory`). This is the differentiator. No change.

### Tier 2 — Add when needed (P3, 1-2 hours)
**Grafana** as optional monitoring dashboard. Deploy when Shikki runs long-lived sessions or multi-agent orchestration where web-based monitoring adds value. Setup:
1. Add `docker-compose.grafana.yml` to repo
2. Provision PostgreSQL data source (ShikiDB)
3. Build 4-5 dashboard panels (health, agents, tests, dispatch, sessions)
4. Configure ntfy alert channel
5. Total: ~2 hours, then zero maintenance

### Tier 3 — Dev-only tool (not committed)
**NocoDB** as ad-hoc DB inspector. Don't commit to repo. Keep in personal `docker-compose.override.yml` for when you want to browse ShikiDB tables in a spreadsheet UI. 30-second setup.

### Tier 4 — Skip entirely
**Appsmith**. Wrong tool for the job. Revisit only if Shikki ever needs a full customer-facing admin panel (unlikely given native-first philosophy).

---

## 8. Action Items

| # | Action | Priority | Effort |
|---|--------|----------|--------|
| 1 | Continue Observatory TUI as primary interface | P0 (done) | 0 |
| 2 | Create `docker-compose.grafana.yml` template | P3 | 30 min |
| 3 | Build Grafana dashboard JSON (provisioned) for 5 core panels | P3 | 1-2 hrs |
| 4 | Wire Grafana alerts to ntfy `shiki` topic | P3 | 15 min |
| 5 | Document NocoDB one-liner for dev DB inspection | P4 | 5 min |
| 6 | Skip Appsmith | - | - |

**Not now**: None of the Grafana work is blocking. The TUI handles current needs. Grafana becomes valuable when Shikki runs multi-company orchestration in long-lived sessions (post-ShikiCore Wave 5).

---

## 9. Risk Notes

- **NocoDB license drift**: Was MIT, now "Sustainable Use License." If the pattern continues, features may get further restricted. Do not build dependencies on NocoDB.
- **Appsmith Enterprise creep**: Core is Apache-2.0 but useful features (SSO, audit logs, environments) are Enterprise-only ($15/user/mo). Common open-core bait-and-switch pattern.
- **Grafana AGPL**: Perfect alignment with Shikki's license. No restrictions for self-hosted internal use. Only matters if embedding in proprietary SaaS (which Shikki is not).
- **Dashboard maintenance**: Even Grafana dashboards need updates when DB schema changes. Keep dashboards provisioned from JSON files in the repo so they version-control with the schema.
